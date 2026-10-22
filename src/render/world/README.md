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
| nothing | open ground: grass, flowers, pebbles, glow plants, all under 0.18 tall |

Buildings: walls sit exactly on the cell edges and rise exactly to the column's top; the
roof is where units stand. Parapets, battlements, eaves, signs, awnings and antennas stay
under 0.15 or flat against the wall. Rooftop props are small.

The look tags (`rock`, `woods`, `building`, `wall`, `water`, `ice`, `lava`, `toxic`,
`crystal`, `rubble`, `chasm`) never change rules. Rules come only from `difficult`,
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
| `skyline.gd`, `sky_traffic.gd` | The city around a city map; burning towers; sky traffic |
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
