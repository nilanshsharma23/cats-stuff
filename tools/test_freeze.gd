extends SceneTree

# Repro harness: put a rat on top of the cat, let it land a hit, and watch what
# happens to Engine.time_scale afterwards. A hitstop that never restores reads
# to the player as "the whole game froze".
#   godot --headless --script res://tools/test_freeze.gd

var elapsed: float = 0.0
var armed: bool = false
var samples: int = 0
var min_scale: float = 1.0
var hit_seen: bool = false
var cat: Node = null
var level: Node = null

func _initialize() -> void:
	set_meta("difficulty", 1)
	set_meta("tutorial_enabled", false)
	change_scene_to_file("res://scenes/level2.tscn")

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed < 1.0:
		return false
	level = current_scene
	if level == null:
		return false
	if not armed:
		armed = true
		cat = level.get_tree().get_first_node_in_group("player")
		# Drop a rat right on top of her so it attacks immediately.
		level.call("_spawn_at", "rat", cat.global_position + Vector2(10, 0))
		print("armed: cat hp ", cat.get("health"), " time_scale ", Engine.time_scale)
		return false

	samples += 1
	min_scale = minf(min_scale, Engine.time_scale)
	if int(cat.get("health")) < 8:
		hit_seen = true

	# Watch for a couple of seconds after the first hit lands.
	if elapsed > 6.0:
		print("cat hp now: ", cat.get("health"), " (took a hit: ", hit_seen, ")")
		print("Engine.time_scale  min=%.3f  final=%.3f" % [min_scale, Engine.time_scale])
		if hit_seen and Engine.time_scale < 0.99:
			printerr("BUG: time_scale never restored -> game runs at %.0f%% speed" % (Engine.time_scale * 100.0))
		elif hit_seen:
			print("OK: time_scale recovered after the hitstop")
		else:
			print("INCONCLUSIVE: no hit landed in the window")
		return true
	return false
