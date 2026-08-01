extends Node2D

# A dropped goodie. Bobs in place, drifts toward the cat once she is close
# enough to "smell" it, and blinks out its last couple of seconds so a pickup
# never silently vanishes.

signal collected(kind: String)

const LIFETIME: float = 13.0
const BLINK_AT: float = 3.5
const MAGNET_RANGE: float = 26.0
const GRAB_RANGE: float = 7.0

# 1px-per-cell heart. Drawn rather than imported so the drop always matches the
# palette of the HUD instead of needing its own art pass.
const HEART := [
	".XX.XX.",
	"XXXXXXX",
	"XXXXXXX",
	".XXXXX.",
	"..XXX..",
	"...X...",
]

var kind: String = "health"
var amount: int = 2
var life: float = 0.0
var bob: float = 0.0
var pop: float = 1.0
var player: Node2D = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 30
	bob = randf() * TAU
	# Little arrival pop so a drop reads instantly even in a busy fight.
	scale = Vector2.ZERO
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(1.25, 1.25), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "scale", Vector2.ONE, 0.1)

func _process(delta: float) -> void:
	life += delta
	bob += delta * 4.0
	if life >= LIFETIME:
		queue_free()
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
	if player != null and is_instance_valid(player) and not bool(player.get("dead")):
		var to_player: Vector2 = player.global_position - global_position
		var distance := to_player.length()
		if distance <= GRAB_RANGE:
			_collect()
			return
		if distance <= MAGNET_RANGE:
			# Ease in the pull so it snaps satisfyingly at the end.
			var pull: float = 1.0 - (distance - GRAB_RANGE) / maxf(MAGNET_RANGE - GRAB_RANGE, 0.01)
			global_position += to_player.normalized() * (30.0 + 150.0 * pull) * delta
	queue_redraw()

func _collect() -> void:
	if player != null and is_instance_valid(player) and player.has_method("heal"):
		player.heal(amount)
	collected.emit(kind)
	queue_free()

func _draw() -> void:
	# Blink out the final seconds; skip drawing on the "off" beat.
	var remaining: float = LIFETIME - life
	if remaining <= BLINK_AT and fmod(remaining, 0.34) < 0.17:
		return
	var lift: float = sin(bob) * 1.5
	var body := Color(1.0, 0.32, 0.42)
	var shine := Color(1.0, 0.72, 0.78)
	var w: int = HEART[0].length()
	var h: int = HEART.size()
	var origin := Vector2(-float(w) * 0.5, -float(h) * 0.5 + lift)
	# Soft glow pad underneath so it pops against the floor tiles.
	draw_circle(Vector2(0.0, lift), 6.0, Color(1.0, 0.35, 0.45, 0.16))
	draw_circle(Vector2(0.0, 3.0), 3.2, Color(0.0, 0.0, 0.0, 0.22))
	for y in h:
		var row: String = HEART[y]
		for x in w:
			if row[x] != "X":
				continue
			var col: Color = shine if (y <= 1 and x >= 1 and x <= 2) else body
			draw_rect(Rect2(origin + Vector2(float(x), float(y)), Vector2.ONE), col)
