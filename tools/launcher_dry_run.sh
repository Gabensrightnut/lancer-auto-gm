#!/usr/bin/env bash
# End-to-end dry run of the launcher's update logic against a local fake release (no GitHub
# release, no tag). Run it through the GPU lock:
#   A:/lancer/tools/gpu_lock.sh run <who> -- bash tools/launcher_dry_run.sh
# Uses build/game/* as the game (export it first, docs/RELEASE.md) and re-exports the launcher.
# The launcher runs headless with LANCER_LAUNCHER_DRY_RUN set: it prints what it did and quits
# instead of starting the game. Checks: first install, an update that keeps the old version for
# rollback, a tampered download refused, and "already up to date".
set -u
G=${G:-A:/godot/Godot_v4.7.2-stable_win64_console.exe}
ROOT="$(pwd)"
WORK="$ROOT/build/dryrun"
rm -rf "$WORK"; mkdir -p "$WORK/rel" "$WORK/root"
[ -f "$ROOT/build/game/LancerTTRPG.exe" ] || { echo "export the game into build/game first"; exit 2; }
"$G" --headless --path launcher --export-release "Windows Desktop" "$ROOT/build/launcher/LancerLauncher.exe" > "$WORK/export.txt" 2>&1 || { echo "launcher export failed"; tail -5 "$WORK/export.txt"; exit 1; }
PORT=8765
release() {  # release <version> [tamper]
  python -I - "$ROOT/build/game" "$WORK/rel" "$1" "${2:-}" "$PORT" <<'PY'
import sys, zipfile, hashlib, json, os
game, rel, ver, tamper, port = sys.argv[1:6]
name = "LancerTTRPG-windows-%s.zip" % ver
with zipfile.ZipFile(os.path.join(rel, name), "w", zipfile.ZIP_DEFLATED) as z:
    for f in os.listdir(game):
        z.write(os.path.join(game, f), f)
h = hashlib.sha256(open(os.path.join(rel, name), "rb").read()).hexdigest()
if tamper:
    h = "0" * 64
open(os.path.join(rel, "SHA256SUMS.txt"), "w").write("%s  %s\n" % (h, name))
base = "http://127.0.0.1:%s/" % port
json.dump({"tag_name": "v" + ver, "assets": [{"name": n, "browser_download_url": base + n} for n in [name, "SHA256SUMS.txt", "LancerLauncher.exe"]]},
          open(os.path.join(rel, "latest.json"), "w"))
PY
}
run() {  # run <label>
  local out
  out=$(LANCER_LAUNCHER_DRY_RUN=1 LANCER_RELEASE_URL="http://127.0.0.1:$PORT/latest.json" LANCER_LAUNCHER_ROOT="$WORK/root" \
    timeout 300 "$ROOT/build/launcher/LancerLauncher.exe" --headless 2>&1 | grep "LAUNCHER:" | tail -1)
  echo "$1: ${out:-no answer from the launcher}"
}
python -I -m http.server $PORT --bind 127.0.0.1 --directory "$WORK/rel" > "$WORK/server.txt" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
sleep 2
release 0.1.0-test;           run "first install (expect installed=0.1.0-test)"
release 0.1.1-test;           run "update (expect installed=0.1.1-test previous=0.1.0-test)"
release 0.1.2-test tamper;    run "tampered checksum (expect refused, still 0.1.1-test)"
release 0.1.1-test;           run "same version (expect up to date)"
