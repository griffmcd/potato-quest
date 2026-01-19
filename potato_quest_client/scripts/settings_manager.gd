extends Node
## SettingsManager - Centralized settings singleton for Potato Quest
##
## Provides single source of truth for all performance and game settings.
## Handles JSON persistence to user directory and signal-based reactivity.

const SETTINGS_FILE_PATH = "user://settings.json"

# Nested dictionary for organized settings
var _settings: Dictionary = {}

# Immutable backup of defaults
var _defaults: Dictionary = {}

# Signals for reactivity
signal setting_changed(category: String, key: String, value: Variant)
signal category_changed(category: String, settings: Dictionary)

# Specific signals for common settings groups
signal network_interval_changed(position_interval: float, rotation_interval: float)
signal animation_interval_changed(player: float, remote_player: float)
signal ui_interval_changed(overlay_interval: float)
signal rendering_changed(max_fps: int, vsync_mode: int)
signal gameplay_changed(interpolation_speed: float, move_threshold: float, rotation_threshold: float)


func _ready() -> void:
	_initialize_defaults()
	_load_settings()
	apply_rendering_settings()
	print("SettingsManager: Settings loaded successfully")


## Initialize default values for all settings
func _initialize_defaults() -> void:
	_defaults = {
		"network": {
			"position_send_interval": 0.1,
			"rotation_send_interval": 0.1
		},
		"animation": {
			"player_update_interval": 0.05,
			"remote_player_update_interval": 0.05
		},
		"ui": {
			"overlay_update_interval": 0.05
		},
		"rendering": {
			"max_fps": 60,
			"vsync_mode": 1,
			"camera_culling_distance": 50.0
		},
		"gameplay": {
			"interpolation_speed": 10.0,
			"move_threshold": 0.5,
			"rotation_threshold": 0.1
		}
	}

	# Deep copy defaults to settings
	_settings = _deep_copy_dict(_defaults)


## Load settings from disk, merge with defaults
func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_FILE_PATH):
		print("SettingsManager: No settings file found, using defaults")
		return

	var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
	if not file:
		push_error("SettingsManager: Failed to open settings file")
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var parse_result = json.parse(json_string)

	if parse_result != OK:
		push_error("SettingsManager: Failed to parse settings JSON, using defaults")
		return

	var loaded_data = json.data
	if typeof(loaded_data) != TYPE_DICTIONARY:
		push_error("SettingsManager: Invalid settings format, using defaults")
		return

	# Merge loaded settings with defaults (preserves new settings added in updates)
	_merge_settings(loaded_data)
	print("SettingsManager: Settings loaded from disk")


## Merge loaded settings with defaults
func _merge_settings(loaded: Dictionary) -> void:
	for category in _defaults.keys():
		if not loaded.has(category):
			continue

		if typeof(loaded[category]) != TYPE_DICTIONARY:
			continue

		for key in _defaults[category].keys():
			if loaded[category].has(key):
				_settings[category][key] = loaded[category][key]


## Save settings to disk
func save_settings() -> void:
	var file = FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
	if not file:
		push_error("SettingsManager: Failed to open settings file for writing")
		return

	var json_string = JSON.stringify(_settings, "\t")  # Pretty print with tabs
	file.store_string(json_string)
	file.close()
	print("SettingsManager: Settings saved to disk")


## Generic getter with default fallback
func get_setting(category: String, key: String, default_value: Variant) -> Variant:
	if not _settings.has(category):
		push_warning("SettingsManager: Unknown category '%s'" % category)
		return default_value

	if not _settings[category].has(key):
		push_warning("SettingsManager: Unknown key '%s' in category '%s'" % [key, category])
		return default_value

	return _settings[category][key]


## Generic setter with validation and signals
func set_setting(category: String, key: String, value: Variant) -> void:
	if not _settings.has(category):
		push_warning("SettingsManager: Cannot set unknown category '%s'" % category)
		return

	if not _settings[category].has(key):
		push_warning("SettingsManager: Cannot set unknown key '%s' in category '%s'" % [key, category])
		return

	_settings[category][key] = value

	# Emit signals
	setting_changed.emit(category, key, value)
	category_changed.emit(category, _settings[category])
	_emit_specific_signals(category)


## Get entire category as dictionary
func get_category(category: String) -> Dictionary:
	if not _settings.has(category):
		push_warning("SettingsManager: Unknown category '%s'" % category)
		return {}

	return _settings[category].duplicate()


## Reset category to defaults
func reset_category(category: String) -> void:
	if not _defaults.has(category):
		push_warning("SettingsManager: Unknown category '%s'" % category)
		return

	_settings[category] = _deep_copy_dict(_defaults[category])
	category_changed.emit(category, _settings[category])
	_emit_specific_signals(category)
	print("SettingsManager: Reset category '%s' to defaults" % category)


## Reset all settings to defaults
func reset_all() -> void:
	_settings = _deep_copy_dict(_defaults)

	# Emit signals for all categories
	for category in _settings.keys():
		category_changed.emit(category, _settings[category])
		_emit_specific_signals(category)

	print("SettingsManager: Reset all settings to defaults")


## Emit category-specific signals
func _emit_specific_signals(category: String) -> void:
	match category:
		"network":
			network_interval_changed.emit(
				_settings["network"]["position_send_interval"],
				_settings["network"]["rotation_send_interval"]
			)
		"animation":
			animation_interval_changed.emit(
				_settings["animation"]["player_update_interval"],
				_settings["animation"]["remote_player_update_interval"]
			)
		"ui":
			ui_interval_changed.emit(
				_settings["ui"]["overlay_update_interval"]
			)
		"rendering":
			rendering_changed.emit(
				_settings["rendering"]["max_fps"],
				_settings["rendering"]["vsync_mode"]
			)
		"gameplay":
			gameplay_changed.emit(
				_settings["gameplay"]["interpolation_speed"],
				_settings["gameplay"]["move_threshold"],
				_settings["gameplay"]["rotation_threshold"]
			)


## Apply rendering settings to engine
func apply_rendering_settings() -> void:
	var max_fps = _settings["rendering"]["max_fps"]
	var vsync_mode = _settings["rendering"]["vsync_mode"]

	Engine.max_fps = max_fps
	DisplayServer.window_set_vsync_mode(vsync_mode)

	print("SettingsManager: Applied rendering settings (FPS: %d, VSync: %d)" % [max_fps, vsync_mode])


## Deep copy dictionary (recursive)
func _deep_copy_dict(dict: Dictionary) -> Dictionary:
	var result = {}
	for key in dict.keys():
		if typeof(dict[key]) == TYPE_DICTIONARY:
			result[key] = _deep_copy_dict(dict[key])
		else:
			result[key] = dict[key]
	return result


# ============================================================================
# Convenience Getters (Type-safe, autocomplete-friendly)
# ============================================================================

## Network settings
func get_position_send_interval() -> float:
	return get_setting("network", "position_send_interval", 0.1)

func get_rotation_send_interval() -> float:
	return get_setting("network", "rotation_send_interval", 0.1)


## Animation settings
func get_player_animation_interval() -> float:
	return get_setting("animation", "player_update_interval", 0.05)

func get_remote_animation_interval() -> float:
	return get_setting("animation", "remote_player_update_interval", 0.05)


## UI settings
func get_ui_update_interval() -> float:
	return get_setting("ui", "overlay_update_interval", 0.05)


## Rendering settings
func get_max_fps() -> int:
	return get_setting("rendering", "max_fps", 60)

func get_vsync_mode() -> int:
	return get_setting("rendering", "vsync_mode", 1)

func get_camera_culling_distance() -> float:
	return get_setting("rendering", "camera_culling_distance", 50.0)


## Gameplay settings
func get_interpolation_speed() -> float:
	return get_setting("gameplay", "interpolation_speed", 10.0)

func get_move_threshold() -> float:
	return get_setting("gameplay", "move_threshold", 0.5)

func get_rotation_threshold() -> float:
	return get_setting("gameplay", "rotation_threshold", 0.1)
