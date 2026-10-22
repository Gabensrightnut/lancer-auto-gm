# src/story: dialogue, the campaign loop, downtime, out-of-mech play

Everything between battles. All of it is data-driven (`data/game/story/`, `data/game/npcs/`)
and follows the core book. Page numbers are the free core book ("Core p.N").

## How LANCER handles life out of the mech (what this is built on)

- **Money exists, the rules don't count it.** Manna is the universal currency outside the Core
  (Core p.10) and frontier worlds have local currencies (p.126), but the rules don't track
  currency (p.18): it appears in dialogue only. Gear comes from licenses: every pilot has GMS,
  and each License Level (one per mission finished, win or lose) gives a license rank to spend
  on a frame license (rank II unlocks the frame) (p.18, p.31). Mechs are printed: with 10 quiet hours somewhere secure
  a FULL REPAIR fixes or reprints anything you're licensed for, one mech at a time (Core p.82).
- **Pilot gear isn't licensed**: one armor, up to two weapons, up to three other items per
  mission (Core p.108).
- **Reserves** are anything extra you bring to the next mission (gear, favors, access, intel,
  support), gone after it (Core p.43, p.50-52). The GM can grant them any time; players get them
  through **downtime actions** (Core p.53-55): Power at a Cost, Buy Some Time, Gather
  Information, Get a Damn Drink, Get Creative, Get Focused, Get Organized, Get Connected,
  Scrounge and Barter. (There is no "Get Resources" action in the core book.) Usually one
  action per pilot per downtime, two in a long one.
- **Narrative skill checks** (Core p.45-47): d20 + one trigger (+2/+4/+6) + Accuracy/Difficulty,
  10+ succeeds; background invoked for +1 Accuracy (or the GM for +1 Difficulty); DIFFICULT,
  RISKY, HEROIC; pushing it; teamwork +1; skill challenges. NPCs don't roll in narrative play.
- **Fights with no mechs** are resolved as skill checks, not turns (Core p.48), with harm
  1-2 / 3-5 / 6+, Armor, 0 HP -> 1d6 Down and Out roll (Core p.48-49); an hour's rest gives
  half HP back. Mech combat (and pilots on foot inside it) is the rules engine.
- **Order of play** (Core p.40-44): briefing (goal and stakes) -> preparation and reserves ->
  boots on the ground -> debrief and level up -> downtime -> next briefing.

## Files

| File | What it does |
|---|---|
| `story_state.gd` | `StoryState`: flags, standing, hub and NPCs, contacts, reserves, pilot HP out of the mech, downtime memory, phase, story dice. Saved inside the campaign (`StoryState.of(campaign)`, `save_to(campaign)`). |
| `story_engine.gd` | `StoryEngine.submit(story, campaign, action)` -> `{ok, reason, rule_ref, events}`. The only thing that changes a StoryState. Action list at the top of the file. Runs AI squadmates' choices, downtime and level-up picks. |
| `narrative_check.gd` | Book skill checks, push levels, skill challenges. |
| `story_conditions.gd` / `story_effects.gd` | The condition and effect vocabulary scenes and downtime data use (lists at the top of each file). |
| `dialogue.gd` | Runs scenes from `data/game/story/scenes/*.json`: branching nodes, 4-6 choices filtered by conditions (cap keeps pinned and trigger-unlocked ones), checks, who decides (speaker or squad vote), AI picks in character (`personas.json`). |
| `downtime.gd` | The nine downtime actions from `data/game/story/downtime.json` + lancer-data text: bands, "choose" lists, "next time treat it as..." memory, organizations, projects, contacts' help. |
| `campaign_loop.gd` | Builds the battle for the chosen job (squad with pilot units, mechanical reserves applied) and feeds the result back (`finish_mission`). |
| `mission_hooks.gd` / `npc_gen.gd` / `story_text.gd` | Procedural jobs, hubs and people from our tables + COMP/CON's name lists; line pools with variants, personality and standing flavors. |
| `story_arc.gd` | `StoryArc`: a few-mission situation at a hub (`arcs.json`) whose next mission is always on the job board; every mission moves it on, win or lose. |
| `tutorial.gd` | `Tutorial`: the guided first opening (`tutorial.json`). `CampaignLoop.start_tutorial()` sets up the training base and the drill; lessons advance on story events automatically and on battle events via `Tutorial.observe_battle(story, campaign, events, my_unit_ids)`; first-time rule tips while `campaign.options.teaching_hints` is on. `ui/tutorial_panel.gd` shows them (hub or battle). |
| `portrait_spec.gd` | `PortraitSpec`: portrait builder data hooks (`portraits.json`): parts with options and color slots, palettes, randomize with locks, old-look upgrade, the expression set (10 ids, placeholder faces via `draw_as`) and automatic expressions (NPC standing/personality, pilot reply tags, check results). Pilots: `pilot["portrait"]`. |
| `story_session.gd` / `story_client.gd` / `story_view.gd` | Multiplayer story. The host's `StorySession` runs every action as the sending seat (remote players can never act as the GM), broadcasts `StoryView` views (no NPC secrets, hidden twists or story dice) over the lobby channel (`attach_net_host`); a remote player's `StoryClient` is a drop-in `StoryEngine` for the UI that forwards actions and mirrors the view (`attach_net_client`). Downtime choices wait per pilot, so one player never blocks another; teamwork helpers opt in or out (`dialogue_help`). |
| `ui/downtime_screen.gd` | Downtime as its own scene: the squad's cards with every narrated result (AI too), the action picker, back to the hub or on to the briefing. |
| `squadmate.gd` | `Squadmate`: AI squadmates as characters. `suggest(pilot)` picks a persona from triggers and background; `role()` / `orders()` give the team role (frame mechtype, or the persona for the Everest) and AiDirector stance; a memory per pilot (wounds, wrecks, fallen friends, choices) shifts their likes and downtime picks, and drives `banter()` between missions (banter.json) and `barks_for(event)` in battle (barks.json, cosmetic, own RNG). |
| `background_story.gd` | `BackgroundStory`: background-only dialogue options per NPC role and personal stakes on jobs (background_story.json). |
| `bonds.gd` | `Bonds`: relationships between pilots (Rivals .. Inseparable) from shared missions, mourning, teamwork, drinking together and vote clashes; the GM's bond reward (+1 Accuracy helping each other next mission, Core p.50; option `bond_rewards`); the Bonded talent's bondmate rule (`set_bondmate`, Core p.90). |
| `ending.gd` | `Ending`: when a campaign ends (options.campaign_arcs situations, LL12, the squad fallen, or `end_campaign`), its kind and an epilogue per pilot (endings.json); `CampaignLoop.sequel()` starts a new campaign with the same pilots. `ui/epilogue_screen.gd` shows it. |
| `codex.gd` | `Codex`: the in-game rules reference (DESIGN.md section 8). Every glossary term, status, action, tag, frame (stats, traits, core system), manufacturer, skill trigger, background, downtime action, reserve, pilot gear and talent, with lancer-data's own text (HTML stripped), plus our own features (`codex_own.json`, marked "Game feature (not a book rule)"). `search(query, category)` ranks exact > prefix > title > text. `ui/codex_panel.gd` shows it in the hub (K, or the HUD button; tutorial tips link to it). |
| `session_zero.gd` | `SessionZero`: the first-session setup (Core p.40-41, `session_zero.json`, our own lists): who the squad is, who gives it orders (biases which NPCs bring work), history questions between pilots (starting bonds), tone (twist chance, arc weights), focus (long downtime, banter) and content to leave out (filters our twists and arcs). Applied with the `session_zero` action before the first mission; `ui/session_zero_screen.gd` (`scenes/story/session_zero.tscn`). |
| `rivals.gd` | `Rivals`: enemy commanders as characters (`rivals.json`): one leads every enemy force (the toughest enemy unit, renamed, `mission.flavor["commander"]`), with a portrait and one of six personalities; a story arc's other side keeps one commander throughout, and those who got away come back for revenge (`hook["commander"]`). In battle they taunt (`Squadmate.barks_for` returns their lines too, `"rival": true`) and, once the outcome is clear (Core p.60), may yield, withdraw, offer a deal or let a losing squad walk away; the squad can call for terms (`parley`). The `parley` scene's choices end the fight with `battle_end_requested` (`CampaignLoop.end_by_parley(mission, event)` gives the `gm_end_mission` action). After the mission their fate is remembered (captured, withdrew, escaped, dead, routed, won) and mentioned in the debrief. |
| (NHP cascades) | `CampaignLoop.battle_summary` lists squad mechs whose NHP cascaded (the rules engine's `cascade_check`, Core p.107); the debrief mentions it, the pilot remembers it and talks about it in banter, and squadmates bark when it happens. Off when session zero leaves NHP themes out. |
| `story_settings.gd` | `StorySettings`: per-player reading options kept in `user://`: text size (`set_text_scale`, StoryStyle scales every story label and button), "skip read lines" (lines already seen go by on their own; choices always wait). `notifier().changed` for UI. The dialogue's toolbar has both, plus the scroll-back log (L) of every conversation (`Dialogue.transcript`). |
| `sector.gd` | `Sector`: the systems and worlds the squad works in (`sector.json`, `story.flags["_sector"]`): 3 systems joined by blink gates (Core p.10), 2-3 worlds each, every world with its own culture kit, landscape (jobs are fought on it) and hub. The `travel` action (between missions, host) moves the squad; the hub left behind is kept with its people, job board and situation (`story.flags["_hubs"]`). A world whose situation ended stays quiet for `StoryArc.QUIET` missions (a `story_hint` suggests moving on). `ui/campaign_map.gd` (`CampaignMap`, M in the hub, `scenes/story/campaign_map.tscn`): the map, standing per world, jobs, situation, Travel. |
| `gm_tools.gd` | `GmTools`: a human GM's story tools (DESIGN.md "Human GM seat"), all StoryEngine actions from the gm seat: `gm_scene` (write a conversation on the spot: lines with who/face, 0-6 replies with answers and effects; saved in `story.flags["_gm_scenes"]`, replayable, and `Dialogue.scene_of` finds them on clients too), `gm_twist` (reveal / hide / set), `gm_standing`, `gm_reserve` (give or take back), `gm_job`, `gm_edit_job` (text, own briefing, commander: existing / none / new), `gm_remove_job`, `gm_npc` (edit or add). `ui/gm_panel.gd` (`GmPanel`, G in the hub when `gm_enabled()`, `scenes/story/gm_panel.tscn`). |
| `story_data.gd` | `StoryData.lint()`: checks every scene, effect, condition, pool, trigger and reserve id (run by the tests). |
| `ui/` | `DialogueView` (PortraitArt cards, mirrored speaker, speech bubble, choices, votes, log), `Portrait` (drawn placeholder faces with expressions), `StoryCheckPopup` (instant roll, one big number, breakdown on hover), `DowntimePanel`, `LevelUpPanel`, `PilotGearPanel` (the quartermaster's racks). |

Story tables (all our own writing, patterns from `docs/research/lancer_campaigns.md`, canon checks
in `docs/CANON.md`): `hooks.json` (22 job templates after the book's goal table, stakes as
questions, `hazardous` crossings), `twists.json` (hidden, revealed at the debrief),
`conflicts.json` (each hub's two sides), `arcs.json`, NPC archetypes and secrets in
`data/game/npcs/tables.json`, and side-job **deals** (an NPC's job pays a named reserve; a lost
deal is withdrawn, and Get Connected stays open as another way).

## Supplies, the book's way

No survival meter. Pilots carry their own supplies as pilot gear (Extra Rations, Wilderness
Survival Kit, Patch, Corrective, Sleeping Bag; Core p.108), shown on the HUD with each mech's
Repairs. Anything bigger is a one-mission reserve (Core p.51): **Supplies** (easy crossing of
hostile ground), **Extra repairs** (+2 Repair Cap), **Ammo**, from a contact (Get Connected) or
**Scrounge and Barter** (presets for each). The quartermaster explains it. A `hazardous` job
makes the squad cross hostile ground at the briefing: a skill challenge (Core p.47) with
1 harm each on a failure, or the long way round (time), skipped if anyone brought Supplies.

The walkable hub is in `src/explore/` (`HubScene`, `scenes/explore/hub.tscn`).

## Our own bookkeeping (not book numbers)

- **Faction standing** (-3 Hostile .. +3 Allied) is how the procedural GM remembers who likes
  the squad. It only changes which dialogue options appear, how people greet you, and what a
  contact offers when you Get Connected (Trusted +2 opens more of the book's reserves). It
  never changes a roll. Jobs, favors and some downtime results move it.
- **What a contact offers** (`data/game/npcs/roles.json`): book reserves that fit the role, e.g.
  a company rep can get you Extra repairs (+2 Repair Cap), Rented gear, Ammo or a CORE battery.
- **Which triggers fit a downtime action**: the procedural GM's call (the book leaves it to
  the GM, Core p.25, p.53); Get a Damn Drink uses the book's own example list.

## PROVISIONAL (please copy into docs/RULES_TODO.md)

- Squad vote ties go to the speaking pilot's vote, then the first option (table procedure).
- Finishing a 10-19 Get Creative project "next downtime without rolling" uses that downtime's
  action. The Get Organized roll adds no trigger.
- AI squadmates take their downtime action as soon as downtime starts, and pick the least
  harmful option when a result says "choose".
- Get a Damn Drink's 9-or-less "wake up with only one" and Scrounge and Barter's prices are
  recorded as story flags (they're narrative; nothing is taken from the pilot's sheet).
- Power at a Cost's GM-chosen costs are picked by the story dice (1 for a modest request, 2 for
  an outlandish one).
- Mechanical reserves applied automatically in battle: Extra repairs, CORE battery. The rest
  are listed in `mission.flavor["reserves"]` for the table (and need engine support).
- Hazardous crossings: 1 harm each on a failed challenge, or "the long way" sets a late flag
  (mission.flavor.arrived_late) for the GM to use; standing changes from jobs, deals and
  conflicts are our own amounts (+/-1).
- Choosing to die instead of going Down and Out (Core p.49) isn't offered yet; cloning and
  coming back (Core p.83) isn't built.

- When a fight's outcome "isn't in question" (Core p.60) so terms can be talked: from round 2,
  half the enemy force down, or their commander badly hurt (last structure, or below half HP
  for a one-structure NPC) with a quarter of their force down; for the squad, half its mechs
  wrecked (`Rivals.enemy_losing` / `squad_losing`). The book leaves it to the GM.

## Asks for other sessions

- **Main / campaign**: give `Campaign` a `story` field instead of `story_flags["_story"]`; add
  `options.dialogue_choice` ("speaker"/"vote"), `options.allow_heroic_push`,
  `options.long_downtime` to the host settings UI.
- **Rules engine**: reserves that change battles (Ammo, Redundant repair, Smart ammo, Boosted
  servos, Jump jets, Deployable shield, Bombardment, Reinforcements, Accuracy) as effects on a
  unit at mission setup; pilot armor/HP from pilot gear in `UnitFactory.build_pilot`.
- **GM (src/gm)**: `mission.flavor["twist"]` holds the hidden twist ({id, reveal, question}):
  reveal it mid-mission (a narration event, e.g. at round 2-3); `mission.flavor["arrived_late"]`
  / `["arrived_spent"]` say how the squad got there. Side jobs and arc missions are ordinary
  hooks with a `sitrep`, built by `CampaignLoop.build_mission` -> `MissionGenerator`.
- **Flow / battle screen**: create a `TutorialPanel`, and after each batch of battle events call
  `Tutorial.observe_battle(story, campaign, events, my_unit_ids)` and pass the result to the
  panel (works in any campaign for the first-time tips). Start a new campaign with
  `CampaignLoop.start_tutorial()` when the player picks "Tutorial".
- **World/maps**: hubs and jobs carry `culture` (frontier_colony, old_west, medieval_tech,
  cyberpunk, retrofuturistic, east_asian, union_core) for picking a matching map kit; the hub's
  3D town could use the same kit's props.
- **Visuals**: draw the parts and 10 expressions in `portraits.json`; `Portrait.set_look()` already
  takes a v2 portrait and any expression id. Every `dialogue_line`, `banter`, bark and epilogue
  carries `face: {portrait, expression}`; NPCs have `npc.portrait`, pilots `pilot.portrait`.
- **Rules engine**: `pilot.bondmate` (set by `set_bondmate`) for the Bonded talent's +1/+2 and reactions.
- **Flow / battle screen**: `Squadmate.orders(story, campaign, db)` -> `AiDirector.set_orders(seat, ...)` when a mission starts; after each batch of events, `Squadmate.barks_for(story, campaign, event, unit->pilot, unit->seat)` gives speech-bubble lines for AI squadmates.
- **Net**: route story actions (`StoryEngine.submit`) through the host like battle actions, send
  story events to clients, and relay hub walking positions to `HubScene.set_avatar_position()`.
- **Menus / builder**: talent, license and core bonus picks waiting in
  `story.pending_picks[pilot]`; the pilot gear picker (`ui_requested` "pilot_gear"); portraits
  read `pilot["look"]` when the portrait builder exists.
- **Menus**: when a new campaign starts (not the tutorial), show `SessionZeroScreen` (`bind(engine,
  story, campaign)`, wait for `done(events)`) before the first briefing. A `CodexPanel` can be
  opened from the main menu / battle screen too (`codex.open(query)`).
- **Flow / battle screen** (enemy commanders and parley, Core p.60):
  - after each batch of battle events (host) submit `{"type": "battle_events", "seat": "gm", "params": {"events": events}}` to the story engine; the commander may open the `parley` dialogue;
  - show a `DialogueView` over the battle while `Dialogue.is_open(story)` (same as the hub);
  - a "Call for terms" button submits `{"type": "parley", "seat": my_seat}` (refused with the reason while the fight is in question);
  - on a `battle_end_requested` story event, submit `CampaignLoop.end_by_parley(mission, event)` through the host like any GM action;
  - bark lines now carry `"who"` (the speaker's callsign): use it instead of `campaign.pilots[line.pilot].callsign`, so the enemy commander's taunts get a name.
- **Menus / settings**: a "Story text" section: text size (`StorySettings.set_text_scale`, 0.8-1.6) and "Skip lines I've read" (`StorySettings.set_skip_seen`).
- **Flow / menus**: a `CampaignMap` can be opened anywhere between missions (`bind(engine, story, campaign)`, `open()`); on `travelled(events)` rebuild whatever shows the hub (HubScene does this itself). Multiplayer: `travel` is a host (gm seat) action.
- **World/maps**: a hub now carries `hub["landscape"]` (its world's), and every job on it uses that landscape.
- **Flow / battle screen**: show a `GmPanel` (`bind(engine, story, campaign)`, `open()`, G) over the battle for a human GM; its `story_events` may include `twist_revealed` (already narrated by the battle screen) and dialogue lines (show the `DialogueView`).
- **Net**: a human GM on a remote machine needs its story actions accepted as the "gm" seat by `StorySession` (today remote seats can never act as the GM); everyone else keeps getting `StoryView` views.
- **Menus**: a "Human GM" campaign option (`campaign.options.human_gm`), which turns on the GM tools in the hub.
