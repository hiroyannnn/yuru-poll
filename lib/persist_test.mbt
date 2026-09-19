///|
let persist_poll_json : String =
  #|{"question": "Q", "choices": [
  #|  {"key": "a", "label": "A", "description": "aaa"},
  #|  {"key": "b", "label": "B", "description": "bbb"}
  #|]}

///|
fn persisted_engine() -> @lib.Engine raise {
  let engine = @lib.Engine::new(@lib.Poll::parse(persist_poll_json))
  engine.apply({ participant_id: "web:x", text: "A かな", at: 1, }, {
    choice: "a",
    probabilities: { "a": 0.7, "b": 0.2, "none": 0.1 },
    confidence: 0.6,
  })
  |> ignore
  engine.apply({ participant_id: "web:y", text: "雑談", at: 2, }, {
    choice: "none",
    probabilities: { "a": 0.0, "b": 0.0, "none": 1.0 },
    confidence: 0.9,
  })
  |> ignore
  engine
}

///|
test "Engine::dump は poll と参加者ごとの最新判定を JSON にする" {
  let dumped = persisted_engine().dump()
  guard dumped is Object({ "poll": Object(_), "entries": Object(entries), .. }) else {
    fail("poll と entries を持つはず")
  }
  inspect(entries.length(), content="2")
  json_inspect(entries["web:x"], content={
    "choice": "a",
    "probabilities": { "a": 0.7, "b": 0.2, "none": 0.1 },
    "confidence": 0.6,
  })
}

///|
test "Engine::restore は dump から同じ集計を復元する（文字列化を挟んでも同じ）" {
  let engine = persisted_engine()
  let text = engine.dump().stringify()
  let restored = @lib.Engine::restore(@json.parse(text))
  assert_eq(restored.snapshot(), engine.snapshot())
  inspect(restored.poll.question, content="Q")
  debug_inspect(restored.poll.keys(), content="[\"a\", \"b\", \"none\"]")
}

///|
test "復元した Engine でも同じ参加者の発言は上書きになる" {
  let restored = @lib.Engine::restore(persisted_engine().dump())
  let update = restored.apply(
    { participant_id: "web:x", text: "やっぱ B", at: 3, },
    { choice: "b", probabilities: { "b": 1.0 }, confidence: 1.0, },
  )
  inspect(update.snapshot.participants, content="2")
  inspect(update.snapshot.totals["a"], content="0")
  inspect(update.snapshot.totals["b"], content="1")
}

///|
test "Engine::restore は壊れた JSON をエラー型で返す" {
  try @lib.Engine::restore(@json.parse("{\"entries\": {}}")) catch {
    e => debug_inspect(e, content="BadPoll(MissingField(\"question\"))")
  } noraise {
    _ => fail("失敗するはず")
  }
  let bad_entry =
    #|{"poll": {"question": "Q", "choices": [{"key": "a", "label": "A"}]},
    #| "entries": {"web:x": {"choice": "a", "probabilities": {"a": "high"}, "confidence": 1}}}
  try @lib.Engine::restore(@json.parse(bad_entry)) catch {
    e =>
      debug_inspect(
        e,
        content="BadEntry(\"web:x\", TypeMismatch(\"probabilities.a\"))",
      )
  } noraise {
    _ => fail("失敗するはず")
  }
}

///|
test "Judgement::from_json は choice・probabilities・confidence を読む" {
  let judgement = @lib.Judgement::from_json(
    { "choice": "a", "probabilities": { "a": 1 }, "confidence": 0.5 },
    path="",
  )
  inspect(judgement.choice, content="a")
  inspect(judgement.confidence, content="0.5")
}
