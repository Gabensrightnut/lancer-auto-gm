shader_type spatial;
// Plants (Flora meshes): vertex color is sRGB; alpha 1 = bark/stone (plain), alpha 0.3-0.6 =
// foliage (soft light through leaves, leafy breakup), alpha 0 = glowing parts (alien plants).
// Everything sways in the wind by height; `gust` rolls waves across the field.
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform float sway = 0.04;
uniform float sway_height = 1.0;
uniform float glow = 2.5;
uniform float leafy = 1.0;
uniform vec2 wind_dir = vec2(1.0, 0.35);

varying vec4 tint;
varying vec3 wp;

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float k = clamp(VERTEX.y / sway_height, 0.0, 1.5);
	float phase = dot(world.xz, normalize(wind_dir)) * 0.35 - TIME * 1.4;
	float gust = 0.6 + 0.4 * sin(phase) + 0.25 * sin(phase * 2.3 + world.x);
	float w = gust * (0.7 + 0.3 * sin(TIME * 3.1 + world.x * 2.0 + world.z));
	vec2 d = normalize(wind_dir);
	VERTEX.x += d.x * w * sway * k * k;
	VERTEX.z += d.y * w * sway * k * k;
	tint = vec4(pow(COLOR.rgb, vec3(2.2)), COLOR.a);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = tint.rgb;
	float foliage = step(tint.a, 0.95) * step(0.05, tint.a);
	if (foliage > 0.5 && leafy > 0.0) {
		// Leaf clusters: bright edges and dark gaps.
		float n = noise(wp * 9.0) * 0.6 + noise(wp * 23.0) * 0.4;
		c *= mix(1.0, 0.55 + 0.75 * n, leafy);
		vec3 dn = vec3(noise(wp * 13.0 + 3.0) - 0.5, 0.0, noise(wp * 13.0 + 7.0) - 0.5);
		NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(dn, 0.0)).xyz * 0.8 * leafy);
	}
	ALBEDO = c;
	ROUGHNESS = foliage > 0.5 ? 0.85 : 0.95;
	SPECULAR = foliage > 0.5 ? 0.25 : 0.2;
	BACKLIGHT = c * 0.45 * foliage;
	if (tint.a < 0.05) {
		float pulse = 0.75 + 0.25 * sin(TIME * 2.0 + wp.x * 0.7 + wp.z);
		EMISSION = c * glow * pulse;
	}
}
