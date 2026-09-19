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
  Judgement::from_json(Json::object(vote), path="answers.vote")
}

///|
/// `{choice, probabilities, confidence}` の形の JSON から判定結果を読む。
/// `path` はエラーに載せる位置の接頭辞（例: `answers.vote`）。
pub fn Judgement::from_json(
  json : Json,
  path~ : String,
) -> Judgement raise ResponseError {
  let at = (field : String) => {
    if path.is_empty() {
      field
    } else {
      "\{path}.\{field}"
    }
  }
  guard json is Object(vote) else {
    raise TypeMismatch(if path.is_empty() { "judgement" } else { path })
  }
  let choice = match vote.get("choice") {
    None => raise MissingField(at("choice"))
    Some(String(s)) => s
    Some(_) => raise TypeMismatch(at("choice"))
  }
  let raw_probabilities = match vote.get("probabilities") {
    None => raise MissingField(at("probabilities"))
    Some(Object(p)) => p
    Some(_) => raise TypeMismatch(at("probabilities"))
  }
  let probabilities : Map[String, Double] = Map([])
  for key, value in raw_probabilities {
    match value {
      Number(n, ..) => probabilities[key] = n
      _ => raise TypeMismatch(at("probabilities.\{key}"))
    }
  }
  let confidence = match vote.get("confidence") {
    None => raise MissingField(at("confidence"))
    Some(Number(n, ..)) => n
    Some(_) => raise TypeMismatch(at("confidence"))
  }
  { choice, probabilities, confidence, }
}
