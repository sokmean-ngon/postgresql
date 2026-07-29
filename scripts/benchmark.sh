#!/usr/bin/env bash

set -Eeuo pipefail

###############################################################################
# Configuration
###############################################################################

CONTAINER="${POSTGRES_CONTAINER:-postgres}"

PGUSER="${PGUSER:-postgres}"
PGDATABASE="${PGDATABASE:-postgres}"

SCALE="${SCALE:-100}"
TIME="${TIME:-300}"

CLIENTS="${CLIENTS:-8 16 32 64}"

INIT="${INIT:-false}"

LOG_DIR="./benchmark"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${LOG_DIR}/pgbench_${TIMESTAMP}.log"

mkdir -p "${LOG_DIR}"

###############################################################################
# Logging
###############################################################################

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "${LOG_FILE}"
}

run() {
    echo "" | tee -a "${LOG_FILE}"
    echo "======================================================================" | tee -a "${LOG_FILE}"
    printf "%q " "$@" | tee -a "${LOG_FILE}"
    echo | tee -a "${LOG_FILE}"
    echo "======================================================================" | tee -a "${LOG_FILE}"

    "$@" 2>&1 | tee -a "${LOG_FILE}"
}

###############################################################################
# Validation
###############################################################################

docker inspect "${CONTAINER}" >/dev/null 2>&1 || {
    echo "ERROR: Container '${CONTAINER}' not found."
    exit 1
}

docker exec "${CONTAINER}" pgbench --version >/dev/null 2>&1 || {
    echo "ERROR: pgbench is not installed in '${CONTAINER}'."
    exit 1
}

###############################################################################
# Information
###############################################################################

log "PostgreSQL Benchmark"
log "Container : ${CONTAINER}"
log "Database  : ${PGDATABASE}"
log "User      : ${PGUSER}"
log "Scale     : ${SCALE}"
log "Duration  : ${TIME}s"
log "Clients   : ${CLIENTS}"

###############################################################################
# Versions
###############################################################################

run docker exec "${CONTAINER}" psql \
    -U "${PGUSER}" \
    -d "${PGDATABASE}" \
    -c "SELECT version();"

run docker exec "${CONTAINER}" pgbench --version

###############################################################################
# PostgreSQL Configuration
###############################################################################

run docker exec "${CONTAINER}" psql \
    -U "${PGUSER}" \
    -d "${PGDATABASE}" \
    -c "
SHOW shared_buffers;
SHOW work_mem;
SHOW maintenance_work_mem;
SHOW effective_cache_size;
SHOW wal_level;
SHOW wal_compression;
SHOW max_wal_size;
SHOW checkpoint_timeout;
SHOW synchronous_commit;
SHOW max_connections;
"

###############################################################################
# Initialize pgbench
###############################################################################

TABLE_EXISTS=$(
docker exec "${CONTAINER}" \
psql -U "${PGUSER}" -d "${PGDATABASE}" \
-tAc "SELECT EXISTS (
SELECT 1
FROM pg_tables
WHERE schemaname='public'
AND tablename='pgbench_accounts'
);"
)

if [[ "${INIT}" == "true" || "${TABLE_EXISTS}" != "t" ]]; then

    log "Initializing pgbench tables..."

    run docker exec "${CONTAINER}" \
        pgbench \
        -i \
        -s "${SCALE}" \
        -U "${PGUSER}" \
        "${PGDATABASE}"

    run docker exec "${CONTAINER}" \
        psql \
        -U "${PGUSER}" \
        -d "${PGDATABASE}" \
        -c "VACUUM ANALYZE;"

else
    log "pgbench tables already exist. Skipping initialization."
fi

###############################################################################
# Warm-up
###############################################################################

log "Warm-up"

run docker exec "${CONTAINER}" \
    pgbench \
    -c 8 \
    -j 4 \
    -T 60 \
    -P 30 \
    -U "${PGUSER}" \
    "${PGDATABASE}"

###############################################################################
# Benchmarks
###############################################################################

for c in ${CLIENTS}; do

    jobs=$(( c / 4 ))

    if (( jobs < 1 )); then
        jobs=1
    fi

    log "Benchmark (${c} clients)"

    run docker exec "${CONTAINER}" \
        pgbench \
        -c "${c}" \
        -j "${jobs}" \
        -T "${TIME}" \
        -P 30 \
        -r \
        -U "${PGUSER}" \
        "${PGDATABASE}"

done

###############################################################################
# PostgreSQL Statistics
###############################################################################

run docker exec "${CONTAINER}" \
psql \
-U "${PGUSER}" \
-d "${PGDATABASE}" \
-c "SELECT * FROM pg_stat_bgwriter;"

run docker exec "${CONTAINER}" \
psql \
-U "${PGUSER}" \
-d "${PGDATABASE}" \
-c "SELECT * FROM pg_stat_wal;"

###############################################################################
# Finished
###############################################################################

log "Benchmark completed."
log "Results saved to ${LOG_FILE}"