///|
/// JS 側から渡される判定関数。リクエスト JSON を受け取り、レスポンス JSON の Promise を返す。
/// Cloudflare では `env.AI.run('typesafe/jev', ...)` を包んだ関数が渡される。
#external
pub type JsJudge

///|
extern "js" fn JsJudge::call(
  self : JsJudge,
  request : String,
) -> @js_async.Promise[String] =
  #|(judge, request) => judge(request)

///|
/// Workers の受け口。JS グルーは method / path / body を文字列で渡し、
/// 返ってきた JSON（`Reply::to_json_text` の形）を Response にするだけ。
pub fn room_handle(
  room : Room,
  meth : String,
  path : String,
  body : String,
  join_url : String,
  judge : JsJudge,
) -> @js_async.Promise[String] {
  @js_async.Promise::from_async(() => {
    let reply = route(
      room,
      meth,
      path,
      body,
      request => judge.call(request).wait(),
      join_url~,
    ) catch {
      err => failure(500, "内部エラー: \{err}")
    }
    reply.to_json_text()
  })
}
