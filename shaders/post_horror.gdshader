shader_type canvas_item;
// Full-screen horror grade, driven by ui/post_fx.gd from the state of Jude.
//   panic        - heartbeat lens pulse, tunnel vision, colour drain, wobble
//   bleeding     - dark red veins creeping in from the screen edge
//   hit_flash    - the moment a blow lands
//   static_burst - a jolt of noise when glass shatters or the Tiktik strikes
// Film grain, a soft vignette and slight chromatic aberration are always on.

#include "res://shaders/noise.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float panic : hint_range(0.0, 1.0) = 0.0;
uniform float bleeding : hint_range(0.0, 1.0) = 0.0;
uniform float hit_flash : hint_range(0.0, 1.0) = 0.0;
uniform float static_burst : hint_range(0.0, 1.0) = 0.0;
uniform float heartbeat_phase = 0.0;
uniform float grain_amount : hint_range(0.0, 0.3) = 0.05;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.5;
uniform float aberration : hint_range(0.0, 0.01) = 0.0011;

float grain_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r = length(c);

	// Lub-dub.
	float beat = pow(max(sin(heartbeat_phase * TAU), 0.0), 8.0)
		+ 0.6 * pow(max(sin((heartbeat_phase - 0.18) * TAU), 0.0), 8.0);
	float pulse = beat * smoothstep(0.3, 1.0, panic);

	// The view swells with each beat and swims at high panic.
	uv = 0.5 + c * (1.0 - pulse * 0.012);
	float wobble = smoothstep(0.6, 1.0, panic);
	uv.x += sin(uv.y * 18.0 + TIME * 2.3) * 0.0016 * wobble;
	uv.y += cos(uv.x * 14.0 + TIME * 1.9) * 0.0016 * wobble;
	// Horizontal tearing during a static burst.
	float tear = step(0.92, hash21(vec2(floor(uv.y * 90.0), floor(TIME * 30.0))));
	uv.x += tear * static_burst * 0.03 * (hash21(vec2(floor(TIME * 40.0), 3.0)) - 0.5);

	float ca = (aberration + panic * 0.004 + hit_flash * 0.01 + static_burst * 0.006) * (0.3 + r * 2.0);
	vec2 dir = normalize(c + vec2(0.00001));
	vec3 col;
	col.r = texture(screen_tex, uv + dir * ca).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - dir * ca).b;

	// Colour drains and cools as panic rises.
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma), panic * 0.55);
	col *= mix(vec3(1.0), vec3(0.92, 0.98, 1.07), panic * 0.6);

	// Film grain, stronger in the shadows.
	// hash21 is only random across whole-number cells; fed raw pixel
	// coordinates it settles into a visible lattice, so grain has its own hash
	// and a whole-pixel offset that changes 24 times a second.
	float grain = grain_hash(floor(FRAGCOORD.xy) + floor(TIME * 24.0) * vec2(37.0, 91.0)) - 0.5;
	col += grain * (grain_amount + panic * 0.05 + static_burst * 0.35) * (1.0 - luma * 0.6);

	// Vignette that closes into tunnel vision.
	float vig = 1.0 - smoothstep(0.25, 0.85 - panic * 0.3 - pulse * 0.06, r);
	col *= mix(1.0, vig, clamp(vignette_strength + panic * 0.3, 0.0, 1.0));

	// Blood at the edge of sight.
	float veins = fbm2(c * 7.0 + vec2(TIME * 0.04, 0.0));
	float edge = smoothstep(0.34, 0.74, r + (veins - 0.5) * 0.3);
	float blood = edge * (bleeding * (0.5 + 0.25 * beat) + hit_flash);
	col = mix(col, vec3(0.33, 0.0, 0.01) * (0.5 + luma), clamp(blood, 0.0, 0.85));

	COLOR = vec4(col, 1.0);
}
