shader_type spatial;
render_mode cull_disabled;
// Wing membrane of the Tiktik and the Manananggal: thin leather stretched
// between finger bones. Light from behind bleeds through it dull red, veins
// branch across it, and its trailing edge is torn and holed.
// UV.x runs across the fingers, UV.y from the wrist (0) to the trailing edge (1).
// Shares `dissolve` and `burn` with aswang_flesh so the whole creature burns
// away together.

#include "res://shaders/noise.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.13, 0.1, 0.1, 1.0);
uniform float glow = 0.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float burn : hint_range(0.0, 1.0) = 0.0;
uniform float tatter : hint_range(0.0, 1.0) = 0.6;
uniform vec3 bleed_color : source_color = vec3(0.45, 0.07, 0.05);
uniform vec3 ember_color : source_color = vec3(1.0, 0.42, 0.08);

// Bends the wing upward (or down) towards its tip, so the tip trails the
// shoulder through each beat instead of the wing swinging like a board.
uniform float curl = 0.0;
uniform float curl_span = 1.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
	float out_along = clamp(abs(VERTEX.x) / curl_span, 0.0, 1.0);
	VERTEX.y += curl * out_along * out_along * curl_span;
	// Air fills the skin between the fingers on the way down.
	VERTEX.z += curl * sin(UV.x * 25.13) * 0.06 * UV.y * curl_span;
	// The membrane shivers, more towards its loose edge.
	VERTEX += NORMAL * sin(TIME * 7.0 + VERTEX.x * 9.0 + VERTEX.y * 6.0) * 0.006 * UV.y;
}

void fragment() {
	float n = fbm3(obj_pos * 9.0);
	float cut = dissolve * 1.08 - 0.04;
	if (n < cut) {
		discard;
	}
	float edge = (1.0 - smoothstep(cut, cut + 0.07, n)) * step(0.001, dissolve);

	// Ragged trailing edge and a few holes.
	float rag = fbm2(UV * vec2(26.0, 5.0) + vec2(3.0));
	if (UV.y > 1.0 - tatter * 0.28 * rag) {
		discard;
	}
	if (fbm3(obj_pos * 6.0 + vec3(11.0)) > 1.0 - tatter * 0.38) {
		discard;
	}

	float vein_line = abs(fbm2(UV * vec2(7.0, 5.0) + vec2(1.7)) - 0.5);
	float vein_mask = 1.0 - smoothstep(0.0, 0.035, vein_line);
	float leather = fbm2(UV * vec2(60.0, 18.0));

	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	float height = leather * 0.5 + vein_mask * 0.5;
	vec3 surface_gradient = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
	NORMAL = normalize(abs(det) * NORMAL - 0.004 * surface_gradient);

	ALBEDO = albedo.rgb * (0.65 + 0.6 * n) * mix(1.0, 0.4, vein_mask);
	ROUGHNESS = 0.5 + leather * 0.25;
	SPECULAR = 0.4;
	BACKLIGHT = bleed_color * (1.0 - vein_mask * 0.7);
	EMISSION = albedo.rgb * glow
		+ ember_color * edge * 5.0
		+ ember_color * burn * vein_mask * (1.0 + 0.8 * sin(TIME * 11.0 + n * 20.0));
}
