shader_type canvas_item;

// `active` is the dash flash. The outline is the readability fix: the cat's
// palette sits very close to the floor tiles, so without a rim she disappears
// into the background the moment the screen gets busy.
//
// The rim is drawn just INSIDE the silhouette (sampling neighbours and
// recolouring edge pixels) because a sprite quad has no room outside itself to
// draw into. COLOR is only ever overwritten for the pixels that need it, so the
// node's modulate / self_modulate tints still come through everywhere else.

uniform bool active;
uniform vec3 flash_color : source_color = vec3(1.0);
uniform bool outline_enabled = true;
uniform vec4 outline_color : source_color = vec4(0.05, 0.03, 0.10, 1.0);
uniform float outline_width = 1.0;
uniform float alpha_cutoff = 0.35;

void fragment(){
	vec4 t = texture(TEXTURE, UV);
	if (active == true) {
		COLOR = vec4(flash_color, t.a);
	}
	if (outline_enabled && t.a > alpha_cutoff) {
		vec2 px = TEXTURE_PIXEL_SIZE * outline_width;
		float right = texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
		float left = texture(TEXTURE, UV - vec2(px.x, 0.0)).a;
		float down = texture(TEXTURE, UV + vec2(0.0, px.y)).a;
		float up = texture(TEXTURE, UV - vec2(0.0, px.y)).a;
		// Sampling past the edge of the frame wraps or clamps depending on the
		// import, so treat anything outside 0..1 as empty space too.
		if (UV.x + px.x > 1.0) { right = 0.0; }
		if (UV.x - px.x < 0.0) { left = 0.0; }
		if (UV.y + px.y > 1.0) { down = 0.0; }
		if (UV.y - px.y < 0.0) { up = 0.0; }
		float neighbour = min(min(right, left), min(down, up));
		if (neighbour <= alpha_cutoff) {
			COLOR = vec4(outline_color.rgb, COLOR.a);
		}
	}
}
