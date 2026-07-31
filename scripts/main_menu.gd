extends Control

var coins: int = 0
var glare_level: int = 1
var best_score: int = 0
var shop_panel: Control
var shop_text: Label
var upgrade_button: Button

func _ready() -> void:
    _load_profile()
    _ensure_shop_panel()
    $Center/Box/Play.pressed.connect(_on_play)
    $Center/Box/Tutorial.pressed.connect(_on_tutorial)
    $Center/Box/Shop.pressed.connect(_toggle_shop)
    $Center/Box/Quit.pressed.connect(_on_quit)
    $Center/Box/Play.grab_focus()

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
    var costs := [0, 80, 180]
    if glare_level >= 3:
        _refresh_shop()
        return
    var next_cost: int = costs[glare_level]
    if coins < next_cost:
        _refresh_shop("Need %d more coins." % (next_cost - coins))
        return
    coins -= next_cost
    glare_level += 1
    _save_profile()
    _refresh_shop("Glare upgraded.")

func _load_profile() -> void:
    var config := ConfigFile.new()
    var err := config.load("user://macatre_profile.cfg")
    if err == OK:
        coins = int(config.get_value("shop", "coins", 0))
        glare_level = int(config.get_value("shop", "glare_level", 1))
        best_score = int(config.get_value("records", "best_score", 0))
    glare_level = clampi(glare_level, 1, 3)

func _save_profile() -> void:
    var config := ConfigFile.new()
    config.load("user://macatre_profile.cfg")
    config.set_value("shop", "coins", coins)
    config.set_value("shop", "glare_level", glare_level)
    config.set_value("records", "best_score", best_score)
    config.save("user://macatre_profile.cfg")

func _ensure_shop_panel() -> void:
    shop_panel = Control.new()
    shop_panel.name = "ShopPanel"
    shop_panel.visible = false
    shop_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.72)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    shop_panel.add_child(dim)
    var box := VBoxContainer.new()
    box.position = Vector2(28, 26)
    box.size = Vector2(200, 96)
    box.add_theme_constant_override("separation", 7)
    shop_panel.add_child(box)
    shop_text = Label.new()
    shop_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    shop_text.custom_minimum_size = Vector2(200, 58)
    shop_text.add_theme_font_size_override("font_size", 9)
    shop_text.add_theme_color_override("font_color", Color(1, 0.93, 0.74, 1))
    box.add_child(shop_text)
    upgrade_button = Button.new()
    upgrade_button.add_theme_font_size_override("font_size", 10)
    upgrade_button.pressed.connect(_upgrade_glare)
    box.add_child(upgrade_button)
    var close_button := Button.new()
    close_button.text = "BACK"
    close_button.add_theme_font_size_override("font_size", 10)
    close_button.pressed.connect(_toggle_shop)
    box.add_child(close_button)
    add_child(shop_panel)
    _refresh_shop()

func _refresh_shop(message: String = "") -> void:
    var stuns := [0.2, 0.5, 0.75]
    var costs := [0, 80, 180]
    var text := "SHOP\nCoins: %d\nBest: %d\nGlare Level %d: %.2fs paralyze" % [coins, best_score, glare_level, stuns[glare_level - 1]]
    if glare_level < 3:
        text += "\nNext: %.2fs for %d coins" % [stuns[glare_level], costs[glare_level]]
        upgrade_button.text = "UPGRADE GLARE"
        upgrade_button.disabled = false
    else:
        text += "\nGlare maxed."
        upgrade_button.text = "MAXED"
        upgrade_button.disabled = true
    if message != "":
        text += "\n" + message
    shop_text.text = text
