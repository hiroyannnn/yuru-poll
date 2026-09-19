///|
let sample_poll_json : String =
  #|{
  #|  "question": "次のゲーム何やる？",
  #|  "choices": [
  #|    {"key": "factorio", "label": "Factorio", "description": "工場、自動化、ベルトの話"},
  #|    {"key": "splatoon", "label": "スプラトゥーン", "description": "塗り、対戦、イカ"}
  #|  ]
  #|}

///|
/// 失敗するはずの Poll::parse を実行し、エラーの Debug 表現を検査する。
fn expect_poll_error(text : String, content : String) -> Unit raise {
  try @lib.Poll::parse(text) catch {
    e => debug_inspect(e, content~)
  } noraise {
    _ => fail("Poll::parse は失敗するはず")
  }
}

///|
test "Poll::parse は質問文と選択肢を読み、none を末尾に自動付与する" {
  let poll = @lib.Poll::parse(sample_poll_json)
  inspect(poll.question, content="次のゲーム何やる？")
  inspect(poll.choices.length(), content="3")
  inspect(poll.choices[0].key, content="factorio")
  inspect(poll.choices[0].label, content="Factorio")
  inspect(
    poll.choices[0].description,
    content="工場、自動化、ベルトの話",
  )
  inspect(poll.choices[2].key, content="none")
  inspect(poll.choices[2].label, content="どれでもない")
  inspect(
    poll.choices[2].description,
    content="どれも支持していない、雑談、意味不明",
  )
}

///|
test "Poll::keys は選択肢のキーを順に返す" {
  let poll = @lib.Poll::parse(sample_poll_json)
  debug_inspect(poll.keys(), content="[\"factorio\", \"splatoon\", \"none\"]")
}

///|
test "JSON に none が含まれていればそれを使い、二重に付与しない" {
  let text =
    #|{"question": "Q", "choices": [
    #|  {"key": "a", "label": "A", "description": "aaa"},
    #|  {"key": "none", "label": "パス", "description": "興味なし"}
    #|]}
  let poll = @lib.Poll::parse(text)
  inspect(poll.choices.length(), content="2")
  inspect(poll.choices[1].label, content="パス")
}

///|
test "description は省略可能で空文字になる" {
  let text =
    #|{"question": "Q", "choices": [{"key": "a", "label": "A"}]}
  let poll = @lib.Poll::parse(text)
  inspect(poll.choices[0].description, content="")
}

///|
test "question が無ければ MissingField エラー" {
  let text =
    #|{"choices": [{"key": "a", "label": "A"}]}
  expect_poll_error(text, "MissingField(\"question\")")
}

///|
test "choices が配列でなければ TypeMismatch エラー" {
  let text =
    #|{"question": "Q", "choices": "a"}
  expect_poll_error(text, "TypeMismatch(\"choices\")")
}

///|
test "キーが重複していれば DuplicateKey エラー" {
  let text =
    #|{"question": "Q", "choices": [
    #|  {"key": "a", "label": "A"}, {"key": "a", "label": "A2"}
    #|]}
  expect_poll_error(text, "DuplicateKey(\"a\")")
}

///|
test "選択肢が 1 つも無ければ EmptyChoices エラー" {
  let text =
    #|{"question": "Q", "choices": []}
  expect_poll_error(text, "EmptyChoices")
}

///|
test "JSON として壊れていれば InvalidJson エラー" {
  try @lib.Poll::parse("{not json") catch {
    e => assert_true(e is @lib.PollError::InvalidJson(_))
  } noraise {
    _ => fail("壊れた JSON は失敗するはず")
  }
}

///|
test "Poll::find は key で選択肢を引ける" {
  let poll = @lib.Poll::parse(sample_poll_json)
  assert_true(
    poll.find("splatoon") is Some({ label: "スプラトゥーン", .. }),
  )
  assert_true(poll.find("zelda") is None)
}
