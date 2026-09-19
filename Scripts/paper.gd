extends SubViewportContainer

## A sheet of paper you can draw on, that refuses to hold still.
##
## Drawing happens inside a SubViewport, which means:
##   - stroke coordinates are always paper-local, no matter where the paper is
##   - capture_png() gives you a clean image with no background bleed
##
## The paper moves while you draw. That is the entire joke: your pen stays
## where the mouse is on screen, and the sheet slides out from under it.

signal stroke_finished
signal edge_hit(normal: Vector2)

@export var bounce_box: Control
@export_group("Look")
@export var paper_color: Color = Color(0.968, 0.952, 0.902)
@export var ink_color: Color = Color(0.105, 0.09, 0.129)
@export var ink_width: float = 5.0
## Smooth lines read better to the AI. Turn off if you want a jagged pixel look.
@export var antialias: bool = true

@export_group("Bounce")
@export var bouncing: bool = false
## Speed at club 0, in pixels per second.
@export var base_speed: float = 90.0
## Added to the speed for every club after the first.
@export var speed_per_club: float = 55.0
## Keeps the paper off a perfect 45-degree path so it doesn't loop forever.
@export var angle_jitter_degrees: float = 12.0

var velocity: Vector2 = Vector2.ZERO
var club_index: int = 0

var _strokes: Array[PackedVector2Array] = []
var _current: PackedVector2Array = PackedVector2Array()
var _drawing: bool = false

@onready var _viewport: SubViewport = $SubViewport
@onready var _sheet: Node2D = $SubViewport/Sheet
@onready var _bg: ColorRect = $SubViewport/BG

const MIN_POINT_DISTANCE := 2.5


func _ready() -> void:
	# CanvasItem emits `draw` when it redraws, so we can do all the rendering
	# from this script instead of giving the Sheet its own.
	_sheet.draw.connect(_on_sheet_draw)
	_bg.color = paper_color
	set_club(0)


# ---------------------------------------------------------------- drawing ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var p := _to_paper(event.position)
			# Only start a stroke if the click actually landed on the sheet.
			if Rect2(Vector2.ZERO, size).has_point(p):
				_drawing = true
				_current = PackedVector2Array([p])
				_sheet.queue_redraw()
				get_viewport().set_input_as_handled()
		elif _drawing:
			_end_stroke()

	elif event is InputEventMouseMotion and _drawing:
		var p := _to_paper(event.position).clamp(Vector2.ZERO, size)
		if _current.is_empty() or p.distance_to(_current[-1]) >= MIN_POINT_DISTANCE:
			_current.append(p)
			_sheet.queue_redraw()


## Screen position -> paper-local position. Uses the paper's position *right
## now*, which is what makes drawing on a moving sheet feel the way it does.
func _to_paper(screen_pos: Vector2) -> Vector2:
	return screen_pos - global_position


func _end_stroke() -> void:
	_drawing = false
	if _current.size() > 0:
		_strokes.append(_current)
		stroke_finished.emit()
	_current = PackedVector2Array()
	_sheet.queue_redraw()


func _on_sheet_draw() -> void:
	for s in _strokes:
		_draw_stroke(s)
	_draw_stroke(_current)


func _draw_stroke(s: PackedVector2Array) -> void:
	if s.size() > 1:
		_sheet.draw_polyline(s, ink_color, ink_width, antialias)
	elif s.size() == 1:
		# A single tap should still leave a dot.
		_sheet.draw_circle(s[0], ink_width * 0.5, ink_color)


# ------------------------------------------------------------------- edit ---

func clear() -> void:
	_strokes.clear()
	_current = PackedVector2Array()
	_drawing = false
	_sheet.queue_redraw()


func undo() -> void:
	if _drawing:
		_end_stroke()
	if not _strokes.is_empty():
		_strokes.remove_at(_strokes.size() - 1)
		_sheet.queue_redraw()


func is_blank() -> bool:
	return _strokes.is_empty() and _current.is_empty()


func stroke_count() -> int:
	return _strokes.size()


# ------------------------------------------------------------------ bounce ---

func set_club(index: int) -> void:
	club_index = maxi(index, 0)
	var speed: float = base_speed + speed_per_club * float(club_index)
	if velocity == Vector2.ZERO:
		# First launch: pick a diagonal, nudged off 45 degrees.
		var dir := Vector2(
			1.0 if randf() < 0.5 else -1.0,
			1.0 if randf() < 0.5 else -1.0
		).normalized()
		var jitter := deg_to_rad(randf_range(-angle_jitter_degrees, angle_jitter_degrees))
		velocity = dir.rotated(jitter) * speed
	else:
		velocity = velocity.normalized() * speed


func start_bouncing() -> void:
	bouncing = true


func stop_bouncing() -> void:
	bouncing = false


func _process(delta: float) -> void:
	if not bouncing:
		return

	if bounce_box == null:
		return

	position += velocity * delta

	var bounds := bounce_box.get_global_rect()
	var hit := Vector2.ZERO

	# LEFT
	if global_position.x <= bounds.position.x:
		global_position.x = bounds.position.x
		velocity.x = absf(velocity.x)
		hit = Vector2.RIGHT

	# RIGHT
	elif global_position.x + size.x >= bounds.end.x:
		global_position.x = bounds.end.x - size.x
		velocity.x = -absf(velocity.x)
		hit = Vector2.LEFT

	# TOP
	if global_position.y <= bounds.position.y:
		global_position.y = bounds.position.y
		velocity.y = absf(velocity.y)
		hit = Vector2.DOWN

	# BOTTOM
	elif global_position.y + size.y >= bounds.end.y:
		global_position.y = bounds.end.y - size.y
		velocity.y = -absf(velocity.y)
		hit = Vector2.UP

	if hit != Vector2.ZERO:
		edge_hit.emit(hit)

# ---------------------------------------------------------------- capture ---

## Returns PNG bytes of just the drawing, ready to base64 and send to the AI.
## Must be awaited:  var png: PackedByteArray = await paper.capture_png()
func capture_png(max_side: int = 512) -> PackedByteArray:
	# Wait for the renderer to finish the current frame, or we may grab a
	# texture that doesn't include the most recent stroke.
	await RenderingServer.frame_post_draw

	var img: Image = _viewport.get_texture().get_image()

	var longest: int = maxi(img.get_width(), img.get_height())
	if max_side > 0 and longest > max_side:
		var scale: float = float(max_side) / float(longest)
		img.resize(
			int(img.get_width() * scale),
			int(img.get_height() * scale),
			Image.INTERPOLATE_BILINEAR
		)

	return img.save_png_to_buffer()


## Convenience for the API call body.
func capture_base64(max_side: int = 512) -> String:
	var png: PackedByteArray = await capture_png(max_side)
	return Marshalls.raw_to_base64(png)
