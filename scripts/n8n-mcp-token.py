#!/usr/bin/env python3
"""Create the access token for n8n's own MCP server (/mcp-server/http) and store it for the Aevia MCP server.

n8n signs its MCP tokens as JWTs (HS256, audience `mcp-server-api`) with the secret `signing.jwt` from the table `deployment_key`, and lists them in
`user_api_keys`. The UI button "generate token" does exactly this; this script does it without a browser login, so it can be repeated after a restore.
It reads the secret through kubectl, mints the token, inserts the row (once) and writes the SOPS secret `mcp-n8n` (namespace apps, key N8N_MCP_TOKEN).
Neither the signing secret nor the token is printed.

  KUBECONFIG=~/.kube/aevia.yaml python3 scripts/n8n-mcp-token.py [--owner max.rml@web.de] [--rotate]
"""
import argparse, base64, hashlib, hmac, json, os, secrets, string, subprocess, sys, time, uuid
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "gitops" / "secrets" / "mcp-n8n.enc.yaml"
AUDIENCE, LABEL = "mcp-server-api", "Aevia MCP server"


def psql(sql, stdin=None):
    cmd = ["kubectl", "-n", "data", "exec", "-i", "postgres-0", "--", "sh", "-c",
           'export PGPASSWORD="$POSTGRES_PASSWORD"; psql -U postgres -d n8n -At -v ON_ERROR_STOP=1' + (" -f -" if stdin else f' -c "{sql}"')]
    r = subprocess.run(cmd, input=stdin, capture_output=True, text=True)
    if r.returncode:
        sys.exit("psql failed: " + r.stderr.strip()[:300])
    return r.stdout.strip()


def b64(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def mint(secret, user_id):
    head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    body = b64(json.dumps({"sub": user_id, "iss": "n8n", "aud": AUDIENCE, "jti": str(uuid.uuid4()), "iat": int(time.time())}, separators=(",", ":")).encode())
    sig = b64(hmac.new(secret.encode(), f"{head}.{body}".encode(), hashlib.sha256).digest())
    return f"{head}.{body}.{sig}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--owner", default="max.rml@web.de")
    ap.add_argument("--rotate", action="store_true", help="replace an existing MCP token")
    a = ap.parse_args()
    if OUT.exists() and not a.rotate:
        print(f"keep    {OUT.name} (use --rotate to replace the token)")
        return
    user_id = psql(f"select id from \\\"user\\\" where email = '{a.owner}'")
    if not user_id:
        sys.exit(f"no n8n user {a.owner}")
    secret = psql("select value from deployment_key where type = 'signing.jwt' and status = 'active'")
    if len(secret) < 32:
        sys.exit("signing secret not found")
    token = mint(secret, user_id)
    key_id = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(16))
    sql = ""
    if a.rotate:
        sql += f"delete from user_api_keys where \"userId\" = '{user_id}' and audience = '{AUDIENCE}';\n"
    sql += (f"insert into user_api_keys (id, \"userId\", label, \"apiKey\", \"createdAt\", \"updatedAt\", scopes, audience) "
            f"values ('{key_id}', '{user_id}', '{LABEL}', '{token}', now(), now(), '[]', '{AUDIENCE}');\n")
    psql(None, stdin=sql)
    doc = {"apiVersion": "v1", "kind": "Secret", "metadata": {"name": "mcp-n8n", "namespace": "apps"}, "type": "Opaque", "stringData": {"N8N_MCP_TOKEN": token}}
    OUT.write_text(json.dumps(doc))
    subprocess.run(["sops", "-e", "-i", str(OUT)], check=True, cwd=REPO,
                   env={**os.environ, "SOPS_AGE_KEY_FILE": str(Path.home() / ".config/sops/age/keys.txt")})
    print(f"created {OUT.name}; token row {key_id} for {a.owner}")


if __name__ == "__main__":
    main()
