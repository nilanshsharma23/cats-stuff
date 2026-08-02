extends Control

# Health as a row of little hearts instead of a red bar. Two reasons: it matches
# the heart the enemies drop (so "that pickup refills these" needs no
# explaining), and discrete pips are readable at a glance in a fight, where a
# continuous bar just looks "somewhat red".

const HEART := [
	".XX.XX.",
	"XXXXXXX",
	"XXXXXXX",
	".XXXXX.",
	"..XXX..",
	"...X...",
]

const PIP_W := 7
const PIP_H := 6
const GAP := 2

const FULL := Color(1.0, 0.32, 0.42)
const FULL_SHINE := Color(1.0, 0.72, 0.78)
const EMPTY := Color(0.30, 0.13, 0.18, 0.85)

var health: int = 0
var max_health: int = 0
var pulse: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_health(current: int, maximum: int) -> void:
	if current == health and maximum == max_health:
		return
	health = current
	max_health = maximum
	queue_redraw()

func _process(delta: float) -> void:
	# Only the last heart animates, and only when it is the last one left.
	if health > 1 or max_health <= 0:
		return
	pulse += delta * 6.0
	queue_redraw()

func _draw() -> void:
	for i in max_health:
		var filled: bool = i < health
		var origin := Vector2(float(i * (PIP_W + GAP)), 0.0)
		var body: Color = FULL if filled else EMPTY
		# The final heart throbs so "one hit left" is impossible to miss.
		if filled and health == 1:
			body = FULL.lerp(Color.WHITE, 0.35 + 0.35 * sin(pulse))
		for y in PIP_H:
			var row: String = HEART[y]
			for x in PIP_W:
				if row[x] != "X":
					continue
				var col: Color = body
				if filled and y <= 1 and x >= 1 and x <= 2:
					col = FULL_SHINE
				# 1px drop shadow keeps the pips readable on light floor tiles.
				draw_rect(Rect2(origin + Vector2(float(x), float(y) + 1.0), Vector2.ONE),
					Color(0, 0, 0, 0.45))
				draw_rect(Rect2(origin + Vector2(float(x), float(y)), Vector2.ONE), col)
