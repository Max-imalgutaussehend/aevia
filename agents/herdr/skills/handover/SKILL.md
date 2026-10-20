---
name: handover
description: Hand the current task over to the Aevia server agent (Herdr on the Hetzner cluster) so it keeps working while the laptop is closed. Use when the user says "handover", "übergib das an den Server", "mach auf dem Server weiter" or wants a long task to continue remotely. Writes a self-contained HANDOVER.md, pushes a handover branch and starts the agent. Reverse with the handover-back skill.
---

# Handover: laptop to the Aevia server agent

The server agent (Claude Code in the Herdr pod on the cluster) continues the task from a git branch. It has **no chat history**, no logins and no
laptop secrets. Everything it needs must be in the repository, so the main job here is writing a handover note that stands on its own.

## 0. Preconditions (check, do not assume)
- The current directory is a git repository with a remote `origin` that the server can read (GitHub or git.maxrommel.de). If it has no remote, stop and say so.
- `kubectl` reaches the cluster (`KUBECONFIG=~/.kube/aevia.yaml`, tunnel `ssh -f -N -L 16443:127.0.0.1:6443 root@2.31.1.35`); `kubectl -n agents get pod herdr-0` shows it Running. If not, tell the user what is missing.
- The server can read the remote: `kubectl -n agents exec herdr-0 -- git ls-remote <origin-url> HEAD`. A private repo needs a token in the secret `herdr-git` (see docs/runbooks/handover.md). If this fails, stop and say so.

## 1. Ask once, then act
Confirm with the user in one message: the task in one sentence, the slug (lowercase, dashes, for example `fix-login-flow`), and that you will push a branch `handover/<slug>` to `origin` and start the server agent. Pushing and starting are outward-facing: do not proceed without a yes.

## 2. Prepare the branch
1. `git status`; show the user what is uncommitted. Never commit secrets (`.env`, keys, tokens, credentials files): if any appear, leave them out and add them to the "Needs the laptop" list.
2. `git switch -c handover/<slug>` from the current commit, commit the work in progress (`wip: handover <slug>`).

## 3. Write `.handover/<slug>/HANDOVER.md`
Self-contained, concrete, in the language of the project. Use exactly these sections:
```
# Handover: <title>
slug: <slug> · from: laptop · created: <UTC date>
## Goal
what "finished" looks like, in two or three sentences
## Context
what the project is, what already exists, decisions already made and why, what was tried and failed
## State
branch and commit, files touched, what works, what is broken (error messages verbatim)
## Next steps
ordered, each one small enough to do and check
## Done when
acceptance checks as commands (tests, build, lint) with the expected result
## Constraints
things not to touch, style rules, security rules, paths that are off limits
## Needs the laptop
what the agent cannot do and must leave for the user: logins, secrets, hardware, interactive or visual checks
```
Rules: no secrets, no vague phrases like "continue as discussed", include the exact commands for tests and builds. Show the note to the user before committing.

## 4. Push and start
```sh
git add -A && git commit -m "handover: <slug>" && git push -u origin handover/<slug>
URL=$(git remote get-url origin)
kubectl -n agents exec herdr-0 -- aevia-handover start "$URL" handover/<slug> <slug>
```

## 5. Tell the user
- The agent works on the branch `handover/<slug>`; it pushes to that branch only and sends a push notification (ntfy) when finished.
- Watch: `kubectl -n agents exec herdr-0 -- aevia-handover status <slug>` and `... logs <slug> -f`; stop with `... stop <slug>`.
- When it is done, or the user is back: run the **handover-back** skill.
- Keep working on the laptop only on a different branch, otherwise the two histories collide.
