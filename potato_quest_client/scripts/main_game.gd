extends Node3D
## MainGame - Main game scene controller
##
## Manages spawning/despawning remote players and handles network events.

# Preload the remote player scene (you'll need to create this scene)
# We'll use a NodePath for now, which you'll set in the Inspector
@export var remote_player_scene: PackedScene

# References to important nodes (set these in the Inspector)
@export var player: CharacterBody3D

# Track remote players
var remote_players: Dictionary = {}  # {player_id: RemotePlayer node}

# Reference to NetworkManager
@onready var network = get_node("/root/NetworkManager")


func _ready() -> void:
	# Position the local player at spawn point
	call_deferred("_connect_signals")

func _connect_signals() -> void:
	# Connect to network signals
	network.player_joined.connect(_on_player_joined)
	network.player_moved.connect(_on_player_moved)
	network.player_rotated.connect(_on_player_rotated)
	network.player_left.connect(_on_player_left)
	network.lobby_state_received.connect(_on_lobby_state_received)
	network.joined_lobby.connect(_on_joined_lobby)

	# Request the current lobby state now that we're ready
	network.request_lobby_state()



## Called when we successfully join the lobby
func _on_joined_lobby(player_id: String) -> void:
	print("MainGame: Joined lobby as ", player_id)


## Called when lobby state is received (list of existing players)
func _on_lobby_state_received(players: Array) -> void:
	print("MainGame: Received lobby state with ", players.size(), " players")

	# Spawn existing players
	for player_data in players:
		var p_id = player_data.get("player_id", "")
		var p_username = player_data.get("username", "")
		var player_position = player_data.get("position", {"x": 0, "y": 0, "z": 0})

		if p_id == network.player_id:
			if player:
				player.global_position = Vector3(player_position.x, player_position.y, player_position.z)
				print("MainGame: Set local player position to ", player.global_position)
		else:
			_spawn_remote_player(p_id, p_username, player_position)


## Called when a new player joins
func _on_player_joined(p_id: String, username: String, player_position: Dictionary) -> void:
	print("MainGame: Player joined - ", username, " (", p_id, ")")

	# Don't spawn ourselves
	if p_id == network.player_id:
		return

	# Don't spawn if already exists
	if remote_players.has(p_id):
		return

	_spawn_remote_player(p_id, username, player_position)


## Called when a player moves
func _on_player_moved(p_id: String, player_position: Dictionary) -> void:
	# Don't update our own position (we control that locally)
	if p_id == network.player_id:
		return

	# Update remote player position
	if remote_players.has(p_id):
		var remote_player = remote_players[p_id]
		var new_pos = Vector3(player_position.x, player_position.y, player_position.z)
		remote_player.update_position(new_pos)


## Called when a player rotates
func _on_player_rotated(p_id: String, rotation_data: Dictionary) -> void:
	# Don't update our own player
	if p_id == network.player_id:
		return

	# Update remote player rotation
	if remote_players.has(p_id):
		var remote_player = remote_players[p_id]
		remote_player.update_rotation(rotation_data)


## Called when a player leaves
func _on_player_left(p_id: String, username: String) -> void:
	print("MainGame: Player left - ", username)

	if remote_players.has(p_id):
		var remote_player = remote_players[p_id]
		remote_player.queue_free()
		remote_players.erase(p_id)


## Spawn a remote player in the world
func _spawn_remote_player(p_id: String, username: String, player_position: Dictionary) -> void:
	if not remote_player_scene:
		print("ERROR: remote_player_scene not set in MainGame!")
		return

	# Instantiate the remote player
	var remote_player = remote_player_scene.instantiate()

	# Set player info
	remote_player.player_id = p_id
	remote_player.player_username = username

	# Set position
	var pos = Vector3(player_position.x, player_position.y, player_position.z)
	remote_player.global_position = pos
	remote_player.target_position = pos

	# Add to scene
	add_child(remote_player)

	# Track it
	remote_players[p_id] = remote_player

	print("MainGame: Spawned remote player ", username, " at ", pos)
