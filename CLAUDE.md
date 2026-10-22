# Lancer Auto-GM

Fan-made 3D LANCER tactics game in Godot 4.7 (typed GDScript). Read [DESIGN.md](DESIGN.md) for
what the game must do and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how code is split.

## Commands

Godot is at `A:/godot/Godot_v4.7.2-stable_win64_console.exe` (not on PATH).

```bash
G=A:/godot/Godot_v4.7.2-stable_win64_console.exe
$G --headless --path . --import                                      # after adding class_name scripts
$G --headless --path . -s res://tests/run_tests.gd                   # all tests, exit 1 on failure
$G --path . -s res://tools/screenshot.gd -- res://scenes/main.tscn out.png   # check visuals
```

Run the tests before every commit. For visual work, take a screenshot and look at it.

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
- **Nothing taken from other games.** Models, art, animation and code are made here. Mechs are
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
- Don't read or use anything from other projects on this machine (e.g. MechFortress).

## The user

New to LANCER and wants to learn it by playing, so in-game text explains rules plainly. Explain
choices to them in plain language, not engine jargon.

## Git

Repo: https://github.com/Gabensrightnut/lancer-auto-gm (public, GPL-3.0-or-later).
End commit messages with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
