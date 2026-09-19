///|
/// Source が供給する 1 発言。
pub(all) struct Comment {
  /// Source ごとにプレフィックスを付けた参加者 ID（例: `twitch:12345`）
  participant_id : String
  /// 発言本文
  text : String
  /// 発言時刻（UNIX ミリ秒。不明なら 0）
  at : Int64
} derive(Debug, Eq, ToJson)

///|
/// 1 発言を処理した結果。Sink はこれを受け取る。
pub(all) struct Update {
  poll : Poll
  comment : Comment
  judgement : Judgement
  snapshot : Snapshot
} derive(Debug, ToJson)

///|
/// 集計の出口。Tally が更新されるたびに呼ばれる。
pub(open) trait Sink {
  fn on_update(Self, Update) -> Unit
}

///|
/// 発言の入口。`submit` に発言を渡すと判定・集計され、判定結果が返る。
/// `run` は Source が尽きるまで（チャットなら接続が切れるまで）戻らない。
pub(open) trait Source {
  async fn run(Self, submit : async (Comment) -> Judgement) -> Unit
}

///|
/// 判定結果を Tally に反映し、接続された全 Sink へ通知するエンジン。
/// 判定そのもの（Jev への問い合わせ）は行わない。
pub struct Engine {
  poll : Poll
  tally : Tally
  sinks : Array[&Sink]
}

///|
pub fn Engine::new(poll : Poll) -> Engine {
  { poll, tally: Tally::new(poll.keys()), sinks: [], }
}

///|
/// Sink を接続する。複数接続できる。
pub fn Engine::add_sink(self : Engine, sink : &Sink) -> Unit {
  self.sinks.push(sink)
}

///|
/// 発言とその判定結果を集計に反映し、全 Sink に通知する。
pub fn Engine::apply(
  self : Engine,
  comment : Comment,
  judgement : Judgement,
) -> Update {
  self.tally.record(comment.participant_id, judgement)
  let update : Update = {
    poll: self.poll,
    comment,
    judgement,
    snapshot: self.tally.snapshot(),
  }
  for sink in self.sinks {
    sink.on_update(update)
  }
  update
}

///|
/// 現時点の集計。
pub fn Engine::snapshot(self : Engine) -> Snapshot {
  self.tally.snapshot()
}
