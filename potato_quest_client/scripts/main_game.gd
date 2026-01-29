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

# Zone management
var current_zone: Node3D = null
var current_zone_id: String = ""

# Reference to NetworkManager
@onready var network = get_node("/root/NetworkManager")
@onready var ui_overlay = $UIOverlay


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
	network.player_attacked.connect(_on_player_attacked)
	network.enemy_positions_updated.connect(_on_enemy_positions_updated)
	network.enemy_attacked_player.connect(_on_enemy_attacked_player)
	network.player_damaged.connect(_on_player_damaged)
	network.enemies_spawned.connect(_on_enemies_spawned)

	# Request the current lobby state now that we're ready
	network.request_lobby_state()
	network.request_zone_state()

func load_zone(zone_id: String) -> void:
	print("MainGame: Loading zone ", zone_id)

	# Clear existing zone
	if current_zone:
		current_zone.queue_free()
		current_zone = null

	# Clear existing enemies
	for enemy in enemies.values():
		enemy.queue_free()
	enemies.clear()

	# Load new zone scene
	var zone_path = "res://scenes/zones/zone_%s.tscn" % zone_id
	var zone_scene = load(zone_path)

	if zone_scene:
		current_zone = zone_scene.instantiate()
		add_child(current_zone)
		current_zone_id = zone_id
		print("MainGame: Zone ", zone_id, " loaded successfully")
	else:
		push_error("Failed to load zone: " + zone_path)

## Request to transition to a different zone
## TODO: Future - trigger from portals, NPCs, etc.
func request_zone_transition(target_zone_id: String) -> void:
	# Future: Send "zone:transition" message to server
	# Server updates socket zone_id and sends new zone:state
	# Client auto-loads new zone via _on_zone_state_received
	pass

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


func _on_player_attacked(p_id: String) -> void:
	# Don't play for local player (they already see it)
	if p_id == network.player_id:
		return

	if remote_players.has(p_id):
		var remote_player = remote_players[p_id]
		remote_player.play_attack_animation()
	else:
		print("WARNING: Received attack from unknown player: ", p_id)


func _on_player_left(p_id: String, username: String) -> void:
	print("MainGame: Player left - ", username)

	if remote_players.has(p_id):
		var remote_player = remote_players[p_id]
		remote_player.queue_free()
		remote_players.erase(p_id)

		# Unregister from UI overlay
		if ui_overlay:
			ui_overlay.unregister_player(p_id)

func _on_zone_state_received(zone_data: Dictionary) -> void:
	# Server sends zone_id with state
	var zone_id = zone_data.get("zone_id", "town_square")
	var enemy_data = zone_data.get("enemies", [])

	# Load zone if not loaded or if zone changed
	if current_zone_id.is_empty() or current_zone_id != zone_id:
		load_zone(zone_id)

	print("MainGame: Spawning ", enemy_data.size(), " enemies")
	for data in enemy_data:
		print("DEBUG: Enemy data = ", data)
		if data.get("state") != "dead":
			_spawn_enemy(data)

func _spawn_enemy(data: Dictionary) -> void:
	if not enemy_scene:
		print("ERROR: enemy_scene not set!")
		return

	var enemy_id = data.get("id", "")
	if enemies.has(enemy_id):
		return

	# Use generic enemy scene for all enemy types for now
	# TODO: Implement type-specific scenes when properly structured
	var enemy_type = data.get("type", "pig_man")
	var enemy = enemy_scene.instantiate()
	if not enemy:
		print("ERROR: Failed to instantiate enemy scene!")
		return

	print("MainGame: Spawned generic enemy for type: ", enemy_type)

	enemy.enemy_id = enemy_id
	enemy.enemy_type = enemy_type
	enemy.current_health = data.get("health", 50)
	enemy.max_health = data.get("max_health", 50)

	var pos = data.get("position", {"x": 0, "y": 0, "z": 0})
	enemy.global_position = Vector3(pos.x, pos.y, pos.z)
	enemy.enemy_clicked.connect(_on_enemy_clicked)
	enemy.health_changed.connect(_on_enemy_health_changed)
	add_child(enemy)
	enemies[enemy_id] = enemy

	# Register with UI overlay for 2D HP bar
	if ui_overlay:
		ui_overlay.register_enemy(enemy_id, enemy, enemy.current_health, enemy.max_health)

	print("MainGame: Spawned enemy ", enemy_id, " at ", enemy.global_position)

func _on_enemy_clicked(enemy_id: String) -> void:
	print("MainGame: Attacking enemy ", enemy_id)
	network.send_attack(enemy_id)


func _on_enemy_health_changed(enemy_id: String, current_hp: int) -> void:
	if ui_overlay:
		ui_overlay.update_enemy_hp(enemy_id, current_hp) 

func _on_enemy_damaged(enemy_id: String, damage: int, health: int, attacker_id: String) -> void:
	print("Enemy ", enemy_id, " damaged for ", damage, " (HP: ", health, ")")
	if enemies.has(enemy_id):
		var enemy = enemies[enemy_id]
		enemy.update_health(health)
		_show_damage_number(enemy.global_position, damage)
	else:
		print("WARNING: Enemy ", enemy_id, " not found in enemies dictionary") 


func _on_enemy_died(enemy_id: String, loot: Dictionary) -> void:
	if enemies.has(enemy_id):
		enemies.erase(enemy_id)

	# Unregister from UI overlay
	if ui_overlay:
		ui_overlay.unregister_enemy(enemy_id)

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
	# Use 2D UI overlay instead of expensive Label3D
	if ui_overlay:
		ui_overlay.show_damage_number(position, damage)


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

	# Note: Removed Label3D for performance - color indicates item type
	# Gold = yellow, Equipment = blue

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

	# Register with UI overlay for 2D username
	if ui_overlay:
		ui_overlay.register_player(p_id, remote_player, username)

	print("MainGame: Spawned remote player ", username, " at ", pos)

func _on_enemy_positions_updated(zone_id: String, enemy_data: Array) -> void:
	if zone_id != current_zone_id:
		return  # Ignore updates for other zones

	for data in enemy_data:
		var enemy_id = data.get("id", "")
		if enemies.has(enemy_id):
			var enemy = enemies[enemy_id]
			var pos = data.get("position", {"x": 0, "y": 0, "z": 0})
			enemy.update_position(Vector3(pos.x, pos.y, pos.z))

			# Update animation if provided
			if data.has("animation"):
				enemy.update_animation(data.animation)

func _on_enemy_attacked_player(enemy_id: String, player_id: String, damage: int) -> void:
	print("MainGame: Enemy ", enemy_id, " attacked player ", player_id, " for ", damage, " damage")

	# If it's us, show damage feedback
	if player_id == network.player_id:
		# TODO: Reduce player health, show damage flash
		print("MainGame: YOU TOOK ", damage, " DAMAGE!")

func _on_player_damaged(enemy_id: String, player_id: String, damage: int, health: int, max_health: int, is_dead: bool) -> void:
	print("MainGame: Player ", player_id, " damaged by ", enemy_id, " for ", damage, " damage (HP: ", health, "/", max_health, ")")

	# If it's us, update our health and show damage
	if player_id == network.player_id and player:
		player.update_health(health, max_health)
		# Show damage number above player
		_show_damage_number(player.global_position + Vector3.UP * 2, damage)

		if is_dead:
			print("MainGame: LOCAL PLAYER DIED!")

func _on_enemies_spawned(zone_id: String, enemy_list: Array) -> void:
	print("MainGame: ", enemy_list.size(), " enemies respawned in zone ", zone_id)
	if zone_id != current_zone_id:
		return  # Ignore spawns for other zones

	for enemy_data in enemy_list:
		_spawn_enemy(enemy_data)
