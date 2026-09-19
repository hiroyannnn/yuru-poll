///|
async fn main {
  let options = parse_cli(@env.args()[1:]) catch {
    err => {
      println("引数エラー: \{Repr(err)}\n\n\{usage}")
      return
    }
  }
  start(options) catch {
    err => println("エラー: \{err}")
  }
}

///|
/// 選ばれた Source / Sink を組み立てて、全 Source が終わるまで回す。
async fn start(options : CliOptions) -> Unit {
  let poll = @lib.Poll::parse(@fs.read_file(options.poll_path).text())
  let engine = @lib.Engine::new(poll)
  let sources : Array[&@lib.Source] = []
  // web は Source（参加フォーム）と Sink（司会者画面・オーバーレイ）を兼ねる 1 つのサーバ。
  // どちらか一方でも指定されていればサーバを起動し、Source に含まれるときだけ発言を受け付ける。
  let wants_web_source = options.sources.contains("web")
  let wants_web_sink = options.sinks.contains("web")
  if wants_web_source || wants_web_sink {
    let web = @web_adapter.WebServer::new(
      engine,
      port=options.port,
      web_dir=options.web_dir,
      public_url?=options.public_url,
      accept_comments=wants_web_source,
    )
    sources.push(web)
    if wants_web_sink {
      engine.add_sink(web)
    }
  }
  for name in options.sources {
    match name {
      "web" => ()
      "stdin" => sources.push(@stdin_source.StdinSource::new())
      "twitch" => {
        guard options.twitch_channel is Some(channel) else {
          println(
            "--source twitch には --twitch <channel> が必要です\n\n\{usage}",
          )
          return
        }
        sources.push(@twitch_source.TwitchSource::new(channel))
      }
      "youtube" => {
        guard options.youtube_video_id is Some(video_id) else {
          println(
            "--source youtube には --youtube <videoId> が必要です\n\n\{usage}",
          )
          return
        }
        guard @env.get_env_var("YOUTUBE_API_KEY") is Some(api_key) else {
          println(
            "--source youtube には環境変数 YOUTUBE_API_KEY が必要です",
          )
          return
        }
        sources.push(@youtube_source.YouTubeSource::new(video_id, api_key))
      }
      _ => {
        println("未対応の source: \{name}\n\n\{usage}")
        return
      }
    }
  }
  for name in options.sinks {
    match name {
      "web" => ()
      "terminal" => engine.add_sink(@terminal_sink.TerminalSink::new())
      _ => {
        println("未対応の sink: \{name}\n\n\{usage}")
        return
      }
    }
  }
  let client = @jev.JevClient::from_env()
  @runtime.run(engine, client.judge_fn(), sources)
}
