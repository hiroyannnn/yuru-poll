///|
/// CLI フラグで選んだ Source / Sink の組み合わせ。
pub(all) struct CliOptions {
  poll_path : String
  sources : Array[String]
  sinks : Array[String]
  port : Int
  public_url : String?
  twitch_channel : String?
  youtube_video_id : String?
  /// 静的ファイルの場所。None ならバイナリに埋め込んだものを使う
  web_dir : String?
} derive(Debug)

///|
pub suberror CliError {
  MissingValue(String)
  UnknownOption(String)
  MissingPoll
  /// `--version` / `-V`。エラーではなく、main がバージョンを表示して終わる
  ShowVersion
  /// `--help` / `-h`
  ShowHelp
  BadNumber(String)
} derive(Debug)

///|
pub const DEFAULT_PORT : Int = 8787

///|
pub let usage : String =
  #|使い方: yuru-poll --poll <poll.json> [--source <name>]... [--sink <name>]...
  #|
  #|  --source stdin|web|youtube|twitch   発言の入口（複数指定可、既定 stdin）
  #|  --sink terminal|web                 集計の出口（複数指定可、既定 terminal）
  #|  --twitch <channel>                  Twitch のチャンネル名（--source twitch 用）
  #|  --youtube <videoId>                 YouTube Live の動画 ID（--source youtube 用。YOUTUBE_API_KEY があれば Data API、無ければキー無しで読む）
  #|  --port <n>                          ウェブサーバのポート（既定 8787）
  #|  --public-url <url>                  参加用 URL の元（既定は LAN IP から推定）
  #|  --web-dir <dir>                     静的ファイルの場所（省略時はバイナリに埋め込んだものを使う）
  #|  --version                           バージョンを表示
  #|
  #|環境変数: JEV_URL（既定 http://127.0.0.1:8000）、JEV_API_KEY（既定 local）、JEV_MODEL（既定 jev-latest）、YOUTUBE_API_KEY
  #|カレントディレクトリの .env も読み、環境変数に無いキーだけを補います

///|
/// 引数列（プログラム名を除く）を解釈する。
pub fn parse_cli(args : ArrayView[String]) -> CliOptions raise CliError {
  let mut poll_path : String? = None
  let sources : Array[String] = []
  let sinks : Array[String] = []
  let mut port = DEFAULT_PORT
  let mut public_url : String? = None
  let mut twitch_channel : String? = None
  let mut youtube_video_id : String? = None
  let mut web_dir : String? = None
  let mut i = 0
  while i < args.length() {
    let flag = args[i]
    let value = () => {
      if i + 1 >= args.length() {
        raise MissingValue(flag)
      }
      i += 1
      args[i]
    }
    match flag {
      "--poll" => poll_path = Some(value())
      "--source" => sources.push(value())
      "--sink" => sinks.push(value())
      "--port" => {
        let text = value()
        port = @string.parse_int(text) catch { _ => raise BadNumber(text) }
      }
      "--public-url" => public_url = Some(value())
      "--twitch" => twitch_channel = Some(value())
      "--youtube" => youtube_video_id = Some(value())
      "--web-dir" => web_dir = Some(value())
      "--version" | "-V" => raise ShowVersion
      "--help" | "-h" => raise ShowHelp
      _ => raise UnknownOption(flag)
    }
    i += 1
  }
  guard poll_path is Some(poll_path) else { raise MissingPoll }
  {
    poll_path,
    sources: if sources.is_empty() {
      ["stdin"]
    } else {
      sources
    },
    sinks: if sinks.is_empty() {
      ["terminal"]
    } else {
      sinks
    },
    port,
    public_url,
    twitch_channel,
    youtube_video_id,
    web_dir,
  }
}
