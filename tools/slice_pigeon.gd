extends SceneTree

# Dev utility: slice the pigeon sheets into individual frame PNGs.
#
# The sheets are 4 facing-rows x N animation-columns, with a title banner on the
# hurt/death sheets that has to be skipped. Every frame of an animation is cut
# with the SAME rect (the union of that row's content) so the bird keeps its
# relative motion instead of jittering frame to frame.
#
#   godot --headless --script res://tools/slice_pigeon.gd

const OUT_DIR := "res://sprites/pigeon"
const PREVIEW_DIR := "user://pigeon_preview"

# sheet path, animation name, column count, top of the sprite grid (skips banner)
const SHEETS := [
	["res://sprites/pigeon-1.png", "idle", 4, 0],
	["res://sprites/pigeon-2.png", "fly", 6, 0],
	["res://sprites/pigeon-3.png", "hurt", 4, 50],
	["res://sprites/pigeon-4.png", "death", 6, 50],
]

const ROW_NAMES := ["front", "back", "side_a", "side_b"]
const ROWS := 4

func _has_content(img: Image, x: int, y: int) -> bool:
	var c := img.get_pixel(x, y)
	if c.a < 0.15:
		return false
	return c.r < 0.92 or c.g < 0.92 or c.b < 0.92

# Content bounds of one grid cell, in cell-local pixels. Returns an empty rect
# when the cell holds nothing.
func _cell_bounds(img: Image, cx: int, cy: int, cw: int, ch: int) -> Rect2i:
	var min_x := cw
	var min_y := ch
	var max_x := -1
	var max_y := -1
	for y in ch:
		var gy := cy + y
		if gy >= img.get_height():
			break
		for x in cw:
			var gx := cx + x
			if gx >= img.get_width():
				break
			if _has_content(img, gx, gy):
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

# White-background sheets need the background knocked out to alpha, otherwise
# every frame renders as a white card over the arena.
func _keyed_copy(img: Image, src: Rect2i, dst_size: Vector2i, at: Vector2i) -> Image:
	var out := Image.create(dst_size.x, dst_size.y, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in src.size.y:
		for x in src.size.x:
			var gx := src.position.x + x
			var gy := src.position.y + y
			if gx >= img.get_width() or gy >= img.get_height():
				continue
			var c := img.get_pixel(gx, gy)
			if c.a < 0.15:
				continue
			if c.r > 0.92 and c.g > 0.92 and c.b > 0.92:
				continue
			out.set_pixel(at.x + x, at.y + y, c)
	return out

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIR))
	for sheet in SHEETS:
		_slice(String(sheet[0]), String(sheet[1]), int(sheet[2]), int(sheet[3]))
	quit()

func _slice(path: String, anim: String, cols: int, grid_top: int) -> void:
	var img := Image.load_from_file(path)
	if img == null:
		print("FAILED ", path)
		return
	var w := img.get_width()
	var h := img.get_height()
	var grid_h := h - grid_top

	# Pass 1: union of every cell's content bounds, per row.
	var row_rects: Array[Rect2i] = []
	for r in ROWS:
		var union := Rect2i(0, 0, 0, 0)
		for c in cols:
			var cx := int(round(float(c) * float(w) / float(cols)))
			var cx2 := int(round(float(c + 1) * float(w) / float(cols)))
			var cy := grid_top + int(round(float(r) * float(grid_h) / float(ROWS)))
			var cy2 := grid_top + int(round(float(r + 1) * float(grid_h) / float(ROWS)))
			var b := _cell_bounds(img, cx, cy, cx2 - cx, cy2 - cy)
			if b.size.x == 0:
				continue
			union = b if union.size.x == 0 else union.merge(b)
		row_rects.append(union)

	# Pass 2: cut every frame with its row's shared rect, padded by 1px.
	for r in ROWS:
		var rect := row_rects[r]
		if rect.size.x == 0:
			continue
		var fw := rect.size.x + 2
		var fh := rect.size.y + 2
		var strip := Image.create(fw * cols, fh, false, Image.FORMAT_RGBA8)
		strip.fill(Color(0, 0, 0, 0))
		for c in cols:
			var cx := int(round(float(c) * float(w) / float(cols)))
			var cy := grid_top + int(round(float(r) * float(grid_h) / float(ROWS)))
			var src := Rect2i(cx + rect.position.x, cy + rect.position.y, rect.size.x, rect.size.y)
			var frame := _keyed_copy(img, src, Vector2i(fw, fh), Vector2i(1, 1))
			var name := "%s_%s_%d" % [anim, ROW_NAMES[r], c]
			frame.save_png("%s/%s.png" % [OUT_DIR, name])
			strip.blit_rect(frame, Rect2i(0, 0, fw, fh), Vector2i(c * fw, 0))
		strip.save_png("%s/%s_%s_STRIP.png" % [PREVIEW_DIR, anim, ROW_NAMES[r]])
		print("%s row %s -> %d frames of %dx%d" % [anim, ROW_NAMES[r], cols, fw, fh])
