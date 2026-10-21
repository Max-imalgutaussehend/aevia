# 0039 Object storage on Cloudflare R2 (free tier)

Date: 2026-10-21. Status: accepted. Supersedes the object-storage part of ADR 0036.

## Context
Hetzner Object Storage has a base fee of about 5 EUR per month even for a few hundred MB. All we store is encrypted nightly backups,
the OpenTofu state and an archive of the retired R1 server. That is a fixed cost for no benefit.

## Decision
Use Cloudflare R2 (Standard class) with three buckets: `aevia-backups`, `aevia-archive`, `aevia-tofu-state`. R2 is free up to
10 GB-month of storage, 1 million Class A and 10 million Class B operations per month, and has no egress fees.
The Hetzner buckets are deleted. Backups stay client-side encrypted (rclone crypt), so only ciphertext is stored.

The free tier must not be exceeded. Layers, from soft to hard:
1. Retention: all three backup jobs delete objects older than 14 days.
2. Few operations: the Forgejo, Kuma and ntfy volumes are streamed into one `.tgz` per volume (a handful of PUTs per night, not one per git object).
3. Guard in every backup job: it sums the size of `aevia-backups` and `aevia-archive` and aborts above 7 GiB (the Job fails visibly).
4. Budget Alert in the Cloudflare dashboard (R2 overview, Add Budget Alert) so any billable usage is mailed.
5. The S3 token only has Object Read & Write on these three buckets.

## Consequences
- Total running cost drops to the Hetzner server, IPv4 and nothing for storage.
- Normal use is far from the limits (about 0.5 GB stored, a few hundred operations per night).
- If the guard trips, either shorten retention or move the archive offline; do not raise the limit.
