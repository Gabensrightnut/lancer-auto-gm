# Rules to confirm

Rules the code currently assumes but that haven't been checked against the core book yet.
When one is confirmed, fix the code if needed, add the book reference, and move it to
"Confirmed". Any difference from Lancer Tactics goes in DESIGN.md's Rule differences table
for the user to decide. Code that depends on a row here is marked `PROVISIONAL`.

## Open

| Rule | Current assumption | Where in code |
|---|---|---|
| Square grid diagonals | Diagonal step = 1 space (Chebyshev distance), 8 neighbors | `square_grid.gd` |
| Hex footprints for big mechs | Size 2 = 3-hex triangle, Size 3 = 7-hex flower | `hex_grid.gd` |
| Big mechs on uneven ground | Table ruling `big_mech_uneven_ground` ("allow" / "forbid"); asked the first time a move needs it | `movement.gd`, `move_actions.gd` |
| Turn order | Sides alternate activations; the side chosen at `start_combat` picks first every round; when one side runs out, the other side's units act in a row | `turn_rules.gd` |
| Splitting the standard move | Allowed: move, act, move the rest | `move_actions.gd` (Move) |
| Climbing cost per step | A step that goes up or down d levels costs 1 + 2d; going down costs the same as up; no free "small step"; no height limit | `movement.gd` |
| Moving through characters | Allies can be passed through but not stopped on; hostile characters and deployables block | `movement.gd` |
| Flight cost and terrain | Flight costs max(ground distance, height change); flying ignores difficult terrain; a straight line follows the grid line | `movement.gd` |
| Distance in 3D | Larger of ground distance and height gap between the two bodies; used for range, threat, Sensors and adjacency (engagement) | `sight.gd` |
| Character height | A character fills Size levels (rounded up to 1) above its footprint | `sight.gd`, `movement.gd` |
| Line of sight in 3D | Clear straight line from any sample point of the attacker (middle of each level it fills, top of its head) to any of the target's; only solid terrain blocks; characters don't | `sight.gd` |
| Hard cover | +2 Difficulty when solid terrain within 1 space of the target hides at least half of its height from the attacker while some of it is visible; terrain further away gives no cover | `sight.gd` |
| Soft cover | +1 Difficulty when the target is in, or every clear line to it passes through, a column tagged `soft_cover` (whole column above the ground); hard and soft don't stack | `sight.gd` |
| Cover and tech attacks | Cover doesn't apply to tech attacks (only ranged attacks, per Fight/Thrown text) | `attacks.gd` |
| Engagement and Hidden | Two characters are Engaged only if adjacent and neither is Hidden | `combat.gd` |
| Halving | Resistance/Brace halving rounds the damage taken up | `combat.gd` |
| Armor with several damage types | Armor is subtracted once per hit, from the damage types in listed order | `combat.gd` |
| Damage past 0 HP | Lost; HP resets to full after marking 1 structure | `combat.gd` |
| Unforced checks and saves | Succeed on 10+ (Direct Hit Hull check, meltdown/burn/dangerous Engineering checks, flyers' Agility save) | `combat.gd` |
| Falling distance | The whole fall happens at the end of the current turn | `combat.gd` |
| Reactor meltdown | The mech is destroyed; the explosion (as in Self Destruct: Burst 2, 4d6 explosive) isn't applied yet; no Engineering retry yet | `combat.gd` |
| Dangerous terrain damage type | Kinetic unless the column is also tagged `dangerous_energy` / `dangerous_explosive` / `dangerous_burn` | `combat.gd` |
| Reactions | Each reaction once per round, refreshed at the start of the unit's turn | `reactions.gd` |
| Brace timing | Taken automatically by the unit's `set_brace_policy` (`on_structure`: when the hit would take its last HP) until the engine can pause for the defender | `attacks.gd`, `reactions.gd` |
| Search ties | A tie keeps the target Hidden | `system_actions.gd` |
| "Variable" damage type | Treated as Kinetic until damage-type choice exists | `combat.gd` |
| Reliable on a miss | Uses the weapon's first damage type | `attacks.gd` |
| Pilot stat bonuses | HP + GRIT + 2/Hull; Repair Cap +1 per 2 Hull; Evasion +1/Agility; Speed +1 per 2 Agility; E-Defense and Tech Attack +1/Systems; Heat Cap +1/Engineering; Limited +1 per 2 Engineering; Save Target + GRIT | `unit_factory.gd`, `weapons.gd` |
| Mount capacities | Main and Heavy hold 1 weapon, Main/Aux holds Main + Aux, Aux/Aux holds 2 Aux, Flex holds 1 Main or 2 Aux (sizes that fit come from rules.json) | `unit_factory.gd` |
| License ranks | One license rank per License Level (ranks add up to at most LL); each license rank 1-3. Items unlock at their lancer-data `license_level` (frames at 2); talent gear needs its talent rank; gear with no license or talent (integrated weapons) can't be installed | `unit_factory.gd` |
| Superheavy mounting | A Superheavy weapon needs a Heavy mount plus one other mount left empty | `unit_factory.gd` |
| High ground | No general bonus assumed | rules engine |
| Square grid range/area templates (blast, burst, cone, line) | Not implemented yet: area weapons are refused with a reason | `attacks.gd` |

## Not implemented yet

Area attacks (Blast, Burst, Cone, Line), Overwatch and other reactions besides Brace (the
movement preview only warns which enemies could react), Ram, Grapple, Jump, Full Tech,
Bolster, Prepare, Eject, Self Destruct, Mount/Dismount, pilots on foot, deployables and
drones, system activations, NPC features/tiers/templates and multiple activations, Recharge,
choosing a weapon profile, mod and frame trait/core system effects, talents (beyond unlocking talent gear),
teleport, zero-g, lifting and dragging, bonus damage, overshield sources, Scan's other two
options (hidden information, public records).

## Confirmed (from lancer-data rule text)

| Rule | Source |
|---|---|
| Size 1/2 and Size 1 occupy one space; Size = spaces per side | glossary: Size |
| Jammed: can't use comms, attack (except Improvised/Grapple/Ram), react, or take/benefit from tech actions | statuses: Jammed |
| Hidden: can't be targeted, no engagement, enemies know approximate location; removed by attacking, forcing saves, reactions, Boost, losing cover | statuses: Hidden, actions: Hide |
| Hide: not Engaged, and out of enemies' line of sight, behind hard cover big enough to conceal you, fully inside soft cover, or Invisible | actions: Hide |
| Search: contested Systems vs Agility, target within Sensors | actions: Search |
| Engaged: +1 Difficulty on ranged attacks; moving into engagement with equal or larger Size stops movement and loses the rest | statuses: Engaged |
| Falling: 3 AP kinetic per 3 spaces, max 9; counts as involuntary movement | glossary: Falling/Fall Damage |
| Flight: up to Speed in any direction, in a straight line; must move 1+ space per turn or fall; Immobilized/Stunned flyers fall; Agility save after structure/stress damage; immune to Prone; Hover needn't move or go straight | glossary: Flight/Hover |
| Climbing costs double (half speed) | glossary: Jumping and Climbing |
| Difficult terrain: each space moved into costs 2 | glossary: Difficult Terrain |
| Dangerous terrain: Engineering check or 5 damage on entering (first time in a round) or ending the turn there, once per round | glossary: Dangerous Terrain |
| Involuntary movement: straight line, no engagement or reactions, blocked by obstructions | glossary: Involuntary Movement |
| Blast/Burst: cover and line of sight from the blast center / the character | glossary: Blast, Burst |
| Accuracy/Difficulty: cancel 1:1, roll d6s, keep highest | core rules (implemented in `dice.gd`) |
| Turn actions: standard move + 2 quick or 1 full; quick actions can't repeat except Quick Tech with different options or via Overcharge | actions: Move, Overcharge, Quick Tech |
| Overcharge: once per turn, extra quick action as a free action; heat 1, 1d3, 1d6, then 1d6+4 | actions: Overcharge, rules.json |
| Boost: quick action, at least 1 space up to Speed | actions: Boost |
| Skirmish (one weapon + different Aux on same mount, no Superheavy) and Barrage (two weapons or one Superheavy, + Aux per fired mount) | actions: Skirmish, Barrage |
| Ranged attacks are affected by cover; melee isn't (Thrown is) | actions: Fight, tags: Thrown |
| Critical hit: 20+ on melee/ranged; damage dice rolled twice, highest kept | glossary: Critical Hits |
| Damage order: increases (Exposed), Armor, then Resistance | glossary: Harm/Calculating Damage |
| Exposed doubles kinetic/explosive/energy; Shredded ignores Armor and Resistance | statuses: Exposed, Shredded |
| Heat over cap: 1 stress, clear all heat, overheating check; no heat cap means energy damage instead | glossary: Heat Capacity |
| 0 HP: 1 structure, HP resets, structure check; 0 structure/stress destroys | glossary: HP, Structure, Stress |
| Structure and Overheating tables (lowest d6 per point marked; two 1s worst) | tables.json |
| Burn: immediate damage ignoring Armor, marked; end of turn Engineering check clears or deals it again | glossary: Burn |
| Lock On: +1 Accuracy when consumed by a hostile attacker | statuses: Lock On, actions: Lock On |
| Invisible: 50% miss before the roll; Prone: +1 Accuracy, Slowed, difficult movement, stand up instead of standard move; Stunned: no actions, Evasion max 5, auto-fail Hull/Agility | statuses |
| Slowed: no Boost; Immobilized: no voluntary movement; Impaired: +1 Difficulty on attacks, checks, saves | statuses |
| Brace: resistance to the triggering hit, +1 Difficulty on other attacks and no reactions until end of next turn, next turn only one quick action | actions: Brace |
| Stabilize options; Shut Down / Boot Up; Scan; Invade + Fragment Signal | actions |
| Tags: Accurate, Inaccurate, AP, Reliable, Knockback, Loading, Limited, Ordnance, Smart (no E-Def counts as 8), Seeking, Arcing, Overkill, Heat (Self/Target), Burn, Threat (default 1) | tags.json, glossary: Threat |
| GRIT = half LL rounded up; SP = frame + GRIT + 1 per 2 Systems | glossary: GRIT, System Points |
| Max License Level 12 | rules.json: max_pilot_level |
