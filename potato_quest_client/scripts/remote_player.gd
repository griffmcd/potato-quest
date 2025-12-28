extends CharacterBody3D
## RemotePlayer - Represents another player in the game
##
## Displays and interpolates movement for remote players.
## Spawned dynamically by MainGame when players join.

@export var interpolation_speed: float = 10.0

var player_id: String = ""
var player_username: String = ""
var target_position: Vector3 = Vector3.ZERO
var target_body_rotation: float = 0.0  # Body Y rotation (which way character faces)
var username_label: Label3D = null

@onready var animation_player: AnimationPlayer = $Body/AnimationPlayer


func _ready() -> void:
	# Create a username label above the player
	username_label = Label3D.new()
	username_label.text = player_username
	username_label.pixel_size = 0.01
	username_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	username_label.position = Vector3(0, 2.5, 0)  # Above the capsule
	username_label.modulate = Color(1, 1, 0)  # Yellow text
	add_child(username_label)

	# Set initial target
	target_position = global_position


func _physics_process(delta: float) -> void:
	# Smoothly interpolate to target position
	global_position = global_position.lerp(target_position, interpolation_speed * delta)

	# Smoothly interpolate body rotation
	# Apply model-specific forward offset to compensate for different mesh orientations
	var body = $Body
	body.rotation.y = lerp_angle(body.rotation.y, target_body_rotation, interpolation_speed * delta)

	_update_animation_state()


## Update the target position for this remote player
func update_position(new_position: Vector3) -> void:
	target_position = new_position


## Update the target rotation for this remote player
func update_rotation(rotation_data: Dictionary) -> void:
	# rotation_data contains: pitch, yaw, rotation_y
	# For now, we only care about rotation_y (body rotation)
	target_body_rotation = rotation_data.get("rotation_y", 0.0)


## Set the player's username (updates label)
func set_username(new_username: String) -> void:
	player_username = new_username
	if username_label:
		username_label.text = new_username

func _update_animation_state() -> void:
	if not animation_player:
		return 
	var distance_to_target = global_position.distance_to(target_position)
	var is_moving = distance_to_target > 0.1 
	if is_moving:
		if animation_player.current_animation != "walk":
			animation_player.play("walk")
	else:
		if animation_player.current_animation != "idle":
			animation_player.play("idle")
