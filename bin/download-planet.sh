#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$PROJECT_DIR/.env" ]]; then
    # shellcheck source=/dev/null
    source "$PROJECT_DIR/.env"
fi

URL="${PLANET_PBF_URL:-https://ftp5.gwdg.de/pub/misc/openstreetmap/planet.openstreetmap.org/pbf/planet-latest.osm.pbf}"
DEST_DIR="$PROJECT_DIR/var/osm"
FILENAME="$(basename "$URL")"

mkdir -p "$DEST_DIR"

echo "Downloading $URL"
echo "Destination: $DEST_DIR/$FILENAME"
echo ""

aria2c \
    --dir="$DEST_DIR" \
    --out="$FILENAME" \
    --continue=true \
    --file-allocation=none \
    --max-connection-per-server=4 \
    --min-split-size=50M \
    --split=4 \
    --max-tries=0 \
    --retry-wait=30 \
    --timeout=600 \
    --console-log-level=notice \
    --summary-interval=60 \
    "$URL"

echo ""
echo "Download complete: $DEST_DIR/$FILENAME"
echo "Start import with: docker compose up -d"
