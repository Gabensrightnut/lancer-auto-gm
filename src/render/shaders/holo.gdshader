shader_type spatial;
// Holographic advert panel: glowing blocks of "text" and a logo shape that scroll and
// flicker, with scanlines. Our own procedural pattern, no images.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.25, 0.7);
uniform float seed = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	float t = TIME + seed * 7.0;
	// A round logo in the upper part that pulses.
	float logo = smoothstep(0.24, 0.22, distance(uv, vec2(0.5, 0.3)) ) * (0.6 + 0.4 * sin(t * 2.0));
	float ring = smoothstep(0.02, 0.0, abs(distance(uv, vec2(0.5, 0.3)) - 0.27));
	// Rows of glowing glyph blocks scrolling sideways.
	vec2 g = vec2(uv.x * 9.0 + floor(t * 1.5) * 0.0 - t * 0.6, uv.y * 14.0);
	float row = step(0.55, uv.y) * step(uv.y, 0.92);
	float glyph = step(0.45, hash(floor(g) + seed)) * step(0.15, fract(g.x)) * step(0.2, fract(g.y)) * row;
	float scan = 0.75 + 0.25 * sin(uv.y * 160.0 + t * 8.0);
	float flicker = 0.85 + 0.15 * step(0.92, hash(vec2(floor(t * 12.0), seed)));
	float edge = smoothstep(0.0, 0.03, uv.x) * smoothstep(1.0, 0.97, uv.x) * smoothstep(0.0, 0.03, uv.y) * smoothstep(1.0, 0.97, uv.y);
	float frame = (1.0 - smoothstep(0.0, 0.015, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y))));
	float a = (logo * 0.8 + ring + glyph * 0.9 + 0.08) * scan * flicker * edge + frame * 0.8;
	ALBEDO = tint * a * 2.2;
	ALPHA = 1.0;
}
