# Lancer TTRPG: Design Notes

Status: foundation built (grid, state, dice, rules engine skeleton, data loader, tests).
Parallel work on rules engine, 3D visuals, and online/launcher in progress.
Code layout and contracts: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Core decisions

- **Type:** procedural Game Master + rules engine. No AI/LLM: the GM is ordinary game code
  driven by rule sets, tables and parameters (section 9), so no API key or ongoing cost.
  The engine is authoritative for all rules (dice, HP, heat, structure, stress, actions,
  statuses); the GM builds missions, runs enemies and events, and everything it does goes
  through the same rules engine as the players.
- **Engine:** Godot 4 (free, open-source, MIT license), desktop game, exported as a Windows
  .exe. Code in typed GDScript. Not a browser game.
  - Chosen over Unity and Unreal because Godot's scenes and scripts are plain text, so I can
    build, run and test the whole project from here (headless test runs, screenshot captures
    to check visuals) with fewer mistakes. No account, license, fees or royalties; ~100MB install.
  - Unity (runner-up): strong tools and built-in relay networking, but needs its editor and a
    Unity account, and its scene files are awkward to edit outside the editor.
  - Unreal: best raw graphics, but most content is binary files I can't edit, it's a 100GB+
    install, and it takes a 5% royalty above $1M revenue.
  - Graphics are not the bottleneck: Godot 4's renderer does real-time lighting, shadows,
    PBR materials, glow and GPU particles, plenty for mechs on a battlefield.
- **Art style:** full 3D with real lighting, shadows and materials (PBR). No pixel art.
- **Canon first, checked from several angles:** every rule, lore detail and system is checked
  against the core book (page cited), and where the book is thin, against other official
  Massif material and Lancer Tactics, and for how it plays at the table. Anything that isn't
  canon is parked as "your own story additions" until you choose to add it. The canon log is
  `docs/CANON.md`.
- **Reference game: Lancer Tactics.** It's the closest thing to a real Lancer video game, so the
  overall look, UI and how systems are shown are based on it, and it's the tiebreaker whenever
  a visual or system is unclear. Studied from its public trailers, screenshots, store page and
  devlogs; nothing is stolen outright: no models, art, audio or code taken from it.
  On rules, the book is the default, but every place Lancer Tactics does it differently is
  reported to you with both versions and the likely reason, and you choose (see "Rule
  differences: Lancer Tactics vs. the book" below).
- **Players:** online multiplayer (one host, others join remotely), hot-seat at one table, or
  solo: one person runs a full squad with AI squadmates flying any pilots they don't control.
- **Scope:** full campaign play: missions, combat, downtime, licenses, leveling, campaign arc.

## Play feel: player-driven, not an auto battler
Inspiration: Baldur's Gate 3's pacing and agency (feel only; nothing taken from it). What
you've seen so far are automated tests and scripted demos running at test speed; the real
game waits for people.

- **Every human makes their own choices.** Nothing a human controls ever acts on its own.
  The game waits on your turn as long as you need; AI only plays seats set to AI (enemies,
  and squadmates you hand over).
- **Turn order the Lancer way, shown like BG3:** a portrait bar across the top shows every
  unit, who has acted this round, and whose side picks next. Lancer has players and enemies
  alternate, and the players decide among themselves which of them goes next (anyone
  clicks "I'll go"; in solo you pick).
- **Your turn:** the camera moves to your mech, the action bar and resources come up
  (section 1), you plan freely (movement arrow, targets, previews), and nothing happens until
  you confirm each action. End turn is a button you press.
- **Watching other turns:** enemy and ally turns play at a readable pace. The camera
  follows each action, there's a short pause before attacks resolve, and the result number pops up.
  Speed setting (cinematic / normal / fast) and a "skip to my turn" option; never faster
  than you can follow unless you choose it.
- **Scenes, not just fights (like BG3's exploration vs. combat):**
  - **Exploration and story scenes:** walk your pilot or mech around a location in real time,
    talk to people (dialogue scenes, section 10), inspect things, find intel and supplies.
  - **Skill checks:** rolled instantly in the background; the result pops up as a number
    (blue/red tinted, breakdown on hover), with outcomes that branch the scene. No dice screen.
  - **Combat starts from the scene:** ambushes, failed sneaking, or a dialogue choice drop
    everyone into turn-based combat on the same map. Surprise follows the book.
  - **Downtime between missions** as its own scene (section 10).
- **Multiplayer:** in exploration everyone moves freely; in combat each player acts on their
  own pilot's turn while others watch (and can ping and chat); dialogue choices go to the
  speaking pilot's player or a vote.

### Exploring vs. fighting (a Final Fantasy / BG3 mix)
- **Outside combat there are no turns:** everyone moves in real time (pilots on foot, mechs
  walking). Combat starts seamlessly where you are, on the same ground, with no loading into a
  separate battle screen.
- **Optional turn-based exploring:** off by default; worth turning on for careful heists and
  stealth (a guard's patrol, a timed lockpick), the way BG3 offers it.
- **Free, independent exploring in multiplayer:** players go wherever they want on their own until
  a major story event pulls everyone to it.
- **Fights start with whoever is there.** Teammates elsewhere can travel to the fight and join it;
  they enter where they arrive, so arriving behind the enemy means starting behind the enemy.
  Late arrivals join the turn order from the next round (Lancer's alternating activations).
- **No teleporting to missions (user decision):** you climb into your mech in the hangar and walk
  out in it. If the job is close by on the same world, you walk there; you only fly, ride a
  dropship or get driven when the place is far away, off-world or across terrain mechs can't cross.
- **World map like Final Fantasy VII / X (feel only):** walk your mech (or your pilot) around a
  region map. Each tile takes travel time on the clock, based on the slowest mech when the squad
  moves together and on each mech's own Speed when players split up. Each player can roam the
  map on their own until a major story event pulls the squad together. Towns, outposts, job
  sites, safe points and landmarks sit on the map. Entering one drops you into that area in real
  time, seamlessly.
- **Encounters are mostly scripted:** they come from the job board, merc contracts, patrons and the
  story, placed at real spots on the map. A few road events (patrols, bandits, a broken-down
  convoy) come from the procedural GM's tables. Every fight still happens on the ground where
  you met it.
- **A starting area with depth:** the first town has people to meet, small jobs, places to
  explore and a reason to walk out of town before the first mission.

## 1. Animations and visual feedback

Every effect gets an animation, a combat-log line, and floating text (damage, MISS,
+heat), so you can always tell what happened.

| Event | Visual |
|---|---|
| Melee attack | Lunge in, swing-arc trail, impact sparks; knockback slide on hit, deflect flash on miss |
| Ranged kinetic | Muzzle flash, tracers, impact puffs; misses fly past the target |
| Energy weapons | Charge-up glow, beam, heat shimmer |
| Explosive / launchers | Arcing projectile, blast-radius warning ring, explosion and debris |
| Area attacks (blast, burst, cone, line) | Template preview on the grid before you confirm, then the effect fills the area |
| Tech attack / hacking | Data-link beam of glyphs from hacker to target; target mech gets glitch, scanline and color-split effects |
| You get hacked | Your HUD panel glitches and shows the attacking mech's ID, with the link beam pointing back to it |
| Statuses (Jammed, Lock On, Impaired, Slowed, Immobilized, Shredded, Stunned, etc.) | Icon ring above the mech plus a lasting effect on the model (lock-on reticle, sparking for Shredded, frozen pose for Stunned) |
| Defense (Brace, shields, overshield, evasion) | Energy shell, overshield shimmer, dodge sidestep, sparks off armor |
| Heat | Heat bar; mech glows orange to white as heat rises; vent steam on Stabilize/vent |
| Overheating | Heat-stress check card, reactor warning pulse, meltdown sequence if it goes critical |
| Structure damage | Armor plates blown off, sparking, structure check card |
| Smoke grenades / mines | Thrown arc, smoke spreads over tiles; the cover/line-of-sight effect the rules give it is shown |
| Hard light walls / deployables | Wireframe builds into a solid wall; cover indicator shown |
| Movement | Movement arrow and cover highlights while planning (see Turn overlays), then walk, hover or boost trail; engagement indicators |
| Destruction / eject | Mech collapses into a wreck that stays as terrain; pilot ejects on foot |

### Resource HUD and action buttons
- **Always-visible resources** for the active mech/pilot, shown as current / total:
  HP, Overshield, Heat (with the Danger Zone threshold marked), Structure, Reactor Stress,
  Repairs, Burn, core power (available/used), and the turn's action economy: Quick and Full
  actions left, Move, Reaction (1/round), Overcharge (next heat cost: 1, 1d3, 1d6, 1d6+4).
- **Limited uses:** weapons and systems with Limited X, Loading, 1/round, 1/scene or
  1/mission show charges left on their button.
- **Action buttons:** every available action is a button showing:
  - an icon for what it costs: Quick, Full, Free, Reaction, Protocol, Move; plus heat cost,
    charges, or Overcharge as extra icons with numbers;
  - its name and a short description from the book data (hover/hold for the full text and
    rule reference);
  - greyed out with the reason when it can't be used ("Already used your Quick actions",
    "Jammed: can't take tech actions").
- **Action bar, BG3-style:** one bar along the bottom center holding every attack, ability,
  dash/Boost, tech action, system, weapon, reaction, protocol and core power: anything that
  isn't a basic move. Basic movement stays click-to-move on the board.
  - Grouped into tabs or sections (Weapons, Quick, Full, Tech, Systems, Reactions/Protocols,
    Core) so it stays tidy; a small resource cluster sits beside it (HP, heat, structure,
    stress, actions left).
  - Icon buttons with cost badges (Quick/Full/Free/Reaction icons, heat, charges); hover for
    the description card described above; number-key shortcuts.
  - **Size:** big enough to read and click comfortably, never a skinny strip, never so big it
    hides the battlefield. Start around 9% of screen height on 1080p, with a bar-size slider
    in settings so we can tune it together; it scales with resolution.
  - Players can rearrange buttons; the layout is saved per pilot.
  - **Cooldowns shown WoW-style:** an unusable button greys out with a dark radial sweep and
    the reason on it. Like a clock hand, the grey slice shrinks as the wait runs down,
    un-greying the button bit by bit (it animates smoothly to the new size each time a turn
    or round passes) until it's fully lit and usable. Waits with no fixed length (Recharge,
    Loading) stay fully grey with their label until they're ready. Lancer doesn't have many plain cooldowns, so the overlay shows what
    actually applies:
    - a **number of turns/rounds** when the wait is fixed (e.g. an effect lasting "until the
      end of your next turn", 1/round abilities until the next round);
    - **Recharge X+** (NPC abilities that come back on a d6 roll) shows the die and target
      number, and lights back up when the roll succeeds;
    - **Loading** weapons show "Reload" until reloaded;
    - **1/scene, 1/mission, Limited X** show the uses left, or "used this scene";
    - **status lockouts** (Jammed, Shut Down...) show the status icon and how long it lasts.
- **Hover cards say what will happen to you, in plain words,** worked out by the rules
  engine from your current state, not just the item's text:
  - costs and results as a number followed by the official icon, e.g. **+2 [heat icon]**,
    **1d6+2 [energy icon]**, **3 [burn icon]**, **Range 10 [range icon]**;
  - warnings when it crosses a line: *"This will overheat you (8/8 → 10): you'll take
    stress damage and roll an overheating check"*, *"This puts you in the Danger Zone"*,
    *"Last charge"*, *"You're Engaged: +1 Difficulty"*, *"Moving away provokes from 2 enemies"*;
  - expected outcome vs. the hovered target: hit chance, cover, likely damage after Armor.
- **Official icons everywhere:** damage types (kinetic, energy, explosive, heat, burn,
  variable), ranges and areas (range, threat, blast, burst, cone, line), action types
  (quick, full, free, reaction, protocol, overcharge, tech), statuses and conditions,
  manufacturers, size, structure, stress, repairs. They're Massif's own icons from COMP/CON
  (GPL-3.0) in `assets/icons/lancer/`, so they look exactly like the book.
- **Cost preview:** hovering a button shows what it will spend on the resource bars (e.g. the
  heat bar previews +2), and warns if it would push you into the Danger Zone or overheat.
- Enemies show only what the view rules allow (section 6): unscanned enemies show "??".

### Roll visuals

No dice on screen: no rolling d20, no D&D-style dice animation. Rolls happen instantly in
the background the moment you confirm an action, and the result **pops up as a number**.

- **Pop-up number:** after the roll, the total floats up over the target (or over you, for
  checks and saves) with the result: e.g. **20** HIT, **9** MISS, **23** CRIT. Damage pops
  up the same way as a number with its official damage-type icon, e.g. **7 [energy icon]**.
- **Colors carry the meaning:** the pop-up is tinted blue when Accuracy helped the roll and
  red when Difficulty hurt it, so you can tell at a glance without reading the math.
- **Breakdown on demand, never in the way:** hover the pop-up, or open the combat log, to see
  how it was made: `6` **`+4`** (blue, Accuracy, from Lock On) `+2 Grit` `= 12 vs Evasion 8`.
  Accuracy and Difficulty cancel first, so only one color is ever left. Damage breakdown shows
  dice, bonuses, Armor reducing it, and resistance halving it.
- **Skill checks and saves** use the same pop-up number, not a big dice screen.
- Speed setting only changes how long pop-ups linger; rolls are always instant.

### Turn overlays (only on the active player's screen)

These are planning aids drawn only for the player whose turn it is. Other players don't see
them, and they disappear when the turn moves on.

- **Movement arrow:** when you plan a move, an arrow runs from your mech along the exact path
  to the destination, bending around obstacles. It shows move cost so far and spaces left,
  and changes color when the path would provoke from an Engaged enemy, needs a Boost, or goes
  through difficult/dangerous terrain. Nothing moves until you confirm.
- **Cover highlights while moving:** terrain glows by cover type: one color for **hard cover**,
  another for **soft cover** (e.g. smoke). The hovered destination also shows which enemies
  you'd have cover from there, and which kind.
- **Cover highlights while attacking:** when you pick a target, the game shows the cover that
  target has *against you* (hard, soft, or none) and outlines the terrain giving it, with the
  effect on your roll (e.g. +1 or +2 Difficulty) shown in the roll breakdown.
- Cover is always worked out by the rules engine, from your actual position, so what's
  highlighted is exactly what the rules will apply.

## 2. 3D models: all made in house

- **No assets ripped from Lancer Tactics or any other game.** Everything is built
  procedurally in our own code, so nothing in it is someone else's art.
- 3D scene in Godot with switchable camera modes, changeable
  any time in game:
  - **The core idea (user decision):** a first-person / third-person / top-down TTRPG. You
    can control your own character directly in every view, but battles stay turn-based, on
    the hex/square grid, with movement limited by the book (Speed, Boost, terrain, Engagement).
  - **Top-down (the base way to play, the default):** overhead like a tabletop map, the
    clearest view of the grid, zones, ranges and areas. Mouse-first: click to move and target,
    WASD and screen edges pan, Q/E rotate, wheel zooms (down to an angled tactical view).
  - **First and third person (optional camera angles):** identical controls, only the camera
    differs (eyes/cockpit vs over the shoulder). Mouse look and aim, WASD steps space by space
    along the grid, hold right mouse to aim down sights (zoom only, never reveals more).
  - **First person:** cockpit view from your mech's eye level, with a HUD (heat, HP,
    structure, selected weapon, range). Attacks, hacks and effects play out from inside the
    cockpit. A minimap shows the grid so moves and ranges stay readable.
  - Camera mode only changes the view, never what you know or what's legal: everything
    visible on the tactical board is still available (minimap, unit list).
  - **Your whole turn works in first person.** It's still the same turn-based TTRPG, just
    played from the cockpit: the grid is projected onto the ground in front of you, you
    look at a space and click to plan your move (path and move cost shown), look at an
    enemy to target it (range, line of sight, cover and hit chance on the HUD), and pick
    actions from a cockpit action panel (Quick/Full actions, Overcharge, Brace, tech, etc.).
    Nothing happens in real time; nothing resolves until you confirm.
  - **Direct control in every view:** on your turn, WASD walks your mech one space at a time
    in the direction you face or the camera points. Each step snaps to the grid, costs
    movement per the book, and shows "Moves left: 3". You can't step past your Speed (or Boost)
    or into illegal spaces; a wall or an Engagement stops you with the reason. Undo steps until
    you confirm. Click-to-move works in every view too.
  - Other players can use different cameras at the same time.
- **Every model matches what's actually equipped.** Mechs are assembled from the pilot's
  real loadout data, not a fixed model per frame:
  - Each frame's mounts (from `lancer-data`) have attachment points on its model; whatever
    weapon is in a mount is drawn there, in hand or on the shoulder/arm as appropriate.
  - Weapons from other manufacturers keep their own design. An IPS-N weapon on a GMS frame
    looks like the IPS-N weapon, mounted on the GMS frame.
  - Each weapon gets its own model, generated from its data: size (Auxiliary, Main, Heavy,
    Superheavy), type (rifle, cannon, launcher, melee, CQB, nexus...), damage type, and
    manufacturer style, with hand-made overrides for signature weapons. Two different rifles
    look different.
  - Visible systems show up too: drones, shield generators, deployables, mods (e.g. a
    weapon mod changes the weapon's look).
  - Changing the loadout rebuilds the model. Attack animations come from the weapon actually
    used (a cannon fires shells, a nexus releases a drone swarm).
  - The rules engine checks the loadout is legal (mount sizes, system points, licenses)
    before a mech can deploy, with the reason shown if not.
- **Full scene rendering in every view:** terrain, buildings, cover, deployables, smoke,
  other mechs and effects are all rendered in 3D around you. In first person you see your
  own mech's arms and weapons in the cockpit view, matching your loadout.
- **Mechs look as close as possible to their official art** (your choice): each frame is
  modeled individually to match its book / Lancer Tactics look: same silhouette, armor
  shapes, proportions, head, and signature details, with smooth curved surfaces, panel lines
  and bevels, not blocks. Reference: the official frame art linked in `frames.json`
  (`image_url`), viewed for reference only; those images are never put in the game or repo.
- Modeled in Blender by script (free, open source), exported as glTF, one model per frame,
  with mount points where weapons attach. Weapons and systems still come from the real
  loadout (above) and match their official art too.
- Manufacturer paint schemes for GMS, IPS-N, SSC, HORUS and Harrison Armory as defaults;
  the mech customizer repaints them.
- **Publishing note:** matching Massif's designs this closely is fine for you and friends;
  a public release would need Massif's permission (see Publishing).
- Mech size matches the rules (Size 1/2, 1, 2, 3); pilots on foot are smaller models.
- Weapon models: one per weapon, as described above.

## 3. Grid: hex or square, switchable

- A grid layer handles neighbors, distance, line of sight, area templates, and footprints
  for big mechs. Rules and enemy-tactics code never assume a grid shape.
- Pick hex or square when setting up a mission, and switch between missions.
- Square-grid diagonal movement follows the core book rule (to confirm against the book).
- Grid spaces line up 1:1 with a tabletop board so measurements match play on paper.

### Living, themed battlefields
- **Bigger maps:** sized for real Lancer fights with room to maneuver and flank (roughly
  30x30 to 60x60 spaces (wider and longer, per the user), depending on mission type and squad size; starting distance is set by the fight length dial, so the extra space is flanking room), not small test boards.
- **Biomes drive both look and terrain:** grassy hills, desert, snow/tundra, urban ruins,
  industrial yard, forest, swamp, volcanic, space station, moon base... Each biome has its own
  height shapes (rolling hills vs. mesas vs. city blocks) and its own materials.
- **Blocks look like real ground, not flat colors:** e.g. grassy hills = grass tops with
  variation, brown dirt and rock on the cliff sides, stone strata on tall columns; textured
  PBR materials with blending, edge wear, and per-tile variation so it doesn't tile visibly.
- **Life and detail:** trees, bushes, rocks, crates, wrecks, buildings, fences, wind in grass
  and trees, water, dust, birds, smoke from fires, lighting and weather per biome
  (time of day, fog, rain, snow).
- **What you see is what the rules use:** anything that looks like cover, an obstacle, or
  difficult/dangerous terrain IS that in the rules (it's built from the same map data).
  Purely decorative details stay small and flat so they never look like cover they aren't.
  Destructible terrain visibly breaks when destroyed.
- The grid stays readable on top of everything (toggle-able grid lines, clear tile edges).

### People up close (feedback to act on next)
- The user, seeing a town NPC face to face: "people here still too blocky and round for my
  liking". Next pass on people: less round, less blocky, closer to the Lancer art style, with
  the most detail on head, face and hands (the face-to-face camera is about 1.25 m away).
- Follow-up from the user: "somewhat realistic", at Dawn of War IV / Titanfall 2 pilot level of
  realism for faces and general features (realism level only; nothing copied).
- **Decision (user picked option A):** human bodies and faces use MakeHuman/MPFB2 open-source
  assets (CC0 base mesh and shape targets; each skin/hair asset's license checked, credited in
  CREDITS) with our own Lancer-style gear on top. This is the one approved exception to
  "models made in house": open-source CC0 base meshes, never assets from games.

### Every place is its own place
- No two towns look the same: every hub and every map gets its own layout, building mix and
  details, even within one culture and landscape.
- Battles happen where you are on the world: fight in town, walk a mile down the road and get
  ambushed, and the second map keeps the same region's look (landscape, culture, weather,
  vegetation, building style) but with different buildings and terrain, as the next stretch of
  the same place.

### Town fights and building toughness
- A fight that breaks out in a town happens in that town: the battle map is built from the
  hub's own layout and culture kit at mech scale, so the saloon you walked into is the cover
  you fight behind.
- Buildings follow the book's object rules (Core p.68): 5 Evasion and 10 HP per Size-1 section,
  each section destroyed separately. Flimsy wood/prefab has no Armor and breaks easily; tough
  stone or brick has 1-2 Armor; fortified bunkers, bulkheads and hulls have 3-4 Armor, so most
  shots just chip them and it takes AP damage or breaching charges to bring them down.

### World art direction: beautiful but dangerous
The feel to aim for (examples are inspiration only; nothing taken from them): the vast alien
vistas of Halo, the lived-in worlds of Star Wars, the grim scale of Warhammer 40k.

- **Vibrant cities:** dense towers, neon and holo signs, skybridges, traffic in the sky,
  plazas and alleys to fight through; also ruined cities, half-collapsed and burning.
- **Rolling hills and wilds:** lush grass under big skies, forests, rivers, cliffs, farmland
  (like the Lancer Tactics countryside, but in full 3D).
- **Alien worlds that are beautiful but scary:** strange colored skies, giant moons and
  ringed planets overhead, bioluminescent plants, crystal fields, colossal ancient
  structures, toxic seas, storms on the horizon, things moving in the distance.
- **Every kind of world, because Lancer's galaxy is huge and no two planets are alike:**
  the Core Worlds (Cradle and other Union core worlds) look polished and similar; out in the
  diaspora, every planet is its own place. Settings to build, each with its own architecture,
  props, people, lighting and sky:
  - **Medieval-tech worlds:** castles, walled towns, banners and stone bridges next to
    mech hangars (low-tech colonies, feudal Karrakin-style baronies).
  - **Old West frontier:** dusty boomtowns, mesas, rail lines, mining camps, saloons with
    satellite dishes.
  - **Retrofuturistic:** chrome, tail fins, atomic-age domes and monorails.
  - **Cyberpunk sci-fi:** neon megacities, rain, holo-ads, stacked slums, corporate towers.
  - **East Asian-inspired sci-fi:** pagoda-towers and shrine gates mixed with high tech,
    terraced cities, lantern-lit streets, bamboo and cherry forests.
  - **Clean high sci-fi:** gleaming Union architecture, orbital elevators, white and glass.
  - plus the natural and alien landscapes above (hills, deserts, ice, jungle, ocean,
    volcanic, crystal, toxic, gas-giant moons, ancient ruins, space stations).
- **Biome + culture mix:** the map generator combines a landscape (e.g. desert mesas) with a
  culture/era (e.g. Old West), so the same rules terrain can look completely different.
- **Backgrounds beyond the board:** every map sits inside a full horizon (skybox, distant
  mountains/cities/megastructures, weather, lighting) so the battle feels like part of a
  huge world, not a tile on a void.
- **Lighting sets the mood:** golden-hour hills, neon night cities, eerie alien twilight,
  stormy war zones; fog, god rays, glow.
- Everything is ours: procedural/shader art, our own models, or CC0 assets with credit.

### How each mech moves (locomotion)
- **Animation matches the frame's real design:** two-legged frames walk, four-legged and
  multi-legged frames step with every leg in a proper gait, tracked or wheeled frames roll,
  hover designs float on thrusters, winged/jet designs fly. Each frame's body type comes from
  its official art and is listed in `data/game/locomotion.json`. Stride and speed scale with
  Size so the model lands exactly on the spaces the rules moved it through.
- **Rules decide where you can go; visuals only show it.** Looking like it floats changes
  nothing in the rules. A mech only gets flight, hover, ignoring difficult terrain, jumping
  further, teleporting, etc. when the book says so: a frame trait, core system, system,
  talent, status or action that grants it. If the book doesn't grant it, a hovering-looking
  mech still pays for difficult terrain, climbs, and is blocked like any other.
- **Every movement rule audited against the book:** every trait, system, talent, core power
  and status that touches movement (Flight, Hover, Teleport, Jump, climbing, difficult and
  dangerous terrain, Immobilized, Slowed, Engaged, knockback, Skirmisher-style effects) is
  checked line by line against the rulebook text, with a test for each.

### Elevation and flying (3D grid)

The board is a stacked 3D grid, like blocks: every hex/square column has height levels, so
terrain can be terraced, mechs can climb up and down it, and flyers can move through the air.

- **Terrain heights:** buildings, cliffs, ledges and rubble are built from stacked levels.
  A mech's height in levels equals its Size, as in the rules.
- **Size and footprint:** a mech takes up as much space as its Size says, across the ground
  and upward, and the engine checks the whole footprint, not just one space:
  - **Standing room:** a mech can only stop where its entire footprint has ground to stand on.
    A Size 3 can't stand on a hilltop or pillar that's only 1 space wide; a Size 1 can.
  - **Clearance:** a tall mech can't fit under a low bridge or overhang, or through a gap
    narrower than its footprint.
  - **The movement arrow shows it:** spaces your mech can't fit on are greyed out for your
    Size, and the destination preview shows your full footprint, not just one tile.
  - **Size applies to every use of terrain**, wherever the book ties something to Size:
    - **Cover:** whether a wall or rock covers you depends on how big it is compared to you.
      A low wall can cover a Size 1/2 or 1 but not a Size 3 standing behind it.
    - **Line of sight:** big mechs can see, and be seen, over small terrain; small mechs can be
      completely blocked by it.
    - **Hiding:** you need terrain big enough to actually hide your mech.
    - **Climbing and moving over terrain:** what counts as a small step vs. a climb depends on
      your Size.
    - **Ram, Grapple, knockback and shoving into terrain:** the Size limits in the book apply.
    - **Destroying or using terrain as a weapon:** follows the book's rules, including Size.
    - The cover highlights (Turn overlays) are worked out for *your* Size and the target's, so a
      wall can light up as cover for a small mech and show nothing for a big one.
  - The exact Size rules for each of these, footprint shapes per Size on hex vs. square
    grids, and whether a big mech can stand
    across uneven ground, come from the book (to confirm). If the book doesn't say, it's a
    "Ruling" grey area for the table to decide, as in section 7.
- **Sky layers ("sky floors"):** when a flying mech plans a move, a see-through grid layer
  appears at each altitude so you can pick a space in the air. Scroll or press keys to raise or
  lower the layer. Flyers show a drop line and shadow to the ground so their height is always
  readable, plus an altitude number.
- **Movement arrow in 3D:** the movement arrow climbs, drops and flies along the real path,
  showing the extra cost of climbing and where a fall would happen.
- **Only the book's rules and modifiers, always shown:** elevation and flying apply exactly the
  rules the book has and nothing invented. From what I remember (to confirm against the book):
  - Climbing and moving up terrain cost extra movement; flying lets you move in any
    direction but you must keep moving each turn or fall.
  - Falling deals damage based on distance fallen.
  - Height matters through line of sight and cover: being above or below terrain changes
    what blocks your view and whether a target has cover.
  - I don't believe core Lancer has a general "high ground = Accuracy" rule. If the book
    has one, it goes in; if not, only gear and talents that give elevation bonuses apply.
- **Every modifier is shown:** whatever elevation, flying or falling does to a roll or move
  appears in the roll display (blue +/red −) and the movement arrow, each labeled with its
  source and rule reference.
- Works the same on hex and square grids.

## 4. Online play without port forwarding

- The host's PC runs the authoritative game (rules engine + GM). Other players connect
  to it; nobody opens ports.
- **Chosen: peer-to-peer (WebRTC).** Options that were considered:
  - **Peer-to-peer (WebRTC):** players connect directly through NAT. Godot has a WebRTC API;
    on desktop it uses the official `webrtc-native` extension. Needs a small matchmaking
    (signaling) service to exchange connection info, plus STUN, and a relay (TURN) only on
    strict networks. Which signaling service to use is decided at the networking stage.
  - **Tunnel:** the launcher starts a free tunnel (e.g. Cloudflare quick tunnel) and shows a
    join link.
  - **Hosted relay:** a small server we deploy on a free host. Most reliable, but needs an account and upkeep.
- Join by room code / link. Reconnect after a dropped connection without losing the game.

## 5. Launcher and auto-update (GitHub)

- Code lives in a GitHub repo (account: Gabensrightnut). Releases are built by GitHub Actions.
- Launcher checks the latest GitHub Release, downloads it, checks the file hash, swaps in the
  new version, then starts the game. Keeps the previous version to roll back to.
- Everyone in a session must be on the same version; the host rejects mismatched clients
  with a "please update" message.
- Game and launcher both ship as Windows .exe files (Godot export), so friends install nothing else.
- Saves and campaigns are stored outside the game folder so updates never touch them.

## 6. Per-player visibility (hidden information)

**Principle: only what the rules hide is hidden. No fog of war.** The whole battlefield is
visible to everyone like a tabletop board, except the specific things the rules keep secret.
That gives a "kinda like fog of war" feel without adding rules that aren't in the game.

- **What the rules keep secret** (each revealed only the way the book says):
  - **Hidden units:** a unit that takes the **Hide** action and becomes **Hidden** vanishes
    from enemy boards; enemies only know its approximate location (book: Hidden), shown as
    a fuzzy area, not an exact space. Allies still see it. Smoke and cover matter because they let you
    Hide, not because they black out the map.
  - **Enemy details:** you see the mech or NPC on the field (silhouette, size), but HP,
    armor, heat, systems, templates and exact stats stay "??" until revealed by **Scan**,
    by seeing them use something (a weapon fired is now known), or by the GM.
  - **Stat-revealing abilities:** players never see enemy stats by default. Only abilities
    that say they reveal information (Scan, and any frame, system or talent whose text
    grants it) reveal anything, and only exactly what that text says, shared with the
    squad as the book allows.
  - **GM secrets:** hidden reinforcements, traps, and secret sitrep objectives stay off
    player boards until the GM or the rules reveal them.
- **Line-of-sight overlay (display aid, not a rule change):** when you pick an attack, spaces
  and units you have no line of sight to are dimmed and marked "no LOS", and cover is shown.
  Nothing is hidden by it; it just shows what the rules already say you can and can't target.
- **Filtered on the host, not hidden on screen.** The host builds a separate view for each
  player and sends only that, so secrets never reach other players' computers and can't be
  dug out of game files or network traffic.
- **GM view:** the procedural GM (and an optional human GM seat) sees everything a tabletop
  GM would: all units, all stats, hidden positions, secret objectives, reinforcements.
- **Hot-seat at one screen:** a "Pass to Player 2" screen between turns, since what's
  secret can differ between players (e.g. one is Hidden from an enemy-controlled seat).
- **Squad intel sharing (the book default; players share freely at the table):**
  - Scan results, revealed enemy stats, and enemy weapons seen in use go into a shared squad
    intel panel everyone on the team reads.
  - Lock On and other statuses an ally applies show for everyone.
  - Pings ("target", "danger", "moving here") and squad text chat. Voice chat as a later option.
  - **The rules can cut comms:** I believe **Jammed** says you can't use comms to talk to
    other characters (to confirm against the book). While it lasts, that mech can't send or
    receive pings/chat/intel, shown with a "COMMS DOWN" indicator and the glitch effect.
- **To verify against the core book:** smoke giving soft cover vs. hiding you, exactly what
  enemies know about a Hidden unit, and the Jammed wording. The engine will follow the book.

## 7. Rules sanity checker

- Every action goes through the rules engine first. If it's illegal, it's blocked with the
  reason and a rule reference (book section/page), never silently allowed.
- Every rule check is written with its source citation, so the code can be audited against
  the book ("sanity checker" report).
- **Grey areas:** where the book is genuinely unclear, the engine allows the reasonable
  readings, labels the action "Ruling", shows the relevant rule text, and lets the table decide
  (host or a vote; a human GM seat if there is one). Rulings are logged and reused so the same call is made every time.
- **House rules:** none in the first version; the game plays strictly by the book so you
  learn the real rules. The engine leaves room for optional toggles to be added later.
- Automated tests: a scenario suite that plays out rule situations (heat, structure,
  overcharge, cover, Hidden, statuses...) and checks the outcome.

## 8. Learning to play (first-time players)

The goal of version one is learning the real game, so it plays strictly by the book and
teaches as you go.

- **Tutorial missions:** a short guided first mission that introduces one thing at a time:
  moving and turns, basic attacks, cover, heat, damage and structure, tech actions, then a
  full fight. Then pilot and mech creation with the GM walking you through each choice.
- **Teaching prompts:** written explanations pop up when a rule comes into play for the
  first time ("you're Engaged, so moving away will provoke"), each citing the rulebook
  section. A searchable in-game rules reference answers questions any time.
- **Explain everything:** hovering any action, status, tag or weapon shows what it does and
  where it's from in the book. Blocked actions say why ("can't Boost: you've already used your
  move") instead of just failing.
- **Show the math:** every roll's pop-up number has its breakdown on hover (d20 + Grit + accuracy/difficulty vs.
  Evasion) so you learn how the numbers work.
- **Teaching hints toggle:** on for new players, off once you know the game.

## 9. Procedural GM (no AI)

The GM is built from rule sets, random tables and tunable parameters, so every game plays
differently without an AI. Each game has a **seed**: share it to replay the same setup.

- **Mission generator:** picks a sitrep (from `lancer-data`: control points, escort, holdout,
  extraction, etc.), map, environment and hazards (`environments.json`), objectives, and
  complications from weighted tables. Maps are generated from terrain kits (urban, desert,
  forest, station interior...) with rules for cover density, elevation and choke points.
- **Encounter builder:** builds enemy forces using the core book's encounter guidance for
  your squad's size and License Level: NPC classes, templates (Elite, Veteran, Ultra...),
  roles mixed so fights vary (artillery-heavy, swarm of grunts, one Ultra boss...).
- **Enemy tactics:** each NPC role (Striker, Artillery, Controller, Defender, Support) has its
  own behavior rules: targeting priorities, keeping range, using cover, focusing fire,
  protecting allies, retreating when damaged. Scored by a utility system, with randomness so
  enemies aren't predictable. Enemies only act on what *they* could know (they can't target
  someone Hidden).
- **Fight length dial:** Short / Standard / Long. A tabletop fight takes about 1-3 hours;
  with automation we aim for ~15-25 / 20-40 / 40-60+ minutes solo. It changes encounter
  size, deployment distance and how early surrender or retreat becomes possible, never
  rules like HP or damage.
- **GM personality / difficulty dials:** aggression, caution, focus fire vs. spread damage,
  reinforcement rate, how often complications happen, overall difficulty. Presets (e.g.
  "Ruthless", "Cautious", "Chaotic", "Teaching") plus custom sliders.
- **Events and reinforcements:** triggered by round number, objectives or player actions,
  from weighted tables (reinforcements arrive, weather turns, a building collapses, a third
  party shows up).
- **Narration:** written text from templates and tables (mission briefings, enemy barks,
  outcome reports, downtime results), filled in with names, places and factions from the
  campaign. Variety comes from many variants per situation, not an AI.
- **Campaign generator:** factions, planets, contacts, reserves (`reserves.json`), mission
  chains and consequences, so what you do in one mission changes the next.
- **Downtime:** the book's downtime actions (`downtime_actions.json`) with outcomes rolled per
  the rules.
- **All of it is data:** tables, behaviors and presets live in editable data files, so new
  content and variety can be added without changing code.

### Soldiers

Soldiers are people fighting on foot on the mech battlefield: a **squad** (ten people sharing
one pool of 10 HP in one space; how many are still standing shows on the model) or a single
**soldier**. They follow the book's rules for anyone out of a mech (Core p.74): they add Grit to
attacks and saves, can't be hacked (only Lock On and Scan work on them), take heat as energy
damage, attack with Fight using pilot weapons, and mechs walk straight through them without
being Engaged. Mech weapons hit them hard; their rifles barely scratch a mech, but a missile
team's launcher can.

Nobody gives soldiers orders, on either side. Each acts on its own AI, by what kind of squad it
is (the book's NPC roles: a missile team fires from far back, medics stay hidden and patch up
people on foot, a guard squad holds what it guards) and by the mission's objective: in a
Holdout, guards stay on the zone instead of chasing kills. On your side you still choose when
an allied squad takes its turn (Core p.60), and the combat log says in plain words what it's
doing and why ("Guard Squad: moves into cover, fires its rifles at the Goblin (holding the
zone)"). Weights are a table in `data/game/gm/objective_priorities.json`; kinds and their
placeholder numbers in `data/game/soldiers.json`. A new player meets them as town guards and
patrols, as garrisons in enemy bases, and as allied troops on missions that have them.

## 10. Around combat: the rest of the game

### Enemy (NPC) data
- Massif's public data has no NPC stats. They were in `lancer-data` until January 2020, when
  Massif removed them on purpose ("remove npc content"), so we don't use those old files.
- **Plan:** load the official NPC content from your own copy (as a content pack if you have
  one for COMP/CON, otherwise entered from your book) through the content-pack loader below. It lives on
  your PC in `/local/` and never goes into the public repo. Each player who hosts needs their
  own copy.
- **Until then:** a few clearly-labeled placeholder enemies written by us (generic grunt,
  artillery, striker, controller) so the game is playable and testable. They're replaced
  once real NPC data is loaded.

### Content packs
- Load Lancer Content Packs (`.lcp`, the format COMP/CON uses): official supplements Massif
  publishes (Long Rim, Wallflower, Karrakin Trade Baronies, Dustgrave, etc.), the NPC pack,
  and community packs. Each pack can be turned on per campaign; everyone in a game must have
  the same packs (checked when joining, like the version check).

### Mech and pilot builder
- Build pilots (background, skill triggers, talents, licenses, core bonuses, pilot gear) and
  mechs (frame, weapons in mounts, mods, systems), with the rules checker live: illegal
  choices are blocked with the reason (mount size, SP, license level).
- **COMP/CON import/export:** bring in pilots built in COMP/CON, and export back.
- The 3D mech preview updates as you change the loadout.
- **License Level accuracy:** a pilot can only field what their License Level and licenses
  allow (frame and gear unlocked by license rank, LL-based stats like Grit, core bonuses and
  talent ranks by level), checked by the rules engine. The mech on the battlefield always
  shows exactly that frame and the weapons and systems actually equipped, never cosmetic
  stand-ins. Enemies and AI squadmates follow the same rules for their tier/level.

### Effects system (talents, traits, core powers, systems)
- Hundreds of unique effects. Built as a data-driven effects system where possible (bonuses,
  triggers, reactions, deployables), with hand-written code only for truly unique ones.
- Order: core book frames first (their traits and core powers), then the gear they start
  with, then talents, then everything else. Each effect gets a scenario test.
- Anything not implemented yet is marked in the builder so nobody picks it by surprise.

### Narrative and campaign flow
- The full loop: **briefing → mission → debrief → downtime → level up → next mission.**
- Skill checks with skill triggers and their consequences, reserves, downtime actions
  (from the book) rolled per the rules, and procedural GM narration (section 9).
- Mission failure, retreat and pilot death have real consequences, as the book describes.

### Solo play and AI squadmates
- **Play a full 4-pilot campaign alone.** For each pilot you choose who controls it: you, or
  an AI squadmate. Control all four yourself, one and let the AI fly the rest, or anything
  in between.
- **Switch any time:** take over an AI pilot mid-mission or hand yours to the AI. When a
  friend joins online, they can take over an AI pilot (drop-in); when they leave, the AI picks
  it back up.
- **Fill empty multiplayer slots (optional):** a host setting, off by default. When on, any
  seat with no player gets an AI pilot, so a 2-person online game can still run a full squad.
  The host can choose per seat: AI, left empty, or reserved for a friend who joins later.
- **AI squadmates** use the same tactics system as enemies (section 9), on your side: they
  follow the book's rules through the same rules engine, and only know what your squad knows
  (no peeking at hidden enemies or unscanned stats).
- **Orders:** give squadmates a stance (aggressive, defensive, support, hold position, follow
  me) and focus targets; they explain their move in the log ("Moving to hard cover, heat is high").
- **Between missions:** for AI pilots you either make their builds and level-up choices
  yourself, or let the AI pick (by role: e.g. "keep this pilot a support build").

### Dialogue scenes
- **Three ways to talk:** third person (Lancer Tactics-style pop-up with portrait cards and a
  speech bubble), first person (face to face: the camera holds on the speaker's 3D face, which
  shows expressions, blinks and mouth movement, with subtitles and choices below), and
  **radio/comms** (a pop-up in a radio frame with static, callsign and channel, for orders and
  chatter over comms). Players pick first or third person any time; radio is used whenever the
  speaker isn't present. Jammed pilots can't use comms (book: Jammed), so their radio cuts to static.
- **Pop-up conversations in and out of battle,** like Lancer Tactics: character portrait
  cards on each side and a speech bubble from whoever's talking, over the live 3D scene.
  Click or press a key to advance; a log keeps every line.
- **Portraits are made in house** (no pixel art): a portrait builder for pilots and NPCs,
  matching each character's look, plus expressions (neutral, angry, worried...).
- **Choices: 4 to 6 options** when a decision matters, each leading the story a different way
  (e.g. negotiate, threaten, stall, attack, ask for terms, stay silent).
- **Options follow the story:** only choices that make sense given what has happened are
  offered: earlier decisions, who's alive, faction standing, mission state, relationships.
  A skill trigger a pilot has can unlock a matching option, still within the 4-6 cap.
- **Choices have consequences** recorded in the campaign (story flags): they change later
  dialogue, missions offered, enemies, allies and reserves.
- **Multiplayer:** the player whose pilot is speaking chooses, or the squad votes (host
  setting). AI squadmates pick in character when the conversation is theirs.
- Dialogue is written as data (scenes, lines, choices, conditions, effects) so the procedural
  GM (section 9) can assemble scenes from it and new story content can be added without code.

### Out of the mech: hubs, people and trade
- Pilots get out of their mechs and walk around towns, bases and stations in real time:
  talk to locals, faction contacts and company reps, take jobs, and use downtime actions.
  In combat, pilots can dismount, fight on foot and remount under the book's pilot rules.
- **Money, canon version:** the setting has money. **Manna** is the universal currency on
  every market outside the Core (Core p.10), and non-core worlds also use **local currencies**
  (p.126). But the rules deliberately don't track currency (p.18): access to mechs and gear
  comes from licenses, and your pilot is assumed to get what they're licensed for "by
  influence, patronage, wealth, or rank" (p.31). So in the game, manna and local money appear
  in the story (prices in dialogue, bribes, deals) but there's no tracked wallet.
- **Mechs are printed, never shipped (canon):** printing facilities are "ubiquitous on most
  occupied worlds" (p.82). With a **Full Repair** (10 hours in a secure location) you rebuild a
  mech or print any mech you're licensed for. You're licensed to field one mech at a time;
  printing a new one shuts down the old one. You never lose access to licensed gear (p.31).
  Mercenaries work the same way: licenses come with them, not shipping.
- **Custom mechs (canon):** you can change your mech's look and layout within reason; how it
  looks has no effect on gameplay (p.32). That's what the customizer does.
- **Favors and jobs, canon version:** missions start by establishing the **Reserves** the
  squad brings (p.40); Reserves (resources, favors, access, allies) are what NPCs give for
  jobs done. Downtime actions cover getting things through people: Get a Damn Drink, Get
  Connected, Get Creative, Get Focused, Get Organized, Power at a Cost, Scrounge and Barter
  (p.53-55). A company rep or local contact offering "clear out the bandits and I'll owe you"
  pays out as a Reserve, run through these rules.
- **Story inspiration from real campaigns:** official modules, actual plays and campaign
  write-ups are researched for structure, mission types, arcs and pacing (written up in
  `docs/research/`), then turned into original story tables. Nothing copied.
- **Everything else** we came up with that the book doesn't support is parked in
  "Parked: your own story additions" below, not built until you say so.

### Progression
- **Everyone starts at the bottom, like D&D level 1:** by the book, new pilots start at
  **License Level 0** with only GMS starter gear (the Everest frame and GMS weapons/systems).
  Every other manufacturer's frames and gear are unlocked rank by rank as you level up
  after missions. (A campaign option lets you start higher, as the book allows GMs to do.)
- License level up after missions, unlocking manufacturer gear by license rank, talent ranks,
  core bonuses, pilot rank; the builder enforces it.

### Menus and lobby
- Main menu, create/join game (room code), seat and pilot select, mission select, campaign
  list, settings.

### Saves
- Campaign saves, autosave between turns, resume a mission when everyone reconnects. Saves
  live outside the game folder so updates never touch them.

### Undo and action log
- Anything planned can be changed freely until you press confirm; after that it's locked.
- A full action log of the battle (who did what, every roll), and a replay from the seed.

### Accessibility and settings
- Colorblind-safe modes (important: the roll display uses blue vs. red, so they also differ by
  symbol and shape, + vs. −), UI scale, text size, rebindable keys, graphics quality presets
  for weaker PCs, animation speed.

### Audio
- No audio made by us. Use free sound effects and music that are licensed for reuse
  (CC0 / public domain), credited in-game, or ship without sound until good ones are chosen.

### Customization
Modeled on Lancer Tactics' character creator (reference only; all parts made in house, no
pixel art).

- **Pilot creator:** a big portrait preview, a grid of options for the selected part, and a
  list of parts down the side: body, face, face detail, body detail, eyes, nose, mouth,
  ears, hair, beard, mustache, eyebrows, inner outfit, outer outfit, glasses, scarves, hats,
  jewelry, other.
  - Each part has **primary and secondary colors** picked from a palette grid, plus saved
    palette presets.
  - **Expressions:** each pilot gets a set of facial expressions (smiling, angry, worried,
    shouting...) used automatically in dialogue scenes.
  - **Randomize all**, with a **lock pin** on any part to keep it when randomizing.
  - **Token tab:** the pilot's on-foot model on the battlefield, customized to match.
  - Save and load looks; Confirm / Cancel / Reset to default.
- **Mech customizer:** paint the actual equipped mech in a 3D preview with **primary,
  secondary and glow** colors (glow = lights, visors, energy parts), palette presets,
  decals and markings, randomize, reset to default. Purely cosmetic: weapons and systems
  shown are always the real loadout.
- Portraits and mechs are built from parts in our own art style (3D-rendered busts or
  illustrated parts, decided when the art work starts). Many parts are needed for "wild"
  variety, so this grows over time.
- Callsigns and names shown to everyone; looks sync in multiplayer.

### Human GM seat
- Optional: a person can run the game instead of the procedural GM: sees everything, spawns
  units, edits the map, triggers events, makes rulings. The procedural GM can still run the
  enemies while the human GM handles story.
- Built so far: "Who is the GM" (the AI, a person at the host's computer, or a friend online who
  joins as the GM). The human GM sees the whole battle and story (secrets included), has the
  story GM tools (G) in the hub and over battles, and reveals the mission twist themselves.
  The AI still flies the enemies, starts the fight, answers rules questions and calls
  reinforcements. Still to come: spawning units, the map editor, making rulings and flying
  enemies by hand.

### Milestones
1. **First playable:** one full mission start to finish, hot-seat, core frames vs.
   placeholder enemies, book rules, 3D board with overlays and roll display.
2. **Online:** the same mission with friends over the internet, launcher updating it.
3. **Builder:** mech/pilot builder with COMP/CON import; content packs (real NPC data).
4. **Campaign:** the full narrative loop, progression, saves, procedural missions.
5. **Polish:** effects coverage, animations, audio, accessibility, customization, human GM.

## 11. The main campaign and branching timelines (AI GM)

How the story works depends on who runs it:
- **AI GM:** the story is **authored**, not made up on the fly. There's one main campaign (our
  own original story, canon-consistent) with **at least 16 alternate branches**. Choices split
  the timeline: pick A, then B, then A, then C and you get a different chain of events. People
  who were friendly last playthrough may hate you this time and refuse you the item you need.
  Procedural generation only fills in small details (names, maps, enemy mixes, line variants),
  never the plot.
- **Human GM:** the GM can make anything up as they go (GM tools, map editor, GM scenes).

**No menu of solutions.** The game never offers "Fight / Steal / Find another" as a choice.
Outcomes come from what players actually do in the world:
- **Conversations escalate naturally:** insult someone, push your luck, threaten, and they may
  draw on you, which starts the fight. Apologize and walk away, and the scene ends.
- **Players come up with plans themselves:** e.g. go into the saloon, wait until night, follow
  the NPC to where they sleep, then jump them or sneak in and steal the item. That works
  because the world supports it, not because it was a listed option:
  - a day/night clock in hubs (waiting, time passing between scenes);
  - NPC schedules (where they are and what they do at each time of day, where they sleep);
  - items that physically belong to someone and are kept somewhere (on them, in a room, a safe);
  - following, sneaking, picking locks, pickpocketing and breaking in, resolved by skill checks
    (book skill triggers, e.g. Hide, Get Somewhere Quickly, Spot, Take Someone Out), with
    witnesses, alarms, and consequences (standing, bounties, a fight starting);
  - enterable interiors for the places that matter (saloon, rooms, offices, warehouses).
- **The campaign remembers:** every branch, theft, insult or kindness changes who helps or
  hinders you later in the main campaign.

### Other campaigns: a pirate career
- Besides the main campaign and generated campaigns, players can pick other story lines. First:
  **Pirate career**: the squad raids ships and stations for most of the game, with lots of fights
  and quick leveling (by the book every mission gives +1 License Level, so short raids level you
  fast, Core p.18). Union and corporate bounties escalate into the story: hunters, a bounty arc,
  and an ending that depends on how far you went. Canon-consistent: piracy is a real threat in the
  setting (Core p.126) and boarding a hostile ship is a book mission goal (Core p.42).
- **Loot, selling it, and upgrading your own ship** (better parts, printer supplies, a bigger
  ship) isn't in the book (it doesn't track money or ships), so it only works with house rules:
  the wallet rule plus a new **"Your own ship"** house rule (a squad ship with upgrade slots).
  Without them, raids pay out in Reserves, as the book does.

### Consequences, split decisions, death and clones
- **Small actions change the world:** blow up a dam and later the town's water runs short; the
  squad can make it right (fix the dam, dig a well) as a side job. Places remember.
- **Personal agendas:** hardship (e.g. a lost mech meaning short rations, with the survival rule
  on) can make a pilot the one pushing for mutiny.
- **Split decisions:** on a story-changing choice, the player who starts it doesn't have to
  convince the others in game. Each player accepts or declines, and if the squad splits, the two
  sides fight it out (player-vs-player battle, views filtered per side).
- **Death and cloning (Core p.83-84):** facsimile clones are natural-life, slow and expensive;
  flash clones are fast but mostly unlawful; revival always brings complications (the clone quirk
  table) and a memory gap back to the start of the session you died in; clones keep their LL
  (the book). Ships and cities can hold genetic templates; growing a usable clone takes in-game
  years; templates can be corrupted, tampered with or destroyed; the squad has to go back and wake
  the clone; same personality and quirks, slightly different backstory. Each player may keep one
  extra pilot (a friend, family member, partner or clone) and choose which is active.
  House rule (off by default): clones lose License Levels.

## House rules (toggles, all off by default)

A **House Rules** page in settings lists optional rules as on/off switches that can be flipped
at any time, even mid-campaign. The game stays canon until someone turns one on.

- **Who decides:** a human GM's settings win. If the GM is the AI, the host's settings are used.
  Other players see which house rules are on (and the change is announced when one is flipped).
- **Clearly labeled:** every house rule shows where it comes from ("Your idea", "Community",
  "Lancer Tactics") and that it isn't a book rule. The codex marks them the same way.
- **Your ideas** (from this design, previously parked):
  - Tracked wallet: manna and local currency with prices for food, drinks, lodging, travel,
    information, pilot supplies and repair kits; mission pay; selling salvage.
  - Frontier printers (Joe's Rules): every world has printers (book), but frontier ones don't
    always have the raw materials, power or crew to run them, and they break down more often.
    So printing there can mean a queue, a materials or access fee, bringing your own scrap, or a
    failed print that has to be redone. Core and well-funded worlds print reliably.
  - Paid travel: company/patron members ride free, independents buy passage.
  - "Can't afford it? Fight for it": an unaffordable deal becomes a generated combat job; lose
    and the deal is off, but you can come back and pay with scrap, a spare mech, manna or money.
  - Food and water as a survival need.
  - Building collapse saving roll after big hits (instead of only HP/Armor/AP, Core p.68).
  - A "brace for the fall" reaction (halves fall damage). (Stunned after a fall: removed by the user.)
- **Lancer Tactics options** (see the table below): split barrage and the big-hit Brace prompt
  are ON by your pick; repeating quick tech stays OFF.
- **Community house rules:** popular ones researched from the Lancer community (forums, Reddit,
  Discord write-ups, GM blogs), each with its source.
- Built: the House Rules panel in settings lists every switch (the rules engine's and the
  story's) by source, each with "Not a book rule", where it applies (battle / between missions)
  and a link to where it's from. A flip applies at once; a human GM's set wins, else the host's;
  every switch is announced (battle log, lobby, story log) and saved with the campaign. Not yet:
  marking them in the codex.

## Rule differences: Lancer Tactics vs. the book

Whenever Lancer Tactics handles a rule differently from the tabletop book, it's listed here
and you pick which one the game uses. The book version is used until you decide. Your choice
becomes a named option, so the other version stays available.

Sources: the Lancer Tactics developers' public FAQ and comments on itch.io
([FAQ](https://itch.io/post/15524940), [activation](https://itch.io/post/15782614),
[Aux fire](https://itch.io/post/15791508)) and devlogs
([NPC Rebake](https://wick.itch.io/lancer-tactics/devlog/937132/npc-rebake-rests-repairs-community-maps),
[talents](https://wick.itch.io/lancer-tactics/devlog/960548/keeping-the-fire-lit-more-talents)).
Lancer Tactics says it keeps "extremely close" to the book, so the list is short. Rows with
an option name are switches on the House Rules page (`HouseRuleSwitches`, `state.house_rules`).

| Rule | Book | Lancer Tactics | Why LT might do it | Your pick |
|---|---|---|---|---|
| Firing two weapons (option `lt_split_barrage`) | Two weapons only as a Barrage, a full action with both shots together; Skirmish (one weapon) once per turn (Core p.60, p.64) | Two "action points" instead of quick/full actions; each mount costs 1, so two weapons are two separate shots and you can move between them | One simple action currency is easier to show on a video-game action bar, and moving between shots gives more positional play | **Lancer Tactics** (on by default; fire, move, fire) |
| Repeating a Quick Tech option (option `lt_repeat_quick_tech`) | Quick Tech can be taken twice, but each time a different option (Core p.69) | The same option can be used twice (e.g. two Invades) | Falls out of the action-point system; fewer "why is this greyed out?" moments | **Book** (no repeating the same option) |
| When Brace is offered (option `lt_brace_prompt`) | Brace whenever an attack hits and deals damage (Core p.73) | Only offered when the hit would structure or stress you, or deal more than half your HP | Stops a pop-up after every hit; Brace is mostly worth it on big hits anyway | **Lancer Tactics** (on by default; only asked on big hits) |
| Firing only the Aux weapon of a mount | A Skirmish's main attack can be an Auxiliary weapon and deals bonus damage as usual; only the extra Aux shot gets none (Core p.64, p.67) | Firing just the Aux on a mount that also has a Main counts as firing the mount, with no Aux bonus damage | Follows from attacking "per mount" instead of "per weapon" | Book by default; Lancer Tactics available as the house-rule switch `lt_aux_mount` |
| Flying | Flyers choose their altitude freely as they move and must move at least 1 space each turn or fall (Core p.63) | Flying is an on/off state that puts you 3 spaces above the surface | Much simpler camera, targeting and pathing in 3D | Book by default; Lancer Tactics available as the house-rule switch `lt_flight_fixed` |
| NPCs | The core book's NPC classes, tiers and templates (Veteran, Elite, Ultra...) | Uses "NPC Rebake" (a community revision by Kai): no extra attacks from tier, reworked Veteran/Ultra options | Better balance for automated enemies; LT notes it is a deliberate divergence | |
| Pilots fighting on foot | Pilots can leave or eject from their mech and act on foot (Core p.71) | No pilot combat | Scope: LT is about mech battles | |
| Talents that need a table call | Leader's "commands", Skirmisher 2 (works off Skirmish) and Bonded's bondmate are played as written | Being redesigned or possibly skipped, because LT has no Skirmish action or open-ended commands | Open-ended talent text doesn't fit an automated game | |

## Build plan: parallel sessions

Keep usage efficient on the 5-hour and weekly limits: **at most 3 sessions working at once**,
each with a narrow, self-contained brief, and a new piece only starts once one finishes.

1. **Foundation (this session, first, not parallel):** repo, folder layout, the shared
   interfaces everything else codes against: game-state format, action/event messages,
   grid layer (hex + square), loading the `lancer-data` content.
2. **Then up to 3 at once, each in its own worktree/branch:**
   - **Rules engine + sanity checker:** actions, combat, heat/structure, statuses,
     Hidden/visibility, rule citations, scenario tests.
   - **3D renderer + animations:** in-house procedural mechs, camera, grid rendering,
     the animation catalogue in section 1.
   - **Networking + launcher:** WebRTC peer-to-peer, per-player filtered views, room
     codes, GitHub Release auto-updater, .exe packaging.
3. **After the engine lands:** procedural GM (mission generation, enemy tactics, events),
   then campaign layer
   (missions, downtime, licenses, leveling). This session merges branches and runs the
   full checks.

## Publishing (if you ever release it)

- **Engine cost: $0.** Godot is MIT-licensed: no fees, no royalties, no splash screen, no
  account. Just include Godot's license notice in the credits.
- **Free places to publish:** GitHub Releases (already the update channel) and itch.io.
  Steam charges a $100 fee per game, so it's not free.
- **Our own code and models:** all made in house. The mech models are faithful recreations of
  Massif's frame designs, so publishing them needs Massif's permission even though we built them.
- **The Lancer IP is the real question, not the engine.** Lancer belongs to Massif Press.
  Before publishing, check Massif's third-party license / community content guidelines for
  what's allowed (name, logo, rules text, game data, free vs. paid). A full digital adaptation
  may need their permission, especially if you charge for it. Personal play with friends is a
  different situation from public release.

## Content sources

- **Player content:** Massif Press `lancer-data` (official JSON): frames, weapons, systems,
  talents, core bonuses, statuses, downtime, sitreps, glossary rule text. In
  `data/lancer-data/` (v4.0.12, GPL-3.0).
- **NPCs:** not public (removed from `lancer-data` by Massif in 2020). Loaded from your own
  copy of the official NPC content pack; see section 10.
- **Rules text and campaign books:** from you where needed.
- Check Massif's third-party content guidelines before sharing the game outside your group.

## Open items

- [ ] NPC book / NPC data
- [ ] Campaign books you want to run
- [x] Godot 4.7.2 installed at `A:\godot`
- [x] Blender 5.2.2 at `A:/blender-5.2.2-windows-x64`
- [ ] Godot export templates (1.3 GB, needed to build the .exe)
- [x] Repo visibility: **public**. Only our own code and Massif's published data go in it;
      rulebook text stays local and is never committed.
- [x] Online connection method: **peer-to-peer (WebRTC)**. Note: some strict networks may
      need a TURN relay as a fallback.
- [x] GitHub repo: https://github.com/Gabensrightnut/lancer-ttrpg (public)
- [x] Project license: **GPL-3.0-or-later** (matches Massif's data license)
