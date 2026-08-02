extends SceneTree

# Checks the tutorial is actually PLAYABLE, not just that the state machine
# advances: every lesson must arrive with its ability off cooldown, with the
# right practice targets alive, and with dummies tough enough (or frail enough)
# for what the lesson asks.
#   godot --headless --script res://tools/test_tutorial_play.gd

var elapsed: float = 0.0
var lvl: Node = null
var failures: Array[String] = []

func check(label: String, ok: bool) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		failures.append(label)

func _initialize() -> void:
	set_meta("difficulty", 0)
	set_meta("tutorial_enabled", true)
	change_scene_to_file("res://scenes/level1.tscn")

func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed < 1.0:
		return false
	lvl = current_scene
	if lvl == null:
		return false
	var cat = lvl.get_tree().get_first_node_in_group("player")
	var steps: Array = lvl.get("TUTORIAL_STEPS")

	for i in steps.size():
		var step: Dictionary = steps[i]
		lvl.set("tutorial_step", i)
		lvl.set("tut_advancing", false)
		# Put every cooldown under load, the way the previous lesson leaves them.
		cat.set("paw_cd", 9.0)
		cat.set("bite_cd_left", 9.0)
		cat.set("tail_cd", 9.0)
		cat.set("leer_cd", 9.0)
		cat.set("dash_cd_left", 9.0)
		lvl.call("_begin_tutorial_step")

		var title: String = String(step["title"])
		var ready_ok: bool = (float(cat.get("paw_cd")) <= 0.0
			and float(cat.get("bite_cd_left")) <= 0.0
			and float(cat.get("tail_cd")) <= 0.0
			and float(cat.get("leer_cd")) <= 0.0
			and float(cat.get("dash_cd_left")) <= 0.0)
		check("%s: kit is off cooldown on arrival" % title, ready_ok)

		var wanted := int(step.get("dummies", 0)) + int(step.get("armed", 0))
		var live := int(lvl.call("_live_tut_dummies"))
		check("%s: %d practice target(s) present" % [title, wanted], live == wanted)

		# A lesson that needs N hits must not kill its dummy before N landed.
		if wanted > 0:
			var hp := int(step.get("dummy_hp", 30))
			var goal := String(step["goal"])
			var need := int(step.get("need", 1))
			if goal == "execute":
				# marked paw does 4; must be killable in a couple of swings
				check("%s: target is killable (%d hp)" % [title, hp], hp <= 8)
			elif goal == "paw_hit":
				check("%s: survives %d paws (%d hp vs %d dmg)" % [title, need, hp, need * 2],
					hp > need * 2)
			elif goal == "bite":
				check("%s: survives %d jaws (%d hp vs %d dmg)" % [title, need, hp, need * 4],
					hp > need * 4)

	print("")
	if failures.is_empty():
		print("ALL TUTORIAL PLAYABILITY CHECKS PASSED")
	else:
		printerr("FAILURES: ", failures)
	return true
