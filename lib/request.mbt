///|
/// Jev に投げるモデル名。
pub const JEV_MODEL : String = "jev-latest"

///|
/// リクエスト内の質問キー。レスポンスの `answers` もこのキーで引く。
pub const VOTE_QUESTION_KEY : String = "vote"

///|
/// choice 質問の既定の instructions。eval/ の評価セットで、本家 Jev とローカルの Gemma 3 4B の両方で選んだ。
/// - 否定の扱いを明示しないと、Gemma は「Bはないわ」を B の支持と誤判定する
/// - 「迷っているなら none」と書くと、本家 Jev は「たぶん B…自信ない」まで none に落とす
/// - 迷いは挙げた選択肢で分ける、と明示すると「A もいいけど B も好き」が小数票になる
pub const VOTE_INSTRUCTIONS : String = "この発言は投票の回答です。どの選択肢を支持しているか？複数の選択肢で迷っている発言は、挙げられた選択肢のあいだで確率を分ける。「〜はない」「〜は嫌」のような否定はその選択肢への支持ではない。どの選択肢にも触れていない雑談・挨拶は none。"

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
        "instructions": poll.instructions.unwrap_or(VOTE_INSTRUCTIONS),
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
