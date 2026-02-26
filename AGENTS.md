# Agent Instructions — Nominatim Service

## Project overview

Docker Compose deployment of Nominatim 5.2 for full-planet geocoding.
All runtime data lives under `var/` (gitignored). Configuration is in
`.env` (from `.env.example`). The service image is `mediagis/nominatim:5.2`.

## Context exclusion

**Never read or index anything under `var/`.**
This directory contains:
- PostgreSQL binary data (`var/lib/postgresql/`) — hundreds of GB
- OSM planet extracts (`var/osm/`) — 75+ GB binary PBF
- Flatnode files (`var/nominatim/flatnode/`) — 50+ GB binary

Including these in context will fail or produce garbage.

## Files to read

- `README.md` — usage, quick start, tuning
- `docker-compose.yml` — service definition and volume mounts
- `.env.example` — all available configuration variables
- `bin/download-planet.sh` — planet download script

## Key operations

| Task | Command |
|---|---|
| Download planet | `bin/download-planet.sh` |
| Start service | `docker compose up -d` |
| View logs | `docker compose logs -f` |
| Stop (keep data) | `docker compose stop` |
| Check API | `curl http://localhost:8080/status` |
| Enable updates | Set `UPDATE_MODE=continuous` in `.env`, then restart |

## Safety rules

- **Never** run `docker compose down -v` — destroys all imported data
- **Never** delete `var/lib/postgresql/` while the container is running
- **Never** modify `.env` while the container is importing (restart required)
- The initial planet import takes 2–4 days; do not interrupt it

## Modifying configuration

All tuning is done through `.env` variables. The PostgreSQL parameters in
`.env.example` are tuned for 64 GB RAM / 20 threads. If the host changes,
recalculate:
- `POSTGRES_SHARED_BUFFERS` = 25% of RAM
- `POSTGRES_EFFECTIVE_CACHE_SIZE` = 75% of RAM
- `shm_size` in `docker-compose.yml` = 50% of RAM
