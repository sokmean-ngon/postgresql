#!/bin/bash

set -euo pipefail

POSTGRES_CONTAINER="postgres"

PMM_USER="${PMM_USER:-pmm}"
PMM_PASSWORD="${PMM_PASSWORD:?PMM_PASSWORD is required}"

docker exec \
    -e PGPASSWORD="${POSTGRES_PASSWORD}" \
    "${POSTGRES_CONTAINER}" \
    psql -v ON_ERROR_STOP=1 -U postgres -d postgres <<EOF
DO
\$BODY\$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = '${PMM_USER}'
    ) THEN
        CREATE ROLE ${PMM_USER}
            LOGIN
            PASSWORD '${PMM_PASSWORD}';
    ELSE
        ALTER ROLE ${PMM_USER}
            WITH PASSWORD '${PMM_PASSWORD}';
    END IF;
END
\$BODY\$;

GRANT pg_monitor TO ${PMM_USER};
GRANT pg_read_all_stats TO ${PMM_USER};
GRANT pg_read_all_settings TO ${PMM_USER};

DO
\$BODY\$
DECLARE
    db RECORD;
BEGIN
    FOR db IN
        SELECT datname
        FROM pg_database
        WHERE datistemplate = false
    LOOP
        EXECUTE format(
            'GRANT CONNECT ON DATABASE %I TO ${PMM_USER}',
            db.datname
        );
    END LOOP;
END
\$BODY\$;

SELECT rolname
FROM pg_roles
WHERE rolname='${PMM_USER}';

SELECT datname
FROM pg_database
WHERE has_database_privilege('${PMM_USER}', datname, 'CONNECT')
ORDER BY datname;
EOF

echo "PMM user '${PMM_USER}' configured successfully."