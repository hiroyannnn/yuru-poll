///|
/// YouTube Data API v3 のレスポンス解釈エラー。
pub suberror YouTubeError {
  VideoNotFound
  NotLive
  TypeMismatch(String)
} derive(Debug, Eq)

///|
/// `liveChatMessages.list` の 1 ページ分。
pub(all) struct LiveChatPage {
  comments : Array[Comment]
  next_page_token : String?
  /// API が指示するポーリング間隔（ミリ秒）。無ければ既定値
  polling_interval_ms : Int
} derive(Debug)

///|
/// pollingIntervalMillis が無いときの既定値（クォータ節約のため長め）。
pub const DEFAULT_POLLING_INTERVAL_MS : Int = 5000

///|
/// `videos.list(part=liveStreamingDetails)` の URL。
pub fn videos_list_url(video_id : String, api_key : String) -> String {
  "https://www.googleapis.com/youtube/v3/videos?part=liveStreamingDetails&id=\{video_id}&key=\{api_key}"
}

///|
/// `liveChatMessages.list(part=snippet,authorDetails)` の URL。
pub fn live_chat_messages_url(
  live_chat_id : String,
  api_key : String,
  page_token : String?,
) -> String {
  let base = "https://www.googleapis.com/youtube/v3/liveChat/messages?liveChatId=\{live_chat_id}&part=snippet,authorDetails&maxResults=200&key=\{api_key}"
  match page_token {
    Some(token) => "\{base}&pageToken=\{token}"
    None => base
  }
}

///|
/// `videos.list` のレスポンスから activeLiveChatId を取り出す。
pub fn parse_live_chat_id(json : Json) -> String raise YouTubeError {
  guard json is Object(root) else { raise TypeMismatch("response") }
  let items = match root.get("items") {
    Some(Array(items)) => items
    _ => raise TypeMismatch("items")
  }
  guard items is [first, ..] else { raise VideoNotFound }
  match first {
    Object(
      {
        "liveStreamingDetails": Object({ "activeLiveChatId": String(id), .. }),
        ..
      }
    ) => id
    _ => raise NotLive
  }
}

///|
/// `liveChatMessages.list` のレスポンスを分解する。
/// displayMessage の無い項目（メンバー加入通知など）は読み飛ばす。
pub fn parse_live_chat_page(json : Json) -> LiveChatPage raise YouTubeError {
  guard json is Object(root) else { raise TypeMismatch("response") }
  let items = match root.get("items") {
    None => []
    Some(Array(items)) => items
    Some(_) => raise TypeMismatch("items")
  }
  let comments : Array[Comment] = []
  for item in items {
    match item {
      Object(
        {
          "snippet": Object({ "displayMessage": String(text), .. }),
          "authorDetails": Object({ "channelId": String(channel_id), .. }),
          ..
        }
      ) =>
        comments.push({
          participant_id: participant_id("youtube", channel_id),
          text,
          at: 0,
        })
      _ => ()
    }
  }
  let next_page_token = match root.get("nextPageToken") {
    Some(String(token)) => Some(token)
    _ => None
  }
  let polling_interval_ms = match root.get("pollingIntervalMillis") {
    Some(Number(n, ..)) => n.to_int()
    _ => DEFAULT_POLLING_INTERVAL_MS
  }
  { comments, next_page_token, polling_interval_ms, }
}
