#!/usr/bin/env bash

set -Eeuo pipefail

[[ $# -eq 1 ]] || {
    echo "Usage:"
    echo "  $0 <backup-set>"
    exit 1
}

SET_NAME="$1"

source "$(dirname "$0")/restore-common.sh"

stop_postgres
clean_pgdata

run_pgbackrest restore \
    --stanza="$STANZA" \
    --set="$SET_NAME"

echo "Restore completed."