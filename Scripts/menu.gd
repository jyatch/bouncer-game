extends Node2D

## Loops last-time.mp3 for as long as the menu is up, and fades it out when
## the player clicks through to the disclaimer scene.

@onready var music: AudioStreamPlayer = $LastTimeMusic


func _ready() -> void:
	# AudioStreamMP3 doesn't have a per-node loop toggle the way Ogg streams
	# do -- looping by hand here means it doesn't depend on the import
	# setting (which defaults to false and isn't worth touching).
	music.finished.connect(music.play)
	music.play()


## Fades the menu music to silence over `duration` seconds -- defaults to
## Transition's own fade-out length, so the music dies right as the screen
## goes black instead of cutting or lingering. Does not block; the caller is
## free to start the scene change immediately after calling this.
func fade_out_music(duration: float = Transition.DEFAULT_FADE_OUT) -> void:
	if not music.playing:
		return
	var tween := create_tween()
	tween.tween_property(music, "volume_db", -80.0, duration)
	tween.finished.connect(music.stop)
