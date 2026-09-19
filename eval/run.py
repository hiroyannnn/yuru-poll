#!/usr/bin/env python3
"""指示文（instructions）の候補を評価セットで比べる。標準ライブラリだけで動く。

依存は Python 3 の標準ライブラリと curl だけ。

使い方:
  # ホスト版のルーム経由（API キー不要。1 候補につきルームを 1 つ作り、終わったら閉じる）
  python3 eval/run.py --via-room https://<your-worker>.workers.dev

  # TypeSafe 互換 API を直接呼ぶ（JEV_API_KEY が必要。JEV_MODEL は省略可）
  JEV_API_KEY=... python3 eval/run.py --jev-url https://ai-gateway.vercel.sh/typesafe --model typesafe-ai/jev

指標:
  正解率      expect のある発言で、最大確率の key が expect と一致した割合
  迷いの分割  split のある発言で、挙げた key のそれぞれに 0.2 以上の確率が乗った割合
"""
import argparse, json, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def http(method, url, body=None, headers=None):
    """curl で呼ぶ（Python の CA 証明書の設定に左右されないようにするため）。"""
    cmd = ["curl", "-sS", "-m", "60", "-X", method, url, "-H", "Content-Type: application/json", "-w", "\n%{http_code}"]
    for key, value in (headers or {}).items():
        cmd += ["-H", f"{key}: {value}"]
    if body is not None:
        cmd += ["--data-binary", json.dumps(body, ensure_ascii=False)]
    done = subprocess.run(cmd, capture_output=True, text=True)
    if done.returncode != 0:
        # タイムアウトなど。呼び出し側がやり直せるよう、失敗として返す
        return 0, {"raw": done.stderr.strip()[:200]}
    text, _, code = done.stdout.rpartition("\n")
    try:
        return int(code), json.loads(text or "{}")
    except json.JSONDecodeError:
        return int(code), {"raw": text[:200]}


def with_candidate(poll, candidate):
    """候補は指示文の文字列か、{"instructions": ..., "none": <none の説明文>}。"""
    if isinstance(candidate, str):
        return {**poll, "instructions": candidate}
    choices = [c for c in poll["choices"] if c["key"] != "none"]
    if candidate.get("none"):
        choices.append({"key": "none", "label": "どれでもない", "description": candidate["none"]})
    return {**poll, "choices": choices, "instructions": candidate["instructions"]}


def judge_via_room(base, poll, cases, pause):
    status, room = http("POST", f"{base}/api/rooms", poll)
    if status != 200:
        sys.exit(f"ルームを作れません: {status} {room}")
    token = room["host_url"].split("#host=")[1]
    out = []
    try:
        for i, case in enumerate(cases):
            for attempt in range(6):
                status, res = http("POST", f"{base}/r/{room['room']}/api/comment", {"participant_id": f"eval-{i}-{attempt}", "comment": case["text"]})
                if status == 200:
                    break
                # 429 は連投制限、502 は判定の一時的な失敗。少し待ってやり直す
                time.sleep(5)
            out.append(res["judgement"]["probabilities"] if status == 200 else None)
            time.sleep(pause)
    finally:
        http("POST", f"{base}/r/{room['room']}/api/close", headers={"Authorization": f"Bearer {token}"})
    return out


def judge_direct(jev_url, model, poll, cases):
    instructions = poll["instructions"]
    criteria = {c["key"]: (f"{c['label']}: {c['description']}" if c.get("description") else c["label"]) for c in poll["choices"]}
    criteria.setdefault("none", "どれでもない: 投票と関係のない雑談・挨拶・意味不明な発言、または選択肢を否定しているだけの発言")
    out = []
    for case in cases:
        body = {"state": {"question": poll["question"], "comment": case["text"]}, "model": model,
                "questions": {"vote": {"type": "choice", "instructions": instructions, "criteria": criteria}}}
        for _ in range(3):
            status, res = http("POST", f"{jev_url.rstrip('/')}/v1/systemone", body, {"Authorization": f"Bearer {os.environ.get('JEV_API_KEY', 'local')}"})
            if status == 200:
                break
            time.sleep(2)
        out.append(res["answers"]["vote"]["probabilities"] if status == 200 else None)
    return out


def score(cases, results):
    right = total = split_ok = split_total = failed = 0
    for case, probs in zip(cases, results):
        if probs is None:
            failed += 1
            continue
        if "expect" in case:
            total += 1
            right += max(probs, key=probs.get) == case["expect"]
        else:
            split_total += 1
            split_ok += all(probs.get(k, 0) >= 0.2 for k in case["split"])
    return {"accuracy": f"{right}/{total}", "split": f"{split_ok}/{split_total}", "failed": failed}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--via-room")
    ap.add_argument("--jev-url")
    ap.add_argument("--model", default=os.environ.get("JEV_MODEL", "jev-latest"))
    ap.add_argument("--set", default="eval/next-game.json")
    ap.add_argument("--only", nargs="*", help="評価する候補名（省略時は全部）")
    ap.add_argument("--pause", type=float, default=3.2, help="ルーム経由のときの発言間隔（秒）。接続元ごとの 1 分 20 回の制限に合わせる")
    ap.add_argument("--out", default=None, help="結果の JSON を書き出すパス")
    args = ap.parse_args()
    if not (args.via_room or args.jev_url):
        ap.error("--via-room か --jev-url のどちらかが必要です")

    dataset = json.load(open(os.path.join(ROOT, args.set), encoding="utf-8"))
    poll = json.load(open(os.path.join(ROOT, dataset["poll"]), encoding="utf-8"))
    candidates = json.load(open(os.path.join(ROOT, "eval/instructions.json"), encoding="utf-8"))
    cases = dataset["cases"]
    report = {}
    for name, candidate in candidates.items():
        if name.startswith("_") or (args.only and name not in args.only):
            continue
        candidate_poll = with_candidate(poll, candidate)
        results = (judge_via_room(args.via_room.rstrip("/"), candidate_poll, cases, args.pause)
                   if args.via_room else judge_direct(args.jev_url, args.model, candidate_poll, cases))
        report[name] = {"score": score(cases, results), "results": results}
        print(f"{name}: {report[name]['score']}", flush=True)
        if args.out:  # 途中で止まっても結果が残るよう、候補ごとに書き出す
            json.dump({"cases": cases, "report": report}, open(args.out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
