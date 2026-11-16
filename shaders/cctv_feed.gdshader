shader_type canvas_item;
// The CCTV feed on Juan's phone: a monochrome infrared picture with film
// grain, scanlines, a slow rolling interference band, a dark vignette and a
// burst of static whenever the feed switches cameras.

uniform float switch_static : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(0.82, 0.95, 0.84);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	// A slight horizontal jitter on the rolling band.
	float band_pos = fract(TIME * 0.07);
	float band = smoothstep(0.06, 0.0, abs(uv.y - band_pos));
	uv.x += band * 0.004 * sin(TIME * 40.0 + uv.y * 300.0);
	vec3 color = texture(TEXTURE, uv).rgb;
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	vec3 picture = luma * tint;
	// Grain, finer than a pixel and different every frame.
	float grain = hash(floor(FRAGCOORD.xy * 0.75) + vec2(TIME * 61.0, TIME * 37.0)) - 0.5;
	picture += grain * 0.09;
	// Scanlines and the brighter interference band.
	picture *= 0.88 + 0.12 * sin(FRAGCOORD.y * 2.1);
	picture += band * 0.05;
	// Vignette.
	vec2 c = UV - 0.5;
	picture *= smoothstep(0.85, 0.25, length(c * vec2(1.1, 1.0)));
	// Static when switching feeds.
	float snow = hash(floor(FRAGCOORD.xy * 0.5) + TIME * 113.0);
	picture = mix(picture, vec3(snow) * tint, switch_static * 0.85);
	COLOR = vec4(picture, 1.0);
}
