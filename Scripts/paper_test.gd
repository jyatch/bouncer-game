extends Control

## Throwaway test scene for the paper. Set it as the main scene, run it,
## and scribble. Delete once the real club scene exists.
##
##   SPACE      start / stop the bouncing
##   UP / DOWN  change club (speed goes up per club)
##   Z          undo last stroke
##   C          clear the page
##   ENTER      fake submit - proves capture_png() works

@onready var paper := $Paper
@onready var readout: Label = $Readout


func _ready() -> void:
	paper.edge_hit.connect(_on_edge_hit)
	_update_readout()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	match (event as InputEventKey).keycode:
		KEY_SPACE:
			if paper.bouncing:
				paper.stop_bouncing()
			else:
				paper.start_bouncing()
			_update_readout()
		KEY_UP:
			paper.set_club(paper.club_index + 1)
			_update_readout()
		KEY_DOWN:
			paper.set_club(paper.club_index - 1)
			_update_readout()
		KEY_Z:
			paper.undo()
			_update_readout()
		KEY_C:
			paper.clear()
			_update_readout()
		KEY_ENTER, KEY_KP_ENTER:
			_fake_submit()


func _fake_submit() -> void:
	if paper.is_blank():
		readout.text = "you didn't draw anything"
		return

	var png: PackedByteArray = await paper.capture_png()
	# This is exactly what you'll base64 and POST to the vision API later.
	readout.text = "captured %d bytes (%d strokes)" % [png.size(), paper.stroke_count()]

	# Uncomment to eyeball what the AI will actually see:
	# var img := Image.new()
	# img.load_png_from_buffer(png)
	# img.save_png("user://last_submission.png")
	# print("saved to ", ProjectSettings.globalize_path("user://last_submission.png"))


func _on_edge_hit(_normal: Vector2) -> void:
	# Hook your thud sound effect in here.
	pass


func _update_readout() -> void:
	readout.text = "club %d   speed %d px/s   %s   |   SPACE bounce  UP/DOWN club  Z undo  C clear  ENTER submit" % [
		paper.club_index,
		int(paper.velocity.length()),
		"moving" if paper.bouncing else "parked",
	]
