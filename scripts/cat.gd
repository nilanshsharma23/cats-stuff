extends CharacterBody2D

signal died
signal style_event(kind: String, amount: int)

@export var speed: int = 106
@export var max_health: int = 8
@export var dash_speed: float = 270.0
@export var dash_duration: float = 0.13
@export var dash_cooldown: float = 0.5

# Light attack - paw swipe (left mouse). Low damage: basics take 2-3.
@export var paw_damage: int = 1
@export var paw_range: float = 37.0
@export var paw_arc: float = -0.25
@export var paw_cooldown: float = 0.3
@export var paw_knockback: float = 118.0

# Heavy attack - bite (right mouse tap). Roots the cat for a beat, leaving it
# vulnerable, but one-shots basics and makes them bleed.
@export var bite_damage: int = 2
@export var bite_range: float = 37.0
@export var bite_arc: float = -0.1
@export var bite_lock: float = 0.86
@export var bite_cooldown: float = 2.35
@export var bite_knockback: float = 120.0
@export var bite_bleed_dur: float = 5.0
@export var bite_bleed_dps: float = 1.0

# Tail sweep - hold right mouse. Big knockback, little damage.
@export var tail_damage: int = 1
@export var tail_range: float = 47.0
@export var tail_arc: float = -0.4
@export var tail_knockback: float = 470.0
@export var tail_cooldown: float = 1.28
@export var tail_hold_threshold: float = 0.32

# Leer (E) - stun and mark a pack for execute setups.
@export var leer_range: float = 92.0
@export var leer_arc: float = 0.35
@export var leer_stun: float = 0.35
@export var leer_cooldown: float = 5.8
@export var leer_show: float = 0.5

@export var invuln_time: float = 0.34

@onready var anim: AnimatedSprite2D = $Anim
@onready var health_bar: TextureProgressBar = $UI/Control/HealthBar
@onready var slash: AnimatedSprite2D = $Slash
@onready var bite_fx: AnimatedSprite2D = $Bite
@onready var tail_sweep: AnimatedSprite2D = $TailSweep
@onready var glare_eyes: Node2D = $GlareEyes

var health: int = max_health
var last_direction: Vector2 = Vector2.DOWN
var dead: bool = false
var is_dashing: bool = false
var dash_time_left: float = 0.0
var dash_cd_left: float = 0.0
var dash_direction: Vector2 = Vector2.DOWN
var paw_cd: float = 0.0
var bite_cd_left: float = 0.0
var leer_cd: float = 0.0
var tail_cd: float = 0.0
var invuln_timer: float = 0.0
var bite_lock_timer: float = 0.0
var rmb_down: bool = false
var rmb_hold: float = 0.0
var rmb_consumed: bool = false
var mark_duration: float = 5.0
var glare_level: int = 1
var external_knockback: Vector2 = Vector2.ZERO
var external_knockback_timer: float = 0.0
var glare_tween: Tween

const CAT_DASH = preload("uid://capfj5y587nhw")
const CAT_PARRY = preload("uid://igm67v3h80mk")
const CAT_DIE = preload("uid://dlkb61t56j13g")
const CAT_HURT = preload("uid://cdwakwq3on3im")

func _ready() -> void:
	add_to_group("player")
	_load_profile()
	health = max_health
	health_bar.max_value = max_health
	health_bar.value = health
	glare_eyes.visible = false
	slash.visible = false
	bite_fx.visible = false
	tail_sweep.visible = false
	slash.animation_finished.connect(func(): slash.visible = false)
	bite_fx.animation_finished.connect(func(): bite_fx.visible = false)
	tail_sweep.animation_finished.connect(func(): tail_sweep.visible = false)

func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	dash_cd_left = max(dash_cd_left - delta, 0.0)
	paw_cd = max(paw_cd - delta, 0.0)
	bite_cd_left = max(bite_cd_left - delta, 0.0)
	leer_cd = max(leer_cd - delta, 0.0)
	tail_cd = max(tail_cd - delta, 0.0)
	invuln_timer = max(invuln_timer - delta, 0.0)
	bite_lock_timer = max(bite_lock_timer - delta, 0.0)
	external_knockback_timer = max(external_knockback_timer - delta, 0.0)

	if external_knockback_timer > 0.0:
		velocity = external_knockback
		external_knockback = external_knockback.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		_play("run_" + _facing())
		return

	# Committed to a bite: rooted and vulnerable until the lock ends.
	if bite_lock_timer > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		_play("idle_" + _facing())
		modulate = Color(1.0, 0.62, 0.62)
		if Input.is_action_just_released("bite"):
			rmb_down = false
		return

	if Input.is_action_just_pressed("paw") and paw_cd <= 0.0:
		_paw()
	if Input.is_action_just_pressed("leer") and leer_cd <= 0.0:
		_leer()

	# Right mouse: quick tap = bite, hold past the threshold = tail sweep.
	if Input.is_action_just_pressed("bite"):
		rmb_down = true
		rmb_hold = 0.0
		rmb_consumed = false
	if rmb_down:
		rmb_hold += delta
		if not rmb_consumed and rmb_hold >= tail_hold_threshold:
			rmb_consumed = true
			if tail_cd <= 0.0:
				_tail()
	if Input.is_action_just_released("bite"):
		var was_tap := rmb_down and not rmb_consumed
		rmb_down = false
		if was_tap and bite_cd_left <= 0.0:
			_bite()
			return

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
		SoundManager.play_sound_with_pitch(CAT_DASH, RandomNumberGenerator.new().randf_range(1.2, 0.8))
		dash_direction = (input_direction if input_direction != Vector2.ZERO else last_direction).normalized()
		last_direction = dash_direction
		is_dashing = true
		dash_time_left = dash_duration
		dash_cd_left = dash_cooldown
		invuln_timer = max(invuln_timer, dash_duration + 0.05)
		style_event.emit("dash", 2)
		_try_parry()
		_set_flash(true)
		return

	modulate = Color.WHITE if invuln_timer <= 0.0 else Color(1, 1, 1, 0.6)

	velocity = input_direction * speed
	move_and_slide()

	if input_direction != Vector2.ZERO:
		_play("walk_" + _facing())
	else:
		_play("idle_" + _facing())

# Sekiro-style deflect: you must dash INTO a telegraphing enemy (dash aimed
# toward it while its tell is on screen) to freeze it. Dodging away never parries.
func _try_parry() -> void:
	SoundManager.play_sound_with_pitch(CAT_PARRY, RandomNumberGenerator.new().randf_range(1.2, 0.8))
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if not (e.has_method("is_parryable") and e.has_method("freeze")):
			continue
		if not e.is_parryable():
			continue
		var to_e: Vector2 = e.global_position - global_position
		if to_e.length() > 80.0:
			continue
		if dash_direction.dot(to_e.normalized()) > 0.45:
			e.freeze(2.0)
			style_event.emit("parry", 24)

func _aim() -> Vector2:
	var a := get_global_mouse_position() - global_position
	return a.normalized() if a != Vector2.ZERO else last_direction

func _paw() -> void:
	paw_cd = paw_cooldown
	var aim := _aim()
	last_direction = aim
	_show_slash(aim, 1.0)
	var kills: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not e.has_method("take_damage"):
			continue
		var to_e: Vector2 = e.global_position - global_position
		if to_e.length() <= paw_range and aim.dot(to_e.normalized()) > paw_arc:
			var marked: bool = e.has_method("is_marked") and e.is_marked()
			var damage: int = _damage_for(e, "paw", paw_damage, marked)
			var killed: bool = e.take_damage(damage)
			style_event.emit("paw_hit", 4)
			if killed:
				kills += 1
				style_event.emit("execute" if marked else "paw_kill", 30 if marked else 16)
			if e.has_method("knockback"):
				e.knockback(to_e.normalized() * paw_knockback)
	if kills >= 2:
		style_event.emit("multi", kills)

# Heavy bite: roots the cat (bite_lock) and leaves it open, but hits hard and
# inflicts bleeding - a big commitment that clears tough foes.
func _bite() -> void:
	bite_lock_timer = bite_lock
	bite_cd_left = bite_cooldown
	var aim := _aim()
	last_direction = aim
	invuln_timer = 0.0
	_show_bite(aim)
	style_event.emit("bite", 8)
	var kills: int = 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not e.has_method("take_damage"):
			continue
		var to_e: Vector2 = e.global_position - global_position
		if to_e.length() <= bite_range and aim.dot(to_e.normalized()) > bite_arc:
			var marked: bool = e.has_method("is_marked") and e.is_marked()
			var damage: int = _damage_for(e, "bite", bite_damage, marked)
			var killed: bool = e.take_damage(damage)
			if not killed and e.has_method("bleed"):
				e.bleed(bite_bleed_dur, bite_bleed_dps)
			if killed:
				kills += 1
				style_event.emit("execute" if marked else "paw_kill", 36 if marked else 22)
			if e.has_method("knockback"):
				e.knockback(to_e.normalized() * bite_knockback)
	if kills >= 2:
		style_event.emit("multi", kills)

# Tail sweep: launch everything in front away. Low damage, huge knockback.
func _tail() -> void:
	tail_cd = tail_cooldown
	var aim := _aim()
	last_direction = aim
	_show_tail_sweep(aim)
	style_event.emit("tail", 5)
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e) or not e.has_method("take_damage"):
			continue
		var to_e: Vector2 = e.global_position - global_position
		if to_e.length() <= tail_range and aim.dot(to_e.normalized()) > tail_arc:
			var damage: int = _damage_for(e, "tail", tail_damage, false)
			e.take_damage(damage)
			if e.has_method("knockback"):
				e.knockback(to_e.normalized() * tail_knockback)

func _damage_for(enemy: Node, move: String, base_damage: int, marked: bool) -> int:
	var boss: bool = enemy.is_in_group("boss")
	var rat: bool = enemy.is_in_group("rats")
	var frog: bool = enemy.is_in_group("frogs")
	var damage: int = base_damage
	if move == "paw":
		if rat and not boss:
			damage = 2
		elif frog:
			damage = 1
		elif boss:
			damage = 1
	elif move == "tail":
		if frog and not boss:
			damage = 3
		elif boss:
			damage = 1
		else:
			damage = 1
	elif move == "bite":
		if boss:
			damage = 8
		elif frog and not boss:
			damage = 1
		else:
			damage = 2
	if marked and move == "paw":
		damage += 1
	return max(1, damage)

func _show_slash(aim: Vector2, scale_mul: float) -> void:
	slash.position = aim * 13.0
	slash.rotation = aim.angle()
	slash.flip_v = aim.x < 0.0
	slash.scale = Vector2(0.62, 0.62) * scale_mul
	slash.frame = 0
	slash.visible = true
	slash.play("slash")

func _show_bite(aim: Vector2) -> void:
	bite_fx.position = aim * 14.0
	bite_fx.rotation = aim.angle()
	bite_fx.flip_v = aim.x < 0.0
	bite_fx.scale = Vector2(0.86, 0.86)
	bite_fx.frame = 0
	bite_fx.visible = true
	bite_fx.play("bite")

func _show_tail_sweep(aim: Vector2) -> void:
	tail_sweep.position = aim * 12.0
	tail_sweep.rotation = aim.angle()
	tail_sweep.flip_v = aim.x < 0.0
	tail_sweep.scale = Vector2(0.72, 0.72)
	tail_sweep.frame = 0
	tail_sweep.visible = true
	tail_sweep.play("tail")

# LEER (E): stun and MARK a pack. Marked foes take double light damage and
# detonate into an EXECUTE when killed - an offensive setup, not a panic button.
func _leer() -> void:
	leer_cd = leer_cooldown
	var aim := _aim()
	last_direction = aim
	glare_eyes.position = aim * 14.0
	glare_eyes.rotation = aim.angle()
	glare_eyes.scale = Vector2(0.35, 0.35)
	glare_eyes.modulate = Color(1.0, 1.0, 1.0, 1.0)
	glare_eyes.visible = true
	if glare_tween != null and glare_tween.is_valid():
		glare_tween.kill()
	glare_tween = create_tween()
	glare_tween.tween_property(glare_eyes, "scale", Vector2(1.05, 1.05), leer_show * 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	glare_tween.parallel().tween_property(glare_eyes, "modulate:a", 0.35, leer_show)
	glare_tween.tween_callback(func(): glare_eyes.visible = false)
	style_event.emit("glare", -4)
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var to_e: Vector2 = e.global_position - global_position
		if to_e.length() <= leer_range and aim.dot(to_e.normalized()) > leer_arc:
			if e.has_method("stun"):
				e.stun(leer_stun)
			if e.has_method("mark"):
				e.mark(mark_duration)

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

func enemy_knockback(v: Vector2) -> void:
	if dead:
		return
	external_knockback = v
	external_knockback_timer = 0.18
	if v != Vector2.ZERO:
		last_direction = v.normalized()

func take_damage(amount: int) -> bool:
	if health <= 0 or is_dashing or invuln_timer > 0.0:
		return false
	health -= amount
	invuln_timer = invuln_time
	style_event.emit("damage_taken", -10)
	health_bar.value = health
	if anim.material != null:
		anim.self_modulate = Color(1, 0.55, 0.55)
		create_tween().tween_property(anim, "self_modulate", Color.WHITE, 0.35)
	if health <= 0:
		health = 0
		die()
		SoundManager.stop_music()
		SoundManager.play_sound(CAT_DIE)
		return true
	SoundManager.play_sound_with_pitch(CAT_HURT, RandomNumberGenerator.new().randf_range(1.2, 0.8))
	return false

func die() -> void:
	dead = true
	modulate = Color(0.4, 0.4, 0.4)
	_play("idle_" + _facing())
	died.emit()

# --- Between-wave roguelite upgrades (applied by the level's break shop) ---

func buy_health() -> void:
	max_health += 1
	health = mini(health + 2, max_health)
	health_bar.max_value = max_health
	health_bar.value = health

func upgrade_dash() -> void:
	dash_speed += 25.0
	dash_duration = minf(dash_duration + 0.01, 0.24)
	dash_cooldown = maxf(dash_cooldown - 0.025, 0.28)

func upgrade_leer() -> void:
	leer_stun += 0.1
	mark_duration += 0.65
	leer_range += 5.0
	leer_cooldown = maxf(leer_cooldown - 0.3, 5.0)

func _load_profile() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://macatre_profile.cfg")
	glare_level = 1
	if err == OK:
		glare_level = int(config.get_value("shop", "glare_level", 1))
	glare_level = clampi(glare_level, 1, 3)
	var stuns := [0.35, 0.6, 0.85]
	leer_stun = stuns[glare_level - 1]
