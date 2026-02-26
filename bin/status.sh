#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Defaults are from https://planet.openstreetmap.org/statistics/data_stats.html
TOTAL_NODES="${TOTAL_NODES:-10453228075}"
TOTAL_WAYS="${TOTAL_WAYS:-1166349662}"
TOTAL_RELATIONS="${TOTAL_RELATIONS:-14133082}"

usage() {
    cat <<'EOF'
Usage: bin/status.sh [--pg18|--pg16]

Default profile: --pg18

Optional overrides:
  TOTAL_NODES=<int> TOTAL_WAYS=<int> TOTAL_RELATIONS=<int> bin/status.sh
EOF
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }
}

require_cmd docker
require_cmd python3
require_cmd curl

PROFILE="${1:---pg18}"
case "$PROFILE" in
    --pg18)
        ENV_FILE="$PROJECT_DIR/.env.pg18"
        COMPOSE_FILE="$PROJECT_DIR/docker-compose.pg18.yml"
        CONTAINER="nominatim-pg18"
        STATUS_URL="http://localhost:8081/status"
        ;;
    --pg16)
        ENV_FILE="$PROJECT_DIR/.env"
        COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
        CONTAINER="nominatim"
        STATUS_URL="http://localhost:8080/status"
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage
        exit 1
        ;;
esac

compose_cmd=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" --project-directory "$PROJECT_DIR")

echo "=== Nominatim status ($(date -Is)) ==="
echo "Profile: $PROFILE"
echo

if [[ ! -f "$ENV_FILE" || ! -f "$COMPOSE_FILE" ]]; then
    echo "Profile files not found:"
    echo "  env: $ENV_FILE"
    echo "  compose: $COMPOSE_FILE"
    exit 1
fi

echo "-- Compose service state --"
"${compose_cmd[@]}" ps
echo

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "Container '$CONTAINER' does not exist yet."
    exit 0
fi

echo "-- Container runtime --"
docker inspect --format "State={{.State.Status}} Health={{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}} Restarts={{.RestartCount}}" "$CONTAINER"
echo

echo "-- API check --"
if api_payload="$(curl -fsS --max-time 8 "$STATUS_URL" 2>/dev/null)"; then
    echo "API is reachable at $STATUS_URL"
    echo "$api_payload"
else
    echo "API is not ready at $STATUS_URL"
fi
echo

echo "-- Import progress and ETA --"
TOTAL_NODES="$TOTAL_NODES" \
TOTAL_WAYS="$TOTAL_WAYS" \
TOTAL_RELATIONS="$TOTAL_RELATIONS" \
python3 - <<'PY' "$CONTAINER"
import math
import os
import re
import subprocess
import sys

container = sys.argv[1]
total_nodes = int(os.environ["TOTAL_NODES"])
total_ways = int(os.environ["TOTAL_WAYS"])
total_relations = int(os.environ["TOTAL_RELATIONS"])

result = subprocess.run(
    ["docker", "logs", "--tail", "50000", container],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    check=False,
)
text = result.stdout.replace("\r", "\n")

pattern = re.compile(
    r"Processing: Node\((\d+)k\s+([0-9.]+)k/s\) "
    r"Way\((\d+)k\s+([0-9.]+)k/s\) "
    r"Relation\((\d+)\s+([0-9.]+)/s\)"
)
rows = [
    (int(a) * 1000, float(b) * 1000, int(c) * 1000, float(d) * 1000, int(e), float(f))
    for a, b, c, d, e, f in pattern.findall(text)
]

if not rows:
    print("No osm2pgsql progress lines found yet.")
    sys.exit(0)

node, node_rate, way, way_rate, relation, relation_rate = rows[-1]

def fmt_pct(done: int, total: int) -> str:
    if total <= 0:
        return "n/a"
    return f"{(done / total) * 100:.3f}%"

def eta_seconds(remaining: int, rate: float) -> float:
    if remaining <= 0:
        return 0.0
    if rate <= 0:
        return math.inf
    return remaining / rate

def fmt_eta(seconds: float) -> str:
    if math.isinf(seconds):
        return "unknown"
    secs = int(round(seconds))
    days, secs = divmod(secs, 86400)
    hours, secs = divmod(secs, 3600)
    minutes, secs = divmod(secs, 60)
    if days:
        return f"{days}d {hours}h {minutes}m"
    if hours:
        return f"{hours}h {minutes}m"
    if minutes:
        return f"{minutes}m {secs}s"
    return f"{secs}s"

node_remaining = max(total_nodes - node, 0)
way_remaining = max(total_ways - way, 0)
relation_remaining = max(total_relations - relation, 0)

node_eta = eta_seconds(node_remaining, node_rate)
way_eta = eta_seconds(way_remaining, way_rate)
relation_eta = eta_seconds(relation_remaining, relation_rate)

# Full import scenarios (heuristic).
full_optimistic = node_eta + way_eta
full_medium = node_eta + way_eta + eta_seconds(relation_remaining, 2000.0)
full_conservative = node_eta + way_eta + eta_seconds(relation_remaining, 500.0) + 4 * 3600

print(
    "Latest: "
    f"Node({node // 1000}k {node_rate / 1000:.1f}k/s) "
    f"Way({way // 1000}k {way_rate / 1000:.2f}k/s) "
    f"Relation({relation} {relation_rate:.1f}/s)"
)
print(
    f"Node: {node}/{total_nodes} ({fmt_pct(node, total_nodes)}) "
    f"ETA={fmt_eta(node_eta)}"
)
print(
    f"Way: {way}/{total_ways} ({fmt_pct(way, total_ways)}) "
    f"ETA={fmt_eta(way_eta)}"
)
print(
    f"Relation: {relation}/{total_relations} ({fmt_pct(relation, total_relations)}) "
    f"ETA={fmt_eta(relation_eta)}"
)
print(
    "Full ETA (heuristic): "
    f"optimistic={fmt_eta(full_optimistic)}, "
    f"medium={fmt_eta(full_medium)}, "
    f"conservative={fmt_eta(full_conservative)}"
)
PY
