shader_type spatial;
// Toxic sea: glowing green liquid with slow swirling scum and bubbles of light.
render_mode blend_mix, depth_draw_always, cull_back;

uniform vec3 deep : source_color = vec3(0.05, 0.18, 0.05);
uniform vec3 glow : source_color = vec3(0.45, 1.0, 0.25);

varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz;
	float t = TIME * 0.12;
	float swirl = noise(p * 1.2 + vec2(t, -t)) * 0.6 + noise(p * 3.5 - vec2(t * 2.0, t)) * 0.4;
	float bubbles = smoothstep(0.93, 0.98, noise(p * 9.0 + vec2(0.0, TIME * 0.3)));
	float n0 = noise(p * 4.0 + t);
	float nx = noise((p + vec2(0.05, 0.0)) * 4.0 + t);
	float ny = noise((p + vec2(0.0, 0.05)) * 4.0 + t);
	NORMAL_MAP = normalize(vec3((n0 - nx) * 2.0, (n0 - ny) * 2.0, 1.0)) * 0.5 + 0.5;
	ALBEDO = mix(deep, glow * 0.4, swirl * 0.5);
	EMISSION = glow * (0.25 + 0.6 * smoothstep(0.55, 0.8, swirl) + 2.0 * bubbles);
	ROUGHNESS = 0.15;
	ALPHA = 0.9;
}
