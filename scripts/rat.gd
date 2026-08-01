extends CharacterBody2D

signal died

@export var move_speed: float = 118.0
@export var dash_speed: float = 245.0
@export var detection_radius: float = 900.0
@export var nibble_range: float = 18.0
@export var nibble_damage: int = 1
@export var dash_damage: int = 1
@export var nibble_interval: float = 0.72
@export var dash_cooldown_min: float = 1.0
@export var dash_cooldown_max: float = 2.2
@export var dash_duration: float = 0.14
@export var dash_chance: float = 0.62
@export var dash_windup: float = 0.32
@export var max_health: int = 2
@export var hurt_time: float = 0.16
@export var attack_show_time: float = 0.28

@onready var anim: AnimatedSprite2D = $Anim
@onready var attack_sparkles: CPUParticles2D = $AttackSparkles

var is_boss: bool = false
var tint: Color = Color.WHITE
var body_scale: float = 0.72
var knockback_resist: float = 0.0
var score_value: int = 12

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
var dash_hit_done: bool = false

func _ready() -> void:
    add_to_group("rats")
    add_to_group("enemies")
    if is_boss:
        add_to_group("boss")
    dash_timer = randf_range(dash_cooldown_min, dash_cooldown_max)
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
    is_dashing = false
    is_winding = false
    attack_timer = 0.0
    queue_redraw()

func knockback(v: Vector2) -> void:
    if dead:
        return
    knockback_vel = v * (1.0 - knockback_resist)
    knockback_timer = 0.12 * (1.0 - knockback_resist)

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
    queue_redraw()

    if knockback_timer > 0.0:
        knockback_timer -= delta
        velocity = knockback_vel
        knockback_vel = knockback_vel.move_toward(Vector2.ZERO, 760.0 * delta)
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
        move_and_slide()
        if wind_timer <= 0.0:
            is_winding = false
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

    var direction := _chase_direction(to_player)
    _face(direction)

    if distance <= nibble_range:
        velocity = Vector2.ZERO
        _try_nibble(direction)
    else:
        velocity = direction * move_speed
        if dash_timer <= 0.0:
            dash_timer = randf_range(dash_cooldown_min, dash_cooldown_max)
            if randf() < dash_chance:
                _begin_windup((player.global_position - global_position).normalized())
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
    await get_tree().create_timer(0.55).timeout
    if is_instance_valid(self):
        queue_free()

func _find_player() -> void:
    if player != null and is_instance_valid(player):
        return
    player = get_tree().get_first_node_in_group("player")

func _face(direction: Vector2) -> void:
    if direction == Vector2.ZERO:
        return
    last_direction = direction

func _try_nibble(direction: Vector2) -> void:
    if nibble_timer > 0.0:
        return
    nibble_timer = nibble_interval
    attack_timer = attack_show_time
    _show_bite(direction)
    _bite(nibble_damage)

func _begin_windup(direction: Vector2) -> void:
    is_winding = true
    wind_timer = dash_windup
    wind_dir = direction if direction != Vector2.ZERO else last_direction

func _start_dash(direction: Vector2) -> void:
    is_dashing = true
    dash_hit_done = false
    dash_time_left = dash_duration
    dash_direction = direction if direction != Vector2.ZERO else last_direction
    _face(dash_direction)

func _run_dash(delta: float) -> void:
    dash_time_left -= delta
    velocity = dash_direction * dash_speed
    move_and_slide()

    if not dash_hit_done and player != null and global_position.distance_to(player.global_position) <= nibble_range:
        dash_hit_done = true
        _show_bite(dash_direction)
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

func _show_bite(direction: Vector2) -> void:
    var dir := direction if direction != Vector2.ZERO else last_direction
    attack_sparkles.position = dir.normalized() * nibble_range * 0.55
    attack_sparkles.rotation = dir.angle()
    attack_sparkles.restart()
    attack_sparkles.emitting = true
    queue_redraw()

func _chase_direction(to_player: Vector2) -> Vector2:
    var base := to_player.normalized() if to_player != Vector2.ZERO else last_direction
    var push := Vector2.ZERO
    for other in get_tree().get_nodes_in_group("enemies"):
        if other == self or not is_instance_valid(other):
            continue
        var away: Vector2 = global_position - other.global_position
        var distance := away.length()
        if distance > 0.0 and distance < 14.0:
            push += away.normalized() * ((14.0 - distance) / 14.0)
    var mixed := base + push * 0.35
    return mixed.normalized() if mixed != Vector2.ZERO else base

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
    if is_winding:
        var t: float = 1.0 - clamp(wind_timer / dash_windup, 0.0, 1.0)
        var reach: float = dash_speed * dash_duration
        var col := Color(1.0, 0.15, 0.15, 0.45 + 0.45 * t)
        var tip: Vector2 = wind_dir * reach
        var side := Vector2(-wind_dir.y, wind_dir.x) * nibble_range
        draw_line(side * 0.45, tip + side * 0.45, col, 1.2)
        draw_line(-side * 0.45, tip - side * 0.45, col, 1.2)
        draw_arc(tip, nibble_range, 0.0, TAU, 24, col, 1.4, true)
        draw_circle(Vector2.ZERO, 1.5 + 1.5 * t, Color(1.0, 0.1, 0.1, 0.85))
    if attack_timer > 0.0:
        var a: float = clamp(attack_timer / attack_show_time, 0.0, 1.0)
        draw_arc(Vector2.ZERO, nibble_range, 0.0, TAU, 24, Color(1.0, 0.85, 0.35, 0.15 + 0.5 * a), 1.3, true)
