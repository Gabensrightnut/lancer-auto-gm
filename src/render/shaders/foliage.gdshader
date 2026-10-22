shader_type spatial;
// Grass tufts and tree foliage: vertex color, swaying in the wind by height.
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform float sway = 0.04;
uniform float sway_height = 0.1;

varying vec3 tint;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float k = clamp(VERTEX.y / sway_height, 0.0, 1.0);
	float w = sin(TIME * 1.7 + world.x * 0.7 + world.z * 0.5) + 0.4 * sin(TIME * 3.1 + world.x * 2.0);
	VERTEX.x += w * sway * k * k;
	VERTEX.z += w * sway * 0.5 * k * k;
	tint = pow(COLOR.rgb, vec3(2.2));  // vertex colors are sRGB
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
	BACKLIGHT = tint * 0.25;
}
