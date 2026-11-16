shader_type spatial;
// Skin of the Aswang. Everything is generated from object-space position, so
// it needs no textures and wraps any procedural body part:
//
//   * pigment: blotchy mottling, darker in the creases, bruise-blue veins
//   * relief:  folds, wrinkles and pores as a real bump (the surface normal
//              is bent, so the flashlight rakes across it), plus rib and
//              tendon ridges along the length of a part when `gaunt` is set
//   * wetness: slick patches that throw a hard highlight
//   * burn:    embers along the veins while burned by salt or sinamak
//   * dissolve: a noise burn-away with a glowing edge when it is destroyed

#include "res://shaders/noise.gdshaderinc"

uniform vec4 albedo : source_color = vec4(0.15, 0.14, 0.14, 1.0);
uniform float glow = 0.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float burn : hint_range(0.0, 1.0) = 0.0;
uniform float wet : hint_range(0.0, 1.0) = 0.35;
uniform float bump : hint_range(0.0, 3.0) = 1.0;
uniform float gaunt : hint_range(0.0, 1.0) = 0.0;
uniform float ridge_spacing = 0.05;
uniform float veins : hint_range(0.0, 1.0) = 0.5;
uniform float breathe = 0.004;
uniform vec3 rim_color : source_color = vec3(0.4, 0.05, 0.04);
uniform vec3 ember_color : source_color = vec3(1.0, 0.42, 0.08);

// Soft parts (hair, tails, tongues, entrails). `sway` is an offset in object
// space applied in full at `sway_length` metres along a strand and not at all
// at its root; the script drives it with a spring. `writhe` adds a slow curl
// of its own. `curl` bends wing bones upward towards the tip, to match the
// membrane they carry.
uniform vec3 sway = vec3(0.0);
uniform float sway_length = 1.0;
uniform float writhe = 0.0;
uniform float curl = 0.0;
uniform float curl_span = 1.0;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
	VERTEX += NORMAL * sin(TIME * 2.1 + VERTEX.y * 5.0) * breathe;
	float along = clamp(UV.y / sway_length, 0.0, 1.0);
	VERTEX += sway * along * along;
	VERTEX.x += sin(TIME * 3.1 + UV.y * 9.0) * writhe * along;
	VERTEX.z += cos(TIME * 2.3 + UV.y * 7.0) * writhe * along;
	float out_along = clamp(abs(obj_pos.x) / curl_span, 0.0, 1.0);
	VERTEX.y += curl * out_along * out_along * curl_span;
}

void fragment() {
	float n = fbm3(obj_pos * 9.0);
	float cut = dissolve * 1.08 - 0.04;
	if (n < cut) {
		discard;
	}
	float edge = (1.0 - smoothstep(cut, cut + 0.07, n)) * step(0.001, dissolve);

	// Relief, in arbitrary units of height.
	float folds = fbm3(obj_pos * 16.0 + vec3(4.0));
	float wrinkles = abs(vnoise3(obj_pos * vec3(70.0, 26.0, 70.0)) - 0.5) * 2.0;
	float pores = vnoise3(obj_pos * 170.0);
	float ridges = 0.5 + 0.5 * sin(UV.y * 6.2832 / ridge_spacing);
	// Ribs show on the flanks and fade out over the spine and the belly.
	float flank = smoothstep(0.3, 0.9, abs(cos(UV.x * 6.2832)));
	ridges = ridges * ridges * flank;
	float height = folds * 0.55 + wrinkles * 0.2 + pores * 0.1 + ridges * gaunt * 0.5;

	// Bend the normal by the screen-space slope of that height.
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 surface_gradient = sign(det) * (dFdx(height) * r1 + dFdy(height) * r2);
	NORMAL = normalize(abs(det) * NORMAL - bump * 0.006 * surface_gradient);

	// Pigment.
	float blotch = fbm3(obj_pos * 5.0 + vec3(7.0));
	float vein_line = abs(fbm3(obj_pos * 11.0 + vec3(3.1)) - 0.5);
	float vein_mask = (1.0 - smoothstep(0.0, 0.03, vein_line)) * veins;
	float cavity = smoothstep(0.15, 0.6, height);
	vec3 skin = albedo.rgb * mix(0.55, 1.2, blotch) * mix(0.6, 1.0, cavity);
	skin = mix(skin, skin * vec3(0.45, 0.4, 0.75), vein_mask * 0.7);
	ALBEDO = skin;

	float slick = wet * smoothstep(0.42, 0.68, fbm3(obj_pos * 6.0 + vec3(20.0)));
	ROUGHNESS = clamp(mix(0.8, 0.38, wet) - slick * 0.3 + (pores - 0.5) * 0.25, 0.06, 1.0);
	SPECULAR = 0.5;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float burn_veins = smoothstep(0.5, 0.56, fbm3(obj_pos * 15.0 + vec3(3.1)));
	EMISSION = albedo.rgb * glow
		+ rim_color * fresnel * 0.1
		+ ember_color * edge * 5.0
		+ ember_color * burn * burn_veins * (1.2 + 0.8 * sin(TIME * 11.0 + n * 20.0));
}
