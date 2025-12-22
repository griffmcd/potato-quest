extends Control

## ChatUI - Handles chat display and input 
## 
## Displays chat messages from all players and allows the local players
## to send messages. 

# UI references
@onready var chat_display: RichTextLabel = $VBoxContainer/ChatDisplay
@onready var chat_input: LineEdit = $VBoxContainer/InputContainer/ChatInput
@onready var send_button: Button = $VBoxContainer/InputContainer/SendButton

# reference to NetworkManager
@onready var network = get_node("/root/NetworkManager")

# Reference to camera controller (found at runtime)
var camera_controller: Node3D = null
var chat_active: bool = false

func _ready() -> void:
    # Find camera controller
    var player = get_tree().get_first_node_in_group("player")
    if player:
        camera_controller = player.get_node_or_null("CameraRig")

    # Connect network signals
    network.chat_message_received.connect(_on_chat_message_received)

    # Connect UI signals
    send_button.pressed.connect(_on_send_button_pressed)
    chat_input.text_submitted.connect(_on_chat_submitted)
    chat_input.focus_exited.connect(_on_chat_focus_lost)

    # Initial welcome message
    _add_system_message("Welcome to Potato Quest! Press T to chat.")

func _on_send_button_pressed() -> void:
    _send_message()

func _on_chat_submitted(_text: String) -> void:
    _send_message()

func _send_message() -> void:
    var message = chat_input.text.strip_edges()

    if message.is_empty():
        _close_chat()
        return

    if not network or network.player_id.is_empty():
        _add_system_message("Not connected to server.")
        return

    network.send_chat(message)
    _close_chat()

func _on_chat_message_received(player_id: String, username: String, message: String) -> void:
    # Color code based on user
    var color = "#00ff00" if player_id == network.player_id else "#ffff00"
    var formatted_message = "[color=%s]%s:[/color] %s" % [color, username, message]
    _add_message(formatted_message)

func _add_message(text: String) -> void:
    # add line break if not first message 
    if chat_display.get_parsed_text().length() > 0:
        chat_display.append_text("\n")
    chat_display.append_text(text) 

func _add_system_message(text: String) -> void:
    var formatted = "[color=#888888][i]%s[/i][/color]" % text
    _add_message(formatted)

func _input(event: InputEvent) -> void:
    # ESC key closes chat if active
    if event.is_action_pressed("ui_cancel") and chat_active:
        _close_chat()
        get_viewport().set_input_as_handled()
        return

    # Toggle chat with T key (but not when typing in the input field)
    if event.is_action_pressed("toggle_chat"):
        # Don't toggle if we're currently typing in the chat input
        if chat_input.has_focus():
            return

        if chat_active:
            _close_chat()
        else:
            _open_chat()
        get_viewport().set_input_as_handled()

func _open_chat() -> void:
    chat_active = true
    chat_input.grab_focus()
    if camera_controller:
        camera_controller.enable_chat_mode()

func _close_chat() -> void:
    chat_active = false
    chat_input.release_focus()
    chat_input.text = ""
    if camera_controller:
        camera_controller.disable_chat_mode()

func _on_chat_focus_lost() -> void:
    # When chat loses focus, close chat mode
    if chat_active:
        _close_chat()