shader_type canvas_item;

// Full-screen colour grade for the OVERDRIVE ultimate: remaps the world's
// luminance onto a deep-violet -> hot-magenta -> cyan ramp, so the arena reads
// as a neon simulation while time is stopped. Sits at the bottom of the UI
// CanvasLayer, which means it grades the world but leaves the HUD untouched.
//
// `amount` drives the whole effect (0 = untouched game) so it can be tweened in
// and out. `surge` is pushed to 1.0 for the execution phase to blow out the
// highlights while the combo actually lands.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float surge : hint_range(0.0, 1.0) = 0.0;

const vec3 SHADOW = vec3(0.16, 0.02, 0.38);
const vec3 MID = vec3(0.95, 0.16, 0.90);
const vec3 HILIGHT = vec3(0.35, 1.0, 1.0);

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	float lum = dot(src, vec3(0.299, 0.587, 0.114));

	// Two-stage ramp: violet in the shadows, magenta through the mids, cyan on
	// the brightest pixels - the classic neon triad.
	vec3 graded = mix(SHADOW, MID, smoothstep(0.12, 0.55, lum));
	graded = mix(graded, HILIGHT, smoothstep(0.58, 0.95, lum));

	// Keep a little of the original hue so sprites stay identifiable.
	graded = mix(graded, graded * (0.65 + src * 0.9), 0.35);

	// Rolling scanlines plus a faint horizontal sweep for the "jacked in" look.
	float scan = 0.88 + 0.12 * sin(SCREEN_UV.y * 190.0 + TIME * 9.0);
	float sweep = 0.94 + 0.06 * sin(SCREEN_UV.y * 3.0 - TIME * 2.2);
	graded *= scan * sweep;

	// Vignette pulls focus to the centre of the arena.
	vec2 d = SCREEN_UV - vec2(0.5);
	graded *= 1.0 - clamp(dot(d, d) * 1.15, 0.0, 0.55);

	// Execution surge: bloom the highlights and push everything hotter.
	graded += vec3(0.55, 0.12, 0.65) * surge * smoothstep(0.4, 1.0, lum);
	graded *= 1.0 + 0.25 * surge;

	COLOR = vec4(mix(src, graded, amount), 1.0);
}
