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
