# 0044 Nextcloud: files, phone photos and the Obsidian vault

Date: 2026-11-11. Status: accepted.

## Decision
- Nextcloud 34 (Apache image, digest pinned) at `nextcloud.maxrommel.de`, namespace `apps`, PostgreSQL database `nextcloud` (created by a PostSync Job, `gitops/base/data/nextcloud-db.yaml`), data on a 30 Gi local-path volume. No Redis: one user does not need it.
- Hand-written manifests (`gitops/base/platform/nextcloud.yaml`); the catalog entry is `managed_by: helm`, which only makes Tofu publish the host and the Access app.
- Sign-in: Cloudflare Access with Authentik for the browser. Apps and WebDAV clients cannot do that, so `remote.php`, `ocs`, the app login flow, `status.php` and previews bypass Access (`access_bypass`); Nextcloud authenticates those itself (app passwords, brute-force protection). Turn on 2FA for the account.
- Quota: 30 GB for the user (the node disk is 80 GB). Cron mode with a sidecar; Apache prefork limited to 12 workers.
- Vault: the folder `Vault` is synced both ways with the Forgejo repository `akadmin/obsidian-vault` by a sidecar (git, every 2 minutes; the Nextcloud side wins a conflict, the git history is the undo). It is the same repository the MCP server writes to and the Obsidian Git plugin pushes to. The phone uses the Obsidian plugin Remotely Save (WebDAV, `/remote.php/dav/files/max/Vault`) with an app password; photos use the Nextcloud app's auto upload.

## Consequences
- Files are not in the R2 backup (free tier limit 7 GiB); only the database is. Photo uploads grow the node disk: watch it (Grafana) and keep the quota.
- Postgres was restarted once by the rollout (`POSTGRES_SERVICES`).
- Gotchas found: a failed first install (wrong DB password) leaves `version.php` and a half `config.php`, and the entrypoint then skips the install: delete both and restart. An Argo Sync hook that needs a policy from the same sync deadlocks: use PostSync. macOS file names in NFD form (umlauts) are refused by Nextcloud ("incompatible encoding").
