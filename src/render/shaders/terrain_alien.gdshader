shader_type spatial;
// Alien wilds: dark violet moss tops threaded with glowing cyan veins, black basalt cliffs
// with glowing magenta mineral seams, crystal columns, and a toxic sea bed.
// COLOR: r = kind (0 moss, 0.25 rough/ash, 0.5 crystal, 0.75 hazard, 1.0 toxic bed),
// g = per-cell variation, b = backdrop dimming, a = top edge factor. UV2.y = column top.
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 moss_a : source_color = vec3(0.13, 0.09, 0.2);
uniform vec3 moss_b : source_color = vec3(0.2, 0.12, 0.26);
uniform vec3 ash : source_color = vec3(0.17, 0.16, 0.18);
uniform vec3 basalt : source_color = vec3(0.07, 0.065, 0.08);
uniform vec3 vein : source_color = vec3(0.2, 0.95, 0.9);
uniform vec3 seam : source_color = vec3(0.95, 0.25, 0.85);
uniform vec3 crystal : source_color = vec3(0.35, 0.75, 1.0);
uniform vec3 toxic : source_color = vec3(0.45, 1.0, 0.25);
uniform vec3 hazard_color : source_color = vec3(1.0, 0.4, 0.15);

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

void fragment() {
	float kind = vcol.r * 4.0;
	bool top = wnrm.y > 0.5;
	float hcoord = abs(wnrm.x) > abs(wnrm.z) ? wpos.z : wpos.x;
	vec3 col;
	vec3 emit = vec3(0.0);
	float rough = 0.85;
	float metal = 0.0;
	vec2 nuv;
	float pulse = 0.75 + 0.25 * sin(TIME * 1.3 + wpos.x * 0.4 + wpos.z * 0.3);
	if (top) {
		vec2 p = wpos.xz;
		nuv = p * 5.0;
		float n1 = fbm(p * 0.4);
		float n2 = fbm(p * 2.5 + 3.0);
		if (kind < 1.5) {
			col = mix(moss_a, moss_b, smoothstep(0.3, 0.7, n1)) * (0.75 + 0.5 * n2);
			// Branching glowing veins through the moss.
			float v = abs(fbm(p * 1.3 + 7.0) - 0.5);
			float veins = smoothstep(0.018, 0.0, v) * smoothstep(0.55, 0.7, n1);
			emit += vein * veins * 1.6 * pulse;
			col = mix(col, vein * 0.3, veins);
			float lip = 1.0 - smoothstep(0.0, 0.35, vcol.a + (n2 - 0.5) * 0.2);
			col = mix(col, basalt * 1.5, lip);
			if (kind > 0.5) {
				col = mix(col, ash * (0.7 + 0.6 * n2), 0.7);
				emit *= 0.3;
			}
		} else if (kind < 2.5) {
			// Crystal top: faceted, glassy, glowing from within.
			float facet = fract(p.x * 3.0 + p.y * 2.0 + n2);
			col = crystal * 0.12 * (0.7 + 0.6 * facet);
			emit += crystal * (0.15 + 1.2 * smoothstep(0.85, 1.0, facet)) * pulse;
			rough = 0.08;
			metal = 0.3;
		} else if (kind < 3.5) {
			float glow = smoothstep(0.5, 0.75, fbm(p * 2.0 + vec2(TIME * 0.05, 0.0)));
			col = vec3(0.06, 0.04, 0.04);
			emit = hazard_color * glow * 4.0;
		} else {
			col = vec3(0.05, 0.07, 0.03);
			rough = 0.4;
		}
	} else if (wnrm.y < -0.5) {
		col = basalt * 0.5;
		nuv = wpos.xz * 4.0;
	} else {
		vec2 p = vec2(hcoord, wpos.y);
		nuv = p * vec2(4.0, 8.0);
		float d = top_y - wpos.y;
		float n = fbm(p * 2.5);
		// Columnar basalt: vertical ridges, warped glowing seams.
		float ridges = 0.5 + 0.5 * sin(hcoord * 30.0 + n * 3.0);
		col = basalt * (0.7 + 0.5 * ridges) * (0.8 + 0.4 * n);
		rough = 0.55 + 0.3 * ridges;
		float s = abs(sin((wpos.y + fbm(vec2(hcoord * 0.7, 1.0)) * 0.8) * 4.0));
		float seams = smoothstep(0.06, 0.0, s) * step(0.25, d);
		emit += seam * seams * 1.4 * pulse;
		// Moss overhang at the top.
		float fringe = step(d, 0.04 + 0.05 * noise(vec2(hcoord * 22.0, 3.0)));
		if (kind < 1.5) {
			col = mix(col, moss_b, fringe);
		}
		if (kind > 1.5 && kind < 2.5) {
			// Crystal column sides: translucent blue with bright edges.
			float f = fract(hcoord * 4.0 + wpos.y * 0.6);
			col = crystal * 0.1 * (0.6 + 0.6 * f);
			emit = crystal * (0.12 + 1.6 * smoothstep(0.9, 1.0, f) + 0.6 * smoothstep(0.25, 0.0, d)) * pulse;
			rough = 0.06;
			metal = 0.35;
		}
		if (kind > 3.5) {
			col = basalt * 0.6;
			emit += toxic * 0.4 * smoothstep(0.6, 0.0, d);
		}
	}
	col *= 0.9 + 0.2 * vcol.g;
	col *= 1.0 - 0.6 * vcol.b;
	emit *= 1.0 - 0.4 * vcol.b;
	float h0 = fbm(nuv);
	float hx = fbm(nuv + vec2(0.07, 0.0));
	float hy = fbm(nuv + vec2(0.0, 0.07));
	NORMAL_MAP = normalize(vec3((h0 - hx) * 5.0, (h0 - hy) * 5.0, 1.0)) * 0.5 + 0.5;
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
