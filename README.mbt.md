# yuru-poll — ゆるアンケート

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
| `lib/` | Poll、リクエスト/レスポンス、Tally、Engine、Source/Sink trait、各種パース、描画（純粋） | all |
| `runtime/` | 全 Source を同時に走らせ、注入した判定関数で直列に判定して Engine へ流す | native |
| `jev/` | Jev HTTP クライアント（`JEV_URL` / `JEV_API_KEY`） | native |
| `adapters/stdin` `adapters/twitch` `adapters/youtube` | Source | native |
| `adapters/terminal` | Sink | native |
| `adapters/web` | Source（参加フォーム）兼 Sink（司会者画面・OBS オーバーレイ） | native |
| `cmd/yuru-poll` | Source と Sink の組み合わせを CLI フラグで選ぶだけの薄い層 | native |

## セットアップ

```bash
moon check --target all      # 型チェック
moon test --target all       # コアは wasm / wasm-gc / js / native、native 限定パッケージは native のみ
moon build --target native
```

判定サーバは TypeSafe Jev、またはローカルの [open-jev](https://github.com/hiroyannnn/open-jev) を使います。

```bash
export JEV_URL=http://127.0.0.1:8000   # 既定値
export JEV_API_KEY=local               # 既定値（Authorization: Bearer <key>）
curl -s $JEV_URL/health
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
| `http://localhost:8787/` | 司会者用の結果画面。棒グラフ、参加者数、確定/揺れ、参加用 URL と **QR コード**。2 秒ごとに更新 |
| `http://<LAN IP>:8787/join` | 参加者用ページ。スマホで QR を読んで開く。発言を送ると「こう解釈されました」と分布が出る |
| `http://localhost:8787/overlay` | OBS ブラウザソース用。背景透過、大きめの文字と棒グラフだけ |
| `/api/poll` `/api/tally` `/api/join-url` `/api/qr.svg` `POST /api/comment` | JSON API |

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
- instructions には「否定はその選択肢への支持ではない」「迷い・雑談・挨拶なら none」と明示しています。
  ローカルの小さなモデルでも「Bはないわ」を B の支持と誤判定しにくくなります

サンプルは `polls/next-game.json`（配信向け 3 択）と `polls/lt-best-talk.json`（LT 向け 4 択）にあります。

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

## 判定のクセ（ローカル open-jev = Gemma 3 4B での実測）

- choice 質問は日本語で概ね正しく判定しますが、`p=1.00` を出しがちで本家 Jev より小数票が出にくいです。設計は確率のまま扱っています
- 「マイクラかスプラで迷ってる」のような二択の迷いは 50/50 にならず片方に寄ることがあります
- 1 質問あたり約 400 ms。発言が集中しても runtime が直列に処理し、待たせるだけで落としません

## Acknowledgments

- [bobzhang/qrc](https://github.com/bobzhang/qrc)（ISC License）— 参加用 QR コードの SVG 生成に使用。OCaml の [qrc](https://github.com/dbuenzli/qrc)（Daniel Bünzli、ISC）の MoonBit 移植
- [moonbitlang/async](https://github.com/moonbitlang/async)（Apache-2.0）— イベントループ、ソケット、TLS、HTTP クライアント/サーバ
- [TypeSafe Jev](https://docs.typesafe.ai/) / [open-jev](https://github.com/hiroyannnn/open-jev) — 判定 API

ライセンス表記の詳細は `NOTICE` を参照してください。本プロジェクトは Apache-2.0 です。
