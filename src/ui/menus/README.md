# src/ui/menus: screens around the battle

Screens are built in code on a shared look (`menu_theme.gd`: dark panels, condensed system font,
manufacturer accent colors, official icons from `assets/icons/lancer/` rasterized crisply).
Logic is kept out of the screens so it can be tested.

| Scene (`scenes/menus/`) | Script | Logic |
|---|---|---|
| `main_menu.tscn` | `main_menu.gd` | Continue (saved campaigns; resumes a mission in progress), New campaign, Join online (room code), Settings, Quit |
| `lobby.tscn` | `lobby_screen.gd` | `LobbyModel`: seats (you / AI / open / reserved), fill empty seats with AI, pilot per seat, content packs, GM preset, hex/square grid, ready-up, start checks, version/pack mismatch messages |
| `builder.tscn` | `builder_screen.gd` | `BuilderModel`: License Level, point budgets, skills, talents, licenses, core bonuses, mech skills, frame, mounts, weapons, mods, systems; locked choices show why; COMP/CON import/export |
| `settings.tscn` | `settings_screen.gd` | `GameSettings` (user://settings.cfg): UI scale, text size, action bar size, colorblind mode, graphics preset, animation speed, pop-up time, key bindings |

`MenuSession` holds what screens share (campaign, lobby, content database, settings) and
switches scenes. Starting a mission hands `Net.host` / `Net.director` the lobby's host and AI
director and opens `MenuSession.BATTLE_SCENE` (`scenes/main.tscn`).

For the battle HUD: read `GameSettings.load_settings()` for `action_bar_scale`, `colorblind`,
`animation_speed`, `popup_duration`; key bindings are InputMap actions named in
`GameSettings.ACTIONS`. Graphics: `GameSettings.graphics` is a WorldQuality preset, applied with
`apply_graphics(viewport)` before a board is built.

Builder: the pilot's portrait with "Edit look" (the visuals' `PilotCreator`, full screen;
result in `pilot["portrait"]`), the visuals' `MechPreview` (turntable and paint customizer,
`mech["paint"]`) in `preview_area`, and "What the game handles": `BuilderModel.automation()`
lists each trait, core system, system, weapon and talent as automatic / partly / at the table
with what to do at the table (the rules engine's `Automation.for_build` when it's in the game;
until then the frame's traits and core system). Lobby "+ New pilot" makes a pilot (random
starting look) and opens the builder with the look creator first. Screenshot stages for the
builder: `stage:creator`, `stage:automation`.
