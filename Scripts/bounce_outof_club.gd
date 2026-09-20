extends Node2D

@onready var endbounce = $endbounce
@onready var get_out_sfx = $GetOutSfx

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	endbounce.play()
	get_out_sfx.play()
	endbounce.animation_finished.connect(_on_endbounce_animation_finished)


func _on_endbounce_animation_finished() -> void:
	await get_tree().create_timer(2.0).timeout
	await get_tree().create_timer(3.0).timeout
	Transition.change_scene("res://Scenes/Menu.tscn")
