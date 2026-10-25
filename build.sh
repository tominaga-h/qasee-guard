#!/bin/bash
# QaseeGuard をビルドする（Intel / Apple シリコン両対応）
#
# 使い方:
#   bash build.sh                       … /Applications/QaseeGuard.app に入れる（自分のMac用）
#   APP=build/QaseeGuard.app bash build.sh … 指定した場所に作る（GitHub Actions 用）
#
# 環境変数:
#   APP           出力先（既定: /Applications/QaseeGuard.app）
#   VERSION       アプリのバージョン（例: 1.0.1）。指定すると Info.plist の値を上書き
#   BUILD_NUMBER  ビルド番号。指定すると Info.plist の値を上書き
set -euo pipefail
cd "$(dirname "$0")"
APP="${APP:-/Applications/QaseeGuard.app}"

mkdir -p build

# アイコン（icon-src.png → 余白調整 → .icns）
if [ -f icon-src.png ]; then
  swift make_icon.swift icon-src.png build/icon-1024.png >/dev/null
  rm -rf build/AppIcon.iconset && mkdir -p build/AppIcon.iconset
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out build/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
    d=$((s*2))
    sips -z $d $d build/icon-1024.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

# Intel と Apple シリコンの両方向けにビルドして 1 つにまとめる
for arch in x86_64 arm64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" main.swift Symbol.swift -o "build/QaseeGuard-$arch"
done
lipo -create build/QaseeGuard-x86_64 build/QaseeGuard-arm64 -output build/QaseeGuard

# /Applications に入れ直すときだけ、動いている QaseeGuard を止める
if [ "$APP" = "/Applications/QaseeGuard.app" ]; then
  pkill -x QaseeGuard 2>/dev/null || true
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
[ -n "${VERSION:-}" ] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
[ -n "${BUILD_NUMBER:-}" ] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp build/QaseeGuard "$APP/Contents/MacOS/QaseeGuard"
[ -f build/AppIcon.icns ] && cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
touch "$APP"   # Finder にアイコン変更を気づかせる
echo "built: $APP"
