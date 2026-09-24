.PHONY: test check assets build release

# 全ターゲットのテスト
test:
	moon test --target all

# コミット前の確認（.mbti の更新、整形、埋め込み資産の同期、型検査、Workers グルーの構文）
check:
	moon info
	moon fmt
	python3 scripts/embed_assets.py --check
	moon check --target all
	node --check cloudflare/src/index.mjs

# web/ を編集したら実行して adapters/web/assets.mbt を作り直す
assets:
	python3 scripts/embed_assets.py

# このマシン向けのリリースビルド（_build/native/release/build/cmd/yuru-poll/yuru-poll.exe）
build:
	moon build --target native --release

# 使い方: make release v=0.2.0
# バージョンを moon.mod と cmd/yuru-poll/version.mbt に書き、コミットして GitHub Release を作る。
# Release が公開されると .github/workflows/release.yml が macOS と Linux のバイナリを添付する。
release:
	@test -n "$(v)" || (echo "Usage: make release v=0.2.0" && exit 1)
	@git diff --quiet || (echo "コミットしていない変更があります" && exit 1)
	@$(MAKE) check
	@moon test --target all
	sed -i '' 's/^version = "[^"]*"/version = "$(v)"/' moon.mod
	sed -i '' 's/^pub const VERSION : String = "[^"]*"/pub const VERSION : String = "$(v)"/' cmd/yuru-poll/version.mbt
	git add moon.mod cmd/yuru-poll/version.mbt
	git commit -m "release: v$(v)"
	git push
	gh release create "v$(v)" --generate-notes --title "v$(v)"
