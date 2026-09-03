#!/bin/bash
#
# Builds llama.cpp as static libraries for the application to link.
#
#   Tools/build_llama.sh [Release|Debug]
#
# Built by its own build system rather than folded into the Xcode target, the
# way peg-markdown-highlight already is. Reproducing what its CMake does —
# which sources belong in a Metal-only build, how the shaders get embedded,
# which files are compiled per CPU feature — would be a second build system
# to keep in step with a project that moves every day.
#
# Static, not dynamic: an application that links a handful of .a files is one
# binary. Dynamic would mean copying five dylibs into the bundle, fixing
# their install names, and signing each one — for no gain here.

set -o errexit
set -o nounset
set -o pipefail

CONFIG="${1:-Release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Dependency/llama.cpp"
OUT="$SRC/build-$CONFIG"

if [ ! -f "$SRC/CMakeLists.txt" ]; then
    echo "error: $SRC is empty. Run: git submodule update --init" >&2
    exit 1
fi

if ! command -v cmake > /dev/null; then
    echo "error: cmake not found. Install it with: brew install cmake" >&2
    exit 1
fi

# The deployment target has to match the application's, or the linker
# refuses the archives.
DEPLOYMENT=26.0

# Both architectures, because the application's Release build is universal
# and a linker handed an arm64-only archive for an x86_64 slice says only
# that every symbol is missing.
cmake -S "$SRC" -B "$OUT" \
    -DCMAKE_BUILD_TYPE="$CONFIG" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT" \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_OPENMP=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_SERVER=OFF \
    -DLLAMA_BUILD_TOOLS=OFF \
    -DLLAMA_CURL=OFF \
    > /dev/null

cmake --build "$OUT" --target llama -j "$(sysctl -n hw.ncpu)" > /dev/null

echo "note: static libraries in $OUT"
find "$OUT" -name '*.a' | while read -r lib; do
    printf "  %8s  %s\n" \
        "$(du -h "$lib" | cut -f1)" "${lib#$OUT/}"
done
