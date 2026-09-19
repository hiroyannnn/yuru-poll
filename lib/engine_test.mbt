///|
let engine_poll_json : String =
  #|{"question": "Q", "choices": [
  #|  {"key": "a", "label": "A", "description": "aaa"},
  #|  {"key": "b", "label": "B", "description": "bbb"}
  #|]}

///|
/// 受け取った Update を記録するだけの Sink。
struct RecordingSink {
  updates : Array[@lib.Update]
}

///|
impl @lib.Sink for RecordingSink with fn on_update(self, update) {
  self.updates.push(update)
}

///|
fn comment(participant_id : String, text : String) -> @lib.Comment {
  { participant_id, text, at: 1000, }
}

///|
fn judged(
  choice : String,
  probabilities : Map[String, Double],
) -> @lib.Judgement {
  { choice, probabilities, confidence: 0.9, }
}

///|
test "Engine::apply は Tally を更新し、Update（発言・判定・集計）を返す" {
  let engine = @lib.Engine::new(@lib.Poll::parse(engine_poll_json))
  let update = engine.apply(
    comment("stdin:alice", "たぶんA"),
    judged("a", { "a": 0.7, "b": 0.2, "none": 0.1 }),
  )
  inspect(update.comment.text, content="たぶんA")
  inspect(update.judgement.choice, content="a")
  inspect(update.snapshot.participants, content="1")
  inspect(update.snapshot.totals["a"], content="0.7")
  inspect(engine.snapshot().totals["a"], content="0.7")
}

///|
test "Engine は接続された全ての Sink に順番に通知する" {
  let engine = @lib.Engine::new(@lib.Poll::parse(engine_poll_json))
  let first = RecordingSink::{ updates: [], }
  let second = RecordingSink::{ updates: [], }
  engine.add_sink(first)
  engine.add_sink(second)
  engine.apply(comment("x", "A"), judged("a", { "a": 1.0 })) |> ignore
  engine.apply(comment("y", "B"), judged("b", { "b": 1.0 })) |> ignore
  inspect(first.updates.length(), content="2")
  inspect(second.updates.length(), content="2")
  inspect(second.updates[1].snapshot.totals["b"], content="1")
  inspect(second.updates[1].poll.question, content="Q")
}

///|
test "Sink が無くても Engine::apply は動く" {
  let engine = @lib.Engine::new(@lib.Poll::parse(engine_poll_json))
  let update = engine.apply(comment("x", "A"), judged("a", { "a": 1.0 }))
  inspect(update.snapshot.confident, content="1")
}

///|
test "Engine::poll で質問と選択肢を参照できる" {
  let engine = @lib.Engine::new(@lib.Poll::parse(engine_poll_json))
  debug_inspect(engine.poll.keys(), content="[\"a\", \"b\", \"none\"]")
}

///|
test "Update は JSON にできる（参加者に返す用）" {
  let engine = @lib.Engine::new(@lib.Poll::parse(engine_poll_json))
  let update = engine.apply(
    comment("x", "A"),
    judged("a", { "a": 1.0, "b": 0.0, "none": 0.0 }),
  )
  json_inspect(update.judgement, content={
    "choice": "a",
    "probabilities": { "a": 1, "b": 0, "none": 0 },
    "confidence": 0.9,
  })
}
