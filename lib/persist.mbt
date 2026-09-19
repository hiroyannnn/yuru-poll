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
  {
    "poll": ToJson::to_json(self.poll),
    "entries": Json::object(entries),
    "history": ToJson::to_json(self.recent),
  }
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
  // 履歴は後から足した項目なので、無い state も受け付ける
  match root.get("history") {
    None | Some(Null) => ()
    Some(Array(items)) =>
      for item in items {
        guard item
          is Object(
            { "comment": comment_json, "judgement": judgement_json, .. }
          ) else {
          raise TypeMismatch("history")
        }
        let comment = comment_from_json(comment_json)
        let judgement = Judgement::from_json(judgement_json, path="") catch {
          err => raise BadEntry(comment.participant_id, err)
        }
        engine.remember({ comment, judgement, })
      }
    Some(_) => raise TypeMismatch("history")
  }
  engine
}

///|
fn comment_from_json(json : Json) -> Comment raise PersistError {
  guard json
    is Object(
      { "participant_id": String(participant_id), "text": String(text), .. }
    ) else {
    raise TypeMismatch("history.comment")
  }
  // at は Int64 なので JSON では文字列になる。読めなければ 0
  let at : Int64 = match json {
    Object({ "at": String(s), .. }) => @string.parse_int64(s) catch { _ => 0 }
    _ => 0
  }
  { participant_id, text, at, }
}
