extends Node2D

@export var level_id: int = 1
@export var next_level_path: String = ""
@export var rat_scene: PackedScene
@export var frog_scene: PackedScene

@onready var game_over: Control = $UI/GameOver
@onready var banner: Label = $UI/Banner

# Enemy roster. Each entry names a base scene ("rat"/"frog") and a config
# dictionary applied on spawn (stats + tint + scale), so the two sprite rigs
# yield a whole cast of distinct foes.
var ROSTER := {
	"rat": {
		"scene": "rat",
		"cfg": {"max_health": 2, "move_speed": 120.0, "nibble_damage": 1,
			"tint": Color(1, 1, 1), "body_scale": 0.72, "score_value": 12}
	},
	"scurrier": {
		"scene": "rat",
		"cfg": {"max_health": 1, "move_speed": 176.0, "nibble_damage": 1,
			"dash_chance": 0.82, "dash_cooldown_min": 0.7, "dash_cooldown_max": 1.4,
			"tint": Color(0.72, 1.0, 0.55), "body_scale": 0.6, "score_value": 10}
	},
	"brute": {
		"scene": "rat",
		"cfg": {"max_health": 7, "move_speed": 74.0, "nibble_damage": 2,
			"nibble_range": 22.0, "dash_chance": 0.25, "knockback_resist": 0.6,
			"tint": Color(1.0, 0.5, 0.42), "body_scale": 1.08, "score_value": 32}
	},
	"frog": {
		"scene": "frog",
		"cfg": {"max_health": 3, "move_speed": 88.0, "aoe_damage": 1,
			"tint": Color(1, 1, 1), "body_scale": 0.72, "score_value": 18}
	},
	"spitter": {
		"scene": "frog",
		"cfg": {"max_health": 2, "move_speed": 104.0, "croak_cooldown": 1.2,
			"croak_range": 56.0, "aoe_radius": 34.0, "croak_windup": 0.42,
			"tint": Color(0.5, 0.82, 1.0), "body_scale": 0.7, "score_value": 22}
	},
	"boss": {
		"scene": "rat",
		"cfg": {"is_boss": true, "max_health": 96, "move_speed": 96.0,
			"nibble_damage": 3, "nibble_range": 30.0, "nibble_interval": 0.55,
			"dash_chance": 0.9, "dash_windup": 0.5, "dash_speed": 300.0,
			"dash_cooldown_min": 1.0, "dash_cooldown_max": 1.8,
			"knockback_resist": 0.9, "tint": Color(0.85, 0.4, 1.0),
			"body_scale": 2.3, "score_value": 600}
	},
}

const BOSS_NAME := "THE RAT KING"

var waves: Array = []
var wave_index: int = -1
var alive: int = 0
var cleared: bool = false
var boss_active: bool = false
var rng := RandomNumberGenerator.new()
var score: int = 0
var kills: int = 0
var best_record: int = 0
var coins: int = 0
var glare_level: int = 1
var style_meter: float = 0.0
var style_timeout: float = 0.0
var no_glare_chain: int = 0
var glare_uses: int = 0
var profile_saved: bool = false
var tutorial_enabled: bool = false
var tutorial_step: int = 0
var last_earned: int = 0
var result_path: String = ""
var reward_timer: float = 0.0

var wave_label: Label
var enemies_label: Label
var score_label: Label
var combo_label: Label
var reward_label: Label
var result_title: Label
var result_summary: Label
var result_continue: Button
var result_retry: Button
var result_shop: Button
var result_menu: Button
var tutorial_panel: Control
var tutorial_text: Label
var tutorial_button: Button
var shop_panel: Control
var shop_text: Label
var shop_status: Label
var upgrade_button: Button
var boss_panel: Control
var boss_fill: ColorRect
var boss_bar_width: float = 160.0

func _ready() -> void:
	get_tree().paused = false
	rng.randomize()
	_load_profile()
	tutorial_enabled = bool(get_tree().get_meta("tutorial_enabled", false))
	get_tree().set_meta("tutorial_enabled", false)
	banner.modulate.a = 0.0
	_build_result_panel()
	_build_hud()
	_build_boss_bar()
	_build_shop_panel()
	_build_tutorial_panel()
	var cat := get_tree().get_first_node_in_group("player")
	if cat != null:
		if cat.has_signal("died"):
			cat.died.connect(_on_cat_died)
		if cat.has_signal("style_event"):
			cat.style_event.connect(_on_style_event)
	_build_waves()
	_next_wave()
	if tutorial_enabled:
		_show_tutorial_step()

func _process(delta: float) -> void:
	if style_timeout > 0.0:
		style_timeout -= delta
	else:
		style_meter = max(style_meter - 12.0 * delta, 0.0)
	if reward_timer > 0.0:
		reward_timer -= delta
		reward_label.modulate.a = clamp(reward_timer, 0.0, 1.0)
	else:
		reward_label.modulate.a = 0.0
	_update_boss_bar()
	_refresh_hud()

func _build_waves() -> void:
	# Level 1: clear 3 waves to advance. Level 2: 5 waves, then the boss.
	if level_id == 1:
		if tutorial_enabled:
			waves = [
				[["rat", 3]],
				[["rat", 4], ["scurrier", 3]],
				[["rat", 4], ["scurrier", 4], ["frog", 1]],
			]
		else:
			waves = [
				[["rat", 5]],
				[["rat", 5], ["scurrier", 4]],
				[["rat", 4], ["scurrier", 5], ["frog", 2]],
			]
	else:
		waves = [
			[["scurrier", 8], ["frog", 2]],
			[["rat", 6], ["brute", 1], ["frog", 2]],
			[["scurrier", 8], ["spitter", 3]],
			[["rat", 6], ["brute", 2], ["spitter", 2]],
			[["scurrier", 10], ["brute", 2], ["frog", 3]],
			[["boss", 1], ["scurrier", 4]],
		]

func _is_boss_wave(index: int) -> bool:
	if index < 0 or index >= waves.size():
		return false
	for entry in waves[index]:
		if String(entry[0]) == "boss":
			return true
	return false

func _next_wave() -> void:
	if cleared:
		return
	wave_index += 1
	if wave_index >= waves.size():
		_level_cleared()
		return
	if _is_boss_wave(wave_index):
		boss_active = true
		_show_banner(BOSS_NAME)
		_set_reward("Final boss. End it in style.")
	else:
		_show_banner("WAVE %d" % (wave_index + 1))
		_set_reward("Rank high. Cash out harder.")
	for entry in waves[wave_index]:
		var key := String(entry[0])
		var count := int(entry[1])
		for i in count:
			_spawn(key)

func _spawn(key: String) -> void:
	if not ROSTER.has(key):
		return
	var data: Dictionary = ROSTER[key]
	var scene: PackedScene = rat_scene if String(data["scene"]) == "rat" else frog_scene
	if scene == null:
		return
	var e := scene.instantiate()
	if e.has_method("configure"):
		e.configure(data["cfg"])
	e.position = _spawn_point()
	add_child(e)
	alive += 1
	if e.has_signal("died"):
		if bool(data["cfg"].get("is_boss", false)):
			e.died.connect(_on_boss_died)
		else:
			e.died.connect(_on_enemy_died.bind(e))

func _spawn_point() -> Vector2:
	var cat := get_tree().get_first_node_in_group("player")
	var cat_pos: Vector2 = cat.global_position if cat != null else Vector2(128, 72)
	var min_pos := Vector2(30, 28)
	var max_pos := Vector2(226, 116)
	for i in 24:
		var p := Vector2(rng.randf_range(min_pos.x, max_pos.x), rng.randf_range(min_pos.y, max_pos.y))
		if p.distance_to(cat_pos) > 58.0:
			return p
	return Vector2(rng.randf_range(min_pos.x, max_pos.x), rng.randf_range(min_pos.y, max_pos.y))

func _on_enemy_died(enemy: Node) -> void:
	alive -= 1
	kills += 1
	var value: int = 12
	if enemy != null and is_instance_valid(enemy):
		value = int(enemy.get("score_value"))
	score += value + wave_index * 4
	_on_style_event("enemy_down", 14)
	if alive <= 0 and not cleared and not boss_active:
		_award_wave_clear()
		call_deferred("_next_wave")

func _on_boss_died() -> void:
	if cleared:
		return
	boss_active = false
	kills += 1
	score += 600
	style_meter += 40.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e != null and not e.is_in_group("boss"):
			e.queue_free()
	_level_cleared()

func _award_wave_clear() -> void:
	var bonus: int = 28 + wave_index * 14 + _rank_bonus()
	score += bonus
	style_meter += 16.0
	no_glare_chain += 1
	_set_reward("Wave clear +%d  Rank %s" % [bonus, _style_rank()])

func _level_cleared() -> void:
	cleared = true
	var final := next_level_path == ""
	_finish_run("VICTORY!" if final else "LEVEL CLEAR", true)

func _on_cat_died() -> void:
	_finish_run("YOU GOT CLIPPED", false)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().paused = false
		get_tree().reload_current_scene()

func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _continue() -> void:
	get_tree().paused = false
	if result_path != "":
		get_tree().change_scene_to_file(result_path)
	else:
		get_tree().change_scene_to_file("res://scenes/level1.tscn")

func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _show_banner(text: String) -> void:
	banner.text = text
	banner.modulate.a = 1.0
	create_tween().tween_property(banner, "modulate:a", 0.0, 1.4)

func _on_style_event(kind: String, amount: int) -> void:
	if amount < 0:
		if kind == "glare":
			glare_uses += 1
		no_glare_chain = 0
		style_meter = max(style_meter + amount, 0.0)
		style_timeout = 1.0
		if kind == "glare":
			_set_reward("Glare saved you. Style taxed.")
		return
	if kind == "paw_hit" or kind == "paw_kill" or kind == "dash" or kind == "enemy_down":
		no_glare_chain += 1
	var multiplier: float = 1.0 + mini(no_glare_chain, 24) * 0.06
	style_meter += amount * multiplier
	style_timeout = 3.5
	if kind != "dash":
		var scored: int = maxi(1, int(amount * multiplier * 0.8))
		score += scored
		if kind == "paw_kill":
			_set_reward("Clean kill +%d  Chain x%d" % [scored, no_glare_chain])

func _style_rank() -> String:
	if style_meter >= 360.0:
		return "SSS"
	if style_meter >= 260.0:
		return "SS"
	if style_meter >= 175.0:
		return "S"
	if style_meter >= 105.0:
		return "A"
	if style_meter >= 55.0:
		return "B"
	if style_meter >= 20.0:
		return "C"
	return "D"

func _rank_bonus() -> int:
	var rank := _style_rank()
	if rank == "SSS":
		return 90
	if rank == "SS":
		return 70
	if rank == "S":
		return 52
	if rank == "A":
		return 34
	if rank == "B":
		return 20
	if rank == "C":
		return 10
	return 0

func _rank_coin_multiplier() -> float:
	var rank := _style_rank()
	if rank == "SSS":
		return 1.25
	if rank == "SS":
		return 1.05
	if rank == "S":
		return 0.85
	if rank == "A":
		return 0.62
	if rank == "B":
		return 0.45
	if rank == "C":
		return 0.3
	return 0.18

func _build_hud() -> void:
	wave_label = _hud_label(Vector2(150, 6), Vector2(100, 12), Color(0.95, 0.92, 0.7, 1.0), 10, HORIZONTAL_ALIGNMENT_RIGHT)
	enemies_label = _hud_label(Vector2(150, 19), Vector2(100, 10), Color(1.0, 0.62, 0.55, 1.0), 9, HORIZONTAL_ALIGNMENT_RIGHT)
	combo_label = _hud_label(Vector2(6, 118), Vector2(140, 10), Color(1.0, 0.82, 0.25, 1.0), 9, HORIZONTAL_ALIGNMENT_LEFT)
	score_label = _hud_label(Vector2(6, 130), Vector2(200, 10), Color(0.85, 0.9, 1.0, 1.0), 8, HORIZONTAL_ALIGNMENT_LEFT)
	reward_label = _hud_label(Vector2(28, 98), Vector2(200, 12), Color(0.5, 1.0, 0.85, 1.0), 8, HORIZONTAL_ALIGNMENT_CENTER)
	reward_label.modulate.a = 0.0
	_refresh_hud()

func _hud_label(pos: Vector2, box: Vector2, color: Color, font_size: int, align: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = box
	label.custom_minimum_size = box
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = align
	$UI.add_child(label)
	return label

func _normal_wave_count() -> int:
	var count := waves.size()
	if count > 0 and _is_boss_wave(count - 1):
		count -= 1
	return count

func _refresh_hud() -> void:
	if wave_label == null:
		return
	var boss_shown: bool = boss_panel != null and boss_panel.visible
	if boss_shown:
		wave_label.text = ""
		enemies_label.text = ""
	else:
		wave_label.text = "WAVE %d / %d" % [clampi(wave_index + 1, 1, _normal_wave_count()), _normal_wave_count()]
		enemies_label.text = "LEFT %d" % max(alive, 0)
	score_label.text = "SCORE %d   KILLS %d   COINS %d" % [score, kills, coins]
	var rank := _style_rank()
	if no_glare_chain > 1:
		combo_label.text = "STYLE %s   COMBO x%d" % [rank, no_glare_chain]
	else:
		combo_label.text = "STYLE %s" % rank
	combo_label.add_theme_color_override("font_color", _rank_color(rank))

func _rank_color(rank: String) -> Color:
	if rank == "SSS":
		return Color(1.0, 0.35, 0.95, 1.0)
	if rank == "SS":
		return Color(0.75, 0.5, 1.0, 1.0)
	if rank == "S":
		return Color(0.45, 0.85, 1.0, 1.0)
	if rank == "A":
		return Color(0.5, 1.0, 0.45, 1.0)
	if rank == "B":
		return Color(1.0, 0.88, 0.35, 1.0)
	return Color(0.86, 0.86, 0.86, 1.0)

func _set_reward(text: String) -> void:
	if reward_label == null:
		return
	reward_label.text = text
	reward_timer = 1.8
	reward_label.modulate.a = 1.0

func _build_boss_bar() -> void:
	boss_panel = Control.new()
	boss_panel.name = "BossBar"
	boss_panel.visible = false
	boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(boss_panel)
	var name_label := Label.new()
	name_label.position = Vector2(48, 3)
	name_label.size = Vector2(160, 10)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 8)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.55, 1.0, 1.0))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.text = BOSS_NAME
	boss_panel.add_child(name_label)
	var frame := ColorRect.new()
	frame.position = Vector2(48, 13)
	frame.size = Vector2(boss_bar_width, 6)
	frame.color = Color(0.1, 0.02, 0.08, 0.9)
	boss_panel.add_child(frame)
	boss_fill = ColorRect.new()
	boss_fill.position = Vector2(49, 14)
	boss_fill.size = Vector2(boss_bar_width - 2.0, 4)
	boss_fill.color = Color(0.95, 0.2, 0.55, 1.0)
	boss_panel.add_child(boss_fill)

func _update_boss_bar() -> void:
	if boss_panel == null:
		return
	var boss := get_tree().get_first_node_in_group("boss")
	if boss == null or not is_instance_valid(boss):
		boss_panel.visible = false
		return
	var mh: float = maxf(1.0, float(boss.get("max_health")))
	var hp: float = clampf(float(boss.get("health")), 0.0, mh)
	boss_panel.visible = true
	boss_fill.size = Vector2((boss_bar_width - 2.0) * (hp / mh), 4)

func _build_result_panel() -> void:
	for child in game_over.get_children():
		game_over.remove_child(child)
		child.queue_free()
	game_over.visible = false
	game_over.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.76)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over.add_child(dim)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over.add_child(center)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(216, 116)
	box.add_theme_constant_override("separation", 2)
	center.add_child(box)
	result_title = Label.new()
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_title.add_theme_font_size_override("font_size", 18)
	result_title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35, 1.0))
	box.add_child(result_title)
	result_summary = Label.new()
	result_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_summary.custom_minimum_size = Vector2(216, 34)
	result_summary.add_theme_font_size_override("font_size", 8)
	result_summary.add_theme_color_override("font_color", Color(0.93, 0.9, 0.78, 1.0))
	box.add_child(result_summary)
	result_continue = _make_button("CONTINUE")
	result_continue.pressed.connect(_continue)
	box.add_child(result_continue)
	result_retry = _make_button("RETRY")
	result_retry.pressed.connect(_restart)
	box.add_child(result_retry)
	result_shop = _make_button("SHOP")
	result_shop.pressed.connect(_open_shop)
	box.add_child(result_shop)
	result_menu = _make_button("MENU")
	result_menu.pressed.connect(_to_menu)
	box.add_child(result_menu)

func _finish_run(title: String, success: bool) -> void:
	_bank_run()
	result_title.text = title
	result_path = next_level_path if success and next_level_path != "" else "res://scenes/level1.tscn"
	result_continue.text = "NEXT LEVEL" if success and next_level_path != "" else "PLAY AGAIN"
	result_continue.visible = true
	result_summary.text = _result_summary(success)
	game_over.visible = true
	get_tree().paused = true
	result_continue.grab_focus()

func _result_summary(success: bool) -> String:
	var rank := _style_rank()
	var no_glare_bonus: int = 75 if glare_uses == 0 else maxi(0, 45 - glare_uses * 12)
	var clear_bonus: int = 120 if success else 0
	return "Rank %s   Score %d   Kills %d\nNo-glare bonus %d   Clear bonus %d\nCoins earned +%d   Total %d" % [rank, score, kills, no_glare_bonus, clear_bonus, last_earned, coins]

func _build_shop_panel() -> void:
	shop_panel = Control.new()
	shop_panel.name = "ShopPanel"
	shop_panel.visible = false
	shop_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	shop_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_panel.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(216, 112)
	box.add_theme_constant_override("separation", 2)
	center.add_child(box)
	shop_text = Label.new()
	shop_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shop_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_text.custom_minimum_size = Vector2(216, 38)
	shop_text.add_theme_font_size_override("font_size", 9)
	shop_text.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72, 1.0))
	box.add_child(shop_text)
	shop_status = Label.new()
	shop_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_status.custom_minimum_size = Vector2(216, 12)
	shop_status.add_theme_font_size_override("font_size", 8)
	shop_status.add_theme_color_override("font_color", Color(0.48, 0.95, 1.0, 1.0))
	box.add_child(shop_status)
	upgrade_button = _make_button("UPGRADE GLARE")
	upgrade_button.pressed.connect(_upgrade_glare)
	box.add_child(upgrade_button)
	var retry_button := _make_button("RETRY RUN")
	retry_button.pressed.connect(_restart)
	box.add_child(retry_button)
	var menu_button := _make_button("MAIN MENU")
	menu_button.pressed.connect(_to_menu)
	box.add_child(menu_button)
	var back_button := _make_button("BACK")
	back_button.pressed.connect(_close_shop)
	box.add_child(back_button)
	$UI.add_child(shop_panel)
	_refresh_shop()

func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(146, 14)
	button.add_theme_font_size_override("font_size", 9)
	return button

func _open_shop() -> void:
	_refresh_shop()
	shop_panel.visible = true
	upgrade_button.grab_focus()

func _close_shop() -> void:
	shop_panel.visible = false
	if game_over.visible:
		result_shop.grab_focus()

func _upgrade_glare() -> void:
	var costs := [0, 60, 140]
	if glare_level >= 3:
		_refresh_shop("Glare is maxed.")
		return
	var next_cost: int = costs[glare_level]
	if coins < next_cost:
		_refresh_shop("Need %d more coins." % (next_cost - coins))
		return
	coins -= next_cost
	glare_level += 1
	_save_profile_values()
	_refresh_shop("Upgrade bought. Next run starts stronger.")
	if game_over.visible:
		result_summary.text = _result_summary(cleared)

func _refresh_shop(message: String = "") -> void:
	var stuns := [0.35, 0.6, 0.85]
	var costs := [0, 60, 140]
	var text := "SHOP\nCoins: %d   Glare L%d %.2fs" % [coins, glare_level, stuns[glare_level - 1]]
	if glare_level < 3:
		text += "\nNext %.2fs costs %d" % [stuns[glare_level], costs[glare_level]]
		upgrade_button.text = "UPGRADE GLARE"
		upgrade_button.disabled = false
	else:
		text += "\nGlare maxed."
		upgrade_button.text = "MAXED"
		upgrade_button.disabled = true
	shop_text.text = text
	shop_status.text = message
	_refresh_hud()

func _build_tutorial_panel() -> void:
	tutorial_panel = Control.new()
	tutorial_panel.name = "TutorialPanel"
	tutorial_panel.visible = false
	tutorial_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	tutorial_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	tutorial_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	tutorial_panel.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(218, 100)
	box.add_theme_constant_override("separation", 2)
	center.add_child(box)
	tutorial_text = Label.new()
	tutorial_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_text.custom_minimum_size = Vector2(218, 62)
	tutorial_text.add_theme_font_size_override("font_size", 9)
	tutorial_text.add_theme_color_override("font_color", Color(1.0, 0.93, 0.7, 1.0))
	box.add_child(tutorial_text)
	tutorial_button = _make_button("NEXT")
	tutorial_button.pressed.connect(_advance_tutorial)
	box.add_child(tutorial_button)
	$UI.add_child(tutorial_panel)

func _show_tutorial_step() -> void:
	var steps := [
		"Time stop. The swarm waits while you learn. Move with WASD or arrows and aim with the mouse.",
		"Left click swipes the paw. Hits and kills build your STYLE rank, score, and coins fast.",
		"Space dashes through danger and dodges hits. Chain kills without panicking to climb the ranks.",
		"Right click glares to stun a pack, but glare drops your style and trims the payout. Now go hunt.",
	]
	tutorial_step = clampi(tutorial_step, 0, steps.size() - 1)
	tutorial_text.text = steps[tutorial_step]
	tutorial_button.text = "FIGHT" if tutorial_step == steps.size() - 1 else "NEXT"
	tutorial_panel.visible = true
	get_tree().paused = true

func _advance_tutorial() -> void:
	tutorial_step += 1
	if tutorial_step >= 4:
		tutorial_panel.visible = false
		get_tree().paused = false
		return
	_show_tutorial_step()

func _load_profile() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://macatre_profile.cfg")
	if err == OK:
		best_record = int(config.get_value("records", "best_score", 0))
		coins = int(config.get_value("shop", "coins", 0))
		glare_level = int(config.get_value("shop", "glare_level", 1))
	glare_level = clampi(glare_level, 1, 3)

func _bank_run() -> void:
	if profile_saved:
		return
	profile_saved = true
	var no_glare_bonus: int = 75 if glare_uses == 0 else maxi(0, 45 - glare_uses * 12)
	var clear_bonus: int = 120 if cleared else 0
	last_earned = maxi(0, int(score * 0.65) + int(style_meter * _rank_coin_multiplier()) + no_glare_bonus + clear_bonus)
	coins += last_earned
	best_record = max(best_record, score)
	_save_profile_values()
	_refresh_hud()

func _save_profile_values() -> void:
	var config := ConfigFile.new()
	config.load("user://macatre_profile.cfg")
	config.set_value("records", "best_score", best_record)
	config.set_value("shop", "coins", coins)
	config.set_value("shop", "glare_level", glare_level)
	config.set_value("shop", "last_score", score)
	config.set_value("shop", "last_style", int(style_meter))
	config.set_value("shop", "last_earned", last_earned)
	config.set_value("shop", "last_rank", _style_rank())
	config.save("user://macatre_profile.cfg")
