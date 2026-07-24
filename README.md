# Restore Guide

This guide explains how to restore a PostgreSQL database from pgBackRest backups.

## Prerequisites

Before restoring, ensure that:

* Docker and Docker Compose are installed.
* The PostgreSQL containers are stopped.
* The `.env`, `docker-compose.yml`, `postgresql.conf`, and `pgbackrest.conf` files are correctly configured.
* The pgBackRest repository (S3 or local) is accessible.

## Restore Workflow

1. Stop the PostgreSQL service.
2. Remove or rename the existing data directory.
3. Run the restore script.
4. Start the PostgreSQL service.
5. Verify that PostgreSQL starts successfully and that the expected data is present.

---

## Stop PostgreSQL

```bash
docker compose down
```

---

## Clean the Data Directory

> **Warning:** This permanently removes the current PostgreSQL data directory. Make sure you have a valid backup before proceeding.

```bash
sudo rm -rf /data/postgres/data/*
```

---

## Restore the Latest Backup

To restore the most recent backup:

```bash
./restore.sh
```

---

## Restore to a Specific Point in Time (PITR)

To restore the database to a specific timestamp:

```bash
./restore.sh "2026-07-23 09:59:59"
```

Replace the timestamp with the desired recovery time in the format:

```text
YYYY-MM-DD HH:MM:SS
```

---

## Start PostgreSQL

After the restore completes successfully:

```bash
docker compose up -d postgres
```

Or, if using the helper script:

```bash
./start.sh
```

---

## Verify the Restore

Check that PostgreSQL is accepting connections:

```bash
docker compose exec postgres pg_isready
```

Verify the server status:

```bash
docker compose exec postgres psql -U postgres -c "SELECT version();"
```

Check whether the server is still in recovery:

```bash
docker compose exec postgres psql -U postgres -c "SELECT pg_is_in_recovery();"
```

A successful restore should normally return:

```text
 pg_is_in_recovery
-------------------
 f
```

---

## Troubleshooting

### Restore Failed

Review the pgBackRest logs:

```bash
docker compose logs pgbackrest
```

or

```bash
docker compose exec pgbackrest pgbackrest info
```

### PostgreSQL Does Not Start

Check the PostgreSQL logs:

```bash
docker compose logs postgres
```

Common causes include:

* Existing files remain in the data directory.
* Incorrect ownership or permissions on `/data/postgres/data`.
* S3 repository is unreachable.
* Incorrect recovery target time.
* Invalid PostgreSQL or pgBackRest configuration.

---

## Notes

* Running `./restore.sh` without a timestamp restores the latest available backup.
* Supplying a timestamp performs Point-in-Time Recovery (PITR).
* The restore script does **not** automatically start PostgreSQL.
* Always verify the restored database before returning it to production.

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
