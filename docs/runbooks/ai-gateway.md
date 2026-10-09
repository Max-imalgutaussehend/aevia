# Runbook: adopt an existing FreeLLMAPI instance (phase 24)

Goal: keep your provider keys. They live encrypted in the instance's SQLite DB, protected by `ENCRYPTION_KEY`.
Both must come along; neither is ever pasted into chat or committed in plaintext.

On the machine that runs FreeLLMAPI today:

1. `grep '^ENCRYPTION_KEY=' ~/freellmapi/.env` (read it yourself, do not paste it anywhere; it is 64 hex characters).
2. Stop the container so SQLite is in a clean state: `docker compose -f ~/freellmapi/docker-compose.yml stop freellmapi`.
3. Copy the data volume out and build the encrypted seed:
   `docker run --rm -v <project>_freellmapi-data:/d -v /tmp/flm:/o alpine sh -c 'cp -a /d/. /o/'`
   `./scripts/freellmapi-seed.sh /tmp/flm` (needs sops + your age key; writes `gitops/secrets/freellmapi-seed.enc.yaml`)
4. Create `gitops/secrets/freellmapi-env.enc.yaml` from `freellmapi-env.example.yaml`: put the `ENCRYPTION_KEY` value there, `sops -e -i`.
5. Delete `/tmp/flm`. Commit only the two `.enc.yaml` files.

In the cluster (needs the server, not done yet): the `seed` init container copies the files into the empty data volume
once. Later restarts leave the volume alone. If the DB is larger than ~900KiB, skip the Secret and use
`kubectl -n platform cp` into the pod's `/app/server/data` instead.

Verify: dashboard login works, Keys page lists your providers, `curl -H "Authorization: Bearer freellmapi-..." http://freellmapi.platform:3001/v1/models` from an agent pod returns models.

Notes: pin is the registry digest of `:latest` on 2026-10-09. If your instance runs an older version, pin its digest instead
(`docker image inspect ghcr.io/tashfeenahmed/freellmapi --format '{{index .RepoDigests 0}}'`); a newer app can migrate an older DB, not the reverse.
Back up the PVC (`freellmapi-data`) separately: `pg-backup` only covers Postgres.
