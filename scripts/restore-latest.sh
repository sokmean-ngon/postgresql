#!/usr/bin/env bash

set -Eeuo pipefail
source "$(dirname "$0")/restore-common.sh"

stop_postgres
clean_pgdata

run_pgbackrest restore \
    --stanza="$STANZA"

echo
echo "Restore completed."
echo "Start PostgreSQL:"
echo "docker compose up -d postgres"