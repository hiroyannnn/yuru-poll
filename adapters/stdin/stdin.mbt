///|
/// 標準入力から `参加者ID<TAB>発言` 行を読む Source。EOF で終わる。
pub struct StdinSource {
  /// 匿名参加者の ID に使う名前
  anonymous_id : String
}

///|
pub fn StdinSource::new(anonymous_id? : String = "anon") -> StdinSource {
  { anonymous_id, }
}

///|
pub impl @lib.Source for StdinSource with fn run(self, submit) {
  while @stdio.stdin.read_until("\n") is Some(line) {
    guard @lib.parse_stdin_line(
        line,
        at=@env.now().reinterpret_as_int64(),
        anonymous_id=self.anonymous_id,
      )
      is Some(comment) else {
      continue
    }
    (submit(comment) |> ignore) catch {
      err => @runtime.log("stdin: 判定に失敗: \{err}")
    }
  }
}
