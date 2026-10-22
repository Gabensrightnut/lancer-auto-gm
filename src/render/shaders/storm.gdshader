shader_type spatial;
// Distant storm wall: dark churning clouds on a curved backdrop, with lightning flashes
// at irregular intervals. UV.x around the band, UV.y bottom (0) to top (1).
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 cloud : source_color = vec3(0.12, 0.08, 0.16);
uniform vec3 flash_color : source_color = vec3(0.75, 0.6, 1.0);

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
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.05; a *= 0.5; }
	return v;
}

void fragment() {
	vec2 p = vec2(UV.x * 14.0, UV.y * 3.0);
	float t = TIME * 0.03;
	float c = fbm(p + vec2(t, 0.0)) * 0.7 + fbm(p * 2.3 - vec2(t * 1.7, 0.0)) * 0.3;
	float shape = smoothstep(0.95, 0.35, UV.y + (c - 0.5) * 0.6);
	// Lightning: a few cells flash briefly at pseudo-random times.
	float cell = floor(UV.x * 7.0);
	float period = 3.0 + 5.0 * hash(vec2(cell, 1.0));
	float phase = fract(TIME / period + hash(vec2(cell, 2.0)));
	float flash = smoothstep(0.03, 0.0, phase) * (0.6 + 0.4 * sin(TIME * 60.0));
	float local = smoothstep(0.5, 0.0, abs(fract(UV.x * 7.0) - 0.5));
	vec3 col = cloud * (0.5 + 0.8 * c) + flash_color * flash * local * c * 1.5;
	// Bolt: a jagged bright line under the cloud during a flash.
	float bx = fract(UV.x * 7.0) - 0.5 + (noise(vec2(UV.y * 20.0, cell + floor(TIME / period))) - 0.5) * 0.15;
	float bolt = smoothstep(0.012, 0.0, abs(bx)) * step(UV.y, 0.55) * flash;
	ALBEDO = col + flash_color * bolt * 3.0;
	float ends = smoothstep(0.0, 0.2, UV.x) * smoothstep(1.0, 0.8, UV.x);
	ALPHA = clamp(shape * 0.95 + bolt, 0.0, 1.0) * ends;
}
