# src/flow: the playable loop (milestone 1)

main menu → new campaign / continue / join → lobby → builder → GM-generated mission → battle →
mission end → debrief and level up → save → next mission. Solo, hot-seat and online.

Story campaigns (`campaign.options.story`; the **Tutorial** on the main menu starts one with
`GameFlow.start_tutorial` → `CampaignLoop.start_tutorial`): main menu → hub (briefing, job
board) → boots on the ground → battle (`GameFlow.start_story_mission`, the battlefield from
`CampaignLoop.build_mission`) → back to the hub for the story's debrief, level up and downtime
(`CampaignLoop.finish_mission`). Continue on a story campaign opens the hub.

| File | What it does |
|---|---|
| `game_flow.gd` | `GameFlow`: start a mission from the lobby (with autosave), resume a saved one, finish (record, +1 License Level per pilot, save), next mission's lobby. |
| `battle_session.gd` | `BattleSession`: one battle without rendering. Host (NetHost + HotSeat + AiDirector + autosave) or online client (NetClient). Whose turn, "I'll go", hot-seat handoffs, reaction questions, AI pacing (waits while the screen animates), mission end. Tested headless. |
| `seat_engine.gd` | `SeatEngine`: the RulesEngine the turn UI talks to; previews on the seat's own view, submits through the host (or to the host when online). |
| `view_mirror.gd` | A GameState rebuilt from one seat's view, so turn previews never see secrets. |
| `battle_screen.gd` (`scenes/flow/battle.tscn`) | The visuals work's BattleView, EventPlayer, TurnOrderBar, ActionBar, PlayerTurn, RollPopups, CombatLog on a BattleSession; plus the hot-seat "Pass to" screen, reaction prompt, in-battle menu. |
| `debrief_screen.gd` (`scenes/flow/debrief.tscn`) | Outcome, level ups with "Spend points" (builder), next mission / main menu. |
| `hub_screen.gd` (`scenes/flow/hub.tscn`) | A story campaign between missions: the story's HubScene, saved after every story step, a Menu (pilot builder, teaching hints, settings, save and quit). Turns the hub's "boots on the ground" into a battle. |
| `narration_popup.gd` | `NarrationPopup`: the GM speaking mid-battle in the story's dialogue look: a mission twist (`twist_revealed`) or narration (`gm_narration`, e.g. the squad arrived late). The AI waits while it's open. |

Tutorial and tips in battle: the battle screen feeds every batch of events the on-screen seat
sees (`BattleSession.events_seen`, own actions included) to `Tutorial.observe_battle` and shows
the result in a `TutorialPanel`. Tips follow `campaign.options.teaching_hints` (the in-battle
and hub menus switch it; "Hide hints" on the panel too). A friend in someone else's game gets
tips only (the host keeps the campaign). Graphics: battle and hub screens call
`GameSettings.apply_graphics` (WorldQuality preset) before building the board.

Screenshot staging: `tools/screenshot.gd -- res://scenes/flow/battle.tscn out.png 150 stage:turn`
(your turn), `stage:hotseat` (pass-the-screen) or `stage:twist` (twist pop-up and a lesson); opened on its own the battle uses an unsaved
example campaign (saves under `user://example_saves`).

## Playtesting the real window

`src/flow/dev/playtest_driver.gd` plays the game like a person (real clicks and key presses on
what's on screen) and saves screenshots and a log: launch with
`godot --path . --resolution 1920x1080 -- qa:solo qa_out:C:/folder` (modes: solo, hotseat,
host + join). It uses its own save folder. Findings: `docs/qa/milestone1.md`.
