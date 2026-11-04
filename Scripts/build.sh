#!/bin/bash
set -euo pipefail
sdk="${1:-iphoneos}"
case "$sdk" in
  iphoneos|iphonesimulator) ;;
  *) echo 'Expected iphoneos or iphonesimulator' >&2; exit 1 ;;
esac
cmake -S . -B "build/native-$sdk" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PWD/build/native"
cmake --build "build/native-$sdk" --parallel 3
cmake --install "build/native-$sdk"
xcodegen generate
