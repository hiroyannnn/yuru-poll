///|
/// JS 側から渡される判定関数。リクエスト JSON を受け取り、レスポンス JSON の Promise を返す。
/// Cloudflare では `env.AI.run('typesafe/jev', ...)` か HTTP の Jev API を包んだ関数が渡される。
#external
pub type JsJudge

///|
extern "js" fn JsJudge::call(
  self : JsJudge,
  request : String,
) -> @js_async.Promise[String] =
  #|(judge, request) => judge(request)

///|
/// Workers の受け口。JS グルーは Workers の API から集めた値を文字列と数値で渡し、
/// 返ってきた JSON（`Reply::to_json_text` の形）を Response にするだけ。
/// `now_ms` は JS の Date.now()（Double）で受け取る。
pub fn room_handle(
  room : Room,
  meth : String,
  path : String,
  body : String,
  join_url : String,
  model : String,
  now_ms : Double,
  client : String,
  token : String,
  judge : JsJudge,
) -> @js_async.Promise[String] {
  let ctx : Context = {
    join_url,
    model,
    now_ms: now_ms.to_int64(),
    client,
    token,
  }
  @js_async.Promise::from_async(() => {
    let reply = route(
      room,
      meth,
      path,
      body,
      request => judge.call(request).wait(),
      ctx,
    ) catch {
      err =>
        failure(500, "内部エラーが起きました", log="route: \{err}")
    }
    reply.to_json_text()
  })
}

///|
/// ルーム作成の回数制限など、ルームの外で使うレート制限器を JS から使うための出入口。
pub fn limiter_new(limit : Int, window_ms : Double) -> @lib.RateLimiter {
  @lib.RateLimiter::new(limit~, window_ms=window_ms.to_int64())
}

///|
pub fn limiter_allow(
  limiter : @lib.RateLimiter,
  key : String,
  now_ms : Double,
) -> Bool {
  limiter.allow(key, now_ms.to_int64())
}
