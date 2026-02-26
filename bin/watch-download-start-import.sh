#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$PROJECT_DIR/var/osm/download-watch.log"
PBF_DIR="$PROJECT_DIR/var/osm"
LATEST_LINK="$PBF_DIR/planet-latest.osm.pbf"

mkdir -p "$PBF_DIR"

echo "$(date -Is) watcher started" >> "$LOG_FILE"

if command -v nproc >/dev/null 2>&1; then
    export THREADS
    THREADS="$(nproc)"
    echo "$(date -Is) set THREADS=$THREADS (osm2pgsql --number-processes)" >> "$LOG_FILE"
fi

while true; do
    ACTIVE_ARIA2=""
    for f in "$PBF_DIR"/planet-[0-9]*.osm.pbf.aria2; do
        [[ -e "$f" ]] || continue
        ACTIVE_ARIA2="$f"
        break
    done

    COMPLETED_PBF=""
    for f in "$PBF_DIR"/planet-[0-9]*.osm.pbf; do
        [[ -e "$f" ]] || continue
        COMPLETED_PBF="$f"
    done

    if [[ -n "$COMPLETED_PBF" && -z "$ACTIVE_ARIA2" ]]; then
        ln -sfn "$(basename "$COMPLETED_PBF")" "$LATEST_LINK"
        echo "$(date -Is) download complete: $(basename "$COMPLETED_PBF"), linked planet-latest.osm.pbf, starting docker compose" >> "$LOG_FILE"
        docker compose -f "$PROJECT_DIR/docker-compose.yml" --project-directory "$PROJECT_DIR" up -d >> "$LOG_FILE" 2>&1
        echo "$(date -Is) docker compose started" >> "$LOG_FILE"
        exit 0
    fi

    if [[ -n "$COMPLETED_PBF" ]]; then
        SIZE_BYTES="$(stat -c %s "$COMPLETED_PBF" 2>/dev/null || echo 0)"
        echo "$(date -Is) waiting, file=$(basename "$COMPLETED_PBF") file_bytes=$SIZE_BYTES aria2_marker=$( [[ -n "$ACTIVE_ARIA2" ]] && echo yes || echo no )" >> "$LOG_FILE"
    else
        echo "$(date -Is) waiting, file_missing=yes" >> "$LOG_FILE"
    fi
    sleep 600
done
