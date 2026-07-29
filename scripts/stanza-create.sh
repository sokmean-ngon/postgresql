#!/bin/bash
set -e

docker exec -it postgres pgbackrest --stanza=main stanza-create