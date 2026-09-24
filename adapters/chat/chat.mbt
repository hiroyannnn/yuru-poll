///|
/// yuru-kit のライブチャットの入口（Twitch・YouTube・標準入力）を、yuru-poll の Source にする。
/// yuru-kit のコメントは投稿者名やスタンプも持つが、集計に使うのは参加者 ID・本文・時刻だけ。
pub struct ChatAdapter {
  inner : &@kit.ChatSource
}

///|
pub fn ChatAdapter::new(inner : &@kit.ChatSource) -> ChatAdapter {
  { inner, }
}

///|
/// yuru-kit のコメントを yuru-poll の発言にする。時刻が無い（0）ときは今の時刻を入れる。
fn to_poll_comment(comment : @kit.Comment) -> @lib.Comment {
  let at = if comment.at == 0 { @async.now() } else { comment.at }
  { participant_id: comment.participant_id, text: comment.text, at, }
}

///|
/// 判定の失敗はログに出して次のコメントに進む（チャットの読み取りは止めない）。
pub impl @lib.Source for ChatAdapter with fn run(self, submit) {
  self.inner.run(comment => {
    (submit(to_poll_comment(comment)) |> ignore) catch {
      err => @sources.log("判定に失敗: \{err}")
    }
  })
}
