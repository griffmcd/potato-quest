extends Node
## NetworkManager - Singleton that handles WebSocket connection to Phoenix server
##
## This autoload manages the WebSocket connection, sends/receives messages,
## and emits signals for game events.

# Server connection settings
const SERVER_URL = "ws://localhost:4000/socket/websocket"
const GAME_TOPIC = "game:lobby"

# WebSocket client
var _client: WebSocketPeer
var _connected: bool = false
var _message_ref: int = 0

# Player state
var username: String = ""
var player_id: String = ""

# Signals for game events
signal connected_to_server()
signal disconnected_from_server()
signal connection_error(error: String)
signal joined_lobby(player_id: String)
signal player_joined(player_id: String, username: String, position: Dictionary)
signal player_moved(player_id: String, position: Dictionary)
signal player_left(player_id: String, username: String)
signal lobby_state_received(players: Array)
signal chat_message_received(player_id: String, username: String, message: String)


func _ready() -> void:
	# WebSocketPeer is available in Godot 4.x
	_client = WebSocketPeer.new()


func _process(_delta: float) -> void:
	if _client.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_client.poll()

	var state = _client.get_ready_state()

	# Handle connection state changes
	if state == WebSocketPeer.STATE_OPEN:
		if not _connected:
			_connected = true
			print("WebSocket connected!")
			connected_to_server.emit()

		# Process incoming messages
		while _client.get_available_packet_count() > 0:
			var packet = _client.get_packet()
			var message_text = packet.get_string_from_utf8()
			_handle_message(message_text)

	elif state == WebSocketPeer.STATE_CLOSED:
		if _connected:
			_connected = false
			print("WebSocket disconnected")
			disconnected_from_server.emit()


## Connect to the Phoenix server
func connect_to_server() -> void:
	print("Connecting to ", SERVER_URL)
	var err = _client.connect_to_url(SERVER_URL)

	if err != OK:
		print("Failed to connect: ", err)
		connection_error.emit("Failed to initiate connection")


## Disconnect from the server
func disconnect_from_server() -> void:
	if _connected:
		_client.close()
		_connected = false


## Join the game lobby with a username
func join_lobby(p_username: String) -> void:
	username = p_username
	var message = {
		"topic": GAME_TOPIC,
		"event": "phx_join",
		"payload": {"username": username},
		"ref": str(_get_next_ref())
	}
	_send_message(message)


## Send player movement to server
func send_move(position: Vector3) -> void:
	if not _connected or player_id.is_empty():
		return

	var message = {
		"topic": GAME_TOPIC,
		"event": "player:move",
		"payload": {
			"x": position.x,
			"y": position.y,
			"z": position.z
		},
		"ref": str(_get_next_ref())
	}
	_send_message(message)


## Send chat message to server
func send_chat(chat_message: String) -> void:
	if not _connected or player_id.is_empty():
		return

	var message = {
		"topic": GAME_TOPIC,
		"event": "chat:message",
		"payload": {"message": chat_message},
		"ref": str(_get_next_ref())
	}
	_send_message(message)


## Request current lobby state (list of players)
func request_lobby_state() -> void:
	if not _connected or player_id.is_empty():
		print("WARNING: Cannot request lobby state - not connected or no player_id")
		return

	print("NetworkManager: Requesting lobby state")
	var message = {
		"topic": GAME_TOPIC,
		"event": "lobby:request_state",
		"payload": {},
		"ref": str(_get_next_ref())
	}
	_send_message(message)


## Send a message through the WebSocket
func _send_message(message: Dictionary) -> void:
	var json_string = JSON.stringify(message)
	_client.send_text(json_string)


## Handle incoming messages from the server
func _handle_message(message_text: String) -> void:
	var json = JSON.new()
	var parse_result = json.parse(message_text)

	if parse_result != OK:
		print("Failed to parse JSON: ", message_text)
		return

	var message = json.get_data()
	var event = message.get("event", "")
	var payload = message.get("payload", {})

	# Handle different message types
	match event:
		"phx_reply":
			_handle_phx_reply(payload)
		"player:joined":
			_handle_player_joined(payload)
		"player:moved":
			_handle_player_moved(payload)
		"player:left":
			_handle_player_left(payload)
		"lobby:state":
			_handle_lobby_state(payload)
		"chat:message":
			_handle_chat_message(payload)
		_:
			print("Unknown event: ", event)


func _handle_phx_reply(payload: Dictionary) -> void:
	if payload.get("status") == "ok":
		var response = payload.get("response", {})
		if response.has("player_id"):
			player_id = response["player_id"]
			print("Joined lobby! Player ID: ", player_id)
			joined_lobby.emit(player_id)


func _handle_player_joined(payload: Dictionary) -> void:
	var p_id = payload.get("player_id", "")
	var p_username = payload.get("username", "")
	var position = payload.get("position", {"x": 0, "y": 0, "z": 0})

	print("Player joined: ", p_username, " (", p_id, ")")
	player_joined.emit(p_id, p_username, position)


func _handle_player_moved(payload: Dictionary) -> void:
	var p_id = payload.get("player_id", "")
	var position = payload.get("position", {"x": 0, "y": 0, "z": 0})

	player_moved.emit(p_id, position)


func _handle_player_left(payload: Dictionary) -> void:
	var p_id = payload.get("player_id", "")
	var p_username = payload.get("username", "")

	print("Player left: ", p_username)
	player_left.emit(p_id, p_username)


func _handle_lobby_state(payload: Dictionary) -> void:
	var players = payload.get("players", [])
	print("Lobby state: ", players.size(), " players online")
	print("DEBUG NetworkManager: Players data = ", players)
	print("DEBUG NetworkManager: Emitting lobby_state_received signal")
	lobby_state_received.emit(players)


func _handle_chat_message(payload: Dictionary) -> void:
	var p_id = payload.get("player_id", "")
	var p_username = payload.get("username", "")
	var message = payload.get("message", "")

	print("[Chat] ", p_username, ": ", message)
	chat_message_received.emit(p_id, p_username, message)


func _get_next_ref() -> int:
	_message_ref += 1
	return _message_ref
