extends Control

func _ready() -> void:
	$Center/Box/Play.pressed.connect(_on_play)
	$Center/Box/Quit.pressed.connect(_on_quit)
	$Center/Box/Play.grab_focus()

func _on_play() -> void:
	get_tree().change_scene_to_file("res://scenes/level1.tscn")

func _on_quit() -> void:
	get_tree().quit()
