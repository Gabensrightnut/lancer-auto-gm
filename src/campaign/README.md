# src/campaign: campaigns, saves, resuming

| File | What it does |
|---|---|
| `campaign.gd` | `Campaign`: pilots (COMP/CON-style records), story flags, rulings, enabled content packs, GM settings, mission history. New pilots start at License Level 0 with GMS gear (book default); `Campaign.create(name, {"start_ll": 3})` starts higher. `validate_pilot()` lists anything illegal in plain words. `squad()` feeds `MissionGenerator` (`opts.squad`). |
| `save_store.gd` | `SaveStore`: `user://saves/<campaign>/campaign.json` and `mission.json`. Writes go to a temp file first and the previous save is kept as `.bak` (loaded automatically if the main file is damaged). |
| `mission_autosave.gd` | `MissionAutosave`: saves the mission after every turn (full state including dice, mission, GM settings, seats). `MissionAutosave.resume()` rebuilds the host; `Net.resume_mission(store, id)` does it all, reopens the same room code and holds play until every remote player is back. |

Saves are versioned (`Campaign.SAVE_VERSION`, `SaveStore.MISSION_VERSION`): `Campaign.migrate()`
upgrades older saves step by step; saves from a newer game version are refused with an "update
the game" message.

Content packs (`src/content/pack_library.gd`): `.lcp` files in `user://packs/`. A campaign's
`packs` list says which are on; `PackLibrary.load_db(campaign.packs)` builds the ContentDB and
reports missing ones. `Campaign.prepare_mission(state)` copies packs and rulings into the
battle; joining players must have the same packs (refusal code `missing_packs`).

COMP/CON (`src/content/compcon.gd`): `Compcon.import_pilot(json, db)` -> `{ok, pilot,
warnings, errors}` (v2 and v3 pilot exports); `Compcon.export_pilot(pilot, db)` -> v2 JSON.
