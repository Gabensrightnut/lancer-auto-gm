shader_type spatial;
// Shallow river water: tinted, glossy, rippling, see-through near the bank.
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform vec3 shallow : source_color = vec3(0.16, 0.34, 0.36);
uniform vec3 deep : source_color = vec3(0.05, 0.16, 0.22);

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME * 0.35;
	float n0 = noise(p * 3.0 + vec2(t, t * 0.6)) + noise(p * 7.0 - vec2(t * 1.3, t));
	float nx = noise((p + vec2(0.05, 0.0)) * 3.0 + vec2(t, t * 0.6)) + noise((p + vec2(0.05, 0.0)) * 7.0 - vec2(t * 1.3, t));
	float ny = noise((p + vec2(0.0, 0.05)) * 3.0 + vec2(t, t * 0.6)) + noise((p + vec2(0.0, 0.05)) * 7.0 - vec2(t * 1.3, t));
	NORMAL_MAP = normalize(vec3((n0 - nx) * 3.0, (n0 - ny) * 3.0, 1.0)) * 0.5 + 0.5;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(shallow, deep, 0.4 + 0.3 * noise(p * 0.5));
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = mix(0.72, 0.95, fres);
}
