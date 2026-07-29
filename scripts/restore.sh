#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Configuration
###############################################################################

COMPOSE="${COMPOSE:-docker compose}"

SERVICE="postgres"
CONTAINER="postgres"

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

success() {
    echo -e "${GREEN}[ OK ]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
    exit 1
}

trap 'error "Restore interrupted."' INT TERM

###############################################################################
# Helpers
###############################################################################

usage() {

cat <<EOF

Usage:

Restore latest backup
    ./scripts/restore.sh

Restore to point in time
    ./scripts/restore.sh "2026-07-26 14:30:00"

Restore to named restore point
    ./scripts/restore.sh restore_point before_upgrade

Restore a specific backup set
    ./scripts/restore.sh --set 20260726-010001F

Show repository information
    ./scripts/restore.sh --info

Check repository
    ./scripts/restore.sh --check

EOF

exit 0
}

exec_pgbackrest() {

    ${COMPOSE} run --rm \
        --no-deps \
        "${SERVICE}" \
        pgbackrest "$@"
}

###############################################################################
# Parse arguments
###############################################################################

MODE="latest"
TARGET=""
BACKUP_SET=""

case "${1:-}" in

    "")
        ;;

    -h|--help)
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

        [[ $# -eq 2 ]] || error "Usage: restore.sh --set BACKUP_LABEL"

        MODE="set"
        BACKUP_SET="$2"
        ;;

    restore_point)

        [[ $# -eq 2 ]] || error "Usage: restore.sh restore_point NAME"

        MODE="name"
        TARGET="$2"
        ;;

    *)

        MODE="time"
        TARGET="$1"
        ;;

esac

###############################################################################
# Validation
###############################################################################

info "Checking Docker container..."

docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER}" \
    || info "Container '${CONTAINER}' does not exist."

[[ -d "${DATA_DIR}" ]] \
    || info "Data directory '${DATA_DIR}' does not exist."

info "Checking backup repository..."

exec_pgbackrest info >/dev/null

success "Repository is healthy."

###############################################################################
# Stop PostgreSQL
###############################################################################

info "Stopping PostgreSQL..."

${COMPOSE} stop "${SERVICE}"

success "PostgreSQL stopped."

###############################################################################
# Confirmation
###############################################################################

echo
warn "ALL DATABASE DATA WILL BE REMOVED."
echo
echo "Data directory:"
echo "    ${DATA_DIR}"
echo

read -rp 'Type "RESTORE" to continue: ' ANSWER

[[ "${ANSWER}" == "RESTORE" ]] \
    || error "Restore cancelled."

###############################################################################
# Remove old data
###############################################################################

info "Removing PostgreSQL data..."

find "${DATA_DIR}" -mindepth 1 -delete

success "Old data removed."

###############################################################################
# Build restore command
###############################################################################

CMD=(
    restore
    --stanza="${STANZA}"
)

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
        --target-action=promote
        --target-timeline=latest
    )

    ;;

name)

    info "Restore point recovery"
    info "Restore point: ${TARGET}"

    CMD+=(
        --type=name
        --target="${TARGET}"
        --target-action=promote
        --target-timeline=latest
    )

    ;;

set)

    info "Restore backup set"
    info "Backup: ${BACKUP_SET}"

    CMD+=(
        --set="${BACKUP_SET}"
    )

    ;;

esac

###############################################################################
# Execute restore
###############################################################################

echo
info "Executing:"
echo

printf "pgbackrest "
printf "%q " "${CMD[@]}"
echo
echo

exec_pgbackrest "${CMD[@]}"

###############################################################################
# Verify restore
###############################################################################

info "Verifying restored cluster..."

[[ -f "${DATA_DIR}/PG_VERSION" ]] \
    || error "PG_VERSION not found."

[[ -d "${DATA_DIR}/base" ]] \
    || error "base directory not found."

[[ -d "${DATA_DIR}/global" ]] \
    || error "global directory not found."

success "Restore verification passed."

###############################################################################
# Done
###############################################################################

echo
success "Restore completed successfully."
echo
echo "Start PostgreSQL:"
echo
echo "    ./scripts/start.sh"
echo