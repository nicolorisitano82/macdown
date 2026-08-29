#!/bin/bash

if [ "$CI" == "true" ]; then
    echo "Skipping build number update script under CI."
    exit 0
fi

# Source: https://gist.github.com/karlvr/c93a98d7000ecb163895

# This script automatically sets the version and short version string of
# an Xcode project from the Git repository containing the project.
#
# To use this script in Xcode, add the script's path to a "Run Script" build
# phase for your application target.

set -o errexit
set -o nounset

pushd `dirname $0` > /dev/null
source $(pwd -P)/utils.sh
popd > /dev/null

BUILD_VERSION=$(get_build_version)
SHORT_VERSION=$(get_short_version)
BUNDLE_VERSION=$(get_bundle_version)

# Alternatively, we could use Xcode's copy of the Git binary,
# but old Xcodes don't have this.
#GIT=$(xcrun -find git)

# Both of the places a product can be sitting by the time this runs. The
# advice used to be to write to TARGET_BUILD_DIR alone, and under the
# current build system that is not always the copy that ships: the app in
# BUILT_PRODUCTS_DIR — the one that gets packaged — was left reporting the
# placeholder version out of the source Info.plist.
stamp() {
    local plist="$1"
    [ -f "$plist" ] || return 0
    /usr/libexec/PlistBuddy -c "Add :CFBundleBuildVersion string $BUILD_VERSION" "$plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Set :CFBundleBuildVersion $BUILD_VERSION" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUNDLE_VERSION" "$plist"
    echo "note: stamped $SHORT_VERSION ($BUNDLE_VERSION) into $plist"
}

stamp "${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
if [ "${BUILT_PRODUCTS_DIR}" != "${TARGET_BUILD_DIR}" ]; then
    stamp "${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"
fi
