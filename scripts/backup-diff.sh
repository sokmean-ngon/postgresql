#!/bin/bash
set -e

docker exec pgbackrest \
    pgbackrest \
    --stanza=main \
    backup \
    --type=diff