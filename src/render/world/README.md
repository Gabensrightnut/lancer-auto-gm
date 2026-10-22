# World rendering: battlefields that look like what the rules say

`TerrainRenderer.build(map, kit)` draws a `BattleMap` in a world style. The style is a
**landscape** plus an optional **culture**: kit names are `"landscape"` or
`"landscape/culture"` (`"grassy_hills"`, `"desert_mesas/old_west"`, `"city/cyberpunk"`).
Old names still work: `"urban_ruins"` is `"city/ruins"`.

All art is made here in code and shaders. No textures, models or images from anywhere else,
and no CC0 assets yet (so no CREDITS entries are needed for this folder).

## Data

- `data/game/biomes/landscapes.json`: ground palette and style (grass, sand, snow, moss,
  paving, ash), liquids, plants, horizon (land shape, far range, landmarks, storms, sky
  creatures), air particles, sky and light. `"base"` inherits another landscape.
- `data/game/biomes/cultures.json`: overrides any landscape field and adds `architecture`
  for buildings (materials, wall palette, floors, windows, roofs and roof edges, signs,
  neon, holo ads, street props, skyline).
- `WorldStyle.resolve(kit)` merges them; `WorldStyle.landscapes()` / `cultures()` list them.
- The mission generator (`src/gm/terrain_gen.gd`) picks a landscape and culture, builds the
  map for it, and puts the kit in `mission.flavor.kit`.

## Landscapes, cultures and weather

Landscapes: grassy_hills, desert_mesas, tundra, volcanic, molten_world, alien_wilds,
crystal_fields, toxic_marsh, toxic_swamp, city, station, starship, moon, asteroid, ocean,
jungle. Cultures: ruins,
cyberpunk, burning, medieval, old_west, retro, east_asian, union. Weather (`data/game/biomes/
weather.json`): clear, rain, storm, snow, blizzard, sandstorm, ashfall, spores, mist. A kit can
end in `+weather`: `"jungle+rain"`, `"desert_mesas/old_west+sandstorm"`. The mission generator
picks weather to suit the landscape (`opts.weather` overrides) and puts it in `flavor.kit`.

**Weather is look only.** Particles, fog, clouds, darker light, lightning flashes. A storm that
should *do* something in the rules comes from a LANCER environment (lancer-data
`environments.json`), which the rules engine applies; weather.json names the matching one in
`environment` (sandstorm: `env_particulatestorms`, storm: `env_electricalstorms`, blizzard:
`env_extremecold`) so a mission that uses that environment can show it. Landscapes name theirs
too: molten_world `env_moltenworld` (its lava cells are tagged `lava`), toxic_swamp
`env_primordealworld` (boiling mud: difficult + dangerous). Low gravity on moons
and asteroids is also look only (slow-hanging dust); its rules are `env_lowgravity`.

## Sitrep objectives on the board

`TerrainRenderer.show_objectives(zones, deployment, show_deployment = true)` draws a mission's
zones (`Mission.zones`, name -> [[x, y]]) and deployment zones: tinted floor with a bold
pulsing border, a light beacon and a label ("ZONE A", "ZONE", "EXTRACTION", "OBJECTIVE");
extraction pads get landing rings and blinking lights; deployment zones a soft blue/red tint
(pass `show_deployment = false` once the battle starts). Flat or thin: never cover. Redrawn on
rebuilds; `show_objectives({})` clears it. Pass only what the seat may know (Recon's True
Control Zone is a host secret and is never marked).

Layouts per sitrep come from `src/gm/sitrep_layout.gd`; fairness checks and repairs from
`src/gm/map_fairness.gd` (cover balance, hidden deployment, reachability for Size 1-3), run by
`MissionGenerator.battlefield()` and tested for 50 seeds per landscape
(`tests/unit/test_gm_fairness.gd`).

## Destroyed terrain

`TerrainRenderer.sync_map(new_map)`: give it the rules' current map (e.g. from a fresh view
after an attack). Every destructible column that got lower collapses on screen (the lost part
shudders and sinks, chunks fly, dust rolls out) and the board rebuilds from the new data. What
is left is exactly the new data: if the rules tagged the cell difficult it shows rubble; if
not, only flat debris. `break_cells(cells, {cell: old_ground})` does the same for known cells.

Buildings come down in pieces: each lost floor's wall panels (the building's own facade) peel
off and topple outward from the top, floor slabs drop, debris and dust. City generation tags
low buildings `destructible` (up to 3 levels; 4 in ruined/burning cities) and MapFairness keeps
destructible cover balanced between the two halves.

## Close-up (cockpit) detail

Shaders clamp bump slopes and fade fine grain by pixel footprint, so seams and cracks read as
soft grooves at mech-eye height instead of sparkling; natural faces use a coordinate that runs
on across facets; building seeds are quantized (no per-pixel speckle). Preview the cockpit
view with the `@eye` tag; `world_bench.gd` measures an `eye` camera too.

## What you see is what the rules use

Every look comes from the map data. Nothing that looks like cover or an obstacle exists
without the map saying so, and the checks in `tests/unit/test_render_world.gd` hold it.

| Map data | Looks like |
|---|---|
| raised column (`ground` > neighbors) | cliff, rock stack (`rock`), crystal prisms (`crystal`), wall (`wall`), building (`building`, or any plain raised column in a city) |
| `soft_cover` | woods: trees, bamboo, glowing fungus (only here) |
| raised `bulkhead` / `container` / `machinery` / `platform` | station and ship walls (3 levels: full cover), cargo containers, machinery blocks, raised decks and walkways |
| `difficult` | rough ground: stones, scree, ice chunks, rubble, cinders (flat, under 0.18) |
| `difficult` + `water` / `ice` | river or frozen lake sunk below its banks |
| `dangerous` | cracked ground glowing through, low flames, embers, flickering light |
| `dangerous` + `lava` / `toxic` | lava flow or glowing toxic pool |
| `impassable` at ground level (or `chasm`) | a deep chasm, no grid lines |
| `impassable` raised | sheer rock spire |
| `destructible` | crack web on the surface; `break_cells()` bursts it into chunks and dust |
| `gap` (overhang) | bridge deck with girders and a low railing |
| `road` (+ `road_x` / `road_z` / `crossing`) | street in the culture's paving: dirt ruts, cobbles, asphalt with lane lines and zebra crossings, Union panels with guide lights; over water a bridge |
| `farm` (+ `dry`) | crop rows (no rules effect) |
| `house` / `keep` | village house (eaves instead of battlements in medieval kits) / castle keep |
| nothing | open ground: grass, flowers, pebbles, glow plants, all under 0.18 tall |

Buildings: walls sit exactly on the cell edges and rise exactly to the column's top; the
roof is where units stand. Parapets, battlements, eaves, signs, awnings and antennas stay
under 0.15 or flat against the wall. Rooftop props are small.

The look tags (`rock`, `woods`, `building`, `wall`, `water`, `ice`, `lava`, `toxic`,
`crystal`, `rubble`, `chasm`, `road*`, `crossing`, `farm`, `dry`, `house`, `keep`) never
change rules. Rules come only from `difficult`,
`dangerous`, `impassable`, `destructible`, `soft_cover` and the heights.

## Files

| File | What it does |
|---|---|
| `../terrain_renderer.gd` | Blocks (terraced columns, smoothed cliff lighting), grid lines (two-tone, toggle-able), surface kinds, `break_cells()` |
| `world_style.gd` | Loads and merges landscape + culture data |
| `atmosphere.gd` | Sky shader, sun, fog, volumetrics, glow and grading per style |
| `world_dressing.gd` | Liquids, ground cover, rough ground, woods, rock stacks, crystals, glow plants, railings |
| `world_hazards.gd`, `flicker_light.gd` | Fire and glow on dangerous ground |
| `world_horizon.gd` | Land that carries on from the board's edges, rivers out of the map, forest, far ranges, storms |
| `landmarks.gd`, `spinner.gd` | Castle, windmill, water tower, headframe, domes, saucer tower, monorail, pagoda, torii, white towers, space elevator |
| `skyline.gd`, `sky_traffic.gd`, `ground_traffic.gd` | The city around a city map (plain, stepped, eight-sided, twin and split-crown towers, spires with aircraft lights); burning towers; sky traffic; cars driving its streets |
| `city_streets.gd`, `vehicles.gd`, `traffic_light.gd` | Street life on `road` cells by culture: parked vehicles, traffic lights, kiosks, steam vents, overhead wires and lanterns |
| `city_builder.gd`, `city_props.gd` | Buildings on grid footprints; roofs, signs, neon, holo ads, street props |
| `sky_beasts.gd` | Huge drifting creatures over alien horizons |
| `flora.gd` | Tree, bush, cactus, bamboo, blossom, alien plant, grass, flower and rock meshes |
| `terrain_break.gd` | Destroyed terrain chunks and dust |
| `world_preview.gd` | Screenshot scene (`scenes/world_preview.tscn`) |
| `world_rand.gd` | Stable scatter hash (MeshKit.hash01 clusters for neighboring indices) |

Shaders: `terrain_world`, `building`, `sky_world`, `far_land`, `foliage`, `water` (also ice),
`toxic` (also lava), `storm`, `holo`.

## Screenshots

```bash
G=A:/godot/Godot_v4.7.2-stable_win64_console.exe
# map: hills | urban | alien | truth (every terrain kind) | gen<seed>[+landscape[+culture[+size]]]
# kit override: map=landscape-culture ; view: @wide (default) @close @vista @top @break @x,z,dist,pitch,yaw
$G --path . -s res://tools/screenshot.gd -- res://scenes/world_preview.tscn "out_%s.jpg" 6 truth urban=city-cyberpunk@vista gen4+desert_mesas+old_west
```

`TerrainRenderer.profile = true` prints build time per step (a 40x40 map builds in 1-3 s).

## Readability

- A light rim runs along every edge where the ground drops: on the top surface and along the top
  of cliff faces and building walls. Night styles make it glow (`ground.rim`, `rim_strength`,
  `rim_glow`; `architecture.rim*` for roofs).
- Land and buildings outside the board are darker and greyer (`ground.backdrop_fade`), and the
  board's outer edge has a bold border, so the playable area is always clear.
- Grid lines are two-tone: a line over a soft shade band. Bright styles (snow, sand, crystal)
  use dark lines (`grid_color`, `grid_shade`).

## Quality presets and frame rate

`WorldQuality.set_preset("high" | "medium" | "low", viewport)`, before building a board.
Medium drops SSIL, SSR and shadow splits and thins scenery. Low also turns off SSAO and
volumetric fog, uses one shadow split, thins grass, trees, particles and lights, and renders
at 75% with FSR upscaling. The settings menu should call it and save the choice.

```bash
$G --path . -s res://src/render/world/world_bench.gd -- high      # or medium / low, then kits (wide, close, eye cameras)
```

RTX 3080, 1080p, generated 40x40 maps with 8 mechs, vsync off. Average fps across five kits
(hills/medieval, neon city, alien wilds, desert/Old West, burning city) at a wide and a close
camera: high 177-274 (1% low 78-210), medium 162-336, low 306-512 (1% low 210-340).


## Hub towns at walking scale (`world_kits.gd`)

The same cultures for on-foot hubs (story's `src/explore`), in meters. Every culture argument
takes story's ids (`medieval_tech`, `retrofuturistic`, `union_core`, `frontier_colony`, ...)
or map ids. Nothing carries text: sign boards are blank, the caller adds names.

```gdscript
# A building for a HubLayout spot: origin at the footprint center, door toward +Z.
var b := WorldKits.build_hub_building(hub["culture"], spot, hub["seed"])
b.position = Vector3(spot["pos"][0], 0, spot["pos"][1])
b.rotation.y = atan2(-b.position.x, -b.position.z)   # face the plaza, as HubScene does
add_child(b)
# Props in the culture's style (kinds that suit it come first), and the plaza centerpiece.
for kind in WorldKits.hub_prop_kinds(culture):
	var p := WorldKits.build_hub_prop(culture, kind, i)   # footprint WorldKits.PROP_RADIUS[kind]
add_child(WorldKits.build_hub_centerpiece(culture, seed))   # within 1.6 m of the center
var colors := WorldKits.hub_ground(culture)                 # {"ground", "pave"} Colors
WorldKits.apply_hub_environment(culture, environment, sun)  # sky, sun and fog
```

Walls stay inside the spot's `size` [w, d, h]; roofs, porches, awnings and signs reach out at
most `ROOF_OVERHANG` (0.6 m) at the sides and back, and porches up to 2.7 m in front (Old West
boardwalk), so keep a clear path at the door. Doors are 1.3 x 2.3 m (3.2 x 3.4 m roll-up
shutters on workshops and printer bays). Landing pads and plazas return an empty node.

| Culture | Buildings | Props | Centerpiece |
|---|---|---|---|
| medieval | stone and timber frame, tiled gable roofs, arched windows, banners, hanging signs, lanterns | braziers, barrels, crates, carts, benches | well with a roofed winch |
| old_west | wood siding, false fronts, covered boardwalks, hitching rails | barrels, crates, carts, lantern posts | trough and windpump |
| retro | pastel plaster, chrome rims, rounded canopies, pylon signs | globe lamps, bright benches, planters | fountain |
| east_asian | plaster and wood, hipped roofs with upturned eaves, lanterns | stone lanterns, blossom planters, benches | blossom tree on a stone ring |
| cyberpunk | metal and glass, neon strips, blade signs, holo ads, shutters | neon posts, crates, barrels | holo pylon |
| union | white and glass, clean canopies with light strips | light columns, planters, benches | fountain |
| "" (frontier) | prefab metal and concrete, struts and awnings | crates, barrels, lamp posts | well |

Preview: `world_preview.tscn` tags `hub-<culture>` (e.g. `hub-medieval_tech`, `hub-union_core`).

## Map editor

`scenes/editor/map_editor.tscn` (`src/ui/editor/`): paint height (raise, lower, level), terrain
presets in plain words (woods, water, fire, lava, rubble, rock, wall, building, chasm...),
breakable/sturdy, deployment zones and sitrep zones; pick landscape, culture, weather and
sitrep ("Lay out zones" uses SitrepLayout); a live fairness panel (MapFairness); mirror
painting for symmetric maps; new blank / generated maps; save and load in user://maps/;
"Play this map" emits `play_requested(doc)` for the caller to start a mission with
`{"map_doc": doc}`.

Every edit is a GM action (`MapEditorModel` -> `gm_edit_terrain` / `gm_edit_objectives`).
Before a mission it runs on a private GameState; live, `start_live(engine, state, kit)` uses
the mission's own, and `edited(events)` gives the host the events to send to every seat
(clients refresh the board on `terrain_edited` and the zones on `objectives_changed`).

## Map sizes, towns and materials

- Generated maps are 30-60 per side, from squad size and sitrep (`missions.json` "map_sizes";
  `MissionGenerator.map_size()`), usually longer than wide. The GM's approach dial keeps the
  deployment zones that many rows apart on every sitrep (SitrepLayout's battle band); the rest
  is flanking room. 60x60: generate 0.3-1.3 s, build about 2.7 s.
- A fight in a hub's town (`generate(seed, {"hub": story.hub})`) is built from the hub's own
  layout (HubLayout spots at about 2 m per space): the same buildings around the same plaza,
  1-2 levels, real cover, destructible, plus houses along the streets, in the hub's culture.
- Materials (Core p.68): `material_wood|stone|concrete|metal|fortified|hull` and `armor_N`
  tags on built and natural cover (TerrainGen.MATERIALS: Old West/frontier/East Asian wood 0,
  medieval stone 1 (town walls 2), cities concrete 1, Union fortified 3, station bulkheads 3,
  starship hull 4, rock 2). The rules read `armor_N`; objects always have 5 Evasion and 10 HP
  per Size 1 section. Hits (`TerrainRenderer.hit_terrain`, event terrain_damaged): wood
  splinters, stone and concrete chip and puff dust, metal and fortified walls spark and dent.
  `show_damage(state.terrain_damage)` deepens the cracks as a section wears down; destroyed
  wood breaks into planks, metal into bent plates.

## Built on purpose, and lived in

Maps read as places people made, not noise (`TerrainGen`):

- **Villages** (`_village`): a levelled site, a main street across the map with a cross street,
  houses on 2x2 / 3x2 plots facing the streets (mostly one storey), and fields on terraces
  around it with field walls in straight runs and a gateway gap.
- **Castles** (medieval, `_castle`): straight curtain walls (2 levels) with 2x2 corner towers
  (3), a 2-wide gate facing the village on the main street's row, a causeway over the moat
  (water, difficult), a keep against the back wall, and a cleared field of fire. The village is
  built first and the castle last, so nothing overlaps the walls.
- **Roads** (`_road`) follow the ground and bridge rivers (deck one level up, river beneath).
  City streets are tagged from the street grid (`_tag_streets`): open runs of 6+ become lanes,
  crossings where buildings sit on the diagonals, plazas stay paved without lanes.
- **Rocks** (`_outcrops`) come in clusters (a tall core, lower stones), at least 4 spaces from
  anything built and 2 from water, buildings and roads.

Street life by culture (`architecture.street` in `cultures.json`: `road`, `vehicles`,
`traffic_lights`, `kiosks`, `vents`, `wires`, `lanterns_on_wires`): Old West wagons on dirt,
medieval carts on cobbles, cyberpunk cars, vans and bikes with traffic lights, kiosks, steam and
wires, retro finned cars, East Asian scooters under lantern wires, Union hover-pods on lit
panels, ruins and burning cities wrecks. Vehicles are about a quarter of a mech's height and
are scenery only: the rules see no cover in them.

## Every city its own look

A culture's `in_city` block (cultures.json) applies only on a city map: its sky, light and
ground palette. Medieval: misty morning in stone streets. Old West: hot gold afternoon. East
Asian: soft pink-hazed morning. Union: bright noon over white towers. Retro: sunny pastels.
Ruins: grey overcast. Cyberpunk: the wet neon night. Industrial: smoggy amber, brick and tanks,
smokestacks. Port: clear harbor morning, a basin with a quay, container stacks, cranes. City
weather follows the culture (`TerrainGen.CITY_WEATHER`).

Only the mega-cities (`TerrainGen.MEGA_CITIES`: cyberpunk, Union) build towers; every other
city is like a city on modern Earth: mostly 1-2 levels, some lots left empty, alleys between
buildings, low skylines. Nothing tall stands between the camera and the board.

Landscapes can chain `base` (boarding -> starship -> station); the nearest overrides last.

## Boarding (ship to ship)

`boarding`: two ships docked side by side. Each side fights from its own ship's outer hull:
armor ridges (bulkhead, straight runs), turret housings (machinery), clamped cargo
(containers), behind an armored hull rim (Armor 4, Core p.68 objects) with hatches. Open space
between the hulls is impassable; boarding tubes (2 wide, deck) cross it. A boarding torpedo
has punched through each hull: a hole in the rim, its body in the deck, wreckage (difficult).
The far ship is the near one turned around, so both sides get the same ground. Beyond the board
(`SpaceScenery._docked`) both hulls run on with the gap between them, armor belts down their
flanks, more docking tubes, and the far ship's superstructure.

Ship interiors for boarding fights (`TerrainGen._ship_interior`; enemies hold the top of the
map, the squad the bottom): the outer hull (Armor 4) runs down both side edges; rooms by role
from the boarders' edge: cargo holds and the airlock bay, then quarters (bunks), engineering
(reactor housings, coolant leaks) and the mess, then the bridge (console banks). Inner
bulkheads are breakable more often than a station's; bunks, tables, consoles and crates break.
- `boarding_defend` (story map "own_ship"): pirates board the squad's ship; two boarding
  torpedoes have punched through the side hulls near the top (wreckage around them, the
  torpedo tails outside the hull). Red alert light.
- `boarding_assault` (story map "enemy_ship"): the squad boards; a docking airlock in one side
  hull near the bottom, the boarding tube running off to the other ship. Rusty, amber light.
- `boarding` (story map "docked"): the two docked hulls above.
`MissionGenerator.generate(seed, {"boarding": {"kind": ..., "map": "docked" | "enemy_ship" |
"own_ship"}})` picks the map; mission.flavor.boarding keeps the dict.

## Hub day and night (story clock)

`WorldKits.apply_hub_environment(culture, env, sun, period)` lays the clock's time of day
(`TownLife.period`: dawn, day, evening, night; `WorldKits.TIMES`) over the culture's own look:
low pink dawn sun from the east, the kit's own daylight, a gold evening sun in the west, blue
moonlit night with stars. The neon city's kit is its night; by day it is a grey smoggy overcast
with the signs still on. `WorldKits.set_hub_time(world, period)` switches the built town:
lamps, lanterns and fires (lights with meta `hub_night_light`) burn at dawn, evening and night,
and more windows are lit the later it gets. The hub scene calls both on every rebuild (waiting
rebuilds it). Preview: `hub-<culture>~<period>[@close]`.

## Interiors (`interiors.gd`, `data/game/interiors.json`)

One shared kit for walking inside key buildings. A kind is data: rooms (rect, floor, `use`),
doors (rooms, position, width, lock 0-2, kind door/hatch/bars/arch), stairs and extra
containers. Furniture comes from the room's use (bar, bedroom, storage, office, study, cell,
bridge, captain, bunks, commons, engineering, cargo, sleepers, control), placed clear of doors
and stairs. `Interiors.layout(kind, culture, seed)` returns plain data for story: rooms (ids
match TownLife's), doors with locks, containers (lock, `contents` for story to fill), sleep
spots, and stand/sit/work/hide points. `Interiors.build(layout)` builds it: walls merged per line
with doorways and frames, floors with stair openings, a "Ceiling" node a camera can hide, one
light per room, doors that `set_door()` swings or slides. Culture picks materials (planks,
stone, plaster, neon-dark, white); ship kinds are metal with strip lights.
Story's own spot kinds and more: `office` (front office, back office with the safe, records),
`inn` (common room, kitchen, five guest rooms upstairs), `market` (store floor with counter and
shelves, storeroom), `warehouse`, `workshop` (mech gantry, benches, a loft up the stairs),
`printer` (fabricator bed, hoppers, control room with the license vault), `house` (front room
with a hearth, bedroom, pantry), `chapel` (pews, altar, vestry), `clinic` (waiting room, ward,
surgery). Kinds also: `bar` (saloon: bar room, back room with the safe, stairs, upstairs corridor, three
rooms and the owner's), `marshal` (front office, three barred cells, the marshal's office with
a safe), `ship_deck` (bridge, captain's quarters, crew bunks, commons with stalls, engineering
with the reactor and the NHP casing, cargo bay), `sleeper_vault` (rows of cryo pods, control
gallery). Preview: `in-<kind>[~culture]@eye|top|up|<room id>`.

## Exploring areas (mech scale, real time)

`MissionGenerator.area(seed, {hub, region, landscape, culture, weather, size, shape})` makes the
ground for a WorldSession / NetRoom area: the hub's town at mech scale in the middle (or the
landscape's own settlement), countryside around it, roads along the middle row and column out
to all four edges, and a level band `TerrainGen.AREA_EDGE` wide along every edge. Areas of one
region (same `region`) look the same and meet on the same roads, so walking off one edge comes
in on the next area's opposite edge. Fights start right there on the area's map. Returns {map,
kit, region, name, center, entries {west, east, north, south}}. Preview: `area<seed>+town+<culture>`
or `area<seed>+<landscape>[+<culture>]`.

## Autumn forest and salt flats

`autumn_forest` (base grassy_hills): rolling hills and denser woods in red, orange and gold,
falling leaves (`particles: "leaves"`), soft gold light; medieval, East Asian, Old West or Union
settlements. `salt_flats` (base desert_mesas; `TerrainGen._flats`): dead level white crust,
cracked soft patches (difficult), low pressure ridges in straight runs (one level), rare rock
islands, old mine spoil heaps; little cover, so the open ground is the danger. Old West, retro
or industrial mining towns.
