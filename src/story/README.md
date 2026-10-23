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
| (fights in town) | Jobs with `in_town` (`defend_town` on the board, `standoff`, `trouble_followed`), every fight a conversation starts (it happens outside that NPC's building), and the hidden twist `jumped_in_town` put the battle in the hub. `MissionHooks.town_for(story, hook)` gives the hub's id, layout (`hub.spots`), culture, landscape, seed, the spot where it starts and whether the squad is on foot; `CampaignLoop.build_mission` passes it as the generator's `opts["town"]` and `mission.flavor["town"]`. |
| `house_rules_story.gd` / `economy.gd` | `StoryHouseRules`: the story's house rules (`house_rules.json`), the user's own ideas, all off by default and labelled "Your idea, not a book rule"; stored in `campaign.options.house_rules`, switched with the `house_rule` action (announced), `definitions()` for the settings page and the codex ("House rules" category). `Economy`: the tracked wallet (manna + each world's money, prices, mission pay, salvage), printer scarcity (wrecked mechs sit out until reprinted at a world with a printer), paid travel (independents pay passage), fight for it (a job instead of money), food and water (rations, hunger: +1 Difficulty, then harm). Actions `buy`, `sell_salvage`, `use_printer`, `restock`, `fight_for_it`. `ui/market_panel.gd` (B in the hub, only while one is on). Nothing shows while a rule is off; switching one on starts it cleanly (a starting wallet, three days of rations each). |
| `town_life.gd` | `TownLife`: doing things yourself in a hub (DESIGN.md section 11, `town_life.json`). A clock (dawn, day, evening, night; `wait`), where each person is at each time and where they sleep (role schedules; `npc.schedule` overrides), rooms with locks, things that belong to someone and are kept somewhere (`add_item`; each hub seeds the company rep's papers in the safe, the bartender's strongbox, the fixer's ledger). Actions `go`, `sneak`, `follow`, `pick_lock`, `break_in`, `pickpocket`, `take_out`, `take`, `slip_away`: narrative checks with the book's triggers (Core p.26-27); witnesses (who's scheduled there, the crowd by time of day), standing, bounty, NPC temper, the alarm and a fight on foot. Never offered as dialogue choices. |
| (conversation modes) | Every line says how it's heard: `mode` "talk" (face to face) or "radio" (comms, with a `channel`), from the node, the scene or the start ctx. `StorySettings.dialogue_view()` picks the pop-up (third person) or face to face (first person: the hub camera holds on the person's face; `set_expression` / `set_talking` called on the figure when it has them). Radio uses the comms frame (scanlines, static, signal flicker); a Jammed pilot (`Dialogue.is_jammed`, tracked from battle events) gets static and can't reply. Parley and enemy-commander barks are on the open channel. |
| `tones.gd` | `Tones`: no solution menus (DESIGN section 11). Every reply has a tone (courteous, warm, blunt, flatter, lie, push, insult, threaten, leave; from the scene or its tags, `tones.json`); it moves the NPC's temper (kept across visits, cools a point a day) and the conversation's patience (by personality). Out of patience they end it; at their limit someone armed draws and the fight starts in town on foot (`combat_requested`, a standoff), anyone else throws you out; walking away ends it calmly. Insult and push-your-luck replies are in every menu, outside the 6-reply cap. |
| `campaign_script.gd` | `CampaignScript`: the authored main campaign for AI-GM play (DESIGN.md section 11), `data/game/story/campaign/<id>.json`: "The Long Arrival" (`long_arrival`: 3 acts, 14 chapters, 18 branch points, 8 endings) and the pirate career "Dead Reckoning" (`dead_reckoning`: a prologue and 3 acts, 17 chapters, 18 branch points, 9 endings); all text in those files. `begin(story, campaign, engine, id)` starts one (`campaign.options.story_mode = "campaign"`). Each chapter is one mission plus the town play around it; flags set by conversations and by doing things in town decide each branch when the chapter ends (end of the downtime after its mission); the next chapter can move the squad to another world. Its people join the hub in place of generated ones, with their own schedules and things (Ione's key-codes in her safe). Finales differ in allies (units on your side, run by the AI as the `allies` seat), enemy mix, commander and place. With a human GM nothing here runs. | Script data can also: rename a world's hub buildings and rooms (`spot_names`, `room_names`: aboard a ship the office is the bridge and its back room the captain's quarters) and give it things (`hub_flags`: a flash vat); keep people out of the hub until a condition holds (`npcs.<id>.if`); reshape a chapter's job from what happened (`hook.variants`: a duel instead of a mutiny); carry a raid's `loot` (Plunder); open squad decisions from replies (effect `decision`, split into a fight); let the pilot with a grudge speak first (`speaker_agenda`, `{aggrieved}` in text); fix the story line at a later act (`line_act`); and react when a clone wakes (`clone_beats`, via `on_clone`).
| (boarding) | Jobs `seize_ship`, `rescue_crew`, `take_smuggler` and the travel fight `repel_boarders` (pirates board the transport: 14% on gate trips, 7% local; `options.travel_events` / `pirate_chance`; never in the main campaign) carry `hook.boarding = {kind: seize/rescue/smuggler/defend, map: docked/enemy_ship/own_ship}` and the starship landscape; `build_mission` passes it as `opts.boarding` and `mission.flavor.boarding`. The Long Arrival boards the colony ship in two chapters. |
| `origin.gd` | `Origin`: a pilot's origin (`origins.json`): homeworld (city, desert, ice, ocean, jungle, spacer, orbital, frontier, Union Core, mining, agri), upbringing, former employer (GMS, IPS-N, SSC, HORUS, HA, Union Navy, DoJ/HR...), specialty, up to 5 perks. `pilot["origin"]`, set with `set_origin`. Its tags widen what the background covers for the book's +1 Accuracy (Core p.20; `NarrativeCheck.background_invoke`), never a second bonus. `combat_perks(pilot)` -> [{id, effect, manufacturer}] for the rules engine's Origin perks house rule. `food_likes` for the food house rule. |
| `inventory.gd` | `Inventory`: each pilot's own money and pack (`inventory.json`, `story.flags._inv`), the squad fund (`Economy.wallet(story)`) and stash (`"squad"`). Mission pay is split between pilots (`split_pay`; host `set_pay_split {shares}`); `fund_deposit`, `sell_item`, `pack_ration` / `unpack_ration`; trades `trade_offer {from, to, give, get}` → `trade_answer {trade, accept}` / `trade_cancel` (a gift goes straight across; nothing duplicates if the goods are gone). Players act for their AI squadmates. `view_for` / `trades_for`: a client sees only its own pilots' packs and its trades (StoryView). |
| `survival.gd` | `Survival`: food and water bars per pilot (food-and-water house rule): run down with the clock (`pass_hours`, from missions, waits, repairs, shifts), auto-eat (`set_auto_eat`, Settings), manual `eat {pilot, item}`, warnings (Hungry, Parched, Starving, Dehydrated), +1 Difficulty on skill checks while hungry, no combat penalties; `need` cut by implants under `hr_cybernetics`, floor 1/4 a day. |
| `troops.gd` | `Troops`: the squad's own troops when it has men of its own (`campaign.options.troops`, or a script's `troops.if`): squads of ten (`troops.json`) whose losses carry over (`after_battle`), deployed as allied units (`deploy`, once the soldier squad template exists). Recruited by talking: extra replies to a bartender, fixer or faction agent (`options_for`), and effects `recruit {source, free, name}` / `reinforce`; manna with `hr_wallet`, else a favour owed; refused on bad standing. Upkeep: a ration per squad per day in `Economy.eat` (food-and-water rule); unfed squads lose morale, desert, and side with a pilot with a grudge (`loyalties`, for the story; split-vote arena fights are only the players' mechs). |
| `soldiers.gd` | `Soldiers`: every hub's garrison (`soldiers.json`, per culture; a campaign world's own via `worlds.<id>.garrison`): guards by day, a night watch, patrols on rounds, as TownLife people (role `soldier`, own schedules, the `soldier` scene) and witnesses who raise the alarm. A crime that turns into a fight (`combat_requested` spec `crime`) turns the garrison out: `hook.soldiers` {faction, squads, template}; chapters can put soldier squads in a fight too (`hook.soldiers`). CampaignLoop adds them as enemy units once the rules session's soldier squad template (`unit_template`) exists. |
| `repair_bay.gd` | `RepairBay`: mech damage lasts between missions (`record` after each mission, `apply` when the next is built: HP, structure, stress, Repairs, CORE power, Limited charges, destroyed gear; a wrecked mech sits out) until a Full Repair (`full_repair {}`, Core p.82) at a hub's repair bay (the gantries, a hangar, engineering; E in the hub). It needs somewhere secure (a hub, or `story.flags._safe_point` set by the flow at a region `safe_point` with no enemies), not with the alarm up; the 10 hours pass on the clock, rations are eaten (food-and-water house rule), and the next fight has one regrouped enemy. |
| `ship_life.gd` | `ShipLife`: life aboard a ship that is home to a whole society (campaign script `society`). Renown with the people aboard (effect `renown`, conditions `renown` / `unrest`, mirrored as standing with them); the captain quietly cuts it down at each mark (`quells`: takes credit, sidelines, reassigns), which raises unrest; `ship_work {job, pilot}`: one shift per pilot per chapter (a narrative check; pay with `hr_wallet`, else a favor as a reserve); side jobs for the people aboard on the board (`side_jobs`, renown on a win). |
| `plunder.gd` | `Plunder`: raid loot and the squad's own ship. A job's `loot` {name, value, reserve}: with `hr_wallet` it's salvage to sell, with `hr_own_ship` loot to spend on upgrades (`buy_upgrade {slot}`: hull, engines, printer, cargo, boarding gear; costs in `house_rules.json` `own_ship`), with both off the book's reserve. Upgrades: fewer boardings on the way, a printer aboard, bigger hauls, a boarding crew on boarding jobs. |
| `decisions.gd` | `Decisions`: story-changing squad decisions (effect `decision`). Each human `decide`s accept or decline; AI squadmates follow their human (owner seat, else the lead human) and never vote, in decisions, dialogue votes or replies (an AI speaker's reply is picked by its human). Agreement: the choice stands. A split: `party_split` {sides: {accept: [seats], decline: [seats]}} for the flow's player-vs-player fight, then `split_resolved` {winner}. `gathering(events)`: events that pull a roaming squad together (chapter starts, decisions, splits, the finale, boots on the ground; anything with `gather: true`). |
| `world_state.gd` | `WorldState`: what the squad did to each place (`consequences.json`, `story.flags._world`). Destroying infrastructure, sabotage and fights in town set facts; a mission or so later they become consequences (water or power short, shortages, damage) with a line, the squad's reaction and a job to make it right (`make_it_right_*`, `rebuild_town`). Effect `world`, condition `{world: fact, eq}`. |
| `cloning.gd` | `Cloning`: death and cloning (Core p.83-84, `cloning.json`): genetic templates in cities (facsimile, sanctioned) or on ships (flash, unlawful) via `store_template`; after a death, go there and `wake_clone` between missions: all LL kept (house rule `hr_clone_ll_penalty` takes one), memory gap from the mission they died on, quirks (our own list), a shifted upbringing; the next clone starts growing. `add_second_pilot` / `set_active_pilot`: one extra pilot per player (a close relation), not after a death. |
| `agendas.gd` | `Agendas`: a pilot's own grudge or goal (`story.flags._agendas`): e.g. short rations while their mech is wrecked (food and printer house rules) builds a grievance. Effect `agenda`, condition `{agenda: kind}`. |
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
- **Flow / battle screen** (done): a `GmPanel` over the battle (G) when the GM seat is at that screen; a `twist_revealed` from the GM tools is narrated in the battle by the host (`BattleSession.gm_reveal_twist`), and the AI GM no longer reveals the twist itself.
- **Net** (done): a friend who joins as the GM (only when the host set up a human GM) acts as "gm" in `StorySession` and gets `StoryView.view_for(..., "gm")` (secrets and twists); everyone else keeps the players' view.
- **Menus** (done): "Who is the GM" (The AI / A person here / A friend online) on the new campaign form and in the lobby: `campaign.options.human_gm` and `gm_where` ("local" / "remote"); Join online has "Join as the GM".
- **World/maps**: build the battle from `opts["town"]` when it's set (the hub's own layout, starting at `town.at`); shape in `MissionHooks.town_for`.
- **Menus (house rules registry, src/content/house_rules.gd)**: list `StoryHouseRules.definitions()` ({id, name, source, label, text}); the on/off state is `campaign.options.house_rules[id]`; switch one by submitting `{"type": "house_rule", "seat": "gm", "params": {"id": id, "on": bool}}` to the story engine so it starts cleanly and is announced (event `house_rule_changed`).
- **Menus**: a "Main campaign: The Long Arrival" start (AI GM) that calls `CampaignScript.begin(story, campaign, engine)` after session zero, next to the procedural campaign and the tutorial.
- **World/maps**: build boarding battles from `opts.boarding` (`map`: "docked" two ships with a boarding tube, "enemy_ship" an enemy interior, "own_ship" the squad's transport decks).
- **Menus / builder**: an origin step in the pilot creator: homeworld, upbringing, former employer, specialty, up to 5 perks from `Origin.data()`; submit `{"type": "set_origin", "params": {"pilot", "origin"}}` (refused with a reason if invalid).
- **Rules engine**: the "Origin perks" house rule reads `Origin.combat_perks(pilot)`: `weak_spots` = `{type: accuracy_vs_manufacturer, value: 1}` against frames of `manufacturer` (GMS, IPS-N, SSC, HORUS, HA).
- **Flow / menus (exploring and PvP)**: after each story submit, `Decisions.gathering(events)` lists the events that should pull the squad together (fast-travel everyone to the scene); on `party_split` run the player-vs-player battle with `sides.accept` vs `sides.decline`, then submit `split_resolved {winner}`.
- **Menus**: a second-pilot option per player (`add_second_pilot`, `set_active_pilot`), and the choice to make a new character instead of waking a clone.
