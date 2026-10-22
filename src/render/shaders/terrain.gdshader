shader_type spatial;
// Terrain blocks for the urban ruins kit. Vertex COLOR.r picks the surface kind
// (0 street, 0.25 concrete/rubble, 0.5 building, 0.75 hazard), COLOR.g is per-cell variation.
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 street_color : source_color = vec3(0.11, 0.115, 0.125);
uniform vec3 concrete_color : source_color = vec3(0.36, 0.35, 0.33);
uniform vec3 building_color : source_color = vec3(0.52, 0.48, 0.42);
uniform vec3 roof_color : source_color = vec3(0.26, 0.255, 0.25);
uniform vec3 hazard_color : source_color = vec3(1.0, 0.38, 0.06);
uniform vec3 window_light : source_color = vec3(1.0, 0.72, 0.42);
uniform float dim = 1.0;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
}

void fragment() {
	float kind = vcol.r * 4.0;
	bool top = wnrm.y > 0.5;
	bool bottom = wnrm.y < -0.5;
	float hcoord = abs(wnrm.x) > abs(wnrm.z) ? wpos.z : wpos.x;
	vec2 tuv = (top || bottom) ? wpos.xz : vec2(hcoord, wpos.y);
	float n = fbm(tuv * 3.0);
	float n2 = fbm(tuv * 0.6 + 17.0);
	vec3 col;
	float rough = 0.88;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	if (top) {
		if (kind < 0.5) {
			col = street_color * (0.75 + 0.5 * n) * (0.85 + 0.3 * n2);
			float cr = smoothstep(0.018, 0.0, abs(fbm(tuv * 1.3 + 3.0) - 0.5));
			col *= 1.0 - 0.55 * cr;
			// Wet patches: darker and glossier.
			float wet = smoothstep(0.6, 0.66, n2) * (1.0 - vcol.b);
			col *= 1.0 - 0.25 * wet;
			rough = mix(0.92, 0.35, wet);
		} else if (kind < 1.5) {
			col = concrete_color * (0.72 + 0.5 * n);
			vec2 tile = abs(fract(tuv * 2.0) - 0.5);
			float seam = smoothstep(0.47, 0.49, max(tile.x, tile.y));
			col *= 1.0 - 0.3 * seam;
		} else if (kind < 2.5) {
			col = roof_color * (0.72 + 0.5 * n) * (0.85 + 0.3 * n2);
			vec2 tile = abs(fract(tuv * 1.5) - 0.5);
			float seam = smoothstep(0.475, 0.49, max(tile.x, tile.y));
			col *= 1.0 - 0.35 * seam;
		} else {
			float glow = smoothstep(0.48, 0.72, fbm(tuv * 2.2 + vec2(TIME * 0.04, 0.0)));
			col = mix(vec3(0.07, 0.06, 0.055), vec3(0.18, 0.1, 0.06), n);
			emit = hazard_color * glow * 4.0;
			rough = 0.95;
		}
	} else if (bottom) {
		col = concrete_color * 0.35;
	} else {
		float lv = fract(wpos.y + 0.0001);
		float band = smoothstep(0.03, 0.0, lv) + smoothstep(0.97, 1.0, lv);
		bool building = kind > 1.5 && kind < 2.5;
		// Each block of the city gets its own facade color.
		float region = hash(floor(wpos.xz / 3.5) + 3.0);
		vec3 facade = region < 0.33 ? building_color : (region < 0.66 ? vec3(0.42, 0.40, 0.38) : vec3(0.45, 0.30, 0.24));
		col = (building ? facade : concrete_color * 0.88) * (0.68 + 0.5 * n) * (0.85 + 0.3 * n2);
		if (building) {
			vec2 w = vec2(hcoord * 1.5, wpos.y * 2.0);
			vec2 f = fract(w);
			float win = step(0.3, f.x) * step(f.x, 0.7) * step(0.3, f.y) * step(f.y, 0.78);
			float cellh = hash(floor(w) + floor(vcol.g * 50.0));
			float broken = step(0.55, cellh);
			vec3 glass = mix(vec3(0.025, 0.03, 0.035), vec3(0.008), broken);
			col = mix(col, glass, win);
			rough = mix(rough, 0.12 + broken * 0.85, win);
			metal = mix(0.0, 0.4 * (1.0 - broken), win);
			emit += window_light * win * step(0.97, cellh) * 0.7;
		}
		col *= 1.0 - 0.5 * band;
		// Grime gathers at the foot of each wall.
		col *= 0.78 + 0.22 * smoothstep(0.0, 0.8, lv);
		if (kind > 2.5) {
			emit += hazard_color * smoothstep(0.35, 0.0, lv) * 0.6;
		}
	}
	col *= 0.9 + 0.2 * vcol.g;
	// Blue channel darkens distant backdrop pieces so the board stands out.
	col *= 1.0 - 0.7 * vcol.b;
	emit *= 1.0 - 0.5 * vcol.b;
	ALBEDO = col * dim;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
