# Runbook: restore from the R2 backups

Backups live in Cloudflare R2 (bucket `aevia-backups`), encrypted client-side with rclone crypt; the keys are in the SOPS secrets
`backup-offsite` (Postgres, prefix `postgres`) and `freellmapi-backup-offsite` (gateway, Forgejo, Kuma, ntfy). Retention: 14 days.

## Rehearsed 2026-10-21 (laptop, throwaway Postgres container)
1. Decrypt the secret and turn it into an rclone env file: `sops -d gitops/secrets/backup-offsite.enc.yaml`, keep the `RCLONE_CONFIG_*` lines as `NAME=value`.
2. `docker run --rm --env-file env -v $PWD/out:/out rclone/rclone:1.70.3 copy enc: /out --include 'aevia-*.sql.gz' --max-age 2d`
3. `gzip -t` the newest dump, start `postgres:16-alpine`, `gunzip -c dump | psql -U postgres`. Expect two harmless errors: `role "postgres" already exists` and `unrecognized configuration parameter "transaction_timeout"` (the dump comes from a newer server).
4. Result: databases `n8n` and `authentik` restored; 115 and 230 tables, 3 Authentik users, 0 n8n workflows: the same numbers as the live database.
5. Forgejo: `copy enc:forgejo/<day> out` gives `forgejo.tgz`; the vault repository `git/repositories/akadmin/obsidian-vault.git` passes `git fsck`, 38 commits, 48 notes.
Delete the env file and the downloaded data afterwards.

## Into a cluster
Sync `namespaces`, `data`; wait for `postgres-0` Ready; then
`kubectl -n data exec -i postgres-0 -- sh -c 'gunzip | psql -U "$POSTGRES_USER" postgres' < dump.sql.gz`, check `\l`, sync `services`.
n8n credentials decrypt only with the original `N8N_ENCRYPTION_KEY` (secret `n8n-env`). Rollback: delete the `data` PVC and re-sync.
For Forgejo stop the pod, unpack `forgejo.tgz` into the `forgejo-data` volume, start it.
A full rebuild of the cluster from nothing has not been rehearsed yet.

## Free-tier guard

Backups live in Cloudflare R2 free tier (10 GB). The three backup CronJobs abort if `aevia-backups` + `aevia-archive` exceed 7 GiB; a failed Job with message `ABORT: R2 above 7 GiB` means this limit was hit.

Check usage: `rclone size r2:aevia-backups` (the nightly Job logs `r2 used: <n> MiB of 10240 MiB free tier`).

If the limit is reached: shorten retention or move old data to the laptop. Do not raise the limit.
