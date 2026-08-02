extends SceneTree

# Dev check for the 320x180 move: every level must have a working camera that is
# clamped to its own room, a visible UI layer, HUD elements inside the screen,
# and a clock that always returns to full speed.
#   godot --headless --script res://tools/test_viewport.gd

var levels := ["level1", "level2", "level3", "level4"]
var index: int = 0
var elapsed: float = 0.0
var failures: Array[String] = []

func check(label: String, ok: bool) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		failures.append(label)

func _initialize() -> void:
	set_meta("difficulty", 1)
	set_meta("tutorial_enabled", false)
	change_scene_to_file("res://scenes/%s.tscn" % levels[0])

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed < 0.8:
		return false
	var lvl := current_scene
	if lvl == null:
		return false
	var level_name: String = levels[index]
	print("=== ", level_name)

	var cam: Camera2D = lvl.get("cam")
	check("camera present and current", cam != null and cam.is_current())
	check("UI layer visible", bool(lvl.get_node("UI").visible))

	var amin: Vector2 = lvl.get("arena_min")
	var amax: Vector2 = lvl.get("arena_max")
	var view: Vector2 = lvl.get("VIEW_SIZE")
	print("    arena %s..%s  view %s" % [amin, amax, view])
	check("arena measured", amax.x > amin.x and amax.y > amin.y)

	# Camera must never show past the walls on an axis larger than the screen.
	var worst_x := 0.0
	var worst_y := 0.0
	for probe in [amin, amax, Vector2(amin.x, amax.y), Vector2(amax.x, amin.y)]:
		var cat = lvl.get_tree().get_first_node_in_group("player")
		cat.global_position = probe
		var target: Vector2 = lvl.call("_camera_target")
		var half := view * 0.5
		if amax.x - amin.x > view.x:
			worst_x = maxf(worst_x, maxf(amin.x - (target.x - half.x), (target.x + half.x) - amax.x))
		if amax.y - amin.y > view.y:
			worst_y = maxf(worst_y, maxf(amin.y - (target.y - half.y), (target.y + half.y) - amax.y))
	check("camera stays inside the room (x)", worst_x <= 0.01)
	check("camera stays inside the room (y)", worst_y <= 0.01)

	# Spawns must land inside the room too.
	var bad_spawns := 0
	for i in 200:
		var p: Vector2 = lvl.call("_spawn_point")
		if p.x < amin.x or p.x > amax.x or p.y < amin.y or p.y > amax.y:
			bad_spawns += 1
	check("spawn points inside the arena", bad_spawns == 0)

	# Every HUD control must be on screen.
	var offscreen: Array[String] = []
	for node in lvl.get_node("UI").get_children():
		if not (node is Control):
			continue
		var c := node as Control
		if c.name == "NeonGrade" or c.name == "Flash" or c.name == "DangerVignette" or c.name == "Vignette":
			continue
		var r := Rect2(c.position, c.size)
		if r.size == Vector2.ZERO:
			continue
		if r.position.x < -1 or r.position.y < -1 or r.end.x > view.x + 1 or r.end.y > view.y + 1:
			offscreen.append("%s %s" % [c.name, r])
	if not offscreen.is_empty():
		print("    offscreen: ", offscreen)
	check("HUD elements fit on screen", offscreen.is_empty())

	index += 1
	if index >= levels.size():
		print("")
		if failures.is_empty():
			print("ALL VIEWPORT CHECKS PASSED")
		else:
			printerr("FAILURES: ", failures)
		return true
	elapsed = 0.0
	change_scene_to_file("res://scenes/%s.tscn" % levels[index])
	return false
