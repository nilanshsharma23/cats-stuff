extends CharacterBody2D

signal died

@export var move_speed: float = 58.0
@export var max_health: int = 62
@export var body_scale: float = 1.65
@export var tint: Color = Color(0.56, 1.0, 0.5, 1.0)
@export var hop_damage: int = 2
@export var hop_knockback: float = 360.0
@export var hop_radius: float = 24.0
@export var aoe_damage: int = 1
@export var aoe_radius: float = 56.0
@export var score_value: int = 760
@export var summon_cooldown: float = 5.8
@export var max_minions: int = 3

@onready var anim: AnimatedSprite2D = $Anim
@onready var aoe: CPUParticles2D = $Aoe
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

const ARENA_MIN := Vector2(28, 24)
const ARENA_MAX := Vector2(228, 120)
const FROG_SCENE: PackedScene = preload("res://scenes/frog.tscn")

# How long before impact a dash-parry still connects.
const PARRY_WINDOW: float = 0.2

var boss_name: String = "THE BOG BARON"
var player: Node2D = null
var health: int = max_health
var dead: bool = false
var last_direction: Vector2 = Vector2.DOWN
var attack_cd: float = 1.0
var attack_kind: String = ""
var attack_timer: float = 0.0
var attack_duration: float = 1.0
var attack_index: int = 0
var summon_cd: float = 2.8
var hop_start: Vector2 = Vector2.ZERO
var hop_target: Vector2 = Vector2.ZERO
var stun_timer: float = 0.0
var frozen: bool = false
var marked_timer: float = 0.0
var bleed_timer: float = 0.0
var bleed_accum: float = 0.0
var bleed_dps: float = 0.0
var hurt_timer: float = 0.0
var knockback_vel: Vector2 = Vector2.ZERO
var knockback_timer: float = 0.0

func _ready() -> void:
	# Opt back into pausing (the level root is PROCESS_MODE_ALWAYS).
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("frogs")
	add_to_group("enemies")
	add_to_group("boss")
	health = max_health
	anim.scale = Vector2(body_scale, body_scale)
	anim.self_modulate = tint

func configure(cfg: Dictionary) -> void:
	for key in cfg:
		set(key, cfg[key])

func stun(duration: float) -> void:
	if dead:
		return
	stun_timer = max(stun_timer, duration)
	_cancel_attack()
	queue_redraw()

# Deflectable only in the last beat of a wind-up, not for its whole duration.
func is_parryable() -> bool:
	return attack_kind.ends_with("_windup") and attack_timer <= PARRY_WINDOW and not dead

func freeze(duration: float) -> void:
	if dead:
		return
	frozen = true
	stun_timer = max(stun_timer, duration)
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
	knockback_vel = v * 0.12
	knockback_timer = 0.06

func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_find_player()
	_tick_common(delta)
	if dead:
		return

	if knockback_timer > 0.0:
		knockback_timer -= delta
		velocity = knockback_vel
		knockback_vel = knockback_vel.move_toward(Vector2.ZERO, 520.0 * delta)
		move_and_slide()
		return

	if stun_timer > 0.0:
		stun_timer -= delta
		velocity = Vector2.ZERO
		modulate = Color(0.35, 0.85, 1.0) if frozen else Color(0.55, 0.75, 1.0)
		_play("idle_" + _facing())
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

	_chase(delta)
	queue_redraw()

func _tick_common(delta: float) -> void:
	hurt_timer = max(hurt_timer - delta, 0.0)
	marked_timer = max(marked_timer - delta, 0.0)
	summon_cd = max(summon_cd - delta, 0.0)
	_tick_bleed(delta)

func _tick_bleed(delta: float) -> void:
	if bleed_timer <= 0.0 or dead:
		return
	bleed_timer -= delta
	bleed_accum += delta
	if bleed_accum >= 0.5:
		bleed_accum -= 0.5
		health -= int(ceil(bleed_dps * 0.5))
		if health <= 0:
			health = 0
			_die()

func _chase(_delta: float) -> void:
	if player == null:
		velocity = Vector2.ZERO
		_play("idle_" + _facing())
		move_and_slide()
		return
	var to_player := player.global_position - global_position
	var direction: Vector2 = to_player.normalized() if to_player.length() > 1.0 else last_direction
	_face(direction)
	if to_player.length() > 46.0:
		velocity = direction * move_speed
		_play("walk_" + _facing())
	else:
		velocity = Vector2.ZERO
		_play("idle_" + _facing())
	move_and_slide()
	global_position = _arena_clamp(global_position)

func _begin_next_attack() -> void:
	if summon_cd <= 0.0 and _summoned_count() < max_minions:
		_begin_summon_attack()
	elif attack_index % 2 == 0:
		_begin_hop_attack()
	else:
		_begin_aoe_attack()
	attack_index += 1

func _begin_hop_attack() -> void:
	hop_start = global_position
	hop_target = _arena_clamp(player.global_position if player != null else global_position)
	_face(hop_target - global_position)
	attack_kind = "hop_windup"
	attack_duration = 0.78
	attack_timer = attack_duration
	_play("croak_" + _facing())

func _begin_aoe_attack() -> void:
	attack_kind = "aoe_windup"
	attack_duration = 0.86
	attack_timer = attack_duration
	_play("croak_" + _facing())

func _begin_summon_attack() -> void:
	attack_kind = "summon_windup"
	attack_duration = 0.72
	attack_timer = attack_duration
	_play("croak_" + _facing())

func _update_attack(delta: float) -> void:
	attack_timer -= delta
	if attack_kind == "hop_windup":
		velocity = Vector2.ZERO
		move_and_slide()
		if attack_timer <= 0.0:
			_release_hop()
		return
	if attack_kind == "hop_air":
		var t: float = 1.0 - clampf(attack_timer / attack_duration, 0.0, 1.0)
		var height: float = sin(t * PI) * 28.0
		global_position = hop_start.lerp(hop_target, t)
		anim.position.y = -height
		if attack_timer <= 0.0:
			anim.position = Vector2.ZERO
			_land_hop()
		return
	if attack_kind == "summon_windup":
		velocity = Vector2.ZERO
		move_and_slide()
		if attack_timer <= 0.0:
			_release_summon()
		return
	if attack_kind == "aoe_windup":
		velocity = Vector2.ZERO
		move_and_slide()
		if attack_timer <= 0.0:
			_release_aoe()
		return
	if attack_kind == "recover" and attack_timer <= 0.0:
		_end_attack()

func _release_summon() -> void:
	_spawn_minion()
	summon_cd = summon_cooldown
	attack_kind = "recover"
	attack_duration = 0.32
	attack_timer = attack_duration

func _summoned_count() -> int:
	var count: int = 0
	for f in get_tree().get_nodes_in_group("frog_boss_minion"):
		if is_instance_valid(f):
			count += 1
	return count

func _spawn_minion() -> void:
	if get_parent() == null or _summoned_count() >= max_minions:
		return
	var minion: Node2D = FROG_SCENE.instantiate() as Node2D
	if minion == null:
		return
	if minion.has_method("configure"):
		minion.configure({"max_health": 2, "move_speed": 74.0, "aoe_damage": 1, "croak_cooldown": 2.0, "body_scale": 0.58, "tint": Color(0.72, 1.0, 0.58, 1.0), "score_value": 12})
	minion.add_to_group("frog_boss_minion")
	minion.global_position = _summon_point()
	get_parent().add_child(minion)
	if minion.has_signal("died") and get_parent().has_method("_on_enemy_died"):
		minion.connect("died", Callable(get_parent(), "_on_enemy_died").bind(minion), CONNECT_ONE_SHOT)

func _summon_point() -> Vector2:
	var angle: float = randf() * TAU
	for i in 8:
		var dir: Vector2 = Vector2(cos(angle), sin(angle))
		var p: Vector2 = _arena_clamp(global_position + dir * randf_range(24.0, 42.0))
		if player == null or p.distance_to(player.global_position) > 28.0:
			return p
		angle += PI * 0.35
	return _arena_clamp(global_position + Vector2.RIGHT * 32.0)

func _release_hop() -> void:
	attack_kind = "hop_air"
	attack_duration = 0.28
	attack_timer = attack_duration
	_play("walk_" + _facing())

func _land_hop() -> void:
	_damage_players_near(global_position, hop_radius, hop_damage, hop_knockback)
	aoe.position = Vector2.ZERO
	aoe.restart()
	aoe.emitting = true
	attack_kind = "recover"
	attack_duration = 0.22
	attack_timer = attack_duration
	_play("idle_" + _facing())

func _release_aoe() -> void:
	_damage_players_near(global_position, aoe_radius, aoe_damage, 240.0)
	aoe.position = Vector2.ZERO
	aoe.restart()
	aoe.emitting = true
	attack_kind = "recover"
	attack_duration = 0.28
	attack_timer = attack_duration

func _damage_players_near(center: Vector2, radius: float, damage: int, shove_strength: float) -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if not (is_instance_valid(p) and p.has_method("take_damage")):
			continue
		var away: Vector2 = p.global_position - center
		if away.length() <= radius:
			p.take_damage(damage)
			var shove: Vector2 = away.normalized() if away != Vector2.ZERO else Vector2.RIGHT
			if p.has_method("enemy_knockback"):
				p.enemy_knockback(shove * shove_strength)

func _end_attack() -> void:
	attack_kind = ""
	attack_timer = 0.0
	attack_cd = randf_range(0.95, 1.45)

func _cancel_attack() -> void:
	attack_kind = ""
	attack_timer = 0.0
	anim.position = Vector2.ZERO
	attack_cd = max(attack_cd, 0.8)

func take_damage(amount: int) -> bool:
	if dead:
		return false
	health -= amount
	_hit_feedback()
	if health <= 0:
		health = 0
		_die()
		return true
	hurt_timer = 0.14
	return false

func _hit_feedback() -> void:
	var base := Vector2(body_scale, body_scale)
	anim.scale = base * 1.16
	create_tween().tween_property(anim, "scale", base, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	anim.self_modulate = Color(1.8, 1.8, 1.8)
	create_tween().tween_property(anim, "self_modulate", tint, 0.16)

func _die() -> void:
	dead = true
	velocity = Vector2.ZERO
	_cancel_attack()
	remove_from_group("enemies")
	collision_shape.set_deferred("disabled", true)
	if has_node("DeathBurst"):
		var burst: CPUParticles2D = $DeathBurst
		burst.restart()
		burst.emitting = true
	_play("death_" + _facing())
	died.emit()
	await get_tree().create_timer(0.55, true, false, true).timeout
	if is_instance_valid(self):
		queue_free()

func _find_player() -> void:
	if player != null and is_instance_valid(player):
		return
	player = get_tree().get_first_node_in_group("player")

func _face(direction: Vector2) -> void:
	if direction != Vector2.ZERO:
		last_direction = direction

func _facing() -> String:
	if abs(last_direction.x) >= abs(last_direction.y):
		anim.flip_h = last_direction.x > 0.0
		return "side"
	anim.flip_h = false
	return "front" if last_direction.y > 0.0 else "back"

func _play(anim_name: String) -> void:
	if anim.animation != anim_name:
		anim.play(anim_name)

func _arena_clamp(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, ARENA_MIN.x, ARENA_MAX.x), clampf(p.y, ARENA_MIN.y, ARENA_MAX.y))

func _draw() -> void:
	if attack_kind == "hop_windup" or attack_kind == "hop_air":
		_draw_hop_tell()
	if attack_kind == "aoe_windup" or attack_kind == "recover":
		_draw_aoe_tell()
	if attack_kind == "summon_windup":
		_draw_summon_tell()
	if frozen and stun_timer > 0.0:
		_draw_frost()
	if is_marked():
		_draw_mark()
	if bleed_timer > 0.0:
		_draw_bleed()

func _draw_hop_tell() -> void:
	var t: float = 1.0 - clampf(attack_timer / maxf(attack_duration, 0.01), 0.0, 1.0)
	var target := to_local(hop_target)
	var ring := Color(0.75, 1.0, 1.0, 0.95) if is_parryable() else Color(1.0, 0.28, 0.2, 0.62)
	draw_arc(target, hop_radius, 0.0, TAU, 36, ring, 2.2 if is_parryable() else 1.6, true)
	draw_circle(target, hop_radius * (0.18 + 0.12 * sin(t * TAU)), Color(0.55, 1.0, 0.48, 0.35))
	draw_line(Vector2.ZERO, target, Color(0.55, 1.0, 0.48, 0.28), 1.0)

func _draw_summon_tell() -> void:
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.014)
	draw_arc(Vector2.ZERO, 30.0 + pulse * 5.0, 0.0, TAU, 34, Color(0.45, 1.0, 0.34, 0.45), 1.3, true)
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 24, Color(0.85, 1.0, 0.4, 0.35), 1.0, true)

func _draw_aoe_tell() -> void:
	var t: float = 1.0 - clampf(attack_timer / maxf(attack_duration, 0.01), 0.0, 1.0)
	var hot := Color(0.75, 1.0, 1.0, 0.95) if is_parryable() else Color(0.25, 1.0, 0.42, 0.45 + 0.28 * t)
	draw_arc(Vector2.ZERO, aoe_radius, 0.0, TAU, 56, hot, 2.2 if is_parryable() else 1.8, true)
	draw_arc(Vector2.ZERO, aoe_radius * 0.58, 0.0, TAU, 38, Color(0.8, 1.0, 0.4, 0.35), 1.1, true)

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
