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
  for name in options.sources {
    match name {
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
