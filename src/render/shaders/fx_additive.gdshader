shader_type spatial;
// Glowing effects (beams, tracers, flashes). Additive, unlit. Vertex color tints it.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 2.0;
uniform float soft_edges = 1.0;
instance uniform float alpha = 1.0;

void fragment() {
	float edge = mix(1.0, pow(abs(dot(NORMAL, VIEW)), 1.5), soft_edges);
	ALBEDO = tint.rgb * COLOR.rgb * energy * alpha * edge * tint.a * COLOR.a;
}
