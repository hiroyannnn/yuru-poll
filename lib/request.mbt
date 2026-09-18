///|
/// Jev に投げるモデル名。
pub const JEV_MODEL : String = "jev-latest"

///|
/// リクエスト内の質問キー。レスポンスの `answers` もこのキーで引く。
pub const VOTE_QUESTION_KEY : String = "vote"

///|
/// TypeSafe Jev 互換 API（`POST /v1/systemone`）向けのリクエスト JSON を組み立てる。
///
/// - `state`: 質問文と発言
/// - `questions.vote`: 選択肢を criteria にした choice 質問 1 個
pub fn build_request(poll : Poll, comment : String) -> Json {
  let criteria : Map[String, Json] = Map([])
  for choice in poll.choices {
    criteria[choice.key] = Json::string(criterion_text(choice))
  }
  {
    "state": { "question": poll.question, "comment": comment },
    "model": JEV_MODEL,
    "questions": {
      "vote": {
        "type": "choice",
        "instructions": "この発言はどの選択肢を支持しているか？",
        "criteria": Json::object(criteria),
      },
    },
  }
}

///|
/// criteria に渡す説明文。label と description を合わせて渡すことで
/// 選択肢名そのものへの言及も拾えるようにする。
fn criterion_text(choice : Choice) -> String {
  if choice.description.is_empty() {
    choice.label
  } else {
    "\{choice.label}: \{choice.description}"
  }
}
