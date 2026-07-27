#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Configuration
###############################################################################

COMPOSE="docker compose"

POSTGRES_CONTAINER="postgres"
PGBACKREST_CONTAINER="pgbackrest"

DATA_DIR="./data"

STANZA="main"

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

error() {
    echo -e "${RED}[ERROR]${NC} $*"
    exit 1
}

success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

###############################################################################
# Helpers
###############################################################################

usage() {
cat <<EOF

Usage:

Restore latest backup
    ./restore.sh

Restore to point in time
    ./restore.sh "2026-07-26 14:30:00"

Restore to PostgreSQL restore point
    ./restore.sh restore_point before_upgrade

Restore specific backup
    ./restore.sh --set 20260726-010001F

Show backup information
    ./restore.sh --info

Check repository
    ./restore.sh --check

EOF
exit 0
}

exec_pgbackrest() {
    docker exec "${PGBACKREST_CONTAINER}" pgbackrest "$@"
}

###############################################################################
# Options
###############################################################################

MODE="latest"
TARGET=""
BACKUP_SET=""

case "${1:-}" in
    "")
        MODE="latest"
        ;;

    --help|-h)
        usage
        ;;

    --info)
        exec_pgbackrest info
        exit 0
        ;;

    --check)
        exec_pgbackrest check
        exit 0
        ;;

    --set)
        [ $# -eq 2 ] || error "Usage: restore.sh --set BACKUP_LABEL"
        MODE="set"
        BACKUP_SET="$2"
        ;;

    restore_point)
        [ $# -eq 2 ] || error "Usage: restore.sh restore_point NAME"
        MODE="name"
        TARGET="$2"
        ;;

    *)
        MODE="time"
        TARGET="$1"
        ;;
esac

###############################################################################
# Validate
###############################################################################

info "Checking pgBackRest container..."

docker ps --format '{{.Names}}' | grep -qx "${PGBACKREST_CONTAINER}" \
    || error "Container '${PGBACKREST_CONTAINER}' is not running."

info "Checking repository..."

exec_pgbackrest check

success "Repository OK"

###############################################################################
# Stop PostgreSQL
###############################################################################

info "Stopping PostgreSQL..."

${COMPOSE} stop postgres

###############################################################################
# Confirmation
###############################################################################

echo
warn "The PostgreSQL data directory will be deleted."

echo
echo "Directory:"
echo "    ${DATA_DIR}"
echo

read -rp "Continue? (yes/no): " ANSWER

[[ "$ANSWER" == "yes" ]] || error "Cancelled."

###############################################################################
# Remove data
###############################################################################

info "Removing old data..."

rm -rf "${DATA_DIR:?}/"*

success "Old data removed."

###############################################################################
# Restore
###############################################################################

CMD=(restore --stanza="${STANZA}")

case "${MODE}" in

latest)
    info "Restoring latest backup..."
    ;;

time)
    info "Point-in-Time Recovery"
    info "Target: ${TARGET}"

    CMD+=(
        --type=time
        --target="${TARGET}"
    )
    ;;

name)
    info "Restore Point Recovery"
    info "Restore Point: ${TARGET}"

    CMD+=(
        --type=name
        --target="${TARGET}"
    )
    ;;

set)
    info "Restore Backup Set"
    info "Backup: ${BACKUP_SET}"

    CMD+=(
        --set="${BACKUP_SET}"
    )
    ;;
esac

echo
echo "Executing:"
echo
printf "pgbackrest %q " "${CMD[@]}"
echo
echo

docker exec "${PGBACKREST_CONTAINER}" pgbackrest "${CMD[@]}"

success "Restore completed."

echo
echo "Start PostgreSQL with:"
echo
echo "    ./scripts/start.sh"