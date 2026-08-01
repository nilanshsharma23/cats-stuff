extends SceneTree

# Dev check: walk the coached tutorial from the first lesson to the first real
# wave, crediting each step's goal the way the cat would. Catches soft-locks,
# bad goal names and dummy-spawn breakage without needing a human at the keys.
#   godot --headless --script res://tools/test_tutorial.gd

var elapsed: float = 0.0
var level: Node = null
var guard: int = 0

func _initialize() -> void:
	root.set_meta("tutorial_enabled", true)
	get_root().set_meta("tutorial_enabled", true)
	set_meta("tutorial_enabled", true)
	change_scene_to_file("res://scenes/level1.tscn")

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed < 1.0:
		return false
	if level == null:
		level = current_scene
		if level == null:
			return false
		if not bool(level.get("tutorial_active")):
			printerr("FAIL: tutorial did not start")
			return true
		print("tutorial started, ", level.get("TUTORIAL_STEPS").size(), " steps")
	guard += 1
	if guard > 400:
		printerr("FAIL: tutorial never completed (stuck on step ", level.get("tutorial_step"), ")")
		return true
	if not bool(level.get("tutorial_active")):
		print("tutorial finished; waves built = ", level.get("waves").size(),
			" wave_index = ", level.get("wave_index"))
		print("leftover dummies = ", level.get("tut_dummies").size())
		if int(level.get("waves").size()) <= 0:
			printerr("FAIL: no waves after tutorial")
		else:
			print("OK: tutorial completed and handed off to the waves")
		return true
	var steps: Array = level.get("TUTORIAL_STEPS")
	var index: int = int(level.get("tutorial_step"))
	if index >= steps.size():
		return false
	var step: Dictionary = steps[index]
	# Skip the arming delay so the harness can drive it fast.
	level.set("tut_ready_timer", 0.0)
	level.call("_tutorial_credit", String(step["goal"]))
	return false
