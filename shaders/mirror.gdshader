shader_type spatial;
// Restroom mirror. The reflection is rendered by MirrorSurface's camera into
// `reflection`; this adds what years in a school washroom do to cheap
// mirror glass: desilvering creeping in from the edges as dark blotches,
// soap-splash smudges along the bottom, drip streaks, faint wobble in the
// glass. Grime is diffuse and catches the flashlight; clean glass shows only
// the reflection.

uniform sampler2D reflection : source_color, filter_linear, repeat_disable;
uniform vec2 size_m = vec2(2.4, 0.8);
uniform float seed = 0.0;
uniform float reflectance = 0.82;

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

float fbm(vec2 p) {
	return noise(p) * 0.5 + noise(p * 2.1 + 3.7) * 0.3 + noise(p * 4.3 + 9.1) * 0.2;
}

void fragment() {
	vec2 m = UV * size_m;                       // metres across the glass
	vec2 s = vec2(seed, seed * 1.37);
	// The reflection camera sees the room un-mirrored, so flip X.
	vec2 wobble = (vec2(noise(m * 3.0 + s), noise(m * 3.0 + s + 11.0)) - 0.5) * 0.0025;
	vec3 refl = texture(reflection, vec2(1.0 - UV.x, UV.y) + wobble).rgb;
	// Desilvering: distance to the edge in metres, eaten into by noise.
	float edge = min(min(m.x, size_m.x - m.x), min(m.y, size_m.y - m.y));
	float rot = smoothstep(0.09, 0.0, edge - (fbm(m * 9.0 + s) - 0.5) * 0.12);
	rot = max(rot, smoothstep(0.78, 0.86, fbm(m * 5.0 + s + 4.0)) * smoothstep(0.35, 0.05, edge));
	// Smudges, heavier near the bottom where hands and splashes reach.
	float low = 1.0 - smoothstep(0.0, size_m.y * 0.55, size_m.y - m.y);
	float smudge = smoothstep(0.55, 0.85, fbm(m * vec2(4.0, 6.0) + s + 20.0)) * (0.25 + 0.75 * low);
	// Drip streaks running down from the top.
	float column = noise(vec2(m.x * 38.0 + seed, 0.0));
	float drip = smoothstep(0.86, 0.97, column) * smoothstep(size_m.y * (0.2 + 0.6 * noise(vec2(m.x * 38.0, 5.0 + seed))), 0.0, m.y);
	float grime = clamp(smudge * 0.4 + drip * 0.25, 0.0, 1.0);
	refl *= reflectance * (1.0 - rot * 0.93) * (1.0 - grime * 0.35);
	// Grime is a faint film, not paint: it only shows as a soft haze where
	// the flashlight hits it. Desilvered patches are simply dead, dark glass.
	ALBEDO = vec3(0.07, 0.066, 0.06) * grime + vec3(0.008) * rot;
	EMISSION = refl;
	ROUGHNESS = mix(0.03, 0.45, grime);
	SPECULAR = mix(0.5, 0.2, max(grime, rot));
}
