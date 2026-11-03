#!/usr/bin/env bash
# Cross-compiles a synthetic EGL probe; does not install or touch a device.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_SDK="${ANDROID_SDK_ROOT:-$(sed -n 's/^sdk.dir=//p' "$TASK_ROOT/android/local.properties")}"
TASK_BUILD="$TASK_ROOT/native/imaging/build/android-gpu-probe"
TASK_CMAKE="$TASK_SDK/cmake/3.22.1/bin/cmake"
"$TASK_CMAKE" -S "$TASK_ROOT/native/imaging" -B "$TASK_BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$TASK_SDK/ndk/27.0.12077973/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 \
  -DANDROID_STL=c++_static -DGREMOTE_BUILD_GPU_PROBE=ON -DCMAKE_BUILD_TYPE=Release
"$TASK_CMAKE" --build "$TASK_BUILD" --target gremote_gpu_probe --parallel
