extends CharacterBody3D 
## Enemy - represents an enemy in the game 

var enemy_id: String = ""
var enemy_type: String = "pig_man"
var current_health: int = 50
var max_health: int = 50

@onready var hurtbox: Area3D = $Hurtbox
@onready var body: Node3D = $CharacterVisual/Body
@onready var animation_player: AnimationPlayer = $CharacterVisual/Body/AnimationPlayer

signal enemy_clicked(enemy_id: String)
signal health_changed(enemy_id: String, current_hp: int)

func _ready() -> void:
    hurtbox.input_event.connect(_on_hurtbox_input_event)

    # Debug: Check if animation player exists
    if not animation_player:
        print("ERROR: Enemy ", enemy_id, " - AnimationPlayer not found!")
    else:
        print("Enemy ", enemy_id, " - AnimationPlayer found, playing Idle")
        _update_animation_state()

func update_health(new_health: int) -> void:
    current_health = new_health
    health_changed.emit(enemy_id, current_health)
    if current_health <= 0:
        _play_death_animation()

func _play_death_animation() -> void:
    # disable collision
    hurtbox.set_deferred("monitoring", false)
    # scale down animation
    var tween = create_tween()
    tween.tween_property(self, "scale", Vector3.ZERO, 0.3)
    tween.tween_callback(queue_free)

func _on_hurtbox_input_event(_camera, event, _position, _normal, _shape_idx):
    if event is InputEventMouseButton:
        if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
            print("Enemy clicked: ", enemy_id)
            enemy_clicked.emit(enemy_id)

func _update_animation_state() -> void:
    if not animation_player:
        return
    # For now, enemies just play idle animation
    # In the future, this can be extended for attack/walk animations
    if animation_player.current_animation != "Idle":
        animation_player.play("Idle")
