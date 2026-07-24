#!/bin/bash

set -euo pipefail

STANZA="main"
CONFIG="/etc/postgresql/pgbackrest/pgbackrest.conf"

if [ $# -eq 1 ]; then
    echo "Restoring to point in time: $1"

    docker compose run --rm postgres \
        pgbackrest \
        --config="${CONFIG}" \
        --stanza="${STANZA}" \
        --type=time \
        --target="$1" \
        restore
else
    echo "Restoring latest backup..."

    docker compose run --rm postgres \
        pgbackrest \
        --config="${CONFIG}" \
        --stanza="${STANZA}" \
        restore
fi

echo "Verify..."
docker compose run --rm postgres \
    pgbackrest \
    --config="${CONFIG}" \
    --stanza="${STANZA}" \
    info

echo
echo "Restore completed."
echo "Run ./start.sh when you are ready."