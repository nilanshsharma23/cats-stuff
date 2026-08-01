extends Node2D

# A queued OVERDRIVE action, pinned to the spot where it will land. These are
# the player's read on their own plan: without them the 5 second window is just
# flailing at frozen statues and hoping.

const GLYPH := {
	"paw": Color(0.55, 1.0, 0.75),
	"bite": Color(1.0, 0.45, 0.35),
	"tail": Color(0.5, 0.8, 1.0),
	"leer": Color(1.0, 0.35, 0.55),
}

var kind: String = "paw"
var index: int = 1
var age: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 45
	scale = Vector2.ZERO
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	age += delta
	queue_redraw()

func _draw() -> void:
	var col: Color = GLYPH.get(kind, Color(1.0, 0.6, 1.0))
	var pulse: float = 0.65 + 0.35 * sin(age * 7.0)
	# Ring plus a tick mark per queued step, so the ordering is legible.
	draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 18, Color(col.r, col.g, col.b, 0.85 * pulse), 1.3, true)
	draw_arc(Vector2.ZERO, 3.0, 0.0, TAU, 12, Color(1.0, 1.0, 1.0, 0.5 * pulse), 1.0, true)
	var ticks: int = mini(index, 6)
	for i in ticks:
		var ang: float = -PI * 0.5 + float(i) * 0.42
		var dir := Vector2(cos(ang), sin(ang))
		draw_line(dir * 7.5, dir * 9.5, Color(col.r, col.g, col.b, 0.9), 1.0)
