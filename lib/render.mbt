///|
/// 小数票を小数 1 桁で表示する（四捨五入）。
pub fn format_votes(votes : Double) -> String {
  let tenths = (votes * 10.0 + 0.5).to_int()
  "\{tenths / 10}.\{tenths % 10}"
}

///|
/// 端末上の表示幅。U+00FF より大きい文字（全角想定）を 2、それ以外を 1 と数える。
pub fn display_width(text : String) -> Int {
  let mut width = 0
  for c in text {
    width += if c.to_int() > 0xFF { 2 } else { 1 }
  }
  width
}

///|
/// 集計をテキストの棒グラフにする。none は棒に出さず内訳にだけ出す。
pub fn render_snapshot(
  poll : Poll,
  snapshot : Snapshot,
  width? : Int = 30,
) -> String {
  let choices = poll.choices.filter(c => c.key != NONE_KEY)
  let label_width = choices.fold(init=0, (acc, c) => {
    let w = display_width(c.label)
    if w > acc {
      w
    } else {
      acc
    }
  })
  let max_votes = choices.fold(init=0.0, (acc, c) => {
    let v = snapshot.totals.get(c.key).unwrap_or(0.0)
    if v > acc {
      v
    } else {
      acc
    }
  })
  let out = StringBuilder()
  out.write_string(poll.question)
  out.write_char('\n')
  for choice in choices {
    let votes = snapshot.totals.get(choice.key).unwrap_or(0.0)
    let filled = if max_votes > 0.0 {
      (votes / max_votes * width.to_double() + 0.5).to_int()
    } else {
      0
    }
    out.write_string(choice.label)
    out.write_string(" ".repeat(label_width - display_width(choice.label) + 1))
    out.write_string("█".repeat(filled))
    out.write_string("░".repeat(width - filled))
    let votes_text = format_votes(votes)
    out.write_string(" ".repeat(6 - votes_text.length()))
    out.write_string(votes_text)
    out.write_char('\n')
  }
  out.write_string(
    "参加 \{snapshot.participants}人 / 確定 \{snapshot.confident} / 揺れ \{snapshot.wavering} / どれでもない \{snapshot.none_count}\n",
  )
  out.to_string()
}

///|
/// 最新発言がどう解釈されたかを 1 行にする（全選択肢の分布を % で並べる）。
pub fn render_last_comment(update : Update) -> String {
  let parts = update.poll.choices.map(choice => {
    let percent = (update.judgement.probability(choice.key) * 100.0 + 0.5).to_int()
    "\{choice.label} \{percent}%"
  })
  let distribution = parts.join(" / ")
  "最新: [\{update.comment.participant_id}] \{update.comment.text} → \{distribution}（confidence \{update.judgement.confidence}）"
}
