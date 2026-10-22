# src/flow: the playable loop (milestone 1)

main menu → new campaign / continue / join → lobby → builder → GM-generated mission → battle →
mission end → debrief and level up → save → next mission. Solo, hot-seat and online.

| File | What it does |
|---|---|
| `game_flow.gd` | `GameFlow`: start a mission from the lobby (with autosave), resume a saved one, finish (record, +1 License Level per pilot, save), next mission's lobby. |
| `battle_session.gd` | `BattleSession`: one battle without rendering. Host (NetHost + HotSeat + AiDirector + autosave) or online client (NetClient). Whose turn, "I'll go", hot-seat handoffs, reaction questions, AI pacing (waits while the screen animates), mission end. Tested headless. |
| `seat_engine.gd` | `SeatEngine`: the RulesEngine the turn UI talks to; previews on the seat's own view, submits through the host (or to the host when online). |
| `view_mirror.gd` | A GameState rebuilt from one seat's view, so turn previews never see secrets. |
| `battle_screen.gd` (`scenes/flow/battle.tscn`) | The visuals work's BattleView, EventPlayer, TurnOrderBar, ActionBar, PlayerTurn, RollDisplay, CombatLog on a BattleSession; plus the hot-seat "Pass to" screen, reaction prompt, in-battle menu. |
| `debrief_screen.gd` (`scenes/flow/debrief.tscn`) | Outcome, level ups with "Spend points" (builder), next mission / main menu. |

Screenshot staging: `tools/screenshot.gd -- res://scenes/flow/battle.tscn out.png 150 stage:turn`
(your turn) or `stage:hotseat` (pass-the-screen); opened on its own the battle uses an unsaved
example campaign (saves under `user://example_saves`).
