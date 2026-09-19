///|
let runtime_poll_json : String =
  #|{"question": "Q", "choices": [
  #|  {"key": "a", "label": "A", "description": "aaa"},
  #|  {"key": "b", "label": "B", "description": "bbb"}
  #|]}

///|
/// 決まった発言列を順に submit するだけの Source。
struct ArraySource {
  comments : Array[@lib.Comment]
  /// submit が返した判定
  results : Array[@lib.Judgement]
  /// submit が失敗した回数
  failures : Ref[Int]
}

///|
impl @lib.Source for ArraySource with fn run(self, submit) {
  for comment in self.comments {
    let judgement = submit(comment) catch {
      _ => {
        self.failures.val += 1
        continue
      }
    }
    self.results.push(judgement)
  }
}

///|
struct RecordingSink {
  updates : Array[@lib.Update]
}

///|
impl @lib.Sink for RecordingSink with fn on_update(self, update) {
  self.updates.push(update)
}

///|
fn comment(participant_id : String, text : String) -> @lib.Comment {
  { participant_id, text, at: 0, }
}

///|
/// 発言に "A" が含まれれば a、それ以外は b と判定する偽の判定関数。
#warnings("-unused_async")
async fn fake_judge(_poll : @lib.Poll, c : @lib.Comment) -> @lib.Judgement {
  if c.text.contains("A") {
    { choice: "a", probabilities: { "a": 0.9, "b": 0.1 }, confidence: 0.8, }
  } else {
    { choice: "b", probabilities: { "a": 0.2, "b": 0.8 }, confidence: 0.8, }
  }
}

///|
async test "run は Source の発言を判定し、Tally を更新して Sink に通知し、Source に判定を返す" {
  let engine = @lib.Engine::new(@lib.Poll::parse(runtime_poll_json))
  let sink = RecordingSink::{ updates: [], }
  engine.add_sink(sink)
  let source = ArraySource::{
    comments: [
      comment("s:alice", "A かな"),
      comment("s:bob", "B でしょ"),
      comment("s:alice", "やっぱ B"),
    ],
    results: [],
    failures: Ref(0),
  }
  @runtime.run(engine, fake_judge, [source])
  inspect(sink.updates.length(), content="3")
  inspect(source.results.length(), content="3")
  inspect(source.results[2].choice, content="b")
  let snapshot = engine.snapshot()
  inspect(snapshot.participants, content="2")
  inspect(snapshot.totals["b"], content="1.6")
}

///|
/// 同時に走っている判定の数を数え、最大値を記録する判定関数を作る。
fn concurrency_probe_judge(
  running : Ref[Int],
  peak : Ref[Int],
) -> async (@lib.Poll, @lib.Comment) -> @lib.Judgement {
  async fn(poll, c) {
    running.val += 1
    if running.val > peak.val {
      peak.val = running.val
    }
    @async.sleep(5)
    running.val -= 1
    fake_judge(poll, c)
  }
}

///|
async test "複数 Source を同時に聞いても判定は直列に処理され、発言は落とさない" {
  let engine = @lib.Engine::new(@lib.Poll::parse(runtime_poll_json))
  let sink = RecordingSink::{ updates: [], }
  engine.add_sink(sink)
  let first = ArraySource::{
    comments: [comment("x:1", "A"), comment("x:2", "A"), comment("x:3", "A")],
    results: [],
    failures: Ref(0),
  }
  let second = ArraySource::{
    comments: [comment("y:1", "B"), comment("y:2", "B"), comment("y:3", "B")],
    results: [],
    failures: Ref(0),
  }
  let running = Ref(0)
  let peak = Ref(0)
  @runtime.run(engine, concurrency_probe_judge(running, peak), [first, second])
  inspect(peak.val, content="1")
  inspect(sink.updates.length(), content="6")
  inspect(engine.snapshot().participants, content="6")
}

///|
suberror JudgeDown

///|
async test "判定が失敗した発言は Source にエラーが返り、他の発言は処理される" {
  let engine = @lib.Engine::new(@lib.Poll::parse(runtime_poll_json))
  let source = ArraySource::{
    comments: [
      comment("s:1", "A"),
      comment("s:2", "crash"),
      comment("s:3", "A"),
    ],
    results: [],
    failures: Ref(0),
  }
  let judge = async fn(poll : @lib.Poll, c : @lib.Comment) -> @lib.Judgement {
    if c.text == "crash" {
      raise JudgeDown
    }
    fake_judge(poll, c)
  }
  @runtime.run(engine, judge, [source])
  inspect(source.results.length(), content="2")
  inspect(source.failures.val, content="1")
  inspect(engine.snapshot().participants, content="2")
}
