shader_type spatial;
// Painted armor for generated mechs and weapons. Per-instance values drive heat glow,
// hit flashes and the hacked glitch so every mech can share materials.
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 base_color : source_color = vec3(0.6);
uniform float metallic_value = 0.55;
uniform float roughness_value = 0.45;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float panel_strength = 1.0;
instance uniform float heat = 0.0;
instance uniform float glitch = 0.0;
instance uniform float flash = 0.0;
// Darkens the model: wrecks, and units out of line of sight.
instance uniform float dim = 0.0;

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
	if (glitch > 0.0) {
		float band = floor(VERTEX.y * 14.0 + TIME * 24.0);
		float r = fract(sin(band * 91.7) * 43758.5453);
		VERTEX.x += glitch * 0.09 * (r - 0.5) * step(0.55, r);
	}
}

void fragment() {
	vec3 an = abs(onrm);
	vec2 uv = an.y > max(an.x, an.z) ? opos.xz : (an.x > an.z ? opos.zy : opos.xy);
	vec2 g = abs(fract(uv * 6.0 + 0.5) - 0.5);
	float line = smoothstep(0.03, 0.0, min(g.x, g.y)) * panel_strength;
	float n = fract(sin(dot(floor(uv * 40.0), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 c = base_color * (1.0 - 0.4 * line) * (0.93 + 0.1 * n);
	ALBEDO = c * (1.0 - 0.75 * dim);
	METALLIC = metallic_value;
	ROUGHNESS = clamp(roughness_value + 0.2 * line + 0.08 * n, 0.0, 1.0);
	vec3 e = emission_color * 3.0;
	// Heat: the paint darkens and the panel seams and edges glow, orange toward yellow-white.
	float h = clamp(heat, 0.0, 1.0);
	vec3 hc = mix(vec3(1.0, 0.28, 0.03), vec3(1.0, 0.75, 0.35), h * h);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float pulse = 0.85 + 0.15 * sin(TIME * 6.0);
	ALBEDO *= 1.0 - 0.65 * h;
	e += hc * h * (0.25 + 1.4 * fres + 3.0 * smoothstep(0.03, 0.0, min(g.x, g.y))) * pulse;
	e += vec3(1.0, 0.95, 0.9) * flash * 1.1;
	if (glitch > 0.0) {
		float scan = step(0.5, fract(SCREEN_UV.y * 140.0 + TIME * 9.0));
		e += mix(vec3(0.1, 0.95, 1.0), vec3(1.0, 0.1, 0.6), step(0.5, fract(TIME * 7.0))) * glitch * scan * 0.9;
	}
	EMISSION = e;
}
