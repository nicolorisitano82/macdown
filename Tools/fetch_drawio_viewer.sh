#!/bin/bash
#
# Refreshes the draw.io viewer the plug-in carries.
#
#   Tools/fetch_drawio_viewer.sh
#
# The file is committed rather than fetched by the build: a build that needs
# the network is a build that fails on a train, and this one changes a few
# times a year. Apache License 2.0, JGraph Ltd.

set -o errexit
set -o nounset
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$ROOT/plugins/Drawio/Resources/viewer.min.js"
URL="https://viewer.diagrams.net/js/viewer.min.js"

TMP="$(mktemp)"
curl --fail --silent --show-error --location --output "$TMP" "$URL"

# It has to be the viewer, not an error page dressed as one: the class the
# plug-in relies on has to be in there.
if ! grep -q "GraphViewer" "$TMP"; then
    echo "error: what came down is not the viewer" >&2
    rm -f "$TMP"
    exit 1
fi

mv "$TMP" "$TARGET"
chmod 644 "$TARGET"
echo "note: $(wc -c < "$TARGET" | tr -d ' ') bytes in $TARGET"
