///|
/// 決まったコメントを順に流すだけの yuru-kit の入口。
struct FakeChat {
  comments : Array[@kit.Comment]
}

///|
impl @kit.ChatSource for FakeChat with fn run(self, emit) {
  for comment in self.comments {
    emit(comment)
  }
}

///|
suberror JudgeDown

///|
async test "yuru-kit のコメントを yuru-poll の発言に変換し、判定の失敗があっても次に進む" {
  let fake = FakeChat::{
    comments: [
      @kit.Comment::new("twitch:1", "たぶんA", author="alice", at=1700L),
      @kit.Comment::new("youtube:UC2", "crash", author="bob", at=1800L),
      @kit.Comment::new("twitch:3", "B かな", emotes=["Kappa"]),
    ],
  }
  let seen : Array[@lib.Comment] = []
  let submit = async fn(comment : @lib.Comment) -> @lib.Judgement {
    @async.pause()
    seen.push(comment)
    if comment.text == "crash" {
      raise JudgeDown
    }
    { choice: "a", probabilities: { "a": 1.0 }, confidence: 1.0, }
  }
  @chat.ChatAdapter::new(fake).run(submit)
  assert_eq(seen.length(), 3)
  assert_eq(seen[0], {
    participant_id: "twitch:1",
    text: "たぶんA",
    at: 1700L,
  })
  assert_eq(seen[1].participant_id, "youtube:UC2")
  // 時刻が無い（0）コメントは受け取った時刻を入れる
  assert_true(seen[2].at > 0L)
}
