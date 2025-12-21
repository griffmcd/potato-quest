extends Control
## UsernameInput - Simple UI for entering username and connecting
##
## Displays before the game starts, allows player to enter
## their username and connect to the server.

# UI references (set in scene or get via $ syntax)
@onready var username_input: LineEdit = $VBoxContainer/UsernameLineEdit
@onready var connect_button: Button = $VBoxContainer/ConnectButton
@onready var status_label: Label = $VBoxContainer/StatusLabel

# Reference to NetworkManager
@onready var network = get_node("/root/NetworkManager")


func _ready() -> void:
	# Connect button signal
	connect_button.pressed.connect(_on_connect_button_pressed)

	# Connect network signals
	network.connected_to_server.connect(_on_connected_to_server)
	network.joined_lobby.connect(_on_joined_lobby)
	network.connection_error.connect(_on_connection_error)

	# Focus the username input
	username_input.grab_focus()

	# Allow Enter key to connect
	username_input.text_submitted.connect(_on_username_submitted)


func _on_connect_button_pressed() -> void:
	var username = username_input.text.strip_edges()

	if username.is_empty():
		status_label.text = "Please enter a username"
		status_label.modulate = Color.RED
		return

	# Disable input while connecting
	username_input.editable = false
	connect_button.disabled = true
	status_label.text = "Connecting..."
	status_label.modulate = Color.YELLOW

	# Connect to server
	network.connect_to_server()


func _on_username_submitted(text: String) -> void:
	_on_connect_button_pressed()


func _on_connected_to_server() -> void:
	status_label.text = "Connected! Joining lobby..."
	status_label.modulate = Color.YELLOW

	# Join the lobby
	var username = username_input.text.strip_edges()
	network.join_lobby(username)


func _on_joined_lobby(player_id: String) -> void:
	status_label.text = "Joined! Loading game..."
	status_label.modulate = Color.GREEN

	# Wait a moment then switch to game scene
	await get_tree().create_timer(0.5).timeout

	# Load the main game scene
	get_tree().change_scene_to_file("res://scenes/main_game.tscn")

func _on_connection_error(error: String) -> void:
	status_label.text = "Error: " + error
	status_label.modulate = Color.RED

	# Re-enable input
	username_input.editable = true
	connect_button.disabled = false
