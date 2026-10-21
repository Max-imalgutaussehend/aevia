#!/usr/bin/env bash
# Adds this machine's current public IP to the SSH/API allow-list of the Hetzner firewall (infra/tofu), then reopens the cluster tunnel.
# Needs infra/tofu/environments/production/production.tfvars and ~/.config/aevia/secrets.env (see docs/runbooks/dev-machine-setup.md).
set -euo pipefail
cd "$(dirname "$0")/../infra/tofu/environments/production"
ip=$(curl -fsS --max-time 10 https://api.ipify.org)
grep -q "\"$ip/32\"" production.tfvars || sed -i.bak -E "s|^(ssh_allowed_cidrs *= *\[[^]]*)\]|\1, \"$ip/32\"]|" production.tfvars && rm -f production.tfvars.bak
set -a; . ~/.config/aevia/secrets.env; set +a
export AWS_ACCESS_KEY_ID=$TF_VAR_object_storage_access_key AWS_SECRET_ACCESS_KEY=$TF_VAR_object_storage_secret_key
export TF_VAR_authentik_cloudflare_secret=${TF_VAR_authentik_cloudflare_secret:-$(SOPS_AGE_KEY_FILE=${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt} sops -d ../../../../gitops/secrets/authentik-env.enc.yaml | sed -n 's/.*OIDC_CLOUDFLARE_SECRET: //p')}
plan=$(mktemp)
tofu plan -out="$plan" -var-file=production.tfvars -target=module.hetzner.hcloud_firewall.node -no-color | grep -E 'Plan:|No changes'
tofu apply -no-color "$plan" | grep -E 'Apply complete|Error' || true
rm -f "$plan"
echo "allowed $ip. Tunnel: ssh -f -N -L 16443:127.0.0.1:6443 root@2.31.1.35   then: export KUBECONFIG=~/.kube/aevia.yaml"
