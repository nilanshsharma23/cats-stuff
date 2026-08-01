extends SceneTree

# Dev check: confirm each difficulty actually produces different enemy stats and
# a different player health pool, and that heart drops / hop dodging are wired.
#   godot --headless --script res://tools/test_difficulty.gd

var elapsed: float = 0.0
var mode: int = 0
var level: Node = null
var reported: Array[String] = []

func _initialize() -> void:
	set_meta("difficulty", 0)
	set_meta("tutorial_enabled", false)
	change_scene_to_file("res://scenes/level1.tscn")

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed < 0.9:
		return false
	level = current_scene
	if level == null:
		return false
	var name := String(level.call("_diff")["name"])
	var cfg: Dictionary = level.call("_scaled_cfg", level.get("ROSTER")["rat"]["cfg"], "rat")
	var frog: Dictionary = level.call("_scaled_cfg", level.get("ROSTER")["frog"]["cfg"], "frog")
	var cat = level.get_tree().get_first_node_in_group("player")
	reported.append("%-7s rat hp=%-3d spd=%-6.1f windup=%.3f parry=%.2f | frog hop_cd=%.2f | cat hp=%d" % [
		name, int(cfg["max_health"]), float(cfg["move_speed"]),
		float(cfg["nibble_windup"]), float(cfg["parry_window"]),
		float(frog["hop_cooldown"]), int(cat.get("max_health"))])
	mode += 1
	if mode >= 3:
		for line in reported:
			print(line)
		# Frog hop wiring
		var f = level.get("frog_scene").instantiate()
		var has_hop: bool = f.has_method("_begin_hop") and f.has_method("_run_hop")
		print("frog hop methods present: ", has_hop)
		f.free()
		print("heart drop hook: ", level.has_method("_maybe_drop_heart"))
		print("vignette: ", level.get("danger_vignette") != null)
		print("style bar: ", level.get("style_bar_fill") != null)
		return true
	elapsed = 0.0
	set_meta("difficulty", mode)
	change_scene_to_file("res://scenes/level1.tscn")
	return false
