#!/bin/bash

set -euo pipefail

docker compose up -d postgres

echo "Waiting for PostgreSQL..."

until docker compose exec postgres pg_isready -U postgres >/dev/null 2>&1
do
    sleep 2
done

echo
echo "PostgreSQL is ready."

docker compose exec postgres psql -U postgres -c "SELECT version();"
docker compose exec postgres psql -U postgres -c "SELECT pg_is_in_recovery();"