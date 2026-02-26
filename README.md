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
├── docker-compose.yml        # Service definition
├── .env.example              # Configuration template
├── bin/
│   └── download-planet.sh    # Planet PBF downloader (aria2)
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

### 2. Download the planet file (~75 GB)

```bash
bin/download-planet.sh
```

The download is resumable. Re-run the script if it gets interrupted.

### 3. Start the import

```bash
docker compose up -d
```

Follow progress:

```bash
docker compose logs -f
```

### 4. Verify

Once the import finishes (expect 2–4 days for the full planet):

```bash
# API status
curl http://localhost:8080/status

# Search test
curl "http://localhost:8080/search?q=Eiffel+Tower&format=jsonv2"

# Reverse geocoding test
curl "http://localhost:8080/reverse?lat=48.8584&lon=2.2945&format=jsonv2"
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
