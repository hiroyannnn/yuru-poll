#!/usr/bin/env python3
"""web/ の静的ファイルを adapters/web/assets.mbt に埋め込む（バイナリ 1 つで動かすため。yuru-come から移植）。

    python3 scripts/embed_assets.py          # 生成
    python3 scripts/embed_assets.py --check  # 生成物が最新かを確かめる（CI 用）
"""
import pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
WEB = ROOT / "web"
OUT = ROOT / "adapters" / "web" / "assets.mbt"
FILES = ["index.html", "join.html", "overlay.html"]  # new.html はホスト版専用


def mbt_string(text: str) -> str:
    # MoonBit の文字列リテラル。バックスラッシュ・二重引用符・改行・補間の { を逃がす
    escaped = (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\r", "")
        .replace("\n", "\\n")
        .replace("\\{", "\\\\{")
    )
    return '"' + escaped + '"'


def render() -> str:
    parts = [
        "///|",
        "/// scripts/embed_assets.py が web/ から生成する。手で編集しない。",
        "/// `--web-dir` を指定しないとき、この中身を返す。",
        "let embedded_assets : Map[String, String] = {",
    ]
    for name in FILES:
        parts.append(f"  {mbt_string(name)}: {mbt_string((WEB / name).read_text(encoding='utf-8'))},")
    parts.append("}")
    return "\n".join(parts) + "\n"


def main() -> int:
    content = render()
    if "--check" in sys.argv:
        current = OUT.read_text(encoding="utf-8") if OUT.exists() else ""
        if current != content:
            print(f"{OUT.relative_to(ROOT)} が web/ と合っていません。python3 scripts/embed_assets.py を実行してください", file=sys.stderr)
            return 1
        return 0
    OUT.write_text(content, encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(content)} chars)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
