#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env.pg18"
ENV_EXAMPLE_FILE="$PROJECT_DIR/.env.pg18.example"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.pg18.yml"
OSM_DIR="$PROJECT_DIR/var-pg18/osm"
POLL_SECONDS=600

log() {
    echo "[$(date -Is)] $*"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }
}

ensure_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
        log "Created .env.pg18 from template"
    fi
    # shellcheck source=/dev/null
    source "$ENV_FILE"
}

download_planet() {
    mkdir -p "$OSM_DIR"
    log "Starting/resuming torrent download for PG18 profile"
    aria2c         --seed-time=0         --check-integrity=true         --file-allocation=none         --continue=true         --dir="$OSM_DIR"         --bt-max-peers=120         --max-overall-upload-limit=64K         "https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf.torrent"
}

link_latest() {
    shopt -s nullglob
    local files=("$OSM_DIR"/planet-[0-9]*.osm.pbf)
    shopt -u nullglob
    if (( ${#files[@]} == 0 )); then
        echo "No downloaded planet file found in $OSM_DIR" >&2
        exit 1
    fi
    local latest="${files[0]}"
    local f
    for f in "${files[@]}"; do
        [[ "$f" -nt "$latest" ]] && latest="$f"
    done
    ln -sfn "$(basename "$latest")" "$OSM_DIR/planet-latest.osm.pbf"
    log "Linked planet-latest.osm.pbf -> $(basename "$latest")"
}

api_url() {
    echo "http://localhost:${NOMINATIM_PORT:-8081}/status"
}

wait_api() {
    local url
    url="$(api_url)"
    log "Waiting for PG18 API at $url"
    while true; do
        if curl -fsS --max-time 15 "$url" >/dev/null 2>&1; then
            log "PG18 API ready: $url"
            return 0
        fi
        log "API not ready yet, next check in $POLL_SECONDS seconds"
        sleep "$POLL_SECONDS"
    done
}

main() {
    require_cmd aria2c
    require_cmd docker
    require_cmd curl
    ensure_env

    mkdir -p "$PROJECT_DIR/var-pg18/lib/postgresql" "$PROJECT_DIR/var-pg18/nominatim/flatnode" "$PROJECT_DIR/var-pg18/osm"

    download_planet
    link_latest

    log "Starting PG18 compose profile"
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" --project-directory "$PROJECT_DIR" up -d

    wait_api
}

main "$@"
