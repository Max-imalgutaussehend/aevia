# Runbook: restore Postgres into R2 (phase 12 / 28)

Needs a cluster. Not run yet (server untouched). `longevity` is excluded until released.

1. Take a fresh dump on R1 (`scripts/backup.sh`) or use the newest `pg-backup` file.
2. Sync `namespaces`, `data`; wait for `postgres-0` Ready.
3. `kubectl -n data exec -i postgres-0 -- sh -c 'gunzip | psql -U "$POSTGRES_USER" postgres' < dump.sql.gz`
4. Verify: `\l` shows `n8n`; row counts of `n8n.workflow_entity` equal R1.
5. Sync `services`; open n8n and confirm a stored credential decrypts (needs the R1 `N8N_ENCRYPTION_KEY`).

Rollback: delete the `data` PVC and re-sync. R1 is untouched.
