# src/explore: walking around as pilots

| File | What it does |
|---|---|
| `hub_scene.gd` | `HubScene`: the 3D hub (town, base or station) the squad walks around in real time. WASD or click to walk, Q/E turn the camera, F or click a person to talk, Tab downtime, J job board, Esc closes menus. Owns the story UI (dialogue, check pop-up, downtime, level up, HUD) and turns story events into pop-ups and toasts. Emits `mission_requested(hook)` when the squad deploys or a scene starts a fight. |
| `hub_layout.gd` | `HubLayout`: where the buildings are (bar, office, market, workshop, printer bay, mech gantries) around the plaza, and where each person stands. Plain data, seeded, saved in `story.hub`. |
| `hub_hud.gd` | `HubHud`: hub name, the campaign phase in plain words with the next-step button, the squad (HP, Down and Out, reserves), standing, favors owed, toasts, the job board. |
| `pilot_figure.gd` | `PilotFigure`: a person on foot built from primitives, colored from the same look as their portrait, with a walk cycle. |
| `hub_demo.gd` | `HubDemo.make()`: four LL0 pilots (one human, three AI) at a generated town in downtime. |

Try it / check visuals:

```bash
godot --path . -s res://tools/screenshot.gd -- res://scenes/explore/hub.tscn "hub_%s.png" 40
```

Stages: walk, talk, choices, check, downtime, board, briefing, levelup.

Use from the game:

```gdscript
var story := StoryState.of(campaign)
var engine := StoryEngine.new(db)
engine.submit(story, campaign, {"type": "set_seat", "seat": "gm", "params": {"seat": "p1", "pilot": pid}})
engine.submit(story, campaign, {"type": "enter_hub", "seat": "gm", "params": {"kind": "town", "seed": 1}})
var hub := preload("res://scenes/explore/hub.tscn").instantiate() as HubScene
add_child(hub)
hub.setup(engine, story, campaign, db, "p1")
hub.mission_requested.connect(func(_hook): var gen := CampaignLoop.build_mission(campaign, story, db); ...)
```

Pilots in a mech battle (on foot or not) are the rules engine's pilot units; a hub fight with no
mechs is a narrative skill check (Core p.48), handled by the dialogue.
