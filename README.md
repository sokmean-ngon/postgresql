# Host OS Tuning

Before deploying PostgreSQL, tune the Linux kernel parameters for better database performance.

## Configure sysctl

Edit the sysctl configuration file:

```bash
sudo nano /etc/sysctl.conf
```

Add the following parameters:

```conf
# -----------------------------------------------------------------------------
# PostgreSQL Performance Tuning
# -----------------------------------------------------------------------------

# Reduce swapping
vm.swappiness = 1

# Dirty page writeback
vm.dirty_background_ratio = 5
vm.dirty_ratio = 15

# Shared memory
kernel.shmmax = 17179869184
kernel.shmall = 4194304
```

Or create a dedicated configuration file:

```bash
sudo tee /etc/sysctl.d/99-postgresql.conf >/dev/null <<EOF
# PostgreSQL Performance Tuning

vm.swappiness=1
vm.dirty_background_ratio=5
vm.dirty_ratio=15

kernel.shmmax=17179869184
kernel.shmall=4194304
EOF
```

Reload the kernel parameters:

```bash
sudo sysctl --system
```

Verify the configuration:

```bash
sysctl vm.swappiness
sysctl vm.dirty_background_ratio
sysctl vm.dirty_ratio
sysctl kernel.shmmax
sysctl kernel.shmall
```

Expected output:

```text
vm.swappiness = 1
vm.dirty_background_ratio = 5
vm.dirty_ratio = 15
kernel.shmmax = 17179869184
kernel.shmall = 4194304
```

## Parameter Description

| Parameter                   |           Recommended | Description                                                        |
| --------------------------- | --------------------: | ------------------------------------------------------------------ |
| `vm.swappiness`             |                   `1` | Minimizes swapping and keeps PostgreSQL memory in RAM.             |
| `vm.dirty_background_ratio` |                   `5` | Starts background flushing when 5% of memory contains dirty pages. |
| `vm.dirty_ratio`            |                  `15` | Forces dirty pages to be written when 15% of memory is dirty.      |
| `kernel.shmmax`             | `17179869184` (16 GB) | Maximum size of a shared memory segment.                           |
| `kernel.shmall`             |             `4194304` | Total shared memory pages available to the system.                 |

## Notes

* These values are appropriate for a server with **32 GB RAM**.
* If the server memory changes, adjust `kernel.shmmax` and `kernel.shmall` accordingly.
* A system reboot is **not required** after running `sysctl --system`.

# Initial Setup

Before starting PostgreSQL for the first time, initialize the project directory structure and configure the required permissions.

The `setup.sh` script will automatically:

- Create the required project directories.
- Detect the PostgreSQL container UID/GID.
- Configure ownership and permissions.
- Create the PostgreSQL log directory.
- Prepare the environment for Docker Compose deployment.

---

# Project Structure

After running the setup script, the project directory will look like this:

```text
postgresql/
├── compose.yaml
├── .env
├── conf/
├── data/
├── initdb/
├── logs/
│   └── postgresql.log
├── pgbackrest-spool/
├── pmm-client/
├── scripts/
│   ├── setup.sh
│   ├── backup-full.sh
│   ├── backup-diff.sh
│   ├── backup-expire.sh
│   ├── restore.sh
│   └── start.sh
└── wal-archive/
```

---

# Run the Setup Script

Execute the setup script from the project root directory.

```bash
./scripts/setup.sh
```

Example output:

```text
[INFO] Detecting PostgreSQL UID/GID...
[ OK ] postgres uid=26 gid=26
[INFO] Setting ownership...
[INFO] Setting permissions...
[ OK ] Directory structure created.
```

The script is **idempotent**, meaning it can be executed multiple times safely.

---

# What the Script Does

## Creates Required Directories

The following directories are created if they do not already exist:

```text
conf/
data/
initdb/
logs/
pgbackrest-spool/
pmm-client/
scripts/
wal-archive/
```

---

## Detects PostgreSQL UID/GID

The script automatically detects the UID and GID used by the PostgreSQL container.

Example:

```text
postgres uid=26
postgres gid=26
```

This avoids hardcoding user IDs and improves compatibility with future PostgreSQL image versions.

---

## Sets Ownership

The following directories are owned by the PostgreSQL container user:

```text
data/
logs/
wal-archive/
pgbackrest-spool/
```

Configuration directories remain owned by the host user:

```text
conf/
initdb/
scripts/
pmm-client/
```

---

## Sets Permissions

The script configures the recommended permissions.

| Directory | Permission |
|-----------|-----------:|
| data | 700 |
| wal-archive | 700 |
| pgbackrest-spool | 700 |
| logs | 750 |
| conf | 755 |
| initdb | 755 |
| scripts | 755 |
| pmm-client | 755 |

Configuration files:

```text
644
```

Shell scripts:

```text
755
```

---

# Verify Directory Permissions

After running the setup script, verify the permissions.

```bash
ls -lah
```

Verify ownership:

```bash
ls -ln
```

---

# Start PostgreSQL

After the setup completes successfully, start the stack.

```bash
docker compose up -d
```

Verify the containers:

```bash
docker compose ps
```

Example:

```text
NAME          STATUS
postgres      Up (healthy)
pgbackrest    Up
pmm-client    Up
```

---

# Re-run the Setup Script

The setup script is safe to execute multiple times.

For example:

```bash
./scripts/setup.sh
```

You may re-run the script after:

- Upgrading PostgreSQL
- Migrating to a new server
- Restoring the project from backup
- Accidentally changing file permissions
- Creating a fresh deployment

---

# Notes

- The setup script **does not overwrite PostgreSQL data**.
- Existing databases are preserved.
- Existing configuration files are not modified.
- Existing WAL archives are preserved.
- Existing backups are preserved.
- Only missing directories are created and permissions are corrected.

> **Warning**
>
> Do not manually delete the `data/` directory unless you intend to initialize a new PostgreSQL cluster or perform a restore from backup.

# Backup & Restore

## Automatic Backup Schedule

Backups are scheduled on the **host** using `cron`. The `pgbackrest` container does not run a cron daemon.

Edit the root crontab:

```bash
sudo crontab -e
```

Add the following entries:

```cron
# Weekly Full Backup (Sunday 01:00)
0 1 * * 0 /path/to/postgresql/scripts/backup-full.sh >> /var/log/pgbackrest.log 2>&1

# Daily Differential Backup (Monday-Saturday 01:00)
0 1 * * 1-6 /path/to/postgresql/scripts/backup-diff.sh >> /var/log/pgbackrest.log 2>&1

# Cleanup Expired Backups (Daily 03:00)
0 3 * * * /path/to/postgresql/scripts/backup-expire.sh >> /var/log/pgbackrest.log 2>&1
```

Replace `/path/to/postgresql` with your PostgreSQL project directory.

Example:

```cron
0 1 * * 0 /opt/postgresql/scripts/backup-full.sh >> /var/log/pgbackrest.log 2>&1
0 1 * * 1-6 /opt/postgresql/scripts/backup-diff.sh >> /var/log/pgbackrest.log 2>&1
0 3 * * * /opt/postgresql/scripts/backup-expire.sh >> /var/log/pgbackrest.log 2>&1
```

---

# Manual Restore

Restores are intentionally **manual** to prevent accidental data loss.

## Show Available Backups

```bash
./scripts/restore.sh --info
```

Example output:

```
stanza: main
    status: ok

    full backup: 20260720-010001F
    diff backup: 20260724-010001D
```

---

## Verify Backup Repository

```bash
./scripts/restore.sh --check
```

---

## Restore Latest Backup

Stop PostgreSQL:

```bash
docker compose stop postgres
```

Restore:

```bash
./scripts/restore.sh
```

Start PostgreSQL:

```bash
./scripts/start.sh
```

---

## Point-in-Time Recovery (PITR)

Restore to a specific timestamp:

```bash
docker compose stop postgres

./scripts/restore.sh "2026-07-26 14:30:00"

./scripts/start.sh
```

---

## Restore to a PostgreSQL Restore Point

Create a restore point before making significant changes:

```sql
SELECT pg_create_restore_point('before_upgrade');
```

Restore to that point:

```bash
docker compose stop postgres

./scripts/restore.sh restore_point before_upgrade

./scripts/start.sh
```

---

## Restore a Specific Backup Set

List available backups:

```bash
./scripts/restore.sh --info
```

Restore a specific backup:

```bash
docker compose stop postgres

./scripts/restore.sh --set 20260720-010001F

./scripts/start.sh
```

---

## Restore Workflow

```
┌─────────────────────────────┐
│ Stop PostgreSQL             │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│ Verify Backup Repository    │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│ Delete Existing Data        │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│ Restore with pgBackRest     │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│ Start PostgreSQL            │
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│ Verify Database             │
└─────────────────────────────┘
```

---

## Verification

Check PostgreSQL status:

```bash
docker exec postgres pg_isready
```

Verify recovery status:

```bash
docker exec postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
```

Display server version:

```bash
docker exec postgres psql -U postgres -c "SELECT version();"
```

Display current timestamp:

```bash
docker exec postgres psql -U postgres -c "SELECT now();"
```

---

## Important Notes

- Always stop PostgreSQL before restoring.
- The restore process deletes the existing PostgreSQL data directory before restoring from backup.
- `restore.sh` never starts PostgreSQL automatically.
- Always run `start.sh` after a successful restore.
- Ensure WAL archiving is functioning correctly to enable Point-in-Time Recovery (PITR).
- Test your backup and restore procedures regularly to verify disaster recovery readiness.

# Percona Monitoring and Management (PMM)

This section describes how to create a dedicated PostgreSQL monitoring user and register the database with a PMM Server.

---

# Create PMM Monitoring User

Connect to PostgreSQL:

```bash
docker exec -it postgres psql -U postgres
```

Create a dedicated monitoring user.

Replace `CHANGE_ME` with a strong password.

```sql
CREATE ROLE pmm LOGIN PASSWORD 'CHANGE_ME';

GRANT pg_monitor TO pmm;
GRANT pg_read_all_stats TO pmm;
GRANT pg_read_all_settings TO pmm;
GRANT pg_read_all_data TO pmm;
```

Grant CONNECT permission to every existing database.

```sql
DO
$$
DECLARE
    db RECORD;
BEGIN
    FOR db IN
        SELECT datname
        FROM pg_database
        WHERE datistemplate = false
    LOOP
        EXECUTE format(
            'GRANT CONNECT ON DATABASE %I TO pmm;',
            db.datname
        );
    END LOOP;
END;
$$;
```

Verify:

```sql
\du
```

Expected output:

```
Role name | Attributes
----------+------------------------------
pmm       | Login
```

Exit PostgreSQL:

```sql
\q
```

---

# Configure PMM Client

Edit the `.env` file.

```dotenv
PMM_SERVER_IP=192.168.10.100
PMM_SERVER_USER=admin
PMM_SERVER_PASSWORD=CHANGE_ME

PMM_POSTGRES_USER=pmm
PMM_POSTGRES_PASSWORD=CHANGE_ME
```

---

# Start PMM Client

```bash
docker compose up -d pmm-client
```

Verify the container is running.

```bash
docker compose ps
```

---

# Register PostgreSQL with PMM Server

Register the database:

```bash
docker exec pmm-client \
pmm-admin add postgresql \
    --username=${PMM_POSTGRES_USER} \
    --password=${PMM_POSTGRES_PASSWORD} \
    --host=postgres \
    --port=5432 \
    --database=postgres \
    --service-name=postgresql \
    --query-source=pgstatmonitor
```

If `pgstatmonitor` is not installed, use:

```bash
docker exec pmm-client \
pmm-admin add postgresql \
    --username=${PMM_POSTGRES_USER} \
    --password=${PMM_POSTGRES_PASSWORD} \
    --host=postgres \
    --port=5432 \
    --database=postgres \
    --service-name=postgresql
```

---

# Verify Registration

Check PMM client status:

```bash
docker exec pmm-client pmm-admin status
```

Example:

```
Agent ID      : ...
Node ID       : ...
Node name     : postgres-node
PMM Server    : https://192.168.10.100
```

List monitored services:

```bash
docker exec pmm-client pmm-admin list
```

Expected output:

```
Service type    : PostgreSQL
Service name    : postgresql
Address         : postgres:5432
```

---

# Verify from PMM Server

Open the PMM web interface.

```
https://<PMM_SERVER_IP>
```

Navigate to:

```
Inventory
    └── Services
```

Verify:

- PostgreSQL service is **Up**
- Node status is **Online**
- Metrics are being collected

Then open:

```
Dashboards
    └── PostgreSQL
```

Verify:

- Connections
- Transactions
- WAL Activity
- Replication
- Buffer Cache
- Checkpoints
- Query Analytics

are reporting data.

---

# Troubleshooting

## Check PMM Client Logs

```bash
docker compose logs -f pmm-client
```

---

## Check Agent Status

```bash
docker exec pmm-client pmm-admin status
```

---

## Remove Registration

```bash
docker exec pmm-client \
pmm-admin remove postgresql postgresql
```

---

## Register Again

```bash
docker exec pmm-client \
pmm-admin add postgresql \
    --username=${PMM_POSTGRES_USER} \
    --password=${PMM_POSTGRES_PASSWORD} \
    --host=postgres \
    --port=5432 \
    --database=postgres \
    --service-name=postgresql \
    --query-source=pgstatmonitor
```

---

# Security Recommendations

- Use a dedicated monitoring user (`pmm`).
- Never use the `postgres` superuser for monitoring.
- Store credentials only in the `.env` file.
- Use a strong password for the PMM monitoring user.
- Restrict network access to the PMM Server.
- Enable HTTPS for all PMM communications.