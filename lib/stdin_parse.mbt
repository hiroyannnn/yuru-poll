///|
/// 標準入力の 1 行（`参加者ID<TAB>発言`）を Comment にする。
/// TAB が無ければ匿名参加者（`stdin:anon`）の発言。空行は None。
pub fn parse_stdin_line(line : String, at~ : Int64) -> Comment? {
  let trimmed = line.trim(chars=" \t\r\n").to_owned()
  if trimmed.is_empty() {
    return None
  }
  let (id, text) = match trimmed.find("\t") {
    Some(i) =>
      (trimmed[:i].to_owned(), trimmed[i + 1:].trim(chars=" \t").to_owned())
    None => ("anon", trimmed)
  }
  Some({ participant_id: participant_id("stdin", id), text, at, })
}
