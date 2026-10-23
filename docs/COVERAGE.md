# Core-book coverage

What the rules engine handles from the core book (data/lancer-data). Made by
`tools/coverage_audit.gd` (see `src/core/rules/coverage.gd` for how each kind is counted);
`tests/unit/test_rules_coverage.gd` fails if a count drops below `data/game/coverage_floor.json`.
Partial = automated with a note for the table; manual = the table resolves it.

| Kind | Total | Automated | Partial | Manual |
|---|---|---|---|---|
| frame traits and core systems | 102 | 99 | 3 | 0 |
| mech systems | 124 | 105 | 18 | 1 |
| weapons | 85 | 84 | 1 | 0 |
| talent ranks | 87 | 66 | 10 | 11 |
| core bonuses | 30 | 30 | 0 | 0 |
| weapon mods | 8 | 8 | 0 | 0 |
| pilot gear | 37 | 36 | 0 | 1 |
| NPC features (placeholder pack) | 17 | 16 | 0 | 1 |

## Gaps

### frame traits and core systems

- Drake: Fortress (partial): Characters that get hard cover from the Drake or its cover sections also gain Immunity to Knockback, Prone and involuntary movement, and Blast Plating: the table applies that.
- Barbarossa: Apocalypse Rail (partial): The blast clouds (soft cover, burning ground), objects in the blast taking 20/40/100 AP, and regaining 1 CP if the rail wasn't fired by the end of the scene are left to the table.
- Sherman: Zone-Focus Mk IV SOLIDCORE (partial): Terrain hit by the ZF4 takes 10 AP energy per charge: the table applies that (objects and deployables are automated).

### mech systems

- COMP/CON-Class Assistant Unit (partial): The COMP/CON follows simple orders you give at the start of your turn; whoever controls the mech keeps to them.
- Personalizations (partial): Your personal mod can give +1 on a check if the GM agrees it helps.
- Reinforced Cabling (partial): Grapple Swing is params.swing on a standard move; securing yourself to a wall or ceiling is the table's.
- SEKHMET-Class NHP (partial): While SEKHMET drives, it moves toward the closest visible character and attacks it in melee; whoever controls the mech keeps to that.
- Aegis Shield Generator (partial): It only reduces attack damage here; damage from other sources is reduced at the table.
- Portable Bunker (partial): Attack the bunker as zone:<id> (40 HP, Evasion 5).
- Ramjet (partial): While it's on you must move your full Speed in straight lines; move that way yourself.
- “Roland” Chamber (partial): Roland Chamber is applied at the table.
- Webjaw Snare (partial): Set it off by moving over its space; the GM tracks snares on paths the game doesn't check.
- Tracking Bug (partial): Removing the bug takes the target an Engineering check as a quick action; resolve that at the table.
- OASIS Wall (partial): While it's on you can only move in straight lines, and nobody may end a turn inside the barrier; keep to that at the table.
- Lotus Projector (partial): It shows you HP, Evasion, E-Defense and heat of characters in its field; ask the GM for them.
- OSIRIS-Class NHP (partial): The First Gate (you control the target's next standard move) is played out at the table.
- SCYLLA-Class NHP (partial): The second trigger (a hostile attacking or using an object you chose) is the table's.
- Interdiction Field (partial): Only characters you choose can teleport inside the field; the GM checks that.
- Repulser Field (partial): You're immune to the mines it sets off; the GM undoes their effects on you.
- Tesseract (manual)
- Blinkshield (partial): Time flows differently inside, so characters inside and outside can't affect each other at all; the game blocks attacks, sight and movement across the edge.
- ASURA-Class NHP (partial): Taking one extra full action instead of two quick actions isn't supported: take the quick actions.

### weapons

- M35 Mjolnir (partial): Its free shot when you reload any weapon (1/round) is taken by hand.

### talent ranks

- Ace 3: Supersonic (manual)
- Bonded 3: Cover Me! (manual)
- Brawler 3: Knockout Blow (manual)
- Centimane 3: Tidal Suppression (partial): Tidal Suppression lets you pick the extra effect; the game uses Harrying Swarm (Impaired and Slowed). Ask your GM to swap it.
- Combined Arms 3: Storm of Violence (manual)
- Drone Commander 1: Shepherd (partial): The Shepherd Drone protocol is resolved at the table.
- Drone Commander 3: Invigorate (manual)
- Engineer 1: Prototype (partial): Your Full Repair choices go in the pilot record (engineer: type, damage type, the Limited roll).
- Engineer 2: Revision (partial): Stripped reactor shielding (2 heat for a Cone, Line, Blast or Burst attack) is the table's.
- Infiltrator 3: Mastermind (manual)
- Juggernaut 3: Unstoppable Force (manual)
- Leader 2: Open Channels (partial): Issue Command at the start of another player's turn: use issue_order then (the game allows it only on your turn for now).
- Leader 3: Inspiring Presence (partial): Spending a die to reduce damage by 1d6 is the table's; +1d6 bonus damage is params.leadership_damage.
- Nuclear Cavalier 3: Here, Catch! (manual)
- Siege Specialist 2: Impact (partial): Afterwards you're pushed 1 space in a direction of your choice; move yourself.
- Skirmisher 1: Integrated Chaff Launchers (partial): Forcing another character to make a save also ends the chaff; drop it yourself when that happens.
- Spotter 3: Bentham/Foucault Elimination (manual)
- Stormbringer 3: Torrent (manual)
- Technophile 1: Servant Fragment (partial): Install the Servant-Class NHP system to get its AI tag; how it acts alone is roleplay.
- Technophile 3: Enlightenment (partial): Unshackled NHPs treating you as significant is roleplay.
- Vanguard 3: Semper Vigilo (manual)

### pilot gear

- Sleeping Bag (manual)

### NPC features (placeholder pack)

- Field Patch (manual)
