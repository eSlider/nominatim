#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OSM_DIR="$PROJECT_DIR/var/osm"
ENV_FILE="$PROJECT_DIR/.env"
ENV_EXAMPLE_FILE="$PROJECT_DIR/.env.example"

TORRENT_URL="${TORRENT_URL:-https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf.torrent}"
API_PORT_DEFAULT="8080"
POLL_SECONDS=600

log() {
    echo "[$(date -Is)] $*"
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Missing required command: $cmd" >&2
        exit 1
    fi
}

load_env() {
    if [[ ! -f "$ENV_FILE" ]]; then
        if [[ -f "$ENV_EXAMPLE_FILE" ]]; then
            cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
            log "Created .env from .env.example"
        else
            echo "Missing $ENV_FILE and $ENV_EXAMPLE_FILE" >&2
            exit 1
        fi
    fi

    # shellcheck source=/dev/null
    source "$ENV_FILE"
}

set_threads_to_nproc() {
    require_cmd nproc
    export THREADS
    THREADS="$(nproc)"
    log "Set THREADS=$THREADS (osm2pgsql --number-processes)"
}

api_status_url() {
    local port="${NOMINATIM_PORT:-$API_PORT_DEFAULT}"
    echo "http://localhost:${port}/status"
}

api_ready() {
    local url
    url="$(api_status_url)"
    curl -fsS --max-time 15 "$url" >/dev/null 2>&1
}

latest_planet_file() {
    shopt -s nullglob
    local candidates=("$OSM_DIR"/planet-[0-9]*.osm.pbf)
    shopt -u nullglob
    if (( ${#candidates[@]} == 0 )); then
        return 1
    fi

    local latest="${candidates[0]}"
    local f
    for f in "${candidates[@]}"; do
        if [[ "$f" -nt "$latest" ]]; then
            latest="$f"
        fi
    done
    echo "$latest"
}

download_planet_torrent() {
    mkdir -p "$OSM_DIR"
    log "Starting/resuming torrent download: $TORRENT_URL"
    aria2c \
        --seed-time=0 \
        --check-integrity=true \
        --file-allocation=none \
        --continue=true \
        --dir="$OSM_DIR" \
        --bt-max-peers=120 \
        --max-overall-upload-limit=64K \
        --summary-interval=60 \
        --console-log-level=notice \
        "$TORRENT_URL"
}

ensure_latest_symlink() {
    local latest
    latest="$(latest_planet_file)"
    ln -sfn "$(basename "$latest")" "$OSM_DIR/planet-latest.osm.pbf"
    log "Linked planet-latest.osm.pbf -> $(basename "$latest")"
}

wait_for_api_ready() {
    local url
    url="$(api_status_url)"
    log "Waiting for Nominatim API to become ready at $url"
    while true; do
        if api_ready; then
            log "API is ready: $url"
            return 0
        fi
        log "API not ready yet. Next check in $POLL_SECONDS seconds."
        sleep "$POLL_SECONDS"
    done
}

main() {
    require_cmd aria2c
    require_cmd docker
    require_cmd curl
    load_env
    set_threads_to_nproc

    if api_ready; then
        log "API already ready at $(api_status_url)"
        exit 0
    fi

    # Download (or resume) the planet file via torrent.
    download_planet_torrent

    # Ensure Compose path PBF_PATH=/nominatim/data/planet-latest.osm.pbf resolves.
    ensure_latest_symlink

    log "Starting/ensuring docker compose service is up"
    docker compose -f "$PROJECT_DIR/docker-compose.yml" --project-directory "$PROJECT_DIR" up -d

    wait_for_api_ready
}

main "$@"
