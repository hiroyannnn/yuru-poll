// Cloudflare Workers 用のグルー。
// ルーティング・判定の await・集計・保存用 state の生成は MoonBit（worker パッケージ）が行い、
// ここは「Workers の API を MoonBit に渡す」だけの薄い層にする。
import { DurableObject } from 'cloudflare:workers';

const MAX_BODY_BYTES = 20_000;
const ROOM_TTL_MS = 24 * 60 * 60 * 1000; // 最後の更新から 24 時間でルームを消す
const ROOMS_PER_CLIENT_PER_HOUR = 10;
const JUDGE_TIMEOUT_MS = 15_000; // 判定 API が応答しないとき、参加者を待たせ続けない
const ROOM_ID = /^[a-z0-9]{6,32}$/;
const PAGES = { '': '/index.html', '/join': '/join.html', '/overlay': '/overlay.html' };

// MoonBit のコアはモジュール初期化時にハッシュ用の乱数シードを作る。Workers はグローバルスコープでの
// 乱数生成を禁止しているので、リクエスト（または Durable Object の初期化）の中で遅延 import する。
let moonbitModule;
async function moonbit() {
  moonbitModule ??= await import('../../_build/js/release/build/worker/worker.js');
  return moonbitModule;
}

// 判定関数。リクエスト JSON（文字列）を受け取り、レスポンス JSON（文字列）を返す。
// JEV_URL があれば TypeSafe 互換の HTTP API を使う（ローカルの open-jev、TypeSafe 公式、
// Vercel AI Gateway の https://ai-gateway.vercel.sh/typesafe など）。無ければ Workers AI の Jev を使う。
function makeJudge(env) {
  return async (requestJson) => {
    if (env.JEV_URL) {
      const res = await fetch(`${env.JEV_URL.replace(/\/$/, '')}/v1/systemone`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${env.JEV_API_KEY ?? 'local'}` },
        body: requestJson,
        signal: AbortSignal.timeout(JUDGE_TIMEOUT_MS),
      });
      if (!res.ok) throw new Error(`Jev HTTP ${res.status}`);
      return await res.text();
    }
    if (!env.AI) throw new Error('JEV_URL も AI バインディングも設定されていません');
    const { state, questions } = JSON.parse(requestJson);
    const timeout = new Promise((_, reject) => setTimeout(() => reject(new Error('Jev timeout')), JUDGE_TIMEOUT_MS));
    return JSON.stringify(await Promise.race([env.AI.run('typesafe/jev', { state, questions }), timeout]));
  };
}

function json(body, status = 200) {
  return Response.json(body, { status, headers: { 'Cache-Control': 'no-store' } });
}

function randomId(length) {
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  return Array.from(bytes, (b) => (b % 36).toString(36)).join('');
}

function clientOf(request) {
  return request.headers.get('CF-Connecting-IP') ?? 'unknown';
}

function bearerOf(request) {
  const header = request.headers.get('Authorization') ?? '';
  return header.startsWith('Bearer ') ? header.slice(7) : '';
}

async function readBody(request) {
  if (request.method !== 'POST') return '';
  const text = await request.text();
  if (text.length > MAX_BODY_BYTES) throw new RangeError('body too large');
  return text;
}

// 1 ルーム = 1 Durable Object。集計はメモリ上の MoonBit の Room が持ち、
// 変更のたびに MoonBit が返す state をストレージへ保存して、休止からの復帰時に復元する。
export class RoomDO extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.judge = makeJudge(env);
    ctx.blockConcurrencyWhile(async () => {
      this.mbt = await moonbit();
      this.room = this.mbt.room_new();
      const state = await ctx.storage.get('state');
      if (state) {
        const error = this.mbt.room_restore(this.room, state);
        if (error) console.error(error);
      }
    });
  }

  async fetch(request) {
    const url = new URL(request.url);
    let body;
    try {
      body = await readBody(request);
    } catch {
      return json({ error: 'リクエストが大きすぎます' }, 413);
    }
    const reply = JSON.parse(
      await this.mbt.room_handle(
        this.room,
        request.method,
        url.pathname,
        body,
        request.headers.get('x-yuru-join-url') ?? '',
        this.env.JEV_MODEL ?? '', // 空なら MoonBit 側の既定値（jev-latest）
        Date.now(),
        request.headers.get('x-yuru-client') ?? 'unknown',
        request.headers.get('x-yuru-token') ?? '',
        this.judge,
      ),
    );
    if (reply.log) console.error(reply.log);
    if (reply.closed) {
      await this.ctx.storage.deleteAll();
    } else if (reply.state) {
      await this.ctx.storage.put('state', reply.state);
      await this.ctx.storage.setAlarm(Date.now() + ROOM_TTL_MS);
    }
    return new Response(reply.body, {
      status: reply.status,
      headers: { 'Content-Type': reply.content_type, 'Cache-Control': 'no-store' },
    });
  }

  // 最後の更新から ROOM_TTL_MS 経ったらルームを消す
  async alarm() {
    await this.ctx.storage.deleteAll();
    this.room = this.mbt.room_new();
  }
}

// ルーム作成の回数制限。全体で 1 個だけ使い、接続元ごとに数える（数え方は MoonBit の RateLimiter）。
export class GateDO extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.mbt = await moonbit();
      this.limiter = this.mbt.limiter_new(ROOMS_PER_CLIENT_PER_HOUR, 60 * 60 * 1000);
    });
  }

  async fetch(request) {
    const allowed = this.mbt.limiter_allow(this.limiter, clientOf(request), Date.now());
    return json({ allowed }, allowed ? 200 : 429);
  }
}

function roomStub(env, id) {
  return env.ROOMS.get(env.ROOMS.idFromName(id));
}

// 利用者が偽装できないよう、内部用ヘッダは必ずここで上書きする
function toRoom(env, id, request, url, apiPath, body, token = bearerOf(request)) {
  const headers = new Headers(request.headers);
  headers.set('x-yuru-join-url', `${url.origin}/r/${id}/join`);
  headers.set('x-yuru-client', clientOf(request));
  headers.set('x-yuru-token', token);
  return roomStub(env, id).fetch(new Request(`${url.origin}${apiPath}`, { method: request.method, headers, body }));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/$/, '') || '/';

    if (request.method === 'GET' && path === '/') {
      return env.ASSETS.fetch(new Request(`${url.origin}/new.html`));
    }

    // ルーム作成: 本文は poll JSON。ID を振って Durable Object に作らせる。
    if (request.method === 'POST' && path === '/api/rooms') {
      let body;
      try {
        body = await readBody(request);
      } catch {
        return json({ error: 'リクエストが大きすぎます' }, 413);
      }
      const gate = await env.GATE.get(env.GATE.idFromName('gate')).fetch(
        new Request(`${url.origin}/allow`, { headers: request.headers }),
      );
      if (!gate.ok) return json({ error: 'ルームを作りすぎです。しばらく待ってからもう一度試してください' }, 429);
      const id = randomId(8);
      const hostToken = randomId(24);
      const created = await toRoom(env, id, request, url, '/api/room', body, hostToken);
      if (!created.ok) return created;
      return json({
        room: id,
        // 司会者トークンは URL のフラグメントに置く（サーバのログやリファラに残らない）
        host_url: `${url.origin}/r/${id}#host=${hostToken}`,
        join_url: `${url.origin}/r/${id}/join`,
        overlay_url: `${url.origin}/r/${id}/overlay`,
      });
    }

    const match = path.match(/^\/r\/([^/]+)(\/.*)?$/);
    if (match && ROOM_ID.test(match[1])) {
      const [, id, rest = ''] = match;
      if (request.method === 'GET' && rest in PAGES) {
        return env.ASSETS.fetch(new Request(`${url.origin}${PAGES[rest]}`));
      }
      if (rest.startsWith('/api/') && rest !== '/api/room') {
        return toRoom(env, id, request, url, rest, request.method === 'POST' ? request.body : undefined);
      }
    }
    if (request.method === 'GET' && path === '/favicon.ico') return new Response(null, { status: 204 });
    return json({ error: 'not found' }, 404);
  },
};
