///|
test "parse_cli は複数の --source / --sink と各オプションを読む" {
  let options = parse_cli(
    [
      "--poll", "polls/a.json", "--source", "youtube", "--source", "twitch", "--sink",
      "web", "--sink", "terminal", "--port", "9000", "--twitch", "ch", "--youtube",
      "vid", "--public-url", "http://x", "--web-dir", "site",
    ][:],
  )
  debug_inspect(
    options,
    content=(
      #|{
      #|  poll_path: "polls/a.json",
      #|  sources: ["youtube", "twitch"],
      #|  sinks: ["web", "terminal"],
      #|  port: 9000,
      #|  public_url: Some("http://x"),
      #|  twitch_channel: Some("ch"),
      #|  youtube_video_id: Some("vid"),
      #|  web_dir: Some("site"),
      #|}
    ),
  )
}

///|
test "source / sink を省略すると stdin と terminal、port は 8787" {
  let options = parse_cli(["--poll", "p.json"][:])
  debug_inspect(options.sources, content="[\"stdin\"]")
  debug_inspect(options.sinks, content="[\"terminal\"]")
  inspect(options.port, content="8787")
  // --web-dir を省略すると、バイナリに埋め込んだ静的ファイルを使う
  debug_inspect(options.web_dir, content="None")
}

///|
test "--version と --help は --poll が無くても受け付ける" {
  expect_cli_error(["--version"], "ShowVersion")
  expect_cli_error(["-V"], "ShowVersion")
  expect_cli_error(["--help"], "ShowHelp")
  expect_cli_error(["--source", "stdin", "-h"], "ShowHelp")
}

///|
fn expect_cli_error(args : Array[String], content : String) -> Unit raise {
  try parse_cli(args[:]) catch {
    e => debug_inspect(e, content~)
  } noraise {
    _ => fail("失敗するはず")
  }
}

///|
test "--poll が無い、値が無い、未知のフラグ、数値でないポートはエラー" {
  expect_cli_error(["--source", "stdin"], "MissingPoll")
  expect_cli_error(["--poll"], "MissingValue(\"--poll\")")
  expect_cli_error(["--poll", "p", "--bogus"], "UnknownOption(\"--bogus\")")
  expect_cli_error(["--poll", "p", "--port", "abc"], "BadNumber(\"abc\")")
}
