extends Node2D

# Brief "incoming!" telegraph at a spawn point: a ring that converges on the
# spot for `life` seconds, then frees itself. The enemy appears as it ends.

var life: float = 0.5
var t: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 40

func _process(delta: float) -> void:
	t += delta
	queue_redraw()
	if t >= life:
		queue_free()

func _draw() -> void:
	var k: float = clampf(t / maxf(life, 0.01), 0.0, 1.0)
	var col := Color(1.0, 0.85, 0.3, 0.25 + 0.6 * k)
	draw_arc(Vector2.ZERO, 12.0 - 8.0 * k, 0.0, TAU, 24, col, 1.4, true)
	draw_circle(Vector2.ZERO, 1.2 + 2.2 * k, Color(1.0, 0.55, 0.2, 0.45 + 0.45 * k))
