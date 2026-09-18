///|
/// 1 発言に対する Jev の判定結果。
pub(all) struct Judgement {
  /// 最も支持している選択肢の key
  choice : String
  /// 全選択肢への確率分布（key → 確率）
  probabilities : Map[String, Double]
  /// モデル自身の確信度
  confidence : Double
} derive(Debug, Eq, ToJson)

///|
/// レスポンス解釈のエラー。
pub suberror ResponseError {
  InvalidJson(String)
  MissingField(String)
  TypeMismatch(String)
} derive(Debug, Eq)

///|
/// key の確率。分布に無い key は 0 として扱う。
pub fn Judgement::probability(self : Judgement, key : String) -> Double {
  self.probabilities.get(key).unwrap_or(0.0)
}

///|
/// レスポンス本文（文字列）を解釈する。
pub fn parse_response_text(text : String) -> Judgement raise ResponseError {
  let json = @json.parse(text) catch {
    err => raise InvalidJson(err.to_string())
  }
  parse_response(json)
}

///|
/// 解析済みレスポンス JSON から判定結果を取り出す。
/// 型不一致・欠落はキャストではなくパターンマッチで検出してエラー型にする。
pub fn parse_response(json : Json) -> Judgement raise ResponseError {
  guard json is Object(root) else { raise TypeMismatch("response") }
  let answers = match root.get("answers") {
    None => raise MissingField("answers")
    Some(Object(a)) => a
    Some(_) => raise TypeMismatch("answers")
  }
  let vote = match answers.get(VOTE_QUESTION_KEY) {
    None => raise MissingField("answers.vote")
    Some(Object(v)) => v
    Some(_) => raise TypeMismatch("answers.vote")
  }
  match vote.get("type") {
    None => raise MissingField("answers.vote.type")
    Some(String("choice")) => ()
    Some(_) => raise TypeMismatch("answers.vote.type")
  }
  let choice = match vote.get("choice") {
    None => raise MissingField("answers.vote.choice")
    Some(String(s)) => s
    Some(_) => raise TypeMismatch("answers.vote.choice")
  }
  let raw_probabilities = match vote.get("probabilities") {
    None => raise MissingField("answers.vote.probabilities")
    Some(Object(p)) => p
    Some(_) => raise TypeMismatch("answers.vote.probabilities")
  }
  let probabilities : Map[String, Double] = Map([])
  for key, value in raw_probabilities {
    match value {
      Number(n, ..) => probabilities[key] = n
      _ => raise TypeMismatch("answers.vote.probabilities.\{key}")
    }
  }
  let confidence = match vote.get("confidence") {
    None => raise MissingField("answers.vote.confidence")
    Some(Number(n, ..)) => n
    Some(_) => raise TypeMismatch("answers.vote.confidence")
  }
  { choice, probabilities, confidence, }
}
