extends CharacterBody2D

@export var speed: int = 200

@onready var animation_player: AnimationPlayer = $AnimationPlayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _physics_process(_delta: float) -> void:
	var input_direction = Input.get_vector("left", "right", "forward", "backward").normalized()
	velocity = input_direction * speed
	move_and_slide()
	
	if input_direction != Vector2.ZERO:
		if abs(input_direction.x) > abs(input_direction.y):
			if input_direction.x > 0:
				animation_player.play("walk_right")
			else:
				animation_player.play("walk_left")
		else:
			if input_direction.y > 0:
				animation_player.play("walk_back")
			else:
				animation_player.play("walk_front")
	else:
		animation_player.play("idle")
