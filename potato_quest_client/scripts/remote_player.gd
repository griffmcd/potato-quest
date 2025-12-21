extends CharacterBody3D
## RemotePlayer - Represents another player in the game
##
## Displays and interpolates movement for remote players.
## Spawned dynamically by MainGame when players join.

@export var interpolation_speed: float = 10.0

# Player info
var player_id: String = ""
var player_username: String = ""

# Position interpolation
var target_position: Vector3 = Vector3.ZERO
var target_rotation: float = 0.0

# Optional: Reference to label showing username
var username_label: Label3D = null


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

	# Smoothly interpolate rotation
	rotation.y = lerp_angle(rotation.y, target_rotation, interpolation_speed * delta)


## Update the target position for this remote player
func update_position(new_position: Vector3) -> void:
	# Calculate rotation based on movement direction
	var direction = new_position - target_position

	if direction.length() > 0.1:
		target_rotation = atan2(direction.x, direction.z)

	target_position = new_position


## Set the player's username (updates label)
func set_username(new_username: String) -> void:
	player_username = new_username
	if username_label:
		username_label.text = new_username
