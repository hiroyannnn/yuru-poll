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
