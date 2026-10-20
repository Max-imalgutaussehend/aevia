# ADR-0037: Websites live in their own repositories

Status: accepted (2026-10-20)

## Context
The portfolio files sat in this repository (`compose/portfolio`), so every text change was a platform commit, and the
site content was mixed with infrastructure. Adding a second site would have meant copying the pattern.

## Decision
- One repository per site (`site-maxrommel`, `site-aevia`), built from `templates/static-site`: Caddy image, pages in `site/`,
  CI publishes `ghcr.io/max-imalgutaussehend/<repo>` and prints the digest.
- The platform repo holds only a catalog entry with the pinned digest. Manifests, network policies and the hostname
  (DNS and tunnel route via tofu) are generated from it, so a new site is one command (`scripts/site.sh add`) plus a push.
- Repos are public so the cluster pulls without credentials; Argo CD never deploys from the site repos directly.

## Consequences
- Site edits and platform changes have separate histories. The digest bump is the deploy and the rollback point.
- No image updater is installed (memory on the single node); bumping is a script run.
