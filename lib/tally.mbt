///|
/// 最大確率がこの値以上なら「確定」、未満なら「揺れ」。
pub const CONFIDENT_THRESHOLD : Double = 0.8

///|
/// 集計結果のスナップショット。Sink はこれを受け取って描画する。
pub(all) struct Snapshot {
  /// 選択肢 key → 小数票の合計（Poll の選択肢順、none を含む）
  totals : Map[String, Double]
  /// 発言した参加者の人数（1 人 1 分布）
  participants : Int
  /// 最大確率が CONFIDENT_THRESHOLD 以上の参加者数（none を除く）
  confident : Int
  /// 最大確率が CONFIDENT_THRESHOLD 未満の参加者数（none を除く）
  wavering : Int
  /// 最大確率が none に落ちた参加者数
  none_count : Int
} derive(Debug, Eq, ToJson)

///|
/// 参加者 ID → 最新の判定を保持し、小数票を集計する。
pub struct Tally {
  keys : Array[String]
  latest_by_participant : Map[String, Judgement]
}

///|
/// 選択肢 key の一覧（none を含む）から空の Tally を作る。
pub fn Tally::new(keys : Array[String]) -> Tally {
  { keys: keys.copy(), latest_by_participant: Map([]), }
}

///|
/// 参加者の最新判定を記録する。同じ参加者なら上書き。
pub fn Tally::record(
  self : Tally,
  participant_id : String,
  judgement : Judgement,
) -> Unit {
  self.latest_by_participant[participant_id] = judgement
}

///|
/// 全参加者の判定を消す。
pub fn Tally::clear(self : Tally) -> Unit {
  self.latest_by_participant.clear()
}

///|
/// 参加者の最新判定。
pub fn Tally::latest(self : Tally, participant_id : String) -> Judgement? {
  self.latest_by_participant.get(participant_id)
}

///|
/// 現時点の集計を計算する。
pub fn Tally::snapshot(self : Tally) -> Snapshot {
  let totals : Map[String, Double] = Map([])
  for key in self.keys {
    totals[key] = 0.0
  }
  let mut confident = 0
  let mut wavering = 0
  let mut none_count = 0
  for _, judgement in self.latest_by_participant {
    for key in self.keys {
      totals[key] = totals[key] + judgement.probability(key)
    }
    let (top_key, top_probability) = self.top_of(judgement)
    if top_key == NONE_KEY {
      none_count += 1
    } else if top_probability >= CONFIDENT_THRESHOLD {
      confident += 1
    } else {
      wavering += 1
    }
  }
  {
    totals,
    participants: self.latest_by_participant.length(),
    confident,
    wavering,
    none_count,
  }
}

///|
/// Poll の選択肢の中で最大確率の key とその確率（同率なら先に定義された方）。
fn Tally::top_of(self : Tally, judgement : Judgement) -> (String, Double) {
  let mut top = (NONE_KEY, -1.0)
  for key in self.keys {
    let p = judgement.probability(key)
    if p > top.1 {
      top = (key, p)
    }
  }
  top
}

///|
/// Source ごとに衝突しない参加者 ID を作る（例: `youtube:UC123`）。
pub fn participant_id(source : String, id : String) -> String {
  "\{source}:\{id}"
}
