shader_type spatial;
// Ground around the school: grass on the flats, bare wet mud on slopes and
// along the creek banks, all of it soaked by the storm. World-space UVs, one
// texture set (grass_ground), the mud is derived from it so nothing tiles twice.
render_mode cull_disabled;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_textures = false;
uniform float tile_m = 2.5;
uniform vec3 grass_tint : source_color = vec3(0.66, 0.92, 0.55);
uniform vec3 mud_color : source_color = vec3(0.17, 0.125, 0.085);
uniform float creek_z = -25.6;
uniform float creek_half = 3.0;

varying vec3 world_pos;
varying vec3 world_nrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = world_pos.xz / tile_m;
	// Two scales of the same texture, rotated, break up the tiling.
	vec2 uv2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * world_pos.xz / (tile_m * 3.7);
	vec3 grass = vec3(0.16, 0.2, 0.11);
	vec3 nrm_map = vec3(0.5, 0.5, 1.0);
	float rough = 0.85;
	if (has_textures) {
		grass = mix(texture(grass_albedo, uv).rgb, texture(grass_albedo, uv2).rgb, 0.35);
		nrm_map = texture(grass_normal, uv).rgb;
		rough = texture(grass_rough, uv).g;
	}
	// Patchy colour over tens of metres: drier and greener areas.
	float patch = vnoise(world_pos.xz * 0.07) * 0.6 + vnoise(world_pos.xz * 0.23) * 0.4;
	grass *= grass_tint * mix(0.75, 1.15, patch);

	float slope = 1.0 - clamp(world_nrm.y, 0.0, 1.0);
	float bank = 1.0 - smoothstep(creek_half, creek_half + 4.5, abs(world_pos.z - creek_z));
	float low = smoothstep(-0.2, -0.9, world_pos.y);
	float mud = clamp(smoothstep(0.1, 0.32, slope) + bank * 0.85 + low, 0.0, 1.0);
	// Ragged edge where the grass gives out.
	mud = smoothstep(0.35, 0.65, mud + (vnoise(world_pos.xz * 1.3) - 0.5) * 0.5);
	float luma = dot(grass, vec3(0.3, 0.59, 0.11));
	vec3 mud_col = mud_color * (0.55 + 2.2 * luma);

	vec3 albedo = mix(grass, mud_col, mud);
	// Soaked: darker, and glossy where it is mud or flat enough to pool.
	float wet = 0.55 + 0.45 * mud;
	ALBEDO = albedo * mix(1.0, 0.72, wet);
	ROUGHNESS = mix(rough * 0.8, 0.22, mud * 0.85);
	SPECULAR = 0.5;
	NORMAL_MAP = mix(nrm_map, vec3(0.5, 0.5, 1.0), mud * 0.6);
}
