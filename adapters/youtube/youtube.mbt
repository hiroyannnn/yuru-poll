///|
/// YouTube Live チャットを読む Source。yuru-come（同じ作者、Apache-2.0）から移植。
///
/// - API キーが無ければ、ブラウザと同じ経路（`live_chat` ページ + `youtubei/v1/live_chat/get_live_chat`、innertube）で読む。
///   キーもクォータも要らないが非公式で、YouTube 側の変更で壊れることがある
/// - API キーがあれば Data API v3（公開ライブなら OAuth 不要）でポーリングする。
///   `pollingIntervalMillis` と `min_interval_ms` の大きい方の間隔で差分取得し、クォータを節約する
pub struct YouTubeSource {
  video_id : String
  api_key : String?
  /// ポーリング間隔の下限（ミリ秒）
  min_interval_ms : Int
  /// エラー時に再試行するまでの待ち（ミリ秒）
  retry_interval_ms : Int
}

///|
pub fn YouTubeSource::new(
  video_id : String,
  api_key? : String,
  min_interval_ms? : Int = @lib.DEFAULT_POLLING_INTERVAL_MS,
  retry_interval_ms? : Int = 15000,
) -> YouTubeSource {
  { video_id, api_key, min_interval_ms, retry_interval_ms, }
}

///|
pub impl @lib.Source for YouTubeSource with fn run(self, submit) {
  match self.api_key {
    Some(api_key) => self.run_data_api(api_key, submit)
    None => self.run_innertube(submit)
  }
}

///|
priv suberror YouTubeHttpError {
  HttpStatus(Int, String)
}

///|
/// 1 件を判定に回す。判定の失敗はログに出して次に進む。
async fn submit_one(
  submit : async (@lib.Comment) -> @lib.Judgement,
  comment : @lib.Comment,
) -> Unit {
  let stamped = if comment.at == 0 {
    { ..comment, at: @env.now().reinterpret_as_int64(), }
  } else {
    comment
  }
  (submit(stamped) |> ignore) catch {
    err => @runtime.log("youtube: 判定に失敗: \{err}")
  }
}

///|
/// ブラウザに見せるためのヘッダ。
fn browser_headers() -> @http.Headers {
  Map::from_array([
    (
      @http.CaseInsensitiveString("User-Agent"),
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36",
    ),
    (@http.CaseInsensitiveString("Accept-Language"), "ja"),
    (@http.CaseInsensitiveString("Cookie"), "CONSENT=YES+1"),
  ])
}

///|
/// キー無しの経路。live_chat ページから継続トークンを取り、切れるまで get_live_chat を回す。
async fn YouTubeSource::run_innertube(
  self : YouTubeSource,
  submit : async (@lib.Comment) -> @lib.Judgement,
) -> Unit {
  let config = self.fetch_innertube_config() catch {
    err => {
      @runtime.log(
        "youtube: \{self.video_id} のチャットページを読めません（キー無し経路）: \{err}",
      )
      return
    }
  }
  @runtime.log(
    "youtube: \{self.video_id} のチャットをキー無しで購読します（クライアント \{config.client_version}）",
  )
  let mut continuation = config.continuation
  let headers = browser_headers()
  headers[@http.CaseInsensitiveString("Content-Type")] = "application/json"
  while true {
    let page = self.fetch_innertube_page(config, continuation, headers) catch {
      err => {
        @runtime.log(
          "youtube: 取得に失敗、\{self.retry_interval_ms}ms 後に再試行: \{err}",
        )
        @async.sleep(self.retry_interval_ms)
        continue
      }
    }
    for comment in page.comments {
      submit_one(submit, comment)
    }
    guard page.next_page_token is Some(next) else {
      @runtime.log(
        "youtube: \{self.video_id} のチャットが終わりました",
      )
      return
    }
    continuation = next
    @async.sleep(
      if page.polling_interval_ms < 1000 {
        1000
      } else {
        page.polling_interval_ms
      },
    )
  }
}

///|
async fn YouTubeSource::fetch_innertube_config(
  self : YouTubeSource,
) -> @lib.InnertubeConfig {
  let (response, body) = @http.get(
    "https://www.youtube.com/live_chat?v=\{self.video_id}",
    headers=browser_headers(),
  )
  if response.code != 200 {
    raise YouTubeHttpError::HttpStatus(response.code, body.text())
  }
  @lib.parse_live_chat_page_html(body.text())
}

///|
async fn YouTubeSource::fetch_innertube_page(
  _self : YouTubeSource,
  config : @lib.InnertubeConfig,
  continuation : String,
  headers : @http.Headers,
) -> @lib.LiveChatPage {
  let (response, body) = @http.post(
    @lib.innertube_live_chat_url(config),
    @lib.innertube_live_chat_body(config, continuation).stringify(),
    headers~,
  )
  if response.code != 200 {
    raise YouTubeHttpError::HttpStatus(response.code, body.text())
  }
  @lib.parse_get_live_chat(body.json())
}

///|
/// Data API v3 の経路。
async fn YouTubeSource::run_data_api(
  self : YouTubeSource,
  api_key : String,
  submit : async (@lib.Comment) -> @lib.Judgement,
) -> Unit {
  let live_chat_id = self.fetch_live_chat_id(api_key) catch {
    err => {
      @runtime.log(
        "youtube: ライブチャット ID の取得に失敗: \{err}",
      )
      return
    }
  }
  @runtime.log(
    "youtube: \{self.video_id} のチャット \{live_chat_id} を Data API で購読します",
  )
  let mut page_token : String? = None
  while true {
    let page = self.fetch_page(api_key, live_chat_id, page_token) catch {
      err => {
        @runtime.log(
          "youtube: 取得に失敗、\{self.retry_interval_ms}ms 後に再試行: \{err}",
        )
        @async.sleep(self.retry_interval_ms)
        continue
      }
    }
    for comment in page.comments {
      submit_one(submit, comment)
    }
    page_token = page.next_page_token
    let wait = if page.polling_interval_ms > self.min_interval_ms {
      page.polling_interval_ms
    } else {
      self.min_interval_ms
    }
    @async.sleep(wait)
  }
}

///|
async fn YouTubeSource::fetch_json(_self : YouTubeSource, url : String) -> Json {
  let (response, body) = @http.get(url)
  if response.code != 200 {
    raise YouTubeHttpError::HttpStatus(response.code, body.text())
  }
  body.json()
}

///|
async fn YouTubeSource::fetch_live_chat_id(
  self : YouTubeSource,
  api_key : String,
) -> String {
  let json = self.fetch_json(@lib.videos_list_url(self.video_id, api_key))
  @lib.parse_live_chat_id(json)
}

///|
async fn YouTubeSource::fetch_page(
  self : YouTubeSource,
  api_key : String,
  live_chat_id : String,
  page_token : String?,
) -> @lib.LiveChatPage {
  let json = self.fetch_json(
    @lib.live_chat_messages_url(live_chat_id, api_key, page_token),
  )
  @lib.parse_live_chat_page(json)
}
