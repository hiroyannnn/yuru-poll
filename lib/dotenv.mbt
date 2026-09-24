///|
/// `.env` の中身を読む（yuru-come から移植）。`KEY=value` の行だけを取り、`#` のコメント・空行・`export` を無視する。
/// 値は前後の空白を除き、`"…"` / `'…'` で囲まれていれば中身をそのまま（囲みの外の `# …` は捨てる）。
pub fn parse_dotenv(text : String) -> Map[String, String] {
  let env : Map[String, String] = Map([])
  for raw_line in text.split("\n") {
    let line = raw_line.trim(chars=" \t\r").to_owned()
    if line.is_empty() || line.has_prefix("#") {
      continue
    }
    let line = if line.has_prefix("export ") {
      line["export ".length():].trim_start(chars=" \t").to_owned()
    } else {
      line
    }
    guard line.find("=") is Some(eq) else { continue }
    let key = line[:eq].trim(chars=" \t").to_owned()
    guard !key.is_empty() && !key.contains(" ") else { continue }
    env[key] = dotenv_value(line[eq + 1:].trim(chars=" \t").to_owned())
  }
  env
}

///|
fn dotenv_value(raw : String) -> String {
  for quote in ['"', '\''] {
    if raw.has_prefix(quote.to_string()) {
      let inner = raw[quote.to_string().length():]
      return match inner.find(quote.to_string()) {
        Some(end) => inner[:end].to_owned()
        None => inner.to_owned()
      }
    }
  }
  match raw.find(" #") {
    Some(i) => raw[:i].trim_end(chars=" \t").to_owned()
    None => raw
  }
}

///|
/// 環境変数を優先し、無いキーだけを `.env` で補う。
pub fn merge_env(
  env : Map[String, String],
  dotenv : Map[String, String],
) -> Map[String, String] {
  let merged : Map[String, String] = Map([])
  for key, value in dotenv {
    merged[key] = value
  }
  for key, value in env {
    merged[key] = value
  }
  merged
}
