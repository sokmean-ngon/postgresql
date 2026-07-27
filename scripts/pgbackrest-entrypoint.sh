#!/bin/bash

set -Eeuo pipefail

###############################################################################
# Configuration
###############################################################################

STANZA="main"

###############################################################################
# Logging
###############################################################################

info() {
    echo "[INFO] $*"
}

warn() {
    echo "[WARN] $*"
}

error() {
    echo "[ERROR] $*"
    exit 1
}

###############################################################################
# Validate required environment variables
###############################################################################

required_vars=(
    POSTGRES_USER
    POSTGRES_PASSWORD
    S3_BUCKET
    S3_ENDPOINT
    S3_REGION
    S3_ACCESS_KEY
    S3_SECRET_KEY
)

info "Validating environment variables..."

for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        error "Missing required environment variable: ${var}"
    fi
done

###############################################################################
# Generate pgBackRest configuration
###############################################################################

info "Generating ${CONFIG_FILE}..."

CONFIG_DIR="/var/lib/postgresql/pgbackrest"
CONFIG_FILE="${CONFIG_DIR}/pgbackrest.conf"

if [[ ! -w "${CONFIG_DIR}" && -e "${CONFIG_DIR}" ]]; then
    error "${CONFIG_DIR} is not writable."
fi

mkdir -p "${CONFIG_DIR}"

cat >"${CONFIG_FILE}" <<EOF
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

log-level-console=info
log-level-file=detail

archive-async=y
spool-path=/var/lib/pgbackrest/spool

[main]
pg1-path=/var/lib/postgresql/data
EOF

chmod 600 "${CONFIG_FILE}"
export PGBACKREST_CONFIG="${CONFIG_FILE}"

info "pgbackrest.conf generated."

###############################################################################
# Wait for PostgreSQL initialization
###############################################################################

info "Waiting for PostgreSQL initialization..."

info "Waiting for PostgreSQL initialization..."

MAX_RETRIES=60
COUNT=0

until PGPASSWORD="${POSTGRES_PASSWORD}" \
    psql \
        -h postgres \
        -U "${POSTGRES_USER}" \
        -d postgres \
        -tAc "SELECT 1" >/dev/null 2>&1
do
    COUNT=$((COUNT+1))

    if [ "$COUNT" -ge "$MAX_RETRIES" ]; then
        error "PostgreSQL did not become ready."
    fi

    sleep 2
done

info "PostgreSQL is fully initialized."

###############################################################################
# Ensure stanza exists
###############################################################################

info "Ensuring pgBackRest stanza exists..."

if pgbackrest \
    --config="${PGBACKREST_CONFIG}" \
    --stanza="${STANZA}" \
    info >/dev/null 2>&1
then
    info "Stanza already exists."
else
    info "Creating stanza..."

    pgbackrest \
        --config="${PGBACKREST_CONFIG}" \
        --stanza="${STANZA}" \
        stanza-create
fi

###############################################################################
# Verify repository
###############################################################################

info "Verifying repository..."

pgbackrest \
    --config="${PGBACKREST_CONFIG}" \
    --stanza="${STANZA}" \
    check

info "Repository check successful."

###############################################################################
# Execute container command
###############################################################################

info "Starting container..."

exec "$@"