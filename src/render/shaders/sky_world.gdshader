shader_type sky;
// Sky for every world style: gradient with horizon haze, sun disk and glow from the scene's
// sun, drifting clouds lit by the sun, and optional stars, nebula, moons and a ringed planet.
// All procedural (no textures). Parameters come from the landscape/culture data.

uniform vec3 top_color : source_color = vec3(0.22, 0.42, 0.75);
uniform vec3 horizon_color : source_color = vec3(0.75, 0.8, 0.86);
uniform vec3 ground_color : source_color = vec3(0.2, 0.22, 0.2);
uniform vec3 haze_color : source_color = vec3(1.0, 0.8, 0.6);
uniform float haze = 0.4;
uniform float sun_glow = 1.0;
uniform float clouds = 0.5;
uniform vec3 cloud_color : source_color = vec3(1.0, 0.97, 0.93);
uniform vec3 cloud_shade : source_color = vec3(0.45, 0.5, 0.6);
uniform float cloud_scale = 1.0;
uniform float stars = 0.0;
uniform float nebula = 0.0;
uniform vec3 nebula_color : source_color = vec3(0.35, 0.1, 0.45);
uniform float planet = 0.0;
uniform vec3 planet_dir = vec3(-0.55, 0.42, -0.72);
uniform float planet_size = 0.32;
uniform vec3 planet_color : source_color = vec3(0.55, 0.62, 0.78);
uniform float planet_rings = 1.0;
uniform float moon_a = 0.0;
uniform vec3 moon_a_dir = vec3(0.6, 0.55, -0.55);
uniform float moon_a_size = 0.045;
uniform vec3 moon_a_color : source_color = vec3(0.85, 0.88, 0.95);
uniform float moon_b = 0.0;
uniform vec3 moon_b_dir = vec3(-0.2, 0.3, -0.9);
uniform float moon_b_size = 0.02;
uniform vec3 moon_b_color : source_color = vec3(0.9, 0.7, 0.6);
uniform float aurora = 0.0;
uniform vec3 aurora_color : source_color = vec3(0.2, 1.0, 0.6);

float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.07; a *= 0.5; }
	return v;
}

vec3 body(vec3 d, vec3 dir, float size, vec3 color, vec3 sun, inout float cover) {
	vec3 pd = normalize(dir);
	vec3 right = normalize(cross(pd, vec3(0, 1, 0)));
	vec3 up = cross(right, pd);
	vec2 q = vec2(dot(d, right), dot(d, up)) / size;
	float r = length(q);
	if (r >= 1.0 || dot(d, pd) <= 0.0) {
		return vec3(0.0);
	}
	float z = sqrt(1.0 - r * r);
	vec3 n = normalize(q.x * right + q.y * up - z * pd);
	float lit = clamp(dot(n, -sun) * 1.1 + 0.08, 0.03, 1.2);
	float craters = fbm(vec3(q * 4.0, size * 50.0));
	cover = smoothstep(1.0, 0.97, r);
	return color * lit * (0.75 + 0.35 * craters);
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 sun = LIGHT0_ENABLED ? LIGHT0_DIRECTION : normalize(vec3(0.5, 0.4, 0.5));
	vec3 sun_col = LIGHT0_ENABLED ? LIGHT0_COLOR : vec3(1.0);
	float sd = max(dot(d, sun), 0.0);
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.55, pow(max(h, 0.0), 0.8)));
	// Warm haze toward the sun along the horizon.
	col = mix(col, haze_color, haze * pow(sd, 3.0) * exp(-max(h, 0.0) * 5.0));
	col = mix(col, ground_color, smoothstep(0.0, -0.12, h));
	// Night sky details.
	if (stars > 0.0) {
		float s = step(0.9982, hash(floor(d * 420.0))) * smoothstep(0.03, 0.3, h);
		col += vec3(s) * stars * (0.6 + 0.4 * sin(TIME * 3.0 + hash(floor(d * 420.0)) * 40.0));
	}
	if (nebula > 0.0) {
		float neb = fbm(d * 3.0 + vec3(0.0, 0.0, TIME * 0.002));
		float band = exp(-pow((d.y - 0.35 + 0.25 * d.x) * 3.0, 2.0));
		col += nebula_color * pow(neb, 2.5) * band * 1.4 * nebula + vec3(0.05, 0.25, 0.3) * pow(fbm(d * 6.0 + 9.0), 3.0) * band * nebula;
	}
	if (aurora > 0.0) {
		float a = fbm(vec3(d.x * 3.0, TIME * 0.05, d.z * 3.0));
		float curtain = smoothstep(0.15, 0.3, h) * smoothstep(0.75, 0.35, h) * pow(0.5 + 0.5 * sin(d.x * 9.0 + a * 6.0 + TIME * 0.1), 4.0);
		col += aurora_color * curtain * aurora * a;
	}
	// Ringed planet.
	if (planet > 0.0) {
		vec3 pd = normalize(planet_dir);
		vec3 right = normalize(cross(pd, vec3(0, 1, 0)));
		vec3 up = cross(right, pd);
		vec2 q = vec2(dot(d, right), dot(d, up)) / planet_size;
		float r = length(q);
		bool front = dot(d, pd) > 0.0;
		if (r < 1.0 && front) {
			float z = sqrt(1.0 - r * r);
			vec3 n = normalize(q.x * right + q.y * up - z * pd);
			float bands = 0.5 + 0.5 * sin(q.y * 18.0 + fbm(vec3(q * 3.0, 1.0)) * 4.0);
			vec3 pc = mix(planet_color, planet_color * vec3(1.2, 0.8, 0.9), bands);
			float lit = clamp(dot(n, -sun) * 1.1 + 0.15, 0.04, 1.2);
			col = mix(col, pc * lit, smoothstep(1.0, 0.985, r) * planet);
		}
		vec2 rq = vec2(q.x * 0.97 + q.y * 0.26, (q.y - q.x * 0.26) * 3.6);
		float rr = length(rq);
		float ring = smoothstep(1.35, 1.4, rr) * smoothstep(2.3, 2.2, rr) * (0.55 + 0.45 * sin(rr * 40.0));
		bool behind = r < 1.0 && rq.y > 0.0;
		if (!behind && front) {
			col = mix(col, vec3(0.85, 0.78, 0.7), ring * 0.75 * planet * planet_rings);
		}
		col += planet_color * 0.25 * smoothstep(1.4, 1.0, r) * step(1.0, r) * step(0.0, dot(d, pd)) * planet;
	}
	float cover = 0.0;
	if (moon_a > 0.0) {
		vec3 m = body(d, moon_a_dir, moon_a_size, moon_a_color, sun, cover);
		col = mix(col, m, cover * moon_a);
		col += moon_a_color * 0.12 * moon_a * smoothstep(moon_a_size * 3.0, moon_a_size, distance(d, normalize(moon_a_dir)));
	}
	if (moon_b > 0.0) {
		cover = 0.0;
		vec3 m = body(d, moon_b_dir, moon_b_size, moon_b_color, sun, cover);
		col = mix(col, m, cover * moon_b);
	}
	// Sun disk and glow.
	if (LIGHT0_ENABLED) {
		float disk = smoothstep(0.9994, 0.9997, sd);
		col += sun_col * (disk * 40.0 + pow(sd, 200.0) * 2.0 * sun_glow + pow(sd, 12.0) * 0.25 * sun_glow) * smoothstep(-0.05, 0.02, h);
	}
	// Clouds on a curved layer above the board, lit from the sun's side.
	if (clouds > 0.0 && h > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 0.6 * cloud_scale;
		vec3 cp = vec3(uv + vec2(TIME * 0.004, TIME * 0.002), 0.0);
		float c = fbm(cp * 1.4);
		float cov = 1.0 - clouds;
		float dens = smoothstep(cov * 0.8 + 0.15, cov * 0.8 + 0.45, c);
		float thick = fbm(cp * 3.1 + 4.0);
		vec3 lit = mix(cloud_shade, cloud_color, clamp(0.35 + 0.65 * thick + 0.4 * pow(sd, 4.0), 0.0, 1.0));
		lit += sun_col * pow(sd, 8.0) * (1.0 - dens) * 1.5;
		float fade = smoothstep(0.0, 0.12, h);
		col = mix(col, lit, dens * fade * 0.92);
	}
	COLOR = col;
}
