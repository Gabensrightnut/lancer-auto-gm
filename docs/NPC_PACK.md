# The local official NPC pack

The LANCER core book's NPC stat blocks (GM's Toolkit) are paid book content that Massif doesn't
ship in its free `lancer-data`, and this repo is public. So the official numbers live in a
local-only file that is never committed:

- **Where:** `local/content/core_npcs.json` (the whole `/local/` folder is gitignored).
- **Loaded by:** `ContentDB.load_all()`, through `ContentPack.from_json()`, whenever the file
  exists. Classes, features and templates with the same id as our placeholders replace them
  (`NPCBuilder.source()`); a unit built from it has `loadout.placeholder = false`.
- **Without it:** the game uses our own placeholders (`data/game/npc_placeholder_pack.json`),
  which have the same ids and mechanics with made-up numbers.

## Format

One JSON object: `name`, `author`, `version`, and the collections `npc_classes`, `npc_features`,
`npc_templates` in the lancer-data / COMP/CON NPC format (field meanings at the top of
`src/content/npc_builder.gd`). Extra fields the engine reads:

- class `npc_type`: e.g. `["Biological", "Squad"]` (Core p.282 types of NPCs).
- weapon feature `attacks`: attacks made at a time (the Squad's Main Rifle: 2).
- Feature mechanics are not in the pack: the engine looks them up by feature id in
  `data/game/npc_feature_effects.json` (our own data, no book text).

## How it's built

Type the stat blocks from your own copy of the core book (Special Classes, Core p.322-323, so
far: Human and Squad, ids `npcc_human`, `npcc_squad`, `npcf_human_*`, `npcf_squad_*`). Keep the
ids of the placeholders so the soldier builds in `data/game/soldiers.json` find them. Never copy
the file or its text into the repo.
