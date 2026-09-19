extends Node

## Quick, Draw! doodle classifier, running entirely in GDScript.
##
## Install: Project Settings -> Globals -> Autoload -> add this file,
##          name it exactly  QuickDraw
##          Put model.json and model.bin in res://model/
##
## Use:  var guesses := QuickDraw.classify(image)
##       # -> [{label = "cat", score = 0.81}, {label = "fish", ...}, ...]

signal model_loaded(ok: bool)

## Working resolution for finding the ink before the final downscale.
const SRC := 128

var labels: PackedStringArray = []
var loaded: bool = false

var _w: Array[PackedFloat32Array] = []
var _b: Array[PackedFloat32Array] = []
var _shapes: Array = []
var _grid: int = 28
var _fit: float = 24.0
var _ink_threshold: float = 0.15


func _ready() -> void:
	pass #load_model()


func load_model(json_path: String = "res://model/model.json",
		bin_path: String = "res://model/model.bin") -> bool:
	loaded = false
	_w.clear()
	_b.clear()

	var jf := FileAccess.open(json_path, FileAccess.READ)
	if jf == null:
		push_error("QuickDraw: can't open %s - did you run train_quickdraw.py?" % json_path)
		model_loaded.emit(false)
		return false

	var meta = JSON.parse_string(jf.get_as_text())
	if typeof(meta) != TYPE_DICTIONARY:
		push_error("QuickDraw: %s is not valid JSON" % json_path)
		model_loaded.emit(false)
		return false

	labels = PackedStringArray(meta.get("labels", []))
	_shapes = meta.get("shapes", [])
	_grid = int(meta.get("grid", 28))
	_fit = float(meta.get("fit", 24))
	_ink_threshold = float(meta.get("ink_threshold", 0.15))

	var bf := FileAccess.open(bin_path, FileAccess.READ)
	if bf == null:
		push_error("QuickDraw: can't open %s" % bin_path)
		model_loaded.emit(false)
		return false

	var floats: PackedFloat32Array = bf.get_buffer(bf.get_length()).to_float32_array()

	# Blob layout, per layer: weights [out][in] row-major, then biases [out].
	var cursor: int = 0
	for s in _shapes:
		var n_in: int = int(s[0])
		var n_out: int = int(s[1])
		_w.append(floats.slice(cursor, cursor + n_in * n_out))
		cursor += n_in * n_out
		_b.append(floats.slice(cursor, cursor + n_out))
		cursor += n_out

	if cursor != floats.size():
		push_warning("QuickDraw: model.bin size doesn't match model.json shapes")

	loaded = true
	model_loaded.emit(true)
	return true


# ----------------------------------------------------------------- public ---

## Returns up to top_k guesses, best first:
##   [{label = "cat", score = 0.81}, ...]
## Empty array means a blank page or no model.
func classify(img: Image, top_k: int = 3) -> Array:
	if not loaded:
		push_error("QuickDraw: no model loaded")
		return []

	var x := _to_grid(img)
	if x.is_empty():
		return []

	for i in _w.size():
		var n_in: int = int(_shapes[i][0])
		var n_out: int = int(_shapes[i][1])
		x = _dense(x, _w[i], _b[i], n_in, n_out, i < _w.size() - 1)

	return _top_k(_softmax(x), top_k)


func classify_png(png: PackedByteArray, top_k: int = 3) -> Array:
	var img := Image.new()
	if img.load_png_from_buffer(png) != OK:
		push_error("QuickDraw: bad PNG")
		return []
	return classify(img, top_k)


## True if `target` is among the model's top_k guesses.
func matches(img: Image, target: String, top_k: int = 3) -> bool:
	for g in classify(img, top_k):
		if g.label == target:
			return true
	return false


## Pick a random prompt the model actually knows how to recognise.
func random_prompt() -> String:
	if labels.is_empty():
		return ""
	return labels[randi() % labels.size()]


# ---------------------------------------------------------- preprocessing ---

## Crop to ink, scale longest side to _fit, center in _grid x _grid, rescale
## peak brightness to 1.0.
##
## THIS MUST MATCH normalize() in train_quickdraw.py EXACTLY. If you change
## one, change the other, or the model sees input it never trained on.
func _to_grid(src: Image) -> PackedFloat32Array:
	var img: Image = src.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(SRC, SRC, Image.INTERPOLATE_BILINEAR)

	# get_data() is far faster than looping get_pixel().
	var data: PackedByteArray = img.get_data()

	var g := PackedFloat32Array()
	g.resize(SRC * SRC)

	var minx: int = SRC
	var miny: int = SRC
	var maxx: int = -1
	var maxy: int = -1

	for y in SRC:
		for x in SRC:
			var o: int = (y * SRC + x) * 4
			# Paper is dark ink on light stock, so ink = inverted luminance.
			var lum: float = (data[o] * 0.299 + data[o + 1] * 0.587 + data[o + 2] * 0.114) / 255.0
			var ink: float = 1.0 - lum
			g[y * SRC + x] = ink
			if ink > _ink_threshold:
				minx = mini(minx, x)
				maxx = maxi(maxx, x)
				miny = mini(miny, y)
				maxy = maxi(maxy, y)

	if maxx < 0:
		return PackedFloat32Array()  # blank page

	var cw: int = maxx - minx + 1
	var ch: int = maxy - miny + 1
	var scale: float = _fit / float(maxi(cw, ch))
	var ow: int = maxi(1, int(round(cw * scale)))
	var oh: int = maxi(1, int(round(ch * scale)))

	var canvas := PackedFloat32Array()
	canvas.resize(_grid * _grid)

	var ox0: int = (_grid - ow) / 2
	var oy0: int = (_grid - oh) / 2
	var peak: float = 0.0

	# Box-filter downscale of the cropped region.
	for oy in oh:
		var sy0: int = int(oy * ch / float(oh))
		var sy1: int = maxi(sy0 + 1, int((oy + 1) * ch / float(oh)))
		for ox in ow:
			var sx0: int = int(ox * cw / float(ow))
			var sx1: int = maxi(sx0 + 1, int((ox + 1) * cw / float(ow)))

			var total: float = 0.0
			var count: int = 0
			for sy in range(sy0, sy1):
				var row: int = (miny + sy) * SRC + minx
				for sx in range(sx0, sx1):
					total += g[row + sx]
					count += 1

			var v: float = total / float(count)
			canvas[(oy0 + oy) * _grid + (ox0 + ox)] = v
			peak = maxf(peak, v)

	# Rescale so thin strokes that faded during downscaling come back.
	if peak > 0.0:
		for i in canvas.size():
			canvas[i] /= peak

	return canvas


# --------------------------------------------------------------- inference ---

func _dense(x: PackedFloat32Array, w: PackedFloat32Array, b: PackedFloat32Array,
		n_in: int, n_out: int, relu: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n_out)
	for o in n_out:
		var acc: float = b[o]
		var base: int = o * n_in
		for i in n_in:
			acc += w[base + i] * x[i]
		out[o] = maxf(acc, 0.0) if relu else acc
	return out


func _softmax(logits: PackedFloat32Array) -> PackedFloat32Array:
	var hi: float = -INF
	for v in logits:
		hi = maxf(hi, v)

	var sum: float = 0.0
	var out := PackedFloat32Array()
	out.resize(logits.size())
	for i in logits.size():
		var e: float = exp(logits[i] - hi)
		out[i] = e
		sum += e

	for i in out.size():
		out[i] /= sum
	return out


func _top_k(probs: PackedFloat32Array, k: int) -> Array:
	var ranked: Array = []
	for i in probs.size():
		ranked.append({label = labels[i], score = probs[i]})
	ranked.sort_custom(func(a, b): return a.score > b.score)
	return ranked.slice(0, mini(k, ranked.size()))
