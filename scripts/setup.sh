#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Project
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

###############################################################################
# Helper functions
###############################################################################

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
# Load environment
###############################################################################

ENV_FILE="${BASE_DIR}/.env"

[[ -f "${ENV_FILE}" ]] || error ".env not found."

set -a
source "${ENV_FILE}"
set +a

###############################################################################
# Validate environment
###############################################################################

required_vars=(
    S3_BUCKET
    S3_ENDPOINT
    S3_REGION
    S3_ACCESS_KEY
    S3_SECRET_KEY
)

for var in "${required_vars[@]}"; do
    [[ -n "${!var:-}" ]] || error "Missing ${var} in .env"
done

###############################################################################
# Check prerequisites
###############################################################################

command -v docker >/dev/null 2>&1 || error "Docker is not installed."

docker compose version >/dev/null 2>&1 || error "Docker Compose is not installed."

###############################################################################
# Check pgBackRest
###############################################################################

info "Checking pgBackRest..."

docker run --rm "${POSTGRES_IMAGE}" \
    pgbackrest version >/dev/null \
    || error "pgBackRest is not installed in ${POSTGRES_IMAGE}"

success "pgBackRest detected."

###############################################################################
# Detect postgres UID/GID
###############################################################################

info "Detecting PostgreSQL UID/GID..."

POSTGRES_UID=$(docker run --rm "${POSTGRES_IMAGE}" id -u postgres)
POSTGRES_GID=$(docker run --rm "${POSTGRES_IMAGE}" id -g postgres)

success "postgres uid=${POSTGRES_UID} gid=${POSTGRES_GID}"

###############################################################################
# Create directories
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
# Generate pgBackRest configuration
###############################################################################

info "Generating conf/pgbackrest.conf..."

mkdir -p "${BASE_DIR}/conf"

cat >"${BASE_DIR}/conf/pgbackrest.conf" <<EOF
[global]
repo1-type=s3
repo1-path=/backup

repo1-s3-bucket=${S3_BUCKET}
repo1-s3-endpoint=${S3_ENDPOINT}
repo1-s3-region=${S3_REGION}
repo1-s3-uri-style=path

repo1-s3-key=${S3_ACCESS_KEY}
repo1-s3-key-secret=${S3_SECRET_KEY}

repo1-s3-verify-tls=${S3_VERIFY_TLS:-y}

repo1-retention-full=${PGBACKREST_RETENTION_FULL:-14}
repo1-retention-archive=${PGBACKREST_RETENTION_ARCHIVE:-14}

process-max=${PGBACKREST_PROCESS_MAX:-2}

repo1-bundle=y
repo1-block=y

compress-type=zst
compress-level=${PGBACKREST_COMPRESS_LEVEL:-3}

start-fast=y

archive-async=y
spool-path=/var/lib/pgbackrest/spool

log-level-console=info
log-level-file=detail
log-path=/var/log/postgresql

delta=y
neutral-umask=y

[main]
pg1-path=/var/lib/postgresql/data
EOF

success "Generated conf/pgbackrest.conf"

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
chown -R 1002:1002 "${BASE_DIR}/pmm-client"

###############################################################################
# Permissions
###############################################################################

info "Setting permissions..."

chmod 700 "${BASE_DIR}/data"
chmod 700 "${BASE_DIR}/wal-archive"
chmod 700 "${BASE_DIR}/pgbackrest-spool"

chmod 750 "${BASE_DIR}/logs"

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
├── pgbackrest-spool/
├── pmm-client/
├── scripts/
└── wal-archive/

PostgreSQL UID : ${POSTGRES_UID}
PostgreSQL GID : ${POSTGRES_GID}

Next steps:

1. Review .env
2. Review conf/postgresql.conf
3. Start PostgreSQL

   docker compose up -d

4. Verify

   docker compose ps

EOF

