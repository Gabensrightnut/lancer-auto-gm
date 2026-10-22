# src/gm: procedural GM and AI pilots

No AI service: the GM is ordinary code driven by data in `data/game/gm/` (DESIGN.md
section 9). Everything it does goes through `NetHost.submit()` -> `RulesEngine.submit()`.

| File | What it does |
|---|---|
| `mission_generator.gd` | `MissionGenerator.generate(seed, opts)` -> `{state, mission}`: sitrep, battlefield from `TerrainGen` (landscape + culture, 20-40 spaces; kit in `mission.flavor.kit`), zones, deployment, squad (core Everest builds) and enemies (NPC templates). Same seed, same mission. |
| (environments) | `MissionGenerator` turns what the world suggests into rules environments (lancer-data environments.json): the weather's (`data/game/biomes/weather.json` "environment": sandstorm, storm, blizzard) and the landscape's (moon/asteroid low gravity, ocean world, volcanic molten world). Each comes into play at the GM dial `environments` (Standard 0.5, Teaching 0) with its own seeded roll. Result: `mission.environments`, `state.environments` (for the rules engine), `flavor.environments` ({id, name, text}), a line in the briefing, and a `gm_narrate` "environment" announcement to everyone when combat starts. |
| `mission.gd` | Sitrep rules and scoring (Basic Combat, Control, Holdout, Gauntlet); `observe(state, events)` sets `outcome`. Save with `to_dict()`. |
| `tactics_ai.gd` | Utility AI: picks a whole turn for one unit (move, attacks, Lock On, Scan, Hide, Stabilize, Boost) and explains it in one line. |
| `ai_knowledge.gd` | The planning copy of the battle for one side: Hidden enemies left out, unscanned stats unknown. |
| `ai_director.gd` | Runs AI seats on the host: starts combat, picks who acts, plays AI turns, reinforcements, ends the mission. |
| `gm_settings.gd` | Dials (aggression, caution, focus fire, reinforcements, difficulty, randomness) and presets. |
| `sitrep_layout.gd` | `SitrepLayout.layout(sitrep, w, h, shape, rng)`: deployment zones, sitrep zones (control/recon quadrants mirrored, holdout center with a wrap-around EDZ, gauntlet, escort extraction and route, extraction objective) and cells kept clear. |
| `map_fairness.gd` | `MapFairness.check/repair`: balanced cover between halves, part of each deployment zone out of the other's sight, every objective reachable on foot by Size 1-3. PROVISIONAL thresholds (GM choice). |
| `name_gen.gd` | Seeded callsigns, pilot/mech names and mission flavor from the COMP/CON generator lists. |
| `gm_actions.gd` | Host-only engine actions `gm_spawn`, `gm_end_mission` and `gm_narrate` (events `units_arrived`, `mission_ended`, `twist_revealed`, `gm_narration`). |
| `gm_twist.gd` | The story hook's hidden twist (`mission.flavor.twist`, Core p.43): the AI GM picks its moment (round 3 or halfway through a timed mission, or sooner at the first mech/NPC destroyed or zone scored) and reveals it through `gm_narrate`, seen only by the squad's side (`seen_by`, ViewFilter). Also narrates `arrived_late` / `arrived_spent` at the start of combat. |

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
