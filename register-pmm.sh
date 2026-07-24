#!/bin/bash

set -euo pipefail

PMM_CONTAINER="pmm-client"
POSTGRES_CONTAINER="postgres"

PMM_DB_USER="${PMM_DB_USER:-pmm}"
PMM_DB_PASSWORD="${PMM_DB_PASSWORD}"

echo "Waiting for PostgreSQL..."

until docker exec "${POSTGRES_CONTAINER}" pg_isready -U postgres >/dev/null 2>&1
do
    sleep 2
done

echo "Registering PostgreSQL with PMM..."

docker exec \
    -e PMM_DB_PASSWORD="${PMM_DB_PASSWORD}" \
    "${PMM_CONTAINER}" \
    pmm-admin add postgresql \
        --username="${PMM_DB_USER}" \
        --password="${PMM_DB_PASSWORD}" \
        --host=postgres \
        --port=5432 \
        --service-name=postgres \
        --query-source=pgstatmonitor

echo "PMM registration completed."