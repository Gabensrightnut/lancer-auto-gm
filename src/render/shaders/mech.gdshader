shader_type spatial;
// Painted armor for generated mechs and weapons. Per-instance values drive heat glow,
// hit flashes and the hacked glitch so every mech can share materials.
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 base_color : source_color = vec3(0.6);
uniform float metallic_value = 0.55;
uniform float roughness_value = 0.45;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float panel_strength = 1.0;
// Blender-made frames: vertex color R = edge wear, G = cavity grime (baked from curvature).
uniform float vertex_wear = 0.0;
instance uniform float heat = 0.0;
instance uniform float glitch = 0.0;
instance uniform float flash = 0.0;
// Darkens the model: wrecks, and units out of line of sight.
instance uniform float dim = 0.0;
// Dark maps: a soft cool rim and a little self-light so mechs still read (BattleView sets it).
instance uniform float lift = 0.0;

varying vec3 opos;
varying vec3 onrm;
varying vec4 vcol;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
	vcol = COLOR;
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
	float metal = metallic_value;
	float rough = clamp(roughness_value + 0.2 * line + 0.08 * n, 0.0, 1.0);
	if (vertex_wear > 0.0) {
		// Edge wear from per-pixel curvature (how fast the normal turns across the surface),
		// so bevels and rims chip to bare metal regardless of mesh density; vertex color G
		// (baked cavity) adds grime in creases; blotchy weathering over the panels.
		float curv = length(fwidth(NORMAL)) / max(length(fwidth(VERTEX)), 1e-5);
		vec3 q = opos * 40.0;
		float chip = fract(sin(dot(floor(q), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		float blot = fract(sin(dot(floor(opos * 9.0), vec3(39.3, 11.1, 71.7))) * 24634.6345);
		float wear = smoothstep(55.0, 140.0, curv) * vertex_wear * step(0.35, chip);
		float grime = clamp(vcol.g * 0.8 + (blot - 0.5) * 0.15, 0.0, 1.0);
		c *= 0.88 + 0.2 * blot;
		c = mix(c, vec3(0.5, 0.48, 0.45), wear * 0.85);
		metal = mix(metal, 0.8, wear);
		rough = mix(rough, 0.38, wear);
		c *= 1.0 - 0.5 * grime;
		rough = mix(rough, 0.9, grime);
	}
	ALBEDO = c * (1.0 - 0.75 * dim);
	METALLIC = metal;
	ROUGHNESS = rough;
	vec3 e = emission_color * 3.0;
	// Heat: the paint darkens and the panel seams and edges glow, orange toward yellow-white.
	float h = clamp(heat, 0.0, 1.0);
	vec3 hc = mix(vec3(1.0, 0.22, 0.02), vec3(1.0, 0.6, 0.18), h * h);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float pulse = 0.85 + 0.15 * sin(TIME * 6.0);
	// Glowing seams: panel lines on code-built parts, sharp edges on Blender-made ones.
	float seam = smoothstep(0.03, 0.0, min(g.x, g.y));
	if (vertex_wear > 0.0) {
		seam = smoothstep(60.0, 160.0, length(fwidth(NORMAL)) / max(length(fwidth(VERTEX)), 1e-5));
	}
	ALBEDO *= 1.0 - 0.7 * h;
	e += hc * h * (0.12 + 0.9 * fres + 2.2 * seam) * pulse;
	e += vec3(1.0, 0.95, 0.9) * flash * 1.1;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	e += lift * (1.0 - 0.75 * dim) * (ALBEDO * 0.3 + vec3(0.55, 0.68, 0.95) * rim * 0.8);
	if (glitch > 0.0) {
		float scan = step(0.5, fract(SCREEN_UV.y * 140.0 + TIME * 9.0));
		e += mix(vec3(0.1, 0.95, 1.0), vec3(1.0, 0.1, 0.6), step(0.5, fract(TIME * 7.0))) * glitch * scan * 0.9;
	}
	EMISSION = e;
}
