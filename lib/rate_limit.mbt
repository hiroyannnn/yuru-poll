///|
/// キー（IP や参加者 ID）ごとに「window_ms の間に limit 回まで」を許可するレート制限器。
/// 時刻は呼び出し側から渡すので純粋で、テストしやすい。
pub struct RateLimiter {
  limit : Int
  window_ms : Int64
  /// キー → 許可した時刻（古い順）
  hits : Map[String, Array[Int64]]
  mut calls_since_sweep : Int
}

///|
/// 何回の呼び出しごとに、使われなくなったキーを掃除するか。
const SWEEP_EVERY : Int = 1000

///|
pub fn RateLimiter::new(limit~ : Int, window_ms~ : Int64) -> RateLimiter {
  { limit, window_ms, hits: Map([]), calls_since_sweep: 0, }
}

///|
/// 許可するなら true を返して 1 回分を記録する。拒否した試行は記録しない。
pub fn RateLimiter::allow(
  self : RateLimiter,
  key : String,
  now_ms : Int64,
) -> Bool {
  self.calls_since_sweep += 1
  if self.calls_since_sweep >= SWEEP_EVERY {
    self.sweep(now_ms)
  }
  let recent = self.hits
    .get(key)
    .unwrap_or([])
    .filter(t => now_ms - t < self.window_ms)
  let allowed = recent.length() < self.limit
  if allowed {
    recent.push(now_ms)
  }
  self.hits[key] = recent
  allowed
}

///|
/// 窓の中に記録が残っていないキーを捨てる。
fn RateLimiter::sweep(self : RateLimiter, now_ms : Int64) -> Unit {
  self.calls_since_sweep = 0
  let stale : Array[String] = []
  for key, times in self.hits {
    if !times.iter().any(t => now_ms - t < self.window_ms) {
      stale.push(key)
    }
  }
  for key in stale {
    self.hits.remove(key)
  }
}

///|
/// 覚えているキーの数（テストと監視用）。
pub fn RateLimiter::tracked_keys(self : RateLimiter) -> Int {
  self.hits.length()
}
