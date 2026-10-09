# gitops/secrets

Encrypted Kubernetes Secrets (ADR-0032). Only `*.enc.yaml` is ever committed; the
`*.example.yaml` files document the keys each workload expects.

Create one (needs the operator age key, nothing on the server):

    cp n8n-env.example.yaml n8n-env.enc.yaml   # fill in real values
    sops -e -i n8n-env.enc.yaml                # rules from ../../.sops.yaml

`kustomization.yaml` + `secret-generator.yaml` (ksops) are added when the first
`.enc.yaml` exists. Until then Argo CD has no `secrets` app, so workloads wait for
their Secrets (`CreateContainerConfigError`) rather than starting with defaults.

| Secret | Namespace | Keys |
|---|---|---|
| postgres-auth | data | POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_N8N_PASSWORD |
| redis-auth | data | REDIS_PASSWORD |
| pg-backup-auth | data | PGUSER, PGPASSWORD |
| n8n-env | apps | N8N_ENCRYPTION_KEY, DB_POSTGRESDB_PASSWORD, QUEUE_BULL_REDIS_PASSWORD |
| cloudflared-token | edge | TUNNEL_TOKEN |

`N8N_ENCRYPTION_KEY` must be the R1 value: it decrypts credentials in the restored DB.
| minio-auth | data | MINIO_ROOT_USER, MINIO_ROOT_PASSWORD |
| authentik-env | platform | AUTHENTIK_SECRET_KEY, AUTHENTIK_POSTGRESQL__PASSWORD, AUTHENTIK_BOOTSTRAP_PASSWORD, AUTHENTIK_BOOTSTRAP_TOKEN |
| grafana-admin | observability | admin-user, admin-password |
