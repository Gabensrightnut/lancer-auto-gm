shader_type spatial;
// Flowing translucent cloth ribbons (e.g. a cloaking mantle). UV.y runs root (0) to tip (1);
// the tip waves more. `color` fades toward `tip_color`.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert;

uniform vec4 color : source_color = vec4(0.35, 0.75, 0.76, 0.85);
uniform vec4 tip_color : source_color = vec4(0.75, 0.95, 0.95, 0.35);
uniform float wave = 0.05;

void vertex() {
	float k = UV.y * UV.y;
	VERTEX.x += sin(TIME * 2.1 + UV.y * 7.0 + UV.x * 3.0) * wave * k;
	VERTEX.z += cos(TIME * 1.6 + UV.y * 5.0) * wave * 0.7 * k;
}

void fragment() {
	vec4 c = mix(color, tip_color, UV.y);
	float vein = smoothstep(0.03, 0.0, abs(fract(UV.x * 3.0 + UV.y * 0.6) - 0.5) - 0.46);
	ALBEDO = c.rgb * (1.0 - 0.25 * vein);
	ALPHA = c.a * (1.0 - smoothstep(0.9, 1.0, UV.y) * 0.6);
	BACKLIGHT = c.rgb * 0.6;
	ROUGHNESS = 0.6;
}
