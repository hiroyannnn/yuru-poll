///|
/// YouTube Live チャットを Data API v3（API キー、公開ライブなら OAuth 不要）でポーリングする Source。
/// `pollingIntervalMillis` と `min_interval_ms` の大きい方の間隔で差分取得し、クォータを節約する。
pub struct YouTubeSource {
  video_id : String
  api_key : String
  /// ポーリング間隔の下限（ミリ秒）
  min_interval_ms : Int
  /// エラー時に再試行するまでの待ち（ミリ秒）
  retry_interval_ms : Int
}

///|
pub fn YouTubeSource::new(
  video_id : String,
  api_key : String,
  min_interval_ms? : Int = @lib.DEFAULT_POLLING_INTERVAL_MS,
  retry_interval_ms? : Int = 15000,
) -> YouTubeSource {
  { video_id, api_key, min_interval_ms, retry_interval_ms, }
}

///|
pub impl @lib.Source for YouTubeSource with fn run(self, submit) {
  let live_chat_id = self.fetch_live_chat_id() catch {
    err => {
      @runtime.log(
        "youtube: ライブチャット ID の取得に失敗: \{err}",
      )
      return
    }
  }
  @runtime.log(
    "youtube: \{self.video_id} のチャット \{live_chat_id} を購読します",
  )
  let mut page_token : String? = None
  while true {
    let page = self.fetch_page(live_chat_id, page_token) catch {
      err => {
        @runtime.log(
          "youtube: 取得に失敗、\{self.retry_interval_ms}ms 後に再試行: \{err}",
        )
        @async.sleep(self.retry_interval_ms)
        continue
      }
    }
    for comment in page.comments {
      let stamped = { ..comment, at: @env.now().reinterpret_as_int64(), }
      (submit(stamped) |> ignore) catch {
        err => @runtime.log("youtube: 判定に失敗: \{err}")
      }
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
priv suberror YouTubeHttpError {
  HttpStatus(Int, String)
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
async fn YouTubeSource::fetch_live_chat_id(self : YouTubeSource) -> String {
  let json = self.fetch_json(@lib.videos_list_url(self.video_id, self.api_key))
  @lib.parse_live_chat_id(json)
}

///|
async fn YouTubeSource::fetch_page(
  self : YouTubeSource,
  live_chat_id : String,
  page_token : String?,
) -> @lib.LiveChatPage {
  let json = self.fetch_json(
    @lib.live_chat_messages_url(live_chat_id, self.api_key, page_token),
  )
  @lib.parse_live_chat_page(json)
}
