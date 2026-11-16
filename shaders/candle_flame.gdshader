shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Billboarded flame for the Blessed Lana Candle. flame_color is warm amber
// normally and pale blue when a real Aswang is near; agitation makes it
// gutter.

uniform vec4 flame_color : source_color = vec4(1.0, 0.72, 0.38, 1.0);
uniform float agitation = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float y = 1.0 - UV.y;
	float x = UV.x - 0.5;
	x -= (sin(TIME * 7.0 * agitation + y * 5.0) * 0.05 + sin(TIME * 13.0 * agitation) * 0.025) * y;
	float width = 0.24 * (1.0 - pow(y, 1.4)) * (0.9 + 0.1 * sin(TIME * 17.0 * agitation));
	float body = (1.0 - smoothstep(width * 0.3, width + 0.001, abs(x))) * smoothstep(0.0, 0.1, y);
	float core = (1.0 - smoothstep(0.0, width * 0.5 + 0.001, abs(x))) * (1.0 - smoothstep(0.1, 0.75, y));
	float base = 1.0 - smoothstep(0.0, 0.28, y);
	vec3 col = flame_color.rgb * body * 1.6 + vec3(1.0, 0.95, 0.82) * core + vec3(0.1, 0.22, 0.7) * body * base;
	ALBEDO = col;
	ALPHA = clamp(body, 0.0, 1.0);
}
