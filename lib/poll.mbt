///|
/// 「どれでもない」選択肢のキー。雑談などを集計から外す受け皿として常に混ぜる。
pub const NONE_KEY : String = "none"

///|
/// 投票の選択肢。
/// `description` には「その選択肢を支持する人がよく言う言い回し」を書く。
/// Jev の criteria にそのまま渡るので、判定精度に直結する。
pub(all) struct Choice {
  key : String
  label : String
  description : String
} derive(Debug, Eq, ToJson)

///|
/// アンケート 1 本。`choices` の末尾には必ず `none` が含まれる。
pub(all) struct Poll {
  question : String
  choices : Array[Choice]
  /// 判定の指示文。None なら既定（VOTE_INSTRUCTIONS）を使う
  instructions : String?
} derive(Debug, Eq, ToJson)

///|
/// poll JSON の読み込みエラー。
pub suberror PollError {
  InvalidJson(String)
  MissingField(String)
  TypeMismatch(String)
  DuplicateKey(String)
  EmptyChoices
} derive(Debug, Eq)

///|
/// JSON 文字列から Poll を読み込む。`none` が無ければ末尾に自動付与する。
pub fn Poll::parse(text : String) -> Poll raise PollError {
  let json = @json.parse(text) catch {
    err => raise InvalidJson(err.to_string())
  }
  Poll::from_json(json)
}

///|
/// 解析済み JSON から Poll を組み立てる。
pub fn Poll::from_json(json : Json) -> Poll raise PollError {
  guard json is Object(obj) else { raise TypeMismatch("poll") }
  let question = required_string(obj, "question")
  guard obj.get("choices") is Some(choices_json) else {
    raise MissingField("choices")
  }
  guard choices_json is Array(items) else { raise TypeMismatch("choices") }
  let choices : Array[Choice] = []
  for item in items {
    let choice = choice_from_json(item)
    if choices.iter().any(c => c.key == choice.key) {
      raise DuplicateKey(choice.key)
    }
    choices.push(choice)
  }
  if choices.is_empty() {
    raise EmptyChoices
  }
  if !choices.iter().any(c => c.key == NONE_KEY) {
    choices.push(default_none_choice())
  }
  let instructions = match obj.get("instructions") {
    None | Some(Null) => None
    Some(String(s)) => {
      let trimmed = s.trim(chars=" \t\r\n").to_owned()
      if trimmed.is_empty() {
        None
      } else {
        Some(trimmed)
      }
    }
    Some(_) => raise TypeMismatch("instructions")
  }
  { question, choices, instructions, }
}

///|
/// 選択肢のキーを定義順に返す。
pub fn Poll::keys(self : Poll) -> Array[String] {
  self.choices.map(c => c.key)
}

///|
/// キーで選択肢を引く。
pub fn Poll::find(self : Poll, key : String) -> Choice? {
  self.choices.iter().find_first(c => c.key == key)
}

///|
fn default_none_choice() -> Choice {
  {
    key: NONE_KEY,
    label: "どれでもない",
    description: "どれも支持していない、雑談、意味不明",
  }
}

///|
fn choice_from_json(json : Json) -> Choice raise PollError {
  guard json is Object(obj) else { raise TypeMismatch("choice") }
  let key = required_string(obj, "key")
  let label = required_string(obj, "label")
  let description = match obj.get("description") {
    None | Some(Null) => ""
    Some(String(s)) => s
    Some(_) => raise TypeMismatch("description")
  }
  { key, label, description, }
}

///|
fn required_string(
  obj : Map[String, Json],
  field : String,
) -> String raise PollError {
  match obj.get(field) {
    None => raise MissingField(field)
    Some(String(s)) => s
    Some(_) => raise TypeMismatch(field)
  }
}
