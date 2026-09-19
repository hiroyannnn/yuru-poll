///|
/// Twitch IRC から読んだ 1 行の解釈結果。
pub enum IrcMessage {
  /// サーバからの PING。payload をそのまま PONG で返す
  Ping(String)
  /// チャット発言
  Chat(Comment)
  /// それ以外（接続時の挨拶など）
  Other(String)
} derive(Debug, Eq)

///|
/// 匿名ユーザーで読み取り専用接続するためのログイン行。
/// `twitch.tv/tags` を要求して user-id と送信時刻を受け取る。
pub fn twitch_login_lines(nick : String, channel : String) -> Array[String] {
  ["CAP REQ :twitch.tv/tags", "NICK \{nick}", "JOIN #\{channel.to_lower()}"]
}

///|
/// PING への返答行。
pub fn pong_line(payload : String) -> String {
  "PONG :\{payload}"
}

///|
/// IRC の 1 行（`[@tags] [:prefix] COMMAND [params] [:trailing]`）を解釈する。
pub fn parse_irc_line(raw : String) -> IrcMessage {
  let line = raw.trim(chars="\r\n").to_owned()
  let mut rest = line.view()
  let tags = if rest is ['@', .. after_at] {
    let (tag_part, after) = split_once(after_at, ' ')
    rest = after
    parse_tags(tag_part)
  } else {
    Map([])
  }
  let prefix = if rest is [':', .. after_colon] {
    let (p, after) = split_once(after_colon, ' ')
    rest = after
    p.to_owned()
  } else {
    ""
  }
  let (command, params) = split_once(rest, ' ')
  match command {
    "PING" => Ping(trailing_of(params))
    "PRIVMSG" => {
      let text = trailing_of(params)
      let id = match tags.get("user-id") {
        Some(user_id) if !user_id.is_empty() => user_id
        _ => nick_of(prefix)
      }
      let at = match tags.get("tmi-sent-ts") {
        Some(ts) => parse_int64(ts)
        None => 0
      }
      Chat({ participant_id: participant_id("twitch", id), text, at, })
    }
    _ => Other(line)
  }
}

///|
/// `sep` で最初の 1 回だけ分割する。見つからなければ残りは空。
fn split_once(s : StringView, sep : Char) -> (StringView, StringView) {
  match s.find(sep.to_string()) {
    Some(i) => (s[:i], s[i + 1:])
    None => (s, "")
  }
}

///|
/// params の `:` 以降（trailing）を取り出す。無ければ params 全体。
fn trailing_of(params : StringView) -> String {
  match params.find(":") {
    Some(i) => params[i + 1:].to_owned()
    None => params.to_owned()
  }
}

///|
/// `nick!user@host` から nick を取り出す。
fn nick_of(prefix : String) -> String {
  match prefix.find("!") {
    Some(i) => prefix[:i].to_owned()
    None => prefix
  }
}

///|
fn parse_tags(part : StringView) -> Map[String, String] {
  let tags : Map[String, String] = Map([])
  for pair in part.split(";") {
    let (key, value) = split_once(pair, '=')
    tags[key.to_owned()] = value.to_owned()
  }
  tags
}

///|
fn parse_int64(s : String) -> Int64 {
  let mut n : Int64 = 0
  for c in s {
    guard c is ('0'..='9') else { return 0 }
    n = n * 10 + (c.to_int() - '0').to_int64()
  }
  n
}
