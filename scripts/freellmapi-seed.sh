#!/usr/bin/env bash
# Builds gitops/secrets/freellmapi-seed.enc.yaml from a local copy of the FreeLLMAPI data directory,
# encrypted with sops. Run it on the machine that has the data; nothing leaves it unencrypted.
#
#   docker compose -f ~/freellmapi/docker-compose.yml stop freellmapi     # clean SQLite state
#   mkdir -p /tmp/flm && docker run --rm -v freellmapi_freellmapi-data:/d -v /tmp/flm:/o alpine sh -c 'cp -a /d/. /o/'
#   ./scripts/freellmapi-seed.sh /tmp/flm
#   shred -u /tmp/flm/* 2>/dev/null || rm -rf /tmp/flm
set -euo pipefail
cd "$(dirname "$0")/.."
src=${1:?usage: $0 <dir with the copied data files>}
out=gitops/secrets/freellmapi-seed.enc.yaml
size=$(du -sk "$src" | cut -f1)
(( size < 900 )) || { echo "data is ${size}KiB; Secrets are limited to 1MiB. Use the kubectl cp path in docs/runbooks/ai-gateway.md"; exit 1; }
args=(); for f in "$src"/*; do [[ -f $f ]] && args+=(--from-file="$f"); done
(( ${#args[@]} )) || { echo "no files in $src"; exit 1; }
kubectl create secret generic freellmapi-seed -n platform "${args[@]}" --dry-run=client -o yaml \
  > "$out"
sops -e -i "$out"
echo "wrote $out (encrypted). Commit it; never commit the plaintext copy."
