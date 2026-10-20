#!/usr/bin/env bash
# Installs the handover skills for Claude Code on this machine (user level): ~/.claude/skills/{handover,handover-back}
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
for s in handover handover-back; do
  mkdir -p "$HOME/.claude/skills/$s"
  cp "$here/$s/SKILL.md" "$HOME/.claude/skills/$s/SKILL.md"
  echo "installed $s"
done
