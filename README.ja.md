# yuru-poll — ゆるアンケート

[English README](README.mbt.md)

参加者は選択肢を選ばず、「たぶんA」「Bはないわ」「うーん迷う」と自由に発言するだけ。
発言を TypeSafe Jev 互換 API（`POST /v1/systemone` の choice 質問）に投げて、
定義済み選択肢への**確率分布**を得て、それを「小数票」としてそのまま集計します。

- **ゆるく答えられる**: 選択肢を選ばなくていい
- **ゆるく数える**: 確率のまま小数で合計する（例: Factorio 12.4 票）
- **ゆるく捨てる**: 「どれでもない」（`none`）を常に選択肢に混ぜ、雑談を集計から外す
- **ゆるく直せる**: 同じ参加者の最新発言で上書き（1 人 1 分布）

## 構成: 入口（Source）× 出口（Sink）

発言の入口と集計の出口は独立したアダプタで、組み合わせは CLI フラグで選びます。
1 つのエンジンに複数の Source と複数の Sink を同時接続できます。

```
Source                      Engine                          Sink
  stdin   ─┐                                             ┌─ terminal（棒グラフ）
  web     ─┼─ submit ─▶ 判定（Jev）─▶ Tally ─▶ Update ─▶ ┼─ web（司会者画面 / OBS オーバーレイ）
  youtube ─┤   （直列化）                                 └─（将来: CSV/JSON, Slack）
  twitch  ─┘
```

| パッケージ | 役割 | ターゲット |
| --- | --- | --- |
| `lib/` | Poll、リクエスト/レスポンス、Tally、Engine、発言履歴、レート制限器、QR、Source/Sink trait、各種パース、描画（純粋） | all |
| `runtime/` | 全 Source を同時に走らせ、注入した判定関数で直列に判定して Engine へ流す | native |
| `jev/` | Jev HTTP クライアント（`JEV_URL` / `JEV_API_KEY`） | native |
| `adapters/stdin` `adapters/twitch` `adapters/youtube` | Source | native |
| `adapters/terminal` | Sink | native |
| `adapters/web` | Source（参加フォーム）兼 Sink（司会者画面・OBS オーバーレイ） | native |
| `cmd/yuru-poll` | Source と Sink の組み合わせを CLI フラグで選ぶだけの薄い層 | native |
| `worker/` | ホスト版のルーム API。native 版のウェブサーバと同じ API を、ルーム単位で処理する | js |
| `cloudflare/` | Cloudflare Workers 用の薄い JS グルーと wrangler 設定 | - |

## セットアップ

```bash
moon check --target all      # 型チェック
moon test --target all       # コアは wasm / wasm-gc / js / native、native 限定パッケージは native のみ
moon build --target native
```

判定サーバは TypeSafe Jev、またはローカルの [open-jev](https://github.com/daseinlabs/open-jev) を使います。

```bash
export JEV_URL=http://127.0.0.1:8000   # 既定値
export JEV_API_KEY=local               # 既定値（Authorization: Bearer <key>）
export JEV_MODEL=jev-latest            # 既定値。リクエストに載せるモデル名
curl -s $JEV_URL/health
```

Vercel AI Gateway の Jev を使う場合は、TypeSafe 互換のエンドポイントに向けます（キーは AI Gateway の API キー）。

```bash
export JEV_URL=https://ai-gateway.vercel.sh/typesafe
export JEV_MODEL=typesafe-ai/jev
export JEV_API_KEY=<AI Gateway の API キー>
```

## 使い方

```bash
moon run --target native cmd/yuru-poll -- --poll polls/next-game.json --source stdin --sink terminal
```

| フラグ | 意味 |
| --- | --- |
| `--poll <file>` | poll JSON（必須） |
| `--source stdin\|web\|youtube\|twitch` | 発言の入口。複数指定可（既定 `stdin`） |
| `--sink terminal\|web` | 集計の出口。複数指定可（既定 `terminal`） |
| `--twitch <channel>` | `--source twitch` のチャンネル名（`#` 不要） |
| `--youtube <videoId>` | `--source youtube` の動画 ID（`YOUTUBE_API_KEY` が必要） |
| `--port <n>` | ウェブサーバのポート（既定 8787） |
| `--public-url <url>` | 参加用 URL の元（既定は LAN IP から推定） |
| `--web-dir <dir>` | 静的ファイルの場所（既定 `web`） |

複数 Source / Sink の同時接続の例（YouTube と Twitch を同時に聞き、ウェブ画面とターミナルに出す）:

```bash
YOUTUBE_API_KEY=... moon run --target native cmd/yuru-poll -- \
  --poll polls/next-game.json \
  --source youtube --youtube <videoId> \
  --source twitch --twitch <channel> \
  --source web --sink web --sink terminal
```

### Source: stdin

`参加者ID<TAB>発言` を 1 行ずつ読みます。TAB が無い行は匿名参加者（`stdin:anon`）の発言です。

```bash
printf 'alice\tたぶんファクトリオかな\nbob\tスプラはないわ\n' | \
  moon run --target native cmd/yuru-poll -- --poll polls/next-game.json
```

### Source: Twitch チャット

`irc.chat.twitch.tv` に TLS（6697）で匿名ユーザー（`justinfan<数字>`、PASS 不要）として接続し、
`JOIN #<channel>` して PRIVMSG を読みます。読み取り専用なので OAuth は不要です。
TLS に失敗したら平文（6667）にフォールバックします。参加者 ID は `twitch:<user-id>` です。

```bash
moon run --target native cmd/yuru-poll -- --poll polls/next-game.json --source twitch --twitch <channel> --sink terminal
```

### Source: YouTube Live チャット

YouTube Data API v3 を API キーで使います（公開ライブなら OAuth 不要）。

1. [Google Cloud Console](https://console.cloud.google.com/) でプロジェクトを作り、「YouTube Data API v3」を有効化
2. 「認証情報」→「API キー」を作成し、環境変数 `YOUTUBE_API_KEY` に設定
3. 配信の URL `https://www.youtube.com/watch?v=<videoId>` の `<videoId>` を `--youtube` に渡す

```bash
YOUTUBE_API_KEY=AIza... moon run --target native cmd/yuru-poll -- \
  --poll polls/next-game.json --source youtube --youtube <videoId> --sink terminal
```

`videos.list(part=liveStreamingDetails)` で `activeLiveChatId` を取り、
`liveChatMessages.list(part=snippet,authorDetails)` を `nextPageToken` で差分取得します。
ポーリング間隔は API が返す `pollingIntervalMillis` 以上（下限 5 秒）にしてクォータを節約します。
参加者 ID は `youtube:<channelId>` です。

### Source / Sink: ウェブ（参加フォーム・司会者画面・OBS オーバーレイ）

`--source web` か `--sink web` のどちらかを含めると HTTP サーバが起動します
（`--source web` を含めたときだけ発言を受け付けます）。

```bash
moon run --target native cmd/yuru-poll -- --poll polls/next-game.json --source web --sink web --sink terminal
```

| URL | 内容 |
| --- | --- |
| `http://localhost:8787/` | 司会者用の結果画面。棒グラフ、参加者数、確定/揺れ、発言の履歴（新しい順に最大 50 件）、参加用 URL と **QR コード**。2 秒ごとに更新 |
| `http://<LAN IP>:8787/join` | 参加者用ページ。スマホで QR を読んで開く。発言を送ると「こう解釈されました」と分布が出る |
| `http://localhost:8787/overlay` | OBS ブラウザソース用。背景透過、大きめの文字と棒グラフだけ |
| `/api/poll` `/api/tally` `/api/history` `/api/join-url` `/api/qr.svg` `POST /api/comment` | JSON API |

参加者 ID はブラウザ側で生成して `localStorage` に保持するので、同じ端末からの最新発言で上書きされます。
参加用 URL は LAN IP（macOS は `ipconfig getifaddr en0`、Linux は `hostname -I`）から推定します。
推定が合わないときは `--public-url http://192.168.1.10:8787` のように上書きしてください。

#### OBS ブラウザソースの設定

1. OBS の「ソース」→「+」→「ブラウザ」を追加
2. URL に `http://localhost:8787/overlay` を入力
3. 幅 1000、高さ 400 程度にする（選択肢が多ければ高さを増やす）
4. 「カスタム CSS」は空のままで OK（背景は透過済み）

表示の仕事は OBS 側に任せる切り分けなので、位置やサイズは OBS で調整してください。

### Sink: terminal

集計が更新されるたびに画面を消して棒グラフを描き直し、最新発言の分布を 1 行で表示します。

```
次のゲーム何やる？
Factorio       ████████████████████████████░░   1.8
スプラトゥーン ███████████████████████░░░░░░░   1.5
マインクラフト ██████████████████████████████   1.9
参加 8人 / 確定 5 / 揺れ 0 / どれでもない 3

最新: [stdin:alice] やっぱマイクラにする → Factorio 0% / スプラトゥーン 0% / マインクラフト 100% / どれでもない 0%（confidence 0.99）
```

## ホスト版（Cloudflare Workers）

ローカルで起動する代わりに、Cloudflare Workers に置いて誰でもルームを作れる形でも動かせます。
コアと API の処理は MoonBit のまま JS にコンパイルし、Workers 側は薄いグルーだけです。

```
ブラウザ ─▶ Worker（cloudflare/src/index.mjs）
             ├─ GET /                  ルーム作成ページ（web/new.html）
             ├─ POST /api/rooms        ルーム ID を振って作成
             └─ /r/<room>/...          ─▶ Durable Object（1 ルームに 1 個）
                                            └─ MoonBit の worker パッケージ
                                                 ルーティング ─▶ Jev で判定 ─▶ Engine ─▶ state を保存
```

| URL | 内容 |
| --- | --- |
| `/` | ルーム作成ページ。質問と選択肢を入れるとルームができる |
| `/r/<room>#host=<トークン>` | 司会者画面（QR 付き）。native 版と同じ `web/index.html`。トークン付きで開くと、発言の履歴とリセット・削除ボタンが出る |
| `/r/<room>/join` | 参加者ページ |
| `/r/<room>/overlay` | OBS ブラウザソース用 |
| `/r/<room>/api/...` | native 版と同じ API（`poll` `tally` `comment` `join-url` `qr.svg`）に加え、司会者用の `history` `reset` `close` |

- **判定**: 既定では Workers AI に載っている Jev（`typesafe/jev`）を `env.AI.run` で呼びます。リクエストとレスポンスの形は TypeSafe の API と同じなので、`lib` の組み立てと解釈をそのまま使います。ただし Cloudflare 上の Jev は第三者モデル扱いで、Workers AI の無料枠ではなく AI Gateway の前払いクレジット（Unified Billing）が必要です。クレジットが無いと `Insufficient AI Gateway credits` で失敗します
- **判定先の切り替え**: `JEV_URL` を設定すると、TypeSafe 互換の HTTP API が優先されます。ローカルの open-jev、TypeSafe 公式、Vercel AI Gateway（`https://ai-gateway.vercel.sh/typesafe`、モデル名は `JEV_MODEL=typesafe-ai/jev`）が使えます。キーは `npx wrangler secret put JEV_API_KEY` で入れます
- **状態**: 集計は Durable Object のメモリにあり、変更のたびに `Engine::dump` の JSON をストレージへ保存します。休止から戻るときに `Engine::restore` で復元します（「最新の発言」の表示だけは復元されません）
- **外部ライブラリ**: JS との出入口は公式の `moonbitlang/async/js_async`（Promise との橋渡し）だけを使い、Workers 用のバインディングには依存していません
- **注意**: MoonBit のコアはモジュールの初期化時にハッシュ用の乱数シードを作ります。Workers はグローバルスコープでの乱数生成を禁止しているため、グルーは MoonBit のモジュールをリクエストの中で遅延 import しています

### ローカルで動かす

アカウントは不要です。判定先にはローカルの open-jev を使います。

```bash
printf 'JEV_URL=http://127.0.0.1:8000\nJEV_API_KEY=local\n' > cloudflare/.dev.vars
```

```bash
cd cloudflare && npx wrangler dev --local
```

`http://localhost:8787/` を開くとルーム作成ページが出ます（wrangler が MoonBit のビルドも行います）。

### デプロイ

Cloudflare へのログインが必要です。`.dev.vars` はローカル専用なので、本番の判定先は `wrangler.toml` の `[vars]` とシークレットで決まります（未設定なら Workers AI の Jev）。

```bash
cd cloudflare && npx wrangler login
```

```bash
cd cloudflare && npx wrangler deploy
```

### 司会者トークンと制限

- **司会者トークン**: ルームを作ると、トークンを URL のフラグメント（`#host=...`）に載せた司会者用リンクが返ります。発言の履歴の閲覧、集計のリセット、ルームの削除にはこのトークンが必要です。フラグメントはサーバのログやリファラに残りません
- **連投の制限**: 同じ参加者は 2 秒に 1 回、同じ接続元は 1 分に 20 回、ルーム全体で 1 分に 300 判定、1 ルーム 2000 人まで。制限は判定 API を呼ぶ前に確かめるので、荒らされても費用は増えません
- **ルーム作成の制限**: 接続元ごとに 1 時間 10 回まで
- **自動削除**: 最後の更新から 24 時間でルームを消します
- **エラー文言**: 判定に失敗しても内部のエラーは利用者に見せず、詳細はサーバ側のログにだけ出します

デプロイや dev のコマンドは、必ず `cloudflare/` ディレクトリの中で実行してください。リポジトリ直下で `wrangler deploy` を実行すると、wrangler が静的サイトとして新規セットアップを始め、同名の Worker を上書きしかねません。

### まだ無いもの

- YouTube / Twitch のチャット連携（ホスト版の入口は今のところウェブフォームだけです）
- 参加者が非常に多いルームでの state の分割保存

## poll JSON の書き方

```json
{
  "question": "次のゲーム何やる？",
  "choices": [
    {
      "key": "factorio",
      "label": "Factorio",
      "description": "Factorio、ファクトリオ、工場、自動化、ベルト、生産ライン。「工場建てたい」「自動化しよう」"
    },
    {
      "key": "splatoon",
      "label": "スプラトゥーン",
      "description": "スプラ、塗り、対戦、ナワバリ、イカ。「塗りたい」「対戦しよう」"
    }
  ]
}
```

- `key`: 集計のキー（英数字推奨）。`none` は自動で末尾に付与されます（自分で書いて説明を上書きしても可）
- `label`: 画面に出る名前
- `description`: **その選択肢を支持する人がよく言う言い回し**を書く欄。判定精度に直結します
  - 略称・別名・関連語を並べる（「スプラ、スプラトゥーン、塗り、イカ」）
  - 支持者の口癖を「」で例示する（「塗りたい」「ガチマ潜ろう」）
  - 選択肢同士で紛らわしい語を避ける
- 判定リクエストの `criteria` には `"<label>: <description>"` が渡ります
- `instructions`（省略可）を書くと、その poll だけ判定の指示文を差し替えられます
- 既定の instructions は、否定の扱いと「迷いは挙げた選択肢のあいだで確率を分ける」ことを明示しています。評価セットで選んだ文言です（「判定の評価」参照）

サンプルは `polls/next-game.json`（配信向け 3 択）と `polls/lt-best-talk.json`（LT 向け 4 択）にあります。

## 判定の評価

`eval/` に、正解ラベル付きの発言セット（支持、弱い支持、否定、雑談、2 択の迷い）と、指示文の候補を比べるスクリプトがあります。必要なのは Python 3 と curl だけです。

```bash
python3 eval/run.py --via-room https://<あなたの Worker>.workers.dev
```

```bash
JEV_API_KEY=... python3 eval/run.py --jev-url https://ai-gateway.vercel.sh/typesafe --model typesafe-ai/jev
```

指標は 2 つです。正解が 1 つに決まる発言での正解率と、2 択で迷っている発言の確率が実際にその 2 択へ分かれた割合（小数票の肝）です。

評価セット（`eval/next-game.json`、28 発言）での結果です。2026-09-20 時点で、本家 Jev は Vercel AI Gateway 経由、Gemma はローカルの open-jev（Gemma 3 4B）です。

| 指示文の候補 | Jev 正解率 | Jev 迷いの分割 | Gemma 正解率 | Gemma 迷いの分割 |
| --- | --- | --- | --- | --- |
| `minimal`（何も足さない） | 22/22 | 2/6 | 18/22 | 0/6 |
| `current`（以前の既定。「迷っているなら none」を含む） | 21/22 | 1/6 | 21/22 | 0/6 |
| `no-hesitation-clause` | 21/21（1 件は通信失敗） | 1/6 | 20/22 | 0/6 |
| `split-explicit` | 21/21（1 件は通信失敗） | 2/6 | 21/22 | 0/6 |
| **`split-explicit+none`（採用）** | **22/22** | **2/6** | **21/22** | **1/6** |

分かったこと:

- 支持、否定、雑談の判定は、本家 Jev ではどの指示文でもほぼ満点です。小さなローカルモデルは、否定の扱いを指示文に書かないと崩れます
- 以前の「迷っているなら none」は有害でした。本家 Jev は「たぶんスプラ…かなあ、自信ない」まで none 0.64 に落とします（採用案ではスプラ 0.97）
- 「A もいいけど B も好き」型は小数票になります（例: 「イカもいいけど工場も好き」→ スプラ 0.60 / Factorio 0.25 / どれでもない 0.15）
- 「A か B で迷ってる」型は、指示文や none の説明を変えても none が 0.8 以上を占めます。プロンプトでは解決できませんでした
- 「たぶん」のような弱い支持は 0.9 台になります。Gemma はほぼ常に 1.00 です

## Source / Sink の追加方法

インターフェースは `lib/engine.mbt` の 2 つの trait だけです。

```moonbit nocheck
///|
/// 発言の入口。`submit` に発言を渡すと判定・集計され、判定結果が返る。
pub(open) trait Source {
  async fn run(Self, submit : async (Comment) -> Judgement) -> Unit
}

///|
/// 集計の出口。Tally が更新されるたびに呼ばれる。
pub(open) trait Sink {
  fn on_update(Self, Update) -> Unit
}
```

- `Comment { participant_id, text, at }`: 参加者 ID には Source 名のプレフィックスを付けます（`@lib.participant_id("slack", id)` → `slack:<id>`）
- `Update { poll, comment, judgement, snapshot }`: Sink が受け取る 1 回分の更新。`snapshot` に合計票・参加者数・確定/揺れ・none 件数が入ります
- `submit` は判定の失敗を raise します。チャット系 Source は catch してログに出し、次の発言に進んでください

### Source を足す（例: `adapters/slack`）

1. `adapters/<name>/moon.pkg` を作り `hiroyannnn/yuru-poll/lib` と `hiroyannnn/yuru-poll/runtime` を import（`supported_targets = "-all+native"`）
2. struct を定義し `pub impl @lib.Source for X with run(self, submit) { ... }` で発言を `submit` に流す
3. 生テキストの解釈は純粋関数として `lib/` に置き、`_test.mbt` で全ターゲットのテストを書く（`twitch_parse.mbt` / `youtube_parse.mbt` が例）
4. `cmd/yuru-poll/main.mbt` の `match name` に 1 行足す

### Sink を足す（例: CSV 書き出し、Slack 投稿）

1. 同様にパッケージを作り `pub impl @lib.Sink for X with on_update(self, update) { ... }`
2. 描画・整形のロジックは `lib/render.mbt` のように純粋関数にしてテストする
3. `cmd/yuru-poll/main.mbt` の sink の `match name` に足す

判定関数は `runtime.run(engine, judge, sources)` に注入するので、HTTP なしのユニットテストでは偽の判定関数を渡せます（`runtime/runtime_test.mbt` 参照）。

## 判定のクセ

- ローカルの open-jev（Gemma 3 4B）は `p=1.00` を出しがちで、小数票がほとんど出ません。先頭の選択肢に寄る誤判定もあります（「みんなでワイワイできるやつ」→ Factorio 100% など）。本家 Jev では「たぶん」が 0.9 台になり、「A もいいけど B も」が分かれます。詳しくは「判定の評価」を見てください
- 判定は本家 Jev で 1 件 0.4〜0.7 秒、ローカルで約 0.4 秒です。発言が集中しても直列に処理し、待たせるだけで落としません

## Acknowledgments

- [naoto24kawa/moonqr](https://github.com/elchika-inc/moonqr)（Apache-2.0）— 参加用 QR コードの生成に使用。テストではそのデコーダで、生成した QR が実際に読めることを検証しています。jsQR（Apache-2.0）と qrcode-generator（MIT）に由来する部分を含みます
- [moonbitlang/async](https://github.com/moonbitlang/async)（Apache-2.0）— イベントループ、ソケット、TLS、HTTP クライアント/サーバ
- [TypeSafe Jev](https://docs.typesafe.ai/) / [open-jev](https://github.com/daseinlabs/open-jev) — 判定 API

ライセンス表記の詳細は `NOTICE` を参照してください。本プロジェクトは Apache-2.0 です。
