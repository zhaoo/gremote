#!/usr/bin/env bash
# Builds the imaging core for the host and runs its C++ tests.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/native/imaging/build/host"

if ! command -v cmake >/dev/null 2>&1; then
  printf '错误：未找到 cmake，请先安装（brew install cmake）。\n' >&2
  exit 1
fi

cmake -S "$ROOT/native/imaging" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$BUILD_DIR" --parallel
ctest --test-dir "$BUILD_DIR" --output-on-failure
