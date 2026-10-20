# Runbook: add or update a website

Sites do not live in this repository (ADR-0037). Each has its own repo that builds a small Caddy image; the platform only
stores the image digest in `catalog/services.yml`. Argo CD turns the entry into a Deployment, Service, Ingress and
network policies in a new pod.

## New site
1. Create the repo from `templates/static-site/` (Dockerfile, Caddyfile, `.github/workflows/image.yml`); put the pages in
   `site/`; make the repo public (the cluster pulls anonymously) and push to `main`. CI prints the image digest.
2. In the platform repo: `scripts/site.sh add <name> <repo>`. It adds the catalog entry with the newest image and regenerates the manifests.
3. `git add -A && git commit && git push` (Argo CD deploys the pod within a few minutes).
4. New host `<name>.maxrommel.de`: `tofu plan` (shows one DNS record and the tunnel route), review, apply the saved plan.

## Update an existing site
Push to the site repo, wait for CI, then `scripts/site.sh bump <name> <repo>`, commit and push.

## Remove a site
Delete its entry in the catalog, regenerate, push. Argo CD does not prune: delete the Deployment, Service, Ingress and
NetworkPolicies of that name in namespace `apps` by hand, then `tofu apply` removes the DNS record.
