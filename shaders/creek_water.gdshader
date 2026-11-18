shader_type spatial;
// The creek behind the school on a storm night: dark, muddy water flowing
// east, its surface pocked by rain. Opaque and cheap.

uniform vec3 deep_color : source_color = vec3(0.03, 0.04, 0.036);
uniform float flow_speed = 0.35;
uniform float ripple_strength = 0.6;

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

// Height of the surface: slow flow swell plus rain rings.
float surface(vec2 p, float t) {
	float h = vnoise(p * 0.9 + vec2(t * flow_speed, 0.0)) * 0.6
		+ vnoise(p * 2.3 - vec2(t * flow_speed * 1.6, t * 0.1)) * 0.3;
	// Rain: one drop per 0.6 m cell, each on its own clock, an expanding ring.
	vec2 cell = floor(p / 0.6);
	vec2 local = fract(p / 0.6) - 0.5;
	float r = hash(cell);
	float age = fract(t * 1.3 + r);
	vec2 c = vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5;
	float d = length(local - c * 0.6);
	float ring = sin((d - age * 0.5) * 40.0) * (1.0 - age) * smoothstep(0.5, 0.0, abs(d - age * 0.5) * 4.0);
	return h + ring * ripple_strength * 0.25;
}

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	float e = 0.03;
	float hx = surface(p + vec2(e, 0.0), t) - surface(p - vec2(e, 0.0), t);
	float hz = surface(p + vec2(0.0, e), t) - surface(p - vec2(0.0, e), t);
	vec3 n = normalize(vec3(-hx, 2.0 * e * 8.0, -hz));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = deep_color;
	ROUGHNESS = 0.06;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
