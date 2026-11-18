shader_type spatial;
render_mode blend_mix, depth_draw_never;
// Second pass over the building shell that ages it - an old provincial school
// that is still swept and painted, not a ruin. Low-contrast only: paint that
// has yellowed a little towards the floor, faint kick and chair scuffs at the
// foot and hip of the walls, floors dulled where the traffic runs (corridor
// centre, doorways), a dark skirting board, and now and then a faint old
// water ring on the ceiling.
// Everything is generated from world position, so it needs no textures or UVs.

#include "res://shaders/noise.gdshaderinc"

uniform float decay : hint_range(0.0, 1.0) = 0.8;
uniform vec3 age_color : source_color = vec3(0.55, 0.48, 0.34);
uniform vec3 scuff_color : source_color = vec3(0.12, 0.11, 0.1);
uniform float floor_height = 3.8;
// Per-mesh dressing, switched on by AtmosphereDirector.
uniform float baseboard : hint_range(0.0, 1.0) = 0.0;
uniform float ceiling_grid : hint_range(0.0, 1.0) = 0.0;
// Half-extents of the building in X and Z; walls beyond them face outdoors.
uniform vec2 footprint = vec2(11.98, 8.58);
// Half width of the central corridor (floors there wear down the middle).
uniform float corridor_half = 1.8;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float alpha = 0.0;
	vec3 color = age_color;
	float roughness = 0.9;
	float specular = 0.3;
	float indoors_xz = step(abs(world_pos.x), footprint.x) * step(abs(world_pos.z), footprint.y);
	if (world_normal.y > 0.5) {
		// Floors: polish worn dull along the middle of the corridor, plus a
		// very faint mottling. No dirt, no puddles.
		vec2 p = world_pos.xz;
		float lane = 1.0 - smoothstep(corridor_half * 0.25, corridor_half * 0.75, abs(world_pos.z));
		float mottle = vnoise2(p * 0.8);
		float indoor_floor = indoors_xz * (1.0 - step(floor_height * 4.0 - 0.1, world_pos.y));
		color = mix(age_color * 0.7, vec3(0.5), 0.4);
		alpha = (lane * 0.06 + smoothstep(0.55, 0.85, mottle) * 0.035) * indoor_floor * decay;
		roughness = 0.95;
		specular = 0.15;
	} else if (world_normal.y < -0.5) {
		// Ceilings: rarely, the faint ring of a leak that was fixed long ago.
		vec2 p = world_pos.xz;
		float n = fbm2(p * 0.5 + vec2(5.0));
		float ring = smoothstep(0.715, 0.725, n) * (1.0 - smoothstep(0.73, 0.75, n));
		float wash = smoothstep(0.72, 0.8, n);
		color = age_color;
		alpha = (ring * 0.07 + wash * 0.025) * decay;
		vec2 tile = world_pos.xz / 0.6;
		vec2 in_tile = abs(fract(tile) - 0.5);
		float grid = smoothstep(0.478, 0.49, max(in_tile.x, in_tile.y)) * ceiling_grid;
		color = mix(color, vec3(0.34, 0.34, 0.33), grid);
		alpha = max(alpha, grid * 0.85);
		roughness = mix(0.95, 0.5, grid);
	} else {
		// Walls: clean painted plaster with a little age.
		float along = dot(world_pos.xz, vec2(abs(world_normal.z), abs(world_normal.x)));
		float h = mod(world_pos.y + 0.001, floor_height);
		vec2 wp = vec2(along, world_pos.y);
		// Inside the footprint and below the roof deck (the parapet and the
		// stair hut stand outdoors even though they are over the building).
		float indoors = indoors_xz * (1.0 - step(floor_height * 4.0 - 0.1, world_pos.y));
		// Paint yellowed a touch towards the floor, unevenly.
		float yellow = (1.0 - smoothstep(0.1, 1.4, h)) * (0.6 + 0.4 * vnoise2(wp * 0.7));
		// Faint kick marks just above the skirting and chair rubs at hip height.
		float kick = (1.0 - smoothstep(0.1, 0.35, h)) * step(0.095, h)
			* smoothstep(0.82, 0.92, vnoise2(vec2(along * 4.0, h * 40.0)));
		float hip = smoothstep(0.6, 0.72, h) * (1.0 - smoothstep(0.95, 1.1, h));
		float rub = hip > 0.0 ? smoothstep(0.86, 0.94, vnoise2(vec2(along * 2.5, h * 60.0))) * hip : 0.0;
		float scuff = max(kick, rub * 0.7) * indoors;
		color = mix(age_color, scuff_color, scuff);
		alpha = max(yellow * 0.05 * indoors, scuff * 0.1) * decay;
		roughness = 0.95;
		// A dark skirting board along the foot of every wall inside the
		// building, with a lighter top edge.
		float skirting = (1.0 - step(0.095, h)) * baseboard * indoors;
		float top_edge = smoothstep(0.08, 0.088, h);
		float skirting_wear = skirting > 0.0 ? vnoise2(vec2(along * 5.0, h * 30.0)) : 0.0;
		vec3 skirting_color = vec3(0.075, 0.068, 0.062) * (0.85 + 0.3 * skirting_wear) + vec3(0.07) * top_edge;
		color = mix(color, skirting_color, skirting);
		alpha = mix(alpha, 1.0, skirting);
		roughness = mix(roughness, 0.45, skirting);
	}
	ALBEDO = color;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	ALPHA = alpha;
}
