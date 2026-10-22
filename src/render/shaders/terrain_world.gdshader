shader_type spatial;
// Terrain for every world style. Colors and the ground style come from the landscape data
// (WorldStyle), so one shader draws grass hills, desert, snow, alien moss and city paving.
// Vertex COLOR: r = surface kind / 16 (see TerrainRenderer.KIND_*), g = per-cell variation,
// b = backdrop dimming (land outside the board), a = on tops 0 near an edge that drops away
// (worn lip) and 1 inside. UV2.y = the column's top height (sides).
render_mode blend_mix, depth_draw_opaque, cull_back;

// Ground style: 0 grass, 1 sand, 2 snow, 3 moss (alien), 4 paving, 5 ash.
uniform int top_style = 0;
uniform vec3 top_a : source_color = vec3(0.2, 0.34, 0.11);
uniform vec3 top_b : source_color = vec3(0.3, 0.43, 0.15);
uniform vec3 top_dry : source_color = vec3(0.56, 0.54, 0.28);
uniform vec3 soil : source_color = vec3(0.36, 0.25, 0.15);
uniform vec3 rock_a : source_color = vec3(0.46, 0.44, 0.41);
uniform vec3 rock_b : source_color = vec3(0.30, 0.29, 0.28);
uniform vec3 rough_col : source_color = vec3(0.33, 0.27, 0.19);
uniform vec3 bed : source_color = vec3(0.22, 0.19, 0.14);
uniform vec3 hazard_col : source_color = vec3(1.0, 0.4, 0.08);
uniform vec3 vein_col : source_color = vec3(0.2, 0.95, 0.9);
uniform float vein_strength = 0.0;
uniform vec3 crystal_col : source_color = vec3(0.35, 0.75, 1.0);
uniform vec3 wall_col : source_color = vec3(0.5, 0.48, 0.45);
uniform float strata = 1.0;
uniform float soil_depth = 0.3;
uniform float wetness = 0.0;

varying vec3 wpos;
varying vec4 vcol;
varying float top_y;
varying float breakable;

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
float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) { v += a * noise(p); p = p * 2.03 + 1.7; a *= 0.5; }
	return v / 0.875;
}
// Cellular cracks: distance to the nearest edge between random cells.
float cracks(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 19.0));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

varying vec3 lnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
	top_y = UV2.y;
	breakable = UV2.x;
}

// Layered stone: warped horizontal strata with blocky fractures.
vec3 stone(vec2 p, float y, out float rough, out float relief) {
	float warp = fbm3(p * 0.7) * 1.6;
	float band = 0.5 + 0.5 * sin((y * strata + warp * 0.35) * 9.0);
	float band2 = 0.5 + 0.5 * sin((y * strata * 2.7 + warp) * 5.0);
	float n = fbm(p * 4.0 + y);
	vec3 c = mix(rock_b, rock_a, band * 0.55 + band2 * 0.15 + n * 0.3);
	c *= 0.82 + 0.3 * fbm3(vec2(p.x * 0.5, y * 3.0));
	// A few long weathered fractures and vertical rain streaks.
	float fr = smoothstep(0.035, 0.0, cracks(vec2(p.x * 0.9 + warp, y * 1.3))) * smoothstep(0.35, 0.6, fbm3(p * 1.3 + y));
	c *= 1.0 - 0.35 * fr;
	c *= 0.9 + 0.12 * noise(vec2(p.x * 9.0, y * 0.8));
	rough = 0.78 + 0.15 * n;
	relief = n * 0.7 + band * 0.25 - fr * 0.6;
	return c;
}

vec3 ground_top(vec2 p, float lip, out float rough, out vec3 emit, out float relief) {
	float n1 = fbm3(p * 0.3);
	float n2 = fbm(p * 1.9 + 5.0);
	float n3 = fbm3(p * 9.0);
	vec3 c;
	rough = 0.95;
	emit = vec3(0.0);
	relief = n3;
	if (top_style == 1) {
		// Sand: wind ripples along a warped direction, darker hollows.
		float r = sin(dot(p, vec2(0.8, 0.6)) * 14.0 + fbm3(p * 0.9) * 9.0);
		c = mix(top_a, top_b, smoothstep(0.25, 0.75, n1));
		c = mix(c, top_dry, smoothstep(0.6, 0.8, n2) * 0.6);
		c *= 0.9 + 0.08 * r + 0.15 * n3;
		relief = r * 0.25 + n3 * 0.4;
		rough = 0.9;
	} else if (top_style == 2) {
		// Snow: blue-white drifts, sparkle, wind-scoured patches of rock.
		c = mix(top_a, top_b, smoothstep(0.3, 0.7, n1));
		float bare = smoothstep(0.66, 0.74, n2);
		c = mix(c, rock_b * (0.8 + 0.4 * n3), bare * 0.8);
		float sp = step(0.985, hash(floor(p * 60.0)));
		emit = vec3(0.6, 0.7, 0.8) * sp * 0.4 * (1.0 - bare);
		rough = mix(0.55, 0.9, bare);
		relief = n3 * 0.4 + bare * 0.5;
	} else if (top_style == 3) {
		// Alien moss with glowing veins.
		c = mix(top_a, top_b, smoothstep(0.3, 0.7, n1));
		c = mix(c, top_dry, smoothstep(0.6, 0.78, n2) * 0.7);
		c *= 0.75 + 0.45 * n3;
		float v = smoothstep(0.03, 0.0, abs(fbm(p * 0.9 + 3.0) - 0.5)) * smoothstep(0.35, 0.6, n2);
		emit = vein_col * v * vein_strength * (0.8 + 0.2 * sin(TIME * 1.5 + p.x));
		c = mix(c, vein_col * 0.2, v * 0.5);
	} else if (top_style == 4) {
		// Paving: worn slabs and asphalt patches, dark seams, oil stains, puddles.
		vec2 g = p * 1.5;
		vec2 tile = abs(fract(g) - 0.5);
		float seam = smoothstep(0.46, 0.49, max(tile.x, tile.y));
		float slab = hash(floor(g));
		c = mix(top_a, top_b, slab * 0.6 + n1 * 0.4) * (0.8 + 0.35 * n3);
		float asphalt = smoothstep(0.55, 0.6, n1);
		c = mix(c, top_dry * (0.8 + 0.3 * n3), asphalt);
		c *= 1.0 - 0.45 * seam * (1.0 - asphalt);
		float cr = smoothstep(0.035, 0.0, cracks(p * 2.2)) * smoothstep(0.4, 0.7, n2);
		c *= 1.0 - 0.5 * cr;
		c *= 1.0 - 0.3 * smoothstep(0.7, 0.8, fbm3(p * 0.7 + 11.0));
		float wet = smoothstep(0.62, 0.66, fbm3(p * 0.5 + 23.0)) * wetness;
		c *= 1.0 - 0.3 * wet;
		rough = mix(0.85, 0.08, wet);
		relief = n3 * 0.3 - seam * 0.5 - cr;
	} else if (top_style == 5) {
		// Ash: grey-black dust with cinders.
		c = mix(top_a, top_b, smoothstep(0.3, 0.7, n1)) * (0.75 + 0.45 * n3);
		c = mix(c, top_dry, smoothstep(0.6, 0.8, n2) * 0.5);
		emit = hazard_col * step(0.993, hash(floor(p * 25.0))) * 0.8;
	} else {
		// Grass: two greens, dry patches, clover-dark spots, fine blade noise.
		c = mix(top_a, top_b, smoothstep(0.3, 0.7, n1));
		c = mix(c, top_dry, smoothstep(0.58, 0.76, n2) * 0.65);
		c *= 0.74 + 0.42 * n3;
		c = mix(c, top_a * 0.6, smoothstep(0.7, 0.85, fbm3(p * 4.0 + 7.0)) * 0.5);
		// Blade streaks.
		float blades = noise(vec2(p.x * 40.0, p.y * 40.0 + sin(p.x * 3.0)));
		c *= 0.92 + 0.16 * blades;
		relief = n3 * 0.6 + blades * 0.3;
	}
	// Worn lip where the ground drops away: soil shows through.
	float l = 1.0 - smoothstep(0.0, 0.32, lip + (n2 - 0.5) * 0.25);
	if (top_style != 4) {
		c = mix(c, soil * (0.8 + 0.4 * n3), l * (top_style == 2 ? 0.4 : 1.0));
	} else {
		c *= 1.0 - 0.25 * l;
	}
	return c;
}

void fragment() {
	// Texture by the true face direction; light by the (smoothed) vertex normal.
	vec3 fn = normalize(cross(dFdx(wpos), dFdy(wpos)));
	if (dot(fn, lnrm) < 0.0) { fn = -fn; }
	vec3 wnrm = fn;
	int kind = int(vcol.r * 16.0 + 0.5);
	bool top = wnrm.y > 0.5;
	float hcoord = abs(wnrm.x) > abs(wnrm.z) ? wpos.z : wpos.x;
	vec3 col;
	float rough = 0.9;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float relief = 0.0;
	float bump = 1.0;
	if (top) {
		vec2 p = wpos.xz;
		float n2 = fbm(p * 2.2 + 5.0);
		float n3 = fbm3(p * 9.0);
		if (kind == 0) {
			col = ground_top(p, vcol.a, rough, emit, relief);
		} else if (kind == 1) {
			// Rough ground: churned soil, stones and roots; reads as hard going.
			col = ground_top(p, vcol.a, rough, emit, relief);
			float mud = smoothstep(0.35, 0.65, fbm(p * 1.4 + 9.0));
			col = mix(col, rough_col * (0.75 + 0.5 * n3), 0.45 + 0.4 * mud);
			float stones = smoothstep(0.08, 0.0, cracks(p * 4.0)) ;
			col = mix(col, rock_a * (0.7 + 0.5 * n3), (1.0 - stones) * smoothstep(0.5, 0.7, fbm3(p * 3.0)) * 0.6);
			col *= 1.0 - 0.35 * stones;
			relief = n3 * 0.8 - stones * 0.8 + mud * 0.2;
			rough = mix(0.95, 0.55, mud * wetness);
			bump = 1.6;
		} else if (kind == 2) {
			float r;
			col = stone(p * 0.8, wpos.y * 0.3 + p.x * 0.1, r, relief);
			// Moss or dust settles on flat rock tops.
			col = mix(col, top_a * 0.85, smoothstep(0.55, 0.75, n2) * (top_style == 1 ? 0.25 : 0.55));
			rough = r;
			bump = 1.8;
		} else if (kind == 3) {
			// Hazard: dark crust split by glowing cracks.
			float cr = cracks(p * 1.6 + vec2(TIME * 0.01, 0.0));
			float glow = smoothstep(0.12, 0.0, cr) * (0.7 + 0.3 * sin(TIME * 2.0 + p.x * 3.0));
			float pool = smoothstep(0.55, 0.75, fbm(p * 1.3 + vec2(TIME * 0.05, 0.0)));
			col = mix(vec3(0.05, 0.045, 0.04), vec3(0.16, 0.1, 0.06), n2);
			emit = hazard_col * (glow * 3.0 + pool * 2.5);
			col = mix(col, hazard_col * 0.3, pool);
			relief = cr;
			rough = 0.9;
		} else if (kind == 4) {
			col = bed * (0.7 + 0.5 * n2);
			rough = 0.5;
		} else if (kind == 6) {
			// Crystal top: glossy facets with an inner glow.
			float f = cracks(p * 3.0);
			col = crystal_col * (0.25 + 0.3 * f);
			emit = crystal_col * (0.4 + 0.8 * smoothstep(0.3, 0.0, f));
			rough = 0.1;
			metal = 0.3;
			relief = f;
		} else if (kind == 7) {
			// Man-made block (wall, barrier): cast concrete or dressed stone.
			vec2 g = p * vec2(2.0, 2.0);
			float seam = smoothstep(0.45, 0.49, max(abs(fract(g.x) - 0.5), abs(fract(g.y) - 0.5)));
			col = wall_col * (0.8 + 0.3 * n3) * (1.0 - 0.3 * seam);
			col *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.3, vcol.a));
			relief = n3 * 0.5 - seam;
			rough = 0.95;
		} else if (kind == 9) {
			// Bridge deck: worn asphalt with patched seams.
			col = mix(vec3(0.09, 0.09, 0.095), vec3(0.14, 0.135, 0.13), n2) * (0.85 + 0.3 * n3);
			col = mix(col, wall_col * 0.7, 1.0 - smoothstep(0.0, 0.25, vcol.a));
			float cr = smoothstep(0.03, 0.0, cracks(p * 1.7));
			col *= 1.0 - 0.4 * cr;
			rough = 0.85;
			relief = n3 * 0.3 - cr;
		} else {
			// Chasm floor: nearly black, fogged.
			col = vec3(0.02, 0.018, 0.02);
		}
	} else if (wnrm.y < -0.5) {
		col = kind == 9 ? wall_col * 0.45 : rock_b * 0.35;
	} else {
		vec2 p = vec2(hcoord, wpos.y);
		float d = top_y - wpos.y;  // depth below the column's top
		float n = fbm(p * 3.0);
		float r;
		vec3 st = stone(vec2(hcoord, 0.0), wpos.y, r, relief);
		if (kind == 6) {
			// Crystal column: clear blue glass with bright fracture planes.
			float f = cracks(vec2(hcoord * 2.0, wpos.y * 0.8));
			col = crystal_col * (0.2 + 0.25 * f);
			emit = crystal_col * (0.25 + 1.2 * smoothstep(0.1, 0.0, f) + 0.4 * smoothstep(0.6, 0.0, d));
			rough = 0.08;
			metal = 0.4;
			relief = f;
		} else if (kind == 7) {
			float lv = fract(wpos.y * 2.0);
			vec2 bk = vec2(hcoord * 2.0 + floor(wpos.y * 2.0) * 0.5, wpos.y * 2.0);
			float seam = max(smoothstep(0.06, 0.0, lv), smoothstep(0.04, 0.0, abs(fract(bk.x) - 0.5) - 0.46));
			col = wall_col * (0.75 + 0.35 * n) * (1.0 - 0.35 * seam);
			col *= 0.7 + 0.3 * smoothstep(0.0, 0.5, wpos.y - (top_y - 2.0));
			relief = n * 0.4 - seam;
		} else if (kind == 9) {
			float d2 = top_y - wpos.y;
			float girder = smoothstep(0.02, 0.0, abs(d2 - 0.18)) + smoothstep(0.015, 0.0, abs(d2 - 0.75));
			float joint = smoothstep(0.02, 0.0, abs(fract(hcoord * 0.5) - 0.5) - 0.48);
			col = wall_col * (0.85 + 0.2 * n) * (1.0 - 0.35 * girder) * (1.0 - 0.3 * joint);
			col *= 1.0 - 0.3 * smoothstep(0.4, 0.8, noise(vec2(hcoord * 6.0, wpos.y * 0.7)));
			col *= 0.75 + 0.25 * smoothstep(0.0, 0.3, d2);
			relief = n * 0.3 - girder - joint;
		} else if (kind == 8) {
			col = st * 0.35 * smoothstep(-4.0, 0.0, wpos.y);
		} else {
			vec3 dirt = soil * (0.7 + 0.5 * n);
			// Roots and pebbles in the soil.
			float peb = smoothstep(0.6, 0.75, noise(p * 14.0));
			dirt = mix(dirt, rock_a * 0.8, peb * 0.5);
			float sd = soil_depth + 0.25 * fbm3(vec2(hcoord * 1.3, 2.0));
			float s = smoothstep(sd, sd + 0.12, d);
			if (kind == 2) {
				s = 1.0;
			}
			col = mix(dirt, st, s);
			rough = mix(0.95, r, s);
			relief = mix(n + peb * 0.5, relief, s);
			// Ground cover hangs over the edge.
			float fringe = step(d, 0.04 + 0.07 * noise(vec2(hcoord * 25.0, 1.0)));
			if ((kind == 0 || kind == 1) && top_style != 4) {
				col = mix(col, top_a * (0.75 + 0.4 * n), fringe);
			}
			if (top_style == 2 && kind != 2) {
				col = mix(col, top_b, fringe);
			}
			if (kind == 3) {
				emit = hazard_col * smoothstep(0.25, 0.0, d) * 0.8;
			}
			if (kind == 4) {
				col = bed * 0.7;
			}
		}
		// Ambient darkening toward the foot of tall walls.
		col *= 0.62 + 0.38 * smoothstep(-0.6, 1.6, wpos.y - (top_y - 3.0));
		bump = 1.4;
	}
	// Destructible terrain: a web of deep cracks and chipped, lighter edges.
	if (breakable > 0.5) {
		vec2 cp = top ? wpos.xz * 1.3 : vec2(hcoord * 1.3, wpos.y * 1.1);
		float web = smoothstep(0.05, 0.0, cracks(cp)) * smoothstep(0.3, 0.55, fbm3(cp * 0.8 + 2.0));
		float chip = smoothstep(0.12, 0.0, top_y - wpos.y) * smoothstep(0.55, 0.7, fbm3(cp * 3.0));
		col = mix(col, col * 0.25, web);
		col = mix(col, col * 1.35 + 0.05, chip);
		relief -= web * 0.6;
	}
	col *= 0.92 + 0.16 * vcol.g;
	col *= 1.0 - 0.6 * vcol.b;
	emit *= 1.0 - 0.6 * vcol.b;
	// Surface relief: bump from the material's own height pattern plus fine grain.
	float g0 = relief + fbm3((top ? wpos.xz : vec2(hcoord, wpos.y)) * 7.0) * 0.6;
	vec3 dpx = dFdx(wpos);
	vec3 dpy = dFdy(wpos);
	float dhx = dFdx(g0);
	float dhy = dFdy(g0);
	vec3 r1 = cross(dpy, wnrm);
	vec3 r2 = cross(wnrm, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	vec3 nb = normalize(abs(det) * normalize(lnrm) - grad * 0.045 * bump);
	NORMAL = normalize((VIEW_MATRIX * vec4(nb, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
