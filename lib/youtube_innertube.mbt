///|
/// yuru-come（https://github.com/hiroyannnn/yuru-come、同じ作者、Apache-2.0）から移植。
/// yuru-poll の Comment は投稿者名とスタンプを持たないので、その部分を落としている。

///|
/// `youtube.com/live_chat?v=…` のページから取り出した、キー無しでチャットを読むための設定。
/// ブラウザと同じ経路（innertube）なので Data API のキーもクォータも要らないが、非公式でページ構造が変わると壊れる。
pub(all) struct InnertubeConfig {
  /// ページに埋め込まれている公開キー（`INNERTUBE_API_KEY`）
  api_key : String
  client_version : String
  /// 最初の継続トークン
  continuation : String
} derive(Debug, Eq)

///|
/// `"NAME":"value"` の形で埋め込まれた値を取り出す。
fn embedded_string(html : String, name : String) -> String? {
  let marker = "\"\{name}\":\""
  guard html.find(marker) is Some(start) else { return None }
  let rest = html[start + marker.length():]
  guard rest.find("\"") is Some(end) else { return None }
  Some(rest[:end].to_owned())
}

///|
/// `window["ytInitialData"] = {…};</script>` の JSON を取り出す。
fn initial_data(html : String) -> Json raise YouTubeError {
  let marker = "ytInitialData\"] = "
  guard html.find(marker) is Some(start) else {
    raise TypeMismatch("ytInitialData")
  }
  let rest = html[start + marker.length():]
  guard rest.find(";</script>") is Some(end) else {
    raise TypeMismatch("ytInitialData")
  }
  @json.parse(rest[:end].to_owned()) catch {
    _ => raise TypeMismatch("ytInitialData")
  }
}

///|
/// live_chat ページから innertube の設定を取り出す。
pub fn parse_live_chat_page_html(
  html : String,
) -> InnertubeConfig raise YouTubeError {
  guard embedded_string(html, "INNERTUBE_API_KEY") is Some(api_key) else {
    raise TypeMismatch("INNERTUBE_API_KEY")
  }
  guard embedded_string(html, "INNERTUBE_CLIENT_VERSION")
    is Some(client_version) else {
    raise TypeMismatch("INNERTUBE_CLIENT_VERSION")
  }
  guard initial_data(html) is Object({ "contents": Object(contents), .. }) else {
    raise TypeMismatch("ytInitialData.contents")
  }
  match contents.get("liveChatRenderer") {
    Some(Object(renderer)) =>
      match continuation_of(renderer) {
        Some((continuation, _)) => { api_key, client_version, continuation, }
        None => raise TypeMismatch("liveChatRenderer.continuations")
      }
    _ => {
      // チャットが無効・視聴者限定のときは messageRenderer に文言が入る
      let reason = match contents.get("messageRenderer") {
        Some(Object({ "text": text, .. })) => runs_text(text)
        _ => ""
      }
      raise ChatUnavailable(reason)
    }
  }
}

///|
/// `continuations[0]` から継続トークンとポーリング間隔を取り出す。
/// invalidation / timed / reload の 3 種類がある。
fn continuation_of(renderer : Map[String, Json]) -> (String, Int)? {
  guard renderer.get("continuations") is Some(Array([Object(first), ..])) else {
    return None
  }
  for
    kind in [
      "invalidationContinuationData", "timedContinuationData", "reloadContinuationData",
    ] {
    if first.get(kind)
      is Some(Object({ "continuation": String(token), .. } as data)) {
      let timeout = match data.get("timeoutMs") {
        Some(Number(n, ..)) => n.to_int()
        _ => DEFAULT_POLLING_INTERVAL_MS
      }
      return Some((token, timeout))
    }
  }
  None
}

///|
pub fn innertube_live_chat_url(config : InnertubeConfig) -> String {
  "https://www.youtube.com/youtubei/v1/live_chat/get_live_chat?key=\{config.api_key}&prettyPrint=false"
}

///|
pub fn innertube_live_chat_body(
  config : InnertubeConfig,
  continuation : String,
) -> Json {
  {
    "context": {
      "client": {
        "clientName": "WEB",
        "clientVersion": config.client_version,
        "hl": "ja",
      },
    },
    "continuation": continuation,
  }
}

///|
/// `message.runs` を本文にする。絵文字は文字そのもの、カスタム絵文字は `:name:` にする。
fn runs_text(message : Json) -> String {
  let text = StringBuilder()
  guard message is Object({ "runs": Array(runs), .. }) else { return "" }
  for run in runs {
    match run {
      Object({ "text": String(t), .. }) => text.write_string(t)
      Object({ "emoji": Object(emoji), .. }) => {
        let custom = emoji.get("isCustomEmoji") is Some(True)
        match (custom, emoji.get("shortcuts"), emoji.get("emojiId")) {
          (true, Some(Array([String(shortcut), ..])), _) =>
            text.write_string(shortcut)
          (_, _, Some(String(id))) => text.write_string(id)
          _ => ()
        }
      }
      _ => ()
    }
  }
  text.to_string()
}

///|
/// `get_live_chat` のレスポンスを分解する。
/// 通常のテキストとスーパーチャットを読み、システムメッセージやバナーは読み飛ばす。
pub fn parse_get_live_chat(json : Json) -> LiveChatPage raise YouTubeError {
  guard json
    is Object(
      {
        "continuationContents": Object(
          { "liveChatContinuation": Object(continuation), .. }
        ),
        ..
      }
    ) else {
    raise TypeMismatch("continuationContents")
  }
  let comments : Array[Comment] = []
  let actions = match continuation.get("actions") {
    Some(Array(actions)) => actions
    _ => []
  }
  for action in actions {
    guard action
      is Object(
        { "addChatItemAction": Object({ "item": Object(item), .. }), .. }
      ) else {
      continue
    }
    let renderer = match
      (
        item.get("liveChatTextMessageRenderer"),
        item.get("liveChatPaidMessageRenderer"),
      ) {
      (Some(Object(r)), _) | (_, Some(Object(r))) => r
      _ => continue
    }
    guard renderer.get("authorExternalChannelId") is Some(String(channel_id)) &&
      renderer.get("message") is Some(message) else {
      continue
    }
    let text = runs_text(message)
    guard !text.is_empty() else { continue }
    let at = match renderer.get("timestampUsec") {
      Some(String(usec)) => parse_int64_digits(usec) / 1000
      _ => 0
    }
    comments.push({
      participant_id: participant_id("youtube", channel_id),
      text,
      at,
    })
  }
  let (next_page_token, polling_interval_ms) = match
    continuation_of(continuation) {
    Some((token, timeout)) => (Some(token), timeout)
    None => (None, DEFAULT_POLLING_INTERVAL_MS)
  }
  { comments, next_page_token, polling_interval_ms, }
}

///|
fn parse_int64_digits(s : String) -> Int64 {
  let mut n : Int64 = 0
  for c in s {
    guard c is ('0'..='9') else { return 0 }
    n = n * 10 + (c.to_int() - '0').to_int64()
  }
  n
}
