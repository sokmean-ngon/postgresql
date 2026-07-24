#!/usr/bin/env bash

set -Eeuo pipefail

# ----------------------------------------------------------------------
# PostgreSQL Storage Setup
# One-time setup for Percona PostgreSQL Docker deployment
# ----------------------------------------------------------------------

BASE_DIR="."
POSTGRES_IMAGE="percona/percona-distribution-postgresql:18.4"

echo "==> PostgreSQL Storage Setup"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Please run as root (sudo)."
    exit 1
fi

echo "==> Detecting postgres UID/GID from Docker image..."

PG_UID=$(docker run --rm "$POSTGRES_IMAGE" id -u postgres)
PG_GID=$(docker run --rm "$POSTGRES_IMAGE" id -g postgres)

echo "    postgres UID : $PG_UID"
echo "    postgres GID : $PG_GID"

echo "==> Creating directories..."

mkdir -p \
    "$BASE_DIR/data" \
    "$BASE_DIR/conf" \
    "$BASE_DIR/logs" \
    "$BASE_DIR/wal-archive" \
    "$BASE_DIR/pgbackrest-spool" \
    "$BASE_DIR/initdb"

echo "==> Setting ownership..."

chown -R "$PG_UID:$PG_GID" \
    "$BASE_DIR/data" \
    "$BASE_DIR/logs" \
    "$BASE_DIR/wal-archive" \
    "$BASE_DIR/pgbackrest-spool"

chown -R root:root \
    "$BASE_DIR/conf" \
    "$BASE_DIR/initdb"

echo "==> Setting permissions..."

chmod 700 "$BASE_DIR/data"
chmod 750 "$BASE_DIR/logs"
chmod 700 "$BASE_DIR/wal-archive"
chmod 700 "$BASE_DIR/pgbackrest-spool"

find "$BASE_DIR/conf" -type d -exec chmod 755 {} \;
find "$BASE_DIR/conf" -type f -exec chmod 644 {} \;

find "$BASE_DIR/initdb" -type d -exec chmod 755 {} \;
find "$BASE_DIR/initdb" -type f -exec chmod 644 {} \;
find "$BASE_DIR/initdb" -name "*.sh" -exec chmod 755 {} \;

echo
echo "==> Directory status"
echo

ls -ld \
    "$BASE_DIR" \
    "$BASE_DIR/data" \
    "$BASE_DIR/conf" \
    "$BASE_DIR/logs" \
    "$BASE_DIR/wal-archive" \
    "$BASE_DIR/pgbackrest-spool" \
    "$BASE_DIR/initdb"

echo
echo "Storage initialization completed successfully."