extends SceneTree

# Capture the pigeon boss fight and verify its facing. The side artwork is drawn
# facing LEFT, so it must be mirrored when the bird heads right - this puts the
# cat on each side of the boss in turn, prints the animation row and flip it
# chose, and saves a frame of each.
#
#   SHOT_DIR=<dir> godot --resolution 1280x720 --script res://tools/shot_boss.gd

# label, where the cat stands relative to the boss, expected row, expected flip
const CASES := [
	["cat_right", Vector2(70, 0), "side", true],
	["cat_left", Vector2(-70, 0), "side", false],
	["cat_below", Vector2(0, 60), "front", false],
	["cat_above", Vector2(0, -60), "back", false],
]

var elapsed: float = 0.0
var index: int = -1
var boss: Node = null
var cat: Node = null
var lvl: Node = null
var out_dir := ""
var problems: Array[String] = []

func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = "user://"
	set_meta("difficulty", 1)
	set_meta("tutorial_enabled", false)
	change_scene_to_file("res://scenes/level4.tscn")

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed < 1.2:
		return false
	lvl = current_scene
	if lvl == null:
		return false
	if boss == null:
		lvl.call("_spawn_at", "pigeon_boss", Vector2(140, 90))
		lvl.set("boss_active", true)
		boss = lvl.get_tree().get_first_node_in_group("boss")
		cat = lvl.get_tree().get_first_node_in_group("player")
		index = 0
		elapsed = 0.0
		return false

	if index >= CASES.size():
		print("")
		if problems.is_empty():
			print("FACING OK: every direction picked the right row and mirror")
		else:
			printerr("FACING PROBLEMS: ", problems)
		return true

	var case_data: Array = CASES[index]
	var label: String = case_data[0]
	var offset: Vector2 = case_data[1]
	# Clear the rabble and keep the cat untouchable, so the capture shows the
	# boss duel rather than a red strobe of the cat being chewed by a wave.
	for e in lvl.get_tree().get_nodes_in_group("enemies"):
		if e != boss and is_instance_valid(e):
			e.queue_free()
	cat.set("invuln_timer", 99.0)
	# Move the BOSS around the cat, not the other way round: the cat is a
	# CharacterBody2D being pushed by its own physics and will not stay where a
	# _process hook puts it, which quietly invalidated the first attempt.
	boss.set("attack_kind", "")
	boss.set("attack_cd", 5.0)
	boss.global_position = cat.global_position - offset
	boss.set("last_direction", offset.normalized())
	if elapsed < 0.9:
		return false

	var sprite: AnimatedSprite2D = boss.get_node("Anim")
	# Drive the facing logic off the true bearing to the cat. Reading whatever
	# the sprite happens to show mid-hover is racy: _animate() runs at the top of
	# _physics_process, before _hover() refreshes last_direction, so a sampled
	# frame can be a step behind.
	boss.set("last_direction", (cat.global_position - boss.global_position).normalized())
	var anim_name: String = "fly_%s" % String(boss.call("_facing"))
	var flipped: bool = sprite.flip_h
	var want_row: String = case_data[2]
	var want_flip: bool = case_data[3]
	var row_ok: bool = anim_name.ends_with(want_row)
	var flip_ok: bool = flipped == want_flip
	print("%-10s -> %-12s flip_h=%-5s   want row '%s' flip=%s   %s" % [
		label, anim_name, flipped, want_row, want_flip,
		"ok" if (row_ok and flip_ok) else "MISMATCH"])
	if not (row_ok and flip_ok):
		problems.append(label)

	var img: Image = root.get_texture().get_image()
	img.save_png("%s/boss_%s.png" % [out_dir, label])
	var big := img.duplicate()
	big.resize(img.get_width() * 4, img.get_height() * 4, Image.INTERPOLATE_NEAREST)
	big.save_png("%s/boss_%s_4x.png" % [out_dir, label])

	index += 1
	elapsed = 0.0
	return false
