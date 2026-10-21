# Herdr workspace image (agents zone). Herdr is a terminal multiplexer for coding agents; sessions live in a background
# server inside the pod, so `kubectl exec -it <pod> -- herdr` reattaches after a disconnect. Claude Code is baked in (pinned)
# for the handover runner (`aevia-handover`); python3 + PyYAML let the agent run the repository's own checks (generator, validation); further agent CLIs are installed per user into the persistent home volume.
FROM node:22-bookworm-slim
ARG HERDR_VERSION=0.9.5
ARG HERDR_SHA256=14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d
RUN apt-get update \
 && apt-get install -y --no-install-recommends git openssh-client ca-certificates curl ripgrep less procps tini jq python3 python3-yaml \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL -o /usr/local/bin/herdr "https://github.com/herdrdev/herdr/releases/download/v${HERDR_VERSION}/herdr-linux-x86_64" \
 && echo "${HERDR_SHA256}  /usr/local/bin/herdr" | sha256sum -c - \
 && chmod 0755 /usr/local/bin/herdr \
 && npm install -g @anthropic-ai/claude-code@2.1.304 && npm cache clean --force \
 && useradd --uid 10001 --create-home --home-dir /home/agent --shell /bin/bash agent
ENV HOME=/home/agent NPM_CONFIG_PREFIX=/home/agent/.npm-global PATH=/home/agent/.npm-global/bin:/usr/local/bin:/usr/bin:/bin
COPY aevia-handover aevia-handover-api git-credential-aevia /usr/local/bin/
RUN chmod 0755 /usr/local/bin/aevia-handover /usr/local/bin/aevia-handover-api /usr/local/bin/git-credential-aevia \
 && git config --system credential.helper /usr/local/bin/git-credential-aevia \
 && git config --system --add safe.directory '*'
USER 10001:10001
WORKDIR /workspace
ENTRYPOINT ["/usr/bin/tini", "--"]
# the handover API (port 8099, needs HANDOVER_API_TOKEN) runs next to the idle shell and is restarted if it dies; without a token it stays off
CMD ["sh", "-c", "if [ -n \"$HANDOVER_API_TOKEN\" ]; then (while true; do /usr/local/bin/aevia-handover-api; sleep 3; done) & fi; exec sleep infinity"]
