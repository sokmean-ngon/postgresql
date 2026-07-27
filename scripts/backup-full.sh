#!/bin/bash
set -e

docker exec postgres \
    pgbackrest \
    --stanza=main \
    backup \
    --type=full