#!/bin/bash
#
# Builds LoremIpsum.plugin and, with --install, puts it where MacDown looks.
#
# A .plugin is a bundle: an Info.plist naming a principal class, and a binary
# built with -bundle. No Xcode target is needed, which is the point — a
# plug-in is meant to be something you can write on your own without adding
# anything to MacDown's project.
set -e

cd "$(dirname "$0")"
NAME=LoremIpsum
OUT="$NAME.plugin"
SDK=$(xcrun --show-sdk-path)

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS"
cp Info.plist "$OUT/Contents/Info.plist"

clang -bundle -fobjc-arc \
    -isysroot "$SDK" \
    -mmacosx-version-min=26.0 \
    -framework Cocoa \
    -o "$OUT/Contents/MacOS/$NAME" \
    "$NAME.m"

echo "built $OUT"

if [ "$1" = "--install" ]; then
    DEST="$HOME/Library/Application Support/MacDown/PlugIns"
    mkdir -p "$DEST"
    rm -rf "$DEST/$OUT"
    cp -R "$OUT" "$DEST/"
    echo "installed in $DEST"
    echo "Restart MacDown: plug-ins are read once, at launch."
fi
