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
  follows each action, there's a short pause before attacks resolve, and the roll is shown.
  Speed setting (cinematic / normal / fast) and a "skip to my turn" option; never faster
  than you can follow unless you choose it.
- **Scenes, not just fights (like BG3's exploration vs. combat):**
  - **Exploration and story scenes:** walk your pilot or mech around a location in real time,
    talk to people (dialogue scenes, section 10), inspect things, find intel and supplies.
  - **Skill checks shown big:** a d20 roll pops up center screen with your skill trigger
    bonus and Accuracy/Difficulty (blue/red) against the target, BG3-style, with outcomes
    that branch the scene.
  - **Combat starts from the scene:** ambushes, failed sneaking, or a dialogue choice drop
    everyone into turn-based combat on the same map. Surprise follows the book.
  - **Downtime between missions** as its own scene (section 10).
- **Multiplayer:** in exploration everyone moves freely; in combat each player acts on their
  own pilot's turn while others watch (and can ping and chat); dialogue choices go to the
  speaking pilot's player or a vote.

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

Every roll is shown step by step on screen, then logged:

1. **Base roll:** the d20 rolls and lands on its number.
2. **Accuracy and Difficulty:** Lancer's version of advantage/disadvantage. Each source is
   listed with what caused it (e.g. "Lock On", "Soft cover", "Impaired").
   - **Accuracy:** blue **+** with a blue d6 per point.
   - **Difficulty:** red **−** with a red d6 per point.
   - They cancel one for one (the rules), shown by matching blue and red pairs fading out
     together. Whatever is left is rolled, and only the highest d6 counts: added if blue,
     subtracted if red.
3. **Flat bonuses:** Grit, Tech Attack, etc. added as their own labeled numbers.
4. **Result:** total vs. the target number (Evasion, E-Defense, save target...), then HIT /
   MISS / CRIT with the matching attack animation.
- **Display format:** the base roll first, then each modifier right after it, colored:
  `6` **`+4`** (blue, Accuracy d6) `+2 Grit` `= 12 vs Evasion 8: HIT`, or with Difficulty
  `6` **`−3`** (red) `+2 Grit` `= 5: MISS`. (Accuracy and Difficulty cancel first, so only one color of d6 is ever left.)
  Blue = anything that helps the roll, red = anything that hurts it.
- Damage rolls work the same way (dice, bonuses, Armor reducing it, resistances halving it).
- Speed setting: full animation, quick, or instant (log only) for when you know the game.

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
  - **Tactical (default):** angled, rotatable overhead view of the whole board.
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
  20x20 to 40x40 spaces depending on mission type and squad size), not small test boards.
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
- **Show the math:** every roll shows its breakdown (d20 + Grit + accuracy/difficulty vs.
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

### Milestones
1. **First playable:** one full mission start to finish, hot-seat, core frames vs.
   placeholder enemies, book rules, 3D board with overlays and roll display.
2. **Online:** the same mission with friends over the internet, launcher updating it.
3. **Builder:** mech/pilot builder with COMP/CON import; content packs (real NPC data).
4. **Campaign:** the full narrative loop, progression, saves, procedural missions.
5. **Polish:** effects coverage, animations, audio, accessibility, customization, human GM.

## Rule differences: Lancer Tactics vs. the book

Whenever Lancer Tactics handles a rule differently from the tabletop book, it's listed here
and you pick which one the game uses. The book version is used until you decide. Your choice
becomes a named option, so the other version stays available.

| Rule | Book | Lancer Tactics | Why LT might do it | Your pick |
|---|---|---|---|---|
| (none found yet) | | | | |

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
- [ ] Godot export templates (1.3 GB, needed to build the .exe) and Blender
- [x] Repo visibility: **public**. Only our own code and Massif's published data go in it;
      rulebook text stays local and is never committed.
- [x] Online connection method: **peer-to-peer (WebRTC)**. Note: some strict networks may
      need a TURN relay as a fallback.
- [x] GitHub repo: https://github.com/Gabensrightnut/lancer-ttrpg (public)
- [x] Project license: **GPL-3.0-or-later** (matches Massif's data license)
