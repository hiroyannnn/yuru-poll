///|
/// 発言の最大文字数。これを超えたら 413。
pub const MAX_COMMENT_CHARS : Int = 200

///|
/// poll JSON の最大文字数。
pub const MAX_POLL_CHARS : Int = 16000

///|
/// 1 ルームの参加者数の上限。超えたら新しい参加者は 429。
pub const MAX_PARTICIPANTS : Int = 2000

///|
/// 同じ参加者が次に発言できるまでの最短間隔（ミリ秒）。
pub const MIN_INTERVAL_PER_PARTICIPANT_MS : Int64 = 2000

///|
/// 同じ接続元（IP）からの 1 分あたりの発言数の上限。参加者 ID を変えた連投を止める。
pub const MAX_COMMENTS_PER_CLIENT_PER_MINUTE : Int = 20

///|
/// 1 ルーム全体での 1 分あたりの判定数の上限。判定 API の費用の歯止め。
pub const MAX_JUDGEMENTS_PER_ROOM_PER_MINUTE : Int = 300

///|
/// 1 リクエスト分の文脈。JS グルーが Workers の API から集めて渡す。
pub(all) struct Context {
  /// 参加用 URL（QR に使う）
  join_url : String
  /// 判定リクエストに載せるモデル名。空なら既定値
  model : String
  /// 現在時刻（UNIX ミリ秒）
  now_ms : Int64
  /// 接続元の識別子（IP アドレス）
  client : String
  /// リクエストに付いてきた司会者トークン。作成時は新しく発行したトークン
  token : String
}

///|
/// 1 ルーム分の状態。Cloudflare では Durable Object 1 個が 1 つ持つ。
pub struct Room {
  mut engine : @lib.Engine?
  mut last : @lib.Update?
  /// 司会者だけが知るトークン。空なら司会者操作は誰にもできない
  mut host_token : String
  by_participant : @lib.RateLimiter
  by_client : @lib.RateLimiter
  whole_room : @lib.RateLimiter
}

///|
/// JS グルーに返す応答。
pub struct Reply {
  status : Int
  content_type : String
  body : String
  /// あれば、グルーが永続ストレージに保存する
  state : String?
  /// true なら、グルーがルームのストレージを消す
  closed : Bool
  /// 利用者には見せない詳細。グルーがログに出す
  log : String?
}

///|
const JSON_TYPE : String = "application/json; charset=utf-8"

///|
pub fn room_new() -> Room {
  {
    engine: None,
    last: None,
    host_token: "",
    by_participant: @lib.RateLimiter::new(
      limit=1,
      window_ms=MIN_INTERVAL_PER_PARTICIPANT_MS,
    ),
    by_client: @lib.RateLimiter::new(
      limit=MAX_COMMENTS_PER_CLIENT_PER_MINUTE,
      window_ms=60000,
    ),
    whole_room: @lib.RateLimiter::new(
      limit=MAX_JUDGEMENTS_PER_ROOM_PER_MINUTE,
      window_ms=60000,
    ),
  }
}

///|
/// 保存してあった state からルームを復元する。成功なら空文字、失敗ならエラー文を返す。
/// 新形式は `{"engine": <Engine の dump>, "host_token": "..."}`。
/// 司会者トークン導入前の形式（Engine の dump そのもの）も読める。
pub fn room_restore(room : Room, state : String) -> String {
  let json = @json.parse(state) catch {
    _ => return "state を復元できません: InvalidJson"
  }
  let (engine_json, host_token) = match json {
    Object({ "engine": engine_json, "host_token": String(token), .. }) =>
      (engine_json, token)
    _ => (json, "")
  }
  room.engine = Some(
    @lib.Engine::restore(engine_json) catch {
      err => return "state を復元できません: \{@debug.to_string(err)}"
    },
  )
  room.host_token = host_token
  room.last = None
  ""
}

///|
fn Room::state_text(self : Room, engine : @lib.Engine) -> String {
  let json : Json = { "engine": engine.dump(), "host_token": self.host_token }
  json.stringify()
}

///|
pub fn Reply::to_json_text(self : Reply) -> String {
  let optional = (value : String?) => {
    match value {
      Some(s) => Json::string(s)
      None => Json::null()
    }
  }
  let json : Json = {
    "status": self.status,
    "content_type": self.content_type,
    "body": self.body,
    "state": optional(self.state),
    "closed": self.closed,
    "log": optional(self.log),
  }
  json.stringify()
}

///|
fn ok(json : Json, state? : String) -> Reply {
  {
    status: 200,
    content_type: JSON_TYPE,
    body: json.stringify(),
    state,
    closed: false,
    log: None,
  }
}

///|
fn failure(status : Int, message : String, log? : String) -> Reply {
  let json : Json = { "error": message }
  {
    status,
    content_type: JSON_TYPE,
    body: json.stringify(),
    state: None,
    closed: false,
    log,
  }
}

///|
/// ルーム内の API を処理する。パスは native 版のウェブサーバと同じ（`/api/poll` など）。
/// `judge` は判定リクエストの JSON を受け取り、レスポンスの JSON を返す（差し替え可能）。
pub async fn route(
  room : Room,
  meth : String,
  path : String,
  body : String,
  judge : async (String) -> String,
  ctx : Context,
) -> Reply {
  if meth == "POST" && path == "/api/room" {
    return create_room(room, body, ctx)
  }
  guard room.engine is Some(engine) else {
    return failure(404, "このルームはありません")
  }
  match (meth, path) {
    ("GET", "/api/poll") => ok(ToJson::to_json(engine.poll))
    ("GET", "/api/tally") => ok(tally_json(room, engine))
    ("GET", "/api/join-url") =>
      ok({ "url": ctx.join_url, "accept_comments": true })
    ("GET", "/api/qr.svg") =>
      match @lib.qr_svg(ctx.join_url) {
        Some(svg) =>
          {
            status: 200,
            content_type: "image/svg+xml",
            body: svg,
            state: None,
            closed: false,
            log: None,
          }
        None => failure(500, "QR を生成できません")
      }
    ("POST", "/api/comment") => comment(room, engine, body, judge, ctx)
    ("GET", "/api/history") | ("POST", "/api/reset") | ("POST", "/api/close") =>
      host_only(room, engine, path, ctx)
    _ => failure(404, "not found")
  }
}

///|
/// 司会者トークンが要る操作。
fn host_only(
  room : Room,
  engine : @lib.Engine,
  path : String,
  ctx : Context,
) -> Reply {
  if room.host_token.is_empty() || ctx.token != room.host_token {
    return failure(401, "司会者用のリンクから開いてください")
  }
  match path {
    "/api/history" => ok({ "history": ToJson::to_json(engine.history()) })
    "/api/reset" => {
      engine.reset()
      room.last = None
      ok(tally_json(room, engine), state=room.state_text(engine))
    }
    _ => {
      // /api/close
      room.engine = None
      room.last = None
      room.host_token = ""
      { ..ok({ "closed": true }), closed: true, }
    }
  }
}

///|
fn create_room(room : Room, body : String, ctx : Context) -> Reply {
  if room.engine is Some(_) {
    return failure(409, "このルームは既に作られています")
  }
  if body.length() > MAX_POLL_CHARS {
    return failure(413, "poll が大きすぎます")
  }
  let poll = @lib.Poll::parse(body) catch {
    err =>
      return failure(400, "poll を読めません: \{@debug.to_string(err)}")
  }
  let engine = @lib.Engine::new(poll)
  room.engine = Some(engine)
  room.host_token = ctx.token
  ok(ToJson::to_json(poll), state=room.state_text(engine))
}

///|
fn tally_json(room : Room, engine : @lib.Engine) -> Json {
  let last : Json = match room.last {
    Some(update) =>
      {
        "comment": ToJson::to_json(update.comment),
        "judgement": ToJson::to_json(update.judgement),
      }
    None => Json::null()
  }
  { "snapshot": ToJson::to_json(engine.snapshot()), "last": last }
}

///|
async fn comment(
  room : Room,
  engine : @lib.Engine,
  body : String,
  judge : async (String) -> String,
  ctx : Context,
) -> Reply {
  let json = @json.parse(body) catch {
    _ => return failure(400, "JSON が不正です")
  }
  guard json
    is Object(
      { "participant_id": String(participant_id), "comment": String(raw), .. }
    ) else {
    return failure(400, "participant_id と comment が必要です")
  }
  let text = raw.trim(chars=" \t\r\n").to_owned()
  if text.is_empty() || participant_id.is_empty() {
    return failure(400, "発言が空です")
  }
  if text.length() > MAX_COMMENT_CHARS || participant_id.length() > 64 {
    return failure(
      413,
      "発言が長すぎます（\{MAX_COMMENT_CHARS} 文字まで）",
    )
  }
  let id = @lib.participant_id("web", participant_id)
  if engine.tally.latest(id) is None &&
    engine.snapshot().participants >= MAX_PARTICIPANTS {
    return failure(429, "このルームは満員です")
  }
  // 判定は費用がかかるので、呼ぶ前に制限を確かめる
  if !room.by_client.allow(ctx.client, ctx.now_ms) ||
    !room.by_participant.allow(id, ctx.now_ms) ||
    !room.whole_room.allow("room", ctx.now_ms) {
    return failure(
      429, "少し待ってからもう一度送ってください",
    )
  }
  // 空ならコアの既定値（jev-latest）を使う
  let request_json = if ctx.model.is_empty() {
    @lib.build_request(engine.poll, text)
  } else {
    @lib.build_request(engine.poll, text, model=ctx.model)
  }
  let judge_failed = "判定に失敗しました。少し待ってからもう一度送ってください"
  let response = judge(request_json.stringify()) catch {
    err => return failure(502, judge_failed, log="judge: \{err}")
  }
  let judgement = @lib.parse_response_text(response) catch {
    err =>
      return failure(
        502,
        judge_failed,
        log="judge response: \{@debug.to_string(err)}",
      )
  }
  let update = engine.apply(
    { participant_id: id, text, at: ctx.now_ms, },
    judgement,
  )
  room.last = Some(update)
  ok(
    {
      "judgement": ToJson::to_json(update.judgement),
      "snapshot": ToJson::to_json(update.snapshot),
    },
    state=room.state_text(engine),
  )
}
