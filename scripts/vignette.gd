extends Control

# Edge-of-screen danger tint. Nested border bands fake a vignette cheaply at
# 256x144 - no shader, no texture. `intensity` is driven by the level from the
# cat's remaining health, and the pulse speeds up the closer she is to dying.

var intensity: float = 0.0
var pulse: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
	if intensity <= 0.001:
		return
	pulse += delta * (3.2 + 2.6 * intensity)
	queue_redraw()

func set_intensity(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(next, intensity):
		return
	intensity = next
	queue_redraw()

func _draw() -> void:
	if intensity <= 0.001:
		return
	var box := size
	var breathe: float = 0.72 + 0.28 * sin(pulse)
	var bands: int = 9
	for i in bands:
		# Outermost band is the most opaque, fading inward.
		var t: float = 1.0 - float(i) / float(bands)
		var alpha: float = 0.3 * intensity * breathe * t * t
		var inset := float(i)
		draw_rect(Rect2(inset, inset, box.x - inset * 2.0, box.y - inset * 2.0),
			Color(0.85, 0.06, 0.12, alpha), false, 1.0)
