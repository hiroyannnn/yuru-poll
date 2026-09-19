///|
/// QR のマトリクスを RGBA の画素列にする（1 モジュール = scale 画素、周囲に margin モジュールの白）。
fn rasterize(
  matrix : @moonqr.Matrix,
  scale : Int,
  margin : Int,
) -> (Bytes, Int) {
  let side = (matrix.size + margin * 2) * scale
  let pixels : Array[Byte] = Array::make(side * side * 4, b'\xff')
  for y in 0..<matrix.size {
    for x in 0..<matrix.size {
      if matrix.get(x, y) {
        for dy in 0..<scale {
          for dx in 0..<scale {
            let px = (x + margin) * scale + dx
            let py = (y + margin) * scale + dy
            let at = (py * side + px) * 4
            pixels[at] = b'\x00'
            pixels[at + 1] = b'\x00'
            pixels[at + 2] = b'\x00'
          }
        }
      }
    }
  }
  (Bytes::from_array(pixels), side)
}

///|
/// 生成した QR を実際にデコードして、元の文字列に戻ることを確かめる。
fn assert_round_trip(text : String) -> Unit raise {
  guard @lib.qr_matrix(text) is Some(matrix) else {
    fail("QR を生成できない: \{text}")
  }
  let (pixels, side) = rasterize(matrix, 4, 4)
  guard @qr_decode.decode(pixels, side, side, false) is Some(result) else {
    fail("デコードできない QR が生成された: \{text}")
  }
  assert_eq(result.text, text)
}

///|
test "参加用 URL の QR は、デコードすると元の URL に戻る（LAN とホスト版）" {
  assert_round_trip("http://192.168.1.63:8787/join")
  assert_round_trip("https://yuru-poll.hiroyannnn.workers.dev/r/orldfdk3/join")
  assert_round_trip("http://localhost:8787/join")
}

///|
test "qr_svg は余白（quiet zone）付きの SVG を返す" {
  let url = "https://example.test/r/abc/join"
  guard @lib.qr_svg(url) is Some(svg) else { fail("SVG を生成できない") }
  guard @lib.qr_matrix(url) is Some(matrix) else {
    fail("QR を生成できない")
  }
  assert_true(svg.has_prefix("<svg"))
  assert_true(svg.contains("fill=\"#fff\""))
  // 余白 4 モジュール × 2 を足した大きさ、1 モジュール 8px
  let side = (matrix.size + 8) * 8
  assert_true(svg.contains("viewBox=\"0 0 \{side} \{side}\""))
}

///|
test "空文字の QR は作れない" {
  assert_true(@lib.qr_svg("") is None)
}
