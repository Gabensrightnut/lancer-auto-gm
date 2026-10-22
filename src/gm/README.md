# src/gm: procedural GM and AI pilots

No AI service: the GM is ordinary code driven by data in `data/game/gm/` (DESIGN.md
section 9). Everything it does goes through `NetHost.submit()` -> `RulesEngine.submit()`.

| File | What it does |
|---|---|
| `mission_generator.gd` | `MissionGenerator.generate(seed, opts)` -> `{state, mission}`: sitrep, battlefield from `TerrainGen` (landscape + culture, 20-40 spaces; kit in `mission.flavor.kit`), zones, deployment, squad (core Everest builds) and enemies (NPC templates). Same seed, same mission. |
| `mission.gd` | Sitrep rules and scoring (Basic Combat, Control, Holdout, Gauntlet); `observe(state, events)` sets `outcome`. Save with `to_dict()`. |
| `tactics_ai.gd` | Utility AI: picks a whole turn for one unit (move, attacks, Lock On, Scan, Hide, Stabilize, Boost) and explains it in one line. |
| `ai_knowledge.gd` | The planning copy of the battle for one side: Hidden enemies left out, unscanned stats unknown. |
| `ai_director.gd` | Runs AI seats on the host: starts combat, picks who acts, plays AI turns, reinforcements, ends the mission. |
| `gm_settings.gd` | Dials (aggression, caution, focus fire, reinforcements, difficulty, randomness) and presets. |
| `name_gen.gd` | Seeded callsigns, pilot/mech names and mission flavor from the COMP/CON generator lists. |
| `gm_actions.gd` | Host-only engine actions `gm_spawn` and `gm_end_mission` (events `units_arrived`, `mission_ended`). |

## Using it (UI)

```gdscript
var gen := MissionGenerator.generate(seed, {"players": 4, "settings": GmSettings.from_preset("Teaching")})
var hot := Net.start_hot_seat(gen["state"], RulesEngine.new(), ["p1", "p2", "p3", "p4"])
Net.host.set_seat_ai("p3", true)         # AI squadmates; switch any time
Net.host.set_seat_ai("p4", true)
var gm := Net.attach_ai(GmSettings.from_preset("Teaching"), gen["mission"])
gm.ai_log.connect(func(unit, text): battle_log.add(text))
gm.mission_over.connect(func(outcome, reason): show_debrief(outcome, reason))
gm.set_orders("p3", {"stance": "defensive", "focus": "e2"})   # stances: aggressive, defensive, support, hold, follow
hot.start()
```

`Net` calls `director.step()` every `ai_step_interval` seconds so each AI move can animate.
Online: `Net.host.set_fill_empty_with_ai(true)` (off by default) gives every empty seat an AI
pilot; `set_seat_reserved(seat, true)` keeps one free for a friend. A friend who joins an
AI seat takes it over; when they leave, the AI picks it back up.

The AI only acts for seats set to AI and never times out or auto-resolves a human seat.
On a side with any human seat the humans pick who goes next ("I'll go", including sending an
AI squadmate in); the AI picks only for a side with no human seat (normally the GM's). Show
`host.waiting_on(seat)` so players know who the game is waiting for (src/net/README.md).

Names and flavor (callsigns, pilot and mech names, operation, planet, faction, team, cargo)
come from COMP/CON's lists in `data/compcon/generators/` via `NameGen`; our own extra lines
go in `data/game/names/<same file name>`. Pilot details are in `state.seats[seat]`
(`callsign`, `pilot`, `mech`); `mission.flavor` holds the rest.
