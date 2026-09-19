///|
test "RateLimiter は窓の中で limit 回まで許可し、超えたら拒否する" {
  let limiter = @lib.RateLimiter::new(limit=3, window_ms=1000)
  inspect(limiter.allow("ip:1", 0), content="true")
  inspect(limiter.allow("ip:1", 100), content="true")
  inspect(limiter.allow("ip:1", 200), content="true")
  inspect(limiter.allow("ip:1", 300), content="false")
  inspect(limiter.allow("ip:1", 999), content="false")
}

///|
test "窓を過ぎた分は数えず、拒否された試行は回数に入れない" {
  let limiter = @lib.RateLimiter::new(limit=2, window_ms=1000)
  inspect(limiter.allow("k", 0), content="true")
  inspect(limiter.allow("k", 500), content="true")
  inspect(limiter.allow("k", 600), content="false")
  inspect(limiter.allow("k", 1001), content="true")
  inspect(limiter.allow("k", 1200), content="false")
  inspect(limiter.allow("k", 1501), content="true")
}

///|
test "キーごとに独立して数える" {
  let limiter = @lib.RateLimiter::new(limit=1, window_ms=1000)
  inspect(limiter.allow("a", 0), content="true")
  inspect(limiter.allow("b", 0), content="true")
  inspect(limiter.allow("a", 1), content="false")
}

///|
test "使われなくなったキーは掃除され、覚えているキーが増え続けない" {
  let limiter = @lib.RateLimiter::new(limit=1, window_ms=1000)
  for i in 0..<3000 {
    limiter.allow("ip:\{i}", i.to_int64()) |> ignore
  }
  assert_true(limiter.tracked_keys() < 2100)
}
