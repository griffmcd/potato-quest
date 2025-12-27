extends Node3D
## MainGame - Main game scene controller
##
## Manages spawning/despawning remote players and handles network events.

# Preload the remote player scene (you'll need to create this scene)
# We'll use a NodePath for now, which you'll set in the Inspector
@export var remote_player_scene: PackedScene
@export var enemy_scene: PackedScene 

# References to important nodes (set these in the Inspector)
@export var player: CharacterBody3D

# Track remote players
var remote_players: Dictionary = {}  # {player_id: RemotePlayer node}
var enemies: Dictionary = {} # {enemy_id: Enemy node}
var loot_items: Dictionary = {} # {item_id: MeshInstance3D node}

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
	network.zone_state_received.connect(_on_zone_state_received)
	network.enemy_damaged.connect(_on_enemy_damaged)
	network.enemy_died.connect(_on_enemy_died)
	network.item_picked_up.connect(_on_item_picked_up)
	network.inventory_updated.connect(_on_inventory_updated)
	network.equipment_updated.connect(_on_equipment_updated)
	network.inventory_changed.connect(_on_inventory_changed)

	# Request the current lobby state now that we're ready
	network.request_lobby_state()
	network.request_zone_state()


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


func _on_player_joined(p_id: String, username: String, player_position: Dictionary) -> void:
	print("MainGame: Player joined - ", username, " (", p_id, ")")

	# Don't spawn ourselves
	if p_id == network.player_id:
		return

	# Don't spawn if already exists
	if remote_players.has(p_id):
		return

	_spawn_remote_player(p_id, username, player_position)


func _on_player_moved(p_id: String, player_position: Dictionary) -> void:
	if p_id == network.player_id:
		return

	# Update remote player position
	if remote_players.has(p_id):
		var remote_player = remote_players[p_id]
		var new_pos = Vector3(player_position.x, player_position.y, player_position.z)
		remote_player.update_position(new_pos)


func _on_player_rotated(p_id: String, rotation_data: Dictionary) -> void:
	if p_id == network.player_id:
		return

	# Update remote player rotation
	if remote_players.has(p_id):
		var remote_player = remote_players[p_id]
		remote_player.update_rotation(rotation_data)


func _on_player_left(p_id: String, username: String) -> void:
	print("MainGame: Player left - ", username)

	if remote_players.has(p_id):
		var remote_player = remote_players[p_id]
		remote_player.queue_free()
		remote_players.erase(p_id)

func _on_zone_state_received(enemy_data: Array) -> void:
	print("MainGame: Spawning ", enemy_data.size(), " enemies")
	for data in enemy_data:
		print("DEBUG: Enemy data = ", data)
		if data.get("state") == "alive":
			_spawn_enemy(data)

func _spawn_enemy(data: Dictionary) -> void:
	if not enemy_scene:
		print("ERROR: enemy_scene not set!")
		return 

	var enemy_id = data.get("id", "")
	if enemies.has(enemy_id):
		return 

	var enemy = enemy_scene.instantiate() 
	enemy.enemy_id = enemy_id 
	enemy.enemy_type = data.get("type", "pig_man")
	enemy.current_health = data.get("health", 50)
	enemy.max_health = data.get("max_health", 50)

	var pos = data.get("position", {"x": 0, "y": 0, "z": 0})
	enemy.global_position = Vector3(pos.x, pos.y, pos.z)
	enemy.enemy_clicked.connect(_on_enemy_clicked)
	add_child(enemy) 
	enemies[enemy_id] = enemy 
	print("MainGame: Spawned enemy ", enemy_id, " at ", enemy.global_position)

func _on_enemy_clicked(enemy_id: String) -> void:
	print("MainGame: Attacking enemy ", enemy_id) 
	network.send_attack(enemy_id) 

func _on_enemy_damaged(enemy_id: String, damage: int, health: int, attacker_id: String) -> void: 
	if enemies.has(enemy_id):
		var enemy = enemies[enemy_id]
		enemy.update_health(health)
		_show_damage_number(enemy.global_position, damage) 


func _on_enemy_died(enemy_id: String, loot: Dictionary) -> void:
	if enemies.has(enemy_id):
		enemies.erase(enemy_id)

	# loot payload now has "spawned_items" array
	if loot.has("spawned_items"):
		for item in loot.get("spawned_items", []):
			_spawn_loot_item(item)
	# Fallback for old single-item format (backward compatibility)
	elif loot.has("id"):
		_spawn_loot_item(loot) 


func _on_item_picked_up(item_id: String, player_id: String) -> void: 
	if loot_items.has(item_id):
		loot_items[item_id].queue_free() 
		loot_items.erase(item_id)

func _on_inventory_updated(gold: int) -> void:
	print("MainGame: Gold = ", gold)

func _on_equipment_updated(equipment: Dictionary, stats: Dictionary) -> void:
	print("MainGame: Equipment updated - Damage: ", stats.get("damage", 0))

func _on_inventory_changed(inventory: Array, gold: int) -> void:
	print("MainGame: Inventory changed - ", inventory.size(), " items, Gold: ", gold)

func _show_damage_number(position: Vector3, damage: int) -> void:
	var label = Label3D.new() 
	label.text = "-%d" % damage 
	label.font_size = 32 
	label.modulate = Color(1, 0.3, 0.3)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED 
	label.global_position = position + Vector3(0, 2, 0)

	add_child(label) 
	var tween = create_tween() 
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", position + Vector3(0, 3, 0), 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(label.queue_free)


func _spawn_loot_item(loot: Dictionary) -> void:
	var item_id = loot.get("id", "")
	var item_type = loot.get("item_type", "")
	var pos = loot.get("position", {"x": 0, "y": 0, "z": 0})
	var pos_vector = Vector3(pos.x, pos.y, pos.z)
	var value = loot.get("value", 0)

	# Determine color and label based on item type
	var color = Color(1, 0.8, 0)  # Gold for coins
	var label_text = "Gold +%d" % value

	if item_type != "gold_coin":
		# It's an equipment item
		color = Color(0.5, 0.5, 1.0)  # Blue for equipment

		# Map template_id to display name
		var item_names = {
			"bronze_sword": "Bronze Sword",
			"wooden_shield": "Wooden Shield",
			"leather_tunic": "Leather Tunic",
			"iron_band": "Iron Band"
		}
		label_text = item_names.get(item_type, item_type)

	# Create visual representation (sphere)
	var mesh_instance = MeshInstance3D.new()
	var mesh = SphereMesh.new()
	mesh.radius = 0.3
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.global_position = pos_vector

	# Click detection area
	var area = Area3D.new()
	area.set_meta("item_id", item_id)
	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.5
	collision.shape = shape
	area.add_child(collision)
	mesh_instance.add_child(area)

	area.input_event.connect(func(_camera, event, _pos, _normal, _shape_idx):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			network.send_pickup_item(item_id)
	)

	# Label showing item name/value
	var label = Label3D.new()
	label.text = label_text
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 1, 0)
	mesh_instance.add_child(label)

	add_child(mesh_instance)
	loot_items[item_id] = mesh_instance 


func _spawn_remote_player(p_id: String, username: String, player_position: Dictionary) -> void:
	if not remote_player_scene:
		print("ERROR: remote_player_scene not set in MainGame!")
		return
	var remote_player = remote_player_scene.instantiate()
	remote_player.player_id = p_id
	remote_player.player_username = username
	var pos = Vector3(player_position.x, player_position.y, player_position.z)
	remote_player.global_position = pos
	remote_player.target_position = pos
	add_child(remote_player)
	remote_players[p_id] = remote_player
	print("MainGame: Spawned remote player ", username, " at ", pos)
