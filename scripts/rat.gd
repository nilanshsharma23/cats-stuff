extends CharacterBody2D

@export var move_speed: float = 70.0
@export var dash_speed: float = 320.0
@export var detection_radius: float = 220.0
@export var nibble_range: float = 24.0
@export var nibble_damage: int = 1
@export var dash_damage: int = 2
@export var nibble_interval: float = 0.8
@export var dash_cooldown_min: float = 2.5
@export var dash_cooldown_max: float = 5.0
@export var dash_duration: float = 0.28
@export var dash_chance: float = 0.55
@export var max_health: int = 3
@export var hurt_time: float = 0.25
@export var attack_show_time: float = 0.35

@onready var anim: AnimatedSprite2D = $Anim

var player: Node2D = null
var last_direction: Vector2 = Vector2.DOWN
var health: int = max_health
var dead: bool = false

var nibble_timer: float = 0.0
var dash_timer: float = 0.0
var dash_time_left: float = 0.0
var dash_direction: Vector2 = Vector2.LEFT
var is_dashing: bool = false
var hurt_timer: float = 0.0
var attack_timer: float = 0.0

func _ready() -> void:
	add_to_group("rats")
	dash_timer = randf_range(dash_cooldown_min, dash_cooldown_max)

func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_find_player()

	nibble_timer = max(nibble_timer - delta, 0.0)
	dash_timer = max(dash_timer - delta, 0.0)
	hurt_timer = max(hurt_timer - delta, 0.0)
	attack_timer = max(attack_timer - delta, 0.0)

	if hurt_timer > 0.0:
		velocity = Vector2.ZERO
		_play("hurt_" + _facing())
		move_and_slide()
		return

	if is_dashing:
		_run_dash(delta)
		_update_animation()
		return

	if player == null:
		velocity = Vector2.ZERO
		_update_animation()
		move_and_slide()
		return

	var to_player: Vector2 = player.global_position - global_position
	var distance: float = to_player.length()

	if distance > detection_radius:
		velocity = Vector2.ZERO
		_update_animation()
		move_and_slide()
		return

	var direction: Vector2 = to_player.normalized()
	_face(direction)

	if distance <= nibble_range:
		velocity = Vector2.ZERO
		_try_nibble()
	else:
		velocity = direction * move_speed
		if dash_timer <= 0.0:
			dash_timer = randf_range(dash_cooldown_min, dash_cooldown_max)
			if randf() < dash_chance:
				_start_dash(direction)

	_update_animation()
	move_and_slide()

func take_damage(amount: int) -> bool:
	if dead:
		return false
	health -= amount
	if health <= 0:
		health = 0
		_die()
		return true
	hurt_timer = hurt_time
	is_dashing = false
	attack_timer = 0.0
	return false

func _die() -> void:
	dead = true
	velocity = Vector2.ZERO
	is_dashing = false
	$CollisionShape2D.set_deferred("disabled", true)
	_play("death_" + _facing())

func _find_player() -> void:
	if player != null and is_instance_valid(player):
		return
	player = get_tree().get_first_node_in_group("player")

func _face(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return
	last_direction = direction

func _try_nibble() -> void:
	if nibble_timer > 0.0:
		return
	nibble_timer = nibble_interval
	attack_timer = attack_show_time
	_bite(nibble_damage)

func _start_dash(direction: Vector2) -> void:
	is_dashing = true
	dash_time_left = dash_duration
	dash_direction = direction if direction != Vector2.ZERO else last_direction
	_face(dash_direction)

func _run_dash(delta: float) -> void:
	dash_time_left -= delta
	velocity = dash_direction * dash_speed
	move_and_slide()

	if player != null and global_position.distance_to(player.global_position) <= nibble_range:
		_bite(dash_damage)

	if dash_time_left <= 0.0:
		is_dashing = false
		dash_timer = randf_range(dash_cooldown_min, dash_cooldown_max)

func _bite(amount: int) -> void:
	if player == null or not player.has_method("take_damage"):
		return
	var killed: bool = player.take_damage(amount)
	if killed:
		_start_dash((player.global_position - global_position).normalized())

func _facing() -> String:
	if abs(last_direction.x) >= abs(last_direction.y):
		anim.flip_h = last_direction.x < 0.0
		return "side"
	anim.flip_h = false
	return "front" if last_direction.y > 0.0 else "back"

func _update_animation() -> void:
	var dir := _facing()
	var state := "idle"
	if is_dashing:
		state = "run"
	elif attack_timer > 0.0:
		state = "attack"
	elif velocity.length() > 1.0:
		state = "walk"
	_play(state + "_" + dir)

func _play(name: String) -> void:
	if anim.animation != name:
		anim.play(name)
