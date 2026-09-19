///|
test "PRIVMSG（tags 付き）を Comment に変換し、participant_id は twitch:<user-id>" {
  let line =
    #|@badge-info=;badges=;color=#FF0000;display-name=Alice;tmi-sent-ts=1700000000123;user-id=12345 :alice!alice@alice.tmi.twitch.tv PRIVMSG #somechannel :たぶんA かな
  debug_inspect(
    @lib.parse_irc_line(line),
    content=(
      #|Chat({ participant_id: "twitch:12345", text: "たぶんA かな", at: 1700000000123 })
    ),
  )
}

///|
test "tags が無い PRIVMSG は nick を participant_id にし、at は 0" {
  let line = ":bob!bob@bob.tmi.twitch.tv PRIVMSG #ch :Bはないわ"
  debug_inspect(
    @lib.parse_irc_line(line),
    content=(
      #|Chat({ participant_id: "twitch:bob", text: "Bはないわ", at: 0 })
    ),
  )
}

///|
test "末尾の CRLF は取り除く" {
  let line = ":bob!bob@bob.tmi.twitch.tv PRIVMSG #ch :hi\r\n"
  assert_true(@lib.parse_irc_line(line) is Chat({ text: "hi", .. }))
}

///|
test "PING は payload 付きの Ping になり、pong_line で返答行を作れる" {
  let message = @lib.parse_irc_line("PING :tmi.twitch.tv")
  debug_inspect(message, content="Ping(\"tmi.twitch.tv\")")
  inspect(@lib.pong_line("tmi.twitch.tv"), content="PONG :tmi.twitch.tv")
}

///|
test "PRIVMSG でも PING でもない行は Other" {
  let line = ":tmi.twitch.tv 001 justinfan123 :Welcome, GLHF!"
  assert_true(@lib.parse_irc_line(line) is Other(_))
  assert_true(@lib.parse_irc_line("") is Other(_))
}

///|
test "twitch_login_lines は匿名ユーザーでの CAP/NICK/JOIN 行を作る" {
  debug_inspect(
    @lib.twitch_login_lines("justinfan777", "SomeChannel"),
    content=(
      #|["CAP REQ :twitch.tv/tags", "NICK justinfan777", "JOIN #somechannel"]
    ),
  )
}
