#!/usr/bin/env bash
# Log Docker lifecycle events for nominatim-pg18 to detect restart causes.
# Run in background: nohup bin/watch-restart-events.sh >/dev/null 2>&1 &
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG="$PROJECT_DIR/var-pg18/restart-events.log"
CONTAINER="nominatim-pg18"

mkdir -p "$(dirname "$LOG")"
echo "$(date -Is) watcher started, container=$CONTAINER" >> "$LOG"

docker events --filter "container=$CONTAINER" --format '{{.Time}} {{.Status}} exitCode={{.Actor.Attributes.exitCode}}' >> "$LOG" 2>&1
