#!/usr/bin/env bash
# One GPU-heavy job at a time across all sessions (Blender, TripoSG, windowed Godot,
# screenshot batches). Usage:
#   tools/gpu_lock.sh run <who> -- <command...>   waits for the lock, runs the command, releases it
# The lock is local/gpu.lock (gitignored). A lock older than 45 minutes is treated as stale.
set -u
LOCK="$(cd "$(git -C "$(dirname "$0")" rev-parse --git-common-dir)/.." && pwd)/local/gpu.lock"  # shared by every worktree
mkdir -p "$(dirname "$LOCK")"
[ "${1:-}" = run ] || { echo "usage: $0 run <who> -- <command...>"; exit 2; }
WHO="$2"; shift 3
while true; do
  if [ -f "$LOCK" ] && [ $(( $(date +%s) - $(stat -c %Y "$LOCK") )) -lt 2700 ]; then
    echo "GPU busy ($(cat "$LOCK")), waiting..."; sleep 20
  elif ( set -o noclobber; echo "$WHO $(date +%H:%M)" > "$LOCK" ) 2>/dev/null; then
    break
  else
    rm -f "$LOCK"
  fi
done
trap 'rm -f "$LOCK"' EXIT
"$@"
