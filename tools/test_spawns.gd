extends SceneTree

# Every level is now full of furniture with real collision. An enemy dropped
# inside a sofa is wedged there for the rest of the run, so no spawn point may
# ever resolve onto a solid tile.
#   godot --headless --script res://tools/test_spawns.gd

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
	var name: String = levels[index]
	print("=== ", name)

	# How much of the room is actually solid? If this is 0 the level has no
	# collision tiles and the test would pass vacuously.
	var play_min: Vector2 = lvl.get("play_min")
	var play_max: Vector2 = lvl.get("play_max")
	var solid_samples := 0
	for i in 2000:
		var p := Vector2(randf_range(play_min.x, play_max.x), randf_range(play_min.y, play_max.y))
		if bool(lvl.call("_tile_solid_at", p)):
			solid_samples += 1
	print("    %.0f%% of the play area is solid scenery" % (solid_samples / 20.0))
	check("level has collision to avoid", solid_samples > 0)

	var bad_wave := 0
	for i in 400:
		if not bool(lvl.call("is_spawn_clear", lvl.call("_spawn_point"))):
			bad_wave += 1
	check("400 wave spawns all on clear ground", bad_wave == 0)

	var bad_tut := 0
	for i in 200:
		if not bool(lvl.call("is_spawn_clear", lvl.call("_tutorial_spawn_point"))):
			bad_tut += 1
	check("200 tutorial spawns all on clear ground", bad_tut == 0)

	# Hearts drop wherever an enemy died, which can be inside furniture.
	var bad_heart := 0
	for i in 200:
		var raw := Vector2(randf_range(play_min.x, play_max.x), randf_range(play_min.y, play_max.y))
		if not bool(lvl.call("is_spawn_clear", lvl.call("_nearest_clear_point", raw))):
			bad_heart += 1
	check("200 heart drops resolved to clear ground", bad_heart == 0)

	index += 1
	if index >= levels.size():
		print("")
		if failures.is_empty():
			print("ALL SPAWN CHECKS PASSED")
		else:
			printerr("FAILURES: ", failures)
		return true
	elapsed = 0.0
	change_scene_to_file("res://scenes/%s.tscn" % levels[index])
	return false
