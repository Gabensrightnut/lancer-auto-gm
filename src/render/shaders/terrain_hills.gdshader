shader_type spatial;
// Grassy hills terrain. Vertex COLOR: r = surface kind (0 grass, 0.25 rough, 0.5 rock,
// 0.75 hazard, 1.0 riverbed), g = per-cell variation, b = backdrop dimming, a = on tops,
// 0 near an edge that drops away (dirt lip) and 1 inside. UV2.y on sides = the column's top.
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 grass_a : source_color = vec3(0.2, 0.34, 0.11);
uniform vec3 grass_b : source_color = vec3(0.3, 0.43, 0.15);
uniform vec3 grass_dry : source_color = vec3(0.56, 0.54, 0.28);
uniform vec3 dirt : source_color = vec3(0.36, 0.25, 0.15);
uniform vec3 rock_a : source_color = vec3(0.44, 0.42, 0.39);
uniform vec3 rock_b : source_color = vec3(0.30, 0.29, 0.28);
uniform vec3 mud : source_color = vec3(0.22, 0.19, 0.14);
uniform vec3 hazard_color : source_color = vec3(1.0, 0.4, 0.08);

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;
varying float top_y;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + 1.7; a *= 0.5; }
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
	top_y = UV2.y;
}

vec3 rock(vec2 p, float y, out float rough) {
	// Layered stone: warped horizontal strata with cracks.
	float warp = fbm(p * 0.8) * 1.6;
	float strata = 0.5 + 0.5 * sin((y + warp * 0.35) * 9.0);
	float n = fbm(p * 4.0);
	vec3 c = mix(rock_b, rock_a, strata * 0.7 + n * 0.3);
	c *= 0.8 + 0.35 * fbm(vec2(p.x * 0.5, y * 3.0));
	float crack = smoothstep(0.02, 0.0, abs(fbm(p * 2.5 + y) - 0.5));
	c *= 1.0 - 0.45 * crack;
	rough = 0.8 + 0.15 * n;
	return c;
}

void fragment() {
	float kind = vcol.r * 4.0;
	bool top = wnrm.y > 0.5;
	float hcoord = abs(wnrm.x) > abs(wnrm.z) ? wpos.z : wpos.x;
	vec3 col;
	float rough = 0.9;
	vec3 emit = vec3(0.0);
	vec2 nuv;
	if (top) {
		vec2 p = wpos.xz;
		nuv = p * 6.0;
		float n1 = fbm(p * 0.35);
		float n2 = fbm(p * 2.2 + 5.0);
		float n3 = fbm(p * 9.0);
		if (kind < 0.5 || (kind > 0.5 && kind < 1.5)) {
			// Grass: two greens and dry patches, fine blade noise, a dirt lip at drops.
			col = mix(grass_a, grass_b, smoothstep(0.3, 0.7, n1));
			col = mix(col, grass_dry, smoothstep(0.58, 0.75, n2) * 0.7);
			col *= 0.78 + 0.4 * n3;
			float lip = 1.0 - smoothstep(0.0, 0.35, vcol.a + (n2 - 0.5) * 0.25);
			col = mix(col, dirt * (0.8 + 0.4 * n3), lip);
			if (kind > 0.5) {
				// Rough ground: stony, patchy.
				float stones = smoothstep(0.55, 0.62, fbm(p * 5.0));
				col = mix(col, dirt * 1.1, 0.35);
				col = mix(col, rock_a * (0.8 + 0.4 * n3), stones);
			}
			rough = 0.95;
		} else if (kind < 2.5) {
			float r;
			col = rock(p, wpos.y * 0.3, r);
			col = mix(col, grass_a * 0.9, smoothstep(0.55, 0.7, n2) * 0.6);
			rough = r;
		} else if (kind < 3.5) {
			float glow = smoothstep(0.5, 0.75, fbm(p * 2.0 + vec2(TIME * 0.05, 0.0)));
			col = mix(vec3(0.06, 0.05, 0.04), vec3(0.2, 0.12, 0.06), n2);
			emit = hazard_color * glow * 4.0;
		} else {
			col = mud * (0.75 + 0.5 * n2);
			rough = 0.6;
		}
	} else if (wnrm.y < -0.5) {
		col = rock_b * 0.4;
		nuv = wpos.xz * 4.0;
	} else {
		vec2 p = vec2(hcoord, wpos.y);
		nuv = p * vec2(5.0, 7.0);
		float d = top_y - wpos.y;  // depth below the column's top
		float n = fbm(p * 3.0);
		float r;
		vec3 stone = rock(vec2(hcoord, 0.0) + vec2(0.0, 0.0), wpos.y, r);
		vec3 soil = dirt * (0.7 + 0.5 * n);
		// Soil near the top, stone below, deeper on tall columns.
		float soil_depth = 0.28 + 0.25 * fbm(vec2(hcoord * 1.3, 2.0));
		float s = smoothstep(soil_depth, soil_depth + 0.12, d);
		col = mix(soil, stone, kind > 1.5 && kind < 2.5 ? 1.0 : s);
		rough = mix(0.95, r, s);
		// Grass fringe hanging over the edge.
		float fringe = step(d, 0.05 + 0.06 * noise(vec2(hcoord * 25.0, 1.0)));
		if (kind < 1.5) {
			col = mix(col, grass_a * (0.8 + 0.4 * n), fringe);
		}
		// Ambient darkening toward the base.
		col *= 0.65 + 0.35 * smoothstep(-0.6, 1.5, wpos.y - (top_y - 3.0));
		if (kind > 3.5) {
			col = mud * 0.7;
		}
	}
	col *= 0.92 + 0.16 * vcol.g;
	col *= 1.0 - 0.6 * vcol.b;
	// Surface relief from noise (bumpy grass, rough stone).
	float h0 = fbm(nuv);
	float hx = fbm(nuv + vec2(0.07, 0.0));
	float hy = fbm(nuv + vec2(0.0, 0.07));
	NORMAL_MAP = normalize(vec3((h0 - hx) * 6.0, (h0 - hy) * 6.0, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	ALBEDO = col;
	ROUGHNESS = rough;
	EMISSION = emit;
}
