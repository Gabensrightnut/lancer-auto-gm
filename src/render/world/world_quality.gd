class_name WorldQuality
extends RefCounted
## Graphics quality presets for battlefields. "high" is the full look; "medium" and "low" are
## for weaker PCs. Set it before building a board (scenery density is read at build time):
##   WorldQuality.set_preset("low", get_viewport())
## A settings menu can call this; the choice should be saved with the player's settings.

const PRESETS := ["high", "medium", "low"]

## The active preset's values (see _VALUES).
static var preset := "high"
static var v: Dictionary = _VALUES["high"]

const _VALUES := {
	"high": {"ssao": true, "ssil": true, "ssr": true, "volumetric": true, "glow": true,
		"shadow_distance": 60.0, "shadow_splits": 4, "shadow_size": 4096, "scenery": 1.0, "grass": 1.0,
		"particles": 1.0, "lights": 1.0, "render_scale": 1.0, "msaa": Viewport.MSAA_DISABLED, "taa": false},
	"medium": {"ssao": true, "ssil": false, "ssr": false, "volumetric": true, "glow": true,
		"shadow_distance": 45.0, "shadow_splits": 2, "shadow_size": 2048, "scenery": 0.7, "grass": 0.6,
		"particles": 0.6, "lights": 0.6, "render_scale": 1.0, "msaa": Viewport.MSAA_DISABLED, "taa": false},
	"low": {"ssao": false, "ssil": false, "ssr": false, "volumetric": false, "glow": true,
		"shadow_distance": 35.0, "shadow_splits": 1, "shadow_size": 1024, "scenery": 0.4, "grass": 0.3,
		"particles": 0.35, "lights": 0.3, "render_scale": 0.75, "msaa": Viewport.MSAA_DISABLED, "taa": false},
}


## Picks a preset and applies the viewport-wide parts (render scale, shadow atlas size).
static func set_preset(name: String, viewport: Viewport = null) -> void:
	if not _VALUES.has(name):
		name = "high"
	preset = name
	v = _VALUES[name]
	RenderingServer.directional_shadow_atlas_set_size(int(v["shadow_size"]), true)
	if viewport:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if float(v["render_scale"]) < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = float(v["render_scale"])
		viewport.msaa_3d = v["msaa"]
		viewport.use_taa = v["taa"]


## Environment and sun settings for the preset (called by WorldAtmosphere.apply).
static func apply_environment(env: Environment, sun: DirectionalLight3D) -> void:
	env.ssao_enabled = v["ssao"]
	env.ssil_enabled = v["ssil"]
	env.ssr_enabled = env.ssr_enabled and v["ssr"]
	env.volumetric_fog_enabled = env.volumetric_fog_enabled and v["volumetric"]
	env.glow_enabled = v["glow"]
	sun.directional_shadow_max_distance = float(v["shadow_distance"])
	sun.directional_shadow_mode = {1: DirectionalLight3D.SHADOW_ORTHOGONAL, 2: DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS}.get(int(v["shadow_splits"]), DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)


## Scales a count of scenery pieces (trees outside the board, landmarks' detail).
static func scenery(n: int) -> int:
	return int(round(n * float(v["scenery"])))


static func grass(n: int) -> int:
	return int(round(n * float(v["grass"])))


static func particles(n: int) -> int:
	return maxi(1, int(round(n * float(v["particles"]))))


static func lights(n: int) -> int:
	return int(round(n * float(v["lights"])))
