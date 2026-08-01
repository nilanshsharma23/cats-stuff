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

# How this rat fights:
#   chaser     - beelines at you (base rat).
#   skirmisher - orbits at preferred_range, darts in to poke, then peels away.
#   bruiser    - slow, no retreat, shrugs off knockback; a walking wall.
@export var behavior: String = "chaser"
@export var preferred_range: float = 42.0
@export var summon_on_enrage: int = 2

@onready var anim: AnimatedSprite2D = $Anim
@onready var attack_sparkles: CPUParticles2D = $AttackSparkles

const RAT_SCENE: PackedScene = preload("res://scenes/rat.tscn")

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
var parry_window: float = 0.0
var frozen: bool = false
var marked_timer: float = 0.0
var bleed_timer: float = 0.0
var bleed_accum: float = 0.0
var bleed_dps: float = 0.0
var attack_lock: float = 0.0
var strafe_sign: float = 1.0
var retreat_timer: float = 0.0
var recover_timer: float = 0.0
var boss_combo_left: int = 0
var enraged: bool = false

func _ready() -> void:
    add_to_group("rats")
    add_to_group("enemies")
    if is_boss:
        add_to_group("boss")
    strafe_sign = 1.0 if randf() < 0.5 else -1.0
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

# The window during which a well-timed player dash can freeze this enemy,
# open only while an attack tell is on screen.
func is_parryable() -> bool:
    return parry_window > 0.0 and not dead

func freeze(duration: float) -> void:
    if dead:
        return
    frozen = true
    stun_timer = max(stun_timer, duration)
    parry_window = 0.0
    is_dashing = false
    is_winding = false
    attack_timer = 0.0
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
    parry_window = max(parry_window - delta, 0.0)
    marked_timer = max(marked_timer - delta, 0.0)
    attack_lock = max(attack_lock - delta, 0.0)
    retreat_timer = max(retreat_timer - delta, 0.0)
    recover_timer = max(recover_timer - delta, 0.0)
    _tick_bleed(delta)
    if dead:
        return
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
            attack_lock = max(attack_lock, 1.0)
        return
    modulate = Color.WHITE
    frozen = false

    if hurt_timer > 0.0:
        velocity = Vector2.ZERO
        _play("hurt_" + _facing())
        move_and_slide()
        return

    # Boss recovery: after a dash flurry the Rat King is winded and wide open.
    if recover_timer > 0.0:
        velocity = Vector2.ZERO
        _play("idle_" + _facing())
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

    var aim := to_player.normalized() if to_player != Vector2.ZERO else last_direction
    _face(aim)
    var direction := _separate(_behavior_dir(aim, distance))

    var can_act := attack_lock <= 0.0
    if distance <= nibble_range and can_act and retreat_timer <= 0.0:
        velocity = Vector2.ZERO
        _try_nibble(aim)
        if behavior == "skirmisher":
            retreat_timer = 0.75   # hit and run: poke, then create space
    else:
        velocity = direction * move_speed
        if can_act and dash_timer <= 0.0:
            dash_timer = randf_range(dash_cooldown_min, dash_cooldown_max)
            if randf() < dash_chance:
                if is_boss:
                    boss_combo_left = 3 if enraged else 2   # multi-dash flurry
                _begin_windup(aim)
                return

    _update_animation()
    move_and_slide()

func take_damage(amount: int) -> bool:
    if dead:
        return false
    health -= amount
    _hit_feedback()
    if health <= 0:
        health = 0
        _die()
        return true
    # The Rat King has hyper-armor: it won't flinch out of its own attacks
    # (only a parry-freeze or leer-stun stops it), so you can't cheese it by
    # mashing. Basics still get staggered.
    if is_boss:
        if not enraged and health <= max_health / 2:
            _boss_enrage()
    else:
        hurt_timer = hurt_time
        is_dashing = false
        is_winding = false
        attack_timer = 0.0
        boss_combo_left = 0
    queue_redraw()
    return false

func _boss_enrage() -> void:
    enraged = true
    move_speed *= 1.28
    dash_speed *= 1.12
    dash_chance = minf(dash_chance + 0.2, 1.0)
    dash_cooldown_min = maxf(dash_cooldown_min * 0.6, 0.4)
    dash_cooldown_max = maxf(dash_cooldown_max * 0.6, 0.9)
    nibble_interval = maxf(nibble_interval * 0.7, 0.32)
    tint = Color(1.0, 0.35, 0.3)
    anim.self_modulate = tint
    _boss_summon(summon_on_enrage)

# Enrage adds: a couple of fast skirmisher rats to split the player's attention.
func _boss_summon(count: int) -> void:
    var parent := get_parent()
    if parent == null:
        return
    for i in count:
        var minion: Node2D = RAT_SCENE.instantiate() as Node2D
        if minion == null:
            continue
        if minion.has_method("configure"):
            minion.configure({
                "max_health": 3, "move_speed": 150.0, "behavior": "skirmisher",
                "preferred_range": 40.0, "dash_chance": 0.7,
                "dash_cooldown_min": 0.9, "dash_cooldown_max": 1.6,
                "body_scale": 0.58, "tint": Color(1.0, 0.55, 0.5), "score_value": 12,
            })
        var ang := randf() * TAU
        minion.global_position = global_position + Vector2(cos(ang), sin(ang)) * randf_range(22.0, 36.0)
        parent.add_child(minion)
        if minion.has_signal("died") and parent.has_method("_on_enemy_died"):
            minion.connect("died", Callable(parent, "_on_enemy_died").bind(minion), CONNECT_ONE_SHOT)

func _hit_feedback() -> void:
    var base := Vector2(body_scale, body_scale)
    anim.scale = base * 1.28
    create_tween().tween_property(anim, "scale", base, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    anim.self_modulate = Color(1.7, 1.7, 1.7)
    create_tween().tween_property(anim, "self_modulate", tint, 0.14)

func _die() -> void:
    dead = true
    velocity = Vector2.ZERO
    is_dashing = false
    is_winding = false
    modulate = Color.WHITE
    queue_redraw()
    remove_from_group("enemies")
    $CollisionShape2D.set_deferred("disabled", true)
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
    if direction == Vector2.ZERO:
        return
    last_direction = direction

func _try_nibble(direction: Vector2) -> void:
    if nibble_timer > 0.0:
        return
    nibble_timer = nibble_interval
    attack_timer = attack_show_time
    parry_window = 0.5
    _show_bite(direction)
    _bite(nibble_damage)

func _begin_windup(direction: Vector2) -> void:
    is_winding = true
    wind_timer = dash_windup
    parry_window = 0.5
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
        if is_boss and boss_combo_left > 1:
            boss_combo_left -= 1
            var next_dir: Vector2 = (player.global_position - global_position).normalized() if player != null else dash_direction
            _begin_windup(next_dir)
        else:
            boss_combo_left = 0
            dash_timer = randf_range(dash_cooldown_min, dash_cooldown_max)
            if is_boss:
                recover_timer = 0.8   # winded and punishable after the flurry
                attack_lock = max(attack_lock, 0.8)

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

# Pick a heading based on this rat's fighting style. Skirmishers keep their
# distance and orbit; chasers/bruisers press in (chasers fan out a little so a
# pack surrounds you rather than stacking into a single conga line).
func _behavior_dir(aim: Vector2, distance: float) -> Vector2:
    if behavior == "skirmisher":
        var strafe := Vector2(-aim.y, aim.x) * strafe_sign
        if retreat_timer > 0.0 or distance < preferred_range - 6.0:
            return (-aim * 0.85 + strafe * 0.55).normalized()
        if distance > preferred_range + 10.0:
            return (aim * 0.9 + strafe * 0.3).normalized()
        return strafe
    var lateral := Vector2(-aim.y, aim.x) * strafe_sign * (0.2 if behavior == "chaser" else 0.0)
    var d := aim + lateral
    return d.normalized() if d != Vector2.ZERO else aim

# Soft crowd separation so rats don't pile into a single point.
func _separate(base_dir: Vector2) -> Vector2:
    var push := Vector2.ZERO
    for other in get_tree().get_nodes_in_group("enemies"):
        if other == self or not is_instance_valid(other):
            continue
        var away: Vector2 = global_position - other.global_position
        var distance := away.length()
        if distance > 0.0 and distance < 14.0:
            push += away.normalized() * ((14.0 - distance) / 14.0)
    var mixed := base_dir + push * 0.35
    return mixed.normalized() if mixed != Vector2.ZERO else base_dir

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
    if frozen and stun_timer > 0.0:
        _draw_frost()
    if is_marked():
        _draw_mark()
    if bleed_timer > 0.0:
        _draw_bleed()

func _draw_bleed() -> void:
    var col := Color(0.8, 0.05, 0.08, 0.85)
    draw_circle(Vector2(-2, 3), 1.1, col)
    draw_circle(Vector2(2.5, 5), 0.9, col)
    draw_circle(Vector2(0, 6.5), 0.7, col)

func _draw_frost() -> void:
    var col := Color(0.6, 0.92, 1.0, 0.9)
    draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 6, col, 1.3)
    for i in 6:
        var ang: float = TAU * float(i) / 6.0
        var dir := Vector2(cos(ang), sin(ang))
        draw_line(dir * 4.0, dir * 9.0, col, 1.0)

func _draw_mark() -> void:
    var pulse: float = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)
    var col := Color(1.0, 0.25, 0.3, pulse)
    var top := Vector2(0, -12)
    draw_line(top + Vector2(-2.5, -3.5), top, col, 1.2)
    draw_line(top + Vector2(2.5, -3.5), top, col, 1.2)
