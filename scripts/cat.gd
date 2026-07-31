extends CharacterBody2D

@export var speed: int = 200
@export var max_health: int = 9
@export var dash_speed: float = 460.0
@export var dash_duration: float = 0.18
@export var dash_cooldown: float = 0.6

@onready var anim: AnimatedSprite2D = $Anim

var health: int = max_health
var last_direction: Vector2 = Vector2.DOWN
var dead: bool = false
var is_dashing: bool = false
var dash_time_left: float = 0.0
var dash_cd_left: float = 0.0
var dash_direction: Vector2 = Vector2.DOWN

func _ready() -> void:
	add_to_group("player")

func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	dash_cd_left = max(dash_cd_left - delta, 0.0)

	if is_dashing:
		dash_time_left -= delta
		velocity = dash_direction * dash_speed
		move_and_slide()
		_play("run_" + _facing())
		if dash_time_left <= 0.0:
			is_dashing = false
			_set_flash(false)
		return

	var input_direction := Input.get_vector("left", "right", "forward", "backward")
	if input_direction != Vector2.ZERO:
		last_direction = input_direction

	if Input.is_action_just_pressed("dash") and dash_cd_left <= 0.0:
		dash_direction = (input_direction if input_direction != Vector2.ZERO else last_direction).normalized()
		last_direction = dash_direction
		is_dashing = true
		dash_time_left = dash_duration
		dash_cd_left = dash_cooldown
		_set_flash(true)
		return

	velocity = input_direction * speed
	move_and_slide()

	if input_direction != Vector2.ZERO:
		_play("walk_" + _facing())
	else:
		_play("idle_" + _facing())

func _facing() -> String:
	if abs(last_direction.x) >= abs(last_direction.y):
		anim.flip_h = last_direction.x < 0.0
		return "side"
	anim.flip_h = false
	return "front" if last_direction.y > 0.0 else "back"

func _play(name: String) -> void:
	if anim.animation != name:
		anim.play(name)

func _set_flash(on: bool) -> void:
	if anim.material != null:
		anim.material.set_shader_parameter("active", on)

func take_damage(amount: int) -> bool:
	if health <= 0:
		return false
	health -= amount
	modulate = Color(1, 0.6, 0.6)
	create_tween().tween_property(self, "modulate", Color.WHITE, 0.2)
	if health <= 0:
		health = 0
		die()
		return true
	return false

func die() -> void:
	dead = true
	modulate = Color(0.4, 0.4, 0.4)
	_play("idle_" + _facing())
