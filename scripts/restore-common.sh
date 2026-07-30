#!/usr/bin/env bash

set -Eeuo pipefail

COMPOSE="docker compose"
SERVICE="postgres"
STANZA="${STANZA:-main}"
PGDATA="${PGDATA:-./data}"

run_pgbackrest() {
    $COMPOSE run --rm --no-deps "$SERVICE" pgbackrest "$@"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

confirm() {
    read -rp "$1 [y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

stop_postgres() {
    echo "Stopping PostgreSQL..."
    $COMPOSE stop "$SERVICE"
}

start_postgres() {
    echo "Starting PostgreSQL..."
    $COMPOSE up -d "$SERVICE"
}

clean_pgdata() {
    [[ -d "$PGDATA" ]] || die "PGDATA not found: $PGDATA"

    if confirm "Delete all files under $PGDATA ?"; then
        rm -rf "${PGDATA:?}/"*
    else
        echo "Cancelled."
        exit 0
    fi
}