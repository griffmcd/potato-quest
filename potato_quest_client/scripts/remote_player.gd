extends CharacterBody3D
## RemotePlayer - Represents another player in the game
##
## Displays and interpolates movement for remote players.
## Spawned dynamically by MainGame when players join.

var interpolation_speed: float = 10.0  # Loaded from SettingsManager
var camera_culling_distance: float = 50.0  # Loaded from SettingsManager

var player_id: String = ""
var player_username: String = ""
var target_position: Vector3 = Vector3.ZERO
var target_body_rotation: float = 0.0  # Body Y rotation (which way character faces)

# Animation tracking
var animation_update_interval: float = 0.05  # Loaded from SettingsManager
var animation_update_timer: float = 0.0
var _is_attacking: bool = false

@onready var animation_player: AnimationPlayer = $CharacterVisual/Body/AnimationPlayer
@onready var settings = get_node("/root/SettingsManager")


func _ready() -> void:
	# Load settings
	interpolation_speed = settings.get_interpolation_speed()
	animation_update_interval = settings.get_remote_animation_interval()
	camera_culling_distance = settings.get_camera_culling_distance()

	# Connect to settings changes
	settings.gameplay_changed.connect(_on_gameplay_changed)
	settings.animation_interval_changed.connect(_on_animation_changed)
	settings.rendering_changed.connect(_on_rendering_changed)

	# Set initial target
	target_position = global_position
	# Username will be displayed via UI overlay (registered by main_game.gd)

	# Connect animation signals
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_finished)


func _physics_process(delta: float) -> void:
	# Cache distance for multiple checks
	var distance = global_position.distance_to(target_position)

	# Only interpolate if character is far enough from target (deadzone)
	if distance > 0.05:
		global_position = global_position.lerp(target_position, interpolation_speed * delta)

	# Smoothly interpolate body rotation
	# Apply model-specific forward offset to compensate for different mesh orientations
	var body = $CharacterVisual/Body
	body.rotation.y = lerp_angle(body.rotation.y, target_body_rotation, interpolation_speed * delta)

	# Skip animation updates for distant players (camera culling)
	var camera = get_viewport().get_camera_3d()
	if camera:
		var dist_to_camera = global_position.distance_to(camera.global_position)
		if dist_to_camera > camera_culling_distance:
			return

	animation_update_timer += delta
	if animation_update_timer >= animation_update_interval:
		_update_animation_state(distance)
		animation_update_timer = 0.0


## Update the target position for this remote player
func update_position(new_position: Vector3) -> void:
	target_position = new_position


## Update the target rotation for this remote player
func update_rotation(rotation_data: Dictionary) -> void:
	# rotation_data contains: pitch, yaw, rotation_y
	# For now, we only care about rotation_y (body rotation)
	target_body_rotation = rotation_data.get("rotation_y", 0.0)


## Set the player's username
func set_username(new_username: String) -> void:
	player_username = new_username
	# Username displayed via UI overlay

func _update_animation_state(distance_to_target: float) -> void:
	if not animation_player:
		return

	# Don't interrupt attack animation
	if _is_attacking:
		return

	# Increased threshold to reduce animation switching (more efficient)
	var is_moving = distance_to_target > 0.2
	if is_moving:
		if animation_player.current_animation != "Walk":
			animation_player.play("Walk")
	else:
		if animation_player.current_animation != "Idle":
			animation_player.play("Idle")


func play_attack_animation() -> void:
	if not animation_player:
		return

	if _is_attacking:
		return  # Ignore duplicate requests

	_is_attacking = true
	animation_player.play("Sword_Attack")


func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "Sword_Attack":
		_is_attacking = false
		# Return to Walk/Idle immediately
		var distance = global_position.distance_to(target_position)
		_update_animation_state(distance)


## Handle gameplay settings changes
func _on_gameplay_changed(new_interpolation_speed: float, _move_threshold: float, _rotation_threshold: float) -> void:
	interpolation_speed = new_interpolation_speed


## Handle animation settings changes
func _on_animation_changed(_player_interval: float, remote_player_interval: float) -> void:
	animation_update_interval = remote_player_interval


## Handle rendering settings changes
func _on_rendering_changed(_max_fps: int, _vsync_mode: int) -> void:
	camera_culling_distance = settings.get_camera_culling_distance()
