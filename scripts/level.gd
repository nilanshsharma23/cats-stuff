extends Node2D

@export var level_id: int = 1
@export var next_level_path: String = ""
@export var rat_scene: PackedScene
@export var frog_scene: PackedScene

@onready var game_over: Control = $UI/GameOver
@onready var banner: Label = $UI/Banner

var waves: Array = []
var wave_index: int = -1
var alive: int = 0
var cleared: bool = false
var rng := RandomNumberGenerator.new()
var score: int = 0
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
var style_label: Label
var record_label: Label
var score_label: Label
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

func _ready() -> void:
	get_tree().paused = false
	rng.randomize()
	_load_profile()
	tutorial_enabled = bool(get_tree().get_meta("tutorial_enabled", false))
	get_tree().set_meta("tutorial_enabled", false)
	banner.modulate.a = 0.0
	_build_result_panel()
	_build_hud()
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
	_refresh_hud()

func _build_waves() -> void:
	if level_id == 1:
		if tutorial_enabled:
			waves = [[ ["rat", 1, false] ], [ ["rat", 3, false] ], [ ["rat", 5, true], ["frog", 1, false] ]]
		else:
			waves = [[ ["rat", 3, false] ], [ ["rat", 5, false] ], [ ["rat", 6, true], ["frog", 1, false] ]]
	else:
		waves = [[ ["rat", 6, true], ["frog", 1, false] ], [ ["rat", 8, true], ["frog", 2, false] ], [ ["rat", 10, true], ["frog", 3, false] ], [ ["rat", 12, true], ["frog", 4, false] ]]

func _next_wave() -> void:
	if cleared:
		return
	wave_index += 1
	if wave_index >= waves.size():
		_level_cleared()
		return
	_show_banner("WAVE %d" % (wave_index + 1))
	_set_reward("Rank high. Cash out harder.")
	for entry in waves[wave_index]:
		var type := String(entry[0])
		var count := int(entry[1])
		var pins := bool(entry[2]) if entry.size() > 2 else false
		for i in count:
			_spawn(type, pins)

func _spawn(type: String, pins: bool) -> void:
	var scene: PackedScene = rat_scene if type == "rat" else frog_scene
	if scene == null:
		return
	var e := scene.instantiate()
	e.position = _spawn_point()
	if type == "rat":
		e.set("roots_player", pins)
	add_child(e)
	alive += 1
	if e.has_signal("died"):
		e.died.connect(_on_enemy_died)

func _spawn_point() -> Vector2:
	var cat := get_tree().get_first_node_in_group("player")
	var cat_pos: Vector2 = cat.global_position if cat != null else Vector2(128, 72)
	var min_pos := Vector2(30, 28)
	var max_pos := Vector2(226, 116)
	for i in 24:
		var p := Vector2(rng.randf_range(min_pos.x, max_pos.x), rng.randf_range(min_pos.y, max_pos.y))
		if p.distance_to(cat_pos) > 52.0:
			return p
	return Vector2(rng.randf_range(min_pos.x, max_pos.x), rng.randf_range(min_pos.y, max_pos.y))

func _on_enemy_died() -> void:
	alive -= 1
	score += 12 + wave_index * 5
	_on_style_event("enemy_down", 14)
	if alive <= 0 and not cleared:
		_award_wave_clear()
		call_deferred("_next_wave")

func _award_wave_clear() -> void:
	var bonus: int = 28 + wave_index * 14 + _rank_bonus()
	score += bonus
	style_meter += 16.0
	no_glare_chain += 1
	_set_reward("Wave clear +%d  Rank %s" % [bonus, _style_rank()])

func _level_cleared() -> void:
	cleared = true
	_finish_run("LEVEL CLEAR", true)

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
	create_tween().tween_property(banner, "modulate:a", 0.0, 1.2)

func _on_style_event(kind: String, amount: int) -> void:
	if amount < 0:
		if kind == "glare":
			glare_uses += 1
		no_glare_chain = 0
		style_meter = max(style_meter + amount, 0.0)
		style_timeout = 1.0
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
	var box := VBoxContainer.new()
	box.name = "RunHUD"
	box.position = Vector2(7, 43)
	box.custom_minimum_size = Vector2(124, 42)
	box.add_theme_constant_override("separation", 0)
	$UI.add_child(box)
	style_label = _make_label("Style", Color(1.0, 0.82, 0.25, 1.0), 13)
	score_label = _make_label("Score", Color(0.85, 0.9, 1.0, 1.0), 8)
	record_label = _make_label("Record", Color(0.72, 0.78, 0.9, 1.0), 8)
	box.add_child(style_label)
	box.add_child(score_label)
	box.add_child(record_label)
	reward_label = Label.new()
	reward_label.name = "Reward"
	reward_label.position = Vector2(7, 88)
	reward_label.custom_minimum_size = Vector2(190, 16)
	reward_label.add_theme_font_size_override("font_size", 8)
	reward_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.85, 1.0))
	reward_label.modulate.a = 0.0
	$UI.add_child(reward_label)
	_refresh_hud()

func _make_label(node_name: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _refresh_hud() -> void:
	if style_label == null:
		return
	var rank := _style_rank()
	style_label.text = "STYLE %s  %.0f" % [rank, style_meter]
	score_label.text = "SCORE %d  CHAIN %d" % [score, no_glare_chain]
	record_label.text = "BEST %d  COINS %d" % [best_record, coins]
	style_label.add_theme_color_override("font_color", _rank_color(rank))

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
	result_continue.visible = success
	result_summary.text = _result_summary(success)
	game_over.visible = true
	get_tree().paused = true
	if result_continue.visible:
		result_continue.grab_focus()
	else:
		result_retry.grab_focus()

func _result_summary(success: bool) -> String:
	var rank := _style_rank()
	var no_glare_bonus: int = 75 if glare_uses == 0 else maxi(0, 45 - glare_uses * 12)
	var clear_bonus: int = 120 if success else 0
	return "Rank %s  Score %d  Style %.0f\nNo glare bonus %d  Clear bonus %d\nCoins earned +%d  Total %d" % [rank, score, style_meter, no_glare_bonus, clear_bonus, last_earned, coins]

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
	var stuns := [0.2, 0.5, 0.75]
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
		"Time stop. The rat is real, but it waits while you learn. Move with WASD or arrows and aim with the mouse.",
		"Left click swipes. Paw hits and kills build rank, score, and coins much faster than panic glare.",
		"Space dashes through danger. Right click glares to stun, but glare cuts style and trims your bonus.",
		"Pinned by a rat means no movement or attacks until the gold sparkles end. Read the bite circle and dash lane."
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
