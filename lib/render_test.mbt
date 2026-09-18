///|
let render_poll_json : String =
  #|{"question": "次のゲーム何やる？", "choices": [
  #|  {"key": "factorio", "label": "Factorio", "description": "工場"},
  #|  {"key": "splatoon", "label": "スプラ", "description": "塗り"}
  #|]}

///|
test "format_votes は小数票を小数 1 桁で表示する" {
  inspect(@lib.format_votes(12.44), content="12.4")
  inspect(@lib.format_votes(0.1 + 0.2), content="0.3")
  inspect(@lib.format_votes(3.0), content="3.0")
  inspect(@lib.format_votes(0.96), content="1.0")
  inspect(@lib.format_votes(0.0), content="0.0")
}

///|
test "display_width は全角を 2、半角を 1 と数える" {
  inspect(@lib.display_width("abc"), content="3")
  inspect(@lib.display_width("スプラ"), content="6")
  inspect(@lib.display_width("A塗り"), content="5")
}

///|
test "render_snapshot は質問・選択肢ごとの棒・内訳を描く（none は棒に出さない）" {
  let poll = @lib.Poll::parse(render_poll_json)
  let tally = @lib.Tally::new(poll.keys())
  tally.record("a", {
    choice: "factorio",
    probabilities: { "factorio": 0.9, "splatoon": 0.1 },
    confidence: 1,
  })
  tally.record("b", {
    choice: "factorio",
    probabilities: { "factorio": 0.6, "splatoon": 0.3, "none": 0.1 },
    confidence: 1,
  })
  tally.record("c", {
    choice: "none",
    probabilities: { "none": 1.0 },
    confidence: 1,
  })
  inspect(
    @lib.render_snapshot(poll, tally.snapshot(), width=10),
    content=(
      #|次のゲーム何やる？
      #|Factorio ██████████   1.5
      #|スプラ   ███░░░░░░░   0.4
      #|参加 3人 / 確定 1 / 揺れ 1 / どれでもない 1
      #|
    ),
  )
}

///|
test "render_snapshot は票が 0 でも割り算で落ちない" {
  let poll = @lib.Poll::parse(render_poll_json)
  let text = @lib.render_snapshot(
    poll,
    @lib.Tally::new(poll.keys()).snapshot(),
    width=4,
  )
  inspect(
    text,
    content=(
      #|次のゲーム何やる？
      #|Factorio ░░░░   0.0
      #|スプラ   ░░░░   0.0
      #|参加 0人 / 確定 0 / 揺れ 0 / どれでもない 0
      #|
    ),
  )
}

///|
test "render_update は最新発言の解釈を 1 行で描く" {
  let poll = @lib.Poll::parse(render_poll_json)
  let engine = @lib.Engine::new(poll)
  let update = engine.apply(
    {
      participant_id: "stdin:alice",
      text: "たぶんファクトリオ",
      at: 0,
    },
    {
      choice: "factorio",
      probabilities: { "factorio": 0.88, "splatoon": 0.05, "none": 0.07 },
      confidence: 0.79,
    },
  )
  inspect(
    @lib.render_last_comment(update),
    content="最新: [stdin:alice] たぶんファクトリオ → Factorio 88% / スプラ 5% / どれでもない 7%（confidence 0.79）",
  )
}
