shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never;
// Second pass over the plain glass panes (corridor viewing glass and
// window sashes): a light film of grime plus a glancing-angle sheen. It is lit, so
// it stays black in the dark and catches the phone LED as a bright smear -
// which is exactly how a flashlight gives Jude away through lab glass.

#include "res://shaders/noise.gdshaderinc"

uniform vec3 grime_color : source_color = vec3(0.52, 0.56, 0.54);
uniform float grime : hint_range(0.0, 1.0) = 0.12;
uniform float sheen : hint_range(0.0, 1.0) = 0.35;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = vec2(world_pos.x + world_pos.z, world_pos.y);
	float blotch = fbm2(p * 1.3);
	float streak = fbm2(vec2(p.x * 9.0, p.y * 0.6));
	float dirt = smoothstep(0.42, 0.8, blotch * 0.6 + streak * 0.5) * grime;
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 4.0);
	ALBEDO = grime_color;
	ROUGHNESS = mix(0.04, 0.6, dirt);
	SPECULAR = 0.9;
	ALPHA = clamp(dirt * 0.38 + fresnel * sheen, 0.0, 0.8);
}
