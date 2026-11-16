shader_type spatial;
render_mode blend_mix, depth_draw_never;
// Second pass over a door leaf: years of hands round the lever, shoe scuffs
// along the bottom, and fine scratches. Coordinates are the leaf mesh's own,
// so every door wears in the same places.

#include "res://shaders/noise.gdshaderinc"

// Lever position and leaf height in the mesh's local space (metres).
uniform vec2 handle_local = vec2(0.35, -0.05);
uniform float leaf_bottom = -1.0;
uniform float seed = 0.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 p = local_pos.xy;
	vec2 s = vec2(seed, seed * 1.7);
	// Hand grime: an oval smear round the lever, heavier towards the edge.
	vec2 d = (p - handle_local) / vec2(0.2, 0.26);
	float hands = exp(-dot(d, d) * 1.6) * (0.55 + 0.45 * vnoise2(p * 9.0 + s));
	// Shoe and trolley scuffs near the floor.
	float low = 1.0 - smoothstep(0.0, 0.32, p.y - leaf_bottom);
	float scuff = smoothstep(0.62, 0.85, vnoise2(vec2(p.x * 6.0, p.y * 40.0) + s)) * low;
	// Fine scratches anywhere, mostly near the lever and the floor.
	float scratch = smoothstep(0.96, 0.995, vnoise2(vec2(p.x * 3.0 + p.y * 9.0, p.y * 140.0) + s)) * (hands + low);
	float grime = clamp(hands * 0.45 + scuff * 0.5, 0.0, 1.0);
	vec3 color = mix(vec3(0.08, 0.06, 0.045), vec3(0.62, 0.58, 0.52), clamp(scratch, 0.0, 1.0));
	ALBEDO = color;
	ALPHA = clamp(max(grime, scratch * 0.22), 0.0, 0.8);
	ROUGHNESS = mix(0.7, 0.45, hands);
	SPECULAR = 0.3;
}
