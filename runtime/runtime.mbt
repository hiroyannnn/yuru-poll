///|
/// 全 Source を同時に走らせ、発言を 1 件ずつ直列に判定して Engine に流す。
///
/// - `judge` は差し替え可能な判定関数（HTTP 実装は `jev` パッケージ）
/// - 判定は Mutex で直列化する。発言が集中しても待たせるだけで落とさない
/// - 判定の失敗は `submit` を呼んだ Source にそのまま返す
/// - 全 Source の `run` が戻ったら `run` も戻る
pub async fn run(
  engine : @lib.Engine,
  judge : async (@lib.Poll, @lib.Comment) -> @lib.Judgement,
  sources : Array[&@lib.Source],
) -> Unit {
  let lock = @async.Mutex()
  let submit = async fn(comment : @lib.Comment) -> @lib.Judgement {
    lock.acquire()
    defer lock.release()
    let judgement = judge(engine.poll, comment)
    engine.apply(comment, judgement).judgement
  }
  @async.with_task_group(group => {
    for source in sources {
      group.spawn_bg(() => source.run(submit))
    }
  })
}

///|
/// カレントディレクトリの `.env` を読み、まだ無い環境変数だけを補う。無ければ何もしない。
/// 補ったキーの数を返す（yuru-come から移植）。
pub async fn load_dotenv(path? : String = ".env") -> Int {
  let text = @fs.read_file(path).text() catch { _ => return 0 }
  let mut loaded = 0
  for key, value in @lib.parse_dotenv(text) {
    if @env.get_env_var(key) is None {
      @env.set_env_var(key, value)
      loaded += 1
    }
  }
  loaded
}

///|
/// 標準エラー出力に 1 行書く（標準出力はターミナル Sink が使うので分ける）。
pub async fn log(message : String) -> Unit {
  @stdio.stderr.write("[yuru-poll] \{message}\n")
}
