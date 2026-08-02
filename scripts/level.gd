extends Node2D

const UI_FONT: FontFile = preload("res://fonts/Pixellari.ttf")
const SPAWN_MARKER: GDScript = preload("res://scripts/spawn_marker.gd")
const PICKUP: GDScript = preload("res://scripts/pickup.gd")
const VIGNETTE: GDScript = preload("res://scripts/vignette.gd")
const NEON_SHADER: Shader = preload("res://shaders/neon.gdshader")
const PLAN_MARKER: GDScript = preload("res://scripts/plan_marker.gd")

# --- OVERDRIVE: the boss-only ultimate --------------------------------------
#
# Costs a full SS style meter and only exists during a boss fight. Stops the
# world for PLAN_SECONDS while the player choreographs a combo, then replays it
# for real in EXEC_SECONDS. The whole arena grades to neon while it runs.
const PLAN_SECONDS: float = 5.0
const EXEC_SECONDS: float = 1.5
const ULT_STYLE_COST: float = 560.0

@export var level_id: int = 1
@export var next_level_path: String = ""
@export var rat_scene: PackedScene
@export var frog_scene: PackedScene
@export var frog_boss_scene: PackedScene
@export var pigeon_boss_scene: PackedScene

@onready var game_over: Control = $UI/GameOver
@onready var banner: Label = $UI/Banner

# Enemy roster. Each entry names a base scene ("rat"/"frog"/"frog_boss"/"pigeon_boss") and a config
# dictionary applied on spawn (stats + tint + scale), so the two sprite rigs
# yield a whole cast of distinct foes.
var ROSTER := {
	"rat": {
		"scene": "rat",
		"cfg": {"max_health": 4, "move_speed": 112.0, "nibble_damage": 1,
			"tint": Color(1, 1, 1), "body_scale": 0.72, "score_value": 16}
	},
	"scurrier": {
		"scene": "rat",
		"cfg": {"max_health": 3, "move_speed": 142.0, "nibble_damage": 1,
			"behavior": "skirmisher", "preferred_range": 44.0,
			"dash_chance": 0.72, "dash_cooldown_min": 0.95, "dash_cooldown_max": 1.7,
			"tint": Color(0.72, 1.0, 0.55), "body_scale": 0.6, "score_value": 14}
	},
	"brute": {
		"scene": "rat",
		"cfg": {"max_health": 8, "move_speed": 68.0, "nibble_damage": 2, "dash_damage": 2,
			"behavior": "bruiser", "nibble_range": 23.0, "nibble_windup": 0.38, "dash_chance": 0.36,
			"knockback_resist": 0.66,
			"tint": Color(1.0, 0.5, 0.42), "body_scale": 1.08, "score_value": 42}
	},
	"frog": {
		"scene": "frog",
		"cfg": {"max_health": 5, "move_speed": 86.0, "aoe_damage": 1, "croak_cooldown": 2.1, "croak_range": 32.0, "bloodlust_speed_mul": 1.48,
			"hop_cooldown": 1.2, "hop_chance": 0.7, "hop_distance": 31.0,
			"tint": Color(1, 1, 1), "body_scale": 0.72, "score_value": 26}
	},
	"spitter": {
		"scene": "frog",
		"cfg": {"max_health": 5, "move_speed": 90.0, "croak_cooldown": 1.55, "bloodlust_speed_mul": 1.28,
			"behavior": "kiter", "croak_range": 54.0, "aoe_radius": 32.0, "croak_windup": 0.5,
			"hop_cooldown": 0.92, "hop_chance": 0.85, "hop_distance": 38.0, "hop_alert_range": 56.0,
			"tint": Color(0.5, 0.82, 1.0), "body_scale": 0.7, "score_value": 34}
	},
	"boss": {
		"scene": "rat",
		"cfg": {"is_boss": true, "max_health": 64, "move_speed": 86.0,
			"nibble_damage": 2, "nibble_range": 30.0, "nibble_interval": 0.55, "nibble_windup": 0.22,
			"dash_chance": 0.9, "dash_windup": 0.52, "dash_speed": 286.0,
			"dash_cooldown_min": 1.0, "dash_cooldown_max": 1.8,
			"knockback_resist": 0.9, "tint": Color(0.85, 0.4, 1.0),
			"body_scale": 2.3, "score_value": 600}
	},
	"frog_boss": {
		"scene": "frog_boss",
		"cfg": {"is_boss": true, "max_health": 84, "move_speed": 62.0,
			"hop_damage": 2, "hop_knockback": 400.0, "hop_radius": 26.0,
			"aoe_damage": 1, "aoe_radius": 56.0, "tint": Color(0.56, 1.0, 0.5, 1.0),
			"body_scale": 1.65, "score_value": 760}
	},
	"pigeon_boss": {
		"scene": "pigeon_boss",
		"cfg": {"is_boss": true, "max_health": 104, "move_speed": 60.0,
			"circle_radius": 36.0, "cross_width": 13.0, "circle_damage": 1,
			"cross_damage": 1, "tint": Color(1.0, 1.0, 1.0, 1.0),
			"body_scale": 0.14, "score_value": 900}
	},
}

const BOSS_NAME := "THE RAT KING"

# Difficulty. Rather than one blunt HP multiplier, each mode moves the knobs
# that actually decide whether a fight feels fair: how long a telegraph is
# readable for, how forgiving the parry timing is, and how often the game hands
# you a heart when you are hurting. Hell pays better because it should.
const DIFFICULTIES := [
	{"name": "EASY", "blurb": "Slower foes, long tells, generous hearts.",
		"colour": Color(0.5, 1.0, 0.62),
		"enemy_hp": 0.76, "enemy_speed": 0.9, "windup": 1.4, "parry": 0.28,
		"drop": 1.7, "bonus_hp": 3, "coin": 0.85, "ramp": 0.6, "dodge": 0.65},
	{"name": "MEDIUM", "blurb": "The fight as intended.",
		"colour": Color(1.0, 0.84, 0.35),
		"enemy_hp": 1.0, "enemy_speed": 1.0, "windup": 1.0, "parry": 0.18,
		"drop": 1.0, "bonus_hp": 0, "coin": 1.0, "ramp": 1.0, "dodge": 1.0},
	{"name": "HELL", "blurb": "Fast, brutal, barely any mercy. Pays best.",
		"colour": Color(1.0, 0.3, 0.35),
		"enemy_hp": 1.32, "enemy_speed": 1.12, "windup": 0.78, "parry": 0.12,
		"drop": 0.5, "bonus_hp": -2, "coin": 1.35, "ramp": 1.4, "dodge": 1.18},
]

var difficulty: int = 1

func _diff() -> Dictionary:
	return DIFFICULTIES[clampi(difficulty, 0, DIFFICULTIES.size() - 1)]

var waves: Array = []
var wave_index: int = -1
var cleared: bool = false
var boss_active: bool = false
var rng := RandomNumberGenerator.new()
var score: int = 0
var kills: int = 0
var best_record: int = 0
var coins: int = 0
var glare_level: int = 1
var style_meter: float = 0.0
var style_timeout: float = 0.0
var no_glare_chain: int = 0
var profile_saved: bool = false
var tutorial_enabled: bool = false
var tutorial_step: int = 0
var endless: bool = false
var pending_spawns: int = 0
var best_chain: int = 0
var kills_since_heart: int = 0
var last_earned: int = 0
var result_path: String = ""
var reward_timer: float = 0.0
var hitstop_id: int = 0
var hitstop_pending: int = 0

var wave_label: Label
var enemies_label: Label
var score_label: Label
var combo_label: Label
var reward_label: Label
var result_title: Label
var result_summary: Label
var result_continue: Button
var result_retry: Button
var result_shop: Button
var result_menu: Button
var tutorial_panel: Control
var tutorial_text: Label
var shop_panel: Control
var shop_text: Label
var shop_status: Label
var upgrade_button: Button
var boss_panel: Control
var boss_name_label: Label
var boss_fill: ColorRect
var boss_bar_width: float = 188.0
var ability_panel: HBoxContainer
var ability_slots: Dictionary = {}
var hud_panel: ColorRect
var score_panel: ColorRect
# Base render resolution (320x180 since the viewport bump) and the measured
# arena, both used for camera clamping and for keeping spawns inside the room.
var VIEW_SIZE := Vector2(
	float(ProjectSettings.get_setting("display/window/size/viewport_width", 320)),
	float(ProjectSettings.get_setting("display/window/size/viewport_height", 180)))
var arena_min: Vector2 = Vector2.ZERO
var arena_max: Vector2 = Vector2(320, 180)
var play_min: Vector2 = Vector2(16, 16)
var play_max: Vector2 = Vector2(304, 164)

var danger_vignette: Control
var style_bar_bg: ColorRect
var style_bar_fill: ColorRect
var neon_rect: ColorRect
var neon_mat: ShaderMaterial
var ult_label: Label
var ult_state: String = ""
var ult_timer: float = 0.0
var ult_frozen: Array = []
var ult_markers: Array = []
var pause_panel: Control
var pause_resume: Button
var pause_retry: Button
var pause_menu: Button
var waiting_for_wave_start: bool = false

# Between-wave break shop
var break_panel: Control
var break_info: Label
var break_status: Label
var break_coins: Label
var hp_button: Button
var dash_button: Button
var leer_button: Button
var hp_buys: int = 0
var dash_buys: int = 0
var leer_buys: int = 0

func _apply_pixel_font(node: Node) -> void:
	if node is Control:
		var control := node as Control
		control.add_theme_font_override("font", UI_FONT)
	for child in node.get_children():
		_apply_pixel_font(child)

# --- Game feel ("juice") ---
var cam: Camera2D
var shake_amt: float = 0.0
var flash_rect: ColorRect
var flash_tween: Tween
var last_milestone: int = 0

const WAVE_MUSIC = preload("uid://dwrvqub1b3dyr")
const RAT_BOSS_1 = preload("uid://bhbk4b83r3n3r")
const FROG_BOSS_2 = preload("uid://myjklip14q8g")
const PIGEON_BOSS_3 = preload("uid://nx84smyo7dmp")

@onready var camera_2d: Camera2D = $Camera2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	# Defensive: a prior run that changed scene mid-effect could leave this
	# stuck, freezing the whole game. Always start at full speed.
	Engine.time_scale = 1.0
	rng.randomize()
	_load_profile()
	# Meta survives a scene reload (so RETRY keeps the mode); the profile is the
	# fallback when the game was just launched.
	difficulty = clampi(int(get_tree().get_meta("difficulty", difficulty)), 0, DIFFICULTIES.size() - 1)
	get_tree().set_meta("difficulty", difficulty)
	tutorial_enabled = bool(get_tree().get_meta("tutorial_enabled", false))
	get_tree().set_meta("tutorial_enabled", false)
	# Endless: kept set across scene reloads so RETRY / PLAY AGAIN stay endless;
	# the menu's PLAY / TUTORIAL explicitly clear it.
	endless = bool(get_tree().get_meta("endless_enabled", false))
	if endless:
		tutorial_enabled = false
	# Hard guarantee: every pause in this game (death, wave break, shop, pause
	# menu) puts a panel on this layer and waits for a click. If the layer is
	# hidden - as level2's scene was - the game locks up with no visible way out
	# and reads as a total freeze. Never trust the scene flag for this.
	$UI.visible = true
	banner.modulate.a = 0.0
	_dim_floor()
	_setup_camera()
	_build_result_panel()
	_build_hud()
	_build_ability_bar()
	_build_vignette()
	_build_neon()
	_build_flash()
	_build_boss_bar()
	_build_shop_panel()
	_build_break_panel()
	_build_pause_panel()
	_build_tutorial_panel()
	_apply_pixel_font($UI)
	var cat := get_tree().get_first_node_in_group("player")
	if cat != null:
		if cat.has_signal("died"):
			cat.died.connect(_on_cat_died)
		if cat.has_signal("style_event"):
			cat.style_event.connect(_on_style_event)
		if cat.has_method("apply_difficulty"):
			cat.apply_difficulty(int(_diff()["bonus_hp"]))
	# The coached tutorial runs first and only releases the real waves once every
	# lesson has actually been performed.
	if tutorial_enabled:
		_start_tutorial()
	else:
		_build_waves()
		_next_wave()
	_sync_fight_ui()

func _process(delta: float) -> void:
	if get_tree().paused:
		_sync_fight_ui()
		return
	# Backstop against a stranded hitstop. If nothing is mid-hitstop the clock
	# must be running at full speed; anything else means a code path dropped it,
	# and the player would just experience the game as frozen.
	if hitstop_pending <= 0 and not is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = 1.0
	if style_timeout > 0.0:
		style_timeout -= delta
	else:
		style_meter = max(style_meter - 12.0 * delta, 0.0)
	if reward_timer > 0.0:
		reward_timer -= delta
		reward_label.modulate.a = clamp(reward_timer, 0.0, 1.0)
	else:
		reward_label.modulate.a = 0.0
	if Input.is_action_just_pressed("ultimate") and _can_ultimate():
		_start_ultimate()
	if ult_state == "plan":
		# Keep re-freezing so stragglers arriving mid-plan are caught too.
		_freeze_world(true)
	_tick_ultimate(delta)
	_tick_tutorial(delta)
	_update_camera(delta)
	_update_boss_bar()
	_update_ability_bar()
	_update_danger(delta)
	_refresh_hud()
	_sync_fight_ui()

func _is_fight_active() -> bool:
	if tutorial_active:
		return true
	return not cleared and not get_tree().paused and (_live_enemy_count() > 0 or boss_active or pending_spawns > 0)

# Red edge-pulse that ramps up as the cat gets low. Purely a readability aid -
# health is otherwise a small bar in the corner you have to look away to read.
func _update_danger(_delta: float) -> void:
	if danger_vignette == null:
		return
	var cat := get_tree().get_first_node_in_group("player")
	if cat == null or not is_instance_valid(cat) or bool(cat.get("dead")):
		danger_vignette.set_intensity(0.0)
		return
	var hp := float(cat.get("health"))
	var max_hp := maxf(float(cat.get("max_health")), 1.0)
	var frac := hp / max_hp
	# Silent above a third health, then climbs hard.
	danger_vignette.set_intensity(clampf((0.34 - frac) / 0.34, 0.0, 1.0))

func _set_player_health_visible(shown: bool) -> void:
	var cat := get_tree().get_first_node_in_group("player")
	if cat != null and cat.has_node("UI/Control"):
		cat.get_node("UI/Control").visible = shown

func _sync_fight_ui() -> void:
	var shown := _is_fight_active()
	var boss_fight: bool = shown and boss_active
	_set_player_health_visible(shown)
	# Bottom HUD (player card, rank, abilities) is always up during a fight.
	for n in [combo_label, ability_panel, style_bar_bg, style_bar_fill]:
		if n != null:
			n.visible = shown
	# The top wave/score plates step aside for the boss bar so nothing stacks.
	for n in [hud_panel, score_panel, wave_label, score_label]:
		if n != null:
			n.visible = shown and not boss_fight
	if enemies_label != null:
		enemies_label.visible = false
	if reward_label != null:
		reward_label.visible = shown and reward_timer > 0.0

# --- Game feel helpers -------------------------------------------------------

# Knock the floor back a touch and cool it slightly. The tiles and the cat share
# a lot of midtone, so pushing the background down is half of what makes the
# actors readable (the sprite outline shader is the other half). Done here
# rather than per-scene so every level gets it.
func _dim_floor() -> void:
	var tiles := get_node_or_null("TileMap")
	if tiles is CanvasItem:
		(tiles as CanvasItem).modulate = Color(0.72, 0.75, 0.86, 1.0)

# Adopts the Camera2D placed in the level scene (creating one if a scene forgot
# it, as level4 had), then pins its limits to the actual tiled arena.
func _setup_camera() -> void:
	_compute_arena()
	cam = get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		cam = Camera2D.new()
		cam.name = "Camera2D"
		add_child(cam)
	cam.zoom = Vector2.ONE
	cam.offset = Vector2.ZERO
	cam.limit_left = int(arena_min.x)
	cam.limit_top = int(arena_min.y)
	cam.limit_right = int(arena_max.x)
	cam.limit_bottom = int(arena_max.y)
	cam.position = _camera_target()
	cam.make_current()

# Playable extent, measured from the tile layers rather than hardcoded, because
# the four levels are now different sizes (352x224 down to 288x176).
func _compute_arena() -> void:
	var rect := Rect2i()
	var tile := Vector2i(16, 16)
	var found := false
	for layer in _tile_layers(self):
		var used: Rect2i = layer.get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		if layer.tile_set != null:
			tile = layer.tile_set.tile_size
		rect = used if not found else rect.merge(used)
		found = true
	if not found:
		arena_min = Vector2.ZERO
		arena_max = VIEW_SIZE
	else:
		arena_min = Vector2(rect.position.x * tile.x, rect.position.y * tile.y)
		arena_max = Vector2(rect.end.x * tile.x, rect.end.y * tile.y)
	# Enemies and spawns stay a tile inside the wall ring.
	var inset := Vector2(tile) * 0.9
	play_min = arena_min + inset
	play_max = arena_max - inset

func _tile_layers(node: Node) -> Array:
	var out: Array = []
	if node is TileMapLayer:
		out.append(node)
	for c in node.get_children():
		out.append_array(_tile_layers(c))
	return out

# Where the camera wants to sit: on the cat, but never showing past the walls.
# An arena smaller than the screen (level3/4 are) is simply centred instead.
func _camera_target() -> Vector2:
	var target := (arena_min + arena_max) * 0.5
	var cat := get_tree().get_first_node_in_group("player")
	if cat != null and is_instance_valid(cat):
		target = cat.global_position
	var half := VIEW_SIZE * 0.5
	var span := arena_max - arena_min
	if span.x <= VIEW_SIZE.x:
		target.x = (arena_min.x + arena_max.x) * 0.5
	else:
		target.x = clampf(target.x, arena_min.x + half.x, arena_max.x - half.x)
	if span.y <= VIEW_SIZE.y:
		target.y = (arena_min.y + arena_max.y) * 0.5
	else:
		target.y = clampf(target.y, arena_min.y + half.y, arena_max.y - half.y)
	return target

# --- OVERDRIVE ---------------------------------------------------------------

func _build_neon() -> void:
	# First child of the UI layer: it reads the screen *before* the HUD is drawn,
	# so the arena grades to neon while the HUD stays legible on top.
	neon_mat = ShaderMaterial.new()
	neon_mat.shader = NEON_SHADER
	neon_mat.set_shader_parameter("amount", 0.0)
	neon_mat.set_shader_parameter("surge", 0.0)
	neon_rect = ColorRect.new()
	neon_rect.name = "NeonGrade"
	neon_rect.material = neon_mat
	neon_rect.color = Color(1, 1, 1, 1)
	neon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	neon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	neon_rect.visible = false
	neon_rect.process_mode = Node.PROCESS_MODE_ALWAYS
	$UI.add_child(neon_rect)
	$UI.move_child(neon_rect, 0)

	ult_label = Label.new()
	ult_label.name = "UltLabel"
	ult_label.visible = false
	ult_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ult_label.position = Vector2(60, 30)
	ult_label.size = Vector2(200, 24)
	ult_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ult_label.add_theme_font_override("font", UI_FONT)
	ult_label.add_theme_font_size_override("font_size", 11)
	ult_label.add_theme_color_override("font_color", Color(1.0, 0.4, 1.0, 1.0))
	ult_label.add_theme_color_override("font_outline_color", Color(0.05, 0, 0.1, 1.0))
	ult_label.add_theme_constant_override("outline_size", 4)
	$UI.add_child(ult_label)

# Available only against a live boss, at a full SS meter, once per meter.
func _can_ultimate() -> bool:
	if ult_state != "" or cleared or tutorial_active or get_tree().paused:
		return false
	if not boss_active:
		return false
	var boss := get_tree().get_first_node_in_group("boss")
	if boss == null or not is_instance_valid(boss):
		return false
	if style_meter < ULT_STYLE_COST:
		return false
	var cat := get_tree().get_first_node_in_group("player")
	return cat != null and is_instance_valid(cat) and not bool(cat.get("dead"))

func _start_ultimate() -> void:
	var cat := get_tree().get_first_node_in_group("player")
	if cat == null or not cat.has_method("begin_plan"):
		return
	ult_state = "plan"
	ult_timer = PLAN_SECONDS
	# Spending the meter is the cost - you drop straight back to D rank.
	style_meter = 0.0
	style_timeout = 0.0
	_clear_hitstop()
	_freeze_world(true)
	if not cat.plan_action_queued.is_connected(_on_plan_action_queued):
		cat.plan_action_queued.connect(_on_plan_action_queued)
	cat.begin_plan()
	neon_rect.visible = true
	neon_mat.set_shader_parameter("surge", 0.0)
	var t := create_tween()
	t.tween_method(_set_neon_amount, 0.0, 1.0, 0.22)
	ult_label.visible = true
	_hype("OVERDRIVE", Color(1.0, 0.35, 1.0))
	_shake(3.0)
	SoundManager.set_music_volume(0.22)

func _set_neon_amount(value: float) -> void:
	if neon_mat != null:
		neon_mat.set_shader_parameter("amount", value)

func _on_plan_action_queued(at: Vector2, kind: String) -> void:
	var marker: Node2D = PLAN_MARKER.new()
	marker.kind = kind
	marker.index = ult_markers.size() + 1
	marker.position = at
	add_child(marker)
	ult_markers.append(marker)
	_shake(0.6)

func _tick_ultimate(delta: float) -> void:
	if ult_state == "":
		return
	var cat := get_tree().get_first_node_in_group("player")
	ult_timer -= delta
	if ult_state == "plan":
		var queued: int = int(cat.call("planned_count")) if cat != null and is_instance_valid(cat) else 0
		ult_label.text = "PLAN  %.1fs\n%d / %d QUEUED" % [maxf(ult_timer, 0.0), queued, 14]
		# End early once the queue is full - no reason to make the player wait.
		if ult_timer <= 0.0 or (cat != null and bool(cat.call("plan_full"))):
			_begin_ultimate_execution()
		return
	if ult_state == "exec":
		ult_label.text = "EXECUTE"
		if ult_timer <= 0.0:
			_end_ultimate()

func _begin_ultimate_execution() -> void:
	var cat := get_tree().get_first_node_in_group("player")
	ult_state = "exec"
	ult_timer = EXEC_SECONDS
	_clear_plan_markers()
	# Swap the hard process freeze for each enemy's own freeze state: they still
	# cannot act, but their hit reactions and death animations play out.
	_freeze_world(false)
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.has_method("freeze"):
			e.freeze(EXEC_SECONDS + 0.6)
	neon_mat.set_shader_parameter("surge", 1.0)
	_flash(Color(1.0, 0.4, 1.0), 0.6)
	_shake(4.0)
	_hype("EXECUTE", Color(1.0, 0.3, 0.9))
	if cat == null or not cat.has_method("run_execution") or not bool(cat.call("run_execution", EXEC_SECONDS)):
		_end_ultimate()

func _end_ultimate() -> void:
	if ult_state == "":
		return
	var cat := get_tree().get_first_node_in_group("player")
	if cat != null and is_instance_valid(cat) and cat.has_method("cancel_overdrive"):
		cat.cancel_overdrive()
	ult_state = ""
	ult_timer = 0.0
	_clear_plan_markers()
	_freeze_world(false)
	ult_label.visible = false
	neon_mat.set_shader_parameter("surge", 0.0)
	var t := create_tween()
	t.tween_method(_set_neon_amount, 1.0, 0.0, 0.35)
	t.tween_callback(func():
		if neon_rect != null:
			neon_rect.visible = false)
	SoundManager.set_music_volume(0.5)
	_set_reward("Overdrive spent. Build it again.")

# Hard freeze: disabling processing stops enemies dead, tells and all, which is
# exactly the "time stopped" read the planning phase needs. Re-applied every
# frame so anything that spawns mid-plan is caught too.
func _freeze_world(on: bool) -> void:
	if on:
		for e in get_tree().get_nodes_in_group("enemies"):
			if is_instance_valid(e):
				e.process_mode = Node.PROCESS_MODE_DISABLED
				if not ult_frozen.has(e):
					ult_frozen.append(e)
		return
	for e in ult_frozen:
		if is_instance_valid(e):
			e.process_mode = Node.PROCESS_MODE_PAUSABLE
	ult_frozen.clear()

func _clear_plan_markers() -> void:
	for m in ult_markers:
		if is_instance_valid(m):
			m.queue_free()
	ult_markers.clear()

func _build_vignette() -> void:
	danger_vignette = VIGNETTE.new()
	danger_vignette.name = "DangerVignette"
	$UI.add_child(danger_vignette)

func _build_flash() -> void:
	flash_rect = ColorRect.new()
	flash_rect.name = "Flash"
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Color(1, 1, 1, 1)
	flash_rect.modulate.a = 0.0
	$UI.add_child(flash_rect)

func _update_camera(delta: float) -> void:
	if cam == null:
		return
	# Follow the cat, eased, and clamped so the view never leaves the room.
	cam.position = cam.position.lerp(_camera_target(), clampf(delta * 9.0, 0.0, 1.0))
	# Shake rides on offset so it never fights the follow or the clamp.
	if shake_amt > 0.05:
		shake_amt = max(shake_amt - 26.0 * delta, 0.0)
		cam.offset = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * shake_amt
	elif cam.offset != Vector2.ZERO:
		cam.offset = Vector2.ZERO

func _shake(amount: float) -> void:
	shake_amt = min(max(shake_amt, amount), 4.5)

func _flash(color: Color, strength: float) -> void:
	if flash_rect == null:
		return
	if flash_tween != null and flash_tween.is_valid():
		flash_tween.kill()
	flash_rect.color = Color(color.r, color.g, color.b, 1.0)
	flash_rect.modulate.a = clamp(strength, 0.0, 1.0)
	flash_tween = create_tween()
	flash_tween.tween_property(flash_rect, "modulate:a", 0.0, 0.3)

func _hitstop(duration: float, scale_value: float) -> void:
	if get_tree().paused or ult_state != "":
		return
	hitstop_id += 1
	var active_id: int = hitstop_id
	hitstop_pending += 1
	Engine.time_scale = scale_value
	await get_tree().create_timer(duration, true, false, true).timeout
	hitstop_pending = maxi(hitstop_pending - 1, 0)
	# Restore unconditionally. The old version skipped this while the tree was
	# paused, which stranded time_scale at 0.12 whenever a pause landed inside a
	# hitstop - the game then ran at a tenth speed forever and read as frozen.
	if hitstop_id == active_id:
		Engine.time_scale = 1.0

# Cancels any in-flight hitstop and puts the clock back. Anything that pauses,
# unpauses or changes scene calls this, so a hitstop can never outlive the
# moment it belongs to.
func _clear_hitstop() -> void:
	hitstop_id += 1
	hitstop_pending = 0
	Engine.time_scale = 1.0

func _hype(text: String, color: Color) -> void:
	banner.add_theme_color_override("font_color", color)
	banner.text = text
	banner.modulate.a = 1.0
	create_tween().tween_property(banner, "modulate:a", 0.0, 1.1)

func _combo_color() -> Color:
	if no_glare_chain >= 20:
		return Color(1.0, 0.4, 0.9)
	if no_glare_chain >= 10:
		return Color(1.0, 0.55, 0.75)
	if no_glare_chain >= 5:
		return Color(1.0, 0.85, 0.35)
	return Color(0.96, 0.97, 1.0)

# Floating combat text that rises off a kill - cheap, immediate dopamine.
func _spawn_popup(pos: Vector2, text: String) -> void:
	var l := Label.new()
	l.position = pos + Vector2(-10, -14)
	l.z_index = 50
	l.add_theme_font_override("font", UI_FONT)
	l.add_theme_font_size_override("font_size", 8)
	l.add_theme_color_override("font_color", _combo_color())
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	l.text = text
	add_child(l)
	var t := create_tween()
	t.tween_property(l, "position:y", l.position.y - 14.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)

func _hide_hud() -> void:
	for n in [hud_panel, score_panel, wave_label, enemies_label, score_label, combo_label, reward_label, boss_panel, ability_panel, style_bar_bg, style_bar_fill]:
		if n != null:
			n.visible = false
	if danger_vignette != null:
		danger_vignette.set_intensity(0.0)
	var cat := get_tree().get_first_node_in_group("player")
	if cat != null and cat.has_node("UI/Control"):
		cat.get_node("UI/Control").visible = false

func _multikill(n: int) -> void:
	var names := {2: "DOUBLE KILL", 3: "TRIPLE KILL", 4: "QUAD KILL", 5: "PENTA KILL"}
	_hype(names.get(n, "MASSACRE"), Color(1.0, 0.72, 0.2))
	_flash(Color(1.0, 0.85, 0.45), 0.32 + 0.05 * n)
	_shake(2.2 + n * 0.4)
	score += n * 14

func _check_combo_milestone() -> void:
	var tiers := {10: "COMBO x10", 20: "RAMPAGE", 30: "UNSTOPPABLE", 40: "GODLIKE", 50: "LEGENDARY"}
	if tiers.has(no_glare_chain) and no_glare_chain != last_milestone:
		last_milestone = no_glare_chain
		_hype(tiers[no_glare_chain], Color(1.0, 0.4, 0.9))
		_flash(Color(1.0, 0.4, 0.9), 0.5)
		_shake(2.8)

# Every track is background music, so it has to loop. The import flag is set to
# loop as well; this guards against a re-import quietly resetting it.
func _play_music(track: AudioStream) -> void:
	if track is AudioStreamMP3:
		(track as AudioStreamMP3).loop = true
	SoundManager.play_music(track, 0, "Music")

func _build_waves() -> void:
	if endless:
		waves = [_gen_endless_wave(0)]
		_play_music(RAT_BOSS_1)
		return
	if level_id == 1:
		if tutorial_enabled:
			waves = [
				[["rat", 3]],
				[["rat", 4], ["scurrier", 3]],
				[["rat", 4], ["scurrier", 3], ["frog", 1]],
			]
		else:
			waves = [
				[["rat", 4]],
				[["rat", 5], ["scurrier", 3]],
				[["scurrier", 4], ["frog", 2]],
				[["rat", 4], ["brute", 1], ["spitter", 2]],
				[["rat", 5], ["scurrier", 4], ["frog", 3]],
			]
		_play_music(WAVE_MUSIC)
	elif level_id == 2:
		waves = [
			[["rat", 6], ["frog", 2]],
			[["scurrier", 6], ["frog", 3]],
			[["rat", 5], ["brute", 2], ["spitter", 2]],
			[["scurrier", 6], ["brute", 2], ["spitter", 3]],
			[["boss", 1], ["scurrier", 4], ["frog", 2]],
		]
		_play_music(RAT_BOSS_1)
	elif level_id == 3:
		waves = [
			[["spitter", 4], ["frog", 5]],
			[["brute", 2], ["scurrier", 6], ["spitter", 4]],
			[["frog", 5], ["spitter", 4], ["brute", 3]],
			[["frog_boss", 1], ["frog", 3], ["spitter", 2]],
		]
		_play_music(FROG_BOSS_2)
	else:
		waves = [
			[["rat", 7], ["brute", 3], ["spitter", 4]],
			[["scurrier", 8], ["frog", 4], ["spitter", 5]],
			[["brute", 4], ["scurrier", 6], ["spitter", 5]],
			[["pigeon_boss", 1], ["scurrier", 4], ["spitter", 2]],
		]
		_play_music(PIGEON_BOSS_3)

func _is_boss_wave(index: int) -> bool:
	if index < 0 or index >= waves.size():
		return false
	for entry in waves[index]:
		var key := String(entry[0])
		if key == "boss" or key == "frog_boss" or key == "pigeon_boss":
			return true
		if ROSTER.has(key):
			var data: Dictionary = ROSTER[key]
			if bool(data["cfg"].get("is_boss", false)):
				return true
	return false

# Endless survival: hordes that keep escalating, with a boss milestone every
# fifth wave (cycling the three bosses). No scripted end - you play until the
# swarm finally catches you.
func _gen_endless_wave(n: int) -> Array:
	if n > 0 and n % 5 == 0:
		var bosses := ["boss", "frog_boss", "pigeon_boss"]
		var pick: String = bosses[(n / 5 - 1) % bosses.size()]
		return [[pick, 1], ["scurrier", 2 + n / 5], ["spitter", 1 + n / 10]]
	var pool := ["rat", "scurrier", "frog"]
	if n >= 3:
		pool.append("spitter")
	if n >= 4:
		pool.append("brute")
	var budget: int = mini(4 + n * 2, 26)
	var types: int = mini(2 + n / 6, 3)
	var wave: Array = []
	for i in types:
		var key: String = pool[rng.randi_range(0, pool.size() - 1)]
		wave.append([key, maxi(1, budget / types)])
	return wave

func _next_wave() -> void:
	if cleared:
		return
	wave_index += 1
	if wave_index >= waves.size():
		if endless:
			waves.append(_gen_endless_wave(wave_index))
		else:
			_level_cleared()
			return
	if _is_boss_wave(wave_index):
		boss_active = true
		_show_banner(_boss_banner_name(waves[wave_index]))
		_set_reward("Boss milestone. Survive it." if endless else "Final boss. End it in style.")
	else:
		_show_banner("WAVE %d" % (wave_index + 1))
		_set_reward("Rank high. Cash out harder.")
	# Bosses land first; the rabble trickles in shuffled batches so a wave opens
	# as a readable fight, not a blob dumped on your head in one frame.
	var bosses: Array = []
	var rabble: Array = []
	for entry in waves[wave_index]:
		var key := String(entry[0])
		if not ROSTER.has(key):
			continue
		var is_boss := bool(ROSTER[key]["cfg"].get("is_boss", false))
		for i in int(entry[1]):
			if is_boss:
				bosses.append(key)
			else:
				rabble.append(key)
	rabble.shuffle()
	for key in bosses:
		_spawn_after(String(key), 0.0)
	for i in rabble.size():
		_spawn_after(String(rabble[i]), 0.55 * float(i / 3))

# Difficulty scales with wave depth only - upgrades the player buys are theirs
# to keep. Growth is gentle and capped so late waves add pressure through
# numbers and mix, not HP sponges. Bosses scale gently by level only.
func _scaled_cfg(cfg: Dictionary, scene_key: String) -> Dictionary:
	var out: Dictionary = cfg.duplicate(true)
	var mode := _diff()
	out["parry_window"] = float(mode["parry"])
	# Rooms are different sizes now, so enemies that clamp themselves (frogs and
	# both hopping/flying bosses) need this level's real bounds.
	out["arena_min"] = play_min
	out["arena_max"] = play_max
	if bool(out.get("is_boss", false)):
		var boss_hp := float(out.get("max_health", 40)) * (1.0 + 0.1 * float(level_id - 1))
		out["max_health"] = maxi(1, int(round(boss_hp * float(mode["enemy_hp"]))))
		return out
	# Wave ramp is scaled by the mode, so Easy stays gentle deep into a level and
	# Hell gets nasty fast.
	var wave := float(maxi(wave_index, 0)) * float(mode["ramp"])
	var hp := float(out.get("max_health", 3)) * minf(1.0 + 0.1 * wave, 2.1) * float(mode["enemy_hp"])
	out["max_health"] = maxi(1, int(round(hp)))
	if out.has("move_speed"):
		out["move_speed"] = float(out["move_speed"]) * minf(1.0 + 0.018 * wave, 1.14) * float(mode["enemy_speed"])
	# Deeper waves swing sooner and more often. That is pressure the player can
	# still read and dodge, unlike raw HP, which only makes fights longer.
	var windup := float(mode["windup"])
	if scene_key == "rat":
		out["nibble_windup"] = maxf(float(out.get("nibble_windup", 0.26)) - 0.012 * wave, 0.16) * windup
		out["nibble_interval"] = maxf(float(out.get("nibble_interval", 0.72)) - 0.03 * wave, 0.42)
		out["dash_windup"] = float(out.get("dash_windup", 0.32)) * windup
	elif scene_key == "frog":
		out["croak_windup"] = maxf(float(out.get("croak_windup", 0.55)) - 0.02 * wave, 0.34) * windup
		out["croak_cooldown"] = maxf(float(out.get("croak_cooldown", 2.35)) - 0.09 * wave, 1.2)
		# Easy frogs still hop, just less often - slippery, not maddening.
		var dodge := float(mode["dodge"])
		out["hop_cooldown"] = maxf(float(out.get("hop_cooldown", 1.15)) - 0.05 * wave, 0.72) / maxf(dodge, 0.1)
		out["hop_chance"] = clampf(float(out.get("hop_chance", 0.72)) * dodge, 0.0, 1.0)
	# Skirmisher rats dodge on the same dial so both archetypes read consistently.
	if scene_key == "rat" and String(out.get("behavior", "chaser")) == "skirmisher":
		out["dash_chance"] = clampf(float(out.get("dash_chance", 0.62)) * float(mode["dodge"]), 0.0, 1.0)
	return out

# Staggered spawn: wait out the batch delay, flash a converging marker at the
# spot for half a second, then materialise the enemy there. pending_spawns keeps
# the wave-clear check honest while stragglers are still on their way in.
func _spawn_after(key: String, delay: float) -> void:
	if not ROSTER.has(key):
		return
	pending_spawns += 1
	if delay > 0.0:
		await get_tree().create_timer(delay, false).timeout
	if cleared or not is_inside_tree():
		pending_spawns -= 1
		return
	var pos := _spawn_point()
	var marker: Node2D = SPAWN_MARKER.new()
	marker.position = pos
	add_child(marker)
	await get_tree().create_timer(0.5, false).timeout
	pending_spawns -= 1
	if cleared or not is_inside_tree():
		return
	_spawn_at(key, pos)

func _spawn_at(key: String, pos: Vector2) -> void:
	if not ROSTER.has(key):
		return
	var data: Dictionary = ROSTER[key]
	var scene: PackedScene = null
	var scene_key := String(data["scene"])
	if scene_key == "rat":
		scene = rat_scene
	elif scene_key == "frog":
		scene = frog_scene
	elif scene_key == "frog_boss":
		scene = frog_boss_scene
	elif scene_key == "pigeon_boss":
		scene = pigeon_boss_scene
	if scene == null:
		return
	var e := scene.instantiate()
	if e.has_method("configure"):
		e.configure(_scaled_cfg(data["cfg"], scene_key))
	e.position = pos
	add_child(e)
	if e.has_signal("died"):
		if bool(data["cfg"].get("is_boss", false)):
			e.died.connect(_on_boss_died.bind(e))
		else:
			e.died.connect(_on_enemy_died.bind(e))

func _boss_banner_name(wave: Array) -> String:
	for entry in wave:
		var key := String(entry[0])
		if not ROSTER.has(key):
			continue
		var data: Dictionary = ROSTER[key]
		if bool(data["cfg"].get("is_boss", false)):
			if key == "frog_boss":
				return "THE BOG BARON"
			if key == "pigeon_boss":
				return "THE WIND WRAITH"
			return BOSS_NAME
	return BOSS_NAME

# Count the enemies actually alive on the field. Dead enemies leave the
# "enemies" group the instant they die, so this can never desync the way a
# hand-tracked counter can.
func _live_enemy_count() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and not e.is_in_group("boss"):
			n += 1
	return n

# Spawn bounds come from the measured arena, not hardcoded numbers - the levels
# are different sizes now and the old 256x144 figures put spawns in the walls.
func _spawn_point() -> Vector2:
	var cat := get_tree().get_first_node_in_group("player")
	var cat_pos: Vector2 = cat.global_position if cat != null else (arena_min + arena_max) * 0.5
	for i in 24:
		var p := Vector2(rng.randf_range(play_min.x, play_max.x), rng.randf_range(play_min.y, play_max.y))
		if p.distance_to(cat_pos) > 58.0:
			return p
	return Vector2(rng.randf_range(play_min.x, play_max.x), rng.randf_range(play_min.y, play_max.y))

func _on_enemy_died(enemy: Node) -> void:
	kills += 1
	var value: int = 12
	if enemy != null and is_instance_valid(enemy):
		value = int(enemy.get("score_value"))
	var gained: int = value + wave_index * 4
	score += gained
	if enemy != null and is_instance_valid(enemy):
		_spawn_popup(enemy.global_position, "+%d" % gained)
		_maybe_drop_heart(enemy.global_position)
	_flash(Color(1.0, 0.82, 0.35), 0.16)
	_shake(1.2)
	_on_style_event("enemy_down", 18)
	if tutorial_active:
		return
	if not cleared and not boss_active and _live_enemy_count() == 0 and pending_spawns == 0:
		_award_wave_clear()
		call_deferred("_finish_wave_after_delay")

# Hearts drop on a curve, not a flat roll: at full health they are rare (you do
# not need them), and the odds climb steeply as the cat gets hurt. A pity timer
# guarantees one if a wounded player has gone a long dry spell, so a bad streak
# never turns into an unwinnable one.
func _maybe_drop_heart(at: Vector2) -> void:
	var cat := get_tree().get_first_node_in_group("player")
	if cat == null or not is_instance_valid(cat) or bool(cat.get("dead")):
		return
	var hp := float(cat.get("health"))
	var max_hp := maxf(float(cat.get("max_health")), 1.0)
	var missing: float = clampf(1.0 - hp / max_hp, 0.0, 1.0)
	if missing <= 0.001:
		kills_since_heart += 1
		return
	var drop_mul := float(_diff()["drop"])
	var chance: float = (0.05 + 0.34 * missing * missing) * drop_mul
	var desperate: bool = hp <= 2.0
	if desperate:
		chance = maxf(chance, 0.32 * drop_mul)
	kills_since_heart += 1
	var pity: int = int(round((8.0 if desperate else 16.0) / maxf(drop_mul, 0.2)))
	if rng.randf() >= chance and kills_since_heart < pity:
		return
	kills_since_heart = 0
	_drop_heart(at)

func _drop_heart(at: Vector2) -> void:
	var heart: Node2D = PICKUP.new()
	heart.kind = "health"
	heart.amount = 2
	heart.position = Vector2(clampf(at.x, play_min.x, play_max.x), clampf(at.y, play_min.y, play_max.y))
	heart.collected.connect(_on_pickup_collected)
	add_child(heart)

func _on_pickup_collected(_kind: String) -> void:
	_flash(Color(0.5, 1.0, 0.6), 0.2)
	_set_reward("Patched up! +2 HP")
	var cat := get_tree().get_first_node_in_group("player")
	var at: Vector2 = cat.global_position if cat != null and is_instance_valid(cat) else Vector2(128, 60)
	_spawn_popup(at, "+2 HP")

func _finish_wave_after_delay() -> void:
	await get_tree().create_timer(2.0).timeout
	if cleared or boss_active or _live_enemy_count() > 0 or pending_spawns > 0:
		return
	if endless or wave_index + 1 >= waves.size():
		_next_wave()
	else:
		_start_break()

func _on_boss_died(boss: Node = null) -> void:
	if cleared:
		return
	boss_active = false
	kills += 1
	var boss_score := 600
	if boss != null and is_instance_valid(boss):
		boss_score = int(boss.get("score_value"))
	score += boss_score
	style_meter += 60.0
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e != null and not e.is_in_group("boss"):
			e.queue_free()
	_hype("BOSS DOWN +%d" % boss_score, Color(1.0, 0.85, 0.3))
	_flash(Color(1, 1, 1), 0.95)
	_shake(4.5)
	# In endless a boss is a milestone, not the finish line - roll into the next
	# wave instead of ending the run.
	if endless:
		_award_wave_clear()
		call_deferred("_finish_wave_after_delay")
		return
	cleared = true
	await get_tree().create_timer(0.7).timeout
	_finish_run("VICTORY!" if next_level_path == "" else "LEVEL CLEAR", true)

func _award_wave_clear() -> void:
	_flash(Color(1.0, 0.9, 0.5), 0.28)
	_shake(1.6)
	var bonus: int = 20 + wave_index * 10 + _rank_bonus()
	score += bonus
	style_meter += 10.0
	no_glare_chain += 1
	best_chain = maxi(best_chain, no_glare_chain)
	_set_reward("Wave clear +%d  Rank %s" % [bonus, _style_rank()])

# --- Between-wave break & roguelite shop ------------------------------------

func _wave_enemy_count(index: int) -> int:
	if index < 0 or index >= waves.size():
		return 0
	var total := 0
	for entry in waves[index]:
		total += int(entry[1])
	return total

func _hp_cost() -> int:
	return 26 + hp_buys * 20

func _dash_cost() -> int:
	return 105 + dash_buys * 85

func _leer_cost() -> int:
	return 135 + leer_buys * 110

func _start_break() -> void:
	if cleared:
		return
	waiting_for_wave_start = true
	var next_i := wave_index + 1
	if _is_boss_wave(next_i):
		break_info.text = "Boss next. Spend coins, then press any key."
	else:
		break_info.text = "Nice clear! Next wave has %d foes. Press any key when ready." % _wave_enemy_count(next_i)
	break_status.text = ""
	_refresh_break()
	_sync_fight_ui()
	break_panel.visible = true
	get_tree().paused = true

func _refresh_break() -> void:
	break_coins.text = "Coins: %d" % coins
	hp_button.text = "+1 MAX HP  (%d)" % _hp_cost()
	dash_button.text = "DASH+ faster/longer/often  (%d)" % _dash_cost()
	leer_button.text = "LEER+ stun/mark  (%d)" % _leer_cost()

func _buy_health() -> void:
	var cost := _hp_cost()
	if coins < cost:
		break_status.text = "Need %d more coins." % (cost - coins)
		return
	coins -= cost
	hp_buys += 1
	var cat := get_tree().get_first_node_in_group("player")
	if cat != null and cat.has_method("buy_health"):
		cat.buy_health()
	_save_profile_values()
	break_status.text = "Max HP up!"
	_refresh_break()
	_refresh_hud()

func _buy_dash() -> void:
	var cost := _dash_cost()
	if coins < cost:
		break_status.text = "Need %d more coins." % (cost - coins)
		return
	coins -= cost
	dash_buys += 1
	var cat := get_tree().get_first_node_in_group("player")
	if cat != null and cat.has_method("upgrade_dash"):
		cat.upgrade_dash()
	_save_profile_values()
	break_status.text = "Dash upgraded!"
	_refresh_break()
	_refresh_hud()

func _buy_leer() -> void:
	var cost := _leer_cost()
	if coins < cost:
		break_status.text = "Need %d more coins." % (cost - coins)
		return
	coins -= cost
	leer_buys += 1
	var cat := get_tree().get_first_node_in_group("player")
	if cat != null and cat.has_method("upgrade_leer"):
		cat.upgrade_leer()
	_save_profile_values()
	break_status.text = "Leer upgraded!"
	_refresh_break()
	_refresh_hud()

func _start_waited_wave() -> void:
	if not waiting_for_wave_start:
		return
	waiting_for_wave_start = false
	break_panel.visible = false
	_clear_hitstop()
	get_tree().paused = false
	_next_wave()
	_sync_fight_ui()

func _on_fight() -> void:
	_start_waited_wave()

func _build_break_panel() -> void:
	break_panel = Control.new()
	break_panel.name = "BreakPanel"
	break_panel.visible = false
	break_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	break_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.84)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	break_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	break_panel.add_child(center)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _panel_box(
		Color(0.05, 0.09, 0.12, 0.97), Color(0.5, 1.0, 0.85, 0.85)))
	center.add_child(frame)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(272, 152)
	box.add_theme_constant_override("separation", 1)
	frame.add_child(box)
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.5, 1.0, 0.85, 1))
	title.text = "BREAK - CHILL OUT"
	box.add_child(title)
	break_info = Label.new()
	break_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	break_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	break_info.custom_minimum_size = Vector2(272, 24)
	break_info.add_theme_font_size_override("font_size", 8)
	break_info.add_theme_color_override("font_color", Color(0.92, 0.9, 0.78, 1))
	box.add_child(break_info)
	break_coins = Label.new()
	break_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	break_coins.add_theme_font_size_override("font_size", 9)
	break_coins.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1))
	box.add_child(break_coins)
	hp_button = _make_button("HEALTH")
	hp_button.pressed.connect(_buy_health)
	box.add_child(hp_button)
	dash_button = _make_button("DASH")
	dash_button.pressed.connect(_buy_dash)
	box.add_child(dash_button)
	leer_button = _make_button("LEER")
	leer_button.pressed.connect(_buy_leer)
	box.add_child(leer_button)
	break_status = Label.new()
	break_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	break_status.custom_minimum_size = Vector2(272, 11)
	break_status.add_theme_font_size_override("font_size", 8)
	break_status.add_theme_color_override("font_color", Color(0.5, 0.95, 1.0, 1))
	box.add_child(break_status)
	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35, 1.0))
	hint.text = "PRESS ANY KEY"
	box.add_child(hint)
	$UI.add_child(break_panel)

func _level_cleared() -> void:
	cleared = true
	var final := next_level_path == ""
	_finish_run("VICTORY!" if final else "LEVEL CLEAR", true)

func _on_cat_died() -> void:
	_flash(Color(0.8, 0.05, 0.1), 0.85)
	_shake(4.0)
	await get_tree().create_timer(0.55).timeout
	var title := ("SURVIVED  W%d" % (wave_index + 1)) if endless else "YOU GOT CLIPPED"
	_finish_run(title, false)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if waiting_for_wave_start and break_panel != null and break_panel.visible and not shop_panel.visible:
				_start_waited_wave()
				get_viewport().set_input_as_handled()
				return
			if key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE:
				_toggle_pause()
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("restart") and (pause_panel == null or not pause_panel.visible):
		get_tree().paused = false
		get_tree().reload_current_scene()

func _toggle_pause() -> void:
	# Pausing mid-Overdrive would strand the freeze and the colour grade.
	if cleared or game_over.visible or break_panel.visible or shop_panel.visible or ult_state != "":
		return
	var paused := not get_tree().paused
	get_tree().paused = paused
	_clear_hitstop()
	pause_panel.visible = paused
	_sync_fight_ui()
	if paused:
		pause_resume.grab_focus()

func _resume_game() -> void:
	_clear_hitstop()
	get_tree().paused = false
	pause_panel.visible = false
	_sync_fight_ui()

func _restart() -> void:
	_clear_hitstop()
	get_tree().paused = false
	get_tree().reload_current_scene()

func _continue() -> void:
	_clear_hitstop()
	get_tree().paused = false
	if result_path != "":
		get_tree().change_scene_to_file(result_path)
	else:
		get_tree().change_scene_to_file("res://scenes/level1.tscn")

func _to_menu() -> void:
	_clear_hitstop()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _show_banner(text: String) -> void:
	banner.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	banner.text = text
	banner.modulate.a = 1.0
	create_tween().tween_property(banner, "modulate:a", 0.0, 1.4)

func _on_style_event(kind: String, amount: int) -> void:
	_tutorial_credit(kind)
	if kind == "multi":
		_hitstop(0.05, 0.08)
		_multikill(amount)
		return
	# Plain dashing is free movement - it neither builds nor breaks the combo.
	# The combo is a damage-and-parry streak, not a dash-spam counter.
	if kind == "dash":
		return
	# LEER is a core setup tool: free to press, never taxes style or the combo.
	if kind == "glare":
		_set_reward("LEER! Marked prey - hit them to EXECUTE.")
		_flash(Color(1.0, 0.2, 0.25), 0.22)
		return
	if amount < 0:
		if kind == "damage_taken":
			_hitstop(0.035, 0.12)
			_flash(Color(1.0, 0.2, 0.2), 0.5)
			_shake(2.6)
			no_glare_chain = 0
			last_milestone = 0
		style_meter = max(style_meter + amount, 0.0)
		style_timeout = 1.0
		return
	if kind == "paw_hit" or kind == "paw_kill" or kind == "enemy_down" or kind == "parry" or kind == "execute":
		no_glare_chain += 1
		best_chain = maxi(best_chain, no_glare_chain)
	var multiplier: float = 1.0 + mini(no_glare_chain, 28) * 0.075
	style_meter += amount * multiplier
	style_timeout = 3.5
	if kind == "paw_hit":
		_hitstop(0.018, 0.18)
		_shake(0.7)
	elif kind == "enemy_down":
		_hitstop(0.03, 0.12)
		_shake(0.9)
	elif kind == "bite":
		_hitstop(0.055, 0.08)
		_shake(2.4)
		_flash(Color(1.0, 0.9, 0.7), 0.22)
	elif kind == "tail":
		_hitstop(0.04, 0.1)
		_shake(1.7)
	var scored: int = maxi(1, int(amount * multiplier * 0.8))
	score += scored
	if kind == "paw_kill":
		_set_reward("Clean kill +%d  Chain x%d" % [scored, no_glare_chain])
		_flash(Color(1, 1, 1), 0.18)
		_shake(1.4)
	elif kind == "execute":
		_hitstop(0.065, 0.06)
		_set_reward("EXECUTE +%d  Chain x%d" % [scored, no_glare_chain])
		_hype("EXECUTE", Color(1.0, 0.3, 0.35))
		_flash(Color(1.0, 0.35, 0.4), 0.45)
		_shake(2.6)
	elif kind == "parry":
		_hitstop(0.07, 0.06)
		_set_reward("PARRY! Frozen +%d  Chain x%d" % [scored, no_glare_chain])
		_hype("PARRY!", Color(0.4, 0.92, 1.0))
		_flash(Color(0.55, 0.92, 1.0), 0.7)
		_shake(3.6)
	_check_combo_milestone()

func _style_rank() -> String:
	if style_meter >= 560.0:
		return "SS - Ssuper Smexxy"
	if style_meter >= 390.0:
		return "S - Smexy"
	if style_meter >= 260.0:
		return "A - Awe"
	if style_meter >= 150.0:
		return "B - Blowin' up"
	if style_meter >= 70.0:
		return "C - Comeback?"
	return "D - Dumbahh"

func _rank_bonus() -> int:
	var rank := _style_rank()
	if rank == "SS - Ssuper Smexxy":
		return 90
	if rank == "S - Smexy":
		return 62
	if rank == "A - Awe":
		return 42
	if rank == "B - Blowin' up":
		return 24
	if rank == "C - Comeback?":
		return 10
	return 0

# Style still pays best, but the floor is livable: a rough run must still fund
# a couple of upgrades or the economy turns into a grind spiral.
func _rank_coin_multiplier() -> float:
	var rank := _style_rank()
	if rank == "SS - Ssuper Smexxy":
		return 1.15
	if rank == "S - Smexy":
		return 0.95
	if rank == "A - Awe":
		return 0.8
	if rank == "B - Blowin' up":
		return 0.65
	if rank == "C - Comeback?":
		return 0.5
	return 0.35

func _build_hud() -> void:
	# Top-left: wave / enemies-left plate. Top-right: score plate. They no longer
	# collide with each other or with the boss bar (which replaces them mid-boss).
	# Laid out for the 320x180 viewport: top plates hug the top corners, the
	# player's rank/score and the ability bar hug the bottom.
	hud_panel = _hud_plate("HudTop", Vector2(5, 4), Vector2(138, 13), Color(0.02, 0.025, 0.035, 0.82))
	score_panel = _hud_plate("HudScore", Vector2(221, 4), Vector2(94, 27), Color(0.025, 0.025, 0.035, 0.86))
	# The rank/score sits bare on the arena - no plate behind it. Its heavy text
	# outline is what keeps it legible over the floor.
	wave_label = _hud_label(Vector2(10, 5), Vector2(130, 11), Color(0.96, 0.92, 0.74, 1.0), 7, HORIZONTAL_ALIGNMENT_LEFT)
	score_label = _hud_label(Vector2(227, 6), Vector2(84, 20), Color(0.95, 0.96, 1.0, 1.0), 7, HORIZONTAL_ALIGNMENT_RIGHT)
	combo_label = _hud_label(Vector2(11, 134), Vector2(120, 20), Color(1.0, 0.82, 0.25, 1.0), 8, HORIZONTAL_ALIGNMENT_LEFT)
	combo_label.add_theme_constant_override("outline_size", 4)
	# Slim bar under the rank showing progress toward the next tier, so style is
	# something you watch climb instead of a word that changes at random.
	style_bar_bg = ColorRect.new()
	style_bar_bg.name = "StyleBarBg"
	style_bar_bg.position = Vector2(11, 156)
	style_bar_bg.size = Vector2(94, 4)
	style_bar_bg.color = Color(0.03, 0.03, 0.05, 0.72)
	style_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(style_bar_bg)
	style_bar_fill = ColorRect.new()
	style_bar_fill.name = "StyleBarFill"
	style_bar_fill.position = Vector2(12, 157)
	style_bar_fill.size = Vector2(0, 2)
	style_bar_fill.color = Color(1.0, 0.82, 0.25, 1.0)
	style_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(style_bar_fill)
	enemies_label = _hud_label(Vector2(0, 0), Vector2(1, 1), Color(1.0, 0.62, 0.55, 1.0), 7, HORIZONTAL_ALIGNMENT_RIGHT)
	enemies_label.visible = false
	reward_label = _hud_label(Vector2(60, 122), Vector2(200, 12), Color(0.55, 1.0, 0.86, 1.0), 8, HORIZONTAL_ALIGNMENT_CENTER)
	reward_label.modulate.a = 0.0
	_refresh_hud()

func _build_ability_bar() -> void:
	ability_slots.clear()
	ability_panel = HBoxContainer.new()
	ability_panel.name = "AbilityBar"
	# Bottom-right, clear of the rank text and the cat's health bar.
	# 6 slots x 28 + 5 gaps x 2 = 178px, ending just shy of x320.
	ability_panel.position = Vector2(138, 146)
	ability_panel.add_theme_constant_override("separation", 2)
	$UI.add_child(ability_panel)
	_add_ability_slot("PAW", "m1", Color(0.48, 1.0, 0.66, 0.95))
	_add_ability_slot("DASH", "spc", Color(0.62, 0.9, 1.0, 0.95))
	_add_ability_slot("JAW", "m2", Color(1.0, 0.45, 0.34, 0.95))
	_add_ability_slot("TAIL", "m2+", Color(0.5, 0.78, 1.0, 0.95))
	_add_ability_slot("GLARE", "e", Color(1.0, 0.28, 0.45, 0.95))
	_add_ability_slot("ULT", "q", Color(1.0, 0.35, 1.0, 0.95))

func _hex_points(size: Vector2) -> PackedVector2Array:
	var w: float = size.x
	var h: float = size.y
	return PackedVector2Array([
		Vector2(w * 0.25, 0.0),
		Vector2(w * 0.75, 0.0),
		Vector2(w, h * 0.5),
		Vector2(w * 0.75, h),
		Vector2(w * 0.25, h),
		Vector2(0.0, h * 0.5),
	])

func _add_ability_slot(key: String, hint: String, color: Color) -> void:
	var root := Control.new()
	var slot_size := Vector2(28.0, 23.0)
	root.custom_minimum_size = slot_size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hex: PackedVector2Array = _hex_points(slot_size)
	var shadow := Polygon2D.new()
	shadow.position = Vector2(0.0, 1.0)
	shadow.polygon = hex
	shadow.color = Color(0.0, 0.0, 0.0, 0.48)
	root.add_child(shadow)
	var bg := Polygon2D.new()
	bg.polygon = hex
	bg.color = Color(0.018, 0.02, 0.03, 0.94)
	root.add_child(bg)
	var fill := Polygon2D.new()
	fill.polygon = hex
	fill.color = color
	root.add_child(fill)
	var outline_points: PackedVector2Array = _hex_points(slot_size)
	outline_points.append(outline_points[0])
	var outline := Line2D.new()
	outline.points = outline_points
	outline.width = 1.15
	outline.default_color = Color(0.95, 0.9, 0.72, 0.9)
	root.add_child(outline)
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", 5)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("outline_size", 2)
	label.text = hint
	root.add_child(label)
	ability_panel.add_child(root)
	ability_slots[key] = {"fill": fill, "label": label, "color": color, "hint": hint}

func _update_ability_bar() -> void:
	if ability_panel == null:
		return
	var cat: Node = get_tree().get_first_node_in_group("player")
	if cat == null or not is_instance_valid(cat):
		ability_panel.visible = false
		return
	ability_panel.visible = true
	_set_ability_slot("PAW", float(cat.get("paw_cd")), float(cat.get("paw_cooldown")))
	_set_ability_slot("DASH", float(cat.get("dash_cd_left")), float(cat.get("dash_cooldown")))
	var bite_cd: float = maxf(float(cat.get("bite_cd_left")), float(cat.get("bite_lock_timer")))
	var bite_max: float = maxf(float(cat.get("bite_cooldown")), float(cat.get("bite_lock")))
	_set_ability_slot("JAW", bite_cd, bite_max)
	_set_ability_slot("TAIL", float(cat.get("tail_cd")), float(cat.get("tail_cooldown")))
	_set_ability_slot("GLARE", float(cat.get("leer_cd")), float(cat.get("leer_cooldown")))
	_update_ult_slot()

# The ultimate has no cooldown - it is gated on being in a boss fight with a
# full SS meter, so the slot fills with the meter and only lights up when the
# whole thing is actually available.
func _update_ult_slot() -> void:
	if not ability_slots.has("ULT"):
		return
	var slot: Dictionary = ability_slots["ULT"]
	var fill: Polygon2D = slot["fill"]
	var label: Label = slot["label"]
	var ready: bool = _can_ultimate()
	var charge: float = clampf(style_meter / ULT_STYLE_COST, 0.0, 1.0)
	fill.scale = Vector2(charge, 1.0)
	if ready:
		# Pulse so a live ultimate is impossible to miss.
		var pulse: float = 0.72 + 0.28 * sin(Time.get_ticks_msec() * 0.012)
		fill.color = Color(1.0, 0.35 * pulse, 1.0, 0.95)
		label.text = "q"
	elif ult_state != "":
		fill.color = Color(1.0, 0.35, 1.0, 0.95)
		label.text = "ON"
	else:
		fill.color = Color(0.35, 0.1, 0.4, 0.96)
		label.text = "q" if charge >= 1.0 else "%d%%" % int(charge * 100.0)

func _set_ability_slot(key: String, cd: float, max_cd: float) -> void:
	if not ability_slots.has(key):
		return
	var slot: Dictionary = ability_slots[key]
	var fill: Polygon2D = slot["fill"]
	var label: Label = slot["label"]
	var ready: bool = cd <= 0.05
	var fill_ratio: float = 1.0 if ready else 1.0 - clampf(cd / maxf(max_cd, 0.01), 0.0, 1.0)
	fill.scale = Vector2(fill_ratio, 1.0)
	fill.color = slot["color"] if ready else Color(0.12, 0.12, 0.15, 0.96)
	label.text = String(slot["hint"]) if ready else "%.1f" % cd

func _hud_plate(title: String, pos: Vector2, box: Vector2, color: Color) -> ColorRect:
	var plate := ColorRect.new()
	plate.name = title
	plate.position = pos
	plate.size = box
	plate.color = color
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(plate)
	return plate

func _hud_label(pos: Vector2, box: Vector2, color: Color, font_size: int, align: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = pos
	label.size = box
	label.custom_minimum_size = box
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = align
	$UI.add_child(label)
	return label

func _normal_wave_count() -> int:
	var count := waves.size()
	if count > 0 and _is_boss_wave(count - 1):
		count -= 1
	return count

func _refresh_hud() -> void:
	if wave_label == null:
		return
	var rank := _style_rank()
	var left := _live_enemy_count()
	# Mode is tagged onto the wave plate rather than announced once, so you can
	# always see what you signed up for. MEDIUM is the default and stays unmarked.
	var tag := "" if difficulty == 1 else "  %s" % String(_diff()["name"])
	if endless:
		wave_label.text = "ENDLESS  W%d   LEFT %02d%s" % [wave_index + 1, left, tag]
	else:
		wave_label.text = "WAVE %d/%d   LEFT %02d%s" % [clampi(wave_index + 1, 1, _normal_wave_count()), _normal_wave_count(), left, tag]
	score_label.text = "KILLS %d\nCOIN %d" % [kills, coins]
	combo_label.text = "%s\n%d PTS" % [rank, score]
	var rank_col := _rank_color(rank)
	combo_label.add_theme_color_override("font_color", rank_col)
	if style_bar_fill != null:
		style_bar_fill.size = Vector2(92.0 * _rank_fraction(), 2)
		style_bar_fill.color = rank_col

# How far the style meter has climbed through the current rank band, 0..1.
func _rank_fraction() -> float:
	var tiers := [0.0, 70.0, 150.0, 260.0, 390.0, 560.0]
	for i in range(tiers.size() - 1):
		if style_meter < tiers[i + 1]:
			var span: float = tiers[i + 1] - tiers[i]
			return clampf((style_meter - tiers[i]) / maxf(span, 1.0), 0.0, 1.0)
	return 1.0

func _rank_color(rank: String) -> Color:
	if rank == "SS - Ssuper Smexxy":
		return Color(0.75, 0.5, 1.0, 1.0)
	if rank == "S - Smexy":
		return Color(0.45, 0.85, 1.0, 1.0)
	if rank == "A - Awe":
		return Color(0.5, 1.0, 0.45, 1.0)
	if rank == "B - Blowin' up":
		return Color(1.0, 0.88, 0.35, 1.0)
	if rank == "C - Comeback?":
		return Color(1.0, 0.62, 0.42, 1.0)
	return Color(0.86, 0.86, 0.86, 1.0)

func _set_reward(text: String) -> void:
	if reward_label == null:
		return
	reward_label.text = text
	reward_timer = 2.1
	reward_label.modulate.a = 1.0

func _build_boss_bar() -> void:
	boss_panel = Control.new()
	boss_panel.name = "BossBar"
	boss_panel.visible = false
	boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(boss_panel)
	var name_label := Label.new()
	boss_name_label = name_label
	name_label.position = Vector2(60, 4)
	name_label.size = Vector2(200, 12)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.55, 1.0, 1.0))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_label.add_theme_constant_override("outline_size", 3)
	name_label.text = BOSS_NAME
	boss_panel.add_child(name_label)
	var frame := ColorRect.new()
	frame.position = Vector2(66, 18)
	frame.size = Vector2(boss_bar_width, 7)
	frame.color = Color(0.1, 0.02, 0.08, 0.9)
	boss_panel.add_child(frame)
	boss_fill = ColorRect.new()
	boss_fill.position = Vector2(67, 19)
	boss_fill.size = Vector2(boss_bar_width - 2.0, 5)
	boss_fill.color = Color(0.95, 0.2, 0.55, 1.0)
	boss_panel.add_child(boss_fill)

func _boss_name_color(shown_name: String) -> Color:
	if shown_name.begins_with("GHOST"):
		return Color(0.78, 0.6, 1.0, 1.0)
	if shown_name == "THE BOG BARON":
		return Color(0.55, 1.0, 0.42, 1.0)
	return Color(1.0, 0.55, 1.0, 1.0)

func _update_boss_bar() -> void:
	if boss_panel == null:
		return
	var boss := get_tree().get_first_node_in_group("boss")
	if boss == null or not is_instance_valid(boss):
		boss_panel.visible = false
		return
	var mh: float = maxf(1.0, float(boss.get("max_health")))
	var hp: float = clampf(float(boss.get("health")), 0.0, mh)
	boss_panel.visible = true
	if boss_name_label != null:
		var shown_name: String = String(boss.get("boss_name")) if boss.get("boss_name") != null else BOSS_NAME
		boss_name_label.text = shown_name
		boss_name_label.add_theme_color_override("font_color", _boss_name_color(shown_name))
	boss_fill.size = Vector2((boss_bar_width - 2.0) * (hp / mh), 5)

func _build_result_panel() -> void:
	for child in game_over.get_children():
		game_over.remove_child(child)
		child.queue_free()
	game_over.visible = false
	game_over.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.76)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over.add_child(dim)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over.add_child(center)
	var frame := PanelContainer.new()
	frame.name = "Frame"
	frame.add_theme_stylebox_override("panel", _panel_box(
		Color(0.07, 0.05, 0.08, 0.97), Color(1.0, 0.45, 0.35, 0.85)))
	center.add_child(frame)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.custom_minimum_size = Vector2(258, 138)
	box.add_theme_constant_override("separation", 2)
	frame.add_child(box)
	result_title = Label.new()
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_title.add_theme_font_size_override("font_size", 18)
	result_title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35, 1.0))
	box.add_child(result_title)
	result_summary = Label.new()
	result_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_summary.custom_minimum_size = Vector2(258, 42)
	result_summary.add_theme_font_size_override("font_size", 8)
	result_summary.add_theme_color_override("font_color", Color(0.93, 0.9, 0.78, 1.0))
	box.add_child(result_summary)
	result_continue = _make_button("CONTINUE")
	result_continue.pressed.connect(_continue)
	box.add_child(result_continue)
	result_retry = _make_button("RETRY")
	result_retry.pressed.connect(_restart)
	box.add_child(result_retry)
	result_shop = _make_button("SHOP")
	result_shop.pressed.connect(_open_shop)
	box.add_child(result_shop)
	result_menu = _make_button("MENU")
	result_menu.pressed.connect(_to_menu)
	box.add_child(result_menu)

func _finish_run(title: String, success: bool) -> void:
	_clear_hitstop()
	# Killing the boss with the Overdrive combo ends the run mid-execution, and
	# _process stops once the tree is paused - so tear the ultimate down here or
	# the freeze, the neon grade and the ducked music all stay stuck on.
	_end_ultimate()
	SoundManager.set_music_volume(0.5)
	_bank_run()
	_hide_hud()
	result_title.text = title
	result_path = next_level_path if success and next_level_path != "" else "res://scenes/level1.tscn"
	if success and next_level_path != "" and not endless:
		result_continue.text = "NEXT LEVEL"
	else:
		result_continue.text = "RUN AGAIN" if endless else "PLAY AGAIN"
	result_continue.visible = true
	result_summary.text = _result_summary(success)
	game_over.visible = true
	get_tree().paused = true
	result_continue.grab_focus()

func _result_summary(success: bool) -> String:
	var rank := _style_rank()
	var combo_bonus: int = mini(best_chain, 25)
	var clear_bonus: int = 30 if success else 0
	var mode := String(_diff()["name"])
	if endless:
		return "ENDLESS (%s) - reached wave %d\nRank %s   Score %d   Kills %d\nBest chain x%d\nCoins earned +%d   Total %d" % [mode, wave_index + 1, rank, score, kills, best_chain, last_earned, coins]
	return "%s   Rank %s   Score %d   Kills %d\nChain bonus %d   Clear bonus %d\nCoins earned +%d   Total %d" % [mode, rank, score, kills, combo_bonus, clear_bonus, last_earned, coins]

func _build_shop_panel() -> void:
	shop_panel = Control.new()
	shop_panel.name = "ShopPanel"
	shop_panel.visible = false
	shop_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	shop_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_panel.add_child(center)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _panel_box(
		Color(0.06, 0.06, 0.1, 0.97), Color(1.0, 0.84, 0.35, 0.85)))
	center.add_child(frame)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(258, 132)
	box.add_theme_constant_override("separation", 2)
	frame.add_child(box)
	shop_text = Label.new()
	shop_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shop_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_text.custom_minimum_size = Vector2(258, 46)
	shop_text.add_theme_font_size_override("font_size", 9)
	shop_text.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72, 1.0))
	box.add_child(shop_text)
	shop_status = Label.new()
	shop_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_status.custom_minimum_size = Vector2(258, 14)
	shop_status.add_theme_font_size_override("font_size", 8)
	shop_status.add_theme_color_override("font_color", Color(0.48, 0.95, 1.0, 1.0))
	box.add_child(shop_status)
	upgrade_button = _make_button("UPGRADE GLARE")
	upgrade_button.pressed.connect(_upgrade_glare)
	box.add_child(upgrade_button)
	var retry_button := _make_button("RETRY RUN")
	retry_button.pressed.connect(_restart)
	box.add_child(retry_button)
	var menu_button := _make_button("MAIN MENU")
	menu_button.pressed.connect(_to_menu)
	box.add_child(menu_button)
	var back_button := _make_button("BACK")
	back_button.pressed.connect(_close_shop)
	box.add_child(back_button)
	$UI.add_child(shop_panel)
	_refresh_shop()

func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(180, 17)
	button.add_theme_font_size_override("font_size", 9)
	button.add_theme_stylebox_override("normal", _button_box(Color(0.13, 0.12, 0.16, 1), Color(0.32, 0.3, 0.36, 1)))
	button.add_theme_stylebox_override("hover", _button_box(Color(0.2, 0.15, 0.19, 1), Color(0.86, 0.28, 0.34, 1)))
	button.add_theme_stylebox_override("pressed", _button_box(Color(0.1, 0.09, 0.12, 1), Color(0.86, 0.28, 0.34, 1)))
	button.add_theme_stylebox_override("focus", _button_box(Color(0.2, 0.15, 0.19, 1), Color(0.86, 0.28, 0.34, 1)))
	button.add_theme_color_override("font_color", Color(0.92, 0.9, 0.94, 1))
	return button

# Shared look for every framed card (tutorial coach, break, pause, results):
# soft rounded corners, a coloured hairline border and a drop shadow, so the
# menus read as one deliberate set instead of raw black rectangles.
func _panel_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(1)
	s.border_color = border
	s.set_corner_radius_all(3)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 3
	s.content_margin_left = 5.0
	s.content_margin_right = 5.0
	s.content_margin_top = 4.0
	s.content_margin_bottom = 4.0
	return s

func _button_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(1)
	s.border_color = border
	s.set_corner_radius_all(2)
	s.content_margin_top = 2.0
	s.content_margin_bottom = 2.0
	s.content_margin_left = 4.0
	s.content_margin_right = 4.0
	return s

func _open_shop() -> void:
	_refresh_shop()
	shop_panel.visible = true
	upgrade_button.grab_focus()

func _close_shop() -> void:
	shop_panel.visible = false
	if game_over.visible:
		result_shop.grab_focus()

func _upgrade_glare() -> void:
	var costs := [0, 150, 340]
	if glare_level >= 3:
		_refresh_shop("Glare is maxed.")
		return
	var next_cost: int = costs[glare_level]
	if coins < next_cost:
		_refresh_shop("Need %d more coins." % (next_cost - coins))
		return
	coins -= next_cost
	glare_level += 1
	_save_profile_values()
	_refresh_shop("Upgrade bought. Next run starts stronger.")
	if game_over.visible:
		result_summary.text = _result_summary(cleared)

func _refresh_shop(message: String = "") -> void:
	var stuns := [0.35, 0.6, 0.85]
	var costs := [0, 150, 340]
	var text := "SHOP\nCoins: %d   Glare L%d %.2fs" % [coins, glare_level, stuns[glare_level - 1]]
	if glare_level < 3:
		text += "\nNext %.2fs costs %d" % [stuns[glare_level], costs[glare_level]]
		upgrade_button.text = "UPGRADE GLARE"
		upgrade_button.disabled = false
	else:
		text += "\nGlare maxed."
		upgrade_button.text = "MAXED"
		upgrade_button.disabled = true
	shop_text.text = text
	shop_status.text = message
	_refresh_hud()

func _build_pause_panel() -> void:
	pause_panel = Control.new()
	pause_panel.name = "PausePanel"
	pause_panel.visible = false
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(center)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _panel_box(
		Color(0.05, 0.05, 0.08, 0.97), Color(1.0, 0.84, 0.35, 0.85)))
	center.add_child(frame)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(210, 96)
	box.add_theme_constant_override("separation", 3)
	frame.add_child(box)
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35, 1.0))
	title.text = "PAUSED"
	box.add_child(title)
	pause_resume = _make_button("RESUME")
	pause_resume.pressed.connect(_resume_game)
	box.add_child(pause_resume)
	pause_retry = _make_button("RETRY")
	pause_retry.pressed.connect(_restart)
	box.add_child(pause_retry)
	pause_menu = _make_button("MAIN MENU")
	pause_menu.pressed.connect(_to_menu)
	box.add_child(pause_menu)
	$UI.add_child(pause_panel)

# --- Coached tutorial -------------------------------------------------------
#
# One idea at a time: read it, then do it. Every step names its input, states
# what the move is FOR, and waits on the player actually performing it - no
# wall of text up front, and no way to skip past something untried.
#
#   goal    - the style_event kind that counts as progress ("move"/"aim" are
#             polled instead, since the cat does not emit those)
#   need    - how many times to do it
#   dummies - practice rats to keep alive during the step
#   armed   - dummies that wind up attacks (for the parry lesson)
const TUTORIAL_STEPS := [
	{"title": "PROWL", "text": "WASD or the ARROW KEYS to move.",
		"goal": "move", "need": 1},
	{"title": "AIM", "text": "Your MOUSE aims every attack - the cat strikes wherever the cursor is, not where she is facing. Wave it around.",
		"goal": "aim", "need": 1},
	{"title": "PAW", "text": "LEFT CLICK to swipe. Fast and cheap - your bread and butter. Aim at the rat and hit it.",
		"goal": "paw_hit", "need": 4, "dummies": 1},
	{"title": "DASH", "text": "SPACE to dash. You are briefly untouchable mid-dash - it is your dodge. Try two.",
		"goal": "dash", "need": 2},
	{"title": "JAW", "text": "RIGHT CLICK (a quick tap) to bite. It roots you for a beat, so pick your moment - but it hurts, and it makes them bleed.",
		"goal": "bite", "need": 2, "dummies": 1},
	{"title": "TAIL", "text": "HOLD RIGHT CLICK to sweep your tail. Barely any damage - it is for flinging a crowd off you when you get swarmed.",
		"goal": "tail", "need": 2, "dummies": 2},
	{"title": "LEER", "text": "Press E to LEER. It stuns everything in front of you and MARKS it. Free to use - never hold it back.",
		"goal": "glare", "need": 1, "dummies": 2},
	{"title": "EXECUTE", "text": "Marked prey has a red chevron. Kill a marked foe for a bonus EXECUTE. Leer them, then finish them.",
		"goal": "execute", "need": 1, "dummies": 3},
	{"title": "PARRY", "text": "Enemies flash their tell before striking. When it turns WHITE, DASH INTO them to freeze them cold.",
		"goal": "parry", "need": 1, "armed": 1},
]

var tutorial_active: bool = false
var tut_progress: int = 0
var tut_dummies: Array = []
var tut_move_origin: Vector2 = Vector2.ZERO
var tut_mouse_origin: Vector2 = Vector2.ZERO
var tut_ready_timer: float = 0.0
var tutorial_title: Label
var tutorial_progress: Label

func _build_tutorial_panel() -> void:
	# Non-blocking coach card pinned under the top HUD: the fight keeps running
	# underneath so the player can practise while reading.
	tutorial_panel = Control.new()
	tutorial_panel.name = "TutorialPanel"
	tutorial_panel.visible = false
	tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_panel.position = Vector2(25, 22)
	tutorial_panel.size = Vector2(270, 52)
	var card := Panel.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", _panel_box(
		Color(0.05, 0.07, 0.12, 0.92), Color(1.0, 0.84, 0.35, 0.9)))
	tutorial_panel.add_child(card)
	tutorial_title = Label.new()
	tutorial_title.position = Vector2(7, 3)
	tutorial_title.size = Vector2(185, 12)
	tutorial_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_title.add_theme_font_size_override("font_size", 10)
	tutorial_title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35, 1.0))
	tutorial_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	tutorial_title.add_theme_constant_override("outline_size", 3)
	tutorial_panel.add_child(tutorial_title)
	tutorial_progress = Label.new()
	tutorial_progress.position = Vector2(198, 3)
	tutorial_progress.size = Vector2(65, 12)
	tutorial_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tutorial_progress.add_theme_font_size_override("font_size", 10)
	tutorial_progress.add_theme_color_override("font_color", Color(0.5, 1.0, 0.86, 1.0))
	tutorial_progress.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	tutorial_progress.add_theme_constant_override("outline_size", 3)
	tutorial_panel.add_child(tutorial_progress)
	tutorial_text = Label.new()
	tutorial_text.position = Vector2(7, 16)
	tutorial_text.size = Vector2(256, 34)
	tutorial_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_text.add_theme_font_size_override("font_size", 9)
	tutorial_text.add_theme_color_override("font_color", Color(0.95, 0.94, 0.86, 1.0))
	tutorial_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	tutorial_text.add_theme_constant_override("outline_size", 2)
	tutorial_panel.add_child(tutorial_text)
	$UI.add_child(tutorial_panel)

func _start_tutorial() -> void:
	tutorial_active = true
	tutorial_step = 0
	_play_music(WAVE_MUSIC)
	_begin_tutorial_step()

func _begin_tutorial_step() -> void:
	if tutorial_step >= TUTORIAL_STEPS.size():
		_finish_tutorial()
		return
	var step: Dictionary = TUTORIAL_STEPS[tutorial_step]
	tut_progress = 0
	tut_ready_timer = 0.35
	tutorial_title.text = String(step["title"])
	tutorial_text.text = String(step["text"])
	tutorial_panel.visible = true
	var cat := get_tree().get_first_node_in_group("player")
	if cat != null and is_instance_valid(cat):
		tut_move_origin = cat.global_position
	tut_mouse_origin = get_viewport().get_mouse_position()
	_update_tutorial_progress()
	_ensure_tut_dummies(int(step.get("dummies", 0)), int(step.get("armed", 0)))

func _update_tutorial_progress() -> void:
	if not tutorial_active or tutorial_step >= TUTORIAL_STEPS.size():
		return
	var need := int(TUTORIAL_STEPS[tutorial_step].get("need", 1))
	tutorial_progress.text = "%d/%d" % [mini(tut_progress, need), need] if need > 1 else ""

# Practice fodder: enough health to survive the lesson, and (except for the
# parry step) completely harmless, so nobody dies learning the controls.
func _ensure_tut_dummies(count: int, armed: int) -> void:
	_clear_tut_dummies()
	for i in count:
		_spawn_tut_dummy(false)
	for i in armed:
		_spawn_tut_dummy(true)

func _spawn_tut_dummy(armed: bool) -> void:
	if rat_scene == null:
		return
	var cfg := {
		"max_health": 3 if armed else 6,
		"move_speed": 52.0 if armed else 30.0,
		"nibble_damage": 0, "dash_damage": 0,
		"score_value": 0,
		"tint": Color(1.0, 0.85, 0.5) if armed else Color(0.8, 0.9, 1.0),
		"body_scale": 0.72,
	}
	if armed:
		# Wants to lunge often so the white parry flash comes around quickly.
		cfg["dash_chance"] = 1.0
		cfg["dash_cooldown_min"] = 1.1
		cfg["dash_cooldown_max"] = 1.7
		cfg["dash_windup"] = 0.6
		cfg["nibble_interval"] = 1.4
	else:
		cfg["dash_chance"] = 0.0
		cfg["nibble_interval"] = 3.0
	var e := rat_scene.instantiate()
	if e.has_method("configure"):
		e.configure(cfg)
	e.position = _spawn_point()
	add_child(e)
	tut_dummies.append(e)
	if e.has_signal("died"):
		e.died.connect(_on_tut_dummy_died.bind(e))

func _on_tut_dummy_died(dummy: Node) -> void:
	tut_dummies.erase(dummy)
	# Killing the practice dummy should never soft-lock the lesson.
	if not tutorial_active or tutorial_step >= TUTORIAL_STEPS.size():
		return
	var step: Dictionary = TUTORIAL_STEPS[tutorial_step]
	var wanted := int(step.get("dummies", 0)) + int(step.get("armed", 0))
	if wanted > 0 and _live_tut_dummies() < wanted:
		_spawn_tut_dummy(int(step.get("armed", 0)) > 0)

func _live_tut_dummies() -> int:
	var n := 0
	for d in tut_dummies:
		if is_instance_valid(d) and not bool(d.get("dead")):
			n += 1
	return n

func _clear_tut_dummies() -> void:
	for d in tut_dummies:
		if is_instance_valid(d):
			d.queue_free()
	tut_dummies.clear()

# Counts a completed rep. Called from _on_style_event for everything the cat
# already reports, and from _process for the polled move/aim steps.
func _tutorial_credit(kind: String) -> void:
	if not tutorial_active or tutorial_step >= TUTORIAL_STEPS.size():
		return
	if tut_ready_timer > 0.0:
		return
	var step: Dictionary = TUTORIAL_STEPS[tutorial_step]
	if String(step["goal"]) != kind:
		return
	tut_progress += 1
	_update_tutorial_progress()
	if tut_progress < int(step.get("need", 1)):
		_flash(Color(0.6, 1.0, 0.8), 0.1)
		return
	_hype("NICE!", Color(0.5, 1.0, 0.7))
	_flash(Color(0.6, 1.0, 0.8), 0.28)
	tutorial_step += 1
	await get_tree().create_timer(0.85, false).timeout
	if tutorial_active:
		_begin_tutorial_step()

func _tick_tutorial(delta: float) -> void:
	if not tutorial_active or tutorial_step >= TUTORIAL_STEPS.size():
		return
	tut_ready_timer = maxf(tut_ready_timer - delta, 0.0)
	var goal := String(TUTORIAL_STEPS[tutorial_step]["goal"])
	if goal == "move":
		var cat := get_tree().get_first_node_in_group("player")
		if cat != null and is_instance_valid(cat):
			if cat.global_position.distance_to(tut_move_origin) > 34.0:
				_tutorial_credit("move")
	elif goal == "aim":
		if get_viewport().get_mouse_position().distance_to(tut_mouse_origin) > 60.0:
			_tutorial_credit("aim")

func _finish_tutorial() -> void:
	tutorial_active = false
	tutorial_panel.visible = false
	_clear_tut_dummies()
	_hype("GO HUNT!", Color(1.0, 0.84, 0.35))
	_set_reward("That's the whole kit. Now use it.")
	_build_waves()
	_next_wave()

func _load_profile() -> void:
	var config := ConfigFile.new()
	var err := config.load("user://macatre_profile.cfg")
	if err == OK:
		best_record = int(config.get_value("records", "best_score", 0))
		coins = int(config.get_value("shop", "coins", 0))
		glare_level = int(config.get_value("shop", "glare_level", 1))
		difficulty = int(config.get_value("options", "difficulty", 1))
	glare_level = clampi(glare_level, 1, 3)
	difficulty = clampi(difficulty, 0, DIFFICULTIES.size() - 1)

func _bank_run() -> void:
	if profile_saved:
		return
	profile_saved = true
	# Payout is deliberately thin. Coins persist between runs, so a generous rate
	# compounds into "buy everything on run two" within an evening. A strong clear
	# should fund roughly one meaningful upgrade, not the whole shop.
	var combo_bonus: int = mini(best_chain, 25)
	var clear_bonus: int = 30 if cleared else 0
	var raw: float = float(score) * 0.035 + style_meter * _rank_coin_multiplier() * 0.11 + float(combo_bonus + clear_bonus)
	last_earned = maxi(0, int(raw * float(_diff()["coin"])))
	coins += last_earned
	best_record = max(best_record, score)
	_save_profile_values()
	_refresh_hud()

func _save_profile_values() -> void:
	var config := ConfigFile.new()
	config.load("user://macatre_profile.cfg")
	config.set_value("records", "best_score", best_record)
	config.set_value("shop", "coins", coins)
	config.set_value("shop", "glare_level", glare_level)
	config.set_value("shop", "last_score", score)
	config.set_value("shop", "last_style", int(style_meter))
	config.set_value("shop", "last_earned", last_earned)
	config.set_value("shop", "last_rank", _style_rank())
	config.set_value("options", "difficulty", difficulty)
	config.save("user://macatre_profile.cfg")
