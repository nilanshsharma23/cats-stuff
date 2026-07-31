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

func _ready() -> void:
	rng.randomize()
	game_over.visible = false
	banner.modulate.a = 0.0
	var cat := get_tree().get_first_node_in_group("player")
	if cat != null and cat.has_signal("died"):
		cat.died.connect(_on_cat_died)
	$UI/GameOver/Center/Box/Retry.pressed.connect(_restart)
	$UI/GameOver/Center/Box/Menu.pressed.connect(_to_menu)
	_build_waves()
	_next_wave()

func _build_waves() -> void:
	if level_id == 1:
		waves = [[["rat", 2]], [["rat", 3]]]
	else:
		waves = [[["rat", 6], ["frog", 3]]]

func _next_wave() -> void:
	if cleared:
		return
	wave_index += 1
	if wave_index >= waves.size():
		_level_cleared()
		return
	_show_banner("WAVE %d" % (wave_index + 1))
	for entry in waves[wave_index]:
		for i in int(entry[1]):
			_spawn(String(entry[0]))

func _spawn(type: String) -> void:
	var scene: PackedScene = rat_scene if type == "rat" else frog_scene
	if scene == null:
		return
	var e := scene.instantiate()
	e.position = _spawn_point()
	if type == "rat" and level_id >= 2:
		e.set("roots_player", true)
	add_child(e)
	alive += 1
	if e.has_signal("died"):
		e.died.connect(_on_enemy_died)

func _spawn_point() -> Vector2:
	var cat := get_tree().get_first_node_in_group("player")
	var cat_pos: Vector2 = cat.global_position if cat != null else Vector2(128, 72)
	for _i in 12:
		var p := Vector2(rng.randf_range(22, 234), rng.randf_range(22, 122))
		if p.distance_to(cat_pos) > 60.0:
			return p
	return Vector2(rng.randf_range(22, 234), rng.randf_range(22, 122))

func _on_enemy_died() -> void:
	alive -= 1
	if alive <= 0 and not cleared:
		call_deferred("_next_wave")

func _level_cleared() -> void:
	cleared = true
	if next_level_path != "":
		_show_banner("LEVEL CLEAR")
		await get_tree().create_timer(1.6).timeout
		get_tree().change_scene_to_file(next_level_path)
	else:
		_show_banner("YOU SURVIVED")
		await get_tree().create_timer(2.6).timeout
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_cat_died() -> void:
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
