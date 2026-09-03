#!/bin/bash
#
# Refreshes what the draw.io plug-in carries: the viewer, and every shape
# library the viewer can ask for.
#
#   Tools/fetch_drawio_viewer.sh
#
# Committed rather than fetched by the build: a build that needs the network
# is a build that fails on a train, and this changes a few times a year.
# Apache License 2.0, JGraph Ltd.
#
# The libraries are not in the viewer — they are files it loads when a
# diagram asks for one, and there are 97 of them, 23 MB. Stored gzipped,
# which is 3 MB, and inflated as they are served: XML of drawn shapes
# compresses to a seventh of itself.
#
# Which files: exactly the ones named in the viewer's own code. Not a list
# written here, which would go stale the first time draw.io added a library.

set -o errexit
set -o nounset
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOURCES="$ROOT/plugins/Drawio/Resources"
SITE="https://viewer.diagrams.net"

fetch() {
    curl --fail --silent --show-error --location --output "$2" "$SITE/$1"
}

echo "note: viewer.min.js"
TMP="$(mktemp)"
fetch "js/viewer.min.js" "$TMP"
# It has to be the viewer, not an error page dressed as one.
if ! grep -q "GraphViewer" "$TMP"; then
    echo "error: what came down is not the viewer" >&2
    rm -f "$TMP"
    exit 1
fi
mv "$TMP" "$RESOURCES/viewer.min.js"
chmod 644 "$RESOURCES/viewer.min.js"

# Every path the viewer builds from STENCIL_PATH, SHAPES_PATH or STYLE_PATH.
LIST="$(mktemp)"
python3 - "$RESOURCES/viewer.min.js" > "$LIST" <<'PY'
import re, sys
js = open(sys.argv[1], errors="ignore").read()
for base, prefix in (("STENCIL_PATH", "stencils"), ("SHAPES_PATH", "shapes"),
                     ("STYLE_PATH", "styles")):
    for path in sorted(set(re.findall(base + r'\+"(/[^"]+)"', js))):
        print(prefix + path)
PY

COUNT=0
GONE=0
rm -rf "$RESOURCES/stencils" "$RESOURCES/shapes" "$RESOURCES/styles"
while read -r PATH_IN_SITE; do
    OUT="$RESOURCES/$PATH_IN_SITE"
    mkdir -p "$(dirname "$OUT")"
    # A few of the paths in the viewer are no longer on the site — sap.xml
    # among them. The viewer asks and gets a 404; carrying on is what it
    # does too, and stopping here would mean carrying nothing.
    if fetch "$PATH_IN_SITE" "$OUT"; then
        gzip -9 --force "$OUT"
        COUNT=$((COUNT + 1))
    else
        rm -f "$OUT"
        echo "note: $PATH_IN_SITE is not on the site any more"
        GONE=$((GONE + 1))
    fi
done < "$LIST"
rm -f "$LIST"
find "$RESOURCES" -type d -empty -delete

echo "note: $COUNT shape libraries ($GONE gone), $(du -sh "$RESOURCES" | cut -f1) in all"
