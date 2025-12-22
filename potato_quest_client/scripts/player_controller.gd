extends CharacterBody3D
## PlayerController - Controls the local player character
##
## Handles WASD movement, sends position updates to server,
## and manages player visuals.

@export var move_speed: float = 5.0
@export var rotation_speed: float = 10.0
@export var position_send_interval: float = 0.1  # Send position every 100ms

# Movement tracking
var _last_sent_position: Vector3 = Vector3.ZERO
var _position_send_timer: float = 0.0
var _move_threshold: float = 0.5  # Minimum movement to trigger update

# Reference to NetworkManager (autoload)
@onready var network = get_node("/root/NetworkManager")


func _ready() -> void:
	# Set initial position
	_last_sent_position = global_position


func _physics_process(delta: float) -> void:
	# Get input for movement
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	# Get camera rig reference for camera-relative movement
	var camera_rig = $CameraRig

	if input_dir.length() > 0:
		# Calculate movement direction relative to camera
		# Use the camera rig's Y rotation directly
		var cam_y_rotation = camera_rig.rotation.y

		# Create forward and right vectors based on camera Y rotation
		# Note: In Godot, Z+ is backward, so we negate for forward movement
		var camera_forward = Vector3(-sin(cam_y_rotation), 0, -cos(cam_y_rotation))
		var camera_right = Vector3(cos(cam_y_rotation), 0, -sin(cam_y_rotation))

		# Movement relative to camera direction
		# input_dir.x is left/right (A/D), input_dir.y is forward/back (W/S)
		# Note: input_dir.y is negative for W (forward), positive for S (backward)
		var direction = (camera_right * input_dir.x - camera_forward * input_dir.y).normalized()

		print("Camera Y rotation: ", rad_to_deg(cam_y_rotation), " degrees")
		print("Input: ", input_dir, " -> Direction: ", direction)

		# Move the character
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed

		# Don't rotate the player body - let it stay at 0
		# The camera handles all rotation
		# (We can add body rotation back later only for visual purposes in third-person)
	else:
		# Decelerate when no input
		velocity.x = move_toward(velocity.x, 0, move_speed * delta * 5)
		velocity.z = move_toward(velocity.z, 0, move_speed * delta * 5)

	# Apply gravity (if needed)
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0

	# Move the character
	move_and_slide()

	# Send position updates to server
	_update_position_sending(delta)


func _update_position_sending(delta: float) -> void:
	_position_send_timer += delta

	# Check if enough time has passed AND player has moved significantly
	if _position_send_timer >= position_send_interval:
		var distance_moved = global_position.distance_to(_last_sent_position)

		if distance_moved >= _move_threshold:
			# Send position to server
			network.send_move(global_position)
			_last_sent_position = global_position
			_position_send_timer = 0.0
		elif velocity.length() < 0.1:
			# Send one final position update when stopped
			if _last_sent_position.distance_to(global_position) > 0.01:
				network.send_move(global_position)
				_last_sent_position = global_position

		_position_send_timer = 0.0
