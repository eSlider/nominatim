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
- `docker-compose.yml` — PG16 service definition
- `docker-compose.pg18.yml` — PG18 migration profile (optimized)
- `.env.example` / `.env.pg18.example` — profile configuration templates
- `bin/download-planet.sh` — planet download script
- `bin/watch-download-start-import.sh` — watcher that polls every 10 min
- `bin/init-pg18.sh` — end-to-end PG18 bootstrap
- `bin/build-pg18-image.sh` — build custom PG18 image

## Key operations

| Task | Command |
|---|---|
| Download planet | `bin/download-planet.sh` |
| Download planet via torrent | `aria2c --seed-time=0 ... planet-latest.osm.pbf.torrent` |
| Auto-start import after download | `bin/watch-download-start-import.sh` |
| Build PG18 image | `bin/build-pg18-image.sh` (prints installed PostGIS package versions) |
| Bootstrap PG18 profile | `bin/init-pg18.sh` |
| Start PG18 profile manually | `THREADS=$(nproc) docker compose --env-file .env.pg18 -f docker-compose.pg18.yml up -d` |
| Check PG18 API | `curl http://localhost:8081/status` |
| Enable PG18 updates | Set `UPDATE_MODE=continuous` in `.env.pg18`, then restart PG18 compose |
| Check low-latency host settings | `bin/tune-low-latency.sh --status` |
| Apply low-latency host settings | `sudo bin/tune-low-latency.sh --apply` |
| Start service | `THREADS=$(nproc) docker compose up -d` |
| View logs | `docker compose logs -f` |
| View watcher logs | `tail -f var/osm/download-watch.log` |
| Stop (keep data) | `docker compose stop` |
| Check API | `curl http://localhost:8080/status` |
| Enable updates | Set `UPDATE_MODE=continuous` in `.env`, then restart |

## Safety rules

- **Never** run `docker compose down -v` — destroys all imported data
- **Never** delete `var/lib/postgresql/` while the container is running
- **Never** modify `.env` while the container is importing (restart required)
- The initial planet import takes 2–4 days; do not interrupt it
- Any documentation change (`README.md`, `AGENTS.md`, `docs/`) should be
  committed and pushed when requested in the task flow

## Low-latency operations notes

- Keep THP disabled on host systems serving production traffic.
- Prefer explicit huge pages for PostgreSQL where possible.
- Run latency-sensitive benchmarks with CPU governor set to performance.
- Keep non-Nominatim I/O-heavy jobs off the same storage during serving.
- Always validate tuning changes with real API workload before rollout.

## Modifying configuration

All tuning is done through `.env` variables. The PostgreSQL parameters in
`.env.example` are tuned for 64 GB RAM / 20 threads. If the host changes,
recalculate:
- `POSTGRES_SHARED_BUFFERS` = 25% of RAM
- `POSTGRES_EFFECTIVE_CACHE_SIZE` = 75% of RAM
- `shm_size` in `docker-compose.yml` = 50% of RAM

## Architecture decision

- Do not switch to a separate `postgis/postgis` DB container by default.
- Keep the integrated Nominatim image model unless the user explicitly asks for
  a split app+DB migration project.
