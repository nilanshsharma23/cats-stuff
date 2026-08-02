extends CharacterBody2D

signal died
signal style_event(kind: String, amount: int)

# A hair faster than the base rat (112) so disengaging is possible but not free;
# scurriers (142) still run you down.
@export var speed: int = 116
@export var max_health: int = 8
@export var dash_speed: float = 300.0
@export var dash_duration: float = 0.16
@export var dash_cooldown: float = 0.42

# Light attack - paw swipe (left mouse). Low damage: basics take 2-3.
@export var paw_damage: int = 1
@export var paw_range: float = 37.0
@export var paw_arc: float = -0.25
@export var paw_cooldown: float = 0.3
@export var paw_knockback: float = 118.0

# Heavy attack - bite (right mouse tap). Roots the cat for a short beat, leaving
# it vulnerable, but hits like a truck on a single target and makes it bleed.
# This is your anti-elite / anti-tank button, not your spam button.
@export var bite_damage: int = 2
@export var bite_range: float = 37.0
@export var bite_arc: float = -0.1
@export var bite_lock: float = 0.28
@export var bite_cooldown: float = 1.5
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

@export var invuln_time: float = 0.22

# Parry has to be aimed at a specific enemy at knife range, not thrown out into a
# crowd: reach is barely past the cat's own attack range and the cone is ~45deg.
const PARRY_REACH: float = 40.0
const PARRY_CONE: float = 0.72

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

# --- OVERDRIVE (the boss-only ultimate) -------------------------------------
#
# Two phases. While `planning`, the cat plays normally but every attack is
# RECORDED instead of resolved - nothing takes damage, and a breadcrumb of her
# position is sampled each frame. While `executing`, that recording is replayed
# at ~3.3x speed and the attacks land for real, all at once.
signal plan_action_queued(at: Vector2, kind: String)

const PLAN_ACTION_CAP: int = 14
const OVERDRIVE_DAMAGE_MUL: float = 1.5

var planning: bool = false
var executing: bool = false
var plan_time: float = 0.0
var plan_path: Array = []
var plan_actions: Array = []
var exec_time: float = 0.0
var exec_duration: float = 1.5
var exec_scale: float = 1.0
var exec_next: int = 0
var exec_path_index: int = 0
var afterimage_cd: float = 0.0

const CAT_DASH = preload("uid://capfj5y587nhw")
const CAT_PARRY = preload("uid://igm67v3h80mk")
const CAT_DIE = preload("uid://dlkb61t56j13g")
const CAT_HURT = preload("uid://cdwakwq3on3im")

@onready var camera_2d: Camera2D = $"../Camera2D"

func _ready() -> void:
	# Opt back into pausing (the level root is PROCESS_MODE_ALWAYS).
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("player")
	_load_profile()
	health = max_health
	health_bar.max_value = max_health
	health_bar.value = health
	glare_eyes.visible = false
	slash.visible = false
	bite_fx.visible = false
	tail_sweep.visible = false
	queue_redraw()
	slash.animation_finished.connect(func(): slash.visible = false)
	bite_fx.animation_finished.connect(func(): bite_fx.visible = false)
	tail_sweep.animation_finished.connect(func(): tail_sweep.visible = false)

func _process(delta: float) -> void:
	camera_2d.offset = global_position

func _physics_process(delta: float) -> void:
	queue_redraw()
	if dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	# Replaying a plan takes the cat off player control entirely.
	if executing:
		_run_execution(delta)
		return

	if planning:
		plan_time += delta
		plan_path.append({"t": plan_time, "pos": global_position, "dir": last_direction})

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

	if Input.is_action_just_pressed("paw") and paw_cd <= 0.0 and not plan_full():
		_paw()
	if Input.is_action_just_pressed("leer") and leer_cd <= 0.0 and not plan_full():
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
			if tail_cd <= 0.0 and not plan_full():
				_tail()
	if Input.is_action_just_released("bite"):
		var was_tap := rmb_down and not rmb_consumed
		rmb_down = false
		if was_tap and bite_cd_left <= 0.0 and not plan_full():
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
		# The dash only dodges for its own active frames - a tight window on a real
		# cooldown, not a blanket cloak. The safe, rewarding option is to dash INTO
		# a telegraphing enemy and PARRY it (below), which pays out far better than
		# scampering away ever could.
		invuln_timer = max(invuln_timer, dash_duration * 0.75)
		style_event.emit("dash", 2)
		if _try_parry():
			# Perfect deflect: most of the dash back and a beat of i-frames to
			# reposition. It buys tempo and style, never health - free healing on a
			# repeatable input is what made the cat unkillable.
			dash_cd_left = dash_cooldown * 0.35
			invuln_timer = 0.28
		_set_flash(true)
		return

	# Planning grants blanket invulnerability, but the cat must stay fully opaque
	# through it - she is the one thing you need to read while setting up.
	modulate = Color.WHITE if (invuln_timer <= 0.0 or planning) else Color(1, 1, 1, 0.6)

	velocity = input_direction * speed
	move_and_slide()

	if input_direction != Vector2.ZERO:
		_play("walk_" + _facing())
	else:
		_play("idle_" + _facing())

# --- OVERDRIVE control surface (driven by the level) ------------------------

func begin_plan() -> void:
	planning = true
	executing = false
	plan_time = 0.0
	plan_path.clear()
	plan_actions.clear()
	# You enter Overdrive with everything off cooldown, but cooldowns still TICK
	# during planning. Letting the player queue 14 free jaws would out-damage
	# every boss in the game and make the rest of the kit irrelevant; keeping the
	# normal economy means Overdrive is a perfect five seconds of your real kit,
	# landing all at once and unanswerable, rather than a separate better kit.
	paw_cd = 0.0
	bite_cd_left = 0.0
	tail_cd = 0.0
	leer_cd = 0.0
	dash_cd_left = 0.0
	bite_lock_timer = 0.0
	invuln_timer = 999.0

func plan_full() -> bool:
	return plan_actions.size() >= PLAN_ACTION_CAP

func planned_count() -> int:
	return plan_actions.size()

func end_plan() -> void:
	planning = false

# Hard stop, used when a run ends mid-Overdrive (killing the boss with the combo
# is the likeliest way to get here). Leaves the cat in a clean, controllable
# state no matter which phase was interrupted.
func cancel_overdrive() -> void:
	planning = false
	if executing:
		_finish_execution()
	plan_path.clear()
	plan_actions.clear()

# Replay the recording over `duration` seconds. Returns false when nothing was
# queued, so the level can skip straight to the cleanup.
func run_execution(duration: float) -> bool:
	planning = false
	if plan_actions.is_empty():
		invuln_timer = invuln_time
		return false
	executing = true
	exec_duration = maxf(duration, 0.1)
	exec_time = 0.0
	exec_scale = maxf(plan_time, 0.01) / exec_duration
	exec_next = 0
	exec_path_index = 0
	afterimage_cd = 0.0
	invuln_timer = exec_duration + 0.35
	return true

func _run_execution(delta: float) -> void:
	exec_time += delta
	afterimage_cd -= delta
	var plan_t: float = exec_time * exec_scale
	_seek_plan_path(plan_t)
	if afterimage_cd <= 0.0:
		afterimage_cd = 0.035
		_spawn_afterimage()
	# Fire every action whose recorded moment has now passed.
	while exec_next < plan_actions.size() and float(plan_actions[exec_next]["t"]) <= plan_t:
		var action: Dictionary = plan_actions[exec_next]
		exec_next += 1
		global_position = action["pos"]
		last_direction = action["aim"]
		_perform(String(action["kind"]), action["aim"], true)
	if exec_time >= exec_duration:
		_finish_execution()

func _seek_plan_path(plan_t: float) -> void:
	while exec_path_index < plan_path.size() - 1 and float(plan_path[exec_path_index]["t"]) < plan_t:
		exec_path_index += 1
	if exec_path_index < plan_path.size():
		var sample: Dictionary = plan_path[exec_path_index]
		global_position = sample["pos"]
		last_direction = sample["dir"]
	_play("run_" + _facing())

func _finish_execution() -> void:
	executing = false
	plan_path.clear()
	plan_actions.clear()
	invuln_timer = maxf(invuln_timer, 0.4)
	_set_flash(false)
	modulate = Color.WHITE

# Streaked copies of the current frame left behind during the replay - the whole
# point of the ultimate is watching the combo land at once.
func _spawn_afterimage() -> void:
	var frames := anim.sprite_frames
	if frames == null or not frames.has_animation(anim.animation):
		return
	var ghost := Sprite2D.new()
	ghost.texture = frames.get_frame_texture(anim.animation, anim.frame)
	ghost.global_position = global_position
	ghost.scale = anim.scale
	ghost.flip_h = anim.flip_h
	ghost.z_index = 1
	ghost.modulate = Color(1.0, 0.35, 1.0, 0.75)
	get_parent().add_child(ghost)
	var t := ghost.create_tween()
	t.tween_property(ghost, "modulate:a", 0.0, 0.28)
	t.parallel().tween_property(ghost, "scale", anim.scale * 1.2, 0.28)
	t.tween_callback(ghost.queue_free)

# Single entry point for "do an attack". During planning it records instead of
# resolving, so the recorded list and the live behaviour can never drift apart.
func _perform(kind: String, aim: Vector2, for_real: bool) -> void:
	match kind:
		"paw":
			_resolve_paw(aim, for_real)
		"bite":
			_resolve_bite(aim, for_real)
		"tail":
			_resolve_tail(aim, for_real)
		"leer":
			_resolve_leer(aim, for_real)

func _record(kind: String, aim: Vector2) -> void:
	if plan_actions.size() >= PLAN_ACTION_CAP:
		return
	plan_actions.append({"t": plan_time, "kind": kind, "aim": aim, "pos": global_position})
	plan_action_queued.emit(global_position + aim * 16.0, kind)

# Sekiro-style deflect: you must dash INTO an enemy during the last beat of its
# wind-up (see each enemy's is_parryable) to freeze it. Dodging away never
# parries, and the reach and cone are tight enough that it has to be aimed.
# Returns true if at least one enemy was deflected, so the caller can reward it.
func _try_parry() -> bool:
	var parried := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if not (e.has_method("is_parryable") and e.has_method("freeze")):
			continue
		if not e.is_parryable():
			continue
		var to_e: Vector2 = e.global_position - global_position
		if to_e.length() > PARRY_REACH:
			continue
		if dash_direction.dot(to_e.normalized()) > PARRY_CONE:
			e.freeze(1.4)
			style_event.emit("parry", 24)
			parried = true
	if parried:
		SoundManager.play_sound_with_pitch(CAT_PARRY, RandomNumberGenerator.new().randf_range(1.2, 0.8))
	return parried

func _aim() -> Vector2:
	var a := get_global_mouse_position() - global_position
	return a.normalized() if a != Vector2.ZERO else last_direction

func _paw() -> void:
	paw_cd = paw_cooldown
	var aim := _aim()
	last_direction = aim
	if planning:
		_show_slash(aim, 1.0)
		_record("paw", aim)
		return
	_resolve_paw(aim, true)

func _resolve_paw(aim: Vector2, for_real: bool) -> void:
	_show_slash(aim, 1.0)
	if not for_real:
		return
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
	var aim := _aim()
	last_direction = aim
	bite_cd_left = bite_cooldown
	if planning:
		# The cooldown still applies (it is what stops a wall of free jaws), but
		# not the root - being pinned in place means nothing while time is stopped.
		_show_bite(aim)
		_record("bite", aim)
		return
	bite_lock_timer = bite_lock
	_resolve_bite(aim, true)

func _resolve_bite(aim: Vector2, for_real: bool) -> void:
	_show_bite(aim)
	if not for_real:
		return
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
	if planning:
		_show_tail_sweep(aim)
		_record("tail", aim)
		return
	_resolve_tail(aim, true)

func _resolve_tail(aim: Vector2, for_real: bool) -> void:
	_show_tail_sweep(aim)
	if not for_real:
		return
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

# Each attack has a lane:
#   paw  - fast, cheap, wide arc: shreds light foes but bounces off tanks.
#   bite - slow, roots you, but a single-target nuke that chews tanks & elites.
#   tail - control: low damage, huge knockback to buy space.
#   leer mark then paw = one-shot EXECUTE on light prey.
func _damage_for(enemy: Node, move: String, base_damage: int, marked: bool) -> int:
	var boss: bool = enemy.is_in_group("boss")
	var tanky: bool = not boss and int(enemy.get("max_health")) >= 7
	var damage: int = base_damage
	if move == "paw":
		damage = 1 if tanky else 2
	elif move == "tail":
		damage = 1 if boss else 2
	elif move == "bite":
		if boss:
			damage = 8
		elif tanky:
			damage = 5
		else:
			damage = 4
	if marked:
		damage += 2 if move == "paw" else 1
	# The replayed combo hits harder than the sum of its parts - that is what
	# makes spending a full SS meter on it worth doing.
	if executing:
		damage = int(round(float(damage) * OVERDRIVE_DAMAGE_MUL))
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
	if planning:
		_show_leer_fx(aim)
		_record("leer", aim)
		return
	_resolve_leer(aim, true)

func _resolve_leer(aim: Vector2, for_real: bool) -> void:
	_show_leer_fx(aim)
	if not for_real:
		return
	style_event.emit("glare", 0)
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var to_e: Vector2 = e.global_position - global_position
		if to_e.length() <= leer_range and aim.dot(to_e.normalized()) > leer_arc:
			if e.has_method("stun"):
				e.stun(leer_stun)
			if e.has_method("mark"):
				e.mark(mark_duration)

func _show_leer_fx(aim: Vector2) -> void:
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

# Contact shadow. Together with the sprite's outline shader this is what stops
# the cat from vanishing into the floor tiles - it anchors her to the ground and
# gives the eye a high-contrast blob to track in a crowded fight.
func _draw() -> void:
	if dead:
		return
	var lift: float = 1.0
	if is_dashing:
		lift = 0.55
	draw_circle(Vector2(0.0, 6.0), 4.6 * lift, Color(0.0, 0.0, 0.0, 0.3 * lift))
	draw_circle(Vector2(0.0, 6.0), 2.8 * lift, Color(0.0, 0.0, 0.0, 0.22 * lift))

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
	# i-frames come from invuln_timer alone. The dash sets it for most (not all)
	# of its duration, so a dash is a real dodge with a punishable tail rather
	# than a blanket of immunity for as long as you keep dashing.
	if health <= 0 or invuln_timer > 0.0:
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

# Picked up a dropped heart. Returns how much actually landed so the pickup can
# tell the difference between a real top-up and a wasted one.
func heal(amount: int) -> int:
	if dead or amount <= 0:
		return 0
	var before := health
	health = mini(health + amount, max_health)
	health_bar.value = health
	var gained := health - before
	if gained > 0:
		anim.self_modulate = Color(0.6, 1.0, 0.7)
		create_tween().tween_property(anim, "self_modulate", Color.WHITE, 0.3)
	return gained

func die() -> void:
	dead = true
	modulate = Color(0.4, 0.4, 0.4)
	_play("idle_" + _facing())
	died.emit()

# Difficulty handicap, applied by the level once on spawn. Easy hands over a
# bigger health pool, Hell takes some away; the floor of 4 keeps Hell survivable
# rather than a one-shot gimmick.
func apply_difficulty(bonus_hp: int) -> void:
	if bonus_hp == 0:
		return
	max_health = maxi(4, max_health + bonus_hp)
	health = max_health
	health_bar.max_value = max_health
	health_bar.value = health

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
