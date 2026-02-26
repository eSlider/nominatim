#!/usr/bin/env bash
set -euo pipefail

# Build a PG18-compatible Nominatim image by patching upstream mediagis Docker context.
# Output image tag defaults to: nominatim:5.2-pg18

IMAGE_TAG="${1:-nominatim:5.2-pg18}"
OSM2PGSQL_VERSION="${OSM2PGSQL_VERSION:-2.2.0}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }
}

require_cmd git
require_cmd docker
require_cmd python3

git clone --depth 1 https://github.com/mediagis/nominatim-docker "$WORK_DIR/src"

python3 - <<'PY2' "$WORK_DIR/src" "$OSM2PGSQL_VERSION"
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
osm2pgsql_version = sys.argv[2]

for rel in ["Dockerfile", "config.sh", "start.sh", "init.sh"]:
    p = root / rel
    s = p.read_text()
    s = s.replace("/postgresql/16/main", "/postgresql/18/main")
    s = s.replace("/var/lib/postgresql/16/main", "/var/lib/postgresql/18/main")
    s = s.replace("/usr/lib/postgresql/16", "/usr/lib/postgresql/18")
    s = s.replace("postgresql-postgis-scripts", "postgresql-18-postgis-3-scripts")
    s = s.replace("postgresql-postgis", "postgresql-18-postgis-3")
    p.write_text(s)

df = root / "Dockerfile"
s = df.read_text()
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
pattern = re.compile(
    r"&& apt-get -y update -qq \\\n\s*&& apt-get -y install \\\n\s*locales \\\n",
    re.MULTILINE,
)
if not pattern.search(s):
    raise SystemExit("Could not patch Dockerfile for PGDG bootstrap")
s = pattern.sub(insert, s, count=1)

# Build osm2pgsql from source to pin the requested version.
s = s.replace(
    " osm2pgsql \\\n",
    " cmake \\\n"
    " libboost-dev \\\n"
    " libbz2-dev \\\n"
    " libexpat1-dev \\\n"
    " liblua5.3-dev \\\n"
    " libpq-dev \\\n"
    " libproj-dev \\\n"
    " nlohmann-json3-dev \\\n"
    " zlib1g-dev \\\n",
    1,
)

build_block = f"""# Build and install osm2pgsql {osm2pgsql_version} from source.
RUN true \\
 && cd /tmp \\
 && curl -fsSL "https://github.com/osm2pgsql-dev/osm2pgsql/archive/refs/tags/{osm2pgsql_version}.tar.gz" -o osm2pgsql.tar.gz \\
 && tar -xzf osm2pgsql.tar.gz \\
 && cd "osm2pgsql-{osm2pgsql_version}" \\
 && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \\
 && cmake --build build -j"$(nproc)" \\
 && cmake --install build \\
 && rm -rf /tmp/osm2pgsql.tar.gz "/tmp/osm2pgsql-{osm2pgsql_version}"

"""
s = s.replace("# Configure postgres.\n", build_block + "# Configure postgres.\n", 1)
df.write_text(s)
PY2

docker build -t "$IMAGE_TAG" "$WORK_DIR/src"
echo "Built image: $IMAGE_TAG"
echo "Installed versions in image:"
docker run --rm "$IMAGE_TAG" bash -lc "set -euo pipefail; \
  echo -n '  osm2pgsql: '; osm2pgsql --version 2>&1 | awk 'NR==1 {print \$3}'; \
  echo -n '  postgresql-18-postgis-3: '; dpkg-query -W -f='\${Version}\n' postgresql-18-postgis-3; \
  echo -n '  postgresql-18-postgis-3-scripts: '; dpkg-query -W -f='\${Version}\n' postgresql-18-postgis-3-scripts"
