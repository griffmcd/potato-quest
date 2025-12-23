extends Node3D

## CameraController - Handles camera rotation, perspective switching, and
##  mouse capture. Manages first-person and third-person camera perspectives.
##  Press V to toggle perspectives, ESC to release mouse, click to capture mouse.

var camera_rig 
var first_person_camera: Camera3D 
var third_person_camera: Camera3D 
var player_body: Node3D 
var player: CharacterBody3D

@export var mouse_sensitivity: float = 0.003
@export var vertical_look_limit: float = 89.0  # degrees

var is_first_person: bool = true
var mouse_captured: bool = false
var chat_mode: bool = false  # True when chat is active

var camera_pitch: float = 0.0 # vertical rotation
var camera_yaw: float = 0.0 # horizontal rotation 

func _ready() -> void:
	camera_rig = self 
	player = get_parent()
	first_person_camera = get_node("FirstPersonCamera")
	third_person_camera = get_node("ThirdPersonArm/ThirdPersonCamera")
	player_body = player.get_node("Body")
	toggle_mouse_capture(true) 


func _input(event: InputEvent) -> void:
	# Don't process camera input when chat is active
	if chat_mode:
		return

	if event.is_action_pressed("ui_cancel"):
		toggle_mouse_capture(false)

	if event is InputEventMouseButton and event.pressed and not mouse_captured:
		toggle_mouse_capture(true)

	if event.is_action_pressed("toggle_camera"):
		toggle_perspective()

	if event is InputEventMouseMotion and mouse_captured:
		handle_mouse_look(event.relative)

func handle_mouse_look(mouse_delta: Vector2) -> void:
	camera_yaw -= mouse_delta.x * mouse_sensitivity
	camera_pitch -= mouse_delta.y * mouse_sensitivity
	camera_pitch = clamp(camera_pitch, 
			deg_to_rad(-vertical_look_limit),
			deg_to_rad(vertical_look_limit))

	camera_rig.rotation.y = camera_yaw 

	if is_first_person:
		first_person_camera.rotation.x = camera_pitch
	else:
		third_person_camera.rotation.x = camera_pitch
	
func toggle_perspective() -> void:
	is_first_person = !is_first_person 
	first_person_camera.current = is_first_person 
	third_person_camera.current = !is_first_person 
	# toggle body visibility (hidden in 1st person)
	player_body.visible = !is_first_person

	print("Camera: Switched to ", "first-person" if is_first_person else "third-person")
	
func toggle_mouse_capture(captured: bool) -> void:
	mouse_captured = captured
	if captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Called by ChatUI to enable chat mode (disables camera control, releases mouse)
func enable_chat_mode() -> void:
	chat_mode = true
	toggle_mouse_capture(false)

## Called by ChatUI to disable chat mode (enables camera control, captures mouse)
func disable_chat_mode() -> void:
	chat_mode = false
	toggle_mouse_capture(true)
