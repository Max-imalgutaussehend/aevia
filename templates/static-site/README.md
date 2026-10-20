# SITE_NAME

Static site served by Caddy. Put the pages in `site/` (any generator, committed output), push to `main`: CI builds
`ghcr.io/max-imalgutaussehend/SITE_NAME` and prints the digest in the job summary. The Aevia platform deploys it with
`scripts/new-site.sh` (see the platform repo, docs/runbooks/add-a-site.md).
