#!/bin/bash
set -e

docker exec pgbackrest \
    pgbackrest \
    --stanza=main \
    expire