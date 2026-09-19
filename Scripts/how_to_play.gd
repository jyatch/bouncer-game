extends Control


@export var game_scene: PackedScene
@export var start_button: Button
@export var name_input: LineEdit


func _on_start_button_pressed() -> void:
	var player_name: String = name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Raging Alcoholic Unc"
	
	PlayerData.player_name = player_name
	
	get_tree().change_scene_to_packed(game_scene)
