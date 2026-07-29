```bash
#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Configuration
###############################################################################

COMPOSE="${COMPOSE:-docker compose}"

POSTGRES_SERVICE="${POSTGRES_SERVICE:-postgres}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-postgres}"

DATA_DIR="${DATA_DIR:-./data}"

STANZA="${STANZA:-main}"

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
    ${COMPOSE} run --rm --no-deps \
        "${POSTGRES_SERVICE}" \
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
        [[ $# -eq 2 ]] || error "Usage: restore.sh --set BACKUP_SET"
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

docker ps -a --format '{{.Names}}' | grep -qx "${POSTGRES_CONTAINER}" \
    || error "Container '${POSTGRES_CONTAINER}' not found."

[[ -d "${DATA_DIR}" ]] \
    || error "Data directory '${DATA_DIR}' does not exist."

info "Checking backup repository..."

exec_pgbackrest info >/dev/null

success "Backup repository is accessible."

###############################################################################
# Confirmation
###############################################################################

echo
warn "THIS OPERATION WILL DESTROY THE CURRENT DATABASE."
echo
echo "Data directory:"
echo "    ${DATA_DIR}"
echo

read -rp 'Type "RESTORE" to continue: ' ANSWER

[[ "${ANSWER}" == "RESTORE" ]] || error "Restore cancelled."

###############################################################################
# Stop PostgreSQL
###############################################################################

info "Stopping PostgreSQL..."

${COMPOSE} stop "${POSTGRES_SERVICE}"

success "PostgreSQL stopped."

###############################################################################
# Remove existing cluster
###############################################################################

info "Removing existing PostgreSQL data..."

find "${DATA_DIR}" -mindepth 1 -delete

success "Old data removed."

###############################################################################
# Build restore command
###############################################################################

CMD=(
    restore
    --stanza="${STANZA}"
    --target-action=promote
    --target-timeline=latest
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

    info "Backup Set Recovery"
    info "Backup Set: ${BACKUP_SET}"

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

success "Restore verified."

###############################################################################
# Finished
###############################################################################

echo
success "Restore completed successfully."
echo
echo "Start PostgreSQL:"
echo
echo "    ./scripts/start.sh"
echo
```
