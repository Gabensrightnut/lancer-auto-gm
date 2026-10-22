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
`GameSettings.ACTIONS`. The builder's `preview_area` (node `MechPreview`) is the placeholder for
the 3D mech preview.
