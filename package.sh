#!/bin/bash
# 配布用の zip を作る（アプリ + はじめにお読みください.txt）
#
# 使い方:
#   bash package.sh [アプリのパス] [名前に付ける環境名]
#     アプリのパス … 既定: /Applications/QaseeGuard.app
#     環境名       … 既定: mac-universal（例: mac-apple-silicon / mac-intel）
#
# 環境変数:
#   ARCHS  アプリに入っているはずの CPU（既定: "x86_64 arm64"）。違っていたらエラーにする
#
# 作った zip のパスだけを標準出力に出す（ほかのメッセージは標準エラー）
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:-/Applications/QaseeGuard.app}"
LABEL="${2:-mac-universal}"
ARCHS="${ARCHS:-x86_64 arm64}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT="dist/QaseeGuard-$VERSION-$LABEL.zip"

# 想定どおりの CPU 向けになっているか確認
# shellcheck disable=SC2086
lipo "$APP/Contents/MacOS/QaseeGuard" -verify_arch $ARCHS
lipo -info "$APP/Contents/MacOS/QaseeGuard" >&2

rm -rf dist/QaseeGuard/QaseeGuard.app "$OUT"
ditto "$APP" dist/QaseeGuard/QaseeGuard.app
xattr -cr dist/QaseeGuard
codesign --verify --strict dist/QaseeGuard/QaseeGuard.app >&2

ditto -c -k --norsrc --keepParent dist/QaseeGuard "$OUT"
echo "packaged: $OUT" >&2
echo "$OUT"
