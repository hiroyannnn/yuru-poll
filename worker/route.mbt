///|
/// 発言の最大文字数。これを超えたら 413。
pub const MAX_COMMENT_CHARS : Int = 200

///|
/// poll JSON の最大文字数。
pub const MAX_POLL_CHARS : Int = 16000

///|
/// 1 ルーム分の状態。Cloudflare では Durable Object 1 個が 1 つ持つ。
pub struct Room {
  mut engine : @lib.Engine?
  mut last : @lib.Update?
}

///|
/// JS グルーに返す応答。`state` があれば、グルーはそれを永続ストレージに保存する。
pub struct Reply {
  status : Int
  content_type : String
  body : String
  state : String?
}

///|
const JSON_TYPE : String = "application/json; charset=utf-8"

///|
pub fn room_new() -> Room {
  { engine: None, last: None, }
}

///|
/// 保存してあった state からルームを復元する。成功なら空文字、失敗ならエラー文を返す。
pub fn room_restore(room : Room, state : String) -> String {
  let json = @json.parse(state) catch {
    _ => return "state を復元できません: InvalidJson"
  }
  room.engine = Some(
    @lib.Engine::restore(json) catch {
      err => return "state を復元できません: \{@debug.to_string(err)}"
    },
  )
  room.last = None
  ""
}

///|
pub fn Reply::to_json_text(self : Reply) -> String {
  let state : Json = match self.state {
    Some(s) => Json::string(s)
    None => Json::null()
  }
  let json : Json = {
    "status": self.status,
    "content_type": self.content_type,
    "body": self.body,
    "state": state,
  }
  json.stringify()
}

///|
fn ok(json : Json, state? : String) -> Reply {
  { status: 200, content_type: JSON_TYPE, body: json.stringify(), state, }
}

///|
fn failure(status : Int, message : String) -> Reply {
  let json : Json = { "error": message }
  { status, content_type: JSON_TYPE, body: json.stringify(), state: None, }
}

///|
/// ルーム内の API を処理する。パスは native 版のウェブサーバと同じ（`/api/poll` など）。
/// `judge` は判定リクエストの JSON を受け取り、レスポンスの JSON を返す（差し替え可能）。
pub async fn route(
  room : Room,
  meth : String,
  path : String,
  body : String,
  judge : async (String) -> String,
  join_url~ : String,
  model? : String = "",
) -> Reply {
  if meth == "POST" && path == "/api/room" {
    return create_room(room, body)
  }
  guard room.engine is Some(engine) else {
    return failure(404, "このルームはまだ作られていません")
  }
  match (meth, path) {
    ("GET", "/api/poll") => ok(ToJson::to_json(engine.poll))
    ("GET", "/api/tally") => ok(tally_json(room, engine))
    ("GET", "/api/join-url") => ok({ "url": join_url, "accept_comments": true })
    ("GET", "/api/qr.svg") =>
      match @lib.qr_svg(join_url) {
        Some(svg) =>
          {
            status: 200,
            content_type: "image/svg+xml",
            body: svg,
            state: None,
          }
        None => failure(500, "QR を生成できません")
      }
    ("POST", "/api/comment") => comment(room, engine, body, judge, model)
    _ => failure(404, "not found")
  }
}

///|
fn create_room(room : Room, body : String) -> Reply {
  if room.engine is Some(_) {
    return failure(409, "このルームは既に作られています")
  }
  if body.length() > MAX_POLL_CHARS {
    return failure(413, "poll が大きすぎます")
  }
  let poll = @lib.Poll::parse(body) catch {
    err =>
      return failure(400, "poll を読めません: \{@debug.to_string(err)}")
  }
  let engine = @lib.Engine::new(poll)
  room.engine = Some(engine)
  ok(ToJson::to_json(poll), state=engine.dump().stringify())
}

///|
fn tally_json(room : Room, engine : @lib.Engine) -> Json {
  let last : Json = match room.last {
    Some(update) =>
      {
        "comment": ToJson::to_json(update.comment),
        "judgement": ToJson::to_json(update.judgement),
      }
    None => Json::null()
  }
  { "snapshot": ToJson::to_json(engine.snapshot()), "last": last }
}

///|
async fn comment(
  room : Room,
  engine : @lib.Engine,
  body : String,
  judge : async (String) -> String,
  model : String,
) -> Reply {
  let json = @json.parse(body) catch {
    _ => return failure(400, "JSON が不正です")
  }
  guard json
    is Object(
      { "participant_id": String(participant_id), "comment": String(raw), .. }
    ) else {
    return failure(400, "participant_id と comment が必要です")
  }
  let text = raw.trim(chars=" \t\r\n").to_owned()
  if text.is_empty() || participant_id.is_empty() {
    return failure(400, "発言が空です")
  }
  if text.length() > MAX_COMMENT_CHARS || participant_id.length() > 64 {
    return failure(
      413,
      "発言が長すぎます（\{MAX_COMMENT_CHARS} 文字まで）",
    )
  }
  // 空ならコアの既定値（jev-latest）を使う
  let request_json = if model.is_empty() {
    @lib.build_request(engine.poll, text)
  } else {
    @lib.build_request(engine.poll, text, model~)
  }
  let request = request_json.stringify()
  let response = judge(request) catch {
    err =>
      return failure(502, "判定サーバに接続できません: \{err}")
  }
  let judgement = @lib.parse_response_text(response) catch {
    err =>
      return failure(
        502,
        "判定結果を読めません: \{@debug.to_string(err)}",
      )
  }
  let update = engine.apply(
    { participant_id: @lib.participant_id("web", participant_id), text, at: 0, },
    judgement,
  )
  room.last = Some(update)
  ok(
    {
      "judgement": ToJson::to_json(update.judgement),
      "snapshot": ToJson::to_json(update.snapshot),
    },
    state=engine.dump().stringify(),
  )
}
