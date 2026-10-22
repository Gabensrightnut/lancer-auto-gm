# Releasing a build

How a version of Lancer TTRPG gets from `main` to players. GitHub builds everything: nothing
needs to be installed or downloaded on your own PC to make a release. The workflow is
`.github/workflows/release.yml`; the launcher that installs and updates the game is in
`launcher/`.

What a release contains (the launcher looks for exactly these names):

| File | What it is |
|---|---|
| `LancerTTRPG-windows-<version>.zip` | The game: `LancerTTRPG.exe` and the WebRTC add-on DLL for online play |
| `LancerLauncher.exe` | The launcher. Friends download this once; it installs and updates the game |
| `SHA256SUMS.txt` | Checksums. The launcher refuses a download that doesn't match |

Versions look like `0.1.0` (or `0.1.0-beta.1`). The tag is the version with a `v` in front:
`v0.1.0`. The version is stamped into the game when it's built; online, players must be on the
same version (the game says so and points at the launcher).

## 1. Check locally (no export templates needed)

From the repo root, on `main` with everything merged:

```bash
G=A:/godot/Godot_v4.7.2-stable_win64_console.exe
$G --headless --path . --import
$G --headless --path . -s res://tests/run_tests.gd
```

All tests must pass. Then check that the export picks up every file the game reads at run
time. A pack-only export needs no export templates:

```bash
$G --headless --path . --export-pack "Windows Desktop" C:/Temp/check.pck
```

It should finish with `[ DONE ] savepack`, listing the COMP/CON name lists
(`data/compcon/generators/*.txt`), all `*.json` data, the icons and the WebRTC add-on, and
nothing from `tests/`, `tools/`, `local/` or `assets/screenshots/`.

## 2. Dry run on GitHub (optional, recommended the first time)

On GitHub: **Actions → Release → Run workflow**, keep the version `0.0.0-dryrun`, run it.
It does everything a real release does (downloads Godot and the export templates on GitHub's
machine, fetches the WebRTC add-on, runs every test, exports the game and the launcher, zips,
writes checksums) but publishes nothing. The three files are attached to the run as an
artifact ("lancer-ttrpg-0.0.0-dryrun"). Download it and try the game exe from the zip.

The first run downloads the Godot export templates (about 1.3 GB) on GitHub's runner and
caches them; later runs reuse the cache. None of that touches your PC.

## 3. Tag the release

```bash
git checkout main
git pull
git tag v0.1.0
git push origin v0.1.0
```

Pushing the tag starts the workflow. It takes roughly 15-25 minutes (most of it is the test
run). Watch it under **Actions → Release**. If any test fails, nothing is published: fix it,
delete the tag (`git tag -d v0.1.0` and `git push origin :refs/tags/v0.1.0`) and tag again.

When it's green, the release page (**Releases → Lancer TTRPG 0.1.0**) has the three files and
notes generated from the merged changes.

## 4. Test the launcher

On a Windows PC (ideally one that has never run the game):

1. Download `LancerLauncher.exe` from the release page into an empty folder and run it.
   Windows SmartScreen may warn that the app isn't recognized (it isn't code-signed): choose
   **More info → Run anyway**.
2. The launcher checks GitHub, downloads the zip, checks it against `SHA256SUMS.txt`, unpacks
   it and offers **Play**. Its files live in `%APPDATA%\LancerTTRPG\launcher\`
   (`versions\0.1.0\LancerTTRPG.exe`, `installs.json`), never in the game's saves.
3. Press Play. The main menu's bottom line should say `Version 0.1.0+p1` (the `+p` number is the
   online protocol; both players need the same whole string).
4. Quick game check: Tutorial → briefing → the drill → back at the hub. New campaign → lobby
   → builder (3D mech preview) → mission.
5. Online check with a friend (both through the launcher, same version): host picks Invite
   friends online (lobby or hub Menu), the friend picks Join online and types the room code.
6. Close and reopen the launcher: it should say the game is up to date and start it.

## 5. The next release

Merge, tag `v0.1.1`, push. Players' launchers find the new version on start, download it and
keep the previous one: if the new build is broken, the launcher's **Go back to <version>** button returns
to it.

## Building on your own PC (later)

Exporting locally needs Godot's export templates for 4.7.2 (about 1.3 GB). They aren't
installed yet; don't download them without the user's OK. Once they are (Godot editor:
**Editor → Manage Export Templates → Download and Install**):

```bash
bash addons/fetch_webrtc_native.sh
$G --headless --path . --export-release "Windows Desktop" build/game/LancerTTRPG.exe
$G --headless --path launcher --export-release "Windows Desktop" ../build/launcher/LancerLauncher.exe
```

`build/` is ignored by git.

## If something goes wrong

| Symptom | Likely cause |
|---|---|
| Workflow fails at "Read version from tag" | The tag isn't like `v1.2.3` |
| Workflow fails at "Import and test" | A test failed: the log lists it. Nothing was published |
| Launcher: "no Windows game build" | The release is missing `LancerTTRPG-windows-<version>.zip` (renamed by hand?) |
| Launcher: checksum mismatch | The zip on the release page was replaced after the build; re-run the release |
| Online: "The host is on version X and you're on Y" | One player hasn't updated: reopen the launcher |
| Game has no generated names | The export filter lost `data/compcon/generators/*.txt` (check step 1) |
