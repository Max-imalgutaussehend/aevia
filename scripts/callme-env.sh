#!/usr/bin/env bash
# Writes gitops/secrets/callme-env.enc.yaml (SOPS) from the Twilio values you type in. Nothing is echoed or printed; the values never go into chat.
#   scripts/callme-env.sh
set -euo pipefail
cd "$(dirname "$0")/.."
out=gitops/secrets/callme-env.enc.yaml
[[ -e $out ]] && { echo "$out exists; delete it first to replace it"; exit 1; }
read -r  -p "Twilio Account SID (AC...): " sid
read -r -s -p "Twilio Auth Token (hidden): " tok; echo
read -r  -p "Twilio phone number (+1...): " from
read -r  -p "Your mobile number, verified in Twilio (+49...): " to
[[ $sid =~ ^AC[0-9a-fA-F]{32}$ ]] || { echo "that is not an Account SID"; exit 1; }
[[ $from =~ ^\+[1-9][0-9]{6,14}$ && $to =~ ^\+[1-9][0-9]{6,14}$ ]] || { echo "numbers must look like +491701234567"; exit 1; }
umask 077
python3 - "$sid" "$tok" "$from" "$to" > "$out" <<'PY'
import sys, json
sid, tok, frm, to = sys.argv[1:5]
print(json.dumps({"apiVersion": "v1", "kind": "Secret", "metadata": {"name": "callme-env", "namespace": "apps"}, "type": "Opaque",
  "stringData": {"CALLME_PHONE_ACCOUNT_SID": sid, "CALLME_PHONE_AUTH_TOKEN": tok, "CALLME_PHONE_NUMBER": frm, "CALLME_USER_PHONE_NUMBER": to}}))
PY
sops -e -i --input-type json --output-type yaml "$out" 2>/dev/null || { rm -f "$out"; echo "sops failed"; exit 1; }
grep -q "callme-env.enc.yaml" gitops/secrets/secret-generator.yaml || printf "  - callme-env.enc.yaml\n" >> gitops/secrets/secret-generator.yaml
echo "wrote $out (encrypted) and listed it in gitops/secrets/secret-generator.yaml"
