extends CharacterBody2D

signal died

@export var move_speed: float = 64.0
@export var max_health: int = 70
@export var body_scale: float = 0.14
@export var tint: Color = Color.WHITE
@export var ghost_tint: Color = Color(0.78, 0.62, 1.0, 0.72)
@export var circle_radius: float = 34.0
@export var cross_width: float = 12.0
@export var circle_damage: int = 1
@export var cross_damage: int = 1
@export var score_value: int = 900

@onready var sprite: Sprite2D = $Sprite
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

const ARENA_MIN := Vector2(28, 24)
const ARENA_MAX := Vector2(228, 120)
const FRAME_TIME := 0.09

var frames: Array[Texture2D] = [
	preload("res://sprites/pigeon-1.png"),
	preload("res://sprites/pigeon-2.png"),
	preload("res://sprites/pigeon-3.png"),
	preload("res://sprites/pigeon-4.png"),
]

var boss_name: String = "THE WIND WRAITH"
var player: Node2D = null
var health: int = max_health
var dead: bool = false
var stage: int = 1
var attack_cd: float = 1.2
var attack_kind: String = ""
var attack_timer: float = 0.0
var attack_duration: float = 1.0
var attack_index: int = 0
var circle_target: Vector2 = Vector2.ZERO
var circle_start: Vector2 = Vector2.ZERO
var circle_end: Vector2 = Vector2.ZERO
var cross_center: Vector2 = Vector2.ZERO
var parry_window: float = 0.0
var stun_timer: float = 0.0
var frozen: bool = false
var hurt_timer: float = 0.0
var marked_timer: float = 0.0
var bleed_timer: float = 0.0
var bleed_accum: float = 0.0
var bleed_dps: float = 0.0
var knockback_vel: Vector2 = Vector2.ZERO
var knockback_timer: float = 0.0
var flap_timer: float = 0.0
var frame_index: int = 0
var last_direction: Vector2 = Vector2.RIGHT
var wobble_seed: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	health = max_health
	wobble_seed = randf() * TAU
	_apply_stage_visuals()

func configure(cfg: Dictionary) -> void:
	for key in cfg:
		set(key, cfg[key])

func stun(duration: float) -> void:
	if dead:
		return
	stun_timer = max(stun_timer, duration)
	_cancel_attack()
	queue_redraw()

func is_parryable() -> bool:
	return parry_window > 0.0 and not dead

func freeze(duration: float) -> void:
	if dead:
		return
	frozen = true
	stun_timer = max(stun_timer, duration)
	parry_window = 0.0
	_cancel_attack()
	velocity = Vector2.ZERO
	queue_redraw()

func mark(duration: float) -> void:
	if dead:
		return
	marked_timer = max(marked_timer, duration)
	queue_redraw()

func is_marked() -> bool:
	return marked_timer > 0.0 and not dead

func bleed(duration: float, dps: float) -> void:
	if dead:
		return
	bleed_timer = max(bleed_timer, duration)
	bleed_dps = max(bleed_dps, dps)

func knockback(v: Vector2) -> void:
	if dead:
		return
	knockback_vel = v * 0.08
	knockback_timer = 0.05

func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_find_player()
	_tick_common(delta)
	_animate(delta)
	if dead:
		return

	if knockback_timer > 0.0:
		knockback_timer -= delta
		velocity = knockback_vel
		knockback_vel = knockback_vel.move_toward(Vector2.ZERO, 420.0 * delta)
		move_and_slide()
		return

	if stun_timer > 0.0:
		stun_timer -= delta
		velocity = Vector2.ZERO
		modulate = Color(0.35, 0.85, 1.0, 0.85) if frozen else Color(0.65, 0.75, 1.0, 0.85)
		move_and_slide()
		if stun_timer <= 0.0:
			frozen = false
			modulate = Color.WHITE
			attack_cd = max(attack_cd, 0.8)
		queue_redraw()
		return

	modulate = Color.WHITE
	if attack_kind != "":
		_update_attack(delta)
		queue_redraw()
		return

	attack_cd -= delta
	if attack_cd <= 0.0 and player != null:
		_begin_next_attack()
		queue_redraw()
		return

	_hover(delta)
	queue_redraw()

func _tick_common(delta: float) -> void:
	hurt_timer = max(hurt_timer - delta, 0.0)
	parry_window = max(parry_window - delta, 0.0)
	marked_timer = max(marked_timer - delta, 0.0)
	_tick_bleed(delta)

func _tick_bleed(delta: float) -> void:
	if bleed_timer <= 0.0 or dead:
		return
	bleed_timer -= delta
	bleed_accum += delta
	if bleed_accum >= 0.5:
		bleed_accum -= 0.5
		health -= int(ceil(bleed_dps * 0.5))
		_maybe_enter_stage_two()
		if health <= 0:
			health = 0
			_die()

func _animate(delta: float) -> void:
	flap_timer -= delta
	if flap_timer > 0.0:
		return
	flap_timer = FRAME_TIME / _stage_speed()
	frame_index = (frame_index + 1) % frames.size()
	sprite.texture = frames[frame_index]
	sprite.flip_h = last_direction.x < 0.0

func _hover(delta: float) -> void:
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var to_player := player.global_position - global_position
	var target_distance := 64.0
	var direction: Vector2 = to_player.normalized() if to_player.length() > 1.0 else last_direction
	last_direction = direction
	var orbit := Vector2(-direction.y, direction.x) * sin(Time.get_ticks_msec() * 0.004 + wobble_seed) * 0.5
	if to_player.length() > target_distance:
		velocity = (direction + orbit).normalized() * move_speed * _stage_speed()
	else:
		velocity = orbit.normalized() * move_speed * 0.45 * _stage_speed()
	move_and_slide()
	global_position = _arena_clamp(global_position)

func _begin_next_attack() -> void:
	if attack_index % 2 == 0:
		_begin_circle_attack()
	else:
		_begin_cross_attack()
	attack_index += 1

func _begin_circle_attack() -> void:
	circle_target = _arena_clamp(player.global_position if player != null else global_position)
	var dir := (circle_target - global_position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	last_direction = dir
	circle_start = _arena_clamp(circle_target - dir * 90.0)
	circle_end = _arena_clamp(circle_target + dir * 90.0)
	attack_kind = "circle_windup"
	attack_duration = 1.05 / _stage_speed()
	attack_timer = attack_duration
	parry_window = attack_duration

func _begin_cross_attack() -> void:
	cross_center = _arena_clamp(player.global_position if player != null else global_position)
	attack_kind = "cross_windup"
	attack_duration = 0.88 / _stage_speed()
	attack_timer = attack_duration
	parry_window = attack_duration

func _update_attack(delta: float) -> void:
	attack_timer -= delta
	if attack_kind == "circle_windup":
		velocity = Vector2.ZERO
		move_and_slide()
		if attack_timer <= 0.0:
			_release_circle_attack()
		return
	if attack_kind == "circle_dash":
		var t: float = 1.0 - clampf(attack_timer / attack_duration, 0.0, 1.0)
		global_position = circle_start.lerp(circle_end, t)
		if attack_timer <= 0.0:
			_end_attack()
		return
	if attack_kind == "cross_windup":
		velocity = Vector2.ZERO
		move_and_slide()
		if attack_timer <= 0.0:
			_release_cross_attack()
		return
	if attack_kind == "cross_blast" and attack_timer <= 0.0:
		_end_attack()

func _release_circle_attack() -> void:
	parry_window = 0.0
	_damage_players_in_circle()
	attack_kind = "circle_dash"
	attack_duration = 0.34 / _stage_speed()
	attack_timer = attack_duration
	global_position = circle_start

func _release_cross_attack() -> void:
	parry_window = 0.0
	_damage_players_in_cross()
	attack_kind = "cross_blast"
	attack_duration = 0.22 / _stage_speed()
	attack_timer = attack_duration

func _end_attack() -> void:
	attack_kind = ""
	attack_timer = 0.0
	attack_cd = randf_range(1.05, 1.55) / _stage_speed()

func _cancel_attack() -> void:
	attack_kind = ""
	attack_timer = 0.0
	attack_cd = max(attack_cd, 0.9 / _stage_speed())

func _damage_players_in_circle() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and p.has_method("take_damage"):
			if p.global_position.distance_to(circle_target) <= circle_radius:
				p.take_damage(circle_damage + stage - 1)

func _damage_players_in_cross() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if not (is_instance_valid(p) and p.has_method("take_damage")):
			continue
		var damage_count := 0
		if _distance_to_diagonal(p.global_position, cross_center, Vector2(1, 1).normalized()) <= cross_width:
			damage_count += 1
		if _distance_to_diagonal(p.global_position, cross_center, Vector2(1, -1).normalized()) <= cross_width:
			damage_count += 1
		if damage_count > 0:
			p.take_damage(damage_count * (cross_damage + stage - 1))

func _distance_to_diagonal(point: Vector2, center: Vector2, direction: Vector2) -> float:
	var rel := point - center
	var normal := Vector2(-direction.y, direction.x)
	return abs(rel.dot(normal))

func take_damage(amount: int) -> bool:
	if dead:
		return false
	health -= amount
	_hit_feedback()
	_maybe_enter_stage_two()
	if health <= 0:
		health = 0
		_die()
		return true
	hurt_timer = 0.12
	return false

func _hit_feedback() -> void:
	var base := Vector2(body_scale, body_scale)
	sprite.scale = base * 1.22
	create_tween().tween_property(sprite, "scale", base, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sprite.self_modulate = Color(1.8, 1.8, 1.8, sprite.self_modulate.a)
	create_tween().tween_property(sprite, "self_modulate", ghost_tint if stage == 2 else tint, 0.16)

func _maybe_enter_stage_two() -> void:
	if stage == 2 or health > max_health / 2:
		return
	stage = 2
	boss_name = "GHOST OF THE WIND WRAITH"
	_apply_stage_visuals()
	attack_cd = 0.35
	_cancel_attack()

func _apply_stage_visuals() -> void:
	sprite.scale = Vector2(body_scale, body_scale)
	sprite.self_modulate = ghost_tint if stage == 2 else tint
	collision_shape.scale = Vector2.ONE

func _stage_speed() -> float:
	return 1.0 if stage == 1 else 1.55

func _die() -> void:
	dead = true
	velocity = Vector2.ZERO
	_cancel_attack()
	remove_from_group("enemies")
	collision_shape.set_deferred("disabled", true)
	sprite.self_modulate = Color(0.92, 0.82, 1.0, 0.32)
	died.emit()
	var t := create_tween()
	t.tween_property(sprite, "scale", Vector2(body_scale, body_scale) * 1.7, 0.35)
	t.parallel().tween_property(sprite, "self_modulate:a", 0.0, 0.35)
	await t.finished
	if is_instance_valid(self):
		queue_free()

func _find_player() -> void:
	if player != null and is_instance_valid(player):
		return
	player = get_tree().get_first_node_in_group("player")

func _arena_clamp(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, ARENA_MIN.x, ARENA_MAX.x), clampf(p.y, ARENA_MIN.y, ARENA_MAX.y))

func _draw() -> void:
	if marked_timer > 0.0:
		_draw_mark()
	if bleed_timer > 0.0:
		_draw_bleed()
	if frozen and stun_timer > 0.0:
		_draw_frost()
	if attack_kind.begins_with("circle"):
		_draw_circle_attack()
	elif attack_kind.begins_with("cross"):
		_draw_cross_attack()
	if stage == 2:
		_draw_ghost_aura()

func _draw_circle_attack() -> void:
	var local_target := to_local(circle_target)
	var wind := Color(0.72, 0.95, 1.0, 0.42)
	var danger := Color(1.0, 0.24, 0.48, 0.65)
	var t: float = 1.0 - clampf(attack_timer / maxf(attack_duration, 0.01), 0.0, 1.0)
	draw_arc(local_target, circle_radius, 0.0, TAU, 48, danger, 1.6, true)
	draw_arc(local_target, circle_radius * (0.55 + 0.18 * sin(t * TAU)), 0.0, TAU, 32, wind, 1.0, true)
	var dash_dir := (circle_end - circle_start).normalized()
	var side := Vector2(-dash_dir.y, dash_dir.x)
	for i in 5:
		var offset := side * float(i - 2) * 7.0
		draw_line(to_local(circle_start + offset), to_local(circle_end + offset * 0.4), wind, 1.0)
	if attack_kind == "circle_dash":
		draw_circle(local_target, circle_radius * (1.0 + t * 0.35), Color(0.95, 0.95, 1.0, 0.28 * (1.0 - t)))

func _draw_cross_attack() -> void:
	var col := Color(0.6, 0.9, 1.0, 0.5)
	var hot := Color(1.0, 0.2, 0.52, 0.7)
	var line_col: Color = hot if attack_kind == "cross_blast" else col
	var dirs := [Vector2(1, 1).normalized(), Vector2(1, -1).normalized()]
	for dir in dirs:
		var normal := Vector2(-dir.y, dir.x)
		for i in 3:
			var offset := normal * (float(i) - 1.0) * cross_width
			draw_line(to_local(cross_center - dir * 170.0 + offset), to_local(cross_center + dir * 170.0 + offset), line_col, 1.4)
	draw_circle(to_local(cross_center), 4.5, Color(0.9, 0.82, 1.0, 0.6))

func _draw_ghost_aura() -> void:
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.01)
	draw_arc(Vector2.ZERO, 22.0 + pulse * 3.0, 0.0, TAU, 32, Color(0.75, 0.5, 1.0, 0.28), 1.2, true)
	draw_arc(Vector2.ZERO, 30.0 + pulse * 5.0, 0.0, TAU, 40, Color(0.6, 0.75, 1.0, 0.18), 1.0, true)

func _draw_frost() -> void:
	var col := Color(0.6, 0.92, 1.0, 0.9)
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 8, col, 1.2)
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(dir * 8.0, dir * 18.0, col, 1.0)

func _draw_mark() -> void:
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)
	var col := Color(1.0, 0.25, 0.3, pulse)
	draw_line(Vector2(-5, -26), Vector2(0, -20), col, 1.4)
	draw_line(Vector2(5, -26), Vector2(0, -20), col, 1.4)

func _draw_bleed() -> void:
	var col := Color(0.8, 0.05, 0.08, 0.85)
	draw_circle(Vector2(-4, 9), 1.2, col)
	draw_circle(Vector2(4, 12), 1.0, col)
	draw_circle(Vector2(0, 15), 0.8, col)
