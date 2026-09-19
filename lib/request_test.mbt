///|
let request_poll_json : String =
  #|{
  #|  "question": "次のゲーム何やる？",
  #|  "choices": [
  #|    {"key": "factorio", "label": "Factorio", "description": "工場、自動化、ベルトの話"},
  #|    {"key": "splatoon", "label": "スプラトゥーン", "description": "塗り、対戦、イカ"}
  #|  ]
  #|}

///|
test "build_request は state に質問文と発言、criteria に選択肢を入れた choice 質問 1 個を作る" {
  let poll = @lib.Poll::parse(request_poll_json)
  let request = @lib.build_request(poll, "たぶんファクトリオかな")
  json_inspect(request, content={
    "state": {
      "question": "次のゲーム何やる？",
      "comment": "たぶんファクトリオかな",
    },
    "model": "jev-latest",
    "questions": {
      "vote": {
        "type": "choice",
        "instructions": "この発言は投票の回答です。どの選択肢を支持しているか？「〜はない」「〜は嫌」のような否定はその選択肢への支持ではない。迷っている・雑談・挨拶なら none。",
        "criteria": {
          "factorio": "Factorio: 工場、自動化、ベルトの話",
          "splatoon": "スプラトゥーン: 塗り、対戦、イカ",
          "none": "どれでもない: どれも支持していない、雑談、意味不明",
        },
      },
    },
  })
}

///|
test "description が空なら criteria は label だけになる" {
  let text =
    #|{"question": "Q", "choices": [{"key": "a", "label": "A"}]}
  let poll = @lib.Poll::parse(text)
  let request = @lib.build_request(poll, "x")
  guard request
    is Object(
      {
        "questions": Object(
          { "vote": Object({ "criteria": Object(criteria), .. }), .. }
        ),
        ..
      }
    ) else {
    fail("criteria が見つからない")
  }
  json_inspect(Json::object(criteria), content={
    "a": "A",
    "none": "どれでもない: どれも支持していない、雑談、意味不明",
  })
}

///|
test "build_request の JSON は文字列化して再パースしても同じ" {
  let poll = @lib.Poll::parse(request_poll_json)
  let request = @lib.build_request(poll, "Bはないわ")
  let text = request.stringify()
  assert_eq(@json.parse(text), request)
}

///|
test "build_request は model を差し替えられる（Vercel AI Gateway では typesafe-ai/jev）" {
  let poll = @lib.Poll::parse(request_poll_json)
  let default_request = @lib.build_request(poll, "x")
  guard default_request is Object({ "model": String(default_model), .. }) else {
    fail("model があるはず")
  }
  inspect(default_model, content="jev-latest")
  let request = @lib.build_request(poll, "x", model="typesafe-ai/jev")
  guard request is Object({ "model": String(model), .. }) else {
    fail("model があるはず")
  }
  inspect(model, content="typesafe-ai/jev")
}

///|
test "poll に instructions があれば、既定の指示文の代わりに使う" {
  let text =
    #|{"question": "Q", "instructions": "この発言はどれを推しているか？", "choices": [{"key": "a", "label": "A"}]}
  let poll = @lib.Poll::parse(text)
  debug_inspect(
    poll.instructions,
    content="Some(\"この発言はどれを推しているか？\")",
  )
  guard @lib.build_request(poll, "x")
    is Object(
      {
        "questions": Object(
          { "vote": Object({ "instructions": String(sent), .. }), .. }
        ),
        ..
      }
    ) else {
    fail("instructions があるはず")
  }
  inspect(sent, content="この発言はどれを推しているか？")
  let default_poll = @lib.Poll::parse(request_poll_json)
  debug_inspect(default_poll.instructions, content="None")
}

///|
test "instructions が文字列でなければ TypeMismatch、空文字は既定に戻す" {
  let bad =
    #|{"question": "Q", "instructions": 1, "choices": [{"key": "a", "label": "A"}]}
  try @lib.Poll::parse(bad) catch {
    e => debug_inspect(e, content="TypeMismatch(\"instructions\")")
  } noraise {
    _ => fail("失敗するはず")
  }
  let empty =
    #|{"question": "Q", "instructions": "  ", "choices": [{"key": "a", "label": "A"}]}
  debug_inspect(@lib.Poll::parse(empty).instructions, content="None")
}
