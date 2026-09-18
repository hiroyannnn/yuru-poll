///|
test "参加者ID<TAB>発言 の行を Comment にする（ID には stdin: を付ける）" {
  debug_inspect(
    @lib.parse_stdin_line("alice\tたぶんA", at=123),
    content=(
      #|Some({ participant_id: "stdin:alice", text: "たぶんA", at: 123 })
    ),
  )
}

///|
test "TAB が無い行は匿名参加者の発言として扱う（ID は差し替え可能）" {
  debug_inspect(
    @lib.parse_stdin_line("うーん迷う", at=1),
    content=(
      #|Some({ participant_id: "stdin:anon", text: "うーん迷う", at: 1 })
    ),
  )
  debug_inspect(
    @lib.parse_stdin_line("うーん迷う", at=1, anonymous_id="me"),
    content=(
      #|Some({ participant_id: "stdin:me", text: "うーん迷う", at: 1 })
    ),
  )
}

///|
test "空行・空白だけの行・末尾改行は無視または除去する" {
  debug_inspect(@lib.parse_stdin_line("", at=1), content="None")
  debug_inspect(@lib.parse_stdin_line("   \n", at=1), content="None")
  assert_true(
    @lib.parse_stdin_line("bob\tBはないわ\r\n", at=1)
    is Some({ text: "Bはないわ", .. }),
  )
}
