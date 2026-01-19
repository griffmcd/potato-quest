extends CanvasLayer
## UIOverlay - Manages all 2D UI elements rendered over the 3D world
##
## Handles damage numbers, HP bars, player usernames, and loot labels
## Much more performant than Label3D nodes

# Node references
@onready var damage_container: Control = $DamageContainer
@onready var hp_bars_container: Control = $HPBarsContainer
@onready var usernames_container: Control = $UsernamesContainer

# Track active UI elements
var damage_labels: Array[Label] = []
var hp_bars: Dictionary = {}  # {enemy_id: {bar: ProgressBar, label: Label}}
var username_labels: Dictionary = {}  # {player_id: Label}

# Reference to camera for 3D -> 2D projection
var camera: Camera3D = null

# UI update throttling
var ui_update_interval: float = 0.05  # Loaded from SettingsManager
var ui_update_timer: float = 0.0

# Reference to SettingsManager
@onready var settings = get_node("/root/SettingsManager")


func _ready() -> void:
	# Load settings
	ui_update_interval = settings.get_ui_update_interval()
	settings.ui_interval_changed.connect(_on_ui_interval_changed)

	# Find camera (deferred to ensure scene is ready)
	call_deferred("_find_camera")


func _find_camera() -> void:
	camera = get_viewport().get_camera_3d()
	if not camera:
		push_warning("UIOverlay: No Camera3D found in viewport")


func _process(delta: float) -> void:
	# Refresh camera reference every frame to handle perspective switching
	camera = get_viewport().get_camera_3d()
	if not camera:
		return

	ui_update_timer += delta
	if ui_update_timer >= ui_update_interval:
		_update_hp_bars()
		_update_usernames()
		ui_update_timer = 0.0


## Show a floating damage number at a 3D position
func show_damage_number(world_position: Vector3, damage: int) -> void:
	var label = Label.new()
	label.text = "-%d" % damage
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	label.z_index = 100

	damage_container.add_child(label)
	damage_labels.append(label)

	# Position initially
	if camera:
		var screen_pos = camera.unproject_position(world_position + Vector3(0, 2, 0))
		label.position = screen_pos - label.size / 2

	# Animate upward and fade out
	var tween = create_tween()
	tween.set_parallel(true)

	# Move upward (we'll update position in _process, this just tracks offset)
	var start_offset = label.position.y
	tween.tween_method(func(offset: float):
		if camera and is_instance_valid(label):
			var current_3d_pos = world_position + Vector3(0, 2 + (offset - start_offset) * 0.01, 0)
			var screen_pos = camera.unproject_position(current_3d_pos)
			label.position = screen_pos - label.size / 2
	, start_offset, start_offset - 50, 1.0)

	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(func():
		if is_instance_valid(label):
			label.queue_free()
			damage_labels.erase(label)
	)


## Register an enemy for HP bar display
func register_enemy(enemy_id: String, enemy_node: Node3D, current_hp: int, max_hp: int) -> void:
	if hp_bars.has(enemy_id):
		return

	# Create HP bar (simple colored rectangle approach for performance)
	var bar_bg = ColorRect.new()
	bar_bg.custom_minimum_size = Vector2(60, 8)
	bar_bg.color = Color(0.2, 0.2, 0.2, 0.8)

	var bar_fill = ColorRect.new()
	bar_fill.custom_minimum_size = Vector2(60, 8)
	bar_fill.color = Color(0.8, 0.2, 0.2)
	bar_fill.size = Vector2(60, 8)

	bar_bg.add_child(bar_fill)
	hp_bars_container.add_child(bar_bg)

	hp_bars[enemy_id] = {
		"node": enemy_node,
		"bg": bar_bg,
		"fill": bar_fill,
		"current_hp": current_hp,
		"max_hp": max_hp
	}


## Update an enemy's HP
func update_enemy_hp(enemy_id: String, current_hp: int) -> void:
	if not hp_bars.has(enemy_id):
		return

	var hp_data = hp_bars[enemy_id]
	hp_data["current_hp"] = current_hp

	# Update bar width
	var percentage = float(current_hp) / float(hp_data["max_hp"])
	hp_data["fill"].size.x = 60 * percentage


## Remove an enemy's HP bar
func unregister_enemy(enemy_id: String) -> void:
	if not hp_bars.has(enemy_id):
		return

	var hp_data = hp_bars[enemy_id]
	hp_data["bg"].queue_free()
	hp_bars.erase(enemy_id)


## Register a remote player for username display
func register_player(player_id: String, player_node: Node3D, username: String) -> void:
	if username_labels.has(player_id):
		return

	var label = Label.new()
	label.text = username
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.0))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 3)
	label.z_index = 100

	usernames_container.add_child(label)

	username_labels[player_id] = {
		"node": player_node,
		"label": label
	}


## Remove a player's username
func unregister_player(player_id: String) -> void:
	if not username_labels.has(player_id):
		return

	var data = username_labels[player_id]
	data["label"].queue_free()
	username_labels.erase(player_id)


## Update all HP bar positions
func _update_hp_bars() -> void:
	for enemy_id in hp_bars.keys():
		var hp_data = hp_bars[enemy_id]
		var enemy_node = hp_data["node"]

		# Check if enemy still exists
		if not is_instance_valid(enemy_node):
			unregister_enemy(enemy_id)
			continue

		# Project 3D position to 2D screen space
		var world_pos = enemy_node.global_position + Vector3(0, 2.5, 0)
		var screen_pos = camera.unproject_position(world_pos)

		# Center the bar
		hp_data["bg"].position = screen_pos - hp_data["bg"].size / 2


## Update all username positions
func _update_usernames() -> void:
	for player_id in username_labels.keys():
		var data = username_labels[player_id]
		var player_node = data["node"]
		var label = data["label"]

		# Check if player still exists
		if not is_instance_valid(player_node):
			unregister_player(player_id)
			continue

		# Project 3D position to 2D screen space
		var world_pos = player_node.global_position + Vector3(0, 2.5, 0)
		var screen_pos = camera.unproject_position(world_pos)

		# Center the label
		label.position = screen_pos - label.size / 2


## Handle UI interval changes from SettingsManager
func _on_ui_interval_changed(interval: float) -> void:
	ui_update_interval = interval
