///|
test "videos.list のレスポンスから activeLiveChatId を取り出す" {
  let text =
    #|{"items": [{"id": "abc", "liveStreamingDetails": {"activeLiveChatId": "Cg0KC2FiYw"}}]}
  inspect(@lib.parse_live_chat_id(@json.parse(text)), content="Cg0KC2FiYw")
}

///|
test "items が空なら VideoNotFound、activeLiveChatId が無ければ NotLive" {
  try @lib.parse_live_chat_id(@json.parse("{\"items\": []}")) catch {
    e => debug_inspect(e, content="VideoNotFound")
  } noraise {
    _ => fail("失敗するはず")
  }
  let not_live =
    #|{"items": [{"id": "abc", "liveStreamingDetails": {"actualEndTime": "x"}}]}
  try @lib.parse_live_chat_id(@json.parse(not_live)) catch {
    e => debug_inspect(e, content="NotLive")
  } noraise {
    _ => fail("失敗するはず")
  }
}

///|
test "liveChatMessages.list のレスポンスを Comment 列・nextPageToken・間隔に分解する" {
  let text =
    #|{"nextPageToken": "TOKEN2", "pollingIntervalMillis": 5000,
    #| "items": [
    #|  {"snippet": {"type": "textMessageEvent", "displayMessage": "たぶんA", "publishedAt": "2026-01-01T00:00:00Z"},
    #|   "authorDetails": {"channelId": "UC1", "displayName": "alice"}},
    #|  {"snippet": {"type": "superChatEvent", "displayMessage": "Bで！"},
    #|   "authorDetails": {"channelId": "UC2"}},
    #|  {"snippet": {"type": "memberMilestoneChatEvent"},
    #|   "authorDetails": {"channelId": "UC3"}}
    #| ]}
  let page = @lib.parse_live_chat_page(@json.parse(text))
  debug_inspect(page.next_page_token, content="Some(\"TOKEN2\")")
  inspect(page.polling_interval_ms, content="5000")
  debug_inspect(
    page.comments,
    content=(
      #|[
      #|  { participant_id: "youtube:UC1", text: "たぶんA", at: 0 },
      #|  { participant_id: "youtube:UC2", text: "Bで！", at: 0 },
      #|]
    ),
  )
}

///|
test "nextPageToken と pollingIntervalMillis が無ければ None と既定値" {
  let page = @lib.parse_live_chat_page(@json.parse("{\"items\": []}"))
  debug_inspect(page.next_page_token, content="None")
  inspect(page.polling_interval_ms, content="5000")
  inspect(page.comments.length(), content="0")
}

///|
test "items が配列でなければ TypeMismatch" {
  try @lib.parse_live_chat_page(@json.parse("{\"items\": 1}")) catch {
    e => debug_inspect(e, content="TypeMismatch(\"items\")")
  } noraise {
    _ => fail("失敗するはず")
  }
}

///|
test "YouTube Data API の URL を組み立てる" {
  inspect(
    @lib.videos_list_url("VIDEO1", "KEY"),
    content="https://www.googleapis.com/youtube/v3/videos?part=liveStreamingDetails&id=VIDEO1&key=KEY",
  )
  inspect(
    @lib.live_chat_messages_url("CHAT1", "KEY", None),
    content="https://www.googleapis.com/youtube/v3/liveChat/messages?liveChatId=CHAT1&part=snippet,authorDetails&maxResults=200&key=KEY",
  )
  inspect(
    @lib.live_chat_messages_url("CHAT1", "KEY", Some("TOKEN2")),
    content="https://www.googleapis.com/youtube/v3/liveChat/messages?liveChatId=CHAT1&part=snippet,authorDetails&maxResults=200&key=KEY&pageToken=TOKEN2",
  )
}
