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

func _ready() -> void:
    # Connect network signals 
    network.chat_message_received.connect(_on_chat_message_received)

    # Connect UI signals 
    send_button.pressed.connect(_on_send_button_pressed)
    chat_input.text_submitted.connect(_on_chat_submitted)

    # Initial welcome message 
    _add_system_message("Welcome to Potato Quest! Press Enter to chat.")

func _on_send_button_pressed() -> void:
    _send_message()

func _on_chat_submitted(_text: String) -> void:
    _send_message()

func _send_message() -> void:
    var message = chat_input.text.strip_edges()

    if message.is_empty():
        return 
    
    if not network or network.player_id.is_empty():
        _add_system_message("Not connected to server.")
        return

    network.send_chat(message)
    chat_input.text = ""
    chat_input.grab_focus()

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