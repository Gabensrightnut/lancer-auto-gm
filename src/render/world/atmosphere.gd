class_name WorldAtmosphere
extends RefCounted
## Sky, sun, fog and color grading for a world style (WorldStyle "sky" and "light" data).

const SKY_SHADER := preload("res://src/render/shaders/sky_world.gdshader")

## Sky shader parameters that are plain numbers, and the colors (data key -> uniform).
const SKY_NUMS := ["haze", "sun_glow", "clouds", "cloud_scale", "stars", "nebula", "planet", "planet_size",
	"planet_rings", "moon_a", "moon_a_size", "moon_b", "moon_b_size", "aurora"]
const SKY_COLORS := {"top": "top_color", "horizon": "horizon_color", "ground": "ground_color", "haze_color": "haze_color",
	"cloud_color": "cloud_color", "cloud_shade": "cloud_shade", "nebula_color": "nebula_color", "planet_color": "planet_color",
	"moon_a_color": "moon_a_color", "moon_b_color": "moon_b_color", "aurora_color": "aurora_color"}
const SKY_DIRS := ["planet_dir", "moon_a_dir", "moon_b_dir"]


static func apply(style: Dictionary, env: Environment, sun: DirectionalLight3D, fill: DirectionalLight3D = null) -> void:
	var sky: Dictionary = style.get("sky", {})
	var light: Dictionary = style.get("light", {})
	var m := ShaderMaterial.new()
	m.shader = SKY_SHADER
	for k: String in SKY_NUMS:
		if sky.has(k):
			m.set_shader_parameter(k, float(sky[k]))
	for k: String in SKY_COLORS:
		if sky.has(k):
			m.set_shader_parameter(SKY_COLORS[k], WorldStyle.color(sky[k]))
	for k: String in SKY_DIRS:
		if sky.has(k):
			var a: Array = sky[k]
			m.set_shader_parameter(k, Vector3(a[0], a[1], a[2]).normalized())
	if env.sky == null:
		env.sky = Sky.new()
	env.sky.sky_material = m
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(light.get("ambient", 0.5))
	env.ambient_light_sky_contribution = float(light.get("sky_ambient", 1.0))
	if light.has("ambient_color"):
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if float(light.get("sky_ambient", 1.0)) <= 0.0 else Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_color = WorldStyle.color(light["ambient_color"])
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = float(light.get("exposure", 1.05))
	env.tonemap_white = float(light.get("white", 6.0))
	env.fog_enabled = true
	env.fog_light_color = WorldStyle.color(light.get("fog_color", "#b3c7db"))
	env.fog_density = float(light.get("fog_density", 0.004))
	env.fog_aerial_perspective = float(light.get("fog_aerial", 0.5))
	env.fog_sky_affect = float(light.get("fog_sky", 0.0))
	env.fog_sun_scatter = float(light.get("sun_scatter", 0.2))
	env.fog_height = float(light.get("fog_height", 0.0))
	env.fog_height_density = float(light.get("fog_height_density", 0.0))
	var vol := float(light.get("volumetric", 0.0))
	env.volumetric_fog_enabled = vol > 0.0
	if vol > 0.0:
		env.volumetric_fog_density = vol
		env.volumetric_fog_albedo = WorldStyle.color(light.get("volumetric_albedo", "#d0d0d0"))
		env.volumetric_fog_emission = WorldStyle.color(light.get("volumetric_emission", "#000000"))
		env.volumetric_fog_emission_energy = float(light.get("volumetric_emission_energy", 1.0))
		env.volumetric_fog_anisotropy = float(light.get("volumetric_anisotropy", 0.6))
		env.volumetric_fog_length = float(light.get("volumetric_length", 80.0))
		env.volumetric_fog_sky_affect = 0.0
	env.ssr_enabled = bool(light.get("ssr", false))
	if env.ssr_enabled:
		env.ssr_max_steps = 48
		env.ssr_fade_in = 0.15
		env.ssr_fade_out = 2.0
	env.glow_enabled = true
	env.glow_intensity = float(light.get("glow", 0.7))
	env.glow_bloom = float(light.get("bloom", 0.04))
	env.glow_hdr_threshold = float(light.get("glow_threshold", 1.1))
	env.adjustment_enabled = true
	env.adjustment_saturation = float(light.get("saturation", 1.05))
	env.adjustment_contrast = float(light.get("contrast", 1.05))
	env.adjustment_brightness = float(light.get("brightness", 1.0))
	sun.light_color = WorldStyle.color(light.get("sun_color", "#fff0d0"))
	sun.light_energy = float(light.get("sun_energy", 2.2))
	sun.rotation_degrees = Vector3(float(light.get("sun_pitch", -40.0)), float(light.get("sun_yaw", -40.0)), 0)
	sun.light_volumetric_fog_energy = float(light.get("sun_fog_energy", 1.0))
	sun.light_angular_distance = float(light.get("sun_softness", 0.5))
	WorldQuality.apply_environment(env, sun)
	if fill:
		fill.light_color = WorldStyle.color(light.get("fill_color", "#8cb3ff"))
		fill.light_energy = float(light.get("fill_energy", 0.28))
