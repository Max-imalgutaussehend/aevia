# Runbook: Gmail and Calendar for Hermes (ADR 0047)

Account: `maxrommel05@gmail.com`, Google Cloud project `aevia-hermes` (OAuth web client `hermes-google-mcp`, Gmail API and Calendar API enabled, consent screen *External*, status *Testing*, you are the test user).
Client id and secret are in the SOPS secret `google-mcp-env` (`gitops/secrets/google-mcp-env.enc.yaml`). The service `google-mcp` is `hold`ed in the catalog until its image exists.

## Switch on (once)
1. Push the repo: `! cd ~/Documents/coding-projects/google-mcp && gh repo create Max-imalgutaussehend/google-mcp --public --source . --push` and wait for the `image` workflow.
2. Pin the digest in `catalog/services.yml` (`image: ghcr.io/max-imalgutaussehend/google-mcp@sha256:...`), delete the `hold:` line, `python3 generator/render_k8s.py`, commit, push. Argo needs about 5 minutes.
3. Consent through a tunnel (the OAuth redirect is `http://localhost:8000/oauth2callback`):
   `scripts/allow-my-ip.sh`, wait 2 minutes, `ssh-add --apple-use-keychain ~/.ssh/life-server`, `ssh -f -N -L 16443:127.0.0.1:6443 root@2.31.1.35`,
   then `KUBECONFIG=~/.kube/aevia.yaml kubectl -n apps port-forward deploy/google-mcp 8000:8000`.
4. Start the login: call the MCP tool `start_google_auth` with `user_google_email=maxrommel05@gmail.com` (MCP over `http://localhost:8000/mcp`), open the link it returns, choose the account, press through
   "Google hasn't verified this app" (Advanced, continue), allow Gmail and Calendar. The redirect lands on the port-forward and the token is stored on the volume.
5. `kubectl -n agents rollout restart sts/hermes` so Hermes connects to the `google` MCP server (its config is merged by the init step, skill `mail-calendar` is copied).

## Renew every 7 days
The consent screen is in *Testing*, so Google expires the refresh token after 7 days. Hermes then gets an authorization link instead of data and sends you one ntfy. Repeat steps 3 and 4.
To end the weekly renewal: publish the app on the Audience page of the Google Auth Platform. Google asks for a homepage, privacy and terms links first (not done: it needs public pages on a domain you own).

## Revoke
https://myaccount.google.com/permissions (remove "Aevia Hermes"), or delete the secret and the volume, or `hold:` the service again. Mail and calendar data is never stored by `google-mcp`, only the token.

## Safety model
The MCP endpoint has no login of its own: no Ingress, no host, a NetworkPolicy lets only the Hermes pod in. Mails are untrusted text that Hermes reads while it also owns tools such as the server handover;
the skill `mail-calendar` forbids acting on instructions inside mails and requires Max's yes before sending, deleting or changing anything.
