extends SceneTree

# Dev check: drive the OVERDRIVE ultimate end to end - gating, the world freeze,
# the recording, the replay, and the cleanup afterwards.
#   godot --headless --script res://tools/test_overdrive.gd

var elapsed: float = 0.0
var level: Node = null
var failures: Array[String] = []

func check(label: String, ok: bool) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		failures.append(label)

func _initialize() -> void:
	set_meta("difficulty", 1)
	set_meta("tutorial_enabled", false)
	change_scene_to_file("res://scenes/level4.tscn")

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed < 1.0:
		return false
	level = current_scene
	if level == null:
		return false
	var cat = level.get_tree().get_first_node_in_group("player")

	print("gating:")
	level.set("style_meter", 600.0)
	check("blocked with no boss on the field", not bool(level.call("_can_ultimate")))
	level.call("_spawn_at", "pigeon_boss", Vector2(150, 60))
	level.set("boss_active", true)
	var boss = level.get_tree().get_first_node_in_group("boss")
	check("boss spawned", boss != null)
	check("available at SS with a boss up", bool(level.call("_can_ultimate")))
	level.set("style_meter", 300.0)
	check("blocked below SS", not bool(level.call("_can_ultimate")))
	level.set("style_meter", 600.0)

	print("planning phase:")
	level.call("_start_ultimate")
	check("state is plan", String(level.get("ult_state")) == "plan")
	check("style meter spent", float(level.get("style_meter")) < 1.0)
	check("boss frozen (processing disabled)", boss.process_mode == Node.PROCESS_MODE_DISABLED)
	check("cat is recording", bool(cat.get("planning")))
	check("neon grade visible", bool(level.get("neon_rect").visible))

	# Queue a combo the way the player's clicks would.
	for i in 4:
		cat.call("_paw")
	cat.call("_bite")
	# Headless has no mouse, so _aim() records a direction pointing away from the
	# boss. Re-aim the recorded actions at it so the replay has something to hit.
	for action in cat.get("plan_actions"):
		action["aim"] = (boss.global_position - action["pos"]).normalized()
	var boss_hp_before: int = int(boss.get("health"))
	check("4 paws + 1 jaw recorded", int(cat.call("planned_count")) == 5)
	check("nothing damaged during planning", int(boss.get("health")) == boss_hp_before)
	check("markers drawn for the plan", level.get("ult_markers").size() == 5)

	print("execution phase:")
	level.call("_tick_ultimate", 9.0)
	check("state is exec", String(level.get("ult_state")) == "exec")
	check("cat is replaying", bool(cat.get("executing")))
	check("markers cleared", level.get("ult_markers").size() == 0)
	# Step the replay at physics rate so every recorded action fires.
	for i in 120:
		cat.call("_run_execution", 0.02)
		if not bool(cat.get("executing")):
			break
	check("replay finished", not bool(cat.get("executing")))
	var dealt: int = boss_hp_before - int(boss.get("health"))
	print("    boss took %d damage from the combo (was %d)" % [dealt, boss_hp_before])
	check("combo actually hurt the boss", dealt > 0)

	print("cleanup:")
	level.call("_tick_ultimate", 9.0)
	check("state cleared", String(level.get("ult_state")) == "")
	check("boss unfrozen", boss.process_mode == Node.PROCESS_MODE_PAUSABLE)
	check("cat released", not bool(cat.get("planning")) and not bool(cat.get("executing")))
	check("frozen list emptied", level.get("ult_frozen").size() == 0)

	print("interrupted mid-execution (boss dies to the combo):")
	level.set("style_meter", 600.0)
	level.set("boss_active", true)
	level.call("_spawn_at", "pigeon_boss", Vector2(150, 60))
	var boss2 = level.get_tree().get_first_node_in_group("boss")
	if boss2 != null:
		level.call("_start_ultimate")
		cat.call("_paw")
		level.call("_tick_ultimate", 9.0)
		check("mid-execution before interrupt", String(level.get("ult_state")) == "exec")
		# _finish_run is what actually runs when the boss dies mid-combo.
		level.call("_finish_run", "TEST", true)
		check("ultimate torn down by run end", String(level.get("ult_state")) == "")
		check("enemies released after interrupt", level.get("ult_frozen").size() == 0)
		check("cat released after interrupt", not bool(cat.get("executing")))
		check("neon grade hidden or fading", level.get("neon_rect") != null)

	print("")
	if failures.is_empty():
		print("ALL OVERDRIVE CHECKS PASSED")
	else:
		printerr("FAILURES: ", failures)
	return true
