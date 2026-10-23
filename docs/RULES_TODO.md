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
| `vehicle_size` | How big is a parked car or truck? | Size 1/2 / Size 1 | p.59 lists vehicles (APCs) as Size 2, not cars; p.66 cover by Size |
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
| `manticore_inferno_self` | Is the Manticore caught in its own charge-die inferno? | yes (a Burst that isn't an attack includes the user) / no | p.64, Manticore core |
| `hologram_blast_targets` | Dusk Wing Hologram Teleport explosions: who is caught? | hostiles / every character but the Dusk Wing | p.64, Dusk Wing core |
| `basilisk_failed_save` | Gorgon Basilisk: does a failed save stop the attack? | no attack / attack goes ahead | p.77, Gorgon core |
| `extremesun_turns` | Extreme sun: 1d6 heat "at the end of a turn" if not in shade. Whose turn? | each character at the end of its own turn / everyone out of shade at the end of every turn | Environments (lancer-data environments.json) |

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
| When a beaten enemy commander offers terms (story parley) | PROVISIONAL reading of Core p.60's "no questions as to the outcome": from round 2, once a share of the enemy force is down (the GM's fight length dial: a third on Short, half on Standard, two thirds on Long) or the commander is badly hurt with half that share down. The book leaves the moment to the GM | `src/story/rivals.gd` `enemy_losing`, `data/game/gm/presets.json` `fight_lengths` |
| Arriving mid-fight | A unit joining a fight in progress (`join_combat`) takes turns from the next round and its arrival provokes nothing. PROVISIONAL: the free core book gives no arrival timing; this follows the alternating activations | `turn_actions.gd` |
| Prepare triggers | "When X, then Y" (p.72): X = a character moves adjacent / within a range, takes an action (optionally of listed types), or attacks (anyone, me, or an ally). PROVISIONAL: action triggers go off after that action resolves; reactions as triggers aren't offered | `pilot_actions.gd`, `reactions.gd` |
| After-attack moves | Taken right away, on your own turn only; the Skirmisher talent's "before" option and its use after Overwatch aren't supported yet | `move_actions.gd`, `effects.gd` |
| Multi-character grapples | A character can Grapple someone already grappling and joins the other side; Sizes add up per side and the smaller side is Immobilized (p.69). PROVISIONAL: each grappler is tied to the one it grabbed; whoever breaks adjacency or lets go leaves, and the rest keep grappling while both sides have someone; only a grappler's own partner is dragged | `close_combat.gd` |
| Mines | A mine goes off after the triggering move resolves (the mover isn't stopped); `detect_mines` (quick, Systems check: every hostile mine within Sensors is detected; PROVISIONAL: one check for all) and `disarm_mine` (quick, adjacent, Systems check; a failure sets it off) | `abilities.gd` |
| Deployables as cover | Solid deployed objects (type Deployable/Object) are hard cover like terrain; drones and mines aren't | `sight.gd` |
| Drones and engagement | Drones don't engage or get Engaged | `combat.gd`, `movement.gd` |
| Pilot-scale spaces | A fight on foot inside a building (InteriorBattle) uses 1.5 m per space; walls two levels high (hard cover, block sight, breakable), counters and tables one level (cover by height), doors keep their lock levels; ground floor only. PROVISIONAL table ruling: the book uses the same grid rules for pilots (Size 1/2) as for mechs but fixes no real-world scale | `interior_battle.gd` `SPACE_M` |
| Parked vehicles | Cars and trucks along streets (tag `vehicle`) are objects: Evasion 5, 10 HP per Size, breakable (Core p.68). Their Size is the table's `vehicle_size` ruling (suggested Size 1/2: the book lists vehicles like APCs as Size 2, p.59, but not cars). Cover by Size (p.66): hard cover for characters that Size or smaller next to it, soft cover (like a low wall) for bigger ones behind it; a character shoots over a car no bigger than itself. Movement by Size (p.62): it obstructs characters its Size or smaller, bigger ones pass through, nobody stops on it. PROVISIONAL: it doesn't block line of sight; attacking a car isn't wired (its column has no sections) | `sight.gd`, `movement.gd`, `terrain_gen.gd` `_parked_vehicles` |
| Manticore Unstable System | "At the end of its next turn" counted on the pilot's turns inside the wreck | `combat.gd`, `turn_rules.gd` |
| Minotaur Invert Cockpit | Eject without Impaired; the first Mount or Dismount each round is free (`free_via: "invert_cockpit"`; one free use per round covers either) | `frame_effects.json` |
| Balor Scouring Swarm | "Characters of its choice" read as every hostile character | `effects.gd` |
| Bonus damage on attacks without damage | Bonus damage (p.67) is added only when the weapon itself deals damage, so Ram and Grapple never carry it | `attacks.gd` |
| Death's Head Neurolink | The engine rerolls the first ranged attack of the round only when it missed (rerolling a hit can't help) | `attacks.gd` |
| Monarch Seeking Payload | Always used when a Launcher attacks a Locked On target (it only ever helps); Brace isn't offered, as the damage can't be reduced | `attacks.gd` |
| Pegasus average damage | The player asks for it per attack (`"average_damage": true`); dice are averaged up, (sides + 1) / 2 each, which matches the trait's table | `attacks.gd` |
| Raleigh M35 Mjolnir | Its own rule (fire as a free action 1/round when you reload) isn't automated; with the core active and no rounds chambered it deals 0 | `attacks.gd`, `effects.gd` |
| Trait reactions | Mag Parry is rolled after a hit (the attack "would deal" kinetic damage) and not when the target is Invisible; Warp Shield counts as the Saladin's reaction; Tactical Simulation protects allies, not the Swallowtail itself, and its teleport is optional (answer with `to`); Reactive Code resolves before the Invade's own heat and conditions; Defensive Pulse's reroll on a miss is left to the table | `trait_reactions.gd` |
| Core system readings | Iskander's Assault Launcher covers grenades (range 15) and mines, 1/round between them; Balor Hive Frenzy's soft cover counts for the Balor and adjacent allies against ranged attacks; Lancaster Supercharger lasts the scene as the book says (lancer-data says until the start of your next turn); Minotaur Maze's first save is at the end of the target's next turn, +1 Accuracy per earlier failed try; Iskander's extra mines each use a charge of the same system; the Apocalypse Die notices a move (even involuntary), Stunned or Jammed at the start of the Barbarossa's turn, which gives the same result as resetting at once; Napoleon's Aegis allows only the listed actions plus free actions and protocols | `frame_systems.gd` |
| Zones | Mag Field: a ranged kinetic/explosive shot is stopped if exactly one of attacker and target is inside, or if its line crosses the field; all mechs and NPCs count as metal; the Immobilized lasts until the field ends; the Black Witch is affected by its own field; resumed attacks hit allies too, damage rolled once. Genghis cloud: Burst 3 from its own spaces; the 2 burn and 2 heat only during the smoke phase. Holograms: "move adjacent" counts any space on the path next to a hologram | `zones.gd` |
| Rest (p.82) | The `rest` action works outside combat: heat, statuses and conditions clear, the pilot regains half HP (rounded up), and Repairs are spent as listed; only a wrecked mech takes Repairs from others. Hydra's drone choice and the Manticore's Castigation State are made at a rest; a Full Repair (between missions) is the campaign's job | `rest_actions.gd` |
| Goblin Symbiosis | "Your Systems, E-Defense and Tech Attack" read as the Systems skill and the two stats; the host uses whichever is better. "Conditions" are the conditions (Core p.77), not other statuses. Using the Goblin's systems (gear) through the host isn't automated. On detaching the Goblin goes to the first free space next to the host | `frame_systems.gd` |
| Arriving late or spent (GM) | The story's briefing can have the squad take the long way (arrived late) or come through a hard crossing (1 harm each, arrived spent). The book gives neither a battle effect, so the GM only narrates them when combat starts; a late squad meets the mission's twist one round sooner. Players still act first (Core p.60). Options for the user: no effect at all, or the enemy acts first when late | `src/gm/gm_twist.gd` |
| Twist timing (GM) | The book says a mission's goal can change when new information comes to light (p.43) but not when; the AI GM reveals a hook's twist at round 3 (halfway through a timed mission), or earlier at the first mech/NPC destroyed (Control: the first zone scored) | `src/gm/gm_twist.gd` |
| Talent choices | Spotter Particularize keeps the better of the two rolls; Relentless counts misses across turns until a hit; "first attack on your turn" talents count attack rolls made on the unit's own turn | `talent_rules.gd` |
| Gear choices | Reactor Stabilizer rerolls an overheating check unless it already rolled the best result (5+); the Stasis Bolt's contested roll is d20 + Grit against the attack's total; the Autoloader Drone is 1/round per drone for any adjacent character | `gear_systems.gd` |
| AIs (Core p.107) | Any mech with the AI tag can hand over as a protocol (`ai_control`, or the system's own protocol); the AI gets a fresh set of actions and loses the pilot's talents, core bonuses and pilot gear; control comes back at the start of a later turn. Cascade d20 on every structure and overheating check (not COMP/CONs or UNCLE): the mech becomes GM-controlled until Shut Down. Also automated: COMP/CON, SEKHMET (melee only, free melee Skirmish 1/round, +1d6 on melee crits), TLALOC (a missed attack retargets the nearest valid hostile), ATHENA, OSIRIS gates 2-4, SCYLLA (attacks on you or allies within 3), NOAH | Where SEKHMET or a COMP/CON moves and whom it attacks is up to whoever controls the mech; OSIRIS First Gate; the host must let the pilot's seat send Shut Down while the mech is GM-controlled |
| Vision and barriers | Blinded = line of sight only to adjacent spaces (Flash Mine, Shock Wreath); a Flash Grenade stops sight out of its blast; Hardlight and Blinkshield stop sight, attacks and tech across their edge (Blinkshield also movement; characters partly inside are moved out); the OASIS Wall trail gives adjacent characters hard cover and Resistance to energy | `zones.gd` |
| Riders and cables | MULE Harness: climb on (`climb_on`, quick), share the space, soft cover, thrown off Prone by Prone/Stunned/Immobilized/destroyed, climb down by moving. Expanded Compartment: `board` / `disembark` (full actions, like Mount/Dismount); a passenger can't be targeted and can only climb out; Transfer Control hands the mech to the passenger's seat (Impaired, Slowed). Cable Winch: voluntary moves must end within 5 spaces of the other end; `cut_cable` is a melee roll (d20 + Grit) against Evasion 10 | `riders.gd` |
| Gear readings | Armor-Lock's "can't fail" covers Hull and Agility saves and checks, contested ones included; Argonaut Shield's half damage to the bearer is rounded up and uses the same damage types; Aegis Shield Generator reduces attack damage (not heat or burn) and uses the owner's reaction; Roland Chamber's next Loading attack is used up hit or miss | `gear_systems.gd` |
| Cascade timing (GM) | The book lets the pilot Shut Down a cascading mech but not when; the host asks the pilot's seat at the start of each of the mech's turns (Shut Down, or let the NHP act as the GM's NPC). An AI-played or absent pilot Shuts Down | `src/gm/nhp_ai.gd`, `src/net/net_host.gd` |
| SEKHMET and COMP/CON driving (GM) | SEKHMET: "closest visible character" read as the nearest present, non-Hidden, non-Invisible mech, NPC or pilot (deployables don't count), any side; it moves (then Boosts) toward it and attacks with its first melee weapon, plus its free melee Skirmish. COMP/CON: basic commands offered as Defend yourself, Hold this area, Protect <ally>, Attack <enemy>; the Range 50 / means-to-communicate limit isn't checked | `src/gm/nhp_ai.gd` |
| Escort and Extraction (GM) | The Objective is a Size 1 object (the book allows 1/2 to 2; `missions.json` objective_size). Escort's text doesn't say how its Objective moves, so it moves like Extraction's: with a character who started their turn next to it, on their standard move, to the free space next to them closest to where it was. Extracting is a free action that ends the unit's turn ("at the end of their turn"). If every PC has extracted without the Objective, the GM ends the mission as an enemy win at once (nobody is left to bring it, so the round-limit result is certain) | `src/gm/sitrep_actions.gd`, `src/gm/mission.gd` |
| Recon (GM) | The True Control Zone is picked with the mission's seeded generator RNG; surveying is a full action for a PC inside a zone and only their side learns the answer; at the end of round 6 the squad needs PCs, and no enemies, in it. The GM's own forces know which zone it is | `src/gm/sitrep_actions.gd`, `src/gm/mission.gd` |
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
| Talents | Ace I (+1 Agility while flying), Skirmisher II | automated; see "Gear automation status" for the rest |
| Core bonuses | Integrated Nerveweave (+2 Boost), All-Theater Movement Suite, Kai Bioplating, Fomorian Frame, Ghostweave (Invisible on own turn) | automated (Ghostweave's "stays Invisible if you only moved, hid or Boosted" not yet); the rest are under "Gear automation status" |
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

## Gear automation status

| Gear | Automated | Left to the table |
|---|---|---|
| GMS weapons (all 21) | every tag they use (Accurate, AP, Arcing, Inaccurate, Loading, Ordnance, Overkill, Reliable, Smart, Thrown, Heat Self, Knockback) | - |
| GMS systems | HEX Charges (Frag Grenade, Explosive Mine), Smoke Charges (grenade and mine), Jericho Cover, Custom Paint Job, Personalizations (+2 HP), Stable Structure, Turret Drones, Type-3 Projected Shield, both flight systems, Manipulators (no rules effect) | EVA Module in zero-g (the ocean world environment honours it), Personalizations' +1 on checks the GM agrees it helps |
| IPS-N weapons | on-hit/on-crit saves and conditions (Concussion Missiles, Power Knuckles, Catalytic Hammer, Impaler), Chain Axe crit Shred, Bristlecrown, Cutter vs objects, Combat Drill Overkill bonus, Impact Lance line, Assault Cannon/Leviathan Spin-Up | - |
| IPS-N systems | Muscle Netting (Size for Ram/Grapple), Drag Down, Argonaut Shield, Aegis Shield Generator, Portable Bunker (hard cover/Resistance from outside once unfolded; 40 HP, Evasion 5: attack it as `zone:<id>`), Restock Drone (any adjacent ally uses it, once it primes at the end of your turn), Whitewash, Aceso Stabilizer, Bulwark Mods, Armor-Lock Plating, Ramjet (+2 Boost, melee Knockback 2), Thermal Grenade, Breaching Charge (detonated as a quick action; 30 AP to objects and terrain in the burst), Roland Chamber, Siege Ram, HyperDense Armor, Cable Winch towing (`drag` the cabled character from up to 5) and climbing at normal speed, Grapple Swing (`swing` on a standard move), Webjaw Snare, Caltrop Launcher, Charged Stake | Ramjet's straight-line moves; Grapple Swing's securing to vertical surfaces |
| SSC weapons | Magnetic Cannon pull, Veil Rifle (allies get soft cover instead), Burst Launcher crit, Sharanga (two targets, damage rolled once), Pinaka (two blasts, `aims`; `delayed`: lands at the end of the next round for 3d6, the user is Slowed; not if the user is destroyed first), Fold Knife crit teleport (`fold_to`), Variable Sword crit bonus | - |
| SSC systems | Ferrous Lash (`toward`), ICEOUT Drone, Black ICE, High-Stress Mag Clamps, Tracking Bug, Core Siphon, Kinetic Compensator, Neurospike (Shrike Code, Mirage), Flicker Field, StunCrown, Reactive Weave (Invisible; the brace answer's `move_to` is its free move), Active Camouflage, Javelin Rockets, Hunter Logic Suite (Stalk Prey; Terrify's Impaired and no moving closer), Singularity Motivator (reaction with `to`), Lotus Projector (no Hiding or Invisible in it), Markerlight (no soft cover; the crit reaction), Retractable Profile, LB/OC Cloaking Field, Magnetic Shield (`aim`: the first space of the line; an obstruction, soft cover and Resistance to kinetic/explosive behind it), Perimeter Command Plate (`Print Perimeter Command Plate`: `aim`, `setting` repulse/attract; 20 HP as `zone:<id>`; PROVISIONAL: Repulse pushes away from the plate; allies' free fly is the table's), FADE Cloak (intangible: no attacks, tech or damage either way, passes through characters, 1d6 each turn) | FADE Cloak passing through terrain walls; which characters count as "partly metal" for the Magnetic Shield (all of them here); Tracking Bug's removal check, the Lotus Projector's information |
| HORUS weapons | Nanobot Whip crit pull, Ghoul Nexus damage type (`damage_type`), Arc Projector chain (`chain`), Autogun (fired by its free action), Autopod (Autonomous Assault: 3 kinetic, automatic), Daisy Cutter (soft cover in the cone until the end of your next turn), Plasma Thrower (flames in 3 spaces, `flames` to choose), Fuel Rod Gun (clears 4 heat when you attack with it), Latch Drone (Lancaster: an allied mech, vs Evasion 8, `repair_from`), Mimic Gun (3d20 Ranges cycling each turn, 1 + half its Range kinetic, "Provoke the Mimic Gun" rerolls), Ghast Nexus (deployed drone: Range and line of sight from it; destroyed: unusable until repaired), Vorpal Gun (Snicker-Snack after an attack damages an ally) | Mimic Gun counting as every ranged weapon type for talents (it uses its listed type) |
| HORUS systems | Hive Drone, Scanner Swarm, Swarm Body, Eject Power Cores, Sentinel Drone, //SCORPION (on missed tech attacks), Puppetmaster Electropulse, Tempest Drone, Beckoner, Smite and Sear, EMP Pulse, Lightning Generator, Mesmer Mine, Viral Logic Suite, Chains of Prometheus and Excommunicate (`shake_off`), Metafold Carver, Interdiction Field (not its teleport rule), Hunter Lock, Eye of HORUS, Mesmer Beacon (only voluntary moves toward you), Assassin Drone (deploy with `aim`: its Blast 2 area; Area Denial on entering or starting to move there), Mimic Mesh (Battlefield Awareness before attacks and tech on the ally; PROVISIONAL: doesn't use up your reaction), Guide the Flock (`moves`), Annihilation Nexus secondary attack (`center`: you or a drone), SISYPHUS (Bend Probability; Probabilistic Cannibalism offered only when X or Y would flip a d20 roll your way), Puppet System (`toward`), Law of Blades (Predator/Prey: `forced_target`, `forced_weapon`; Slave Systems: `forced_action`, `forced_params`), Metahook (tech through the ally's Sensors and line of sight; the ally uses your Systems; heat and conditions shared), Monitor Module (1d3 charges; half-damage Skirmish when the ally is attacked next to it), H0R_OS II Ideal Image (`dispel_construct`, full action) and False Idol (deploy within Sensors, `target` you or an ally; a fooled attacker keeps its action and can't target that character until the end of its next turn) and III (Dimensional Emblems: 3 one-space constructs, 2 heat to whoever passes through, `params.cells` to place them; Celestial Shackles: `shackle_return`, `break_shackles`) | -; SISYPHUS keeps both numbers for each use (PROVISIONAL: the text doesn't say a number is spent); Puppet System moves in a straight line toward `toward`; //SCORPION after saves against tech effects |
| HA weapons | Siege Cannon modes and other profiled weapons (`profile`), Plasma Thrower Cone/Line (`pattern`), Shatterhead (no Difficulty), Tachyon Lance backblast, Annihilator secondary attacks, Gravity Gun (Hull saves in the blast, 1d6 energy and the pull) | - |
| HA systems | Siege Stabilizers (toggle), Autoloader Drone, Flak Launcher, External Ammo Feed, Explosive Vents, Napalm Grenade, Auto-Cooler, AGNI, Gravity Grenade, Grounding Mine (detonated as a quick action), Repulser Field, Clamp Bombs, Stasis Bolt (Interdiction Point), Stasis Generator, ENCLAVE shield (Blinkfield Intervention), Flash Anchor, Reactor Stabilizer, Redundant Systems Upgrade, ASURA (two extra quick actions), External Batteries, Deep Well Heat Sink, LUCIFER, Plasma Gauntlet, Tesseract (Spread Focus: a zero-g zone, `aim`; Pinpoint Focus: 6 up, Immobilized, sinks harmlessly), Stasis Barrier (a line like the Magnetic Shield; 4+ on 1d6 consumes attacks on characters behind it), Roller Grenade (`aim`: the direction; it rolls over terrain), Bouncing Mine (only flyers; the burst goes off around the flyer), HAVOK Mine (the line runs toward the mover) | Tesseract's 6-space height and floating objects; ASURA's "one extra full action" option; the Repulser's immunity to its own mines |
| Talents | Ace 1-2 (`ace_burst` before a Boost while flying), Bonded 1-2 (pilot `bondmate`: the partner's unit id; Intercede suggested only when the hit would take the bondmate down), Brawler 1-2, Brutal 1-3, Centimane 1-2 (3 uses Harrying Swarm), Combined Arms 1-2, Crack Shot 1-3 (`zero_in`; `called_shot`: head/leg/body, default leg), Drone Commander 1-2 (+5 HP; not the Shepherd protocol; the pulse hits hostiles, one roll), Duelist 1-3 (Blademaster Dice: Parry/Deflect reactions, `feint`, `trip`, `duelist_strike`; the dice don't yet clear at the end of a scene), Executioner 1-3 (Backswing Cut: the `backswing` free action after the hit; the miss reroll goes to `reroll_target` or the nearest hostile), Exemplar 1-3 (mark on the first attack within 3, `no_mark` to skip; Valiant Aid reroll; Overwatch when the mark attacks near you, after that attack; `duel` with the marking attack: ends when a duelist is destroyed, scene end is the table's), Heavy Gunner 1-3 (Covering Fire, its reaction shot after the target moves past 1 space, the pin on a hit, two `targets`), Grease Monkey 1-3 (rest `supply_drop`, once per mission), Gunslinger 1-3 (Return Fire, Gunslinger Die), Hacker 1-3 (the three Invade options; `fix_hack` undoes them; Last Argument of Kings), Hunter 1-3 (`lunge` on an Auxiliary melee attack; `hunter_throw` after a melee hit), Infiltrator 1-2 (Prowl), Juggernaut 1-2 (Kinetic Mass Transfer on Ram knockback), Nuclear Cavalier 1-2 (3 is talent gear), Siege Specialist 1-3 (Jackhammer Round on objects and terrain; not your own 1-space push; Collateral Damage, `collateral: false` to skip), Skirmisher 1-3, Spotter 1-2 (the free Lock On picks the character Locked On this turn, else the nearest hostile; the stat reveal is the HUD's), Stormbringer 1-2 (`storm`: lightning/thunder on a Launcher hit), Tactician 1-3 (Flank), Vanguard 1-2, Walking Armory 1-3 (`ammo`: thumper/shock/mag, hellfire/jager/sabot for 2 charges; a crit is free) | Ace 3, Bonded 3,  Drone Commander 3, Engineer 1-3 (the prototype is built from pilot.engineer; shielding option is the table's), Infiltrator 3, Juggernaut 3, Leader 2 (Issue Command as a reaction), Spotter 3, Stormbringer 3, Technophile 1 and 3 (roleplay parts), Vanguard 3, Hellfire's bonus damage as burn; Jager's save falls on the attack's target; Hunter's Lunge follows the ground path (no flying over obstacles); Covering Fire's shot comes after the move that takes the target past 1 space, not at any point during it; Skirmisher 1's "forcing a save" also ends the chaff |
| Weapon mods | All eight: added tags and range (Stabilizer, Nanocomposite, Paracausal: damage can't be reduced), Thermal Charge (`thermal_charge` on a hit), UNCLE (free attack at +2 Difficulty, weapon locked until your next turn), Throughbolt Rounds (`throughbolt`: aim point), Shock Wreath (quick action after a hit), Phase-Ready (`phase`). A mount's mod goes on its first weapon unless `mod_slot` says otherwise | Phase-Ready's "know the rough location"; Shock Wreath's line-of-sight limit |
| Core bonuses | All 31: stats (Reinforced Frame, Sloped Plating, Full Subjectivity Sync, Disbelief, Open Door, Superior by Design), Accuracy (Gyges, Kai, Disbelief, Armory-Sculpted), reach (Gyges, Neurolink Targeting), mounts (Improved Armament, Mount Retrofitting, Integrated Weapon), choices in `pilot.core_bonus_choices` (Auto-Stabilizing Hardpoints: mount index; Overpower Caliber: weapon key; Mount Retrofitting: mount index), Universal Compatibility (automatic on core power), Briareos, Titanomachy, the five Lessons, Adaptive Reactor (`adaptive` on Stabilize), Heatfall, Integrated Ammo Feeds, Stasis Shielding, Fomorian, flight and movement ones | Open Door's heat only follows saves from systems, weapons and mines the game resolves; Transubstantiation's "nearest free space" when it comes back |
| Data corrections | Explosive Mine deals 2d6 as Core p.120 says (lancer-data has 3d6): `activation_effects.json` "deploy:" entries override deployable data | - |

## NPCs

NPCs are built from NPC class data in the lancer-data / COMP/CON format (npc_classes,
npc_features, npc_templates): from a loaded content pack, or from our placeholder pack
(`data/game/npc_placeholder_pack.json`, not official) when no pack has NPCs. Code:
`src/content/npc_builder.gd`, `UnitFactory.build_npc_class(db, id, class_id, tier, opts)`.

| Rule | Current state | Where in code |
|---|---|---|
| NPC rules source | The free core book has no NPC rules; the NPC numbers come from the pack's data. Recharge follows lancer-data's tag text (one 1d6 roll at the start of each of the NPC's turns recharges everything at or under it) | `abilities.gd` |
| Multiple activations (PROVISIONAL) | An NPC with N activations (class stats.activations plus template bonuses, e.g. Elite) takes N turns per round, each a normal turn in the sides' alternation; Recharge rolls and reactions refresh at the start of each of them. Whether an NPC may take two turns in a row isn't restricted | `turn_rules.gd` |
| NPC features | Weapons (tiered damage, attack bonus, accuracy, tags), tech features (rolled with their own attack bonus), systems with activation tags, Recharge and Limited, and stat bonuses/overrides (templates) work for any pack. Effect text is applied by the table unless `data/game/npc_feature_effects.json` encodes the feature | `npc_builder.gd` |
| Placeholder Elite/Ultra | Our stand-ins: Elite +1 Structure, +1 Stress, 2 activations; Ultra +2/+2, 3 activations. The official templates replace them when an NPC pack is loaded | `data/game/npc_placeholder_pack.json` |

### Soldiers (squads and single humans on foot)

Code: `src/content/soldiers.gd`, `data/game/soldiers.json`, `Unit.on_foot()`. PROVISIONAL rows:

| Assumption | Why |
|---|---|
| Soldier numbers (HP, Grit by tier, defenses, squad Size 1 with 10 HP for 10 people) are placeholders | The book's Human and Squad NPC templates are in the full core book's GM section; our free copy has no NPC data. Check against the full book or an NPC pack. |
| Soldiers use the book's rules for unmounted characters: Grit to attacks and saves, Biological (tech immunity except Lock On and Scan, heat becomes energy damage), attack with Fight, take only pilots' actions | Core p.74 ("unmounted characters"); the Fight rule says "characters on foot" (p.64) |
| Soldiers don't Engage mechs and don't block them, at any Size | Core p.74 says this of "pilots"; we read it for all people on foot. A squad that blocks mechs would be a table ruling. |
| Soldiers can't repair or otherwise aid mechs | Core p.74: unmounted characters can't aid mechs |
| Allied soldiers activate like allied NPCs: the players choose when one goes, and its own AI picks what it does | Core p.60 (players nominate a player or allied NPC); the book doesn't say who decides an allied NPC's actions, so the user's choice is that nobody orders soldiers |
| "Men left" for squads is ceil(HP / max HP x 10), for the look only | Not a book rule; no rules effect |
| Patch (pilot gear) works on a squad, restoring half its maximum HP | The gear says "an adjacent pilot"; we read it as any person on foot |

### Open-ended talents: the literal reading, and the alternatives

The user asked for the most literal reading of each, with the other readings listed for the
table. Implemented ones are marked (code); the rest are played at the table this way.

| Talent | Literal reading (used) | Alternatives |
|---|---|---|
| Leader 1-3 (code) | `issue_order`: 1/turn on your turn, a die to an allied PC holding none; the ally spends it on any one roll it says follows the order (`leadership`), or for +1d6 bonus damage at rank 3 (`leadership_damage`). A rest returns 1 die if you have none | the GM judges which actions "directly follow" the order; dice also usable on skill checks |
| Engineer (code) | the prototype is an integrated Main weapon set at each Full Repair (pilot.engineer); Limited is the 1d6+2 / 2d6 roll the campaign records | roll Limited at each mission start; let the prototype take mods |
| Technophile (code) | Student/Enlightenment NHP Assistance rerolls the first failed mech check or save each round; Enlightenment's AI never cascades | reroll only when the player asks (a reaction prompt) |
| Ace 2 (code) | `ace_burst`: while flying, roll 1d6 before the Boost; it may go that much further; heat = half, rounded up | roll after choosing the destination |
| Grease Monkey 3 (code) | at a rest, once per mission: allied mechs regain 1 use of each Limited item and 1 Structure | only characters at the same rest |
| Bonded 3 | when someone in your line of sight attacks your bondmate, you may spend your Overwatch: the attacker picks another target (your Overwatch is spent) or attacks anyway after your Overwatch attack resolves | the attacker loses the attack instead of retargeting |
| Ace 3, Spotter 3, Vanguard 3, Infiltrator 3, Stormbringer 3, Juggernaut 3, Drone Commander 3 | as written, resolved at the table (each needs movement or targeting the player chooses mid-action) | - |

## House rules (not book rules)

Switches in `state.house_rules` (`HouseRuleSwitches`, catalog in
`data/game/house_rules_engine.json`), flipped between actions with `set_house_rule`. Off by
default except the two Lancer Tactics options the user picked. Each card names its source.

| Id | Source | What it does |
|---|---|---|
| `lt_split_barrage` (on) | Lancer Tactics | Skirmish twice with different mounts, moving in between |
| `lt_brace_prompt` (on) | Lancer Tactics | Brace offered only on big hits |
| `lt_repeat_quick_tech` | Lancer Tactics | the same Quick Tech option twice |
| `hr_collapse_save` | Your idea | a section still standing after 5+ damage rolls 1d6 + Armor; 3 or less: it collapses |
| `hr_fall_stun` | Your idea | fall damage: Hull save (10+) or Stunned until the end of its next turn |
| `hr_brace_fall` | Your idea | reaction: halve fall damage |
| `hr_structure_no_stun` | Community (lancer-rules.carrd.co) | Direct Hit's Stun becomes Brace's penalties |
| `hr_hide_hard_cover` | Community (lancer-rules.carrd.co) | hard cover from everyone who sees you is enough to Hide and stay Hidden |
| `hr_npc_recharge_heat` | Community (Train Lightning) | NPC Recharge abilities cost 1 heat (4+/5+) or 2 (6+) |
| `hr_overheated` | Community (Train Lightning) | Exposed from overheating also blocks Heat (Self) and Overkill until Stabilize |
| `hr_garrisoned_buildings` (on) | Your idea | a building cell's ground storey is a room, entered only by its door face; a room space holds one Size 1+ unit alone, or two Size 1/2 units plus one squad; when the room's section is destroyed, everyone inside takes the book's falling damage for the building's height and is moved to the nearest free space (`garrison.gd`). Off: buildings are solid. Cover at windows is the book's (Core p.66), not part of the switch |
| `hr_origin_perks` | Your idea | former employer (`pilot.origin.former_employer`, a manufacturer id, or `employer` by name): +1 Accuracy on the first attack each scene against a frame from that manufacturer. NPC classes have no manufacturer, so it only meets player-built frames |

## Buildings, windows and collapses

Code: `src/core/rules/garrison.gd`, `sight.gd`, `movement.gd`, `terrain_damage.gd`. Map tags
are the world session's (`TerrainGen._building_interiors`): every building cell `interior`
(+ `storeys_N`), `window_<i>` on each outside face (i = the face's index in
`GridLayout.neighbors`), one cell per building `entrance` + `door_face_<i>`; optional
`name:<text>` for the collapse message. With the house rule on, a building cell's ground
storey is a room (`BattleMap.rooms_open`).

| Rule | Reading | Book |
|---|---|---|
| A unit at a window has hard cover (+2) and can shoot out through it | the window wall is hard cover it's adjacent to, and "a character in hard cover [who] could shoot over, through, or around the source of their cover" keeps its line of sight | Core p.66 |
| Flanking beats window cover | an attacker with a line totally clear of hard cover (from inside, through the doorway, from the side) gets no cover penalty | Core p.66 |
| Windows block movement | a window is part of a wall; nobody climbs through (PROVISIONAL: the book doesn't model windows) | - |
| Sight through windows | only lines with one end inside a room; a line doesn't pass clean through a building by two windows (PROVISIONAL) | - |
| Rooms of one building are open to each other | adjacent `interior` cells have no wall between them (the world tags no inner walls; PROVISIONAL) | - |
| Knockback into a building | walls and windows stop it like any obstruction; the door face lets it through (PROVISIONAL). Teleports into a room aren't wall-checked (no wall stops a teleport) | Core p.62 |
| Standing on a building that's destroyed | the book's falling rule: falling starts at the end of the current turn, 3 AP per 3 spaces, up to 9 | Core p.63 |
| Caught inside a collapse | house rule `hr_garrisoned_buildings`: damage as if they fell the building's height (the same numbers), then moved to the nearest free space | not in the book |

## Environments

`state.environments` (lancer-data environments.json ids; the mission generator sets them
from the world's weather). Code: `src/core/rules/environments.gd`. The text comes from the
core book's environments as lancer-data has it; readings it leaves open are below.

| Rule | Current state (PROVISIONAL where marked) | Where in code |
|---|---|---|
| "During storms" | A storm environment in the list is active for the whole battle (the GM can drop it from the list when the storm passes) | `environments.gd` |
| Who counts as a mech | Player mechs and NPCs (hostile flora are characters, not mechs). PROVISIONAL: NPCs are mechs | `Environments.is_mech` |
| Extreme heat "+1 heat from systems or weapons" | PROVISIONAL: heat damage from a character's attacks and systems, Heat (Self) from weapons and systems, flight-system heat and Overkill. Not Overcharge, basic Invade options, talents, core bonuses or other environments | `Environments.gear_heat` callers |
| Extreme cold | Mechs that didn't move or Boost on their turn are Immobilized at its end; `break_ice` (quick action, Hull save) ends it | `turn_ending`, `EnvironmentActions.BreakIce` |
| Extreme sun shade | PROVISIONAL: a column tagged `shade`, solid ground overhead, or next to an object that gives hard cover. Whose turn: the `extremesun_turns` ruling | `in_shade` |
| Dangerous storms "adjacent to an object that grants hard cover" | PROVISIONAL: terrain right next to it at least as tall as it (the hard-cover test against attacks) | `next_to_hard_cover` |
| Particulate storms "each turn they are outside" | A pilot outside a mech takes 1 AP kinetic at the end of its own turn | `turn_ending` |
| Electrical storms | One character at random (`state.dice`) at the end of each round; Engineering save with +1 Difficulty per Size (PROVISIONAL: Size 1/2 adds none) or Stunned until the end of its next turn | `round_ending` |
| Earthquakes | 1d6 at the end of each round; on 1, every non-flying mech makes a Hull save or is knocked Prone | `round_ending` |
| Molten world | Columns tagged `lava`: 5 AP energy and 3 heat when a character moves in for the first time on its turn or starts its turn there | `moved`, `turn_started` |
| Ocean world | Mechs move as in difficult terrain unless flying or carrying an EVA Module ("ignore difficult terrain" still applies) | `movement.gd` |
| Low / high gravity | Mechs fly when they Boost and must land at the end of that move; no falling damage. High: no Boost, and Immobilized whenever they'd be Slowed | `effects_for`, `Combat.add_status`, `Combat.fall_unit` |
| Sinking world | Counts the spaces a mech moved on its own turn. 1 or less: Slowed; already Slowed: Immobilized and sinking. PROVISIONAL: both last until `dig_out` (full action Hull save by it or an adjacent mech) | `turn_ending`, `EnvironmentActions.DigOut` |
| Dangerous flora | `Environments.make_flora(id, cell, size)`: Size 1-2, 5 HP, Evasion 10, takes no turns. PROVISIONAL: a character whose own move passes or ends next to it makes the Hull save (involuntary movement doesn't). Immobilized until the flora is destroyed | `_flora_moved`, `release_flora` |
| Zero gravity (`env_zero_g` for the whole battle, or map cells tagged `zero_g` / `vacuum` for a ship's breached deck or hull; glossary: Zero Gravity, Core p.63) | Mechs without a flight trait/system, count-as-flying gear or an EVA Module are Slowed; anyone can fly when moving; nothing falls | `effects_for`, `_zero_g_slowed` |
| Narrative only | Tomb world, spire world, holy world, primordial world (its terrain comes from the map's difficult/dangerous tags) | `Environments.NARRATIVE` |

## Terrain and objects (Core p.58, p.68)

Code: `src/core/rules/terrain_damage.gd`. Columns tagged `destructible` are made of Size 1
sections (10 HP, Evasion 5, Armor from an `armor_N` tag); untagged terrain is the GM waiving
the rule (Core p.68 allows it). Attack a section with target `terrain:x,y`.

| Rule | Current state (PROVISIONAL where marked) | Where in code |
|---|---|---|
| Which section an attack hits | The top one. PROVISIONAL: excess damage doesn't carry into the next section | `TerrainDamage.settle` |
| Floor | A column breaks down to its `floor_N` tag, else 0. Walls built on raised ground need the tag | `floor_of` |
| Armor and HP from the map | `armor_N` (0-4) wins; else `material:<name>`: wood, prefab, glass 0; metal, rock 1; stone, concrete 2; reinforced 3; fortified 4 (Core p.68: solid rock 1-2, fortified 3-4). Sections have 10 HP unless tagged `hp_N`. No "collapse save" (not in the book) | `armor_of`, `section_hp` |
| Rubble | The book gives destroyed terrain no special rule, so the cell keeps its tags (minus `destructible`) and isn't difficult | `destroy_sections` |
| Area attacks | Blast, Burst and Cone "affect characters": they don't hit terrain unless the gear says objects are hit (Thermal Grenade, Manticore's discharge, Apocalypse Rail). PROVISIONAL: those hit every section of a column in the area | `damage_area`, `after_area` |
| Knockback into terrain | No damage by the book (tags: Knockback); Juggernaut 2 adds 1d6 kinetic | `TalentRules.kinetic_mass_transfer` |
| Not automated | Juggernaut 3's charge through walls, Breaching Charge's 30 AP to objects, Line attacks that "affect all targets" hitting terrain | - |

## Not implemented yet

 frame traits and core systems
marked "manual" in `data/game/frame_effects.json`, talents (beyond unlocking talent gear),
Jockey and Reload (p.75), pilot armor and gear, zero-g
(p.63),
overshield sources, Scan's other two options, the same-Size grapple contest, Engineering
retries against a meltdown, Full Repair (p.82; rest is automated), unlicensed mechs (p.74: Impaired
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
