shader_type spatial;
render_mode blend_mix, depth_draw_never;
// Second pass over the box-built counters, cabinets and fridges. Without it
// they are featureless blocks; this draws what joinery would give them:
// a recessed toe-kick along the floor, door seams at a regular spacing, a
// shadow line under the worktop, and (optionally) a bar handle on each door.
// Generated from world position, so it needs no UVs.

uniform float door_width = 0.6;
uniform float handles : hint_range(0.0, 1.0) = 0.0;
uniform float floor_height = 3.8;
uniform vec3 seam_color : source_color = vec3(0.03, 0.03, 0.035);

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Indoor joinery only: the same material is used for planters outside.
	if (abs(world_normal.y) > 0.5 || abs(world_pos.x) > 12.0 || abs(world_pos.z) > 8.0) {
		discard;
	}
	float along = dot(world_pos.xz, vec2(abs(world_normal.z), abs(world_normal.x)));
	float h = mod(world_pos.y + 0.001, floor_height);
	float cell = mod(along, door_width);
	float to_seam = min(cell, door_width - cell);

	float toe_kick = 1.0 - smoothstep(0.085, 0.09, h);
	float seam = (1.0 - smoothstep(0.002, 0.004, to_seam)) * step(0.09, h);
	// Worktops sit at about 0.9 m; a thin dark gap just under that height.
	float lip = (1.0 - smoothstep(0.002, 0.004, abs(h - 0.86))) * 0.8;
	float handle = handles
		* (1.0 - smoothstep(0.008, 0.011, abs(cell - 0.07)))
		* step(0.6, h) * (1.0 - step(0.76, h));

	float alpha = max(max(toe_kick * 0.9, seam * 0.75), max(lip, handle));
	if (alpha < 0.01) {
		discard;
	}
	ALBEDO = mix(seam_color, vec3(0.55, 0.56, 0.58), handle);
	METALLIC = handle;
	ROUGHNESS = mix(0.8, 0.3, handle);
	ALPHA = alpha;
}
