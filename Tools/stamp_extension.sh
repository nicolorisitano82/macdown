#!/bin/bash
#
# Puts the application's version into the Quick Look extension, and signs it
# again.
#
# The extension has to report the same version as the application, because
# the Quick Look panel in Preferences compares the registered version with
# the one in hand to decide whether to offer an update — and an extension
# left at a placeholder version would offer one for ever.
#
# The signing again is not optional: an Info.plist written after signing no
# longer matches the signature, and an extension whose seal is broken is one
# Quick Look ignores without a word anywhere. This is the same trap as
# `codesign --deep`, from the other side.
#
# Called on the copy that ships — the one in dist/ — because the build
# system processes the extension's Info.plist again at the end of its own
# target, and a stamp put there earlier does not survive.
#
#   Tools/stamp_extension.sh "dist/Release/MacDown Next.app"

set -o errexit
set -o nounset
set -o pipefail

pushd "$(dirname "$0")" > /dev/null
source "$(pwd -P)"/utils.sh
popd > /dev/null

BUILD_VERSION=$(get_build_version)
SHORT_VERSION=$(get_short_version)
BUNDLE_VERSION=$(get_bundle_version)

stamp() {
    local plist="$1"
    [ -f "$plist" ] || return 0
    /usr/libexec/PlistBuddy -c \
        "Add :CFBundleBuildVersion string $BUILD_VERSION" "$plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c \
        "Set :CFBundleBuildVersion $BUILD_VERSION" "$plist"
    /usr/libexec/PlistBuddy -c \
        "Set :CFBundleShortVersionString $SHORT_VERSION" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUNDLE_VERSION" "$plist"
    echo "note: stamped $SHORT_VERSION ($BUNDLE_VERSION) into $plist"
}

reseal() {
    local bundle="$1"
    [ -d "$bundle" ] || return 0
    if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then
        echo "note: signing is off for this build, so $bundle is left as it is"
        return 0
    fi
    # The entitlements have to be named again: signing without them leaves an
    # extension outside the sandbox, and Quick Look only loads sandboxed ones.
    codesign --force --sign "${CODE_SIGN_IDENTITY:--}" \
        --entitlements "${SRCROOT:-.}/QuickLook/MacDownQuickLook.entitlements" \
        "$bundle" 2>&1 | sed 's/^/note: /'
    echo "note: sealed $bundle again"
}

APP="${1:?percorso del bundle .app}"
APPEX="$APP/Contents/PlugIns/MacDownQuickLook.appex"
if [ ! -d "$APPEX" ]; then
    echo "note: no Quick Look extension in $APP, nothing to stamp"
    exit 0
fi

stamp "$APPEX/Contents/Info.plist"
reseal "$APPEX"
