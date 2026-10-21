# Runbook: restore Postgres into R2 (phase 12 / 28)

Needs a cluster. Not run yet (server untouched). `longevity` is excluded until released.

1. Take a fresh dump on R1 (`scripts/backup.sh`) or use the newest `pg-backup` file.
2. Sync `namespaces`, `data`; wait for `postgres-0` Ready.
3. `kubectl -n data exec -i postgres-0 -- sh -c 'gunzip | psql -U "$POSTGRES_USER" postgres' < dump.sql.gz`
4. Verify: `\l` shows `n8n`; row counts of `n8n.workflow_entity` equal R1.
5. Sync `services`; open n8n and confirm a stored credential decrypts (needs the R1 `N8N_ENCRYPTION_KEY`).

Rollback: delete the `data` PVC and re-sync. R1 is untouched.

## Free-tier guard

Backups live in Cloudflare R2 free tier (10 GB). The three backup CronJobs abort if `aevia-backups` + `aevia-archive` exceed 7 GiB; a failed Job with message `ABORT: R2 above 7 GiB` means this limit was hit.

Check usage: `rclone size r2:aevia-backups` (the nightly Job logs `r2 used: <n> MiB of 10240 MiB free tier`).

If the limit is reached: shorten retention or move old data to the laptop. Do not raise the limit.
