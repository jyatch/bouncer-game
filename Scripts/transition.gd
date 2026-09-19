extends CanvasLayer

## Global fade-to-black scene changer.
##
## Lives above every scene, so the black stays on screen across the swap and
## you get fade-out -> change -> fade-in instead of a hard cut.
##
## Install: Project Settings -> Globals -> Autoload -> add this file,
##          name it exactly  Transition
##
## Use:     Transition.change_scene("res://disclaimer.tscn")

signal covered   ## screen is fully black, scene is about to change
signal finished  ## new scene is visible, fade complete

const DEFAULT_FADE_OUT := 0.45
const DEFAULT_HOLD := 0.10
const DEFAULT_FADE_IN := 0.45

var _rect: ColorRect
var _busy: bool = false


func _ready() -> void:
	# Above everything, including any CanvasLayer a scene might add.
	layer = 128
	# Keeps working even if the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.modulate.a = 0.0
	_rect.visible = false
	add_child(_rect)
	# A Control parented to a CanvasLayer anchors to the viewport, so this
	# stays full-screen at any window size.
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Fade to black, load `path`, fade back in. Safe to await.
func change_scene(
	path: String,
	fade_out: float = DEFAULT_FADE_OUT,
	hold: float = DEFAULT_HOLD,
	fade_in: float = DEFAULT_FADE_IN
) -> void:
	if _busy:
		return
	if not ResourceLoader.exists(path):
		push_error("Transition: no scene at %s" % path)
		return

	_busy = true
	await cover(fade_out)
	covered.emit()

	get_tree().change_scene_to_file(path)

	# change_scene_to_file is deferred to the end of the frame, so wait for
	# the new scene to actually exist and get drawn before uncovering.
	await get_tree().process_frame
	await get_tree().process_frame

	if hold > 0.0:
		await get_tree().create_timer(hold).timeout

	await reveal(fade_in)
	_busy = false
	finished.emit()


## Fade the screen to black and leave it there.
func cover(duration: float = DEFAULT_FADE_OUT) -> void:
	_rect.visible = true
	# Swallow clicks so nothing gets pressed mid-transition.
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var t := create_tween()
	t.tween_property(_rect, "modulate:a", 1.0, duration)
	await t.finished


## Fade the black away to show whatever is underneath.
func reveal(duration: float = DEFAULT_FADE_IN) -> void:
	_rect.visible = true
	var t := create_tween()
	t.tween_property(_rect, "modulate:a", 0.0, duration)
	await t.finished
	_rect.visible = false
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_busy() -> bool:
	return _busy
