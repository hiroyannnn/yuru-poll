///|
/// Jev に投げるモデル名。
pub const JEV_MODEL : String = "jev-latest"

///|
/// リクエスト内の質問キー。レスポンスの `answers` もこのキーで引く。
pub const VOTE_QUESTION_KEY : String = "vote"

///|
/// choice 質問の instructions。否定形・迷い・雑談の扱いを明示すると
/// ローカルモデル（Gemma 3 4B）でも「Bはないわ」を B の支持と誤判定しにくくなる。
pub const VOTE_INSTRUCTIONS : String = "この発言は投票の回答です。どの選択肢を支持しているか？「〜はない」「〜は嫌」のような否定はその選択肢への支持ではない。迷っている・雑談・挨拶なら none。"

///|
/// TypeSafe Jev 互換 API（`POST /v1/systemone`）向けのリクエスト JSON を組み立てる。
///
/// - `state`: 質問文と発言
/// - `questions.vote`: 選択肢を criteria にした choice 質問 1 個
/// - `model`: 既定は `jev-latest`。Vercel AI Gateway 経由なら `typesafe-ai/jev` を渡す
pub fn build_request(
  poll : Poll,
  comment : String,
  model? : String = JEV_MODEL,
) -> Json {
  let criteria : Map[String, Json] = Map([])
  for choice in poll.choices {
    criteria[choice.key] = Json::string(criterion_text(choice))
  }
  {
    "state": { "question": poll.question, "comment": comment },
    "model": model,
    "questions": {
      "vote": {
        "type": "choice",
        "instructions": VOTE_INSTRUCTIONS,
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
