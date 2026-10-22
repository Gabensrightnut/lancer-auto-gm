shader_type spatial;
// Ink outline for mechs (inverted hull): back faces pushed out along the normal, drawn dark.
// Width is in screen space so lines stay even at any zoom.
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 ink : source_color = vec4(0.05, 0.045, 0.04, 1.0);
uniform float width = 1.6;  // pixels

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec2 offset = normalize((PROJECTION_MATRIX * vec4(n, 0.0)).xy);
	clip.xy += offset * width * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = ink.rgb;
}
