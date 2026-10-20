#!/usr/bin/env python3
"""Create gitops/secrets/*.enc.yaml with random values (idempotent: existing files are kept).

Values that must come from R1 (N8N_ENCRYPTION_KEY) are read from the local .env and, if
--verify-r1 is given, compared by SHA-256 with the running R1 container before use.
Anything the operator should be able to log in with is also written to
~/.config/aevia/r2-generated.env (mode 600), never printed.
"""
import hashlib, json, os, secrets, subprocess, sys
from pathlib import Path
import yaml

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "gitops" / "secrets"
GEN = Path.home() / ".config" / "aevia" / "r2-generated.env"

def rnd(n=32): return secrets.token_urlsafe(n)[:n]

def read_env(path, key):
    for line in Path(path).read_text().splitlines():
        if line.startswith(key + "="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit(f"{key} not in {path}")

def write(name, ns, data, labels=None):
    f = OUT / f"{name}.enc.yaml"
    if f.exists():
        print(f"keep    {f.name}")
        return
    doc = {"apiVersion": "v1", "kind": "Secret", "metadata": {"name": name, "namespace": ns, **({"labels": labels} if labels else {})},
           "type": "Opaque", "stringData": data}
    f.write_text(yaml.safe_dump(doc, sort_keys=False))
    subprocess.run(["sops", "-e", "-i", str(f)], check=True, cwd=REPO,
                   env={**os.environ, "SOPS_AGE_KEY_FILE": str(Path.home() / ".config/sops/age/keys.txt")})
    print(f"created {f.name}")

def write_offsite(name="backup-offsite", ns="data", prefix="postgres"):
    """rclone env config: Hetzner Object Storage bucket, client-side encrypted (crypt) so dumps are unreadable there."""
    if (OUT / f"{name}.enc.yaml").exists():
        print(f"keep    {name}.enc.yaml")
        return
    sec = Path.home() / ".config" / "aevia" / "secrets.env"
    ak = read_env(sec, "export TF_VAR_object_storage_access_key")
    sk = read_env(sec, "export TF_VAR_object_storage_secret_key")
    obscure = lambda v: subprocess.run(
        ["docker", "run", "--rm", "rclone/rclone:1.70.3", "obscure", v],
        capture_output=True, text=True, check=True).stdout.strip()
    write(name, ns, {
        "RCLONE_CONFIG_HZ_TYPE": "s3", "RCLONE_CONFIG_HZ_PROVIDER": "Other",
        "RCLONE_CONFIG_HZ_ENDPOINT": "https://hel1.your-objectstorage.com", "RCLONE_CONFIG_HZ_REGION": "hel1",
        "RCLONE_CONFIG_HZ_ACCESS_KEY_ID": ak, "RCLONE_CONFIG_HZ_SECRET_ACCESS_KEY": sk,
        "RCLONE_CONFIG_ENC_TYPE": "crypt", "RCLONE_CONFIG_ENC_REMOTE": f"hz:aevia-backups/{prefix}",
        "RCLONE_CONFIG_ENC_PASSWORD": obscure(rnd(40)), "RCLONE_CONFIG_ENC_PASSWORD2": obscure(rnd(40))})

def write_oidc():
    """Client secrets for the Authentik OIDC providers (blueprint in gitops/base/platform): one random value each,
    stored in authentik-env (read by the blueprint via !Env) and in the consuming namespace."""
    if (OUT / "grafana-oauth.enc.yaml").exists():
        print("keep    grafana-oauth.enc.yaml")
        return
    env = {"SOPS_AGE_KEY_FILE": str(Path.home() / ".config/sops/age/keys.txt")}
    sec = {"cloudflare": rnd(48), "grafana": rnd(48), "argocd": rnd(48)}
    f = str(OUT / "authentik-env.enc.yaml")
    for k, v in (("OIDC_CLOUDFLARE_SECRET", sec["cloudflare"]), ("OIDC_GRAFANA_SECRET", sec["grafana"]), ("OIDC_ARGOCD_SECRET", sec["argocd"])):
        subprocess.run(["sops", "set", f, f'["stringData"]["{k}"]', json.dumps(v)], check=True, cwd=REPO, env={**os.environ, **env})
    write("grafana-oauth", "observability", {"GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET": sec["grafana"]})
    write("argocd-oidc", "argocd", {"clientSecret": sec["argocd"]}, labels={"app.kubernetes.io/part-of": "argocd"})

def write_herdr_s3():
    """Credentials of the S3 identity `agents` (bucket agent-workspace only), taken from s3-auth."""
    if (OUT / "herdr-s3.enc.yaml").exists():
        print("keep    herdr-s3.enc.yaml")
        return
    env = {**os.environ, "SOPS_AGE_KEY_FILE": str(Path.home() / ".config/sops/age/keys.txt")}
    doc = yaml.safe_load(subprocess.run(["sops", "-d", str(OUT / "s3-auth.enc.yaml")], capture_output=True, text=True, check=True, env=env).stdout)
    ident = next(i for i in json.loads(doc["stringData"]["s3.json"])["identities"] if i["name"] == "agents")
    cred = ident["credentials"][0]
    write("herdr-s3", "agents", {"AWS_ACCESS_KEY_ID": cred["accessKey"], "AWS_SECRET_ACCESS_KEY": cred["secretKey"]})

def write_forgejo():
    """Forgejo: stable SECRET_KEY plus the OIDC client secret shared with the Authentik blueprint (OIDC_FORGEJO_SECRET)."""
    if (OUT / "forgejo-env.enc.yaml").exists():
        print("keep    forgejo-env.enc.yaml")
        return
    env = {**os.environ, "SOPS_AGE_KEY_FILE": str(Path.home() / ".config/sops/age/keys.txt")}
    sec = rnd(48)
    f = str(OUT / "authentik-env.enc.yaml")
    subprocess.run(["sops", "set", f, '["stringData"]["OIDC_FORGEJO_SECRET"]', json.dumps(sec)], check=True, cwd=REPO, env=env)
    write("forgejo-env", "platform", {"FORGEJO__security__SECRET_KEY": rnd(64), "OIDC_CLIENT_SECRET": sec})

def write_mcp():
    """Obsidian MCP server: one OIDC client secret shared by the Authentik blueprint (OIDC_MCP_SECRET) and the server."""
    if (OUT / "mcp-obsidian-env.enc.yaml").exists():
        print("keep    mcp-obsidian-env.enc.yaml")
        return
    env = {**os.environ, "SOPS_AGE_KEY_FILE": str(Path.home() / ".config/sops/age/keys.txt")}
    sec = rnd(48)
    f = str(OUT / "authentik-env.enc.yaml")
    subprocess.run(["sops", "set", f, '["stringData"]["OIDC_MCP_SECRET"]', json.dumps(sec)], check=True, cwd=REPO, env=env)
    write("mcp-obsidian-env", "apps", {"OIDC_CLIENT_SECRET": sec})

def main():
    # The n8n key came from the retired R1 server (.env); it is only needed while n8n-env does not exist yet.
    n8n_key = "" if (OUT / "n8n-env.enc.yaml").exists() else read_env(REPO / ".env", "N8N_ENCRYPTION_KEY")
    pg, n8n_pw, ak_pw, redis = rnd(), rnd(), rnd(), rnd()
    ak_boot, ak_token, grafana = rnd(24), rnd(40), rnd(24)
    s3_ak, s3_sk = rnd(20), rnd(40)
    write("postgres-auth", "data", {"POSTGRES_USER": "postgres", "POSTGRES_PASSWORD": pg,
                                    "POSTGRES_N8N_PASSWORD": n8n_pw, "POSTGRES_AUTHENTIK_PASSWORD": ak_pw})
    write("pg-backup-auth", "data", {"PGUSER": "postgres", "PGPASSWORD": pg})
    write("redis-auth", "data", {"REDIS_PASSWORD": redis})
    write("s3-auth", "data", {"s3.json": json.dumps({"identities": [{"name": "admin",
          "credentials": [{"accessKey": s3_ak, "secretKey": s3_sk}],
          "actions": ["Admin", "Read", "Write", "List", "Tagging"]}]})})
    write("n8n-env", "apps", {"N8N_ENCRYPTION_KEY": n8n_key, "DB_POSTGRESDB_PASSWORD": n8n_pw,
                              "QUEUE_BULL_REDIS_PASSWORD": redis})
    write("authentik-env", "platform", {"AUTHENTIK_SECRET_KEY": rnd(50), "AUTHENTIK_POSTGRESQL__PASSWORD": ak_pw,
                                        "AUTHENTIK_BOOTSTRAP_PASSWORD": ak_boot, "AUTHENTIK_BOOTSTRAP_TOKEN": ak_token})
    # Fresh gateway key. To adopt an existing instance replace this secret and add the seed (docs/runbooks/ai-gateway.md).
    write("freellmapi-env", "platform", {"ENCRYPTION_KEY": secrets.token_hex(32)})
    write_offsite()
    write_offsite("freellmapi-backup-offsite", "platform", "freellmapi")
    if os.environ.get("TUNNEL_TOKEN"):  # from: GET /accounts/<id>/cfd_tunnel/<tunnel_id>/token
        write("cloudflared-token", "edge", {"TUNNEL_TOKEN": os.environ["TUNNEL_TOKEN"]})
    write_oidc()
    write_herdr_s3()
    write_forgejo()
    write_mcp()
    write("grafana-admin", "observability", {"admin-user": "admin", "admin-password": grafana})
    if not GEN.exists():
        GEN.parent.mkdir(parents=True, exist_ok=True)
        GEN.touch(mode=0o600)
        GEN.write_text(f"AUTHENTIK_BOOTSTRAP_PASSWORD={ak_boot}\nGRAFANA_ADMIN_PASSWORD={grafana}\n"
                       f"S3_ACCESS_KEY={s3_ak}\nS3_SECRET_KEY={s3_sk}\n")
        print(f"login values saved to {GEN} (600)")

if __name__ == "__main__":
    main()
