#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v cmake >/dev/null
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  echo '需要完整 Xcode 和 iOS SDK；Command Line Tools 无法构建 iOS。' >&2
  exit 1
fi
for sdk in iphoneos iphonesimulator; do
  arch=arm64
  build="$ROOT_DIR/build/ios-imaging/$sdk"
  cmake -S "$ROOT_DIR/native/imaging" -B "$build" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
  cmake --build "$build" --config Release --target gremote_imaging --parallel 4
 done
output="$ROOT_DIR/dist/ios/gremote_imaging.xcframework"
if [[ -e "$output" ]]; then
  echo 'XCFramework 已存在。请先移动旧产物，再重新构建。' >&2
  exit 1
fi
mkdir -p "$(dirname "$output")"
xcodebuild -create-xcframework \
  -framework "$ROOT_DIR/build/ios-imaging/iphoneos/Release-iphoneos/gremote_imaging.framework" \
  -framework "$ROOT_DIR/build/ios-imaging/iphonesimulator/Release-iphonesimulator/gremote_imaging.framework" \
  -output "$output"
