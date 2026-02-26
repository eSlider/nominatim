#!/usr/bin/env bash
set -euo pipefail

# Build a PG18-compatible Nominatim image by patching upstream mediagis Docker context.
# Output image tag defaults to: nominatim:5.2-pg18

IMAGE_TAG="${1:-nominatim:5.2-pg18}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }
}

require_cmd git
require_cmd docker
require_cmd python3

git clone --depth 1 https://github.com/mediagis/nominatim-docker "$WORK_DIR/src"

python3 - <<'PY2' "$WORK_DIR/src"
from pathlib import Path
import sys

root = Path(sys.argv[1])

for rel in ["Dockerfile", "config.sh"]:
    p = root / rel
    s = p.read_text()
    s = s.replace("/postgresql/16/main", "/postgresql/18/main")
    s = s.replace("/var/lib/postgresql/16/main", "/var/lib/postgresql/18/main")
    s = s.replace("postgresql-postgis-scripts", "postgresql-18-postgis-3-scripts")
    s = s.replace("postgresql-postgis", "postgresql-18-postgis-3")
    p.write_text(s)

df = root / "Dockerfile"
s = df.read_text()
needle = "&& apt-get -y update -qq \
 && apt-get -y install \
 locales \
"
insert = """&& apt-get -y update -qq \
 && apt-get -y install -o APT::Install-Recommends="false" -o APT::Install-Suggests="false" \
 ca-certificates curl gnupg lsb-release \
 && install -d /etc/apt/keyrings \
 && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/keyrings/pgdg.gpg \
 && echo "deb [signed-by=/etc/apt/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
 && apt-get -y update -qq \
 && apt-get -y install \
 locales \
"""
if needle not in s:
    raise SystemExit("Could not patch Dockerfile for PGDG bootstrap")
s = s.replace(needle, insert)
df.write_text(s)
PY2

docker build -t "$IMAGE_TAG" "$WORK_DIR/src"
echo "Built image: $IMAGE_TAG"
