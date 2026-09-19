extends Node

## Sketch recognition via Transformers.js, running in the browser.
##
## Uses Xenova/quickdraw-mobilevit-small -- MobileViT finetuned on Google's
## Quick, Draw! dataset, ~20 MB, 300+ classes.
##
## WEB EXPORTS ONLY. On desktop this reports unavailable and you should fall
## back to the pure-GDScript QuickDraw autoload.
##
## Install: Project Settings -> Globals -> Autoload -> name it  DoodleAI
##
## Use:  await DoodleAI.wait_until_ready()
##       var guesses := await DoodleAI.classify(image)
##       # -> [{label = "cat", score = 0.81}, ...]

signal status_changed(status: String)

## "unsupported" | "loading" | "ready" | "error"
var status: String = "loading"
var last_error: String = ""

## Quick, Draw! bitmaps are WHITE ink on a BLACK background. Our paper is dark
## ink on cream, so it has to be flipped. Left as a variable because the first
## classify() call measures both and locks in whichever scores higher.
var invert_ink: bool = true
## Set false to skip the one-time both-ways test and trust invert_ink as-is.
var auto_polarity: bool = true
## Last image actually sent, as a data URL. Paste it into a browser tab to see
## exactly what the model saw -- the single most useful debugging trick here.
var last_sent: String = ""
## The prepped Image exactly as sent. Show it on screen to debug.
var last_image: Image = null
## One-line summary of the last run, for displaying in-game.
var debug_line: String = ""

var _polarity_locked: bool = false

## --- Tuning knobs. Sweep these if recognition is poor. ---
## Size of the image sent. Doodle Dash sends large crops, so start high.
var out_size: int = 224
## Fraction of the frame left empty around the drawing (0.0 - 0.3).
var margin_ratio: float = 0.08
## Force pure black / pure white. The training bitmaps are near-binary, so
## a soft grey stroke is off-distribution.
var binarize: bool = true
## Ink below this fraction of peak is dropped when binarizing.
var binarize_threshold: float = 0.35

## Unrestricted top guesses from the last run, for debugging.
var last_raw: Array = []

## How many classes the loaded model can predict. Stays 0 until the model
## finishes loading; the paper_test readout prints this so a stuck-at-0
## reading points straight at "model config isn't loading" instead of a
## preprocessing bug.
var label_count: int = 0

## Pass this to _run()/classify_among() to request scores for every label
## instead of a truncated top-N. Restricting the raw request to a small N
## silently hides any shortlisted PROMPTS label that isn't already in the
## model's global top N -- which is how a run can end up always reporting
## whatever unrelated class *is* in that top N (e.g. a constant "snowman")
## no matter what was actually drawn.
const ALL_LABELS := -1

## Test-time augmentation: classify the same drawing several ways and average.
## A wobbly mouse doodle sits near the boundary between classes, so a single
## preprocessing choice is a coin flip. Averaging across several is not.
var tta: bool = true

## The variants that get averaged. Deliberately spread across framing,
## resolution and contrast so their errors are uncorrelated.
const VARIANTS: Array = [
	{size = 224, margin = 0.08, binar = true},
	{size = 224, margin = 0.20, binar = true},
	{size = 128, margin = 0.08, binar = true},
	{size = 224, margin = 0.12, binar = false},
]

## The only things the bouncer ever demands. Curated for shapes that survive
## 28x28 and don't collide with each other -- no circle/moon/donut/coin/wheel
## pileup, nothing like "animal migration" that nobody can draw.
##
## These must match the model's label strings exactly.
const PROMPTS: PackedStringArray = [
	"airplane", "apple", "banana", "bicycle",
	"birthday cake", "butterfly", "cactus", "candle",
	"cat", "clock", "cup", "envelope",
	"eyeglasses", "fish", "flower", "guitar",
	"hammer", "hat", "house", "key",
	"ladder", "light bulb", "mushroom", "pizza",
	"sailboat", "scissors", "snowman", "star",
	"sun", "t-shirt", "tree", "umbrella",
]


## A prompt the bouncer can reasonably demand.
func random_prompt() -> String:
	return PROMPTS[randi() % PROMPTS.size()]

## Runs once in the page's global scope. Dynamic import() works from a plain
## eval, so no custom HTML shell is needed.
const BOOTSTRAP := """
window.DoodleAI = window.DoodleAI || { status: 'loading', result: null, error: null };
(async () => {
	try {
		const T = await import('https://cdn.jsdelivr.net/npm/@huggingface/transformers@3');
		T.env.allowLocalModels = false;

		const classifier = await T.pipeline(
			'image-classification',
			'Xenova/quickdraw-mobilevit-small',
			{ dtype: 'fp32' }
		);

		// Exposed so the GDScript side can print "model ready, N labels" --
		// if N comes back 0, the model config didn't load, which is a
		// different bug than a preprocessing mismatch.
		const id2label = (classifier.model && classifier.model.config &&
			classifier.model.config.id2label) || {};
		window.DoodleAI.numLabels = Object.keys(id2label).length;

		window.DoodleAI.run = async (dataUrl, topk) => {
			window.DoodleAI.status = 'busy';
			window.DoodleAI.result = null;
			try {
				const img = await T.RawImage.read(dataUrl);
				// topk is `null` for "give me the full distribution". Passing
				// a small number here silently hides any shortlisted label
				// that isn't already in the model's global top N.
				const out = await classifier(img.grayscale(), { top_k: topk });
				window.DoodleAI.result = JSON.stringify(out);
				window.DoodleAI.status = 'done';
			} catch (e) {
				window.DoodleAI.error = String(e);
				window.DoodleAI.status = 'error';
			}
		};

		window.DoodleAI.status = 'ready';
	} catch (e) {
		window.DoodleAI.error = String(e);
		window.DoodleAI.status = 'error';
	}
})();
"""


func _ready() -> void:
	if not OS.has_feature("web"):
		_set_status("unsupported")
		push_warning("DoodleAI: not a web export - fall back to the QuickDraw autoload")
		return

	JavaScriptBridge.eval(BOOTSTRAP, true)
	_watch_loading()


func _watch_loading() -> void:
	# The model is ~20 MB, so first load takes a few seconds. Start this early
	# (during the disclaimer scene) and it'll be warm by the first club.
	var waited: float = 0.0
	while waited < 120.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25

		var s = JavaScriptBridge.eval("window.DoodleAI ? window.DoodleAI.status : 'loading'", true)
		if s == "ready":
			label_count = int(JavaScriptBridge.eval("window.DoodleAI.numLabels || 0", true))
			print("DoodleAI: model ready, %d labels" % label_count)
			_set_status("ready")
			return
		if s == "error":
			last_error = str(JavaScriptBridge.eval("window.DoodleAI.error || ''", true))
			push_error("DoodleAI: %s" % last_error)
			_set_status("error")
			return

	last_error = "timed out loading the model"
	_set_status("error")


func _set_status(s: String) -> void:
	status = s
	status_changed.emit(s)


func is_ready() -> bool:
	return status == "ready"


## Await this before the first classify call.
func wait_until_ready() -> bool:
	while status == "loading":
		await status_changed
	return status == "ready"


## Returns [{label = "cat", score = 0.81}, ...], best first. Empty on failure.
func classify(img: Image, top_k: int = 3) -> Array:
	if status != "ready":
		return []

	# One-time calibration: run it both ways and keep the more confident one.
	if auto_polarity and not _polarity_locked:
		var a: Array = await _run(_prep(img, true), top_k)
		var b: Array = await _run(_prep(img, false), top_k)
		var sa: float = a[0].score if not a.is_empty() else 0.0
		var sb: float = b[0].score if not b.is_empty() else 0.0
		invert_ink = sa >= sb
		_polarity_locked = true
		var la: String = a[0].label if not a.is_empty() else "<nothing>"
		var lb: String = b[0].label if not b.is_empty() else "<nothing>"
		debug_line = "inverted: %s %.2f  |  normal: %s %.2f  ->  %s" % [
			la, sa, lb, sb, "inverted" if invert_ink else "normal"]
		print("DoodleAI ", debug_line)
		return a if invert_ink else b

	return await _run(_prep(img, invert_ink), top_k)


## Rebuild the drawing the way the training bitmaps look: the doodle cropped
## to its ink, scaled to fill the frame, centred, and pushed to FULL contrast.
##
## Contrast matters more than it sounds. Inverting cream paper and navy ink
## gives a washed-out, colour-tinted image; Quick, Draw! bitmaps are
## essentially pure black and pure white.
func _prep(src: Image, invert: bool, p_size: int = -1, p_margin: float = -1.0,
		p_binar: int = -1) -> Image:
	var out_size: int = p_size if p_size > 0 else self.out_size
	var margin_ratio: float = p_margin if p_margin >= 0.0 else self.margin_ratio
	var binarize: bool = (p_binar == 1) if p_binar >= 0 else self.binarize
	var work: Image = src.duplicate()
	work.convert(Image.FORMAT_RGBA8)
	var w: int = work.get_width()
	var h: int = work.get_height()

	# Find the ink box on a small copy -- scanning the full sheet is slow.
	const PROBE := 128
	var probe: Image = work.duplicate()
	probe.resize(PROBE, PROBE, Image.INTERPOLATE_BILINEAR)
	var pd: PackedByteArray = probe.get_data()

	var minx: int = PROBE
	var miny: int = PROBE
	var maxx: int = -1
	var maxy: int = -1
	for y in PROBE:
		for x in PROBE:
			var o: int = (y * PROBE + x) * 4
			var lum: float = (pd[o] * 0.299 + pd[o + 1] * 0.587 + pd[o + 2] * 0.114) / 255.0
			if 1.0 - lum > 0.15:
				minx = mini(minx, x)
				maxx = maxi(maxx, x)
				miny = mini(miny, y)
				maxy = maxi(maxy, y)

	var canvas: Image = Image.create_empty(out_size, out_size, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.WHITE)

	if maxx < 0:
		debug_line = "NO INK FOUND"
		push_warning("DoodleAI: the capture looks blank")
	else:
		debug_line = "ink %dx%d" % [maxx - minx + 1, maxy - miny + 1]

		var fx: float = float(w) / float(PROBE)
		var fy: float = float(h) / float(PROBE)
		var bx: int = clampi(int(minx * fx) - 2, 0, w - 1)
		var by: int = clampi(int(miny * fy) - 2, 0, h - 1)
		var bw: int = clampi(int((maxx - minx + 1) * fx) + 4, 1, w - bx)
		var bh: int = clampi(int((maxy - miny + 1) * fy) + 4, 1, h - by)

		var cropped: Image = Image.create_empty(bw, bh, false, Image.FORMAT_RGBA8)
		cropped.blit_rect(work, Rect2i(bx, by, bw, bh), Vector2i.ZERO)

		var inner: int = int(out_size * (1.0 - margin_ratio * 2.0))
		var scale: float = float(inner) / float(maxi(bw, bh))
		var tw: int = maxi(1, int(round(bw * scale)))
		var th: int = maxi(1, int(round(bh * scale)))
		cropped.resize(tw, th, Image.INTERPOLATE_BILINEAR)

		canvas.blit_rect(cropped, Rect2i(0, 0, tw, th),
			Vector2i((out_size - tw) / 2, (out_size - th) / 2))

	# --- Convert to a clean single-channel ink map, then stretch to full range.
	var d: PackedByteArray = canvas.get_data()
	var n: int = out_size * out_size

	var ink := PackedFloat32Array()
	ink.resize(n)
	var lo: float = 1.0
	var hi: float = 0.0
	for i in n:
		var o: int = i * 4
		var lum: float = (d[o] * 0.299 + d[o + 1] * 0.587 + d[o + 2] * 0.114) / 255.0
		var v: float = 1.0 - lum
		ink[i] = v
		lo = minf(lo, v)
		hi = maxf(hi, v)

	var span: float = maxf(hi - lo, 0.001)
	for i in n:
		var v: float = (ink[i] - lo) / span
		if binarize:
			v = 1.0 if v >= binarize_threshold else 0.0
		# invert = white ink on black; otherwise black ink on white.
		var out_v: float = v if invert else 1.0 - v
		var b: int = clampi(int(out_v * 255.0), 0, 255)
		var o: int = i * 4
		d[o] = b
		d[o + 1] = b
		d[o + 2] = b
		d[o + 3] = 255

	return Image.create_from_data(out_size, out_size, false, Image.FORMAT_RGBA8, d)


## top_k <= 0 (see ALL_LABELS) asks the model for its full label distribution
## instead of a truncated top-N -- passed through to JS as the literal `null`,
## since transformers.js only returns every label when top_k is null.
func _run(prepped: Image, top_k: int) -> Array:
	last_image = prepped
	var b64 := Marshalls.raw_to_base64(prepped.save_png_to_buffer())
	last_sent = "data:image/png;base64," + b64

	var topk_literal: String = "null" if top_k <= 0 else str(top_k)
	JavaScriptBridge.eval(
		"window.DoodleAI.run('data:image/png;base64,%s', %s);" % [b64, topk_literal], true)

	# Poll rather than marshalling a callback back across the bridge.
	var waited: float = 0.0
	while waited < 15.0:
		await get_tree().process_frame
		waited += get_process_delta_time()

		var s = JavaScriptBridge.eval("window.DoodleAI.status", true)
		if s == "done":
			break
		if s == "error":
			last_error = str(JavaScriptBridge.eval("window.DoodleAI.error || ''", true))
			push_error("DoodleAI: %s" % last_error)
			return []

	var raw = JavaScriptBridge.eval("window.DoodleAI.result", true)
	if typeof(raw) != TYPE_STRING:
		return []

	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_ARRAY:
		return []

	var out: Array = []
	for item in parsed:
		out.append({label = str(item.get("label", "")), score = float(item.get("score", 0.0))})
	return out


## Opens the last image sent to the model in a new browser tab.
func debug_show_last() -> void:
	if last_sent.is_empty():
		print("DoodleAI: nothing sent yet")
		return
	JavaScriptBridge.eval("window.open().document.write('<img style=\"image-rendering:pixelated;width:512px\" src=\"%s\">')" % last_sent, true)


## Scores restricted to `candidates` (defaults to PROMPTS), averaged across
## preprocessing variants, renormalised and ranked. Use this, not classify().
##
## Two compounding wins over raw classification:
##   1. Ranking against 32 shortlisted doodles instead of all 345 classes.
##   2. Averaging several preprocessings, so one unlucky crop can't decide it.
func classify_among(img: Image, candidates: PackedStringArray = PROMPTS,
		top_k: int = 3) -> Array:
	if status != "ready":
		return []

	# One-time polarity calibration, on a single variant.
	if auto_polarity and not _polarity_locked:
		var a: Array = await _run(_prep(img, true, 224, 0.08, 1), 10)
		var b: Array = await _run(_prep(img, false, 224, 0.08, 1), 10)
		var sa: float = a[0].score if not a.is_empty() else 0.0
		var sb: float = b[0].score if not b.is_empty() else 0.0
		invert_ink = sa >= sb
		_polarity_locked = true
		print("DoodleAI polarity -> %s" % ["inverted" if invert_ink else "normal"])

	var variants: Array = VARIANTS if tta else [
		{size = out_size, margin = margin_ratio, binar = binarize}]

	var totals: Dictionary = {}
	var runs: int = 0

	for v in variants:
		var prepped: Image = _prep(img, invert_ink, v.size, v.margin, 1 if v.binar else 0)
		# Must request the FULL distribution here, not a truncated top-N --
		# otherwise a shortlisted label (e.g. "envelope") that isn't already
		# in the model's global top N never gets a score at all, and whatever
		# unrelated class *is* in that top N wins by default every time.
		var res: Array = await _run(prepped, ALL_LABELS)
		if res.is_empty():
			continue
		runs += 1
		for g in res:
			totals[g.label] = float(totals.get(g.label, 0.0)) + g.score

	if runs == 0:
		return []

	# Averaged, unrestricted view -- this is what to look at when debugging.
	var raw: Array = []
	for label in totals:
		raw.append({label = label, score = float(totals[label]) / float(runs)})
	raw.sort_custom(func(x, y): return x.score > y.score)
	last_raw = raw.slice(0, mini(5, raw.size()))
	debug_line = "%d variants" % runs

	var kept: Array = []
	var total: float = 0.0
	for g in raw:
		if candidates.has(g.label):
			kept.append({label = g.label, score = g.score})
			total += g.score

	if kept.is_empty():
		return []

	# Renormalise so scores read as confidence within the shortlist.
	if total > 0.0:
		for g in kept:
			g.score = g.score / total

	kept.sort_custom(func(x, y): return x.score > y.score)
	return kept.slice(0, mini(top_k, kept.size()))


## Where `target` placed among the shortlist. 0 = the model's first choice,
## -1 = not found. Accepting 0, 1 or 2 makes for a forgiving, funnier game.
func rank_of(img: Image, target: String,
		candidates: PackedStringArray = PROMPTS) -> int:
	var ranked: Array = await classify_among(img, candidates, candidates.size())
	for i in ranked.size():
		if ranked[i].label == target:
			return i
	return -1


## True if `target` is among the model's top_k guesses.
func matches(img: Image, target: String, top_k: int = 3) -> bool:
	for g in await classify(img, top_k):
		if g.label == target:
			return true
	return false
