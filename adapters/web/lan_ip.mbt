///|
/// 参加者がスマホから開ける LAN 上の IP アドレスを推定する。
/// macOS は `ipconfig getifaddr en0/en1`、Linux は `hostname -I` を試し、
/// どれも取れなければ `localhost`。`--public-url` で上書きできる。
pub async fn guess_lan_ip() -> String {
  for
    candidate in [
      ("ipconfig", ["getifaddr", "en0"]),
      ("ipconfig", ["getifaddr", "en1"]),
      ("hostname", ["-I"]),
    ] {
    let (command, args) = candidate
    let ip = first_token_of(command, args) catch { _ => continue }
    if !ip.is_empty() {
      return ip
    }
  }
  "localhost"
}

///|
async fn first_token_of(command : String, args : Array[String]) -> String {
  let (code, output) = @process.collect_stdout(command, args)
  if code != 0 {
    return ""
  }
  let text = output.text()
  match text.trim(chars=" \t\r\n").split(" ").iter().next() {
    Some(token) => token.to_owned()
    None => ""
  }
}
