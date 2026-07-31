extends CharacterBody2D

signal died

@export var move_speed: float = 95.0
@export var dash_speed: float = 210.0
@export var detection_radius: float = 320.0
@export var nibble_range: float = 24.0
@export var nibble_damage: int = 1
@export var dash_damage: int = 2
@export var nibble_interval: float = 0.6
@export var dash_cooldown_min: float = 1.2
@export var dash_cooldown_max: float = 2.8
@export var dash_duration: float = 0.16
@export var dash_chance: float = 0.7
@export var dash_windup: float = 0.35
@export var max_health: int = 3
@export var hurt_time: float = 0.2
@export var attack_show_time: float = 0.35
@export var roots_player: bool = false
@export var root_time: float = 0.9

@onready var anim: AnimatedSprite2D = $Anim

var player: Node2D = null
var last_direction: Vector2 = Vector2.DOWN
var health: int = max_health
var dead: bool = false

var nibble_timer: float = 0.0
var dash_timer: float = 0.0
var dash_time_left: float = 0.0
var dash_direction: Vector2 = Vector2.DOWN
var is_dashing: bool = false
var is_winding: bool = false
var wind_timer: float = 0.0
var wind_dir: Vector2 = Vector2.DOWN
var hurt_timer: float = 0.0
var attack_timer: float = 0.0
var stun_timer: float = 0.0
var knockback_vel: Vector2 = Vector2.ZERO
var knockback_timer: float = 0.0

func _ready() -> void:
	add_to_group("rats")
	add_to_group("enemies")
	dash_timer = randf_range(dash_cooldown_min, dash_cooldown_max)

func stun(duration: float) -> void:
	if dead:
		return
	stun_timer = max(stun_timer, duration)
	is_dashing = false
	is_winding = false
	attack_timer = 0.0
	queue_redraw()

func knockback(v: Vector2) -> void:
	if dead:
		return
	knockback_vel = v
	knockback_timer = 0.14

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

	if knockback_timer > 0.0:
		knockback_timer -= delta
		velocity = knockback_vel
		knockback_vel = knockback_vel.move_toward(Vector2.ZERO, 700.0 * delta)
		move_and_slide()
		return

	if stun_timer > 0.0:
		stun_timer -= delta
		velocity = Vector2.ZERO
		modulate = Color(0.55, 0.75, 1.0)
		_play("idle_" + _facing())
		move_and_slide()
		if stun_timer <= 0.0:
			modulate = Color.WHITE
		return
	modulate = Color.WHITE

	if hurt_timer > 0.0:
		velocity = Vector2.ZERO
		_play("hurt_" + _facing())
		move_and_slide()
		return

	if is_winding:
		velocity = Vector2.ZERO
		wind_timer -= delta
		_face(wind_dir)
		_play("idle_" + _facing())
		queue_redraw()
		move_and_slide()
		if wind_timer <= 0.0:
			is_winding = false
			queue_redraw()
			_start_dash(wind_dir)
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
				_begin_windup(direction)
				return

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
	is_winding = false
	attack_timer = 0.0
	queue_redraw()
	return false

func _die() -> void:
	dead = true
	velocity = Vector2.ZERO
	is_dashing = false
	is_winding = false
	modulate = Color.WHITE
	queue_redraw()
	remove_from_group("enemies")
	$CollisionShape2D.set_deferred("disabled", true)
	_play("death_" + _facing())
	died.emit()

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

func _begin_windup(direction: Vector2) -> void:
	is_winding = true
	wind_timer = dash_windup
	wind_dir = direction if direction != Vector2.ZERO else last_direction

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
	if not killed and roots_player and player.has_method("root"):
		player.root(root_time)
	if killed:
		_start_dash((player.global_position - global_position).normalized())

func _facing() -> String:
	if abs(last_direction.x) >= abs(last_direction.y):
		anim.flip_h = last_direction.x > 0.0
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

func _draw() -> void:
	if not is_winding:
		return
	var t: float = 1.0 - clamp(wind_timer / dash_windup, 0.0, 1.0)
	var reach: float = dash_speed * dash_duration
	var col := Color(1.0, 0.15, 0.15, 0.45 + 0.45 * t)
	var tip: Vector2 = wind_dir * reach
	draw_line(Vector2.ZERO, tip, col, 1.5)
	var perp := Vector2(-wind_dir.y, wind_dir.x) * 3.0
	draw_line(tip, tip - wind_dir * 4.0 + perp, col, 1.5)
	draw_line(tip, tip - wind_dir * 4.0 - perp, col, 1.5)
	draw_circle(Vector2(0, -12), 1.5 + 1.5 * t, Color(1.0, 0.1, 0.1, 0.85))
