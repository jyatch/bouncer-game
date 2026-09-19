extends Control

## Test harness for the paper + classifier.
##
##   SPACE      start / stop the bouncing
##   UP / DOWN  change club (speed goes up per club)
##   Z          undo last stroke
##   C          clear the page
##   ENTER      submit the drawing for recognition
##   D          open the last image sent to the model (web only)
##   K          self test - is the model responding to the image at all?
##
## NOTE: DoodleAI (Transformers.js) only exists in a WEB EXPORT. In the editor
## it reports "unsupported" and we fall back to the GDScript QuickDraw model.

@onready var paper := $Paper
@onready var readout: Label = $Readout

var _busy: bool = false
var _debug_view: TextureRect
var _target: String = ""


func _ready() -> void:
	paper.edge_hit.connect(_on_edge_hit)
	_build_debug_view()

	# Start the ~20 MB model download immediately. In the real game, do this
	# on the disclaimer scene so it's warm before the first club.
	if QuickDraw.loaded:
		_new_target()
	elif DoodleAI.status == "loading":
		readout.text = "downloading model ..."
		DoodleAI.status_changed.connect(_on_ai_status)
	else:
		readout.text = "no model - run train_quickdraw.py and put the files in res://model/"


func _on_ai_status(s: String) -> void:
	if s == "error":
		readout.text = "model failed: %s" % DoodleAI.last_error
	elif s == "ready":
		# If N comes back 0 here, the model config never loaded -- a
		# different bug than a preprocessing mismatch. See CLAUDE.md.
		readout.text = "model ready, %d labels" % DoodleAI.label_count
		await get_tree().create_timer(1.0).timeout
		_new_target()
	else:
		_new_target()


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
		KEY_D:
			_toggle_debug_view()
		KEY_K:
			_self_test()
		KEY_T:
			DoodleAI.tta = not DoodleAI.tta
			readout.text = "ensemble: %s" % ("on (4 variants)" if DoodleAI.tta else "off")
		KEY_B:
			DoodleAI.binarize = not DoodleAI.binarize
			readout.text = "binarize: %s" % DoodleAI.binarize
		KEY_M:
			# Cycle the margin: 0.08 -> 0.16 -> 0.24 -> 0.00 -> ...
			DoodleAI.margin_ratio = fmod(DoodleAI.margin_ratio + 0.08, 0.32)
			readout.text = "margin: %.2f" % DoodleAI.margin_ratio
		KEY_S:
			# Cycle the image size the model receives.
			DoodleAI.out_size = 28 if DoodleAI.out_size == 224 else (
				64 if DoodleAI.out_size == 28 else (
				128 if DoodleAI.out_size == 64 else 224))
			readout.text = "size: %d" % DoodleAI.out_size
		KEY_I:
			DoodleAI.invert_ink = not DoodleAI.invert_ink
			DoodleAI._polarity_locked = true
			readout.text = "invert: %s" % DoodleAI.invert_ink
		KEY_ENTER, KEY_KP_ENTER:
			_submit()


## THIS is where the classifier attaches.
func _submit() -> void:
	if _busy:
		return
	if paper.is_blank():
		readout.text = "you didn't draw anything"
		return

	_busy = true
	readout.text = "thinking ..."

	var img: Image = await paper.capture_image()
	var guesses: Array = []

	if QuickDraw.loaded:
		# Only 15 classes, and the preprocessing here provably matches what
		# the model was trained on -- so its confidence means something.
		guesses = QuickDraw.classify(img, 3)
	elif DoodleAI.is_ready():
		guesses = await DoodleAI.classify_among(img, DoodleAI.PROMPTS, 3)
	else:
		readout.text = "no classifier loaded"
		_busy = false
		return

	if guesses.is_empty():
		readout.text = "no idea what that is"
		_busy = false
		return

	var parts: PackedStringArray = []
	for g in guesses:
		parts.append("%s %d%%" % [g.label, int(g.score * 100.0)])

	var placed: int = -1
	for i in guesses.size():
		if guesses[i].label == _target:
			placed = i
			break

	if placed == 0:
		readout.text = "PASS (first guess)   %s" % ", ".join(parts)
		await get_tree().create_timer(1.5).timeout
		paper.clear()
		_new_target()
	elif placed > 0:
		readout.text = "PASS (guess %d)   %s" % [placed + 1, ", ".join(parts)]
		await get_tree().create_timer(1.5).timeout
		paper.clear()
		_new_target()
	else:
		var raw: PackedStringArray = []
		for g in DoodleAI.last_raw:
			raw.append("%s %d%%" % [g.label, int(g.score * 100.0)])
		readout.text = "REJECTED - that's a %s? (wanted %s)   [raw: %s]" % [
			guesses[0].label, _target, ", ".join(raw)]

	_busy = false


## Feeds the classifier three images built in code. If all three come back
## with the SAME label, the model is not responding to the image at all and
## the bug is in the pipeline, not in your drawing.
func _self_test() -> void:
	if _busy:
		return
	_busy = true
	DoodleAI._polarity_locked = true  # don't recalibrate on a blank page

	var tests: Array = [
		["blank", _make_test_image("blank")],
		["square", _make_test_image("square")],
		["bars", _make_test_image("bars")],
	]

	var lines: PackedStringArray = []
	for pair in tests:
		readout.text = "self test: %s ..." % pair[0]
		var g: Array = await DoodleAI.classify_among(pair[1], DoodleAI.PROMPTS, 1)
		var raw: String = DoodleAI.last_raw[0].label if not DoodleAI.last_raw.is_empty() else "-"
		lines.append("%s -> %s (raw %s)" % [
			pair[0], g[0].label if not g.is_empty() else "none", raw])

	readout.text = "SELF TEST   " + "   |   ".join(lines)
	print("SELF TEST  ", lines)
	_busy = false


func _make_test_image(kind: String) -> Image:
	const S := 420
	var paper_col := Color(0.968, 0.952, 0.902)
	var ink_col := Color(0.105, 0.09, 0.129)

	var img := Image.create_empty(S, S, false, Image.FORMAT_RGBA8)
	img.fill(paper_col)

	match kind:
		"square":
			var a := 90
			var b := S - 180
			var w := 18
			img.fill_rect(Rect2i(a, a, b, w), ink_col)
			img.fill_rect(Rect2i(a, a + b - w, b, w), ink_col)
			img.fill_rect(Rect2i(a, a, w, b), ink_col)
			img.fill_rect(Rect2i(a + b - w, a, w, b), ink_col)
		"bars":
			img.fill_rect(Rect2i(60, 195, 300, 24), ink_col)
			img.fill_rect(Rect2i(195, 60, 24, 300), ink_col)
		_:
			pass  # blank

	return img


func _new_target() -> void:
	if QuickDraw.loaded:
		_target = QuickDraw.random_prompt()
	else:
		_target = DoodleAI.random_prompt()
	_update_readout()


## An on-screen preview of exactly what the model received. No browser
## console, no popup blocker, works identically on desktop and web.
func _build_debug_view() -> void:
	_debug_view = TextureRect.new()
	_debug_view.visible = false
	_debug_view.custom_minimum_size = Vector2(256, 256)
	_debug_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_debug_view.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_debug_view.position = Vector2(get_viewport_rect().size.x - 272, 16)
	_debug_view.size = Vector2(256, 256)
	add_child(_debug_view)

	var border := ColorRect.new()
	border.color = Color(0.909804, 0.796078, 0.376471, 1)
	border.size = Vector2(264, 264)
	border.position = _debug_view.position - Vector2(4, 4)
	border.z_index = -1
	border.visible = false
	add_child(border)
	_debug_view.set_meta("border", border)


func _toggle_debug_view() -> void:
	if DoodleAI.last_image == null:
		readout.text = "nothing sent to the model yet - draw and press ENTER first"
		return

	var on := not _debug_view.visible
	_debug_view.visible = on
	(_debug_view.get_meta("border") as ColorRect).visible = on
	if on:
		_debug_view.texture = ImageTexture.create_from_image(DoodleAI.last_image)


func _on_edge_hit(_normal: Vector2) -> void:
	# Hook your thud sound effect in here.
	pass


func _update_readout() -> void:
	if _busy:
		return
	readout.text = "DRAW ME A %s   |   club %d   %s   |   ENTER submit  C clear  Z undo  SPACE bounce  D debug" % [
		_target.to_upper(),
		paper.club_index,
		"moving" if paper.bouncing else "parked",
	]
