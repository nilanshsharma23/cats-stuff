extends SceneTree

# Frogs were incapable of dealing damage: they walked to croak_range and croaked,
# but the croak only reached aoe_radius, which was SMALLER. On top of that the
# dodge-hop triggered from further out than their attack range, so they bailed
# before ever getting close. This asserts a frog can actually hurt the player.
#   godot --headless --script res://tools/test_frogs.gd

var elapsed: float = 0.0
var armed := false
var lvl: Node = null
var cat: Node = null
var start_hp: int = 0
var failures: Array[String] = []

func check(label: String, ok: bool) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		failures.append(label)

func _initialize() -> void:
	set_meta("difficulty", 1)
	set_meta("tutorial_enabled", false)
	change_scene_to_file("res://scenes/level3.tscn")

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed < 1.0:
		return false
	lvl = current_scene
	if lvl == null:
		return false

	if not armed:
		armed = true
		cat = lvl.get_tree().get_first_node_in_group("player")
		# Config sanity first - this is the invariant that was violated.
		for key in ["frog", "spitter"]:
			var cfg: Dictionary = lvl.call("_scaled_cfg", lvl.get("ROSTER")[key]["cfg"], "frog")
			var reach: float = float(cfg.get("croak_range", 34.0))
			var radius: float = float(cfg.get("aoe_radius", 28.0))
			print("    %-8s croaks from %.0f, cloud reaches %.0f" % [key, reach, radius])
			check("%s can reach what it attacks" % key, reach <= radius)
		# Clear the level and put a handful of frogs on the cat.
		for e in lvl.get_tree().get_nodes_in_group("enemies"):
			e.queue_free()
		for i in 4:
			lvl.call("_spawn_at", "frog", cat.global_position + Vector2(28 + i * 8, 0))
		for i in 2:
			lvl.call("_spawn_at", "spitter", cat.global_position + Vector2(-40, 10 * i))
		start_hp = int(cat.get("health"))
		elapsed = 0.0
		return false

	# Let them fight for a while. The cat just stands there.
	if elapsed < 12.0:
		return false

	var now_hp: int = int(cat.get("health"))
	var croaked := 0
	for f in lvl.get_tree().get_nodes_in_group("frogs"):
		if bool(f.get("is_croaking")):
			croaked += 1
	print("    cat went %d -> %d hp over 12s with 6 frogs on it" % [start_hp, now_hp])
	check("frogs actually damaged the player", now_hp < start_hp)

	print("")
	if failures.is_empty():
		print("ALL FROG CHECKS PASSED")
	else:
		printerr("FAILURES: ", failures)
	return true
