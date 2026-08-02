extends Node2D

# Bouncing arrow over a tutorial practice target. Without it a lesson that says
# "hit the rat" leaves the player scanning a room that may also contain the
# leftovers of the previous lesson - this points at the thing they are meant to
# be hitting.

const COLOUR := Color(1.0, 0.86, 0.3)

var age: float = 0.0
var lift: float = 20.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	z_index = 46

func _process(delta: float) -> void:
	age += delta
	queue_redraw()

func _draw() -> void:
	var bob: float = sin(age * 4.5) * 2.0
	var tip := Vector2(0.0, -lift + bob)
	var w := 4.0
	var h := 5.0
	# Solid downward chevron with a dark shim behind it so it reads on any tile.
	var shadow := PackedVector2Array([
		tip + Vector2(-w, -h) + Vector2(0, 1),
		tip + Vector2(w, -h) + Vector2(0, 1),
		tip + Vector2(0, 1),
	])
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.55))
	var body := PackedVector2Array([
		tip + Vector2(-w, -h),
		tip + Vector2(w, -h),
		tip,
	])
	draw_colored_polygon(body, COLOUR)
