extends Control

## InventoryUI - Displays player inventory, equipment slots, and stats
##
## Toggle with E key. Shows 28 inventory slots (4 rows x 7 cols),
## 7 equipment slots, stats panel, and gold display.

# UI references (set in _ready from scene tree)
@onready var inventory_grid: GridContainer = $Panel/VBoxContainer/HSplitContainer/InventorySection/InventoryGrid
@onready var equipment_slots: VBoxContainer = $Panel/VBoxContainer/HSplitContainer/RightPanel/EquipmentSection/EquipmentSlots
@onready var stats_label: RichTextLabel = $Panel/VBoxContainer/HSplitContainer/RightPanel/StatsSection/StatsLabel
@onready var gold_label: Label = $Panel/VBoxContainer/GoldLabel

# Reference to NetworkManager
@onready var network = get_node("/root/NetworkManager")

# Reference to camera controller
var camera_controller: Node3D = null
var inventory_active: bool = false

# Item catalog (mirrored from server ItemCatalog)
var item_catalog: Dictionary = {
	"bronze_sword": {
		"name": "Bronze Sword",
		"slot": "weapon",
		"stats": {"damage": 15, "str_bonus": 5}
	},
	"wooden_shield": {
		"name": "Wooden Shield",
		"slot": "shield",
		"stats": {"def_bonus": 3}
	},
	"leather_tunic": {
		"name": "Leather Tunic",
		"slot": "chest",
		"stats": {"def_bonus": 2}
	},
	"iron_band": {
		"name": "Iron Band",
		"slot": "ring",
		"stats": {"str_bonus": 2}
	}
}

# Current state
var current_inventory: Array = []
var current_equipment: Dictionary = {}
var current_stats: Dictionary = {}
var current_gold: int = 0

func _ready() -> void:
	# Find camera controller
	var player = get_tree().get_first_node_in_group("player")
	if player:
		camera_controller = player.get_node_or_null("CameraRig")

	# Connect network signals
	network.inventory_changed.connect(_on_inventory_changed)
	network.equipment_updated.connect(_on_equipment_updated)
	network.inventory_updated.connect(_on_gold_updated)
	network.error_received.connect(_on_error_received)

	# Initialize UI
	_setup_inventory_grid()
	_setup_equipment_slots()

	# Hide initially
	visible = false

func _input(event: InputEvent) -> void:
	# Toggle inventory with E key
	if event.is_action_pressed("toggle_inventory"):
		if inventory_active:
			_close_inventory()
		else:
			_open_inventory()
		get_viewport().set_input_as_handled()

func _open_inventory() -> void:
	inventory_active = true
	visible = true
	if camera_controller:
		camera_controller.enable_chat_mode()  # Disable mouselook

func _close_inventory() -> void:
	inventory_active = false
	visible = false
	if camera_controller:
		camera_controller.disable_chat_mode()  # Re-enable mouselook

func _setup_inventory_grid() -> void:
	# Create 28 inventory slots (4 rows x 7 cols)
	inventory_grid.columns = 7
	for i in range(28):
		var slot = _create_inventory_slot(i)
		inventory_grid.add_child(slot)

func _setup_equipment_slots() -> void:
	# Create 7 equipment slots
	var slots = ["weapon", "shield", "head", "chest", "legs", "ring", "amulet"]
	for slot_name in slots:
		var slot = _create_equipment_slot(slot_name)
		equipment_slots.add_child(slot)

func _create_inventory_slot(slot_number: int) -> Panel:
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(60, 60)
	panel.set_meta("slot_number", slot_number)

	var label = Label.new()
	label.name = "ItemLabel"
	label.text = ""
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(label)

	# Click handler
	var button = Button.new()
	button.name = "ClickButton"
	button.flat = true
	button.custom_minimum_size = Vector2(60, 60)
	button.pressed.connect(func(): _on_inventory_slot_clicked(slot_number))
	panel.add_child(button)

	return panel

func _create_equipment_slot(slot_name: String) -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.set_meta("slot_name", slot_name)

	# Label for slot name
	var name_label = Label.new()
	name_label.text = slot_name.capitalize() + ":"
	name_label.custom_minimum_size = Vector2(80, 0)
	hbox.add_child(name_label)

	# Panel for item display
	var panel = Panel.new()
	panel.custom_minimum_size = Vector2(60, 60)

	var item_label = Label.new()
	item_label.name = "ItemLabel"
	item_label.text = ""
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(item_label)

	# Click handler
	var button = Button.new()
	button.name = "ClickButton"
	button.flat = true
	button.custom_minimum_size = Vector2(60, 60)
	button.pressed.connect(func(): _on_equipment_slot_clicked(slot_name))
	panel.add_child(button)

	hbox.add_child(panel)
	return hbox

func _on_inventory_slot_clicked(slot_number: int) -> void:
	# Find item in this slot
	var item = current_inventory.filter(func(i): return i.get("slot") == slot_number)
	if item.size() > 0:
		var instance_id = item[0].get("instance_id")
		# Show context menu: Equip or Drop
		_show_item_context_menu(instance_id, "inventory")

func _on_equipment_slot_clicked(slot_name: String) -> void:
	# Check if slot has item
	if current_equipment.has(slot_name) and current_equipment[slot_name] != null:
		# Unequip item
		network.send_unequip_item(slot_name)

func _show_item_context_menu(instance_id: String, source: String) -> void:
	# For MVP: Equip if from inventory, Drop is future feature
	if source == "inventory":
		network.send_equip_item(instance_id)

func _on_inventory_changed(inventory: Array, gold: int) -> void:
	current_inventory = inventory
	if gold >= 0:
		current_gold = gold
	_update_inventory_display()
	_update_gold_display()

func _on_equipment_updated(equipment: Dictionary, stats: Dictionary) -> void:
	current_equipment = equipment
	current_stats = stats
	_update_equipment_display()
	_update_stats_display()

func _on_gold_updated(gold: int) -> void:
	current_gold = gold
	_update_gold_display()

func _on_error_received(message: String) -> void:
	# Show error popup or add to chat
	print("Error: ", message)

func _update_inventory_display() -> void:
	for i in range(28):
		var slot_panel = inventory_grid.get_child(i)
		var label = slot_panel.get_node("ItemLabel")

		# Find item in this slot
		var item = current_inventory.filter(func(it): return it.get("slot") == i)
		if item.size() > 0:
			var template_id = item[0].get("template_id")
			var item_data = item_catalog.get(template_id, {})
			label.text = item_data.get("name", template_id)
		else:
			label.text = ""

func _update_equipment_display() -> void:
	for child in equipment_slots.get_children():
		var slot_name = child.get_meta("slot_name")
		var panel = child.get_child(1)  # Second child is the panel
		var label = panel.get_node("ItemLabel")

		var equipped_item = current_equipment.get(slot_name)
		if equipped_item != null:
			var template_id = equipped_item.get("template_id")
			var item_data = item_catalog.get(template_id, {})
			label.text = item_data.get("name", template_id)
		else:
			label.text = ""

func _update_stats_display() -> void:
	var text = "[b]Stats[/b]\n"
	text += "STR: %d\n" % current_stats.get("str", 0)
	text += "DEF: %d\n" % current_stats.get("def", 0)
	text += "DEX: %d\n" % current_stats.get("dex", 0)
	text += "INT: %d\n" % current_stats.get("int", 0)
	text += "Damage: %d\n" % current_stats.get("damage", 0)
	text += "Health: %d/%d" % [current_stats.get("health", 100), current_stats.get("max_health", 100)]
	stats_label.text = text

func _update_gold_display() -> void:
	gold_label.text = "Gold: %d" % current_gold
