#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# PostgreSQL Docker Setup
###############################################################################

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

POSTGRES_IMAGE="${POSTGRES_IMAGE:-percona/percona-distribution-postgresql:18.4}"

###############################################################################
# Colors
###############################################################################

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

success() {
    echo -e "${GREEN}[ OK ]${NC} $*"
}

error() {
    echo -e "${RED}[FAIL]${NC} $*"
    exit 1
}

###############################################################################
# Check prerequisites
###############################################################################

command -v docker >/dev/null 2>&1 || error "Docker is not installed."

docker compose version >/dev/null 2>&1 || error "Docker Compose is not installed."

###############################################################################
# Detect postgres UID/GID
###############################################################################

info "Detecting PostgreSQL UID/GID..."

POSTGRES_UID=$(docker run --rm "${POSTGRES_IMAGE}" id -u postgres)
POSTGRES_GID=$(docker run --rm "${POSTGRES_IMAGE}" id -g postgres)

success "postgres uid=${POSTGRES_UID} gid=${POSTGRES_GID}"

###############################################################################
# Directories
###############################################################################

DIRS=(
    data
    conf
    initdb
    logs
    wal-archive
    pgbackrest-spool
    pmm-client
    scripts
)

for dir in "${DIRS[@]}"; do
    mkdir -p "${BASE_DIR}/${dir}"
done

###############################################################################
# Log files
###############################################################################

touch "${BASE_DIR}/logs/postgresql.log"

###############################################################################
# Ownership
###############################################################################

info "Setting ownership..."

chown -R "${POSTGRES_UID}:${POSTGRES_GID}" \
    "${BASE_DIR}/data" \
    "${BASE_DIR}/logs" \
    "${BASE_DIR}/wal-archive" \
    "${BASE_DIR}/pgbackrest-spool"

# PMM client stores pmm-agent.yaml
chmod 755 "${BASE_DIR}/pmm-client"

###############################################################################
# Permissions
###############################################################################

info "Setting permissions..."

chmod 700 "${BASE_DIR}/data"
chmod 700 "${BASE_DIR}/wal-archive"
chmod 700 "${BASE_DIR}/pgbackrest-spool"

chmod 750 "${BASE_DIR}/logs"

chmod 755 "${BASE_DIR}/conf"
chmod 755 "${BASE_DIR}/initdb"
chmod 755 "${BASE_DIR}/scripts"
chmod 755 "${BASE_DIR}/pmm-client"

find "${BASE_DIR}/conf" -type f -exec chmod 644 {} \; 2>/dev/null || true
find "${BASE_DIR}/initdb" -type f -exec chmod 644 {} \; 2>/dev/null || true

find "${BASE_DIR}/scripts" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

###############################################################################
# Summary
###############################################################################

echo
success "Directory structure created."

cat <<EOF

Project directory:

${BASE_DIR}

Created:

├── conf/
├── data/
├── initdb/
├── logs/
│   └── postgresql.log
├── pgbackrest-spool/
├── pmm-client/
├── scripts/
└── wal-archive/

PostgreSQL UID : ${POSTGRES_UID}
PostgreSQL GID : ${POSTGRES_GID}

Next steps:

1. Copy:
   - docker-compose.yml
   - .env
   - conf/*
   - initdb/*
   - scripts/*

2. Start PostgreSQL

   docker compose up -d

3. Verify

   docker compose ps

EOF