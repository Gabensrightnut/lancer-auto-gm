shader_type spatial;
// Far scenery (mountain ranges, mesas, skylines far out): our own haze instead of scene fog,
// so distant layers read as soft silhouettes that get lighter with distance and toward their
// foot, like aerial perspective in a painting. Vertex color = base color (sRGB);
// UV.x = 0 for the nearest layer .. 1 for the farthest.
render_mode blend_mix, fog_disabled, cull_disabled;

uniform vec3 haze_color : source_color = vec3(0.8, 0.75, 0.7);
uniform float haze_near = 0.25;
uniform float haze_far = 0.7;
uniform float foot_haze = 0.35;
uniform float base_y = 0.0;
uniform float top_y = 60.0;

varying vec3 base;
varying float layer;
varying float wy;

void vertex() {
	base = pow(COLOR.rgb, vec3(2.2));
	layer = UV.x;
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	float h = clamp((wy - base_y) / max(top_y - base_y, 1.0), 0.0, 1.0);
	float haze = mix(haze_near, haze_far, layer) + foot_haze * (1.0 - h) * (1.0 - h);
	haze = clamp(haze, 0.0, 0.95);
	// Mix toward the haze: dim the lit color and add the haze as light of its own.
	ALBEDO = base * (1.0 - haze);
	EMISSION = haze_color * haze * 0.9;
}
