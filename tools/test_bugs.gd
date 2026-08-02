extends SceneTree

# Regression checks for interaction bugs found during a bug hunt.
#   godot --headless --script res://tools/test_bugs.gd

var elapsed: float = 0.0
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
	var lvl := current_scene
	if lvl == null:
		return false
	var cat = lvl.get_tree().get_first_node_in_group("player")

	print("1. a stunned frog must not escape by hopping")
	lvl.call("_spawn_at", "frog", cat.global_position + Vector2(30, 0))
	var frog = null
	for e in lvl.get_tree().get_nodes_in_group("frogs"):
		frog = e
		break
	if frog == null:
		printerr("  no frog spawned")
		return true
	# The frog only resolves `player` inside _physics_process, which has not run
	# yet for a just-spawned node - without this the hop guard short-circuits on
	# a null player and the test passes for the wrong reason.
	frog.set("player", cat)
	frog.set("hop_cd", 0.0)
	frog.call("stun", 2.0)
	check("frog is stunned", float(frog.get("stun_timer")) > 0.0)
	frog.call("take_damage", 1)
	check("stunned frog did not start a hop", not bool(frog.get("is_hopping")))
	check("stun survived the hit", float(frog.get("stun_timer")) > 0.0)

	print("2. a parry-frozen frog must not escape either")
	frog.set("hop_cd", 0.0)
	frog.call("freeze", 2.0)
	frog.call("take_damage", 1)
	check("frozen frog did not start a hop", not bool(frog.get("is_hopping")))

	print("3. boss-summoned minions stay inside the room")
	var play_min: Vector2 = lvl.get("play_min")
	var play_max: Vector2 = lvl.get("play_max")
	lvl.call("_spawn_at", "frog_boss", Vector2(120, 80))
	var boss = lvl.get_tree().get_first_node_in_group("boss")
	if boss != null:
		boss.call("_spawn_minion")
		var minions := lvl.get_tree().get_nodes_in_group("frog_boss_minion")
		check("a minion spawned", minions.size() > 0)
		if minions.size() > 0:
			var m = minions[0]
			var mn: Vector2 = m.get("arena_min")
			var mx: Vector2 = m.get("arena_max")
			print("    minion clamp %s..%s   room %s..%s" % [mn, mx, play_min, play_max])
			check("minion clamp matches this room", mn.is_equal_approx(play_min) and mx.is_equal_approx(play_max))

	print("4. an interrupted Overdrive plan must not leave the cat invincible")
	lvl.set("style_meter", 600.0)
	lvl.set("boss_active", true)
	if bool(lvl.call("_can_ultimate")):
		lvl.call("_start_ultimate")
		check("planning started", String(lvl.get("ult_state")) == "plan")
		# Interrupt while still planning (nothing recorded, no execution).
		lvl.call("_end_ultimate")
		var inv: float = float(cat.get("invuln_timer"))
		print("    invuln_timer after interrupt: %.2f" % inv)
		check("i-frames released after interrupt", inv <= 1.0)
	else:
		printerr("  could not arm the ultimate")

	print("5. finishing a tutorial lesson must not auto-complete the next one")
	lvl.set("tutorial_active", true)
	lvl.set("tutorial_step", 2)      # PAW, needs 4
	lvl.set("tut_progress", 3)
	lvl.set("tut_ready_timer", 0.0)
	lvl.set("tut_advancing", false)
	lvl.call("_tutorial_credit", "paw_hit")   # 4th rep -> completes, advances
	check("advanced off the PAW lesson", int(lvl.get("tutorial_step")) == 3)
	check("hand-off is locked", bool(lvl.get("tut_advancing")))
	# DASH (step 3) needs 2. Spamming during the hand-off must not count.
	lvl.call("_tutorial_credit", "dash")
	lvl.call("_tutorial_credit", "dash")
	lvl.call("_tutorial_credit", "dash")
	check("DASH not credited during hand-off", int(lvl.get("tutorial_step")) == 3)
	check("progress reset for the next lesson", int(lvl.get("tut_progress")) == 0)
	lvl.set("tutorial_active", false)

	print("")
	if failures.is_empty():
		print("ALL BUG CHECKS PASSED")
	else:
		printerr("FAILURES: ", failures)
	return true
