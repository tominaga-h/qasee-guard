#!/bin/bash
# QaseeGuard をビルドして /Applications/QaseeGuard.app に置く
set -euo pipefail
cd "$(dirname "$0")"
APP="/Applications/QaseeGuard.app"

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

# Intel と Apple Silicon の両方向けにビルドして 1 つにまとめる
for arch in x86_64 arm64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" main.swift Symbol.swift -o "build/QaseeGuard-$arch"
done
lipo -create build/QaseeGuard-x86_64 build/QaseeGuard-arm64 -output build/QaseeGuard

pkill -x QaseeGuard 2>/dev/null || true
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp build/QaseeGuard "$APP/Contents/MacOS/QaseeGuard"
[ -f build/AppIcon.icns ] && cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
touch "$APP"   # Finder にアイコン変更を気づかせる
echo "built: $APP"
