///|
/// ウェブフォーム（Source）と司会者画面・OBS オーバーレイ（Sink）を提供する HTTP サーバ。
///
/// - `GET /`         司会者用の結果画面（`/api/tally` を 2 秒ごとにポーリング、参加 URL と QR）
/// - `GET /join`     参加者用ページ（発言を送ると解釈された分布が返る）
/// - `GET /overlay`  OBS ブラウザソース用（背景透過、棒グラフだけ）
/// - `GET /api/poll` 質問と選択肢
/// - `GET /api/tally` 集計 JSON（最新の発言と判定を含む）
/// - `GET /api/join-url` 参加用 URL、`GET /api/qr.svg` その QR コード
/// - `POST /api/comment` `{participant_id, comment}` を判定して分布を返す
pub struct WebServer {
  engine : @lib.Engine
  port : Int
  web_dir : String
  public_url : String?
  /// `--source web` のときだけ発言を受け付ける
  accept_comments : Bool
  mut latest : @lib.Update?
  mut join_url : String
}

///|
pub fn WebServer::new(
  engine : @lib.Engine,
  port? : Int = 8787,
  web_dir? : String = "web",
  public_url? : String,
  accept_comments? : Bool = true,
) -> WebServer {
  {
    engine,
    port,
    web_dir,
    public_url,
    accept_comments,
    latest: None,
    join_url: "",
  }
}

///|
/// Sink として最新の Update を覚えておき、`/api/tally` に載せる。
pub impl @lib.Sink for WebServer with fn on_update(self, update) {
  self.latest = Some(update)
}

///|
/// Source として HTTP サーバを起動し、`POST /api/comment` の発言を `submit` に流す。
/// サーバは止まらないので、この `run` も戻らない。
pub impl @lib.Source for WebServer with fn run(self, submit) {
  self.join_url = match self.public_url {
    Some(base) => "\{base.trim_end(chars="/")}/join"
    None => "http://\{guess_lan_ip()}:\{self.port}/join"
  }
  let server = @http.Server(@socket.Addr::parse("0.0.0.0:\{self.port}"))
  @runtime.log(
    "web: http://localhost:\{self.port}/ で司会者画面、参加用 URL は \{self.join_url}",
  )
  server.run_forever(allow_failure=true, (request, body, conn) => {
    self.handle(request, body, conn, submit)
  })
}

///|
async fn WebServer::handle(
  self : WebServer,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
  submit : async (@lib.Comment) -> @lib.Judgement,
) -> Unit {
  let path = match request.path.find("?") {
    Some(i) => request.path[:i].to_owned()
    None => request.path
  }
  match (request.meth, path) {
    (Get, "/") => self.send_static(conn, "index.html")
    (Get, "/join") => self.send_static(conn, "join.html")
    (Get, "/overlay") => self.send_static(conn, "overlay.html")
    (Get, "/api/poll") => send_json(conn, 200, self.engine.poll.to_json())
    (Get, "/api/tally") => send_json(conn, 200, self.tally_json())
    (Get, "/api/join-url") =>
      send_json(conn, 200, {
        "url": self.join_url,
        "accept_comments": self.accept_comments,
      })
    (Get, "/api/qr.svg") => {
      let svg = @qr_render.to_svg(@qrc.encode(self.join_url))
      conn.send_response(200, "OK", extra_headers=content_type("image/svg+xml"))
      conn.write(svg)
    }
    (Post, "/api/comment") => self.handle_comment(body, conn, submit)
    (Get, "/favicon.ico") => conn.send_response(204, "No Content")
    _ => send_json(conn, 404, { "error": "not found" })
  }
}

///|
/// 集計 JSON。Sink として最新の Update を受け取っていればそれも載せる。
fn WebServer::tally_json(self : WebServer) -> Json {
  let snapshot = self.engine.snapshot().to_json()
  let last : Json = match self.latest {
    Some(update) =>
      {
        "comment": update.comment.to_json(),
        "judgement": update.judgement.to_json(),
      }
    None => Json::null()
  }
  { "snapshot": snapshot, "last": last }
}

///|
async fn WebServer::handle_comment(
  self : WebServer,
  body : &@io.Reader,
  conn : @http.ServerConnection,
  submit : async (@lib.Comment) -> @lib.Judgement,
) -> Unit {
  if !self.accept_comments {
    return send_json(conn, 403, {
      "error": "この画面からの参加は無効です（--source web が必要）",
    })
  }
  let text = body.read_all().text()
  let json = @json.parse(text) catch {
    _ => return send_json(conn, 400, { "error": "JSON が不正です" })
  }
  guard json
    is Object(
      {
        "participant_id": String(participant_id),
        "comment": String(comment_text),
        ..
      }
    ) else {
    return send_json(conn, 400, {
      "error": "participant_id と comment が必要です",
    })
  }
  let trimmed = comment_text.trim(chars=" \t\r\n").to_owned()
  if trimmed.is_empty() || participant_id.is_empty() {
    return send_json(conn, 400, { "error": "発言が空です" })
  }
  let comment : @lib.Comment = {
    participant_id: @lib.participant_id("web", participant_id),
    text: trimmed,
    at: @async.now(),
  }
  let judgement = submit(comment) catch {
    err => {
      @runtime.log("web: 判定に失敗: \{err}")
      return send_json(conn, 502, {
        "error": "判定サーバに接続できません",
      })
    }
  }
  send_json(conn, 200, {
    "judgement": judgement.to_json(),
    "snapshot": self.engine.snapshot().to_json(),
  })
}

///|
/// `web_dir` の静的ファイルを返す。毎回読むので編集が即反映される。
async fn WebServer::send_static(
  self : WebServer,
  conn : @http.ServerConnection,
  name : String,
) -> Unit {
  let data = @fs.read_file("\{self.web_dir}/\{name}") catch {
    err => {
      @runtime.log("web: \{self.web_dir}/\{name} を読めません: \{err}")
      return send_json(conn, 500, { "error": "static file not found: \{name}" })
    }
  }
  conn.send_response(
    200,
    "OK",
    extra_headers=content_type("text/html; charset=utf-8"),
  )
  conn.write(data)
}

///|
async fn send_json(
  conn : @http.ServerConnection,
  code : Int,
  json : Json,
) -> Unit {
  let reason = if code == 200 { "OK" } else { "Error" }
  conn.send_response(
    code,
    reason,
    extra_headers=content_type("application/json; charset=utf-8"),
  )
  conn.write(json.stringify())
}

///|
fn content_type(value : String) -> @http.Headers {
  Map::from_array([
    (@http.CaseInsensitiveString("Content-Type"), value),
    (@http.CaseInsensitiveString("Cache-Control"), "no-store"),
  ])
}
