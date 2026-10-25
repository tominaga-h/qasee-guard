#!/bin/bash
# 配布用の zip を作る（アプリ + はじめにお読みください.txt）
#
# 使い方:
#   bash package.sh [アプリのパス]   （既定: /Applications/QaseeGuard.app）
#
# 作った zip のパスだけを標準出力に出す（ほかのメッセージは標準エラー）
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:-/Applications/QaseeGuard.app}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT="dist/QaseeGuard-$VERSION.zip"

# Intel / Apple シリコンの両方が入っているか確認
lipo "$APP/Contents/MacOS/QaseeGuard" -verify_arch x86_64 arm64

rm -rf dist/QaseeGuard/QaseeGuard.app "$OUT"
ditto "$APP" dist/QaseeGuard/QaseeGuard.app
xattr -cr dist/QaseeGuard
codesign --verify --strict dist/QaseeGuard/QaseeGuard.app >&2

ditto -c -k --norsrc --keepParent dist/QaseeGuard "$OUT"
echo "packaged: $OUT" >&2
echo "$OUT"
