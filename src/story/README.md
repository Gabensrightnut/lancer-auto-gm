# src/story: dialogue, the campaign loop, downtime, out-of-mech play

Everything between battles. All of it is data-driven (`data/game/story/`, `data/game/npcs/`)
and follows the core book. Page numbers are the free core book ("Core p.N").

## How LANCER handles life out of the mech (what this is built on)

- **No money.** Gear comes from licenses: every pilot has GMS, and each License Level (one per
  mission finished, win or lose) gives a license rank to spend on a frame license (rank II
  unlocks the frame) (Core p.18, p.31). Mechs are printed: with 10 quiet hours somewhere secure
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
| `story_data.gd` | `StoryData.lint()`: checks every scene, effect, condition, pool, trigger and reserve id (run by the tests). |
| `ui/` | `DialogueView` (portrait cards, speech bubble, choices, votes, log), `Portrait` (drawn placeholder faces with expressions), `StoryCheckPopup` (instant roll, one big number, breakdown on hover), `DowntimePanel`, `LevelUpPanel`. |

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
- Choosing to die instead of going Down and Out (Core p.49) isn't offered yet; cloning and
  coming back (Core p.83) isn't built.

## Asks for other sessions

- **Main / campaign**: give `Campaign` a `story` field instead of `story_flags["_story"]`; add
  `options.dialogue_choice` ("speaker"/"vote"), `options.allow_heroic_push`,
  `options.long_downtime` to the host settings UI.
- **Rules engine**: reserves that change battles (Ammo, Redundant repair, Smart ammo, Boosted
  servos, Jump jets, Deployable shield, Bombardment, Reinforcements, Accuracy) as effects on a
  unit at mission setup; pilot armor/HP from pilot gear in `UnitFactory.build_pilot`.
- **Net**: route story actions (`StoryEngine.submit`) through the host like battle actions, send
  story events to clients, and relay hub walking positions to `HubScene.set_avatar_position()`.
- **Menus / builder**: talent, license and core bonus picks waiting in
  `story.pending_picks[pilot]`; the pilot gear picker (`ui_requested` "pilot_gear"); portraits
  read `pilot["look"]` when the portrait builder exists.
