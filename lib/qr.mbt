///|
/// QR の周囲に空ける余白（quiet zone）。規格で 4 モジュール以上が必要。
const QR_MARGIN_MODULES : Int = 4

///|
/// SVG での 1 モジュールの大きさ（px）。
const QR_CELL_PX : Int = 8

///|
/// 文字列（参加用 URL）を QR のマトリクスにする。空文字や長すぎる文字列は None。
/// 誤り訂正レベルは M。スマホのカメラで画面越しに読む用途に十分な強さ。
pub fn qr_matrix(text : String) -> @moonqr.Matrix? {
  @moonqr.encode(text, @moonqr.EcLevel::M, None)
}

///|
/// 文字列を余白付きの QR の SVG にする。
pub fn qr_svg(text : String) -> String? {
  match qr_matrix(text) {
    Some(matrix) =>
      Some(@moonqr.to_svg_string(matrix, QR_MARGIN_MODULES, QR_CELL_PX))
    None => None
  }
}
