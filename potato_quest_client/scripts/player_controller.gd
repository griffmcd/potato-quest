extends CharacterBody3D
## PlayerController - Controls the local player character
##
## Handles WASD movement, sends position updates to server,
## and manages player visuals.

@export var move_speed: float = 5.0
@export var rotation_speed: float = 10.0
@export var position_send_interval: float = 0.1  # Send position every 100ms
@export var model_forward_offset: float = 0.0  ## Rotation offset to align model's forward with -Z (in radians)

# Movement tracking
var _last_sent_position: Vector3 = Vector3.ZERO
var _position_send_timer: float = 0.0
var _move_threshold: float = 0.5  # Minimum movement to trigger update

# Rotation tracking
var _last_sent_rotation: Vector3 = Vector3.ZERO
var _rotation_threshold: float = 0.05 # ~3 degrees in radians

# Attack tracking
var _is_attacking: bool = false 

# Reference to NetworkManager (autoload)
@onready var network = get_node("/root/NetworkManager")
@onready var animation_player: AnimationPlayer = $CharacterVisual/Body/AnimationPlayer

func _ready() -> void:
	# Set initial position
	_last_sent_position = global_position

	# Connect to animation finished signal
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and \
		event.button_index == MOUSE_BUTTON_LEFT:
			var camera_rig = $CameraRig
			if camera_rig.mouse_captured:
				# Always play attack animation
				_play_attack_animation()
				# Check if we hit anything
				_perform_raycast() 




func _physics_process(delta: float) -> void:
	# Get input for movement
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

	# Get camera rig reference for camera-relative movement
	var camera_rig = $CameraRig
	var body = $CharacterVisual/Body

	# Body always faces camera direction (both first and third person)
	# Apply model-specific forward offset to compensate for different mesh orientations
	body.rotation.y = camera_rig.rotation.y + model_forward_offset

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

		# Move the character
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		# Decelerate when no input
		velocity.x = move_toward(velocity.x, 0, move_speed * delta * 5)
		velocity.z = move_toward(velocity.z, 0, move_speed * delta * 5)

	# Apply gravity (if needed)
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0

	# Move the character, change animation, and send updated position
	move_and_slide()
	_update_animation_state()
	_update_position_sending(delta)

	# track rotation changes
	if _rotation_changed():
		var current_pitch = _get_camera_pitch()
		var current_yaw = camera_rig.rotation.y
		var current_body_rotation = $CharacterVisual/Body.rotation.y

		_last_sent_rotation = Vector3(current_pitch, current_yaw, current_body_rotation)
		# Send rotation update to server immediately
		network.send_move(global_position, _get_current_rotation())




func _update_position_sending(delta: float) -> void:
	_position_send_timer += delta

	# Check if enough time has passed AND player has moved significantly
	if _position_send_timer >= position_send_interval:
		var distance_moved = global_position.distance_to(_last_sent_position)

		if distance_moved >= _move_threshold:
			# Send position to server
			network.send_move(global_position, _get_current_rotation())
			_last_sent_position = global_position
			_position_send_timer = 0.0
		elif velocity.length() < 0.1:
			# Send one final position update when stopped
			if _last_sent_position.distance_to(global_position) > 0.01:
				network.send_move(global_position, _get_current_rotation())
				_last_sent_position = global_position

		_position_send_timer = 0.0

func _rotation_changed() -> bool:
	var camera_rig = $CameraRig
	var current_pitch = _get_camera_pitch()
	var current_yaw = camera_rig.rotation.y 
	var current_body_rotation = $CharacterVisual/Body.rotation.y 

	var current_rotation = Vector3(current_pitch, current_yaw, current_body_rotation)
	# did any component change beyond the threshold 
	if abs(current_rotation.x - _last_sent_rotation.x) >= _rotation_threshold:
		return true 
	if abs(current_rotation.y - _last_sent_rotation.y) >= _rotation_threshold:
		return true 
	if abs(current_rotation.z - _last_sent_rotation.z) >= _rotation_threshold:
		return true 
	return false 

func _get_camera_pitch() -> float:
	var camera_rig = $CameraRig 
	if camera_rig.is_first_person:
		return camera_rig.first_person_camera.rotation.x 
	else:
		return camera_rig.third_person_camera.rotation.x

func _get_current_rotation() -> Vector3:
	var camera_rig = $CameraRig 
	return Vector3(_get_camera_pitch(), camera_rig.rotation.y, $CharacterVisual/Body.rotation.y)

func _perform_raycast() -> void: 
	var camera_rig = $CameraRig 
	var camera = camera_rig.first_person_camera if camera_rig.is_first_person \
			else camera_rig.third_person_camera
	var from = camera.global_position
	var to = from + (-camera.global_transform.basis.z * 100.0) # 100 units forward
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to) 
	query.collide_with_areas = true # enable Area3D detection 
	query.exclude = [self]

	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		if collider.name == "Hurtbox" and "enemy_id" in collider.get_parent():
			var enemy = collider.get_parent()
			print("Player attacked enemy: ", enemy.enemy_id)
			# Deal damage to enemy
			get_node("/root/MainGame")._on_enemy_clicked(enemy.enemy_id)
		elif collider is Area3D and collider.has_meta("item_id"):
			var item_id = collider.get_meta("item_id")
			print("Player picking up item: ", item_id)
			get_node("/root/NetworkManager").send_pickup_item(item_id)

func _update_animation_state() -> void:
	if not animation_player:
		return

	# Don't interrupt attack animation
	if _is_attacking:
		return

	var is_moving = velocity.length() > 0.1
	var target_animation = "Walk" if is_moving else "Idle"

	if animation_player.current_animation != target_animation:
		animation_player.play(target_animation)

func _play_attack_animation() -> void:
	if not animation_player:
		return

	_is_attacking = true
	animation_player.play("Sword_Attack")

func _on_animation_finished(anim_name: String) -> void:
	# When attack animation finishes, return to normal state
	if anim_name == "Sword_Attack":
		_is_attacking = false
		_update_animation_state()
