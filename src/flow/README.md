# src/flow: the playable loop (milestone 1)

main menu → new campaign / continue / join → lobby → builder → GM-generated mission → battle →
mission end → debrief and level up → save → next mission. Solo, hot-seat and online.

Story campaigns (`campaign.options.story`; the **Tutorial** on the main menu starts one with
`GameFlow.start_tutorial` → `CampaignLoop.start_tutorial`): main menu → hub (briefing, job
board) → boots on the ground → battle (`GameFlow.start_story_mission`, the battlefield from
`CampaignLoop.build_mission`) → back to the hub for the story's debrief, level up and downtime
(`CampaignLoop.finish_mission`, with every battle event). Continue on a story campaign opens
the hub. New campaign offers "Story campaign" (the default: `GameFlow.start_story_campaign`,
a town hub, seat p1 here and AI squadmates with personas in the rest) or "Missions only" (the
lobby loop), and a campaign length (`options.campaign_arcs`, default 3 stories; the tutorial
asks too). The hub Menu (or Esc) can retire the squad (`end_campaign`, between missions only;
the button says why when it can't). When a campaign ends the story's EpilogueScreen shows (also
when the campaign is opened again); "New campaign with the same pilots" saves and opens
`GameFlow.start_sequel` (`CampaignLoop.sequel`), "Main menu" (`HubScene.menu_requested`) leaves.

A new story campaign (not the tutorial or a sequel) starts with session zero (Core p.40-41):
the hub shows the story's `SessionZeroScreen` over the town before anything else, and the job
board fills only once it's applied (`GameFlow.finish_session_zero`), so its choices shape the
first jobs. `campaign.options.session_zero_pending` keeps it waiting if the player quits first.

Enemy commanders and parley in story battles (Core p.60): the host sends every batch of rules
events to the story (`GameFlow.story_battle_events`, StoryEngine `battle_events`); when the
commander opens a parley, or the squad presses "Call for terms" (refused with the book's reason
while the fight is in question), the story's `DialogueView` shows over the battle and the AI
waits. A choice that ends the fight (`battle_end_requested`, from any seat) becomes the GM's
`gm_end_mission` (`BattleSession.end_by_parley`). Friends online see the conversation through
their StoryClient. Bark speaker names come from `line.who` (so the commander's taunts are named).

Codex (the story's `CodexPanel`, the rules reference): a main menu button, and in battle the
pause menu ("Codex: look up <term>") or the rebindable Codex key (F1), opened on whatever the
player last pointed at: a mech's frame, else the last action hovered on the action bar. After leveling up, talent, license and core bonus picks are made in the pilot builder
(hub Menu); closing it updates `story.pending_picks` (`GameFlow.builder_done`).

Online story campaigns: the hub Menu's "Invite friends online" makes `GameFlow.story_host`, a
NetHost carrying the story's seats at the hub, with `StorySession.attach_net_host`. The host's
hub UI talks to a `StoryHostEngine` (actions through the session, so friends get every
change). A friend who joins lands in the lobby, which sees the story payload and opens the
hub with `GameFlow.join_story` (`StoryClient.attach_net_client`; the hub UI's engine is the
StoryClient, and each new view is copied into the objects the hub already holds). Friends
take AI squadmates' seats (the AI takes a seat back if its friend leaves). Their builds go to
the host as `{"pilot_update": pilot}` and are kept only if legal and their own. Boots on the
ground: the battle runs on the same NetHost, so friends follow the host in ("started") and
come back to the hub for the debrief. Walking around the hub is shared too: each screen sends
its pilot's spot ({"hub_pos": [x, z, facing]}, `HubScreenPositions`) a few times a second and
the host passes it on; other players' pilots glide there (cosmetic, not game state).

AI squadmates in story battles: `GameFlow.apply_squad_orders` gives the AI director each
one's stance (`Squadmate.orders`: their frame's role or persona) when the battle starts or is
resumed, and the battle screen shows their barks (`Squadmate.barks_for`) as speech bubbles
over their mechs (the visuals' `BattleBarks`, named from `line.who`) and in the combat log.

| File | What it does |
|---|---|
| `game_flow.gd` | `GameFlow`: start a mission from the lobby (with autosave), resume a saved one, finish (record, +1 License Level per pilot, save), next mission's lobby. |
| `battle_session.gd` | `BattleSession`: one battle without rendering. Host (NetHost + HotSeat + AiDirector + autosave) or online client (NetClient). Whose turn, "I'll go", hot-seat handoffs, reaction questions, AI pacing (waits while the screen animates), mission end. Tested headless. |
| `seat_engine.gd` | `SeatEngine`: the RulesEngine the turn UI talks to; previews on the seat's own view, submits through the host (or to the host when online). |
| `view_mirror.gd` | A GameState rebuilt from one seat's view, so turn previews never see secrets. |
| `battle_screen.gd` (`scenes/flow/battle.tscn`) | The visuals work's BattleView, EventPlayer, TurnOrderBar, ActionBar, PlayerTurn, RollPopups, CombatLog on a BattleSession; plus the hot-seat "Pass to" screen, reaction prompt, in-battle menu. |
| `debrief_screen.gd` (`scenes/flow/debrief.tscn`) | Outcome, level ups with "Spend points" (builder), next mission / main menu. |
| `hub_screen.gd` (`scenes/flow/hub.tscn`) | A story campaign between missions: the story's HubScene, saved after every story step, a Menu (pilot builder, teaching hints, settings, save and quit). Turns the hub's "boots on the ground" into a battle. |
| `hub_screen_positions.gd` | Wire format for pilots' walking positions at the hub, checked on arrival. |
| `story_host_engine.gd` | `StoryHostEngine`: the host's hub UI engine; every story action goes through the StorySession (friends online see it). |
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
