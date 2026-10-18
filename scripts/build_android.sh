#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="debug"

case "${1:-}" in
  ""|--debug) MODE="debug" ;;
  --release) MODE="release" ;;
  *)
    printf '用法：%s [--debug|--release]\n' "$0" >&2
    exit 64
    ;;
esac

find_java_home() {
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]] &&
      "$JAVA_HOME/bin/java" -version 2>&1 | head -n 1 | grep -q '"17\.'; then
    printf '%s\n' "$JAVA_HOME"
    return
  fi

  if [[ "$(uname -s)" == "Darwin" ]] && [[ -x /usr/libexec/java_home ]]; then
    local mac_java
    mac_java="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
    if [[ -n "$mac_java" && -x "$mac_java/bin/java" ]]; then
      printf '%s\n' "$mac_java"
      return
    fi
  fi

  if command -v brew >/dev/null 2>&1; then
    local brew_java
    brew_java="$(brew --prefix openjdk@17 2>/dev/null || true)"
    if [[ -x "$brew_java/libexec/openjdk.jdk/Contents/Home/bin/java" ]]; then
      printf '%s\n' "$brew_java/libexec/openjdk.jdk/Contents/Home"
      return
    fi
    if [[ -x "$brew_java/bin/java" ]]; then
      printf '%s\n' "$brew_java"
      return
    fi
  fi

  printf '错误：未找到 JDK 17。\n' >&2
  return 1
}

find_android_sdk() {
  if [[ -n "${ANDROID_SDK_ROOT:-}" && -d "$ANDROID_SDK_ROOT" ]]; then
    printf '%s\n' "$ANDROID_SDK_ROOT"
    return
  fi
  if [[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME" ]]; then
    printf '%s\n' "$ANDROID_HOME"
    return
  fi

  local properties="$ROOT_DIR/android/local.properties"
  if [[ -f "$properties" ]]; then
    local configured
    configured="$(sed -n 's/^sdk\.dir=//p' "$properties" | head -n 1)"
    if [[ -n "$configured" && -d "$configured" ]]; then
      printf '%s\n' "$configured"
      return
    fi
  fi

  local conventional="$HOME/Library/Android/sdk"
  if [[ -d "$conventional" ]]; then
    printf '%s\n' "$conventional"
    return
  fi

  printf '错误：未找到 Android SDK。\n' >&2
  return 1
}

command -v flutter >/dev/null 2>&1 || {
  printf '错误：PATH 中没有 flutter。\n' >&2
  exit 1
}

export JAVA_HOME="$(find_java_home)"
export ANDROID_SDK_ROOT="$(find_android_sdk)"
export ANDROID_HOME="$ANDROID_SDK_ROOT"

cd "$ROOT_DIR"
"$ROOT_DIR/scripts/build_native_host.sh"
flutter pub get
flutter analyze
flutter test
(
  cd "$ROOT_DIR/android"
  ./gradlew :app:testDebugUnitTest
)
flutter build apk "--$MODE" --target-platform android-arm64

SOURCE_APK="$ROOT_DIR/build/app/outputs/flutter-apk/app-$MODE.apk"
[[ -f "$SOURCE_APK" ]] || {
  printf '错误：构建完成但未找到 %s。\n' "$SOURCE_APK" >&2
  exit 1
}

mkdir -p "$ROOT_DIR/dist"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
APP_VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$ROOT_DIR/pubspec.yaml" | head -n 1)"
OUTPUT_APK="$ROOT_DIR/dist/gremote-$APP_VERSION-arm64-$MODE-$TIMESTAMP.apk"
cp "$SOURCE_APK" "$OUTPUT_APK"

if command -v shasum >/dev/null 2>&1; then
  HASH="$(shasum -a 256 "$OUTPUT_APK" | awk '{print $1}')"
else
  HASH="$(sha256sum "$OUTPUT_APK" | awk '{print $1}')"
fi

printf 'APK: %s\nSHA-256: %s\n' "$OUTPUT_APK" "$HASH"
