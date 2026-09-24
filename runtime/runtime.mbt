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
/// 標準エラー出力に 1 行書く。yuru-kit の接続と同じロガーを使う（先頭の名前は main が設定する）。
pub async fn log(message : String) -> Unit {
  @sources.log(message)
}
