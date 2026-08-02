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
var difficulty_panel: Control
var difficulty: int = 1
var pending_endless: bool = false

# Mirrors level.gd's table - only the parts the menu needs to describe a mode.
const DIFFICULTIES := [
	{"name": "EASY", "blurb": "Slower foes, long tells,\ngenerous hearts, +3 HP.",
		"colour": Color(0.5, 1.0, 0.62)},
	{"name": "MEDIUM", "blurb": "The fight as intended.", "colour": Color(1.0, 0.84, 0.35)},
	{"name": "HELL", "blurb": "Fast and brutal, few hearts,\n-2 HP. Pays 35% more.",
		"colour": Color(1.0, 0.3, 0.35)},
]

const MAIN_MENU: AudioStream = preload("uid://b2vea5dv5llnp")

func _ready() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	_load_profile()
	_scale_menu()
	_ensure_stats()
	_ensure_shop_panel()
	_ensure_difficulty_panel()
	_apply_pixel_font(self)
	$Center/Box/Play.pressed.connect(_on_play)
	$Center/Box/Tutorial.pressed.connect(_on_tutorial)
	$Center/Box/Shop.pressed.connect(_toggle_shop)
	$Center/Box/Quit.pressed.connect(_on_quit)
	_ensure_endless_button()
	$Center/Box/Play.grab_focus()
	SoundManager.set_music_volume(0.5)
	# Menu music has to loop; the import flag says so too, this guards a re-import.
	var track: AudioStream = MAIN_MENU
	if track is AudioStreamMP3:
		(track as AudioStreamMP3).loop = true
	SoundManager.play_music(track, 0, "Music")

func _apply_pixel_font(node: Node) -> void:
	if node is Control:
		var control := node as Control
		control.add_theme_font_override("font", UI_FONT)
	for child in node.get_children():
		_apply_pixel_font(child)

# PLAY and ENDLESS both route through the difficulty picker; TUTORIAL always
# starts on EASY, since someone who picked the tutorial is here to learn the
# buttons, not to be tested on them.
func _on_play() -> void:
	pending_endless = false
	_open_difficulty()

func _on_endless() -> void:
	pending_endless = true
	_open_difficulty()

func _on_tutorial() -> void:
	_launch(0, true, false)

func _launch(mode: int, tutorial: bool, endless_mode: bool) -> void:
	difficulty = clampi(mode, 0, DIFFICULTIES.size() - 1)
	_save_profile()
	get_tree().set_meta("difficulty", difficulty)
	get_tree().set_meta("tutorial_enabled", tutorial)
	get_tree().set_meta("endless_enabled", endless_mode)
	if last_score == 0:
		get_tree().change_scene_to_file("res://scenes/cutscene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/level1.tscn")

func _on_quit() -> void:
	get_tree().quit()

# Endless lives right under PLAY. Built in code so we don't have to touch the
# scene; styled to match the other menu buttons.
func _ensure_endless_button() -> void:
	var box: VBoxContainer = $Center/Box
	if box.has_node("Endless"):
		return
	var button := _make_button("ENDLESS")
	button.name = "Endless"
	button.pressed.connect(_on_endless)
	box.add_child(button)
	box.move_child(button, $Center/Box/Play.get_index() + 1)

func _toggle_shop() -> void:
	shop_panel.visible = not shop_panel.visible
	_refresh_shop()
	if shop_panel.visible:
		upgrade_button.grab_focus()
	else:
		$Center/Box/Play.grab_focus()

func _upgrade_glare() -> void:
	var costs := [0, 150, 340]
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
		difficulty = int(config.get_value("options", "difficulty", 1))
	glare_level = clampi(glare_level, 1, 3)
	difficulty = clampi(difficulty, 0, DIFFICULTIES.size() - 1)

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
	config.set_value("options", "difficulty", difficulty)
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
		button.custom_minimum_size = Vector2(184, 16)
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
		stats_label.custom_minimum_size = Vector2(220, 24)
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
	box.custom_minimum_size = Vector2(266, 142)
	box.add_theme_constant_override("separation", 2)
	center.add_child(box)
	shop_text = Label.new()
	shop_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shop_text.custom_minimum_size = Vector2(266, 50)
	shop_text.add_theme_font_size_override("font_size", 9)
	shop_text.add_theme_color_override("font_color", Color(1, 0.93, 0.72, 1))
	box.add_child(shop_text)
	shop_status = Label.new()
	shop_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_status.custom_minimum_size = Vector2(266, 14)
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

func _ensure_difficulty_panel() -> void:
	difficulty_panel = Control.new()
	difficulty_panel.name = "DifficultyPanel"
	difficulty_panel.visible = false
	difficulty_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	difficulty_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	difficulty_panel.add_child(center)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _panel_box(
		Color(0.05, 0.06, 0.1, 0.97), Color(1.0, 0.84, 0.35, 0.9)))
	center.add_child(frame)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(244, 132)
	box.add_theme_constant_override("separation", 2)
	frame.add_child(box)
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35, 1))
	title.text = "PICK YOUR PAIN"
	box.add_child(title)
	for i in DIFFICULTIES.size():
		var mode: Dictionary = DIFFICULTIES[i]
		var button := _make_button(String(mode["name"]))
		button.add_theme_color_override("font_color", mode["colour"])
		button.pressed.connect(_on_difficulty_chosen.bind(i))
		button.focus_entered.connect(_on_difficulty_focused.bind(i))
		button.mouse_entered.connect(_on_difficulty_focused.bind(i))
		box.add_child(button)
	var blurb := Label.new()
	blurb.name = "Blurb"
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(240, 24)
	blurb.add_theme_font_size_override("font_size", 7)
	blurb.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 1))
	box.add_child(blurb)
	var back := _make_button("BACK")
	back.pressed.connect(_close_difficulty)
	box.add_child(back)
	add_child(difficulty_panel)

func _open_difficulty() -> void:
	difficulty_panel.visible = true
	_on_difficulty_focused(difficulty)
	var box: VBoxContainer = difficulty_panel.get_child(1).get_child(0).get_child(0)
	# Start on whichever mode was last played.
	box.get_child(1 + clampi(difficulty, 0, DIFFICULTIES.size() - 1)).grab_focus()

func _close_difficulty() -> void:
	difficulty_panel.visible = false
	$Center/Box/Play.grab_focus()

func _on_difficulty_focused(index: int) -> void:
	var blurb: Label = difficulty_panel.find_child("Blurb", true, false)
	if blurb != null:
		blurb.text = String(DIFFICULTIES[index]["blurb"])
		blurb.add_theme_color_override("font_color", DIFFICULTIES[index]["colour"])

func _on_difficulty_chosen(index: int) -> void:
	_launch(index, false, pending_endless)

func _panel_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(1)
	s.border_color = border
	s.set_corner_radius_all(3)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 3
	s.content_margin_left = 5.0
	s.content_margin_right = 5.0
	s.content_margin_top = 4.0
	s.content_margin_bottom = 4.0
	return s

func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(184, 16)
	button.add_theme_font_size_override("font_size", 9)
	_style_button(button)
	return button

func _refresh_shop(message: String = "") -> void:
	var stuns := [0.35, 0.6, 0.85]
	var costs := [0, 150, 340]
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
