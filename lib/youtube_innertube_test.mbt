///|
/// `youtube.com/live_chat?v=…` のページを模した断片。
let sample_page : String =
  #|<!DOCTYPE html><html><head></head><body><script>ytcfg.set({"INNERTUBE_API_KEY":"AIzaSyTESTKEY","INNERTUBE_CLIENT_VERSION":"2.20260921.01.00","X":1});</script>
  #|<script>window["ytInitialData"] = {"responseContext":{},"contents":{"liveChatRenderer":{"continuations":[{"invalidationContinuationData":{"timeoutMs":10000,"continuation":"CONT_FIRST"}}],"actions":[]}}};</script><yt-live-chat-app></yt-live-chat-app></body></html>

///|
test "ページから innertube のキー、クライアントバージョン、最初の継続トークンを取り出す" {
  let config = @lib.parse_live_chat_page_html(sample_page)
  assert_eq(config.api_key, "AIzaSyTESTKEY")
  assert_eq(config.client_version, "2.20260921.01.00")
  assert_eq(config.continuation, "CONT_FIRST")
}

///|
test "チャットが無効な配信は ChatUnavailable（画面の文言つき）" {
  let page = sample_page.replace(
    old="{\"liveChatRenderer\":{\"continuations\":[{\"invalidationContinuationData\":{\"timeoutMs\":10000,\"continuation\":\"CONT_FIRST\"}}],\"actions\":[]}}",
    new="{\"messageRenderer\":{\"text\":{\"runs\":[{\"text\":\"このライブ ストリームではチャットは無効です。\"}]}}}",
  )
  try @lib.parse_live_chat_page_html(page) catch {
    e =>
      debug_inspect(
        e,
        content="ChatUnavailable(\"このライブ ストリームではチャットは無効です。\")",
      )
  } noraise {
    _ => fail("失敗するはず")
  }
}

///|
test "ページにキーやデータが無ければ TypeMismatch" {
  try @lib.parse_live_chat_page_html("<html></html>") catch {
    e => debug_inspect(e, content="TypeMismatch(\"INNERTUBE_API_KEY\")")
  } noraise {
    _ => fail("失敗するはず")
  }
}

///|
test "get_live_chat のリクエストは WEB クライアントと継続トークンを持つ" {
  let config : @lib.InnertubeConfig = {
    api_key: "K",
    client_version: "2.0",
    continuation: "C1",
  }
  assert_eq(
    @lib.innertube_live_chat_url(config),
    "https://www.youtube.com/youtubei/v1/live_chat/get_live_chat?key=K&prettyPrint=false",
  )
  assert_eq(@lib.innertube_live_chat_body(config, "C2"), {
    "context": {
      "client": { "clientName": "WEB", "clientVersion": "2.0", "hl": "ja" },
    },
    "continuation": "C2",
  })
}

///|
let innertube_response : String =
  #|{"continuationContents":{"liveChatContinuation":{
  #| "continuations":[{"invalidationContinuationData":{"timeoutMs":10000,"continuation":"CONT_NEXT"}}],
  #| "actions":[
  #|  {"addChatItemAction":{"item":{"liveChatTextMessageRenderer":{
  #|    "message":{"runs":[{"text":"それ原油じゃなくて"},{"emoji":{"emojiId":"😆","shortcuts":[":laughing:"],"image":{}}},{"text":"重油では"}]},
  #|    "authorName":{"simpleText":"@ブギー-h3r"},"authorExternalChannelId":"UCL3HA2KTvFjajmvakogQgZw",
  #|    "id":"ChwKGk","timestampUsec":"1790057328918688"}}}},
  #|  {"addChatItemAction":{"item":{"liveChatTextMessageRenderer":{
  #|    "message":{"runs":[{"emoji":{"emojiId":"UCkszU2WH9gy1mb0dV-11UJg/xsIfY","shortcuts":[":face-green-smiling:"],"isCustomEmoji":true}},{"emoji":{"emojiId":"UCkszU2WH9gy1mb0dV-11UJg/xsIfY","shortcuts":[":face-green-smiling:"],"isCustomEmoji":true}}]},
  #|    "authorName":{"simpleText":"@viewer2"},"authorExternalChannelId":"UC2","id":"x","timestampUsec":"1790057330000000"}}}},
  #|  {"addChatItemAction":{"item":{"liveChatViewerEngagementMessageRenderer":{"message":{"runs":[{"text":"ようこそ"}]}}}}},
  #|  {"addBannerToLiveChatCommand":{"bannerRenderer":{}}},
  #|  {"addChatItemAction":{"item":{"liveChatPaidMessageRenderer":{
  #|    "message":{"runs":[{"text":"応援してます"}]},"authorName":{"simpleText":"@rich"},"authorExternalChannelId":"UC3","id":"y","timestampUsec":"1790057331000000","purchaseAmountText":{"simpleText":"￥1,000"}}}}}
  #| ]}}}

///|
test "get_live_chat のレスポンスから、テキストとスーパーチャットのコメントを取り出す" {
  let page = @lib.parse_get_live_chat(@json.parse(innertube_response))
  assert_eq(page.next_page_token, Some("CONT_NEXT"))
  assert_eq(page.polling_interval_ms, 10000)
  assert_eq(page.comments.map(c => c.text), [
    "それ原油じゃなくて😆重油では", ":face-green-smiling::face-green-smiling:",
    "応援してます",
  ])
  assert_eq(page.comments[0].participant_id, "youtube:UCL3HA2KTvFjajmvakogQgZw")
  // timestampUsec はマイクロ秒。ミリ秒に丸める
  assert_eq(page.comments[0].at, 1790057328918L)
  // カスタム絵文字はショートカット表記（:name:）で本文に残す
  assert_eq(page.comments[2].participant_id, "youtube:UC3")
}

///|
test "継続トークンが無ければ配信終了として None" {
  let text =
    #|{"continuationContents":{"liveChatContinuation":{"actions":[]}}}
  let page = @lib.parse_get_live_chat(@json.parse(text))
  assert_eq(page.next_page_token, None)
  assert_eq(page.comments, [])
}

///|
test "timedContinuationData と reloadContinuationData も読む" {
  let timed =
    #|{"continuationContents":{"liveChatContinuation":{"continuations":[{"timedContinuationData":{"timeoutMs":5000,"continuation":"T"}}]}}}
  let page = @lib.parse_get_live_chat(@json.parse(timed))
  assert_eq(page.next_page_token, Some("T"))
  assert_eq(page.polling_interval_ms, 5000)
  let reload =
    #|{"continuationContents":{"liveChatContinuation":{"continuations":[{"reloadContinuationData":{"continuation":"R"}}]}}}
  assert_eq(
    @lib.parse_get_live_chat(@json.parse(reload)).next_page_token,
    Some("R"),
  )
}

///|
test "continuationContents が無い（配信が終わった・トークンが古い）レスポンスは TypeMismatch" {
  let empty = Json::empty_object()
  try @lib.parse_get_live_chat(empty) catch {
    e => debug_inspect(e, content="TypeMismatch(\"continuationContents\")")
  } noraise {
    _ => fail("失敗するはず")
  }
}
