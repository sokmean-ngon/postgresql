#!/usr/bin/env bash

set -Eeuo pipefail

source "$(dirname "$0")/restore-common.sh"

FAILED=0

check_file() {
    if [[ -f "$1" ]]; then
        printf "✓ %s\n" "$1"
    else
        printf "✗ %s\n" "$1"
        FAILED=1
    fi
}

check_dir() {
    if [[ -d "$1" ]]; then
        printf "✓ %s\n" "$1"
    else
        printf "✗ %s\n" "$1"
        FAILED=1
    fi
}

echo "Checking restored cluster..."
echo

check_file "$PGDATA/PG_VERSION"
check_file "$PGDATA/backup_label"
check_file "$PGDATA/recovery.signal"
check_file "$PGDATA/postgresql.auto.conf"

check_dir "$PGDATA/base"
check_dir "$PGDATA/global"
check_dir "$PGDATA/pg_wal"

echo
echo "Checking repository..."

if run_pgbackrest info >/dev/null; then
    echo "✓ Repository reachable"
else
    echo "✗ Repository unreachable"
    FAILED=1
fi

echo

if [[ $FAILED -eq 0 ]]; then
    echo "======================================"
    echo " Restore verification PASSED"
    echo "======================================"
else
    echo "======================================"
    echo " Restore verification FAILED"
    echo "======================================"
    exit 1
fi