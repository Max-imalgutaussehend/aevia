# Runbook: develop Aevia R2 on a second machine (e.g. Omarchy)

No secret is in this file. Secrets travel in one age-encrypted bundle (see step 4), never through chat or git.

## 1. Tools

Arch/Omarchy: `sudo pacman -S --needed git github-cli openssh opentofu kubectl helm sops age kubeconform python python-yaml docker kind jq curl`
(`kubeconform` and `kind` may come from the AUR/`go install`; `colima` is only needed on macOS.)

## 2. Repo

    gh auth login                       # GitHub account Max-imalgutaussehend
    gh repo clone Max-imalgutaussehend/aevia && cd life-server && git checkout r2

Layout and phase status: `README.md`, `docs/migration/R2-PLAN.md`, ADR-0028. Everything on the cluster is applied by
Argo CD from branch `r2`; pushing a manifest change is the deploy.

## 3. Checks that run without any secret

    python3 generator/render_k8s.py --check     # generated manifests match catalog/services.yml
    bash scripts/k8s-validate.sh                # kubeconform, helm template, policy, secret checks
    bash tests/isolation/run.sh | tests/restore/run.sh | tests/smoke/run.sh   # kind-based, need docker

After editing `catalog/services.yml` run `python3 generator/render_k8s.py` and commit the generated files.

## 4. Secrets and local-only files (from the main machine)

On the main machine: `scripts/export-dev-bundle.sh` (passphrase) or `scripts/export-dev-bundle.sh <age public key of this machine>`
(`age-keygen -o ~/.config/sops/age/keys.txt` here first; it prints the public key). Copy `~/aevia-dev-bundle.tar.age` over with scp or a USB stick, then:

    age -d ~/aevia-dev-bundle.tar.age | tar xz -C /tmp/b      # use -i ~/.config/sops/age/keys.txt for the recipient variant
    cp -r /tmp/b/home/.config/. ~/.config/ && chmod -R go-rwx ~/.config/sops ~/.config/aevia
    cp -r /tmp/b/repo/. ./                                    # production.tfvars, backend.hcl, .env (all gitignored)
    shred -u ~/aevia-dev-bundle.tar.age; rm -rf /tmp/b

What the files are: `~/.config/sops/age/keys.txt` (operator key; decrypts `gitops/secrets/*.enc.yaml`) and `aevia-cluster-key.txt`
(the cluster's own key, keep a copy offline); `~/.config/aevia/secrets.env` (Hetzner token, object-storage keys, Cloudflare token, tunnel secret);
`r2-generated.env` (S3 access keys; admin logins for Argo CD, Grafana, Authentik and ntfy live in Bitwarden, folder "Aevia R2"); `production.tfvars`/`backend.hcl` (see the `.example` files next to them).

Use them: `set -a; . ~/.config/aevia/secrets.env; set +a; export AWS_ACCESS_KEY_ID=$TF_VAR_object_storage_access_key AWS_SECRET_ACCESS_KEY=$TF_VAR_object_storage_secret_key`
then `cd infra/tofu/environments/production && tofu init -backend-config=backend.hcl && tofu plan -var-file=production.tfvars`.
Review every plan; apply only a saved plan file. Edit a secret: `sops gitops/secrets/<name>.enc.yaml`.

## 5. Reach the cluster

The node is `aevia-control-01` (public IPv4 2.31.1.35, k3s API 6443 is not exposed). SSH is firewalled to `ssh_allowed_cidrs`:

1. Make a key here: `ssh-keygen -t ed25519`. Give the public key and this machine's public IP to the main machine; it adds the key to
   `/root/.ssh/authorized_keys` on the node and the IP to `ssh_allowed_cidrs` in `production.tfvars` (targeted `tofu apply`).
2. Tunnel: `ssh -f -N -L 16443:127.0.0.1:6443 root@2.31.1.35`
3. Kubeconfig: `ssh root@2.31.1.35 cat /etc/rancher/k3s/k3s.yaml | sed 's|https://127.0.0.1:6443|https://127.0.0.1:16443|' > ~/.kube/aevia.yaml`
   then `export KUBECONFIG=~/.kube/aevia.yaml`. The API cert contains the SANs 127.0.0.1 and 10.42.1.1.

Argo CD UI/CLI: `kubectl -n argocd port-forward svc/argocd-server 8080:443`; admin password: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`.

## 6. Other

Backups: Postgres dumps nightly into the Hetzner bucket `aevia-backups/postgres` (rclone crypt, config in secret `backup-offsite`); R1 archive in `aevia-backups/r1-final/` (age-encrypted to the cluster key).
Runbooks: `r2-bring-up.md`, `restore.md`, `ai-gateway.md`. Claude Code works the same here: open the repo and follow `docs/migration/R2-PLAN.md`.
