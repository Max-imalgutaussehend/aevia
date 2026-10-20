#!/usr/bin/env bash
# Static sites live in their own repositories (template: templates/static-site). The platform only knows the image digest.
#   scripts/site.sh add  <name> <repo>    new catalog entry (host <name>.maxrommel.de) with the newest image of <repo>
#   scripts/site.sh bump <name> <repo>    point an existing entry at the newest image of <repo>
# Then: python3 generator/render_k8s.py (done here), commit, push. A new host also needs `tofu apply` (DNS and tunnel).
set -euo pipefail
cd "$(dirname "$0")/.."
OWNER=${SITE_OWNER:-Max-imalgutaussehend}
cmd=${1:?usage: $0 add|bump <name> <repo>}; name=${2:?name}; repo=${3:?repo}

sha=$(gh api "repos/$OWNER/$repo/commits/main" --jq .sha)
tok=$(curl -s "https://ghcr.io/token?scope=repository:${OWNER,,}/$repo:pull" | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
digest=$(curl -sI -H "Authorization: Bearer $tok" \
  -H "Accept: application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json" \
  "https://ghcr.io/v2/${OWNER,,}/$repo/manifests/$sha" | tr -d '\r' | awk 'tolower($1)=="docker-content-digest:"{print $2}')
[[ $digest == sha256:* ]] || { echo "no image for $repo at $sha yet (CI still running, or the package is private)"; exit 1; }
image="ghcr.io/${OWNER,,}/$repo@$digest"

python3 - "$cmd" "$name" "$image" <<'PY'
import re, sys
cmd, name, image = sys.argv[1:4]
p = "catalog/services.yml"
t = open(p).read()
if cmd == "add":
    if re.search(rf"^  - name: {re.escape(name)}$", t, re.M):
        sys.exit(f"{name} already exists; use bump")
    entry = f"""  - name: {name}
    image: {image}
    type: application
    description: "Static site (own repository)"
    port: 8080
    exposure: public
    needs: []
    persistence: none
    uid: 65532
    add_caps: [NET_BIND_SERVICE] # the caddy binary carries cap_net_bind_service
    scratch_paths: [/config, /data]

"""
    anchor = t.index("  - name: longevity")
    t = t[:anchor] + entry + t[anchor:]
else:
    m = re.search(rf"(^  - name: {re.escape(name)}\n    image: )\S+", t, re.M)
    if not m:
        sys.exit(f"{name} not found; use add")
    t = t[:m.start()] + m.group(1) + image + t[m.end():]
open(p, "w").write(t)
print(f"{cmd}: {name} -> {image}")
PY
python3 generator/render_k8s.py
