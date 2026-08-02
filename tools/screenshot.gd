extends SceneTree

# Capture real frames of chosen tutorial lessons at actual game resolution.
#
# Worth keeping: --headless uses a dummy renderer, so no automated check can see
# layout. Every HUD test passed while the coach card was sitting directly on top
# of the cat and the rat the lesson told you to hit - only a screenshot showed it.
#
#   SHOT_DIR=<dir> godot --resolution 1280x720 --script res://tools/screenshot.gd
#
# Writes tut_step<N>.png (native 320x180) and tut_step<N>_4x.png (nearest-
# upscaled, for reading the pixel font).

var elapsed: float = 0.0
var staged: bool = false
var shots: int = 0
const STEPS_TO_SHOOT := [0, 2, 8]
var out_dir := ""

func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = "user://"
	set_meta("difficulty", 0)
	set_meta("tutorial_enabled", true)
	change_scene_to_file("res://scenes/level1.tscn")

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed < 1.2:
		return false
	var lvl := current_scene
	if lvl == null:
		return false
	if not staged:
		staged = true
		lvl.set("tutorial_step", int(STEPS_TO_SHOOT[shots]))
		lvl.set("tut_advancing", false)
		lvl.call("_begin_tutorial_step")
		elapsed = 0.9
		return false

	var img: Image = root.get_texture().get_image()
	var step: int = int(STEPS_TO_SHOOT[shots])
	img.save_png("%s/tut_step%d.png" % [out_dir, step])
	# 4x nearest upscale so the pixel text is legible when reviewed.
	var big := img.duplicate()
	big.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
	big.save_png("%s/tut_step%d_4x.png" % [out_dir, step])
	print("saved lesson ", step)
	shots += 1
	if shots >= STEPS_TO_SHOOT.size():
		return true
	staged = false
	elapsed = 1.0
	return false
