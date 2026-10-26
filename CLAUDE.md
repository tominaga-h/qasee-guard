# CLAUDE.md

このファイルは、Claude Code（claude.ai/code）がこのリポジトリのコードを扱うときの手引きです。

## 概要

QaseeGuard は macOS のメニューバー常駐アプリ（`LSUIElement`、Dock に出ない）。QaseeClient（`com.zerofield.QaseeClient`）の起動/終了ボタンを出し、平日の始業時間（9:30）を過ぎても QaseeClient が起動していなければ、メニューバーを赤字にして通知する。Xcode プロジェクトや SwiftPM は使っておらず、`swiftc` で直接ビルドする。macOS 13 以降が対象。

コメント・UI 文言・コミットメッセージはすべて日本語。利用者は技術者ではない前提なので、文言はやさしい言葉にそろえる。

## コマンド

```bash
bash build.sh                              # ビルドして /Applications/QaseeGuard.app に入れる（動いている QaseeGuard は止める）
APP=build/QaseeGuard.app bash build.sh     # 指定した場所に作る（/Applications は触らない）
ARCHS=arm64 bash build.sh                  # 1 つの CPU だけ（既定は "x86_64 arm64" のユニバーサル）
bash package.sh [アプリのパス] [環境名]     # dist/QaseeGuard-<版>-<環境名>.zip を作る
```

テストやリンターはない。動作確認は実際に起動して行う。

- `/Applications/QaseeGuard.app/Contents/MacOS/QaseeGuard --test-notification` … 「（テスト）」付きの未起動通知をすぐ出す（押しても QaseeClient は起動しない）
- `--check-update` … 起動直後に更新確認を走らせる
- 環境変数 `QASEEGUARD_UPDATE_AUTO_CONFIRM=1` … 更新のダイアログを出さずに進める（失敗もダイアログにせずログだけ）
- ログは `NSLog`（`log stream --predicate 'process == "QaseeGuard"'` で見られる）。入れ替えスクリプトのログは `~/Library/Logs/QaseeGuard-update.log`

ソースファイルを増やしたら、`build.sh` の `swiftc` の引数にも追加すること（ファイルを列挙している）。

## 構成

- `main.swift` … `AppDelegate` がすべて。状態は UserDefaults の 2 つのキーで、どちらも値は当日の日付文字列（`yyyy-MM-dd`）。日付が変われば自然に無効になる。
  - `dayOffDate` … メニューの「今日は警告を出さない」
  - `finishedDate` … 「終了…」で QaseeClient を止めたときに入る（終業扱い）。「起動」で消える
  - 警告の判定は `shouldWarn`（未起動・平日・始業時間以降・休みでも終業でもない）。メニューバーは 20 秒ごとのタイマーと、NSWorkspace の起動/終了/スリープ復帰の通知で `refresh()` する。メニューは開くたびに `menuNeedsUpdate` で作り直す。
- `Updater.swift` … GitHub Releases（`tominaga-h/qasee-guard`）からの自動更新。最新リリースを取得 → この Mac 用の zip（`hw.optional.arm64` で判定し、Rosetta で動いていても Apple シリコン用を選ぶ）と `.sha256` を取得して照合 → 展開して codesign・バンドル ID・バージョンを確認 → 切り離した bash スクリプトが QaseeGuard の終了を待ってアプリを入れ替え、起動し直す。失敗したら元のアプリを残す。
- `Symbol.swift` … `menubar-symbol.svg` のパスをそのまま埋め込み、`NSBezierPath` で描くメニューバー用シンボル。SVG を変えたらパス文字列もここに写す（M/L/C/Z の絶対座標だけに対応）。
- `make_icon.swift` … `build.sh` から呼ばれ、`icon-src.png` を 1024px の透明キャンバスに置き直す。そこから `.icns` を作る。

## リリース

`.github/workflows/release.yml` が、Apple シリコン用（`macos-15`）と Intel 用（`macos-15-intel`）を別々にビルドする。`v*` のタグを push したときだけ、そのタグで GitHub Releases に公開する（main への push とプルリクエストはビルドの確認だけ）。**リリースしたいときは `Info.plist` の `CFBundleShortVersionString` をタグと同じ値にしてコミットし、そのコミットに `v<版>` のタグを打って push する。** タグと `Info.plist` が違うと CI はエラーで止まる。`CFBundleVersion` は CI では `github.run_number` で上書きされる。

Updater と CI は次の約束でつながっているので、どちらかを変えるときはもう一方も合わせる。

- タグ名は `v<版>`、zip 名は `QaseeGuard-<版>-mac-apple-silicon.zip` / `QaseeGuard-<版>-mac-intel.zip`、それぞれに `<zip名>.sha256` を付ける
- zip の中は `QaseeGuard/QaseeGuard.app`（`package.sh` の `ditto --keepParent` による）
- zip 内の `CFBundleShortVersionString` がタグの版と一致すること
- 署名はアドホック（`codesign --sign -`）。Updater は `codesign --verify --strict` が通るかとバンドル ID しか見ていない

`package.sh` のコメントにある「はじめにお読みください.txt」は `dist/QaseeGuard/` に手で置いているだけで、git の管理外（`dist/` は .gitignore 対象）。そのため CI で作る zip には入らない。
