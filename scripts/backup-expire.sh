#!/bin/bash
set -e

docker exec pgbackrest \
    pgbackrest \
    --config=/var/lib/postgresql/pgbackrest/pgbackrest.conf \
    --stanza=main \
    expire