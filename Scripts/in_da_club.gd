extends Node2D

@onready var Club = $Club 

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Club.play()
