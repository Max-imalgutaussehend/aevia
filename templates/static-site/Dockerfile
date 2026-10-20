# Static site image: Caddy serves ./site on :8080 as a non-root user. Built by CI, deployed by the Aevia platform
# (catalog entry + image digest in the platform repo); nothing here talks to the cluster.
FROM caddy:2.10.2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY site /srv/site
USER 65532:65532
EXPOSE 8080
