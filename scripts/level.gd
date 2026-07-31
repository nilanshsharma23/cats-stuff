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
var style_meter: float = 0.0
var style_timeout: float = 0.0
var no_glare_chain: int = 0
var glare_uses: int = 0
var profile_saved: bool = false
var tutorial_enabled: bool = false
var tutorial_step: int = 0
var style_label: Label
var record_label: Label
var score_label: Label
var tutorial_panel: Control
var tutorial_text: Label
var tutorial_button: Button

func _ready() -> void:
    get_tree().paused = false
    rng.randomize()
    _load_profile()
    tutorial_enabled = bool(get_tree().get_meta("tutorial_enabled", false))
    get_tree().set_meta("tutorial_enabled", false)
    game_over.visible = false
    banner.modulate.a = 0.0
    _build_hud()
    var cat := get_tree().get_first_node_in_group("player")
    if cat != null:
        if cat.has_signal("died"):
            cat.died.connect(_on_cat_died)
        if cat.has_signal("style_event"):
            cat.style_event.connect(_on_style_event)
    $UI/GameOver/Center/Box/Retry.pressed.connect(_restart)
    $UI/GameOver/Center/Box/Menu.pressed.connect(_to_menu)
    _build_waves()
    _next_wave()
    if tutorial_enabled:
        _show_tutorial_step()

func _process(delta: float) -> void:
    if style_timeout > 0.0:
        style_timeout -= delta
    else:
        style_meter = max(style_meter - 18.0 * delta, 0.0)
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
    score += 10 + wave_index * 4
    _on_style_event("enemy_down", 10)
    if alive <= 0 and not cleared:
        call_deferred("_next_wave")

func _level_cleared() -> void:
    cleared = true
    _bank_run()
    if next_level_path != "":
        _show_banner("LEVEL CLEAR")
        await get_tree().create_timer(1.6).timeout
        get_tree().change_scene_to_file(next_level_path)
    else:
        _show_banner("YOU SURVIVED")
        await get_tree().create_timer(2.6).timeout
        get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_cat_died() -> void:
    _bank_run()
    game_over.visible = true
    $UI/GameOver/Center/Box/Retry.grab_focus()
    get_tree().paused = true

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("restart"):
        get_tree().paused = false
        get_tree().reload_current_scene()

func _restart() -> void:
    get_tree().paused = false
    get_tree().reload_current_scene()

func _to_menu() -> void:
    get_tree().paused = false
    get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _show_banner(text: String) -> void:
    banner.text = text
    banner.modulate.a = 1.0
    create_tween().tween_property(banner, "modulate:a", 0.0, 1.4)

func _on_style_event(kind: String, amount: int) -> void:
    if amount < 0:
        glare_uses += 1 if kind == "glare" else 0
        no_glare_chain = 0
        style_meter = max(style_meter + amount, 0.0)
        style_timeout = 1.0
        return
    if kind == "paw_hit" or kind == "paw_kill" or kind == "dash" or kind == "enemy_down":
        no_glare_chain += 1
    var multiplier: float = 1.0 + mini(no_glare_chain, 18) * 0.055
    style_meter += amount * multiplier
    style_timeout = 3.0

func _style_rank() -> String:
    if style_meter >= 450.0:
        return "SSS"
    if style_meter >= 320.0:
        return "SS"
    if style_meter >= 215.0:
        return "S"
    if style_meter >= 135.0:
        return "A"
    if style_meter >= 75.0:
        return "B"
    if style_meter >= 30.0:
        return "C"
    return "D"

func _build_hud() -> void:
    style_label = _make_label("Style", Vector2(8, 48), Color(1.0, 0.82, 0.25, 1.0), 14)
    score_label = _make_label("Score", Vector2(8, 64), Color(0.85, 0.9, 1.0, 1.0), 9)
    record_label = _make_label("Record", Vector2(8, 76), Color(0.72, 0.78, 0.9, 1.0), 8)
    _build_tutorial_panel()
    _refresh_hud()

func _make_label(node_name: String, pos: Vector2, color: Color, font_size: int) -> Label:
    var label := Label.new()
    label.name = node_name
    label.position = pos
    label.add_theme_color_override("font_color", color)
    label.add_theme_font_size_override("font_size", font_size)
    $UI.add_child(label)
    return label

func _refresh_hud() -> void:
    if style_label == null:
        return
    style_label.text = "STYLE %s  %.0f" % [_style_rank(), style_meter]
    score_label.text = "SCORE %d" % score
    record_label.text = "BEST %d   COINS %d" % [best_record, coins]

func _build_tutorial_panel() -> void:
    tutorial_panel = Control.new()
    tutorial_panel.name = "TutorialPanel"
    tutorial_panel.visible = false
    tutorial_panel.process_mode = Node.PROCESS_MODE_ALWAYS
    tutorial_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    var dim := ColorRect.new()
    dim.color = Color(0.0, 0.0, 0.0, 0.68)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    tutorial_panel.add_child(dim)
    var box := VBoxContainer.new()
    box.position = Vector2(22, 28)
    box.size = Vector2(212, 90)
    box.add_theme_constant_override("separation", 7)
    tutorial_panel.add_child(box)
    tutorial_text = Label.new()
    tutorial_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    tutorial_text.custom_minimum_size = Vector2(212, 56)
    tutorial_text.add_theme_font_size_override("font_size", 9)
    tutorial_text.add_theme_color_override("font_color", Color(1.0, 0.93, 0.7, 1.0))
    box.add_child(tutorial_text)
    tutorial_button = Button.new()
    tutorial_button.text = "NEXT"
    tutorial_button.add_theme_font_size_override("font_size", 10)
    tutorial_button.pressed.connect(_advance_tutorial)
    box.add_child(tutorial_button)
    $UI.add_child(tutorial_panel)

func _show_tutorial_step() -> void:
    var steps := [
        "Time stop. That rat is real, but it waits while you learn. Move with WASD or arrows and aim with the mouse.",
        "Left click swipes. Paw hits build style fast, especially when you keep fighting without glare.",
        "Space dashes through danger. Right click glares to stun, but glare cuts style, so save it for panic moments.",
        "Pinned by a rat means no movement or attacks until the sparkles end. Watch the gold hit circle and dash lane."
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

func _bank_run() -> void:
    if profile_saved:
        return
    profile_saved = true
    var config := ConfigFile.new()
    config.load("user://macatre_profile.cfg")
    best_record = max(best_record, score)
    var gained: int = maxi(0, score + int(style_meter * 0.35))
    coins += gained
    config.set_value("records", "best_score", best_record)
    config.set_value("shop", "coins", coins)
    config.set_value("shop", "last_score", score)
    config.set_value("shop", "last_style", int(style_meter))
    config.save("user://macatre_profile.cfg")
    _refresh_hud()
