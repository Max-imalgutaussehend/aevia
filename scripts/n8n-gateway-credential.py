#!/usr/bin/env python3
"""Create the n8n credential "Aevia AI Gateway" (Header Auth: `Authorization: Bearer <gateway key>`) without a browser login.

n8n stores credentials in `credentials_entity.data`, encrypted like CryptoJS.AES.encrypt(json, N8N_ENCRYPTION_KEY): base64 of "Salted__" + salt + AES-256-CBC
ciphertext, key and IV from OpenSSL's EVP_BytesToKey (MD5). The row is shared with the owner's personal project, so the owner sees it in the UI and workflows can use it.
The gateway key comes from the secret `herdr-gateway` (agents) and is never printed. Idempotent: an existing credential with this name is left alone (`--replace` rewrites it).

  KUBECONFIG=~/.kube/aevia.yaml python3 scripts/n8n-gateway-credential.py [--replace]
Needs the `cryptography` package and sops (for the encryption key in gitops/secrets/n8n-env.enc.yaml).
"""
import argparse, base64, hashlib, json, os, re, secrets, string, subprocess, sys
from pathlib import Path

from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

REPO = Path(__file__).resolve().parent.parent
NAME, TYPE = "Aevia AI Gateway", "httpHeaderAuth"


def kubectl(*args, stdin=None):
    r = subprocess.run(["kubectl", *args], input=stdin, capture_output=True, text=True)
    if r.returncode:
        sys.exit("kubectl failed: " + r.stderr.strip()[:300])
    return r.stdout


def psql(sql):
    out = kubectl("-n", "data", "exec", "-i", "postgres-0", "--", "sh", "-c", 'export PGPASSWORD="$POSTGRES_PASSWORD"; psql -U postgres -d n8n -At -v ON_ERROR_STOP=1 -f -', stdin=sql)
    return out.strip()


def evp_bytes_to_key(passphrase: bytes, salt: bytes, key_len=32, iv_len=16):
    d, prev = b"", b""
    while len(d) < key_len + iv_len:
        prev = hashlib.md5(prev + passphrase + salt).digest()
        d += prev
    return d[:key_len], d[key_len:key_len + iv_len]


def encrypt(plain: str, passphrase: str) -> str:
    salt = os.urandom(8)
    key, iv = evp_bytes_to_key(passphrase.encode(), salt)
    padder = padding.PKCS7(128).padder()
    enc = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
    ct = enc.update(padder.update(plain.encode()) + padder.finalize()) + enc.finalize()
    return base64.b64encode(b"Salted__" + salt + ct).decode()


def decrypt(blob: str, passphrase: str) -> str:
    raw = base64.b64decode(blob)
    key, iv = evp_bytes_to_key(passphrase.encode(), raw[8:16])
    dec = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
    unpad = padding.PKCS7(128).unpadder()
    return (unpad.update(dec.update(raw[16:]) + dec.finalize()) + unpad.finalize()).decode()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--replace", action="store_true")
    ap.add_argument("--owner", default="max.rml@web.de")
    a = ap.parse_args()
    sops = subprocess.run(["sops", "-d", str(REPO / "gitops/secrets/n8n-env.enc.yaml")], capture_output=True, text=True,
                          env={**os.environ, "SOPS_AGE_KEY_FILE": str(Path.home() / ".config/sops/age/keys.txt")})
    m = re.search(r"N8N_ENCRYPTION_KEY:\s*(\S+)", sops.stdout)
    if not m:
        sys.exit("encryption key not found")
    enc_key = m.group(1).strip("\"'")
    existing = psql(f"select id from credentials_entity where name = '{NAME}' and type = '{TYPE}';")
    if existing and not a.replace:
        print(f"keep    credential '{NAME}' ({existing})")
        return
    gw = base64.b64decode(kubectl("-n", "agents", "get", "secret", "herdr-gateway", "-o", "jsonpath={.data.ANTHROPIC_AUTH_TOKEN}")).decode()
    data = json.dumps({"name": "Authorization", "value": f"Bearer {gw}"})
    blob = encrypt(data, enc_key)
    assert decrypt(blob, enc_key) == data  # round trip with our own implementation
    project = psql(f"select p.id from project p join project_relation r on r.\"projectId\" = p.id join \"user\" u on u.id = r.\"userId\" where u.email = '{a.owner}' and p.type = 'personal';")
    if not project:
        sys.exit("personal project of the owner not found")
    cid = existing or "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(16))
    if existing:
        psql(f"update credentials_entity set data = $b${blob}$b$, \"updatedAt\" = now() where id = '{cid}';")
    else:
        psql(f"insert into credentials_entity (id, name, data, type, \"createdAt\", \"updatedAt\") values ('{cid}', '{NAME}', $b${blob}$b$, '{TYPE}', now(), now());\n"
             f"insert into shared_credentials (\"credentialsId\", \"projectId\", role, \"createdAt\", \"updatedAt\") values ('{cid}', '{project}', 'credential:owner', now(), now());")
    print(f"{'replaced' if existing else 'created '} credential '{NAME}' ({cid}) in project {project}")


if __name__ == "__main__":
    main()
