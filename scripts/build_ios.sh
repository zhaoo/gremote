#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1 || { echo '缺少完整 Xcode / iOS SDK，无法构建 iOS。' >&2; exit 1; }
command -v pod >/dev/null || { echo '缺少 CocoaPods。' >&2; exit 1; }
flutter pub get
flutter analyze
flutter test
python3 scripts/generate_ios_bridges.py
if [[ ! -d dist/ios/gremote_imaging.xcframework ]]; then
  bash scripts/build_ios_imaging.sh
fi
(cd ios && pod install)
case "${1:---no-codesign}" in
  --no-codesign) flutter build ios --release --no-codesign ;;
  --ipa) flutter build ipa --release ;;
  *) echo '用法：bash scripts/build_ios.sh [--no-codesign|--ipa]' >&2; exit 64 ;;
esac
