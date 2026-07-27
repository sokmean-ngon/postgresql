#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Configuration
###############################################################################

COMPOSE="${COMPOSE:-docker compose}"

POSTGRES_CONTAINER="postgres"
PGBACKREST_CONTAINER="pgbackrest"

DATA_DIR="./data"

STANZA="main"

PGBACKREST_CONFIG="/var/lib/postgresql/pgbackrest/pgbackrest.conf"

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

Restore to PostgreSQL restore point
    ./scripts/restore.sh restore_point before_upgrade

Restore specific backup
    ./scripts/restore.sh --set 20260726-010001F

Show backup information
    ./scripts/restore.sh --info

Check repository
    ./scripts/restore.sh --check

EOF
exit 0
}

exec_pgbackrest() {
    docker exec "${PGBACKREST_CONTAINER}" \
        pgbackrest \
        --config="${PGBACKREST_CONFIG}" \
        "$@"
}

###############################################################################
# Parse arguments
###############################################################################

MODE="latest"
TARGET=""
BACKUP_SET=""

case "${1:-}" in

    "")
        MODE="latest"
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

info "Checking pgBackRest container..."

docker ps --format '{{.Names}}' | grep -qx "${PGBACKREST_CONTAINER}" \
    || error "Container '${PGBACKREST_CONTAINER}' is not running."

[[ -d "${DATA_DIR}" ]] \
    || error "Data directory '${DATA_DIR}' does not exist."

info "Checking backup repository..."

exec_pgbackrest check

success "Repository is healthy."

###############################################################################
# Stop PostgreSQL
###############################################################################

info "Stopping PostgreSQL..."

${COMPOSE} stop postgres

info "Waiting for PostgreSQL to stop..."

while docker ps --format '{{.Names}}' | grep -qx "${POSTGRES_CONTAINER}"
do
    sleep 1
done

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
    || error "Cancelled."

###############################################################################
# Remove old data
###############################################################################

info "Removing old PostgreSQL data..."

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
    info "Target : ${TARGET}"

    CMD+=(
        --type=time
        --target="${TARGET}"
    )

    ;;

name)

    info "Restore Point Recovery"
    info "Restore Point : ${TARGET}"

    CMD+=(
        --type=name
        --target="${TARGET}"
    )

    ;;

set)

    info "Restore Backup Set"
    info "Backup : ${BACKUP_SET}"

    CMD+=(
        --set="${BACKUP_SET}"
    )

    ;;

esac

###############################################################################
# Execute restore
###############################################################################

echo
info "Executing command:"
echo

printf "pgbackrest --config=%q " "${PGBACKREST_CONFIG}"
printf "%q " "${CMD[@]}"
echo
echo

exec_pgbackrest "${CMD[@]}"

###############################################################################
# Verify restore
###############################################################################

info "Verifying restored cluster..."

[[ -f "${DATA_DIR}/PG_VERSION" ]] \
    || error "Restore verification failed: PG_VERSION not found."

success "Restore verified."

###############################################################################
# Done
###############################################################################

echo
success "Restore completed successfully."
echo
echo "Start PostgreSQL with:"
echo
echo "    ./scripts/start.sh"
echo