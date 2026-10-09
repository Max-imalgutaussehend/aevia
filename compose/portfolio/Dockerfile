# Static portfolio image for R2 (phase 21). Same Caddy and Caddyfile as R1; the site is baked in
# instead of bind-mounted, so the image is the deployable unit and can be pinned by digest.
FROM caddy:2.10.2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY site /srv/site
USER 65532:65532
EXPOSE 8080
