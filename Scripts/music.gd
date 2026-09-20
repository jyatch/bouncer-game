extends Node

## Global background-music player.
##
## Lives across scene changes (autoload), so a track started in one scene
## keeps playing -- same stream, same position -- straight into the next,
## instead of restarting (or cutting out) at every scene swap. Used for
## ambience.mp3: starts on HowToPlay, keeps looping through the club
## gameplay in Main, and only stops once the player loses (see main.gd's
## _game_over()).
##
## Install: Project Settings -> Globals -> Autoload -> name it exactly Music

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(_on_finished)


## Starts `stream` looping. No-op if it's already the one playing, so a
## scene re-entering this call (e.g. on a re-run) doesn't restart the track
## from the top.
func play_loop(stream: AudioStream) -> void:
	if _player.stream == stream and _player.playing:
		return
	_player.stream = stream
	_player.volume_db = 0.0
	_player.play()


func _on_finished() -> void:
	# Manual loop -- same reasoning as menu.gd's LastTimeMusic: AudioStreamMP3
	# doesn't expose a per-node loop toggle the way Ogg streams do.
	if _player.stream != null:
		_player.play()


## Fades to silence over `duration` seconds, then stops. Safe to call when
## nothing is playing.
func fade_out(duration: float = 0.6) -> void:
	if not _player.playing:
		return
	var tween := create_tween()
	tween.tween_property(_player, "volume_db", -80.0, duration)
	tween.finished.connect(stop)


func stop() -> void:
	_player.stop()


func is_playing() -> bool:
	return _player.playing
