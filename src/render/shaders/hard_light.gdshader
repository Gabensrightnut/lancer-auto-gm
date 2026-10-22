shader_type spatial;
// Hard light wall: a lattice wireframe climbs up (build 0..0.5), then the panel fills in.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 color : source_color = vec3(0.3, 0.85, 1.0);
instance uniform float build = 1.0;

void fragment() {
	vec2 size = UV2;
	vec2 p = UV * size;
	vec2 g = abs(fract(p * vec2(5.0, 5.0)) - 0.5);
	vec2 g2 = abs(fract((p + vec2(p.y, 0.0)) * 5.0) - 0.5);
	float lattice = max(smoothstep(0.04, 0.0, 0.5 - max(g.x, g.y)), smoothstep(0.04, 0.0, 0.5 - g2.x));
	vec2 e = min(UV, 1.0 - UV) * size;
	float edge = smoothstep(0.04, 0.0, min(e.x, e.y));
	float wire_h = clamp(build * 2.0, 0.0, 1.0);
	float fill = clamp(build * 2.0 - 1.0, 0.0, 1.0);
	float shown = step(UV.y, wire_h);
	float front = smoothstep(0.06, 0.0, abs(UV.y - wire_h)) * (1.0 - fill);
	float scan = 0.5 + 0.5 * sin(p.y * 25.0 - TIME * 3.0);
	vec3 c = color * ((lattice * 0.9 + edge * 2.5) * shown + front * 3.0 + fill * (0.18 + 0.1 * scan));
	ALBEDO = c;
}
