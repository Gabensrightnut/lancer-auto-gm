shader_type spatial;
// Building facades and roofs (CityBuilder). Walls follow the grid footprint exactly; the
// architecture is painted in: floors, window bays, storefronts, trim, damage and lights.
// COLOR.rgb = wall color (sRGB), COLOR.a = building seed. UV = (u along the face, world y).
// CUSTOM0 = (face width, building top y, building foot y, material type).
// Types: 0 concrete, 1 brick, 2 plaster, 3 metal panels, 4 stone blocks, 5 wood planks,
// 6 glass curtain wall, 7 timber frame (plaster with dark beams).
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform float floors = 3.0;
uniform float bay = 0.3;
uniform float window_w = 0.55;
uniform float window_h = 0.55;
uniform vec3 trim : source_color = vec3(0.35, 0.34, 0.32);
uniform vec3 glass : source_color = vec3(0.08, 0.1, 0.12);
uniform vec3 window_light : source_color = vec3(1.0, 0.72, 0.42);
uniform float lit = 0.05;
uniform float ruined = 0.0;
uniform float burning = 0.0;
uniform vec3 fire_color : source_color = vec3(1.0, 0.45, 0.1);
uniform float storefront = 1.0;
uniform vec3 shop_light : source_color = vec3(1.0, 0.85, 0.6);
uniform vec3 roof_color : source_color = vec3(0.3, 0.3, 0.3);
uniform float neon = 0.0;
uniform vec3 neon_a : source_color = vec3(1.0, 0.2, 0.7);
uniform vec3 neon_b : source_color = vec3(0.1, 0.9, 1.0);
uniform float wet = 0.0;
uniform float arched = 0.0;
// Roof surface: 0 tar and gravel, 1 clay tiles, 2 wood shingles, 3 white panels, 4 corrugated metal.
uniform int roof_style = 0;
// 1 on buildings outside the board (skyline): darker, greyer, dimmer lights.
uniform float backdrop = 0.0;
// Light rim along each wall's top edge (roof edges = elevation edges a unit stands at).
uniform vec3 rim_color : source_color = vec3(1.0, 0.96, 0.88);
uniform float rim_strength = 0.4;
uniform float rim_glow = 0.0;

varying vec4 vc;
varying vec4 cu;
varying vec3 wpos;
varying vec3 wnrm;

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
	for (int i = 0; i < 4; i++) { v += a * noise(p); p = p * 2.03 + 1.7; a *= 0.5; }
	return v / 0.9375;
}

void vertex() {
	vc = vec4(pow(COLOR.rgb, vec3(2.2)), COLOR.a);
	cu = CUSTOM0;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Wall material without openings. Returns color; height for bump in h.
vec3 wall(vec2 p, int type, vec3 base, out float h, out float rough, out float metal) {
	float n = fbm(p * 3.0);
	float n2 = fbm(p * 0.7 + 9.0);
	vec3 c = base * (0.82 + 0.3 * n);
	h = n * 0.3;
	rough = 0.9;
	metal = 0.0;
	if (type == 1) {
		// Brick: running bond with mortar.
		vec2 b = vec2(p.x * 16.0, p.y * 36.0);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		vec2 f = fract(b);
		float near = 1.0 - smoothstep(0.15, 0.4, fwidth(b.y));
		float mortar = max(smoothstep(0.9, 0.96, f.y), smoothstep(0.94, 0.98, f.x)) * near;
		c *= 1.0 + (0.3 * hash(floor(b)) - 0.15) * near;
		c = mix(c, vec3(0.55, 0.52, 0.48) * 0.8, mortar);
		h = 1.0 - mortar;
	} else if (type == 2 || type == 7) {
		// Plaster, stained and patched.
		c *= 0.9 + 0.15 * n2;
		c = mix(c, c * 0.75, smoothstep(0.6, 0.75, fbm(p * 1.5 + 3.0)) * 0.6);
		if (type == 7) {
			// Timber frame: posts, rails and braces in dark wood.
			float fx = abs(fract(p.x * 2.0) - 0.5);
			float fy = abs(fract(p.y * 2.0 * floors / 3.0) - 0.5);
			float brace = abs(fract(p.x * 2.0 + p.y * 2.0) - 0.5);
			float beam = max(step(0.44, fx), step(0.45, fy));
			beam = max(beam, step(0.46, brace) * step(fy, 0.42));
			c = mix(c, vec3(0.12, 0.08, 0.05), beam);
			h = 1.0 - beam * 0.5;
		}
	} else if (type == 3) {
		// Metal panels with seams, rivets and streaks.
		vec2 g = vec2(p.x * 3.0, p.y * floors * 0.5);
		vec2 f = abs(fract(g) - 0.5);
		float seam = smoothstep(0.47, 0.49, max(f.x, f.y));
		c *= 0.85 + 0.25 * hash(floor(g));
		c *= 1.0 - 0.4 * seam;
		rough = 0.45 + 0.3 * n;
		metal = 0.6;
		h = 1.0 - seam;
	} else if (type == 4) {
		// Dressed stone blocks.
		vec2 b = vec2(p.x * 4.0, p.y * 7.0);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		vec2 f = fract(b);
		float joint = max(smoothstep(0.9, 0.97, f.y), smoothstep(0.93, 0.98, f.x));
		c *= 0.8 + 0.35 * hash(floor(b)) + 0.15 * n;
		c = mix(c, c * 0.5, joint);
		h = 1.0 - joint + n * 0.3;
	} else if (type == 5) {
		// Horizontal wood siding.
		float plank = fract(p.y * 30.0);
		c *= 0.8 + 0.25 * hash(vec2(floor(p.y * 30.0), floor(p.x * 1.3)));
		c *= 1.0 - 0.35 * smoothstep(0.85, 1.0, plank);
		c *= 0.9 + 0.15 * noise(vec2(p.x * 40.0, p.y * 30.0));
		h = 1.0 - plank * 0.4;
	} else if (type == 6) {
		// Curtain wall: blue-grey glass between thin mullions.
		vec2 g = vec2(p.x * 6.0, p.y * floors * 1.0);
		vec2 f = abs(fract(g) - 0.5);
		float mull = smoothstep(0.44, 0.47, max(f.x, f.y));
		c = mix(glass * (1.2 + 0.4 * hash(floor(g))), trim, mull);
		rough = mix(0.05, 0.4, mull);
		metal = mix(0.7, 0.5, mull);
		h = 1.0 - mull;
	} else {
		// Cast concrete: form-tie holes and pour lines.
		float pour = smoothstep(0.96, 1.0, fract(p.y * floors * 1.0));
		c *= 1.0 - 0.12 * pour;
		c *= 0.92 + 0.12 * n2;
		h = n * 0.3 - pour * 0.3;
	}
	return c;
}

void fragment() {
	vec3 fn = normalize(cross(dFdx(wpos), dFdy(wpos)));
	if (dot(fn, wnrm) < 0.0) { fn = -fn; }
	int type = int(cu.w + 0.5);
	// Quantized: interpolation leaves tiny per-pixel differences that the hashes below would
	// turn into speckle.
	float seed = floor(vc.a * 256.0 + 0.5) / 256.0;
	vec3 col;
	float rough = 0.9;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	float h = 0.0;
	if (fn.y > 0.5) {
		// Roof: tar and gravel with seams, vents' stains, puddles.
		vec2 p = wpos.xz;
		float n = fbm(p * 4.0);
		vec2 g = abs(fract(p * 1.2) - 0.5);
		float seam = smoothstep(0.47, 0.49, max(g.x, g.y));
		col = roof_color * (0.75 + 0.4 * n) * (1.0 - 0.3 * seam);
		if (roof_style == 1 || roof_style == 2) {
			// Overlapping rows of tiles or shingles.
			float rows = roof_style == 1 ? 10.0 : 14.0;
			vec2 q = vec2(p.x * rows * 0.6, p.y * rows);
			q.x += step(1.0, mod(floor(q.y), 2.0)) * 0.5;
			vec2 f = fract(q);
			float edge_shade = smoothstep(0.0, 0.25, f.y);
			float gap = smoothstep(0.05, 0.0, abs(f.x - 0.5) - 0.45);
			col = roof_color * (0.7 + 0.35 * hash(floor(q))) * (0.6 + 0.4 * edge_shade) * (1.0 - 0.4 * gap);
			col *= 0.85 + 0.25 * n;
			h = f.y - gap;
			seam = 0.0;
		} else if (roof_style == 3) {
			vec2 g2 = abs(fract(p * 0.8) - 0.5);
			float s2 = smoothstep(0.48, 0.49, max(g2.x, g2.y));
			col = roof_color * (0.95 + 0.08 * n) * (1.0 - 0.25 * s2);
			h = -s2;
		} else if (roof_style == 4) {
			float rib = 0.5 + 0.5 * sin(p.x * 60.0);
			col = roof_color * (0.75 + 0.3 * rib) * (0.8 + 0.3 * n);
			col = mix(col, vec3(0.35, 0.18, 0.1), smoothstep(0.55, 0.75, fbm(p * 2.0 + seed)) * 0.6);
			h = rib;
		}
		col *= 1.0 - 0.3 * smoothstep(0.65, 0.8, fbm(p * 0.8 + seed * 9.0));
		float pud = smoothstep(0.66, 0.7, fbm(p * 0.6 + 4.0)) * max(wet, 0.3);
		col *= 1.0 - 0.35 * pud;
		rough = mix(0.92, 0.1, pud);
		h = n * 0.5 - seam;
		if (ruined > 0.0) {
			float scorch = smoothstep(0.55, 0.75, fbm(p * 0.9 + 7.0)) * ruined;
			col *= 1.0 - 0.7 * scorch;
		}
	} else if (fn.y < -0.5) {
		col = trim * 0.4;
	} else {
		float u = UV.x;
		float y = UV.y;
		float face_w = cu.x;
		float top = cu.y;
		float foot = cu.z;
		float floor_h = 1.0 / floors;
		vec2 p = vec2(u + seed * 13.0, y);
		col = wall(p, type, vc.rgb, h, rough, metal);
		// Per-building rhythm: bay width and window proportions vary a little.
		float bay_b = bay * (0.85 + 0.4 * fract(seed * 7.3));
		float ww_b = clamp(window_w * (0.8 + 0.45 * fract(seed * 3.1)), 0.25, 0.85);
		float wh_b = clamp(window_h * (0.85 + 0.35 * fract(seed * 5.7)), 0.3, 0.75);
		float bays = max(1.0, floor(face_w / bay_b + 0.5));
		float bw = face_w / bays;
		float bx = u / bw;
		float bi = floor(bx);
		float fx = fract(bx);
		float fl = (y - foot) / floor_h;
		float fi = floor(fl);
		float fy = fract(fl);
		float above_foot = step(0.0, y - foot);
		// Detail fades out where it would shimmer (far away or edge-on).
		float detail = 1.0 - smoothstep(0.18, 0.4, max(fwidth(fl), fwidth(bx)));
		// Base course and grime at the foot.
		col *= 0.75 + 0.25 * smoothstep(0.0, 0.25, y - foot);
		// Spandrels (horizontal bands) or pilasters (vertical bands) on some buildings.
		float style_r = fract(seed * 11.0);
		if (type != 6 && type != 7) {
			if (style_r < 0.35) {
				float band = smoothstep(0.08, 0.1, fy) * smoothstep(0.2, 0.18, fy);
				col = mix(col, trim * 0.9, band * 0.5 * detail);
			} else if (style_r < 0.6) {
				float pil = smoothstep(0.1, 0.07, abs(fx - 0.0)) + smoothstep(0.93, 0.96, fx);
				col = mix(col, col * 0.8 + trim * 0.15, pil * detail);
			}
		}
		// Cornice under the roof edge.
		float cornice = smoothstep(top - 0.07, top - 0.055, y) * step(y, top - 0.005);
		col = mix(col, trim, cornice);
		vec2 cell_id = vec2(bi + seed * 101.0 + floor(wpos.x * 3.0 + wpos.z * 7.0) * 0.0, fi + seed * 37.0) + vec2(floor(u * 0.0 + (wpos.x + wpos.z) * 0.37), 0.0);
		float r1 = hash(cell_id);
		bool ground_floor = fi < 1.0 && fi >= 0.0;
		bool glassy = type == 6;
		float win = 0.0;
		float recess = 0.0;
		float wy = 0.0;
		float y0 = 0.22;
		float top_w = 0.0;
		if (!glassy && y < top - 0.09 && above_foot > 0.5) {
			float ww = ww_b;
			float wh = wh_b;
			if (ground_floor && storefront > 0.5) {
				ww = 0.86;
				wh = 0.6;
				y0 = 0.1;
			}
			top_w = y0 + wh;
			float wx = smoothstep(0.5 - ww * 0.5 - 0.01, 0.5 - ww * 0.5, fx) * smoothstep(0.5 + ww * 0.5 + 0.01, 0.5 + ww * 0.5, fx);
			float arch = arched > 0.5 ? smoothstep(0.0, 0.02, (top_w - fy) - (1.0 - sqrt(max(0.0, 1.0 - pow((fx - 0.5) / (ww * 0.5), 2.0)))) * ww * 0.35) : 1.0;
			wy = smoothstep(y0 - 0.02, y0, fy) * smoothstep(top_w + 0.02, top_w, fy) * arch;
			win = wx * wy * detail;
			// Sill under the opening, lintel shadow inside its top.
			float sill = smoothstep(0.5 - ww * 0.5 - 0.05, 0.5 - ww * 0.5 - 0.02, fx) * smoothstep(0.5 + ww * 0.5 + 0.05, 0.5 + ww * 0.5 + 0.02, fx)
				* smoothstep(y0 - 0.07, y0 - 0.05, fy) * smoothstep(y0 - 0.01, y0 - 0.03, fy);
			col = mix(col, trim * 1.25, sill * detail * 0.8);
			h += sill * 0.4;
			recess = smoothstep(top_w - 0.14, top_w, fy) * win;
		}
		if (glassy) {
			vec2 pane = floor(vec2(u * 6.0, y * floors));
			float r2 = hash(pane + seed);
			float g_detail = 1.0 - smoothstep(0.15, 0.35, max(fwidth(u * 6.0), fwidth(y * floors)));
			emit += window_light * (step(1.0 - lit, r2) * (0.25 + 0.3 * hash(pane + 7.0)) * g_detail + lit * 0.18 * (1.0 - g_detail));
		}
		if (win > 0.0) {
			// Glass: tinted by the sky it reflects; curtains in some; ruins break them out.
			float fres = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 3.0);
			vec3 g = glass * (0.8 + 0.5 * hash(cell_id + 3.0));
			g = mix(g, vec3(0.32, 0.38, 0.46), 0.25 + 0.5 * fres);
			float curtain = step(0.82, hash(cell_id + 9.0)) * step(0.35, fx) ;
			g = mix(g, vec3(0.55, 0.48, 0.38) * 0.5, curtain * 0.7);
			float broken = step(1.0 - ruined * 0.6, r1);
			vec3 room = vec3(0.03, 0.025, 0.02) * (1.0 + 2.0 * fy);
			vec3 wc = mix(g, room, broken);
			wc *= 1.0 - 0.55 * recess;
			col = mix(col, wc, win);
			rough = mix(rough, mix(0.06, 1.0, broken), win);
			metal = mix(metal, 0.0, win);
			h = mix(h, -0.8, win);  // flat glass, no wall pattern showing through
			float is_lit = step(1.0 - lit, hash(cell_id + 11.0));
			vec3 lamp = (ground_floor && storefront > 0.5) ? shop_light : window_light;
			emit += lamp * win * is_lit * (1.0 - broken) * (0.6 + 0.6 * hash(cell_id + 17.0)) * (1.0 - 0.5 * fy);
			if (burning > 0.0) {
				float on_fire = step(1.0 - burning, hash(cell_id + 23.0)) * step(0.5, broken + burning);
				float flick = 0.7 + 0.3 * sin(TIME * 9.0 + r1 * 40.0) * sin(TIME * 5.3 + r1 * 13.0);
				emit += fire_color * win * on_fire * flick * 4.0 * (0.4 + 0.6 * (1.0 - fy));
			}
		}
		// Soot above broken or burning windows.
		if (ruined > 0.0 && !glassy) {
			float broken_here = step(1.0 - ruined * 0.6, r1) * step(0.5, wy + 0.0);
			float above = smoothstep(0.0, 0.2, fy - top_w) * smoothstep(1.0, 0.85, fy) * step(abs(fx - 0.5), 0.35);
			col *= 1.0 - 0.6 * step(1.0 - ruined * 0.6, r1) * above * detail;
		}
		// Far away the window grid fades to its average brightness.
		emit += window_light * lit * 0.35 * (1.0 - detail) * step(y, top - 0.09) * (glassy ? 0.0 : 1.0);
		// Rain streaks under windows and general grime.
		float streak = smoothstep(0.3, 0.7, noise(vec2(u * 30.0, y * 1.5))) * (1.0 - win);
		col *= 1.0 - 0.12 * streak;
		col *= 1.0 - 0.25 * smoothstep(0.55, 0.8, fbm(vec2(u * 0.8, y * 0.5) + seed * 5.0));
		// Ruin: scorch, shell holes, cracks.
		if (ruined > 0.0) {
			float scorch = smoothstep(0.5, 0.75, fbm(vec2(u * 0.6, y * 0.6) + seed * 7.0)) * ruined;
			col *= 1.0 - 0.75 * scorch;
			float hn = fbm(vec2(u * 0.9, y * 0.9) + seed * 3.0);
			float holes = smoothstep(0.8, 0.81, hn) * step(0.45, ruined) * step(y, top - 0.15);
			float rim = smoothstep(0.74, 0.8, hn) * (1.0 - holes) * step(0.45, ruined);
			col = mix(col, col * 0.55, rim);
			col = mix(col, vec3(0.02, 0.018, 0.016), holes);
			h -= holes;
			float crack = smoothstep(0.03, 0.0, abs(fbm(vec2(u * 2.0, y * 1.0) + 5.0) - 0.5)) * ruined;
			col *= 1.0 - 0.5 * crack;
		}
		// Neon: glowing strips and bands on signage-heavy styles.
		if (neon > 0.0) {
			float band = step(0.985, fract(fl * 0.5 + seed)) * step(hash(vec2(seed * 50.0, fi)), neon);
			vec3 nc = mix(neon_a, neon_b, step(0.5, hash(vec2(seed * 7.0, fi))));
			emit += nc * band * 1.6 * detail;
			float edge = smoothstep(0.03, 0.0, min(u, face_w - u)) * step(0.5, hash(vec2(seed * 3.0, 1.0))) * neon;
			emit += nc * edge * 1.2 * step(y, top - 0.02);
		}
		// Wet walls darken toward the bottom.
		col *= 1.0 - wet * 0.25 * (1.0 - smoothstep(0.0, 0.6, y - foot));
	}
	// Roof-edge rim on board buildings: wall tops and parapet caps.
	if (backdrop < 0.5) {
		float rim = 0.0;
		if (fn.y < 0.5 && fn.y > -0.5) {
			rim = smoothstep(0.03, 0.012, cu.y - UV.y) * step(UV.y, cu.y + 0.001);
		}
		col = mix(col, rim_color, rim * rim_strength);
		emit += rim_color * rim * rim_glow;
	} else {
		float lum = dot(col, vec3(0.3, 0.59, 0.11));
		col = mix(col, vec3(lum), 0.35) * 0.6;
		emit *= 0.55;
	}
	// Bump from the height pattern.
	vec3 dpx = dFdx(wpos);
	vec3 dpy = dFdy(wpos);
	float lx = max(length(dpx), 1e-5);
	float ly = max(length(dpy), 1e-5);
	float dhx = clamp(dFdx(h) / lx, -25.0, 25.0) * lx;
	float dhy = clamp(dFdy(h) / ly, -25.0, 25.0) * ly;
	vec3 r1v = cross(dpy, fn);
	vec3 r2v = cross(fn, dpx);
	float det = dot(dpx, r1v);
	vec3 grad = sign(det) * (dhx * r1v + dhy * r2v);
	vec3 nb = normalize(abs(det) * fn - grad * 0.012);
	NORMAL = normalize((VIEW_MATRIX * vec4(nb, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = emit;
}
