extends CharacterBody3D
## PlayerController - Controls the local player character
##
## Handles WASD movement, sends position updates to server,
## and manages player visuals.

@export var move_speed: float = 5.0
@export var rotation_speed: float = 10.0
@export var model_forward_offset: float = 0.0  ## Rotation offset to align model's forward with -Z (in radians)

var position_send_interval: float = 0.1  # Loaded from SettingsManager
var rotation_send_interval: float = 0.1  # Loaded from SettingsManager

# Movement tracking
var _last_sent_position: Vector3 = Vector3.ZERO
var _position_send_timer: float = 0.0
var _move_threshold: float = 0.5  # Loaded from SettingsManager

# Rotation tracking
var _last_sent_rotation: Vector3 = Vector3.ZERO
var _rotation_send_timer: float = 0.0
var _rotation_threshold: float = 0.1  # Loaded from SettingsManager

# Animation tracking
var animation_update_interval: float = 0.05  # Loaded from SettingsManager
var animation_update_timer: float = 0.0

# Attack tracking
var _is_attacking: bool = false

# Health tracking
var current_health: int = 100
var max_health: int = 100
signal health_changed(current_hp: int, max_hp: int)

# Reference to NetworkManager (autoload)
@onready var network = get_node("/root/NetworkManager")
@onready var settings = get_node("/root/SettingsManager")
@onready var animation_player: AnimationPlayer = $CharacterVisual/Body/AnimationPlayer

func _ready() -> void:
	# Load settings
	position_send_interval = settings.get_position_send_interval()
	rotation_send_interval = settings.get_rotation_send_interval()
	animation_update_interval = settings.get_player_animation_interval()
	_move_threshold = settings.get_move_threshold()
	_rotation_threshold = settings.get_rotation_threshold()

	# Connect to settings changes
	settings.network_interval_changed.connect(_on_network_changed)
	settings.animation_interval_changed.connect(_on_animation_changed)
	settings.gameplay_changed.connect(_on_gameplay_changed)

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

	animation_update_timer += delta
	if animation_update_timer >= animation_update_interval:
		_update_animation_state()
		animation_update_timer = 0.0

	_update_position_sending(delta)
	_update_rotation_sending(delta)




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


func _update_rotation_sending(delta: float) -> void:
	_rotation_send_timer += delta

	# Only send rotation updates at throttled interval
	if _rotation_send_timer >= rotation_send_interval:
		if _rotation_changed():
			var current_pitch = _get_camera_pitch()
			var current_yaw = $CameraRig.rotation.y
			var current_body_rotation = $CharacterVisual/Body.rotation.y

			_last_sent_rotation = Vector3(current_pitch, current_yaw, current_body_rotation)
			# Send rotation update to server
			network.send_move(global_position, _get_current_rotation())

		_rotation_send_timer = 0.0

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

	# Broadcast attack animation to other players
	network.send_attack_animation()

	animation_player.play("Sword_Attack")

func _on_animation_finished(anim_name: String) -> void:
	# When attack animatwion finishes, return to normal state
	if anim_name == "Sword_Attack":
		_is_attacking = false
		_update_animation_state()


## Handle network interval changes from SettingsManager
func _on_network_changed(pos_interval: float, rot_interval: float) -> void:
	position_send_interval = pos_interval
	rotation_send_interval = rot_interval


## Handle animation interval changes from SettingsManager
func _on_animation_changed(player_interval: float, _remote_player_interval: float) -> void:
	animation_update_interval = player_interval


## Handle gameplay settings changes from SettingsManager
func _on_gameplay_changed(_interpolation_speed: float, move_threshold: float, rotation_threshold: float) -> void:
	_move_threshold = move_threshold
	_rotation_threshold = rotation_threshold

## Update player health when damaged
func update_health(new_health: int, new_max: int) -> void:
	current_health = new_health
	max_health = new_max
	health_changed.emit(current_health, max_health)
	if current_health <= 0:
		_on_player_death()

## Handle player death
func _on_player_death() -> void:
	print("PLAYER DIED!")
	# TODO: Show death screen, respawn logic, etc.
