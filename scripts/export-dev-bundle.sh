#!/usr/bin/env bash
# Packs the local-only files a second dev machine needs (keys, tokens, gitignored config) into ONE
# age-encrypted archive. Nothing is printed. Transfer the result with scp/USB, never via chat or git.
#
#   scripts/export-dev-bundle.sh                 # asks for a passphrase (run it in your own terminal)
#   scripts/export-dev-bundle.sh age1...         # encrypts to the other machine's age public key
#
# Restore on the other machine: docs/runbooks/dev-machine-setup.md
set -euo pipefail
cd "$(dirname "$0")/.."
out=${OUT:-$HOME/aevia-dev-bundle.tar.age}
stage=$(mktemp -d); trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/home/.config/sops/age" "$stage/home/.config/aevia" "$stage/repo/infra/tofu/environments/production"
cp ~/.config/sops/age/keys.txt ~/.config/sops/age/aevia-cluster-key.txt "$stage/home/.config/sops/age/"
cp ~/.config/aevia/secrets.env ~/.config/aevia/r2-generated.env "$stage/home/.config/aevia/"
cp infra/tofu/environments/production/{production.tfvars,backend.hcl} "$stage/repo/infra/tofu/environments/production/"
[ -f .env ] && cp .env "$stage/repo/.env"
umask 077
if [ $# -ge 1 ]; then recipient=(-r "$1"); else recipient=(-p); fi
tar czf - -C "$stage" . | age "${recipient[@]}" -o "$out"
echo "wrote $out ($(du -h "$out" | cut -f1)); transfer it, then delete both copies"
