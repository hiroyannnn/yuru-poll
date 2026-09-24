///|
/// yuru-poll の判定。送信と一時的な失敗の再試行は yuru-kit の JevClient に任せ、
/// ここでは poll の質問の組み立てと、応答の解釈だけを行う。
pub suberror JevError {
  /// 応答は JSON だが、期待した形ではない
  BadResponse(@lib.ResponseError)
} derive(Debug)

///|
pub struct JevClient {
  transport : @kit_jev.JevClient
}

///|
/// 環境変数 JEV_URL / JEV_API_KEY / JEV_MODEL から作る。
pub fn JevClient::from_env() -> JevClient {
  { transport: @kit_jev.JevClient::from_env(), }
}

///|
pub fn JevClient::new(transport : @kit_jev.JevClient) -> JevClient {
  { transport, }
}

///|
/// 1 発言を判定する。
pub async fn JevClient::judge(
  self : JevClient,
  poll : @lib.Poll,
  comment : @lib.Comment,
) -> @lib.Judgement {
  let request = @lib.build_request(
    poll,
    comment.text,
    model=self.transport.model,
  )
  let response = self.transport.systemone(request)
  @lib.parse_response(response) catch {
    err => raise BadResponse(err)
  }
}

///|
/// runtime に注入する判定関数の形にする。
pub fn JevClient::judge_fn(
  self : JevClient,
) -> async (@lib.Poll, @lib.Comment) -> @lib.Judgement {
  (poll, comment) => self.judge(poll, comment)
}
