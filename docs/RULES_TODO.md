# Rules to confirm

Rules the code currently assumes but that haven't been checked against the core book yet.
When one is confirmed, fix the code if needed, add the book reference, and move it to
"Confirmed". Any difference from Lancer Tactics goes in DESIGN.md's Rule differences table
for the user to decide.

## Open

| Rule | Current assumption | Where in code |
|---|---|---|
| Square grid diagonals | Diagonal step = 1 space (Chebyshev distance), 8 neighbors | `square_grid.gd` |
| Hex footprints for big mechs | Size 2 = 3-hex triangle, Size 3 = 7-hex flower | `hex_grid.gd` |
| Big mechs on uneven ground | Not decided; `BattleMap.footprint_ground` reports heights, rules must decide | `battle_map.gd` |
| Cover rules (hard/soft, size of obstacle vs. target) | Not implemented yet | rules engine |
| Line of sight in 3D (elevation, size) | Not implemented yet | rules engine |
| High ground | No general bonus assumed | rules engine |
| Square grid range/area templates (blast, burst, cone, line) | Not implemented yet | rules engine |

## Confirmed (from lancer-data rule text)

| Rule | Source |
|---|---|
| Size 1/2 and Size 1 occupy one space; Size = spaces per side | glossary: Size |
| Jammed: can't use comms, attack (except Improvised/Grapple/Ram), react, or take/benefit from tech actions | statuses: Jammed |
| Hidden: can't be targeted, no engagement, enemies know approximate location; removed by attacking, forcing saves, reactions, Boost, losing cover | statuses: Hidden |
| Engaged: +1 Difficulty on ranged attacks; moving into engagement with equal or larger Size stops movement | statuses: Engaged |
| Falling: 3 AP kinetic per 3 spaces, max 9; counts as involuntary movement | glossary: Falling/Fall Damage |
| Flight: move up to Speed in any direction, in a straight line; must move 1+ space per turn or fall | glossary: Flight/Hover |
| Jumping and climbing: climbing costs double (half speed); vertical jump = Size spaces up | glossary: Jumping and Climbing |
| Blast/Burst: cover and line of sight from the blast center / the character | glossary: Blast, Burst |
| Accuracy/Difficulty: cancel 1:1, roll d6s, keep highest | core rules (implemented in `dice.gd`) |
