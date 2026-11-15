# Runbook: phone calls and dashboard for Hermes (ADR 0046)

Both services sit in `catalog/services.yml` with a `hold:` line. Nothing is deployed until you finish this list. Code: `~/Documents/coding-projects/callme` and `~/Documents/coding-projects/dashboard`
(local git repos, nothing pushed).

## 1. Twilio trial (callme), no payment
Free start, nothing to pay: do not add a card and do not upgrade, then calls just stop when the trial credit is used up (check the current trial terms yourself).
1. Create a Twilio account, verify your mobile number (it is the only number the trial can call).
2. Get the trial phone number (Console, Phone Numbers). Voice > Geo permissions: allow Germany if it is not on.
3. Note: Account SID (`AC...`), Auth Token, the Twilio number and your number in E.164 (`+49...`). No OpenAI, no Telnyx.
Trial behaviour: each call starts with a trial announcement and you press a key to continue; this is the price of free.
Hermes checks the credit with the tool `call_budget` before every call and warns below 5 USD; below 2 USD the server refuses calls.

## 2. Repos and images
1. Create public GitHub repos `callme` and `dashboard` under Max-imalgutaussehend (ADR 0037: public so the cluster pulls without credentials; neither repo contains secrets) and push the local repos.
2. Wait for the `image` workflow; copy each digest from the job summary.
3. In `catalog/services.yml` add `image: ghcr.io/max-imalgutaussehend/<repo>@sha256:...` and delete the `hold:` line of the entry, then `python3 generator/render_k8s.py`.

## 3. Secrets (SOPS)
- Already generated (random tokens, encrypted, never printed): `callme-mcp` + `hermes-callme`, `dashboard-api` + `hermes-dashboard` (`python3 scripts/gen-k8s-secrets.py call-dashboard`).
- Yours: `scripts/callme-env.sh` asks for the Twilio values in your terminal (token hidden) and writes `gitops/secrets/callme-env.enc.yaml`.

## 4. Tofu (you run the reviewed plan)
Creates DNS and tunnel routes for `callme` and `dashboard`, and the Access app for the dashboard with a 30-day session. The dashboard is live from the start but its browser path stays closed (fail closed) until the AUD tag is set. Then copy the **Application Audience (AUD) tag** of the dashboard Access app
into `DASHBOARD_CF_AUD` in the catalog (replace `TODO-after-first-tofu-apply`), regenerate, push. Until then the browser path of the dashboard stays closed (fail closed).
`callme.maxrommel.de` is deliberately not behind Access (the phone provider cannot log in).

## 5. Hermes
`kubectl -n agents rollout restart sts/hermes`: the init step adds the `callme` MCP server to `/vol/h/config.yaml` and copies the skills `dashboard` and `call-escalation`.
Then tell Hermes (Signal or Jarvis), for example: "Lege einen Cron-Job an, täglich 06:30 und 18:00: Dashboard aktualisieren nach dem Skill dashboard (Notizen der letzten zwei Tage ohne Privat,
offene Signal-Antworten; nur Fakten eintragen; ohne Änderungen nichts schreiben). Trag den Job in deine Notiz unter Aevia/Hermes ein." Keep it cheap: each run costs subscription tokens (ADR 0045).

## 6. Test
- `kubectl -n apps get pods`, then the dashboard through Hermes: "Schreib ein Testwidget ins Dashboard".
- Ask Hermes for `call_budget` (credit, calls left). Then: "Ruf mich an und sag Hallo" (press a key after the trial announcement).
- Budget: a fourth call within 24 hours must be refused.

## 7. Devices
Open `https://dashboard.maxrommel.de` on iPhone, Mac and Framework once and sign in; the Access session then lasts 30 days. Authentik has its own session lifetime: if the login still comes back
sooner, raise it there (not verified). iPhone: Share, Add to Home Screen (opens like an app; it has its own cookie jar, so sign in once there too).
