#!/usr/bin/env bash
# Creates (or updates) a write-only ntfy user for topic `aevia` with the password from a SOPS secret in gitops/secrets.
#   scripts/ntfy-user.sh aevia-mcp aevia-mcp-ntfy     # the Aevia MCP server
#   scripts/ntfy-user.sh herdr herdr-ntfy             # the Herdr handover runner
# The password never appears on the command line of this machine.
set -euo pipefail
cd "$(dirname "$0")/.."
user=${1:?ntfy user}; secret=${2:?secret name (file gitops/secrets/<name>.enc.yaml)}
export SOPS_AGE_KEY_FILE=${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}
pw=$(sops -d "gitops/secrets/$secret.enc.yaml" | python3 -c 'import sys,re;print(re.search(r"NTFY_PASSWORD: (\S+)",sys.stdin.read()).group(1))')
kubectl -n platform exec -i deploy/ntfy -- sh -c "read -r NTFY_PASSWORD; export NTFY_PASSWORD
  ntfy user add --role=user $user 2>/dev/null || ntfy user change-pass $user
  ntfy access $user aevia write-only" <<<"$pw"
echo "ntfy user $user: write-only on topic aevia"
