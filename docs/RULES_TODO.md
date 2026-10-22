# Rules to confirm

Rules the code assumes but the core book doesn't settle. Checked against the LANCER core
book (free version, `local/books/core.txt`, never committed); page references are
"Core p.N". When one is settled, fix the code if needed, add the reference, and move it to
"Confirmed". Any difference from Lancer Tactics goes in DESIGN.md's Rule differences table
for the user to decide. Code that depends on a row here is marked `PROVISIONAL`.

## Table rulings (the book allows more than one reading)

Each reading is supported; the table picks (a "table rules" screen from
`RulesQueries.rulings()`, or when it first comes up: actions are refused with the ruling id,
or paused mid-action with a `ruling_needed` event, until `set_ruling` answers). The campaign
keeps the choices. An AI GM answers with the suggested reading and logs it. Code:
`src/core/rules/rulings.gd`.

| Ruling id | Question | Readings (suggested first) | Book |
|---|---|---|---|
| `big_mech_uneven_ground` | Can a Size 2+ mech stand partly over lower ground? | forbid / allow | p.59, 62 silent |
| `climb_cost` | Cost of a step up or down | 1 + 2 per level / 2 per level, step included | p.63 |
| `flight_difficult` | Do flyers pay for difficult terrain below? | ignore / pay | p.62, 63 |
| `distance_3d` | Range, Threat, Sensors when heights differ | spaces in any direction / along the ground | p.62, 63, 64 |
| `heat_overflow` | Heat that carries over after overheating | beyond Cap + 1 / beyond Cap | p.81 |
| `unforced_save_target` | Flyer's Agility save after structure/stress damage | 10 / the damager's Save Target | p.13, 63 |
| `explosion_save_target` | Reactor explosion Agility save | the mech's Save Target / 10 | p.72, 81 |
| `npc_brace` | Can NPCs Brace? | no / yes | p.73 (no NPC rules in the free book) |
| `overwatch_area_weapons` | Overwatch with Blast/Burst/Cone/Line weapons | no / yes, aimed at the mover | p.64, 73 |
| `slowed_jump` | Can a Slowed character jump? | no / yes | p.63, 78 |
| `teleport_move_cost` | Movement a teleporting move uses | the whole move / 1 space | p.63 |
| `prone_ignore_difficult` | Does "ignore difficult terrain" cancel Prone's extra cost? | cancels / still double | p.77 |
| `eject_distance` | Where an ejecting pilot lands | exactly 6 in a line / anywhere within 6 | p.71 |

## Engine geometry (consistent with the book, which only describes a flat tabletop)

| Topic | How the engine does it | Where |
|---|---|---|
| Hex footprints | Size 2 = 3-hex triangle, Size 3 = 7-hex flower: N spaces across (p.59, 79: "N spaces on all sides") | `hex_grid.gd` |
| Line of sight | Lines between the middles of the spaces a character fills (plus the top of its head); terrain and wrecks block, characters don't (p.65, 66) | `sight.gd` |
| Cover in 3D | Flanking (p.66) uses lines from the attacker's spaces to the target's spaces or the top of its head; the soft-cover line runs center to center; a column's "size" is its height above the target's base; attackers shoot over cover no taller than themselves unless it's also next to the target | `sight.gd` |
| Soft cover zones | A column tagged `soft_cover` (smoke, foliage) is soft cover over its whole height | `sight.gd` |
| Dangerous terrain type | The map says which hazard: `dangerous` = kinetic, plus `dangerous_energy` / `dangerous_explosive` / `dangerous_burn` ("depending on the hazard", p.62) | `combat.gd` |
| Area templates | Cone widens evenly from 1 to X; templates are flat and catch characters within X levels of the origin; Line/Cone start at the user's space nearest the aim (or a point in Range, p.64); characters out of line of sight of the origin aren't hit unless Arcing/Seeking; one damage roll, a crit rolls the extra dice once | `areas.gd` |
| Jump geometry | Horizontal jumps keep their height (crossing pits and lower ground) and land on the highest ground at or below; vertical jumps rise max(1, Size) (p.63) | `close_combat.gd` |
| Reaction prompts | Player units are asked; AI seats answer with `Reactions.suggested_answer` | `reactions.gd`, `src/gm/ai_director.gd` |
| Eject flight | The pilot flies, so nothing on the way blocks it; it must land in a free space | `pilot_actions.gd` |

## Still open

| Rule | Current state | Where in code |
|---|---|---|
| Prepare triggers | Only movement triggers so far (a character moves adjacent / within a range); the book allows any "When X, then Y" (p.72) | `pilot_actions.gd`, `reactions.gd` |
| After-attack moves | Taken right away, on your own turn only; the Skirmisher talent's "before" option and its use after Overwatch aren't supported yet | `move_actions.gd`, `effects.gd` |
| Multi-character grapples | Sizes add up on each side (p.69): not supported, only two-character grapples | `close_combat.gd` |
| Mines | A mine goes off after the triggering move resolves (the mover isn't stopped); detecting and disarming mines (Systems checks) aren't automated yet | `abilities.gd` |
| Deployables as cover | Solid deployed objects (type Deployable/Object) are hard cover like terrain; drones and mines aren't | `sight.gd` |
| Drones and engagement | Drones don't engage or get Engaged | `combat.gd`, `movement.gd` |
| Manticore Unstable System | "At the end of its next turn" counted on the pilot's turns inside the wreck | `combat.gd`, `turn_rules.gd` |
| Minotaur Invert Cockpit | Eject without Impaired and a free Dismount 1/round are automated; the free Mount (taken by the pilot) isn't yet | `frame_effects.json` |
| Balor Scouring Swarm | "Characters of its choice" read as every hostile character | `effects.gd` |
| Bonus damage on attacks without damage | Bonus damage (p.67) is added only when the weapon itself deals damage, so Ram and Grapple never carry it | `attacks.gd` |
| Death's Head Neurolink | The engine rerolls the first ranged attack of the round only when it missed (rerolling a hit can't help) | `attacks.gd` |
| Monarch Seeking Payload | Always used when a Launcher attacks a Locked On target (it only ever helps); Brace isn't offered, as the damage can't be reduced | `attacks.gd` |
| Pegasus average damage | The player asks for it per attack (`"average_damage": true`); dice are averaged up, (sides + 1) / 2 each, which matches the trait's table | `attacks.gd` |
| Raleigh M35 Mjolnir | Its own rule (fire as a free action 1/round when you reload) isn't automated; with the core active and no rounds chambered it deals 0 | `attacks.gd`, `effects.gd` |
| Frame trait readings | Tortuga Sentinel counts Overwatch as a reaction attack; Blast Plating resists all damage types from area attacks; Vlad's core resistance applies to attackers within range 3; Shrike Armor damage comes before the attack roll; Kai Bioplating jumps up to Speed across, half Speed up; Iskander's range is measured at each move | `data/game/frame_effects.json`, `gear_effects.json` |

## Movement audit (Core p.62-63, 77-78 and lancer-data text)

Only rule text grants movement; a frame's look never does (a mech that looks like it floats
still pays for difficult terrain unless a rule says otherwise). Tests:
`tests/unit/test_rules_movement*.gd`.

| Source | Rule | Status |
|---|---|---|
| Core p.62 | Standard move, splitting, adjacency, obstruction by Size, allies never obstruct, mechs pass pilots, engagement stop, provoking, Disengage | automated |
| Core p.62 | Involuntary movement: straight line, no reactions/engagement, blocked by obstructions (passes smaller characters, can't end in occupied spaces) | automated |
| Core p.62 | Difficult terrain (x2), dangerous terrain (Engineering check, once per round) | automated |
| Core p.62 | Lifting and dragging (Slowed / Immobilized) | not yet |
| Core p.63 | Jumping, climbing (half speed), falling (10 per round, 3 AP per 3, max 9) | automated |
| Core p.63 | Flight: straight line, ignores obstructions, immune to Prone, must move or fall, falls if Immobilized/Stunned, Agility save, 10-space ceiling; Hover | automated |
| Core p.63 | Teleportation | automated |
| Core p.63 | Zero-g / underwater (Slowed without propulsion, can't fall, can fly) | not yet |
| Core p.77-78 | Prone (Slowed, difficult, stand up), Slowed (only the standard move), Immobilized (no voluntary movement), Stunned, Engaged, Hidden (Boost reveals) | automated |
| Core p.69 | Grapple: smaller is Immobilized and dragged along; no Boost | automated (same-Size contest not yet) |
| Everest core | Boost as a free action 1/turn | automated |
| Blackbeard | Lock/Kill: Boost while grappling | automated; Grapple Cable (range 5, pulled adjacent) and core not yet |
| Drake, Barbarossa | Heavy Frame: not pushed/pulled/knocked Prone/back by smaller | automated; Drake core (Immobilized, immune to involuntary movement) not yet |
| Nelson | Skirmisher: 1 space after attacking, ignores engagement, no reactions; core: 4 spaces | automated |
| Tortuga core | Threat 3 for ranged weapons, an extra Overwatch, Overwatch hits Immobilize | automated |
| Dusk Wing | Hover | automated; core (hologram teleport) not yet |
| Mourning Cloak core | Teleport on Boost and standard move | automated; Blinkspace Jump not yet |
| Swallowtail | Integrated Cloak (Invisible if it didn't move) | automated |
| Iskander core | Damage on hostile non-standard movement | automated |
| Minotaur | Localized Maze (hostiles can't pass through its space and always stop when Engaged with it) | automated |
| Black Witch, Balor, Barbarossa, Goblin, Hydra, Death's Head, Lancaster cores | Difficult zones, Immobilize, Apocalypse Die reset on moving, riding a host, drones | not yet |
| Bulwark Mods | Ignore difficult terrain | automated |
| High-Stress Mag Clamps | Climb at normal speed | automated (wall-walking and falling when knocked Prone not yet) |
| Type-I Flight System | Count any movement as flying, Size+1 heat on turns flown | automated |
| Rapid Burst Jump Jet System | Fly when Boosting, land or fall | automated |
| Flicker Field Projector | Invisible against the next attack after a standard move or Boost | automated |
| Reinforced Cabling, Ramjet, Singularity Motivator, FADE Cloak, Ferrous Lash, Beckoner, Metafold Carver, Mimic Mesh, Puppetmaster, Cable Winch, MULE Harness, Webjaw Snare, Caltrop Launcher, Perimeter Command Plate, Grounding Charges, Flak Launcher, Tesseract, Interdiction Field, H0R_OS upgrades, Hunter Logic Suite, Mesmer Charges, Viral Logic Suite, Siege Stabilizers, Retractable Profile, HyperDense Armor, deployable mines/drones | Activated systems, deployables or choices | not yet (need system activation / deployables) |
| Weapons | Impaler Nailgun (Immobilize), Magnetic Cannon / Gravity Gun / Nanobot Whip (pull), Fold Knife (teleport on crit), Assault Cannon / Leviathan spin-up (Slowed), Pinaka (Slowed) | not yet (on-hit effects and profiles) |
| Talents | Skirmisher II (2 spaces after a Skirmish) | automated (after only, own turn) |
| Talents | Ace I (+1 Agility while flying) | automated; Ace II-III, Hunter, Infiltrator III, Juggernaut, Brawler, Brutal, Siege Specialist, Stormbringer, Hacker, Heavy Gunner, Crack Shot, Duelist, Vanguard, Grease Monkey | not yet |
| Core bonuses | Integrated Nerveweave (+2 Boost), All-Theater Movement Suite, Kai Bioplating, Fomorian Frame, Ghostweave (Invisible on own turn) | automated (Ghostweave's "stays Invisible if you only moved, hid or Boosted" not yet) |
| Pilot gear | Mobility Hardsuit (fly, land by end of turn) | automated |
| EVA Module | Fly and not Slowed in zero-g | not yet (no zero-g) |

## Activated abilities and deployables

Every action in lancer-data (systems, weapons, core systems, unautomated traits, talents,
NPC features) is an ability used with `activate`; costs, once-per-system-per-turn, Protocols,
Limited, X/turn, X/round, 1/scene, Recharge and lockouts are automated. What an ability does
is automated only where `data/game/activation_effects.json` (or frame core ops) encodes it:
now Crack Shot's Steady Aim, Lancaster Combat Repair, Monarch's missile core, Death's Head
Mark for Death, Tokugawa Overclock, the Pegasus omnigun. Everything
else is handed to the table as text (`manual_effect`). Deployables, drones and mines deploy,
take damage and are destroyed or recalled.

## Not implemented yet

NPC templates and multiple activations, weapon profile choice, mod effects, frame traits and core systems
marked "manual" in `data/game/frame_effects.json`, talents (beyond unlocking talent gear),
Jockey and Reload (p.75), pilot armor and gear, zero-g
(p.63), lifting and dragging (p.62), dragging wrecks, objects as attack targets (p.68),
overshield sources, Scan's other two options, the same-Size grapple contest, Engineering
retries against a meltdown, rest and Full Repair (p.82), unlicensed mechs (p.74: Impaired
and Slowed), NHP control (p.75).

## Confirmed

| Rule | Source |
|---|---|
| Square grid: diagonal moves are adjacent moves; adjacency includes diagonal and vertical | Core p.62 |
| Bonus damage: melee/ranged attacks only; kinetic, explosive or energy (kinetic by default or one of the weapon's types); halved when the attack targets more than one character; rolled twice on a crit | Core p.64, 67 |
| Integrated mounts: always fitted, can't be destroyed, removed or modified | Core p.32 |
| Size N = N spaces on each side and N high; under 1 rounds up; Size 1/2 and 1 share one space | Core p.59, 79 |
| Turn order: players first; sides alternate; leftovers act in turn; the side that didn't take the last turn starts the next round | Core p.60 |
| Two quick or one full action plus a standard move; no repeating an action except free actions and reactions; Quick Tech repeats with different options | Core p.61, 68, 69 |
| Standard move can be split around actions, which must fully resolve first | Core p.62 |
| Obstruction: same Size or larger blocks; smaller can be passed; allies never obstruct; no ending in an occupied space; mechs pass unmounted pilots | Core p.62, 74 |
| Engaged: +1 Difficulty on ranged attacks; becoming Engaged by an equal-or-larger hostile stops the move; further moves while Engaged don't stop | Core p.62 |
| Starting a move in a hostile's THREAT can trigger Overwatch; Disengage avoids reactions and engagement | Core p.62, 71, 73 |
| Involuntary movement: straight line, no reactions or engagement, blocked by obstructions | Core p.62 |
| Difficult terrain costs 2 per space; dangerous terrain: Engineering check or 5 damage, once per round | Core p.62 |
| Climbing is half speed; jumping (half speed horizontal, Size up vertical); ending a jump mid-air falls at the end of the move | Core p.63 |
| Falling: starts at the end of the current turn, then at the end of each of the faller's turns, 10 spaces per round, 3 AP kinetic per 3 spaces, max 9 | Core p.63 |
| Teleportation: free space in range, start and end on a surface you can move on, ignores obstructions/LOS/engagement, no reactions, counts as 1 space, Immobilized stops it, occupied destination fails | Core p.63 |
| Flight: Speed in any direction, straight line, ignores obstructions if physically possible, immune to Prone; must move or fall; falls if Immobilized/Stunned; Agility save after structure/stress damage; more than 10 above any surface: only move/Boost, no reactions; hover | Core p.63 |
| Critical hits: 20+ on melee/ranged, damage dice rolled twice keeping the best | Core p.64 |
| Range and Threat measured from any edge; Threat 1 by default | Core p.64, 73 |
| Area patterns: one attack roll per target, damage rolled once; Blast cover/LOS from its center; Burst from the user, who isn't affected; Cone starts 1 wide, X wide at the end | Core p.64 |
| Melee attacks and tech attacks ignore cover; ranged attacks: soft +1, hard +2 Difficulty | Core p.64 |
| Line of sight: a line to some part of the target; Arcing ignores LOS but not cover; Seeking ignores both | Core p.65 |
| Invisible: 50% miss before the roll; can always Hide | Core p.65 |
| Cover: hard only if adjacent and the cover is at least the target's Size, and not flanked; obscured by non-adjacent hard cover = soft; center-to-center line test for soft; no stacking; characters only grant cover with Guardian | Core p.66 |
| Damage order: increases (Exposed), Armor (once per source), then Resistance; Armor and AP; burn ignores Armor; heat isn't damage but Resistance applies | Core p.67 |
| Always round up | Core p.12 |
| Characters without a Heat Cap (Biological, drones) take energy damage instead of heat | Core p.67, 74 |
| Immunity ignores the damage/effect entirely | Core p.68 |
| "Until the end of your next turn" means the next turn, even if applied during your turn | Core p.68, 77 |
| Actions: Boost, Grapple, Hide, Quick Tech (Bolster, Lock On, Scan, Invade/Fragment Signal), Ram, Search, Skirmish, Barrage, Disengage, Full Tech, Improvised Attack, Stabilize, Boot Up, Mount/Dismount (full), Eject (quick), Prepare, Self-Destruct, Shut Down, Overcharge (1, 1d3, 1d6, 1d6+4) | Core p.69-73 |
| Reactions: each once until the start of your next turn; one reaction per turn; Brace and Overwatch | Core p.61, 73 |
| Free actions only on your turn; Protocols only at the start of a turn, once per turn | Core p.61, 73 |
| Contested checks: highest wins, ties go to whoever started the contest; checks succeed on 10+ | Core p.13 |
| Pilots: HP 6 + Grit, Evasion 10, E-Defense 10, Size 1/2, Speed 4; add Grit to attacks and saves; Biological (immune to tech except Lock On and Scan); don't engage or obstruct mechs; pilot actions; actions shared with the mech | Core p.74, 76 |
| Statuses and conditions (Danger Zone, Down and Out, Engaged, Exposed, Hidden, Invisible, Prone, Shut Down, Immobilized, Impaired, Jammed, Lock On, Shredded, Slowed, Stunned) | Core p.77-78 |
| Structure: at 0 HP, 1 structure, structure check, HP to full, then the excess; 0 structure destroys; Structure Damage table | Core p.80 |
| Overheating: over the cap, 1 stress, overheating check, clear heat, then the excess; 0 stress melts down at the end of the next turn; Overheating table | Core p.81 |
| Reactor meltdown: pilot killed, Burst 2, Agility save or 4d6 explosive (half on success), no wreck | Core p.81 |
| Destroyed mechs are wreckage: hard cover, difficult terrain | Core p.82 |
| Mounts: Main, Heavy, Aux/Aux, Main/Aux (Main + Aux or two Aux), Flex (one Main or two Aux); Superheavy needs a Heavy mount plus one other | Core p.32 |
| SP = frame + Grit + 1 per 2 Systems; Grit = half LL rounded up | Core p.33, 78 |
| Mech skill bonuses: Grit to HP/Save Target/SP/attacks; Hull +2 HP, +1 Repair Cap per 2; Agility +1 Evasion, +1 Speed per 2; Systems +1 E-Def and Tech Attack, +1 SP per 2; Engineering +1 Heat Cap, +1 Limited use per 2 | Core p.34-35 |
| Licenses: +1 rank per LL up to 12, ranks I-III in order (so ranks add up to at most LL), rank II unlocks the frame; GMS and the Everest always available | Core p.31 |
| Same-Size grapples: contested Hull at the start of a turn, winner counts as larger | Core p.69 |
| A destroyed mech's pilot can be targeted and may exit as normal | Core p.74, 80 |
| Line/Cone/Burst with a listed Range: origin within that Range and line of sight | Core p.64 |
| Core system: usually once per mission; Full Repair recovers it | Core p.32, 82 |
| High ground: no general rule (only some talents mention it) | Core (no rule found) |
