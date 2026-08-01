extends SceneTree

# Dev utility: assemble the sliced pigeon PNGs into a SpriteFrames resource.
#   godot --headless --script res://tools/build_pigeon_frames.gd

const SRC := "res://sprites/pigeon"
const OUT := "res://sprites/pigeon_frames.tres"

# animation, frame count, fps, loops
const ANIMS := [
	["idle", 4, 7.0, true],
	["fly", 6, 12.0, true],
	["hurt", 4, 11.0, false],
	["death", 6, 9.0, false],
]

# in-game direction suffix -> sheet row suffix
const DIRS := {"front": "front", "back": "back", "side": "side_b"}

func _initialize() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var made := 0
	for entry in ANIMS:
		var anim := String(entry[0])
		var count := int(entry[1])
		for dir in DIRS:
			var row := String(DIRS[dir])
			var anim_name := "%s_%s" % [anim, dir]
			frames.add_animation(anim_name)
			frames.set_animation_speed(anim_name, float(entry[2]))
			frames.set_animation_loop(anim_name, bool(entry[3]))
			for i in count:
				var path := "%s/%s_%s_%d.png" % [SRC, anim, row, i]
				var tex: Texture2D = load(path)
				if tex == null:
					printerr("missing ", path)
					continue
				frames.add_frame(anim_name, tex)
			made += 1
	var err := ResourceSaver.save(frames, OUT)
	print("saved ", OUT, " with ", made, " animations, err=", err)
	quit()
