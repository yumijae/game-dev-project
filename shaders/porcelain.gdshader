shader_type spatial;
// Glazed porcelain basin, years without a proper scrub: grime settles towards
// the drain, a tide line where standing water used to sit, and a rust streak
// running down from under the tap. UV.x = angle round the bowl (0..1, the tap
// is at `streak_u`), UV.y = 0 at the rim .. 1 at the drain.

uniform vec3 base_color : source_color = vec3(0.9, 0.9, 0.875);
uniform vec3 grime_color : source_color = vec3(0.44, 0.38, 0.28);
uniform vec3 rust_color : source_color = vec3(0.34, 0.15, 0.05);
uniform float streak_u = 0.75;
uniform float seed = 0.0;
uniform float wear = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	// Wrap the angular coordinate so the seam never shows in the noise.
	vec2 ring = vec2(cos(u * 6.2831853), sin(u * 6.2831853));
	float n = noise(ring * 9.0 + vec2(v * 10.0, seed)) * 0.6 + noise(ring * 31.0 + vec2(v * 33.0, seed * 1.7)) * 0.4;
	float grime = smoothstep(0.5, 1.0, v) * 0.6 * (0.55 + 0.45 * n);
	grime += smoothstep(0.035, 0.0, abs(v - 0.58)) * 0.3 * n;
	float du = abs(fract(u - streak_u + 0.5) - 0.5);
	float streak = exp(-du * du * 1400.0) * smoothstep(0.2, 0.95, v) * (0.45 + 0.55 * n);
	grime = clamp(grime * wear, 0.0, 1.0);
	streak = clamp(streak * wear, 0.0, 1.0);
	vec3 col = mix(base_color, grime_color, grime);
	col = mix(col, rust_color, streak * 0.85);
	float dirt = clamp(grime + streak, 0.0, 1.0);
	ALBEDO = col;
	ROUGHNESS = mix(0.06, 0.6, dirt);
	SPECULAR = 0.55;
	CLEARCOAT = 1.0 - dirt;
	CLEARCOAT_ROUGHNESS = 0.06;
}
