///|
test ".env の行を読む（コメント・空行・export・引用符・前後の空白）" {
  let text =
    #|# コメント
    #|JEV_URL=https://ai-gateway.vercel.sh/typesafe
    #|
    #|export JEV_MODEL = typesafe-ai/jev
    #|JEV_API_KEY="quoted value" # 末尾コメント
    #|JEV_EXTRA='single quoted'
    #|EMPTY=
    #|BROKEN LINE WITHOUT EQUALS
    #|CONTEXT=雑談 # 配信の話題
    #|HASH_IN_QUOTES="a#b"
  let env = @lib.parse_dotenv(text)
  assert_eq(env.get("JEV_URL"), Some("https://ai-gateway.vercel.sh/typesafe"))
  assert_eq(env.get("JEV_MODEL"), Some("typesafe-ai/jev"))
  assert_eq(env.get("JEV_API_KEY"), Some("quoted value"))
  assert_eq(env.get("JEV_EXTRA"), Some("single quoted"))
  assert_eq(env.get("EMPTY"), Some(""))
  assert_eq(env.get("BROKEN"), None)
  assert_eq(env.get("CONTEXT"), Some("雑談"))
  assert_eq(env.get("HASH_IN_QUOTES"), Some("a#b"))
}

///|
test "環境変数が優先で、.env は無いキーだけを補う" {
  let env : Map[String, String] = { "JEV_URL": "http://127.0.0.1:8000" }
  let merged = @lib.merge_env(
    env,
    @lib.parse_dotenv("JEV_URL=x\nJEV_API_KEY=k"),
  )
  assert_eq(merged.get("JEV_URL"), Some("http://127.0.0.1:8000"))
  assert_eq(merged.get("JEV_API_KEY"), Some("k"))
}
