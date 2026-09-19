///|
let history_poll_json : String =
  #|{"question": "Q", "choices": [{"key": "a", "label": "A"}, {"key": "b", "label": "B"}]}

///|
fn say(
  engine : @lib.Engine,
  id : String,
  text : String,
  choice : String,
) -> Unit {
  engine.apply({ participant_id: id, text, at: 0, }, {
    choice,
    probabilities: Map::from_array([(choice, 1.0)]),
    confidence: 1.0,
  })
  |> ignore
}

///|
test "Engine::history は発言と判定を新しい順に返す（上書きされた発言も履歴には残る）" {
  let engine = @lib.Engine::new(@lib.Poll::parse(history_poll_json))
  say(engine, "web:x", "A かな", "a")
  say(engine, "web:y", "B で", "b")
  say(engine, "web:x", "やっぱ B", "b")
  let history = engine.history()
  inspect(history.length(), content="3")
  inspect(history[0].comment.text, content="やっぱ B")
  inspect(history[2].comment.text, content="A かな")
  inspect(history[0].judgement.choice, content="b")
  inspect(engine.snapshot().participants, content="2")
}

///|
test "履歴は HISTORY_LIMIT 件までで、古いものから捨てる" {
  let engine = @lib.Engine::new(@lib.Poll::parse(history_poll_json))
  for i in 0..<(@lib.HISTORY_LIMIT + 5) {
    say(engine, "web:p\{i}", "発言 \{i}", "a")
  }
  let history = engine.history()
  inspect(history.length() == @lib.HISTORY_LIMIT, content="true")
  inspect(history[0].comment.text, content="発言 \{@lib.HISTORY_LIMIT + 4}")
  inspect(history[history.length() - 1].comment.text, content="発言 5")
}

///|
test "dump / restore で履歴も戻る。履歴の無い古い state も読める" {
  let engine = @lib.Engine::new(@lib.Poll::parse(history_poll_json))
  say(engine, "web:x", "A かな", "a")
  say(engine, "web:y", "B で", "b")
  let restored = @lib.Engine::restore(@json.parse(engine.dump().stringify()))
  inspect(restored.history().length(), content="2")
  inspect(restored.history()[0].comment.text, content="B で")
  let old_state =
    #|{"poll": {"question": "Q", "choices": [{"key": "a", "label": "A"}]}, "entries": {}}
  inspect(
    @lib.Engine::restore(@json.parse(old_state)).history().length(),
    content="0",
  )
}

///|
test "Engine::reset は集計と履歴を空にする（poll は残る）" {
  let engine = @lib.Engine::new(@lib.Poll::parse(history_poll_json))
  say(engine, "web:x", "A かな", "a")
  engine.reset()
  inspect(engine.snapshot().participants, content="0")
  inspect(engine.history().length(), content="0")
  inspect(engine.poll.question, content="Q")
}
