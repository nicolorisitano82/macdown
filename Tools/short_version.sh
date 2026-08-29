#!/bin/bash
# The version string, from the tags: exactly the tag when the build sits on
# one, and the next version with a count of commits when it does not.
pushd "$(dirname "$0")" > /dev/null
source "$(pwd -P)"/utils.sh
popd > /dev/null
get_short_version
