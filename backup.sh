#!/bin/bash

set -e

echo "Starting backup scheduler..."

# Weekly full backup
echo "0 2 * * 0 pgbackrest --config=/etc/postgresql/pgbackrest/pgbackrest.conf --stanza=main backup --type=full" >/etc/crontabs/root

# Daily differential backup
echo "0 2 * * 1-6 pgbackrest --config=/etc/postgresql/pgbackrest/pgbackrest.conf --stanza=main backup --type=diff" >>/etc/crontabs/root

# Expire old backups
echo "30 3 * * * pgbackrest --config=/etc/postgresql/pgbackrest/pgbackrest.conf --stanza=main expire" >>/etc/crontabs/root

crond -f