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

info "Generating /etc/pgbackrest/pgbackrest.conf..."

mkdir -p /etc/pgbackrest

cat >/etc/pgbackrest/pgbackrest.conf <<EOF
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


start-fast=y

log-level-console=info
log-level-file=detail

archive-async=y
spool-path=/var/lib/pgbackrest/spool

[global:archive-push]
compress-level=${PGBACKREST_COMPRESS_LEVEL:-3}

[main]
pg1-path=/var/lib/postgresql/data
EOF

chmod 600 /etc/pgbackrest/pgbackrest.conf

info "pgbackrest.conf generated."

###############################################################################
# Wait for PostgreSQL initialization
###############################################################################

info "Waiting for PostgreSQL initialization..."

until PGPASSWORD="${POSTGRES_PASSWORD}" \
    psql \
        -h postgres \
        -U "${POSTGRES_USER:-postgres}" \
        -d postgres \
        -tAc "SELECT 1" >/dev/null 2>&1
do
    sleep 2
done

info "PostgreSQL is fully initialized."

###############################################################################
# Ensure stanza exists
###############################################################################

info "Ensuring pgBackRest stanza exists..."

if pgbackrest --stanza="${STANZA}" check >/dev/null 2>&1; then
    info "Stanza already exists."
else
    info "Creating stanza..."

    pgbackrest \
        --stanza="${STANZA}" \
        stanza-create

    info "Stanza created."
fi

###############################################################################
# Verify repository
###############################################################################

info "Verifying repository..."

pgbackrest \
    --stanza="${STANZA}" \
    check

info "Repository check successful."

###############################################################################
# Execute container command
###############################################################################

info "Starting container..."

exec "$@"