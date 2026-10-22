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
| `manticore_inferno_self` | Is the Manticore caught in its own charge-die inferno? | yes (a Burst that isn't an attack includes the user) / no | p.64, Manticore core |
| `hologram_blast_targets` | Dusk Wing Hologram Teleport explosions: who is caught? | hostiles / every character but the Dusk Wing | p.64, Dusk Wing core |
| `basilisk_failed_save` | Gorgon Basilisk: does a failed save stop the attack? | no attack / attack goes ahead | p.77, Gorgon core |

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
| GMS systems | HEX Charges (Frag Grenade, Explosive Mine), Smoke Charges (grenade and mine), Jericho Cover, Custom Paint Job, Personalizations (+2 HP), Stable Structure, Turret Drones, Type-3 Projected Shield, both flight systems, Manipulators (no rules effect) | EVA Module (no zero-g or underwater maps yet), Personalizations' +1 on checks the GM agrees it helps |
| IPS-N weapons | on-hit/on-crit saves and conditions (Concussion Missiles, Power Knuckles, Catalytic Hammer, Impaler), Chain Axe crit Shred, Bristlecrown, Cutter vs objects, Combat Drill Overkill bonus, Impact Lance line, Assault Cannon/Leviathan Spin-Up | - |
| IPS-N systems | Muscle Netting (Size for Ram/Grapple), Drag Down, Argonaut Shield, Aegis Shield Generator, Portable Bunker (hard cover/Resistance from outside once unfolded), Restock Drone (any adjacent ally uses it), Whitewash, Aceso Stabilizer, Bulwark Mods, Armor-Lock Plating, Ramjet (+2 Boost, melee Knockback 2), Thermal Grenade, Breaching Charge (detonated as a quick action), Roland Chamber, Siege Ram, HyperDense Armor, Webjaw Snare, Caltrop Launcher, Charged Stake | Grapple Swing; towing and climbing with the Cable Winch (dragging isn't modelled); Ramjet's straight-line moves; the bunker's 40 HP and the Restock Drone's priming delay; objects in a Breaching Charge blast |
| SSC weapons | Magnetic Cannon pull, Veil Rifle (allies get soft cover instead), Burst Launcher crit, Sharanga (two targets, damage rolled once), Pinaka (two blasts, `aims`), Fold Knife crit teleport (`fold_to`), Variable Sword crit bonus | Pinaka's delayed strike |
| SSC systems | Ferrous Lash (`toward`), ICEOUT Drone, Black ICE, High-Stress Mag Clamps, Tracking Bug, Core Siphon, Kinetic Compensator, Neurospike (Shrike Code, Mirage), Flicker Field, StunCrown, Reactive Weave (Invisible), Active Camouflage, Javelin Rockets, Hunter Logic Suite (Stalk Prey; Terrify's Impaired), Singularity Motivator (reaction with `to`), Lotus Projector (no Hiding or Invisible in it), Markerlight (no soft cover; the crit reaction), Retractable Profile, LB/OC Cloaking Field | Perimeter Command Plate, Magnetic Shield, Fade Cloak; Reactive Weave's free move, Terrify's "can't move closer", Tracking Bug's removal check, the Lotus Projector's information |
| HORUS weapons | Nanobot Whip crit pull, Ghoul Nexus damage type (`damage_type`), Arc Projector chain (`chain`), Autogun (fired by its free action) | Autopod and Vorpal Gun reactions, Ghast Nexus as a drone, Annihilation Nexus secondary attack, Mimic Gun |
| HORUS systems | Hive Drone, Scanner Swarm, Swarm Body, Eject Power Cores, Sentinel Drone, //SCORPION (on missed tech attacks), Puppetmaster Electropulse, Tempest Drone, Beckoner, Smite and Sear, EMP Pulse, Lightning Generator, Mesmer Mine, Viral Logic Suite, Chains of Prometheus and Excommunicate (`shake_off`), Metafold Carver, Interdiction Field (not its teleport rule), Hunter Lock, Eye of HORUS | Puppet System, Metahook, H0R_OS II and III constructs, Mimic Mesh, Monitor Module, Guide the Flock, Assassin Drone, Mesmer Beacon, Law of Blades, SISYPHUS; //SCORPION after saves against tech effects |
| HA weapons | Siege Cannon modes and other profiled weapons (`profile`), Plasma Thrower Cone/Line (`pattern`), Shatterhead (no Difficulty), Tachyon Lance backblast, Annihilator secondary attacks | Gravity Gun's effect |
| HA systems | Siege Stabilizers (toggle), Autoloader Drone, Flak Launcher, External Ammo Feed, Explosive Vents, Napalm Grenade, Auto-Cooler, AGNI, Gravity Grenade, Grounding Mine (detonated as a quick action), Repulser Field, Clamp Bombs, Stasis Bolt (Interdiction Point), Stasis Generator, ENCLAVE shield (Blinkfield Intervention), Flash Anchor, Reactor Stabilizer, Redundant Systems Upgrade, ASURA (two extra quick actions), External Batteries, Deep Well Heat Sink, LUCIFER, Plasma Gauntlet | Roller Grenade, Bouncing and HAVOK Mines, Tesseract (zero-g), Stasis Barrier; ASURA's "one extra full action" option; the Repulser's immunity to its own mines |
| Talents | Ace 1, Brawler 1-2, Brutal 1-3, Centimane 1-2 (3 uses Harrying Swarm), Combined Arms 1-2, Crack Shot 1-2 (`zero_in`), Drone Commander 1 (+5 HP; not the Shepherd protocol), Duelist 1, Executioner 2, Grease Monkey 1-2, Gunslinger 1, Hacker 1, Hunter 2, Infiltrator 2, Juggernaut 1, Nuclear Cavalier 1-2 (3 is talent gear), Siege Specialist 2 (not your own 1-space push), Skirmisher 1-3, Spotter 1, Stormbringer 1, Tactician 1-2, Vanguard 1-2 | Ace 2-3, Bonded, Crack Shot 3, Drone Commander 2-3, Duelist 2-3, Engineer, Executioner 1 and 3, Exemplar, Grease Monkey 3, Gunslinger 2-3, Hacker 2-3, Heavy Gunner, Hunter 1 and 3, Infiltrator 1 and 3, Juggernaut 2-3, Leader, Siege Specialist 1 and 3, Spotter 2-3, Stormbringer 2-3, Tactician 3, Technophile, Vanguard 3, Walking Armory; Skirmisher 1's "forcing a save" also ends the chaff |
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

## Not implemented yet

 frame traits and core systems
marked "manual" in `data/game/frame_effects.json`, talents (beyond unlocking talent gear),
Jockey and Reload (p.75), pilot armor and gear, zero-g
(p.63), lifting and dragging (p.62), dragging wrecks, objects as attack targets (p.68),
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
