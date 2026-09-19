///|
let poll_json : String =
  #|{"question": "Q", "choices": [
  #|  {"key": "a", "label": "A", "description": "aaa"},
  #|  {"key": "b", "label": "B", "description": "bbb"}
  #|]}

///|
/// 発言に "A" があれば a、無ければ b と答える偽の Jev。受け取ったリクエストを記録する。
fn fake_judge(seen : Array[String]) -> async (String) -> String {
  async fn(request) {
    seen.push(request)
    @async.sleep(1)
    if request.contains("A かな") {
      (
        #|{"answers": {"vote": {"type": "choice", "choice": "a", "probabilities": {"a": 0.7, "b": 0.2, "none": 0.1}, "confidence": 0.6}}}
      )
    } else {
      (
        #|{"answers": {"vote": {"type": "choice", "choice": "b", "probabilities": {"a": 0, "b": 1, "none": 0}, "confidence": 0.9}}}
      )
    }
  }
}

///|
suberror JudgeDown

///|
async fn request(
  room : @worker.Room,
  meth : String,
  path : String,
  body? : String = "",
  judge? : async (String) -> String = fake_judge([]),
) -> @worker.Reply {
  @worker.route(
    room,
    meth,
    path,
    body,
    judge,
    join_url="https://example.test/r/x/join",
  )
}

///|
async fn created_room() -> @worker.Room {
  let room = @worker.room_new()
  let reply = request(room, "POST", "/api/room", body=poll_json)
  assert_eq(reply.status, 200)
  room
}

///|
async test "POST /api/room でルームを作ると poll が返り、保存用の state が付く" {
  let room = @worker.room_new()
  let reply = request(room, "POST", "/api/room", body=poll_json)
  inspect(reply.status, content="200")
  assert_true(reply.state is Some(_))
  guard @json.parse(reply.body) is Object({ "question": String(q), .. }) else {
    fail("poll が返るはず")
  }
  inspect(q, content="Q")
  inspect(request(room, "GET", "/api/poll").status, content="200")
}

///|
async test "ルーム作成前は 404、二重作成は 409、壊れた poll は 400" {
  let room = @worker.room_new()
  inspect(request(room, "GET", "/api/poll").status, content="404")
  inspect(
    request(room, "POST", "/api/comment", body="{}").status,
    content="404",
  )
  inspect(
    request(room, "POST", "/api/room", body="{\"question\": \"Q\"}").status,
    content="400",
  )
  inspect(
    request(room, "POST", "/api/room", body=poll_json).status,
    content="200",
  )
  inspect(
    request(room, "POST", "/api/room", body=poll_json).status,
    content="409",
  )
}

///|
async test "POST /api/comment は判定して集計し、判定・集計・state を返す" {
  let room = created_room()
  let seen : Array[String] = []
  let reply = request(
    room,
    "POST",
    "/api/comment",
    body="{\"participant_id\": \"p1\", \"comment\": \"  A かな \"}",
    judge=fake_judge(seen),
  )
  inspect(reply.status, content="200")
  inspect(seen.length(), content="1")
  guard @json.parse(seen[0])
    is Object({ "state": Object({ "comment": String(sent), .. }), .. }) else {
    fail("判定リクエストに発言が入るはず")
  }
  inspect(sent, content="A かな")
  guard @json.parse(reply.body)
    is Object(
      {
        "judgement": Object({ "choice": String(choice), .. }),
        "snapshot": Object({ "participants": Number(n, ..), .. }),
        ..
      }
    ) else {
    fail("judgement と snapshot が返るはず")
  }
  inspect(choice, content="a")
  inspect(n, content="1")
  assert_true(reply.state is Some(_))
}

///|
async test "同じ参加者の言い直しは上書きされ、tally に最新の発言が載る" {
  let room = created_room()
  request(
    room,
    "POST",
    "/api/comment",
    body="{\"participant_id\": \"p1\", \"comment\": \"A かな\"}",
  )
  |> ignore
  request(
    room,
    "POST",
    "/api/comment",
    body="{\"participant_id\": \"p1\", \"comment\": \"やっぱり\"}",
  )
  |> ignore
  let tally = request(room, "GET", "/api/tally")
  inspect(tally.status, content="200")
  assert_true(tally.state is None)
  guard @json.parse(tally.body)
    is Object(
      {
        "snapshot": Object(
          {
            "participants": Number(n, ..),
            "totals": Object({ "b": Number(b, ..), .. }),
            ..
          }
        ),
        "last": Object(
          {
            "comment": Object(
              { "text": String(text), "participant_id": String(pid), .. }
            ),
            ..
          }
        ),
        ..
      }
    ) else {
    fail("snapshot と last が返るはず")
  }
  inspect(n, content="1")
  inspect(b, content="1")
  inspect(text, content="やっぱり")
  inspect(pid, content="web:p1")
}

///|
async test "不正な発言は 400、長すぎる発言は 413、判定の失敗は 502" {
  let room = created_room()
  inspect(
    request(room, "POST", "/api/comment", body="oops").status,
    content="400",
  )
  inspect(
    request(
      room,
      "POST",
      "/api/comment",
      body="{\"participant_id\": \"p\", \"comment\": \"   \"}",
    ).status,
    content="400",
  )
  let long = "あ".repeat(201)
  inspect(
    request(
      room,
      "POST",
      "/api/comment",
      body="{\"participant_id\": \"p\", \"comment\": \"\{long}\"}",
    ).status,
    content="413",
  )
  let down = async fn(_request : String) -> String {
    @async.pause()
    raise JudgeDown
  }
  let reply = request(
    room,
    "POST",
    "/api/comment",
    body="{\"participant_id\": \"p\", \"comment\": \"A かな\"}",
    judge=down,
  )
  inspect(reply.status, content="502")
  assert_true(reply.state is None)
  guard @json.parse(request(room, "GET", "/api/tally").body)
    is Object({ "snapshot": Object({ "participants": Number(n, ..), .. }), .. }) else {
    fail("snapshot が返るはず")
  }
  inspect(n, content="0")
}

///|
async test "state から復元したルームは同じ集計を返す" {
  let room = created_room()
  let reply = request(
    room,
    "POST",
    "/api/comment",
    body="{\"participant_id\": \"p1\", \"comment\": \"A かな\"}",
  )
  guard reply.state is Some(state) else { fail("state が付くはず") }
  let restored = @worker.room_new()
  inspect(@worker.room_restore(restored, state), content="")
  assert_eq(
    request(restored, "GET", "/api/tally").body.contains("\"participants\":1"),
    true,
  )
  inspect(
    @worker.room_restore(@worker.room_new(), "{broken"),
    content="state を復元できません: InvalidJson",
  )
}

///|
async test "join-url と qr.svg、未知のパス" {
  let room = created_room()
  let join = request(room, "GET", "/api/join-url")
  inspect(
    join.body,
    content="{\"url\":\"https://example.test/r/x/join\",\"accept_comments\":true}",
  )
  let qr = request(room, "GET", "/api/qr.svg")
  inspect(qr.content_type, content="image/svg+xml")
  assert_true(qr.body.contains("<svg"))
  inspect(request(room, "GET", "/api/nope").status, content="404")
  inspect(request(room, "DELETE", "/api/poll").status, content="404")
}

///|
async test "Reply::to_json_text は JS グルーが読む形になる" {
  let room = created_room()
  let reply = request(room, "GET", "/api/join-url")
  guard @json.parse(reply.to_json_text())
    is Object(
      {
        "status": Number(status, ..),
        "content_type": String(ct),
        "body": String(_),
        "state": Null,
        ..
      }
    ) else {
    fail("status / content_type / body / state を持つはず")
  }
  inspect(status, content="200")
  inspect(ct, content="application/json; charset=utf-8")
}

///|
async test "route は model を指定でき、判定リクエストに載る（空なら既定値）" {
  let room = created_room()
  let seen : Array[String] = []
  let body = "{\"participant_id\": \"p1\", \"comment\": \"A かな\"}"
  @worker.route(
    room,
    "POST",
    "/api/comment",
    body,
    fake_judge(seen),
    join_url="",
    model="typesafe-ai/jev",
  )
  |> ignore
  @worker.route(
    room,
    "POST",
    "/api/comment",
    body,
    fake_judge(seen),
    join_url="",
    model="",
  )
  |> ignore
  assert_true(seen[0].contains("\"model\":\"typesafe-ai/jev\""))
  assert_true(seen[1].contains("\"model\":\"jev-latest\""))
}
