shader_type spatial;
// Soft billboarded smoke puff. `seed` varies the noise per puff.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec4 color : source_color = vec4(0.58, 0.58, 0.6, 0.8);
instance uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float n = noise(UV * 4.0 + vec2(seed, TIME * 0.08)) * 0.6 + noise(UV * 9.0 - vec2(TIME * 0.05, seed)) * 0.4;
	float a = smoothstep(1.0, 0.15, length(uv) + (n - 0.5) * 0.7);
	// Fake light from above: brighter tops.
	ALBEDO = color.rgb * (0.7 + 0.35 * n + 0.15 * (1.0 - UV.y));
	ALPHA = a * color.a;
}
