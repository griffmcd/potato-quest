extends CharacterBody3D 
## Enemy - represents an enemy in the game 

var enemy_id: String = ""
var enemy_type: String = "pig_man"
var current_health: int = 50 
var max_health: int = 50 

@onready var health_label: Label3D = $Label3D
@onready var hurtbox: Area3D = $Hurtbox 
@onready var body: Node3D = $Body 

signal enemy_clicked(enemy_id: String) 

func _ready() -> void:
    update_health_label() 
    hurtbox.input_event.connect(_on_hurtbox_input_event)

func update_health(new_health: int) -> void:
    current_health = new_health 
    update_health_label() 
    if current_health <= 0:
        _play_death_animation() 

func update_health_label() -> void:
    if health_label:
        health_label.text = "HP: %d/%d" % [current_health, max_health]

func _play_death_animation() -> void:
    # disable collision 
    hurtbox.set_deferred("monitoring", false)
    # scale down animation 
    var tween = create_tween()
    tween.set_parallel(true) 
    tween.tween_property(self, "scale", Vector3.ZERO, 0.3)
    tween.tween_property(health_label, "modulate:a", 0.0, 0.2)
    tween.chain().tween_callback(queue_free)

func _on_hurtbox_input_event(_camera, event, _position, _normal, _shape_idx):
    if event is InputEventMouseButton:
        if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
            print("Enemy clicked: ", enemy_id)
            enemy_clicked.emit(enemy_id)
