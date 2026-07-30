#!/usr/bin/env bash

set -Eeuo pipefail
source "$(dirname "$0")/restore-common.sh"

run_pgbackrest check