# Nominatim — Full Planet Geocoding Service

Self-hosted [Nominatim](https://nominatim.org/) instance serving worldwide
forward and reverse geocoding, running via Docker Compose on a single machine.

## Prerequisites

| Requirement | Minimum | This host |
|---|---|---|
| RAM | 64 GB | 64 GB |
| Free disk | ~1.2 TB | 1.9 TB (`/mnt/4TB-XFS`) |
| CPU threads | 8+ | 20 (i7-12700H) |
| Docker Engine | 24+ | — |
| `aria2` | any | — |

Install aria2 if not present:

```bash
sudo apt install -y aria2
```

## Repository layout

```
.
├── docker-compose.yml        # PG16 profile (current)
├── docker-compose.pg18.yml   # PG18 profile (optimized compose)
├── .env.example              # PG16 configuration template
├── .env.pg18.example         # PG18 configuration template
├── bin/
│   ├── download-planet.sh            # Direct HTTP downloader (aria2)
│   ├── watch-download-start-import.sh # 10-min watcher, auto-starts import
│   ├── init-pg18.sh                 # End-to-end PG18 bootstrap
│   └── build-pg18-image.sh          # Build custom PG18 image
├── etc/
│   └── nominatim/            # Config overrides (future use)
└── var/                      # ⛔ gitignored — all runtime data
    ├── lib/postgresql/       # PostgreSQL data directory
    ├── osm/                  # Downloaded .osm.pbf files
    └── nominatim/flatnode/   # Flatnode storage
```

## Quick start

### 1. Configure

```bash
cp .env.example .env
# Edit .env — at minimum change NOMINATIM_PASSWORD
```

### 2. Download the planet file (~85 GB)

```bash
aria2c --seed-time=0 \
  --check-integrity=true \
  --file-allocation=none \
  --continue=true \
  --dir="$(pwd)/var/osm" \
  --bt-max-peers=120 \
  --max-overall-upload-limit=64K \
  "https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf.torrent"
```

The torrent download is resumable.

### 3. Start the 10-minute watcher (recommended)

```bash
bin/watch-download-start-import.sh
```

The watcher checks every 10 minutes and automatically:
- waits for `.aria2` marker disappearance (download complete),
- links `var/osm/planet-latest.osm.pbf` to the completed dated file,
- runs `docker compose up -d`.

To run watcher in background:

```bash
nohup bin/watch-download-start-import.sh >/tmp/nominatim-watch.out 2>&1 &
```

### 4. Start the import manually (optional)

```bash
docker compose up -d
```

Follow progress:

```bash
docker compose logs -f
```

Check torrent progress:

```bash
ls -lh var/osm/*.aria2 var/osm/planet-*.osm.pbf
```

### 5. Verify

Once the import finishes (expect 2–4 days for the full planet):

```bash
# API status
curl http://localhost:8080/status

# Search test
curl "http://localhost:8080/search?q=Eiffel+Tower&format=jsonv2"

# Reverse geocoding test
curl "http://localhost:8080/reverse?lat=48.8584&lon=2.2945&format=jsonv2"
```


## PostgreSQL 18 profile (migration path)

`docker-compose.pg18.yml` is an optimized migration profile that keeps your active
PG16 deployment untouched. It uses separate state directories under `./var-pg18/`.

### Build PG18 image

```bash
bin/build-pg18-image.sh
```

This builds `nominatim:5.2-pg18` by patching upstream `mediagis/nominatim-docker`
for PostgreSQL 18 paths/packages.

### Configure and run PG18 profile

```bash
cp .env.pg18.example .env.pg18
# edit .env.pg18 (password, ports, tuning)

# end-to-end bootstrap: torrent download -> compose up -> wait for API
bin/init-pg18.sh
```

Or manually:

```bash
docker compose --env-file .env.pg18 -f docker-compose.pg18.yml up -d
```

### PG18 compose optimizations

The PG18 compose profile enables:
- `init: true` and `stop_grace_period` for cleaner process shutdown
- high `ulimits.nofile` for concurrent API usage
- explicit `healthcheck` on `/status`
- log rotation (`max-size`, `max-file`)
- larger shared memory via `NOMINATIM_SHM_SIZE`

### PG18 verification and updates

```bash
# verify PG18 profile health endpoint
curl http://localhost:8081/status

# enable replication updates for PG18 profile
sed -i 's/^UPDATE_MODE=.*/UPDATE_MODE=continuous/' .env.pg18
docker compose --env-file .env.pg18 -f docker-compose.pg18.yml up -d
```

## Enabling updates

After the initial import completes, switch to continuous replication:

1. Edit `.env`:
   ```
   UPDATE_MODE=continuous
   ```
2. Restart:
   ```bash
   docker compose up -d
   ```

## Disk usage estimates (full planet)

| Component | Size |
|---|---|
| Planet PBF download | ~75 GB |
| PostgreSQL database | ~900 GB |
| Flatnode file | ~50 GB |
| **Total** | **~1.1 TB** |

## PostgreSQL tuning

Tuning parameters in `.env` are pre-configured for 64 GB RAM.
Key settings:

- `POSTGRES_SHARED_BUFFERS=16GB` — 25% of RAM
- `POSTGRES_EFFECTIVE_CACHE_SIZE=48GB` — 75% of RAM
- `POSTGRES_MAINTENANCE_WORK_MEM=10GB` — speeds up import
- `shm_size=32g` — set in `docker-compose.yml`, half of RAM

## Low-latency tuning checklist

Apply these after initial import to minimize query tail latency:

### Database and container

- Keep flatnode enabled (`./var/nominatim/flatnode:/nominatim/flatnode`) for planet-scale data.
- Keep `UPDATE_MODE=none` if you prioritize read latency over freshness.
- Set `WARMUP_ON_STARTUP=true` in `.env` if restart-time warmup is acceptable.
- Keep `POSTGRES_SHARED_BUFFERS` near 25% RAM and `POSTGRES_EFFECTIVE_CACHE_SIZE` near 75% RAM.
- Tune `GUNICORN_WORKERS` explicitly (start with number of physical cores, then benchmark).

### Host kernel and memory

- Disable Transparent Huge Pages (THP); PostgreSQL docs warn THP can hurt latency.
- Prefer explicit huge pages for PostgreSQL shared memory when available.
- Avoid swap thrashing: keep swap small/emergency-only and set low swappiness.
- Keep free page cache available; avoid memory overcommit from other heavy workloads.

### Storage and CPU

- Use local NVMe storage for `var/lib/postgresql` and `var/nominatim/flatnode`.
- Keep CPU governor in performance mode during heavy import and benchmark runs.
- Avoid colocating other high-I/O jobs on the same disk while serving traffic.

### Automated host tuning script

Use the bundled script to inspect/apply low-latency host settings:

```bash
# show current values only
bin/tune-low-latency.sh --status

# apply runtime tuning (needs root)
sudo bin/tune-low-latency.sh --apply
```

The script targets:
- THP `enabled/defrag` -> `never`
- CPU governor -> `performance`
- `vm.swappiness=1`
- `vm.dirty_background_bytes=268435456`
- `vm.dirty_bytes=1073741824`

These are runtime settings. Re-apply after reboot or persist them using your OS tooling.

### PostgreSQL I/O knobs to benchmark

For latency-sensitive systems, benchmark these parameters (PostgreSQL runtime resource/I/O docs):

- `effective_io_concurrency` (higher for fast NVMe, lower for slower media)
- `bgwriter_flush_after`
- `backend_flush_after`
- `max_wal_size` (bigger can smooth checkpoints and reduce stalls)

Benchmark changes under representative query load before keeping them.

## API endpoints

| Endpoint | Description |
|---|---|
| `GET /search?q=...` | Forward geocoding |
| `GET /reverse?lat=...&lon=...` | Reverse geocoding |
| `GET /lookup?osm_ids=...` | OSM ID lookup |
| `GET /status` | Server status and import state |

Full API docs: https://nominatim.org/release-docs/latest/api/Overview/

## Stopping and restarting

```bash
docker compose stop       # stop (preserves data)
docker compose start      # restart
```

Never use `docker compose down -v` — this destroys all imported data.

## Troubleshooting

**Import killed by OOM**: Reduce `THREADS` or `POSTGRES_MAINTENANCE_WORK_MEM` in `.env`.

**Slow queries after restart**: Set `WARMUP_ON_STARTUP=true` in `.env` to preload
database caches on container start (increases startup time).

**Resuming a failed import**: The container detects existing PostgreSQL data on
start. If the import was interrupted, remove `var/lib/postgresql/` and restart
from scratch.

**Check watcher status**: `tail -f var/osm/download-watch.log` to see 10-minute
polls and auto-start events.
