extends CharacterBody2D

signal died

@export var move_speed: float = 86.0
@export var detection_radius: float = 900.0
@export var croak_range: float = 42.0
@export var aoe_radius: float = 28.0
@export var aoe_damage: int = 1
@export var croak_cooldown: float = 1.8
@export var croak_windup: float = 0.55
@export var max_health: int = 3
@export var hurt_time: float = 0.22

@onready var anim: AnimatedSprite2D = $Anim
@onready var aoe: CPUParticles2D = $Aoe

var is_boss: bool = false
var tint: Color = Color.WHITE
var body_scale: float = 0.72
var knockback_resist: float = 0.0
var score_value: int = 18

var player: Node2D = null
var last_direction: Vector2 = Vector2.DOWN
var health: int = max_health
var dead: bool = false
var croak_cd: float = 0.0
var croak_timer: float = 0.0
var is_croaking: bool = false
var hurt_timer: float = 0.0
var stun_timer: float = 0.0
var knockback_vel: Vector2 = Vector2.ZERO
var knockback_timer: float = 0.0
var parry_window: float = 0.0
var frozen: bool = false

func _ready() -> void:
    add_to_group("frogs")
    add_to_group("enemies")
    if is_boss:
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
    is_croaking = false
    queue_redraw()

# Open only while the croak wind-up tell is on screen; a dash in that
# window freezes the frog.
func is_parryable() -> bool:
    return parry_window > 0.0 and not dead

func freeze(duration: float) -> void:
    if dead:
        return
    frozen = true
    stun_timer = max(stun_timer, duration)
    parry_window = 0.0
    is_croaking = false
    velocity = Vector2.ZERO
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
    croak_cd = max(croak_cd - delta, 0.0)
    hurt_timer = max(hurt_timer - delta, 0.0)
    parry_window = max(parry_window - delta, 0.0)
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
        modulate = Color(0.35, 0.85, 1.0) if frozen else Color(0.55, 0.75, 1.0)
        _play("idle_" + _facing())
        move_and_slide()
        if stun_timer <= 0.0:
            modulate = Color.WHITE
            frozen = false
        return
    modulate = Color.WHITE
    frozen = false

    if hurt_timer > 0.0:
        velocity = Vector2.ZERO
        _play("hurt_" + _facing())
        move_and_slide()
        return

    if is_croaking:
        velocity = Vector2.ZERO
        croak_timer -= delta
        _play("croak_" + _facing())
        if croak_timer <= 0.0:
            _release_aoe()
            is_croaking = false
            queue_redraw()
        move_and_slide()
        return

    if player == null:
        velocity = Vector2.ZERO
        _play("idle_" + _facing())
        move_and_slide()
        return

    var to_player: Vector2 = player.global_position - global_position
    var distance: float = to_player.length()

    if distance > detection_radius:
        velocity = Vector2.ZERO
        _play("idle_" + _facing())
        move_and_slide()
        return

    var direction := _chase_direction(to_player)
    _face(direction)

    if distance <= croak_range:
        velocity = Vector2.ZERO
        if croak_cd <= 0.0:
            is_croaking = true
            croak_timer = croak_windup
            croak_cd = croak_cooldown
            parry_window = 0.5
            _play("croak_" + _facing())
        else:
            _play("idle_" + _facing())
    else:
        velocity = direction * move_speed
        _play("walk_" + _facing())

    move_and_slide()

func _release_aoe() -> void:
    aoe.restart()
    aoe.emitting = true
    for p in get_tree().get_nodes_in_group("player"):
        if is_instance_valid(p) and p.has_method("take_damage"):
            if global_position.distance_to(p.global_position) <= aoe_radius:
                p.take_damage(aoe_damage)

func take_damage(amount: int) -> bool:
    if dead:
        return false
    health -= amount
    _hit_feedback()
    if health <= 0:
        health = 0
        _die()
        return true
    hurt_timer = hurt_time
    is_croaking = false
    queue_redraw()
    return false

func _hit_feedback() -> void:
    var base := Vector2(body_scale, body_scale)
    anim.scale = base * 1.28
    create_tween().tween_property(anim, "scale", base, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    anim.self_modulate = Color(1.7, 1.7, 1.7)
    create_tween().tween_property(anim, "self_modulate", tint, 0.14)

func _die() -> void:
    dead = true
    velocity = Vector2.ZERO
    is_croaking = false
    modulate = Color.WHITE
    queue_redraw()
    remove_from_group("enemies")
    $CollisionShape2D.set_deferred("disabled", true)
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
    if direction == Vector2.ZERO:
        return
    last_direction = direction

func _chase_direction(to_player: Vector2) -> Vector2:
    var base := to_player.normalized() if to_player != Vector2.ZERO else last_direction
    var push := Vector2.ZERO
    for other in get_tree().get_nodes_in_group("enemies"):
        if other == self or not is_instance_valid(other):
            continue
        var away: Vector2 = global_position - other.global_position
        var distance := away.length()
        if distance > 0.0 and distance < 16.0:
            push += away.normalized() * ((16.0 - distance) / 16.0)
    var mixed := base + push * 0.3
    return mixed.normalized() if mixed != Vector2.ZERO else base

func _facing() -> String:
    if abs(last_direction.x) >= abs(last_direction.y):
        anim.flip_h = last_direction.x > 0.0
        return "side"
    anim.flip_h = false
    return "front" if last_direction.y > 0.0 else "back"

func _play(name: String) -> void:
    if anim.animation != name:
        anim.play(name)

func _draw() -> void:
    if frozen and stun_timer > 0.0:
        _draw_frost()
        return
    if not is_croaking:
        return
    var t: float = 1.0 - clamp(croak_timer / croak_windup, 0.0, 1.0)
    var r: float = aoe_radius * (0.35 + 0.65 * t)
    var a: float = 0.22 + 0.4 * t
    draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0.3, 1.0, 0.45, a), 1.5, true)
    draw_arc(Vector2.ZERO, r * 0.6, 0.0, TAU, 28, Color(0.55, 1.0, 0.6, a * 0.55), 1.0, true)

func _draw_frost() -> void:
    var col := Color(0.6, 0.92, 1.0, 0.9)
    draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 6, col, 1.3)
    for i in 6:
        var ang: float = TAU * float(i) / 6.0
        var dir := Vector2(cos(ang), sin(ang))
        draw_line(dir * 4.0, dir * 9.0, col, 1.0)
