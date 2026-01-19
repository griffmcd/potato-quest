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
signal player_rotated(player_id: String, rotation: Dictionary)
signal player_left(player_id: String, username: String)
signal lobby_state_received(players: Array)
signal chat_message_received(player_id: String, username: String, message: String)
signal zone_state_received(enemies: Array)
signal enemy_damaged(enemy_id: String, damage: int, health: int, attacker_id: String) 
signal enemy_died(enemy_id: String, loot: Dictionary)
signal item_picked_up(item_id: String, player_id: String)
signal inventory_updated(gold: int)
signal equipment_updated(equipment: Dictionary, stats: Dictionary)
signal inventory_changed(inventory: Array, gold: int)
signal error_received(message: String)
signal player_attacked(player_id: String)


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
func send_move(position: Vector3, rotation: Vector3) -> void:
	if not _connected or player_id.is_empty():
		return

	var message = {
		"topic": GAME_TOPIC,
		"event": "player:move",
		"payload": {
			"x": position.x,
			"y": position.y,
			"z": position.z,
			"pitch": rotation.x,
			"yaw": rotation.y,
			"rotation_y": rotation.z
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

func request_zone_state() -> void:
	if not _connected or player_id.is_empty():
		print("WARNING: Cannot request zone state - not connected or no player_id")
		return 
	print("NetworkManager: Requesting zone state")
	var message = {
		"topic": GAME_TOPIC,
		"event": "zone:request_state",
		"payload": {},
		"ref": str(_get_next_ref())
	}
	_send_message(message)

func send_attack(enemy_id: String) -> void:
	if not _connected or player_id.is_empty():
		return

	var message = {
		"topic": GAME_TOPIC,
		"event": "player:attack",
		"payload": {"enemy_id": enemy_id},
		"ref": str(_get_next_ref())
	}
	_send_message(message)

func send_attack_animation() -> void:
	if not _connected or player_id.is_empty():
		return

	var message = {
		"topic": GAME_TOPIC,
		"event": "player:attack_animation",
		"payload": {},
		"ref": str(_get_next_ref())
	}
	_send_message(message)

func send_pickup_item(item_id: String) -> void:
	if not _connected or player_id.is_empty():
		return
	var message = {
		"topic": GAME_TOPIC,
		"event": "player:pickup_item",
		"payload": {"item_id": item_id},
		"ref": str(_get_next_ref())
	}
	_send_message(message)

func send_equip_item(instance_id: String) -> void:
	if not _connected or player_id.is_empty():
		return

	var message = {
		"topic": GAME_TOPIC,
		"event": "player:equip_item",
		"payload": {"instance_id": instance_id},
		"ref": str(_get_next_ref())
	}
	_send_message(message)

func send_unequip_item(slot: String) -> void:
	if not _connected or player_id.is_empty():
		return

	var message = {
		"topic": GAME_TOPIC,
		"event": "player:unequip_item",
		"payload": {"slot": slot},
		"ref": str(_get_next_ref())
	}
	_send_message(message)

func send_drop_item(instance_id: String) -> void:
	if not _connected or player_id.is_empty():
		return

	var message = {
		"topic": GAME_TOPIC,
		"event": "player:drop_item",
		"payload": {"instance_id": instance_id},
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
		"player:attacked":
			_handle_player_attacked(payload)
		"lobby:state":
			_handle_lobby_state(payload)
		"chat:message":
			_handle_chat_message(payload)
		"zone:state":
			_handle_zone_state(payload)
		"enemy:damaged":
			_handle_enemy_damaged(payload)
		"enemy:died":
			_handle_enemy_died(payload)
		"item:picked_up":
			_handle_item_picked_up(payload)
		"inventory:updated":
			_handle_inventory_updated(payload)
		"equipment:updated":
			_handle_equipment_updated(payload)
		"error":
			_handle_error(payload)
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
	var rotation = payload.get("rotation", {"pitch": 0, "yaw": 0, "rotation_y": 0})

	player_moved.emit(p_id, position)
	player_rotated.emit(p_id, rotation)


func _handle_player_left(payload: Dictionary) -> void:
	var p_id = payload.get("player_id", "")
	var p_username = payload.get("username", "")

	print("Player left: ", p_username)
	player_left.emit(p_id, p_username)


func _handle_lobby_state(payload: Dictionary) -> void:
	var players = payload.get("players", [])
	print("Lobby state: ", players.size(), " players online")
	lobby_state_received.emit(players)


func _handle_chat_message(payload: Dictionary) -> void:
	var p_id = payload.get("player_id", "")
	var p_username = payload.get("username", "")
	var message = payload.get("message", "")

	print("[Chat] ", p_username, ": ", message)
	chat_message_received.emit(p_id, p_username, message)

func _handle_zone_state(payload: Dictionary) -> void:
	var enemies = payload.get("enemies", [])
	print("Zone state: ", enemies.size(), " enemies")
	zone_state_received.emit(enemies)

func _handle_enemy_damaged(payload: Dictionary) -> void:
	var enemy_id = payload.get("enemy_id", "")
	var damage = payload.get("damage", 0)
	var health = payload.get("health", 0)
	var attacker_id = payload.get("attacker_id", "")

	enemy_damaged.emit(enemy_id, damage, health, attacker_id)

func _handle_enemy_died(payload: Dictionary) -> void:
	var enemy_id = payload.get("enemy_id", "")
	var spawned_items = payload.get("spawned_items", [])

	print("Enemy died: ", enemy_id, " with ", spawned_items.size(), " items")

	# Emit with spawned_items wrapped in a dictionary for compatibility
	var loot_payload = {"spawned_items": spawned_items}
	enemy_died.emit(enemy_id, loot_payload)

func _handle_item_picked_up(payload: Dictionary) -> void:
	var item_id = payload.get("item_id", "")
	var this_player_id = payload.get("player_id", "")

	item_picked_up.emit(item_id, this_player_id) 

func _handle_inventory_updated(payload: Dictionary) -> void:
	var gold = payload.get("gold", -1)
	var inventory = payload.get("inventory", [])

	print("Inventory updated - Gold: ", gold)

	if gold >= 0:
		inventory_updated.emit(gold)

	if not inventory.is_empty():
		inventory_changed.emit(inventory, gold)

func _handle_equipment_updated(payload: Dictionary) -> void:
	var equipment = payload.get("equipment", {})
	var stats = payload.get("stats", {})
	var inventory = payload.get("inventory", [])

	print("Equipment updated - Stats: ", stats.get("damage", 0), " damage")
	equipment_updated.emit(equipment, stats)

	# Also update inventory if provided
	if not inventory.is_empty():
		var gold = -1  # Signal no gold change
		inventory_changed.emit(inventory, gold)

func _handle_error(payload: Dictionary) -> void:
	var reason = payload.get("reason", "Unknown error")
	var message = payload.get("message", reason)
	print("ERROR from server: ", message)
	push_error("Server error: " + message)
	error_received.emit(message)

func _handle_player_attacked(payload: Dictionary) -> void:
	var p_id = payload.get("player_id", "")
	if p_id.is_empty():
		print("WARNING: Received player:attacked with no player_id")
		return
	player_attacked.emit(p_id)

func _get_next_ref() -> int:
	_message_ref += 1
	return _message_ref
