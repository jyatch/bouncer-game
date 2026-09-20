extends Control

@export var start_button: Button
@export var name_input: LineEdit

const AMBIENCE := preload("res://Audio Files/ambience.mp3")


func _ready() -> void:
	# Keeps looping (via the Music autoload) straight through the club
	# gameplay in Main -- see main.gd's _game_over() for where it stops.
	Music.play_loop(AMBIENCE)


func _on_start_button_pressed() -> void:
	var player_name: String = name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Raging Alcoholic Unc"
	
	PlayerData.player_name = player_name
	
	Transition.change_scene("res://Scenes/Main.tscn")
