shader_type sky;
// Alien sky: violet-teal gradient, a giant ringed planet, a pale moon, stars and a nebula band.
// All procedural (no textures).

uniform vec3 top_color : source_color = vec3(0.04, 0.03, 0.12);
uniform vec3 horizon_color : source_color = vec3(0.42, 0.22, 0.38);
uniform vec3 ground_color : source_color = vec3(0.05, 0.04, 0.07);
uniform vec3 planet_dir = vec3(-0.55, 0.42, -0.72);
uniform float planet_size = 0.32;
uniform vec3 planet_color : source_color = vec3(0.55, 0.62, 0.78);
uniform vec3 moon_dir = vec3(0.6, 0.55, -0.55);

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
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.6, h));
	col = mix(col, ground_color, smoothstep(0.0, -0.15, h));
	// Nebula band and stars above the horizon.
	float neb = fbm(d * 3.0 + vec3(0.0, 0.0, TIME * 0.002));
	float band = exp(-pow((d.y - 0.35 + 0.25 * d.x) * 3.0, 2.0));
	col += vec3(0.35, 0.1, 0.45) * pow(neb, 2.5) * band * 1.4 + vec3(0.05, 0.25, 0.3) * pow(fbm(d * 6.0 + 9.0), 3.0) * band;
	float star = step(0.9985, hash(floor(d * 380.0))) * smoothstep(0.05, 0.3, h);
	col += vec3(star) * (0.6 + 0.4 * sin(TIME * 3.0 + hash(floor(d * 380.0)) * 40.0));
	// Giant planet with banded clouds, lit from one side, and its rings.
	vec3 pd = normalize(planet_dir);
	float ang = acos(clamp(dot(d, pd), -1.0, 1.0));
	vec3 right = normalize(cross(pd, vec3(0, 1, 0)));
	vec3 up = cross(right, pd);
	vec2 q = vec2(dot(d, right), dot(d, up)) / planet_size;
	float r = length(q);
	if (r < 1.0 && dot(d, pd) > 0.0) {
		float z = sqrt(1.0 - r * r);
		vec3 n = normalize(q.x * right + q.y * up + z * (-pd));
		float bands = 0.5 + 0.5 * sin(q.y * 18.0 + fbm(vec3(q * 3.0, 1.0)) * 4.0);
		vec3 pc = mix(planet_color, planet_color * vec3(1.2, 0.8, 0.9), bands);
		float lit = clamp(dot(n, normalize(vec3(0.7, 0.35, -0.6))) * 1.1 + 0.15, 0.04, 1.2);
		col = mix(col, pc * lit, smoothstep(1.0, 0.985, r));
	}
	// Rings: an ellipse tilted across the planet, hidden behind it on the far side.
	vec2 rq = vec2(q.x * 0.97 + q.y * 0.26, (q.y - q.x * 0.26) * 3.6);
	float rr = length(rq);
	float ring = smoothstep(1.35, 1.4, rr) * smoothstep(2.3, 2.2, rr) * (0.55 + 0.45 * sin(rr * 40.0));
	bool behind = r < 1.0 && rq.y > 0.0;
	if (!behind && dot(d, pd) > 0.0) {
		col = mix(col, vec3(0.85, 0.78, 0.7), ring * 0.75);
	}
	// Atmosphere glow around the planet.
	col += planet_color * 0.25 * smoothstep(1.4, 1.0, r) * step(1.0, r) * step(0.0, dot(d, pd));
	// Pale moon.
	float md = distance(d, normalize(moon_dir));
	col = mix(col, vec3(0.85, 0.88, 0.95) * (0.7 + 0.3 * fbm(d * 40.0)), smoothstep(0.045, 0.04, md));
	col += vec3(0.4, 0.5, 0.7) * 0.15 * smoothstep(0.15, 0.04, md);
	COLOR = col;
}
