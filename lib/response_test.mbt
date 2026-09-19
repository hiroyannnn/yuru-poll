///|
let sample_response : String =
  #|{"model": "jev-latest",
  #| "answers": {"vote": {"type": "choice", "choice": "factorio",
  #|   "probabilities": {"factorio": 0.88, "splatoon": 0.05, "none": 0.07},
  #|   "confidence": 0.79}},
  #| "usage": {"input_tokens": 120, "output_tokens": 2}}

///|
fn expect_response_error(text : String, content : String) -> Unit raise {
  try @lib.parse_response_text(text) catch {
    e => debug_inspect(e, content~)
  } noraise {
    _ => fail("parse_response_text は失敗するはず")
  }
}

///|
test "parse_response_text は選ばれた key、確率分布、confidence を取り出す" {
  let judgement = @lib.parse_response_text(sample_response)
  inspect(judgement.choice, content="factorio")
  inspect(judgement.confidence, content="0.79")
  debug_inspect(
    judgement.probabilities,
    content=(
      #|{ "factorio": 0.88, "splatoon": 0.05, "none": 0.07 }
    ),
  )
}

///|
test "Judgement::probability は無い key なら 0 を返す" {
  let judgement = @lib.parse_response_text(sample_response)
  inspect(judgement.probability("splatoon"), content="0.05")
  inspect(judgement.probability("zelda"), content="0")
}

///|
test "answers が無ければ MissingField" {
  expect_response_error(
    (
      #|{"model": "jev-latest"}
    ),
    "MissingField(\"answers\")",
  )
}

///|
test "answers.vote が無ければ MissingField" {
  expect_response_error(
    (
      #|{"answers": {"other": {}}}
    ),
    "MissingField(\"answers.vote\")",
  )
}

///|
test "type が choice でなければ TypeMismatch" {
  expect_response_error(
    (
      #|{"answers": {"vote": {"type": "score", "choice": "a", "probabilities": {}, "confidence": 1}}}
    ),
    "TypeMismatch(\"answers.vote.type\")",
  )
}

///|
test "probabilities がオブジェクトでなければ TypeMismatch" {
  expect_response_error(
    (
      #|{"answers": {"vote": {"type": "choice", "choice": "a", "probabilities": [], "confidence": 1}}}
    ),
    "TypeMismatch(\"answers.vote.probabilities\")",
  )
}

///|
test "確率が数値でなければその key を含む TypeMismatch" {
  expect_response_error(
    (
      #|{"answers": {"vote": {"type": "choice", "choice": "a", "probabilities": {"a": "high"}, "confidence": 1}}}
    ),
    "TypeMismatch(\"answers.vote.probabilities.a\")",
  )
}

///|
test "confidence が無ければ MissingField" {
  expect_response_error(
    (
      #|{"answers": {"vote": {"type": "choice", "choice": "a", "probabilities": {"a": 1}}}}
    ),
    "MissingField(\"answers.vote.confidence\")",
  )
}

///|
test "JSON として壊れていれば InvalidJson" {
  try @lib.parse_response_text("<html>") catch {
    e => assert_true(e is @lib.ResponseError::InvalidJson(_))
  } noraise {
    _ => fail("壊れた JSON は失敗するはず")
  }
}
