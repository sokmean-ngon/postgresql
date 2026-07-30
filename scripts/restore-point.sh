#!/usr/bin/env bash

set -Eeuo pipefail

[[ $# -eq 1 ]] || {
    echo "Usage:"
    echo "  $0 <restore-point>"
    exit 1
}

TARGET="$1"

source "$(dirname "$0")/restore-common.sh"

stop_postgres
clean_pgdata

run_pgbackrest restore \
    --stanza="$STANZA" \
    --type=name \
    --target="$TARGET" \
    --target-action=promote

echo "Restore completed."