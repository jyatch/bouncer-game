extends TextureButton

func _on_pressed():
	var menu := get_parent()
	if menu.has_method("fade_out_music"):
		menu.fade_out_music()
	Transition.change_scene("res://Scenes/Disclaimer.tscn")
