extends CharacterBody2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var dash_timer: Timer = $DashTimer
@onready var sprite_2d: Sprite2D = $Sprite2D

var normal_speed: float = 200
var dash_speed: float = normal_speed * 1.5
var speed: float = normal_speed

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("dash"):
		dash()

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

func dash() -> void:
	dash_timer.start()
	speed = dash_speed
	sprite_2d.material.set_shader_parameter("active", true)

func _on_dash_timer_timeout() -> void:
	speed = normal_speed
	sprite_2d.material.set_shader_parameter("active", false)
