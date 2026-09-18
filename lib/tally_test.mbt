///|
fn judgement(
  choice : String,
  probabilities : Map[String, Double],
) -> @lib.Judgement {
  { choice, probabilities, confidence: 0.5, }
}

///|
let tally_keys : Array[String] = ["a", "b", "none"]

///|
test "空の Tally は全選択肢 0 票・参加者 0 人" {
  let tally = @lib.Tally::new(tally_keys)
  let snapshot = tally.snapshot()
  debug_inspect(
    snapshot,
    content=(
      #|{
      #|  totals: { "a": 0, "b": 0, "none": 0 },
      #|  participants: 0,
      #|  confident: 0,
      #|  wavering: 0,
      #|  none_count: 0,
      #|}
    ),
  )
}

///|
test "確率をそのまま小数票として合計し、確定と揺れを分類する" {
  let tally = @lib.Tally::new(tally_keys)
  tally.record("web:alice", judgement("a", { "a": 0.9, "b": 0.1, "none": 0.0 }))
  tally.record("web:bob", judgement("b", { "a": 0.4, "b": 0.5, "none": 0.1 }))
  let snapshot = tally.snapshot()
  inspect(snapshot.totals["a"], content="1.3")
  inspect(snapshot.totals["b"], content="0.6")
  inspect(snapshot.totals["none"], content="0.1")
  inspect(snapshot.participants, content="2")
  inspect(snapshot.confident, content="1")
  inspect(snapshot.wavering, content="1")
  inspect(snapshot.none_count, content="0")
}

///|
test "同じ参加者の最新発言で上書きされ、1 人 1 分布になる" {
  let tally = @lib.Tally::new(tally_keys)
  tally.record("web:alice", judgement("a", { "a": 0.9, "b": 0.1 }))
  tally.record("web:alice", judgement("b", { "a": 0.2, "b": 0.8 }))
  let snapshot = tally.snapshot()
  inspect(snapshot.participants, content="1")
  inspect(snapshot.totals["a"], content="0.2")
  inspect(snapshot.totals["b"], content="0.8")
}

///|
test "最大確率が none の発言は none_count に数え、確定/揺れには含めない" {
  let tally = @lib.Tally::new(tally_keys)
  tally.record(
    "twitch:1",
    judgement("none", { "a": 0.1, "b": 0.1, "none": 0.8 }),
  )
  tally.record(
    "twitch:2",
    judgement("none", { "a": 0.3, "b": 0.2, "none": 0.5 }),
  )
  let snapshot = tally.snapshot()
  inspect(snapshot.participants, content="2")
  inspect(snapshot.none_count, content="2")
  inspect(snapshot.confident, content="0")
  inspect(snapshot.wavering, content="0")
}

///|
test "最大確率がちょうど 0.8 なら確定" {
  let tally = @lib.Tally::new(tally_keys)
  tally.record("x", judgement("a", { "a": 0.8, "b": 0.2 }))
  inspect(tally.snapshot().confident, content="1")
}

///|
test "分布に無い選択肢は 0、Poll に無い key は無視する" {
  let tally = @lib.Tally::new(tally_keys)
  tally.record("x", judgement("a", { "a": 1.0, "zelda": 5.0 }))
  let snapshot = tally.snapshot()
  debug_inspect(snapshot.totals, content="{ \"a\": 1, \"b\": 0, \"none\": 0 }")
}

///|
test "Tally::latest で参加者の最新判定を引ける" {
  let tally = @lib.Tally::new(tally_keys)
  tally.record("x", judgement("a", { "a": 1.0 }))
  assert_true(tally.latest("x") is Some({ choice: "a", .. }))
  assert_true(tally.latest("y") is None)
}

///|
test "participant_id は Source 名のプレフィックスを付ける" {
  inspect(@lib.participant_id("youtube", "UC123"), content="youtube:UC123")
  inspect(@lib.participant_id("twitch", "42"), content="twitch:42")
}

///|
test "Snapshot は JSON にできる" {
  let tally = @lib.Tally::new(["a", "none"])
  tally.record("x", judgement("a", { "a": 0.75, "none": 0.25 }))
  json_inspect(tally.snapshot(), content={
    "totals": { "a": 0.75, "none": 0.25 },
    "participants": 1,
    "confident": 0,
    "wavering": 1,
    "none_count": 0,
  })
}
