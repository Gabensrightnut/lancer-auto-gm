# Rules to confirm

Rules the code assumes but the core book doesn't settle. Checked against the LANCER core
book (free version, `local/books/core.txt`, never committed); page references are
"Core p.N". When one is settled, fix the code if needed, add the reference, and move it to
"Confirmed". Any difference from Lancer Tactics goes in DESIGN.md's Rule differences table
for the user to decide. Code that depends on a row here is marked `PROVISIONAL`.

## Open (the book doesn't say, or only says it for a flat tabletop)

| Rule | Current assumption | Where in code |
|---|---|---|
| Hex footprints for big mechs | Size 2 = 3-hex triangle, Size 3 = 7-hex flower. The book only says Size N is N spaces on each side (p.59, 79) | `hex_grid.gd` |
| Big mechs on uneven ground | Table ruling `big_mech_uneven_ground` ("allow" / "forbid"), asked the first time a move needs it | `movement.gd`, `move_actions.gd` |
| Climbing cost per step | Climbing is half speed (p.63); a step up or down d levels costs 1 + 2d; down costs the same as up; no height limit | `movement.gd` |
| Flight and difficult terrain | Flying ignores difficult terrain on the ground | `movement.gd` |
| Distance in 3D | Larger of ground distance and height gap; adjacency including vertical is confirmed (p.62), range/threat/sensors in 3D aren't spelled out | `sight.gd` |
| Line of sight sampling | Lines between the middles of the spaces a character fills (plus the top of its head); only terrain and wrecks block; characters don't (p.66: they never grant cover) | `sight.gd` |
| Cover geometry in 3D | The book's tests are for a flat map (p.66). Flanking uses lines from the attacker's spaces to the target's spaces or the top of its head; the soft-cover line runs between the centers of the two bodies; a column's terrain "size" is its height above the target's base; cover next to the attacker no taller than it is ignored unless it is also next to the target | `sight.gd` |
| Soft cover zones | A column tagged `soft_cover` (smoke, foliage) is soft cover over its whole height | `sight.gd` |
| Heat overflow | Over the cap, "the excess beyond what was required to exceed" (p.81) read as heat − (cap + 1) | `combat.gd` |
| Unforced saves | Saves nobody forces (flyers' Agility save after structure/stress damage, p.63) need 10+; forced saves use the forcer's Save Target (p.13) | `combat.gd` |
| Reactor explosion save | Agility save against the exploding mech's Save Target (p.72, 81 don't name one) | `pilots.gd` |
| Dangerous terrain damage type | "Depending on the hazard" (p.62): Kinetic unless the column is tagged `dangerous_energy` / `dangerous_explosive` / `dangerous_burn` | `combat.gd` |
| Reaction decisions | Player units are asked (engine pauses); GM/AI seats answer with `Reactions.suggested_answer`: take Overwatch and prepared actions, Brace when the hit would take the last HP | `reactions.gd`, `src/gm/ai_director.gd` |
| NPCs and Brace | NPCs can't Brace (lancer-data has NPC versions of Overwatch, Ram, Grapple, Stabilize, Improvised Attack but not of Brace); NPC rules aren't in the free book | `reactions.gd` |
| Overwatch weapons | Any weapon whose THREAT reaches the mover except Ordnance (tag), Superheavy (can't Skirmish, p.70) and area weapons | `reactions.gd` |
| Area templates | Cone width grows evenly from 1 to X; templates are flat and catch characters within X levels of the origin; Line/Cone start at the user's space nearest the aim; characters out of line of sight of the origin aren't hit (unless Arcing/Seeking); a crit on any target rolls the extra dice once. Line/Cone/Burst with a listed Range (origin within range, p.64) not supported yet | `areas.gd` |
| Grapple | Same-Size contest at the start of a turn (p.69) isn't automated: nobody is Immobilized; only two-character grapples | `close_combat.gd` |
| Jump | Horizontal: straight line at the jumper's height (crosses pits and lower ground, not taller terrain), lands on the highest ground at or below; vertical rises max(1, Size); Slowed and Prone can't jump | `close_combat.gd` |
| Prepare triggers | Only movement triggers so far (a character moves adjacent / within a range); the book allows any "When X, then Y" (p.72) | `pilot_actions.gd`, `reactions.gd` |
| Pilot of a destroyed mech | Climbs out into a free adjacent space ("you may still exit it as normal", p.80); the wreck stops protecting it (p.74) | `combat.gd`, `pilots.gd` |
| Eject | Lands in any free space within 6 (no straight-line or path check) | `pilot_actions.gd` |
| Self Destruct timing | "Within the following two rounds" read as your next turn (delay 1) or the one after (delay 2) | `pilot_actions.gd` |
| Frame trait readings | Tortuga Sentinel counts Overwatch as a reaction attack; Blast Plating resists all damage types from area attacks; Vlad's core resistance applies to attackers within range 3; Shrike Armor damage comes before the attack roll | `data/game/frame_effects.json` |
| Mech building limits | Each license rank 1-3, ranks add up to at most LL (p.31: +1 rank per LL, ranks bought in order) | `unit_factory.gd` |

## Not implemented yet

Deployables and drones, system activations (Activate), NPC templates and multiple
activations, Recharge, weapon profile choice, mod effects, frame traits and core systems
marked "manual" in `data/game/frame_effects.json`, talents (beyond unlocking talent gear),
bonus damage (p.67), Jockey and Reload (p.75), pilot armor and gear, teleport (p.63), zero-g
(p.63), lifting and dragging (p.62), dragging wrecks, objects as attack targets (p.68),
overshield sources, Scan's other two options, the same-Size grapple contest, Engineering
retries against a meltdown, rest and Full Repair (p.82), unlicensed mechs (p.74: Impaired
and Slowed), NHP control (p.75).

## Confirmed

| Rule | Source |
|---|---|
| Square grid: diagonal moves are adjacent moves; adjacency includes diagonal and vertical | Core p.62 |
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
| Licenses: +1 rank per LL up to 12, ranks I-III in order, rank II unlocks the frame; GMS and the Everest always available | Core p.31 |
| Core system: usually once per mission; Full Repair recovers it | Core p.32, 82 |
| High ground: no general rule (only some talents mention it) | Core (no rule found) |
