///|
/// 保存した Engine の復元エラー。
pub suberror PersistError {
  TypeMismatch(String)
  BadPoll(PollError)
  /// (参加者 ID, 判定の読み取りエラー)
  BadEntry(String, ResponseError)
} derive(Debug, Eq)

///|
/// poll と参加者ごとの最新判定を JSON にする。Sink は含めない。
/// プロセスが落ちても集計を戻せるよう、外部ストレージに置く用途。
pub fn Engine::dump(self : Engine) -> Json {
  let entries : Map[String, Json] = Map([])
  for participant_id, judgement in self.tally.latest_by_participant {
    entries[participant_id] = ToJson::to_json(judgement)
  }
  { "poll": ToJson::to_json(self.poll), "entries": Json::object(entries) }
}

///|
/// `Engine::dump` の JSON から Engine を復元する。Sink は付け直すこと。
pub fn Engine::restore(json : Json) -> Engine raise PersistError {
  guard json is Object(root) else { raise TypeMismatch("state") }
  let poll = Poll::from_json(root.get("poll").unwrap_or(Json::object(Map([])))) catch {
    err => raise BadPoll(err)
  }
  let engine = Engine::new(poll)
  match root.get("entries") {
    None => ()
    Some(Object(entries)) =>
      for participant_id, entry in entries {
        let judgement = Judgement::from_json(entry, path="") catch {
          err => raise BadEntry(participant_id, err)
        }
        engine.tally.record(participant_id, judgement)
      }
    Some(_) => raise TypeMismatch("entries")
  }
  engine
}
