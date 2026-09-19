///|
/// JEV_URL が無いときの既定（ローカルの open-jev）。
pub const DEFAULT_URL : String = "http://127.0.0.1:8000"

///|
/// JEV_API_KEY が無いときの既定。
pub const DEFAULT_API_KEY : String = "local"

///|
pub suberror JevError {
  /// 200 以外のステータス（コード, 本文）
  HttpStatus(Int, String)
  /// 本文が JSON として壊れている
  InvalidJson(String)
  /// JSON だが期待した形ではない
  BadResponse(@lib.ResponseError)
} derive(Debug)

///|
/// TypeSafe Jev 互換 API（`POST /v1/systemone`）のクライアント。
pub struct JevClient {
  base_url : String
  api_key : String
  /// リクエストに載せるモデル名（JEV_MODEL。Vercel AI Gateway では `typesafe-ai/jev`）
  model : String
}

///|
pub fn JevClient::new(
  base_url? : String = DEFAULT_URL,
  api_key? : String = DEFAULT_API_KEY,
  model? : String = @lib.JEV_MODEL,
) -> JevClient {
  { base_url: base_url.trim_end(chars="/").to_owned(), api_key, model, }
}

///|
/// 環境変数 JEV_URL / JEV_API_KEY から作る。
pub fn JevClient::from_env() -> JevClient {
  JevClient::new(
    base_url=@env.get_env_var("JEV_URL").unwrap_or(DEFAULT_URL),
    api_key=@env.get_env_var("JEV_API_KEY").unwrap_or(DEFAULT_API_KEY),
    model=@env.get_env_var("JEV_MODEL").unwrap_or(@lib.JEV_MODEL),
  )
}

///|
/// 1 発言を判定する。
pub async fn JevClient::judge(
  self : JevClient,
  poll : @lib.Poll,
  comment : @lib.Comment,
) -> @lib.Judgement {
  let headers : @http.Headers = Map::from_array([
    (@http.CaseInsensitiveString("Authorization"), "Bearer \{self.api_key}"),
    (@http.CaseInsensitiveString("Content-Type"), "application/json"),
  ])
  let body = @lib.build_request(poll, comment.text, model=self.model).stringify()
  let (response, data) = @http.post(
    "\{self.base_url}/v1/systemone",
    body,
    headers~,
  )
  if response.code != 200 {
    raise HttpStatus(response.code, data.text())
  }
  let json = data.json() catch { err => raise InvalidJson(err.to_string()) }
  @lib.parse_response(json) catch {
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
