#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v cmake >/dev/null
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  echo '需要完整 Xcode 和 iOS SDK；Command Line Tools 无法构建 iOS。' >&2
  exit 1
fi
output="$ROOT_DIR/dist/ios/gremote_imaging.xcframework"
if [[ -e "$output" ]]; then
  echo 'XCFramework 已存在。请先移动旧产物，再重新构建。' >&2
  exit 1
fi
for sdk in iphoneos iphonesimulator; do
  arch=arm64
  build="$ROOT_DIR/build/ios-imaging/$sdk"
  cmake -S "$ROOT_DIR/native/imaging" -B "$build" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_C_FLAGS_RELEASE='-O3 -DNDEBUG -g' \
    -DCMAKE_CXX_FLAGS_RELEASE='-O3 -DNDEBUG -g' \
    -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
    -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf-with-dsym
  cmake --build "$build" --config Release --target gremote_imaging --parallel 4
  framework="$build/Release-$sdk/gremote_imaging.framework"
  symbols="$build/Release-$sdk/gremote_imaging.framework.dSYM"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$framework/Info.plist" >/dev/null
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$framework/Info.plist" >/dev/null
  test -f "$symbols/Contents/Resources/DWARF/gremote_imaging"
  binary_uuid="$(xcrun dwarfdump --uuid "$framework/gremote_imaging" | awk '{print $2}')"
  symbols_uuid="$(xcrun dwarfdump --uuid "$symbols" | awk '{print $2}')"
  if [[ -z "$binary_uuid" || "$binary_uuid" != "$symbols_uuid" ]]; then
    echo "$sdk framework 与 dSYM UUID 不匹配。" >&2
    exit 1
  fi
 done
mkdir -p "$(dirname "$output")"
xcodebuild -create-xcframework \
  -framework "$ROOT_DIR/build/ios-imaging/iphoneos/Release-iphoneos/gremote_imaging.framework" \
  -debug-symbols "$ROOT_DIR/build/ios-imaging/iphoneos/Release-iphoneos/gremote_imaging.framework.dSYM" \
  -framework "$ROOT_DIR/build/ios-imaging/iphonesimulator/Release-iphonesimulator/gremote_imaging.framework" \
  -debug-symbols "$ROOT_DIR/build/ios-imaging/iphonesimulator/Release-iphonesimulator/gremote_imaging.framework.dSYM" \
  -output "$output"
