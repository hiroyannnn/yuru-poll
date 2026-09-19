# yuru-poll

**Polls where nobody has to pick an option.** Participants just say something — "probably A", "no way B", "hmm, can't decide" — and an AI model turns each remark into a probability distribution over the options. Those probabilities are added up as *fractional votes*.

[日本語の README はこちら](README.ja.md)

*yuru* (ゆるい) is Japanese for loose, relaxed.

- **Loose answers**: no buttons, no commands. Chat as usual.
- **Loose counting**: probabilities are summed as they are (e.g. *Factorio 12.4 votes*).
- **Loose filtering**: a "none of these" option is always mixed in, so small talk and negations fall out of the tally.
- **Loose revisions**: the latest remark from the same participant replaces the previous one (one distribution per person).

Judging is done by [Jev](https://docs.typesafe.ai/), TypeSafe AI's System One model, which returns calibrated probabilities for typed questions instead of generating text. yuru-poll is written in [MoonBit](https://www.moonbitlang.com/): the same core runs as a native CLI/server and, compiled to JavaScript, on Cloudflare Workers.

## How it fits together

Inputs (**sources**) and outputs (**sinks**) are independent adapters around a small pure core. One engine can listen to several sources and feed several sinks at once.

```
Source                       Engine                           Sink
  stdin    ─┐                                              ┌─ terminal bar chart
  web form ─┼─ submit ─▶ judge (Jev) ─▶ Tally ─▶ Update ─▶ ┼─ host screen (web)
  YouTube  ─┤   (serialized)                                └─ OBS overlay (web)
  Twitch   ─┘
```

| Package | Role | Target |
| --- | --- | --- |
| `lib/` | Poll, request/response, tally, engine, history, rate limiter, QR, chat parsers, rendering — all pure | all |
| `runtime/` | Runs all sources concurrently and serializes judging through an injected judge function | native |
| `jev/` | Jev HTTP client | native |
| `adapters/*` | `stdin`, `twitch`, `youtube` sources; `terminal` sink; `web` source + sink | native |
| `cmd/yuru-poll` | Thin CLI that picks sources and sinks by flags | native |
| `worker/` | Room API for the hosted version (same API as the native web server, per room) | js |
| `cloudflare/` | Thin JS glue and wrangler config for Cloudflare Workers | - |

## Quick start (local)

You need the [MoonBit toolchain](https://www.moonbitlang.com/download/) and access to a Jev-compatible endpoint.

```bash
moon test --target all
```

Point the client at a judge. Any TypeSafe-compatible `POST /v1/systemone` endpoint works:

```bash
# Vercel AI Gateway
export JEV_URL=https://ai-gateway.vercel.sh/typesafe
export JEV_MODEL=typesafe-ai/jev
export JEV_API_KEY=<your AI Gateway API key>
```

The defaults (`JEV_URL=http://127.0.0.1:8000`, `JEV_API_KEY=local`, `JEV_MODEL=jev-latest`) target a local [open-jev](https://github.com/daseinlabs/open-jev) server.

Run a poll with a web form for participants, a host screen, and a terminal chart:

```bash
moon run --target native cmd/yuru-poll -- --poll polls/next-game.json --source web --sink web --sink terminal
```

Open `http://localhost:8787/` for the host screen. It shows the results, the join URL and a QR code; participants open `/join` on their phones.

| Flag | Meaning |
| --- | --- |
| `--poll <file>` | Poll JSON (required) |
| `--source stdin\|web\|youtube\|twitch` | Where remarks come from. Repeatable (default `stdin`) |
| `--sink terminal\|web` | Where the tally goes. Repeatable (default `terminal`) |
| `--twitch <channel>` | Channel for `--source twitch`. Connects anonymously over TLS; no OAuth needed |
| `--youtube <videoId>` | Live video for `--source youtube`. Needs `YOUTUBE_API_KEY` (YouTube Data API v3) |
| `--port <n>` | Web server port (default 8787) |
| `--public-url <url>` | Base of the join URL (default: guessed from the LAN IP) |

Pages served by the web adapter:

| URL | What |
| --- | --- |
| `/` | Host screen: bars, participant counts, recent remarks, join URL and QR code |
| `/join` | Participant page. Send a remark, see how it was interpreted |
| `/overlay` | For an OBS browser source: transparent background, big bars only |

## Hosted version (Cloudflare Workers)

The same core and API, compiled to JavaScript, with one Durable Object per room. Anyone can create a room from the landing page.

```
browser ─▶ Worker (cloudflare/src/index.mjs)
            ├─ GET /                landing page: create a room
            ├─ POST /api/rooms      rate-limited per client, issues a host token
            └─ /r/<room>/...        ─▶ Durable Object (one per room)
                                         └─ MoonBit `worker` package
                                              route ─▶ judge ─▶ engine ─▶ state to storage
```

- **No third-party Workers bindings.** The only bridge to JavaScript is the official `moonbitlang/async/js_async` (Promise interop). Routing, validation, rate limiting, judging and tallying are MoonBit.
- **Judge**: set `JEV_URL` / `JEV_MODEL` in `wrangler.toml` and put the key in a secret (`npx wrangler secret put JEV_API_KEY`). Without `JEV_URL` it falls back to Jev on Workers AI (`env.AI.run('typesafe/jev', ...)`), which is billed through AI Gateway prepaid credits rather than the Workers AI free tier.
- **Host token**: creating a room returns a host link with the token in the URL fragment (`#host=...`). Viewing remark history, resetting the tally and closing the room require it.
- **Limits**: one remark per participant every 2 s, 20 remarks per minute per client IP, 300 judgements per minute per room, 2000 participants per room, 10 new rooms per hour per client. Limits are checked *before* calling the judge.
- **State**: the tally lives in the Durable Object's memory; every change is saved as `Engine::dump` JSON and restored with `Engine::restore`. Rooms are deleted 24 hours after their last update.

Run it locally (no Cloudflare account needed; wrangler also builds the MoonBit package):

```bash
printf 'JEV_URL=http://127.0.0.1:8000\nJEV_API_KEY=local\n' > cloudflare/.dev.vars
```

```bash
cd cloudflare && npx wrangler dev --local
```

Deploy. Always run wrangler from the `cloudflare/` directory:

```bash
cd cloudflare && npx wrangler deploy
```

### Notes on running MoonBit on Workers

- MoonBit's core creates a random hash seed when the module initializes. Workers forbid generating random values in global scope, so a top-level `import` of the compiled module fails at startup. The glue imports it lazily inside the first request (and inside the Durable Object's initialization).
- A MoonBit function that `raise`s is exposed to JavaScript as returning a `Result` object, not throwing. The exported entry points therefore never raise and return JSON strings.
- The `wasm-gc` backend does not run on Workers as is: it relies on the `js-string` builtins, which must be enabled at compile time, and Workers only accept statically imported Wasm modules. The JS backend is used instead.

## Writing a poll

```json
{
  "question": "Which game should we play next?",
  "choices": [
    {
      "key": "factorio",
      "label": "Factorio",
      "description": "Factorio, factories, automation, belts. \"let's build a factory\", \"launch the rocket\""
    },
    {
      "key": "splatoon",
      "label": "Splatoon",
      "description": "Splatoon, inking, turf war, squid. \"I want to ink\", \"ranked battles\""
    }
  ]
}
```

- `description` is where accuracy comes from: write **how supporters of that option tend to talk** — nicknames, related words, typical phrases.
- `none` ("none of these") is appended automatically. You can define it yourself to change its wording.
- `instructions` (optional) replaces the default instruction text sent to the judge for this poll.

Samples: `polls/next-game.json` (for streams) and `polls/lt-best-talk.json` (for talks). Both are in Japanese.

## Evaluating the judge

`eval/` holds a labelled set of remarks (support, weak support, negation, small talk, hesitation between two options) and a script that compares instruction candidates. It needs only Python 3 and curl.

```bash
python3 eval/run.py --via-room https://<your-worker>.workers.dev
```

```bash
JEV_API_KEY=... python3 eval/run.py --jev-url https://ai-gateway.vercel.sh/typesafe --model typesafe-ai/jev
```

Two numbers are reported: accuracy on remarks with a single expected option, and how often a remark that hesitates between two options actually gets its probability split between them — the behaviour fractional votes depend on.

Results on the evaluation set (`eval/next-game.json`, 28 remarks in Japanese) as of 2026-09-20. *Jev* is TypeSafe's model through Vercel AI Gateway; *Gemma* is a local open-jev server running Gemma 3 4B.

| Instruction candidate | Jev accuracy | Jev split | Gemma accuracy | Gemma split |
| --- | --- | --- | --- | --- |
| `minimal` (no extra guidance) | 22/22 | 2/6 | 18/22 | 0/6 |
| `current` (the previous default; says "if hesitating, answer none") | 21/22 | 1/6 | 21/22 | 0/6 |
| `no-hesitation-clause` | 21/21 (1 request failed) | 1/6 | 20/22 | 0/6 |
| `split-explicit` | 21/21 (1 request failed) | 2/6 | 21/22 | 0/6 |
| **`split-explicit+none` (adopted)** | **22/22** | **2/6** | **21/22** | **1/6** |

What we learned:

- Support, negation and small talk are judged almost perfectly by Jev under every candidate. A small local model needs the negation guidance or it breaks.
- The old "if hesitating, answer none" clause was harmful: Jev pushed "probably Splatoon… not sure though" to *none* 0.64 (0.97 Splatoon with the adopted text).
- "I like A, but B is good too" remarks do become fractional votes (e.g. Splatoon 0.60 / Factorio 0.25 / none 0.15).
- "I can't decide between A and B" remarks stay dominated by *none* (0.8+) whatever the instructions or the *none* description say. Prompting did not fix this.
- Hedged support ("probably A") lands in the 0.9s with Jev. Gemma almost always answers 1.00.

## Adding a source or a sink

The whole interface is two traits in `lib/engine.mbt`:

```moonbit nocheck
///|
/// An input. Pass each remark to `submit`; it is judged, tallied, and the judgement is returned.
pub(open) trait Source {
  async fn run(Self, submit : async (Comment) -> Judgement) -> Unit
}

///|
/// An output. Called every time the tally changes.
pub(open) trait Sink {
  fn on_update(Self, Update) -> Unit
}
```

1. Create `adapters/<name>/` with `supported_targets = "-all+native"` and implement the trait.
2. Keep text parsing pure in `lib/` with tests for every target (`twitch_parse.mbt` and `youtube_parse.mbt` are examples).
3. Add one line to the `match` in `cmd/yuru-poll/main.mbt`.

Prefix participant IDs with the source name (`@lib.participant_id("slack", id)` gives `slack:<id>`) so they never collide across sources.

## Testing

```bash
moon check --target all && moon test --target all
```

The core is tested on wasm, wasm-gc, js and native. Native-only packages are tested on native, and the Workers router on js with `async test` and a fake judge. QR codes are verified by rasterizing the generated matrix and decoding it again.

## Acknowledgments

- [naoto24kawa/moonqr](https://github.com/elchika-inc/moonqr) (Apache-2.0) — QR code generation; its decoder is used in tests to prove the generated codes are readable. Contains portions derived from jsQR (Apache-2.0) and qrcode-generator (MIT).
- [moonbitlang/async](https://github.com/moonbitlang/async) (Apache-2.0) — event loop, sockets, TLS, HTTP client/server, Promise interop.
- [TypeSafe Jev](https://docs.typesafe.ai/) and [open-jev](https://github.com/daseinlabs/open-jev) — the judge.

See `NOTICE` for license details. yuru-poll itself is licensed under Apache-2.0.
