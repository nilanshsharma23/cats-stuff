extends Control

const UI_FONT: FontFile = preload("res://fonts/Pixellari.ttf")

var coins: int = 0
var glare_level: int = 1
var best_score: int = 0
var last_score: int = 0
var last_style: int = 0
var last_earned: int = 0
var last_rank: String = "D"
var stats_label: Label
var shop_panel: Control
var shop_text: Label
var upgrade_button: Button
var shop_status: Label

func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	_load_profile()
	_scale_menu()
	_ensure_stats()
	_ensure_shop_panel()
	_apply_pixel_font(self)
	$Center/Box/Play.pressed.connect(_on_play)
	$Center/Box/Tutorial.pressed.connect(_on_tutorial)
	$Center/Box/Shop.pressed.connect(_toggle_shop)
	$Center/Box/Quit.pressed.connect(_on_quit)
	$Center/Box/Play.grab_focus()

func _apply_pixel_font(node: Node) -> void:
	if node is Control:
		var control := node as Control
		control.add_theme_font_override("font", UI_FONT)
	for child in node.get_children():
		_apply_pixel_font(child)

func _on_play() -> void:
	get_tree().set_meta("tutorial_enabled", false)
	get_tree().change_scene_to_file("res://scenes/level1.tscn")

func _on_tutorial() -> void:
	get_tree().set_meta("tutorial_enabled", true)
	get_tree().change_scene_to_file("res://scenes/level1.tscn")

func _on_quit() -> void:
	get_tree().quit()

func _toggle_shop() -> void:
	shop_panel.visible = not shop_panel.visible
	_refresh_shop()
	if shop_panel.visible:
		upgrade_button.grab_focus()
	else:
		$Center/Box/Play.grab_focus()

func _upgrade_glare() -> void:
	var costs := [0, 60, 140]
	if glare_level >= 3:
		_refresh_shop("Glare is already maxed.")
		return
	var next_cost: int = costs[glare_level]
	if coins < next_cost:
		_refresh_shop("Need %d more coins." % (next_cost - coins))
		return
	coins -= next_cost
	glare_level += 1
	_save_profile()
	_refresh_shop("Glare upgraded. Go make them regret entering the room.")

func _load_profile() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://macatre_profile.cfg")
	if err == OK:
		coins = int(config.get_value("shop", "coins", 0))
		glare_level = int(config.get_value("shop", "glare_level", 1))
		best_score = int(config.get_value("records", "best_score", 0))
		last_score = int(config.get_value("shop", "last_score", 0))
		last_style = int(config.get_value("shop", "last_style", 0))
		last_earned = int(config.get_value("shop", "last_earned", 0))
		last_rank = String(config.get_value("shop", "last_rank", "D"))
	glare_level = clampi(glare_level, 1, 3)

func _save_profile() -> void:
	var config := ConfigFile.new()
	config.load("user://macatre_profile.cfg")
	config.set_value("shop", "coins", coins)
	config.set_value("shop", "glare_level", glare_level)
	config.set_value("records", "best_score", best_score)
	config.set_value("shop", "last_score", last_score)
	config.set_value("shop", "last_style", last_style)
	config.set_value("shop", "last_earned", last_earned)
	config.set_value("shop", "last_rank", last_rank)
	config.save("user://macatre_profile.cfg")

func _scale_menu() -> void:
	var box: VBoxContainer = $Center/Box
	box.add_theme_constant_override("separation", 2)
	var title: Label = $Center/Box/Title
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.86, 0.22, 0.28, 1))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 4)
	var sub: Label = $Center/Box/Sub
	sub.add_theme_font_size_override("font_size", 7)
	sub.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68, 1))
	if box.has_node("Spacer"):
		box.get_node("Spacer").custom_minimum_size = Vector2(0, 1)
	for name in ["Play", "Tutorial", "Shop", "Quit"]:
		var button: Button = box.get_node(name)
		button.custom_minimum_size = Vector2(150, 13)
		button.add_theme_font_size_override("font_size", 9)
		_style_button(button)

func _style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _button_box(Color(0.13, 0.12, 0.16, 1), Color(0.32, 0.3, 0.36, 1)))
	button.add_theme_stylebox_override("hover", _button_box(Color(0.2, 0.15, 0.19, 1), Color(0.86, 0.28, 0.34, 1)))
	button.add_theme_stylebox_override("pressed", _button_box(Color(0.1, 0.09, 0.12, 1), Color(0.86, 0.28, 0.34, 1)))
	button.add_theme_stylebox_override("focus", _button_box(Color(0.2, 0.15, 0.19, 1), Color(0.86, 0.28, 0.34, 1)))
	button.add_theme_color_override("font_color", Color(0.92, 0.9, 0.94, 1))
	button.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.96, 1))
	button.add_theme_color_override("font_focus_color", Color(1, 0.95, 0.96, 1))

func _button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(1)
	s.border_color = border
	s.set_corner_radius_all(2)
	s.content_margin_top = 2.0
	s.content_margin_bottom = 2.0
	s.content_margin_left = 4.0
	s.content_margin_right = 4.0
	return s

func _ensure_stats() -> void:
	var box: VBoxContainer = $Center/Box
	if box.has_node("Stats"):
		stats_label = box.get_node("Stats")
	else:
		stats_label = Label.new()
		stats_label.name = "Stats"
		stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stats_label.custom_minimum_size = Vector2(180, 20)
		box.add_child(stats_label)
		box.move_child(stats_label, 3)
	stats_label.add_theme_font_size_override("font_size", 7)
	stats_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.58, 1))
	_refresh_stats()

func _refresh_stats() -> void:
	if stats_label == null:
		return
	stats_label.text = "Coins %d   Best %d\nLast %s  Score %d  +%d" % [coins, best_score, last_rank, last_score, last_earned]

func _ensure_shop_panel() -> void:
	shop_panel = Control.new()
	shop_panel.name = "ShopPanel"
	shop_panel.visible = false
	shop_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	shop_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_panel.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(218, 116)
	box.add_theme_constant_override("separation", 2)
	center.add_child(box)
	shop_text = Label.new()
	shop_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shop_text.custom_minimum_size = Vector2(218, 42)
	shop_text.add_theme_font_size_override("font_size", 9)
	shop_text.add_theme_color_override("font_color", Color(1, 0.93, 0.72, 1))
	box.add_child(shop_text)
	shop_status = Label.new()
	shop_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_status.custom_minimum_size = Vector2(218, 12)
	shop_status.add_theme_font_size_override("font_size", 8)
	shop_status.add_theme_color_override("font_color", Color(0.5, 0.95, 1, 1))
	box.add_child(shop_status)
	upgrade_button = _make_button("UPGRADE GLARE")
	upgrade_button.pressed.connect(_upgrade_glare)
	box.add_child(upgrade_button)
	var play_button := _make_button("PLAY RUN")
	play_button.pressed.connect(_on_play)
	box.add_child(play_button)
	var tutorial_button := _make_button("TUTORIAL")
	tutorial_button.pressed.connect(_on_tutorial)
	box.add_child(tutorial_button)
	var close_button := _make_button("BACK")
	close_button.pressed.connect(_toggle_shop)
	box.add_child(close_button)
	add_child(shop_panel)
	_refresh_shop()

func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(150, 13)
	button.add_theme_font_size_override("font_size", 9)
	_style_button(button)
	return button

func _refresh_shop(message: String = "") -> void:
	var stuns := [0.35, 0.6, 0.85]
	var costs := [0, 60, 140]
	var text := "SHOP\nCoins: %d   Best: %d\nGlare L%d: %.2fs paralyze" % [coins, best_score, glare_level, stuns[glare_level - 1]]
	if glare_level < 3:
		text += "\nNext: %.2fs for %d coins" % [stuns[glare_level], costs[glare_level]]
		upgrade_button.text = "UPGRADE GLARE"
		upgrade_button.disabled = false
	else:
		text += "\nGlare maxed."
		upgrade_button.text = "MAXED"
		upgrade_button.disabled = true
	shop_text.text = text
	shop_status.text = message
	_refresh_stats()
