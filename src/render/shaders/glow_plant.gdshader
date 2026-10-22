shader_type spatial;
// Bioluminescent plants: vertex color (sRGB) tints; vertex alpha marks the glowing parts.
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform float glow = 2.5;
uniform float sway = 0.03;
varying vec4 tint;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX.x += sin(TIME * 1.3 + world.x + world.z * 0.7) * sway * VERTEX.y * 8.0;
	tint = vec4(pow(COLOR.rgb, vec3(2.2)), COLOR.a);
}

void fragment() {
	float pulse = 0.7 + 0.3 * sin(TIME * 2.0 + FRAGCOORD.x * 0.002);
	ALBEDO = tint.rgb * 0.3;
	EMISSION = tint.rgb * glow * (1.0 - tint.a) * pulse;
	ROUGHNESS = 0.5;
}
