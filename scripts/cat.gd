extends CharacterBody2D

signal died

@export var speed: int = 200
@export var max_health: int = 9
@export var dash_speed: float = 460.0
@export var dash_duration: float = 0.18
@export var dash_cooldown: float = 0.32

@export var paw_damage: int = 4
@export var paw_range: float = 42.0
@export var paw_arc: float = -0.15
@export var paw_cooldown: float = 0.2
@export var paw_knockback: float = 190.0

@export var glare_range: float = 95.0
@export var glare_arc: float = 0.45
@export var glare_stun: float = 1.6
@export var glare_cooldown: float = 1.2
@export var glare_show: float = 0.4

@onready var anim: AnimatedSprite2D = $Anim
@onready var health_bar: TextureProgressBar = $UI/Control/HealthBar
@onready var paw_particles: CPUParticles2D = $PawParticles
@onready var glare_eyes: Node2D = $GlareEyes

var health: int = max_health
var last_direction: Vector2 = Vector2.DOWN
var dead: bool = false
var is_dashing: bool = false
var dash_time_left: float = 0.0
var dash_cd_left: float = 0.0
var dash_direction: Vector2 = Vector2.DOWN
var paw_cd: float = 0.0
var glare_cd: float = 0.0
var rooted_timer: float = 0.0

func _ready() -> void:
	add_to_group("player")
	health_bar.max_value = max_health
	health_bar.value = health
	glare_eyes.visible = false

func root(duration: float) -> void:
	rooted_timer = max(rooted_timer, duration)

func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	dash_cd_left = max(dash_cd_left - delta, 0.0)
	paw_cd = max(paw_cd - delta, 0.0)
	glare_cd = max(glare_cd - delta, 0.0)
	rooted_timer = max(rooted_timer - delta, 0.0)

	if Input.is_action_just_pressed("paw") and paw_cd <= 0.0:
		_paw()
	if Input.is_action_just_pressed("glare") and glare_cd <= 0.0:
		_glare()

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
		rooted_timer = 0.0
		_set_flash(true)
		return

	if rooted_timer > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		_play("idle_" + _facing())
		modulate = Color(1, 0.85, 0.5)
		return
	modulate = Color.WHITE

	velocity = input_direction * speed
	move_and_slide()

	if input_direction != Vector2.ZERO:
		_play("walk_" + _facing())
	else:
		_play("idle_" + _facing())

func _aim() -> Vector2:
	var a := get_global_mouse_position() - global_position
	return a.normalized() if a != Vector2.ZERO else last_direction

func _paw() -> void:
	paw_cd = paw_cooldown
	var aim := _aim()
	last_direction = aim
	paw_particles.rotation = aim.angle()
	paw_particles.position = aim * 12.0
	paw_particles.restart()
	paw_particles.emitting = true
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not e.has_method("take_damage"):
			continue
		var to_e: Vector2 = e.global_position - global_position
		if to_e.length() <= paw_range and aim.dot(to_e.normalized()) > paw_arc:
			e.take_damage(paw_damage)
			if e.has_method("knockback"):
				e.knockback(to_e.normalized() * paw_knockback)

func _glare() -> void:
	glare_cd = glare_cooldown
	var aim := _aim()
	last_direction = aim
	glare_eyes.visible = true
	var t := create_tween()
	t.tween_interval(glare_show)
	t.tween_callback(func(): glare_eyes.visible = false)
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var to_e: Vector2 = e.global_position - global_position
		if to_e.length() <= glare_range and aim.dot(to_e.normalized()) > glare_arc:
			if e.has_method("stun"):
				e.stun(glare_stun)

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
	if health <= 0 or is_dashing:
		return false
	health -= amount
	modulate = Color(1, 0.6, 0.6)
	health_bar.value = health
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
	died.emit()
