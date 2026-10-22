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

## What you see is what the rules use

Every look comes from the map data. Nothing that looks like cover or an obstacle exists
without the map saying so, and the checks in `tests/unit/test_render_world.gd` hold it.

| Map data | Looks like |
|---|---|
| raised column (`ground` > neighbors) | cliff, rock stack (`rock`), crystal prisms (`crystal`), wall (`wall`), building (`building`, or any plain raised column in a city) |
| `soft_cover` | woods: trees, bamboo, glowing fungus (only here) |
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
$G --path . -s res://src/render/world/world_bench.gd -- high      # or medium / low, then kits
```

RTX 3080, 1080p, generated 40x40 maps with 8 mechs, vsync off. Average fps across five kits
(hills/medieval, neon city, alien wilds, desert/Old West, burning city) at a wide and a close
camera: high 177-274 (1% low 78-210), medium 162-336, low 306-512 (1% low 210-340).

