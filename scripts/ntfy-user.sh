#!/usr/bin/env bash
# Creates (or updates) the write-only ntfy user `aevia-mcp` for topic `aevia` with the password from the SOPS secret
# gitops/secrets/aevia-mcp-ntfy.enc.yaml. The password never appears on the command line of this machine.
set -euo pipefail
cd "$(dirname "$0")/.."
export SOPS_AGE_KEY_FILE=${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}
pw=$(sops -d gitops/secrets/aevia-mcp-ntfy.enc.yaml | python3 -c 'import sys,re;print(re.search(r"NTFY_PASSWORD: (\S+)",sys.stdin.read()).group(1))')
kubectl -n platform exec -i deploy/ntfy -- sh -c 'read -r NTFY_PASSWORD; export NTFY_PASSWORD
  ntfy user add --role=user aevia-mcp 2>/dev/null || ntfy user change-pass aevia-mcp
  ntfy access aevia-mcp aevia write-only' <<<"$pw"
echo "ntfy user aevia-mcp: write-only on topic aevia"
