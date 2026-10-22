# Lancer TTRPG

Fan-made 3D LANCER tactics game in Godot 4.7 (typed GDScript). Read [DESIGN.md](DESIGN.md) for
what the game must do and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how code is split.

## Commands

Godot is at `A:/godot/Godot_v4.7.2-stable_win64_console.exe` (not on PATH). Blender 5.2.2 is at
`A:/blender-5.2.2-windows-x64/blender.exe` (mech models are built by bpy scripts in tools/blender/).

```bash
G=A:/godot/Godot_v4.7.2-stable_win64_console.exe
$G --headless --path . --import                                      # after adding class_name scripts
$G --headless --path . -s res://tests/run_tests.gd                   # all tests, exit 1 on failure
LANCER_SLOW_TESTS=1 $G --headless --path . -s res://tests/run_tests.gd -- fairness   # full 50-seed map fairness (slow)
$G --path . -s res://tools/screenshot.gd -- res://scenes/main.tscn out.png   # check visuals
```

Before every commit run only your area's tests (`-- <area>` filter); the main session runs the full
suite on merge. The user's PC is shared: launch Godot/Blender/Python at below-normal priority
(`cmd.exe //c start "" //belownormal //b //wait <exe> <args>`), no benchmarks unless asked, and keep
screenshots and GPU-heavy work to a minimum. Only ONE GPU-heavy job may run at a time across
all sessions (Blender, TripoSG, windowed Godot runs, screenshot batches): wrap it in
`tools/gpu_lock.sh run <session-name> -- <command>`, which waits for the lock. Everything else
stays small (code, data, headless filtered tests).
Keep files small: textures as JPG/WebP (PNG only when alpha is needed), at most 2048 px and
1024 px for most; models with only the detail they need; screenshots as JPG and kept out of the
repo unless a doc needs them (`local/screenshots/`). Audio is exempt.

## Rules that don't bend

- **Book rules only.** The game follows the LANCER core book exactly. No house rules unless the
  user asks. Rule text available offline: `data/lancer-data/glossary.json`, `statuses.json`,
  `actions.json` (use `ContentDB.rule_text()`). Unconfirmed assumptions go in
  `docs/RULES_TODO.md` and the code is marked `PROVISIONAL`.
- **Everything goes through `RulesEngine`.** Players, the procedural GM and network clients all
  submit actions; nothing else changes `GameState`. Illegal actions are refused with a reason
  and a `rule_ref`. Unclear rules become grey-area rulings, never silent guesses.
- **Grid-agnostic.** Only `src/core/grid/` knows hex vs square. Use `GridLayout` everywhere else.
- **Secrets stay on the host.** Clients only ever get `ViewFilter.view_for()` output.
- **All randomness through `state.dice`.**
- **Nothing taken from other games.** Models, art, animation and code are made here. One approved
  exception (user decision): MakeHuman/MPFB2 open-source CC0 base meshes for human bodies/faces,
  with every skin/hair license checked and credited. Mechs are
  modeled to look as close as possible to Massif's official frame art (user's decision), using
  the art in frames.json `image_url` as reference only; never put official images or
  Lancer Tactics files in the game or repo. Lancer
  Tactics is the reference for look, UI and how systems are presented (public trailers,
  screenshots, devlogs only). If Lancer Tactics handles a rule differently from the book, follow
  the book and add a row to DESIGN.md's "Rule differences" table for the user to decide.
- **Never commit rulebook text or PDFs** (repo is public). Put them in `/local/` (gitignored).
- Official icons: `assets/icons/lancer/` (from COMP/CON, GPL-3.0). Use them for every damage
  type, range/area, action type, status and manufacturer. COMP/CON name lists:
  `data/compcon/generators/`. Never edit either; COMP/CON's fonts are NOT free, don't use them.
- `data/lancer-data/` is Massif's data: never edit it. Our own data goes in `data/game/`.
- **Canon only.** Lore and setting systems must be canon or consistent with the core book (cite
  "Core p.N"); log each in docs/CANON.md. Anything not canon goes to DESIGN.md "Parked: your own
  story additions", never into the game unless the user turns it on.
- Don't read or use anything from other projects on this machine (e.g. MechFortress).

## The user

New to LANCER and wants to learn it by playing, so in-game text explains rules plainly. Explain
choices to them in plain language, not engine jargon.

## Git

Repo: https://github.com/Gabensrightnut/lancer-ttrpg (public, GPL-3.0-or-later).
End commit messages with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
