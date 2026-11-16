shader_type spatial;
render_mode blend_mix, depth_draw_never;
// Second pass over the building shell that rots it: thin rust drips from the
// ceiling line,
// hard-edged water stains with dried rims, scuffs at hip height; leak stains
// with tide rings on the ceilings; and on the floors grit, a film of dirt and
// mirror-smooth puddles that throw the flashlight back at you.
// Everything is generated from world position, so it needs no textures or UVs.

#include "res://shaders/noise.gdshaderinc"

uniform float decay : hint_range(0.0, 1.0) = 0.8;
uniform float wetness : hint_range(0.0, 1.0) = 0.65;
uniform vec3 mold_color : source_color = vec3(0.05, 0.065, 0.045);
uniform vec3 stain_color : source_color = vec3(0.2, 0.125, 0.065);
uniform float floor_height = 3.8;
// Per-mesh dressing, switched on by AtmosphereDirector.
uniform float baseboard : hint_range(0.0, 1.0) = 0.0;
uniform float ceiling_grid : hint_range(0.0, 1.0) = 0.0;
// Half-extents of the building in X and Z; walls beyond them face outdoors.
uniform vec2 footprint = vec2(11.98, 7.98);

varying vec3 world_pos;

// Two octaves: enough for shapes whose fine detail is broken up anyway.
float fbm_lite(vec2 p) {
	return vnoise2(p) * 0.65 + vnoise2(p * 2.03 + vec2(17.1, 9.2)) * 0.35;
}
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float alpha = 0.0;
	vec3 color = mold_color;
	float roughness = 0.9;
	float specular = 0.3;
	if (world_normal.y > 0.5) {
		// Floors: grime, and standing water.
		vec2 p = world_pos.xz;
		float dirt = smoothstep(0.42, 0.72, fbm_lite(p * 0.9));
		float puddle = smoothstep(0.6, 0.68, fbm2(p * 0.55 + vec2(31.0, 7.0))) * wetness;
		color = mix(stain_color * 0.5, mold_color, vnoise2(p * 3.0));
		color = mix(color, vec3(0.008, 0.01, 0.012), puddle);
		float grit = smoothstep(0.72, 0.9, vnoise2(p * 60.0)) * 0.35;
		// The plaza and the roof deck are rinsed by the rain: far less grime.
		float outdoor_floor = max(1.0 - step(abs(world_pos.x), footprint.x) * step(abs(world_pos.z), footprint.y),
			step(floor_height * 4.0 - 0.1, world_pos.y));
		dirt *= mix(1.0, 0.3, outdoor_floor);
		grit *= mix(1.0, 0.4, outdoor_floor);
		alpha = max(max(dirt * 0.6, grit) * decay, puddle * 0.72);
		roughness = mix(0.9, 0.03, puddle);
		specular = mix(0.3, 1.0, puddle);
	} else if (world_normal.y < -0.5) {
		// Ceilings: leaks from the floor above. Each stain has a pale wash,
		// several hard tide lines where it dried and spread again, and a
		// dark rotten heart.
		vec2 p = world_pos.xz;
		vec2 warp = vec2(vnoise2(p * 1.3 + vec2(2.0)), vnoise2(p * 1.3 + vec2(9.0))) - 0.5;
		float n = fbm2(p * 0.55 + warp * 0.9 + vec2(5.0));
		float inside = smoothstep(0.615, 0.63, n);
		float tides = smoothstep(0.9, 0.98, abs(fract(n * 7.0) - 0.5) * 2.0) * smoothstep(0.63, 0.66, n) * (1.0 - smoothstep(0.7, 0.74, n));
		float edge = smoothstep(0.61, 0.622, n) * (1.0 - smoothstep(0.624, 0.64, n));
		float heart = smoothstep(0.76, 0.86, n);
		float grain = vnoise2(p * 18.0);
		color = mix(stain_color * 1.25, stain_color * 0.55, max(edge, tides));
		color = mix(color, mold_color, heart);
		alpha = (inside * 0.13 + edge * 0.24 + tides * 0.08 + heart * 0.35) * (0.75 + 0.5 * grain) * decay;
		// Grime gathers along the edges of the ceiling-light frames and
		// round the room in a faint smoky band.
		vec2 tile = world_pos.xz / 0.6;
		vec2 in_tile = abs(fract(tile) - 0.5);
		float grid = smoothstep(0.478, 0.49, max(in_tile.x, in_tile.y)) * ceiling_grid;
		color = mix(color, vec3(0.34, 0.34, 0.33), grid);
		alpha = max(alpha, grid * 0.85);
		roughness = mix(0.95, 0.5, grid);
	} else {
		// Walls.
		float along = dot(world_pos.xz, vec2(abs(world_normal.z), abs(world_normal.x)));
		float h = mod(world_pos.y + 0.001, floor_height);
		vec2 wp = vec2(along, world_pos.y);
		float grain = vnoise2(wp * 16.0);
		// Inside the footprint and below the roof deck (the parapet and the
		// stair hut stand outdoors even though they are over the building).
		float indoors = step(abs(world_pos.x), footprint.x) * step(abs(world_pos.z), footprint.y)
			* (1.0 - step(floor_height * 4.0 - 0.1, world_pos.y));
		// (No rising-damp band along the foot of the walls: removed per user
		// preference - it read as a stain on every wall.)

		// Drips from the ceiling line: thin streaks, two widths, each
		// running its own length and wandering slightly as it goes.
		float h_top = floor_height - 0.25 - h;
		float drip = 0.0;
		for (int k = 0; k < 2; k++) {
			float freq = k == 0 ? 9.0 : 23.0;
			float wander = (vnoise2(vec2(along * 3.0, world_pos.y * 2.5 + float(k) * 7.0)) - 0.5) * 0.35 / freq;
			float column = (along + wander) * freq;
			float id = floor(column);
			float r = hash21(vec2(id, float(k) * 13.0 + 1.0));
			float len = 0.3 + 1.7 * hash21(vec2(id, float(k) * 5.0 + 3.0));
			float width = 0.08 + 0.12 * hash21(vec2(id, 9.0));
			float core = 1.0 - smoothstep(width * 0.5, width, abs(fract(column) - 0.5));
			float run = (1.0 - smoothstep(len * 0.6, len, h_top)) * step(0.0, h_top + 0.05);
			drip = max(drip, core * run * step(k == 0 ? 0.84 : 0.9, r) * (0.6 + 0.4 * r));
		}
		drip *= 0.7 + 0.3 * grain;

		// Old water stains: hard-edged shapes with a darker dried rim.
		vec2 warp = vec2(vnoise2(wp * 1.1 + vec2(3.0)), vnoise2(wp * 1.1 + vec2(8.0))) - 0.5;
		float b = fbm2(wp * 0.65 + warp * 0.8 + vec2(11.0));
		float stain = smoothstep(0.655, 0.665, b);
		float rim = smoothstep(0.648, 0.658, b) * (1.0 - smoothstep(0.66, 0.69, b));

		// Scuffs and scratches at hip height where bags and chairs rub.
		float hip = smoothstep(0.55, 0.7, h) * (1.0 - smoothstep(1.05, 1.25, h));
		float scuff = 0.0;
		if (hip > 0.0) {
			scuff = smoothstep(0.8, 0.9, vnoise2(vec2(along * 2.5, h * 70.0))) * hip * smoothstep(0.45, 0.65, vnoise2(wp * 2.0 + vec2(23.0)));
		}

		color = mix(mold_color * 1.6, stain_color * 0.8, 0.5);
		alpha = 0.0;
		color = mix(color, stain_color * 1.1, stain * (1.0 - rim));
		alpha = max(alpha, stain * 0.12);
		color = mix(color, stain_color * 0.75, rim);
		alpha = max(alpha, rim * 0.22);
		color = mix(color, stain_color * 0.5, drip);
		alpha = max(alpha, drip * 0.5);
		color = mix(color, vec3(0.06, 0.06, 0.065), scuff);
		alpha = max(alpha, scuff * 0.16);
		alpha *= (0.8 + 0.4 * grain) * decay;
		roughness = mix(0.95, 0.4, drip * wetness);
		// A dark skirting board along the foot of every wall inside the
		// building, scuffed and with a lighter top edge.
		float skirting = (1.0 - step(0.095, h)) * baseboard * indoors;
		float top_edge = smoothstep(0.08, 0.088, h);
		float skirting_scuff = skirting > 0.0 ? vnoise2(vec2(along * 5.0, h * 30.0)) : 0.0;
		vec3 skirting_color = vec3(0.075, 0.068, 0.062) * (0.7 + 0.6 * skirting_scuff) + vec3(0.07) * top_edge;
		color = mix(color, skirting_color, skirting);
		alpha = mix(alpha, 1.0, skirting);
		roughness = mix(roughness, 0.45, skirting);
	}
	ALBEDO = color;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	ALPHA = alpha;
}
