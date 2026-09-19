///|
/// 集計が更新されるたびに画面を消して棒グラフを描き直す Sink。
pub struct TerminalSink {
  width : Int
}

///|
pub fn TerminalSink::new(width? : Int = 30) -> TerminalSink {
  { width, }
}

///|
pub impl @lib.Sink for TerminalSink with fn on_update(self, update) {
  let chart = @lib.render_snapshot(
    update.poll,
    update.snapshot,
    width=self.width,
  )
  let last = @lib.render_last_comment(update)
  println("[2J[H\{chart}\n\{last}")
}
