extends Node2D

## The real club scene. Ported from paper_test.gd's submit/classify logic
## (the dev harness), wired up to this scene's bouncer dialogue, hearts and
## club progression instead of a plain debug readout.

@onready var paper = $Panel/Paper
@onready var bouncer = $Bouncer
@onready var BG = $BG
@onready var speech_bubble = $SpeechBubble
@onready var yap = $SpeechBubble/Yap
@onready var me_bubble = $MeBubble
@onready var bet_button = $MeBubble/BetButton
@onready var submit_button = $Submit
@onready var reset_button = $Reset
@onready var nametag = $Nametag
@onready var _hearts: Array[Sprite2D] = [$heart1, $heart2, $heart3]
@onready var round_timer = $RoundTimer
@onready var timer_label = $TimerLabel
@onready var game_over_dim = $GameOverLayer/Dim
@onready var wasted_image = $GameOverLayer/WastedImage
@onready var wasted_sfx = $GameOverLayer/WastedSfx
@onready var submit_label = $Submit/Label
@onready var reset_label = $Reset/Label

# Keeps track of what the BetButton currently does
var waiting_for_bet := false

var _target: String = ""
var _lives: int = 3
var _club_index: int = 0
var _busy: bool = false

## Seconds given per attempt. Runs out -> counts as a failed submit, same as
## a wrong guess: lose a life via _lose_life(), then a fresh 15s if any are
## left.
const ROUND_SECONDS := 15
var time_left: int = ROUND_SECONDS
var current_level = 1


func _ready() -> void:
	submit_button.button_down.connect(_on_submit_button_down)
	submit_button.button_up.connect(_on_submit_button_up)
	reset_button.button_down.connect(_on_reset_button_down)
	reset_button.button_up.connect(_on_reset_button_up)
	nametag.text = "TONIGHT's Alcoholic: " + PlayerData.player_name
	bouncer.play("Jake")
	BG.play()

	paper.hide()
	speech_bubble.hide()
	me_bubble.hide()
	submit_button.hide()
	reset_button.hide()
	timer_label.hide()
	round_timer.timeout.connect(_on_round_timer_timeout)

	start_round()


func start_round() -> void:
	# Beginning of EVERY round
	paper.hide()
	speech_bubble.hide()
	submit_button.hide()
	reset_button.hide()
	submit_button.disabled = false
	reset_button.disabled = false
	_busy = false

	round_timer.stop()
	timer_label.hide()

	# Button starts as HI!
	bet_button.text = "HI!"
	me_bubble.show()

	waiting_for_bet = false

	_new_target()


## Gives the player a fresh ROUND_SECONDS-second window. Called both when a
## round's drawing first appears and again after a life is lost mid-round
## (wrong guess or a timeout), so every attempt gets the same full window.
func _start_timer() -> void:
	time_left = ROUND_SECONDS
	timer_label.text = str(time_left)
	timer_label.show()
	round_timer.paused = false
	round_timer.start()


## Picks the word the bouncer demands. Mirrors paper_test.gd's _new_target():
## prefer QuickDraw (verified, on-device preprocessing) when it's loaded,
## otherwise fall back to DoodleAI's curated PROMPTS shortlist.
func _new_target() -> void:
	if QuickDraw.loaded:
		_target = QuickDraw.random_prompt()
	else:
		_target = DoodleAI.random_prompt()


## Puts the current bouncer's ask into the speech bubble, with the actual
## target word swapped in for the old literal "_____" placeholder.
func _show_prompt_dialogue() -> void:
	match bouncer.animation:
		"Jake":
			yap.text = "If you're really sober, draw me a %s UwU." % _target
		"Aakash":
			yap.text = "You look madddd cooked boi. Draw me %s if you are not." % _target
		"Cindy":
			yap.text = "You look drunker than League teammates. Draw me %s dude." % _target
		"Patrick":
			yap.text = "Senpai~ you look a little drunk... prove me wrong and draw %s! >w<" % _target
		_:
			yap.text = "Draw me a %s." % _target


func _reset_lives() -> void:
	_lives = 3
	for h in _hearts:
		h.show()


func _on_bet_button_pressed() -> void:
	if waiting_for_bet == false:
		# Player pressed HI!
		speech_bubble.show()
		_show_prompt_dialogue()

		# Change HI! into BET!
		bet_button.text = "BET!"
		waiting_for_bet = true
	else:
		# Player pressed BET!
		me_bubble.hide()
		reset_button.show()
		submit_button.show()
		paper.clear()
		paper.show()
		paper.start_bouncing()
		_start_timer()

func _on_submit_button_down() -> void:
	submit_label.position.y += 5


func _on_submit_button_up() -> void:
	submit_label.position.y -= 5

func _on_reset_button_down() -> void:
	reset_label.position.y += 5


func _on_reset_button_up() -> void:
	reset_label.position.y -= 5


## THIS is where the classifier attaches. Ported from paper_test.gd's
## _submit(), with the debug readout swapped for bouncer dialogue and a
## life/club system layered on top.
func _on_submit_pressed() -> void:
	if _busy:
		return
	if paper.is_blank():
		yap.text = "\"...you didn't draw anything.\""
		return

	_busy = true
	submit_button.disabled = true
	reset_button.disabled = true
	yap.text = "\"...hang on, let me look.\""

	# Classifying can take a couple of seconds (DoodleAI runs several
	# preprocessing variants). Pause rather than stop, so a slow model
	# response can't both time out AND lose a life for the same attempt --
	# the clock resumes with whatever time was left once we have an answer.
	round_timer.paused = true

	var img: Image = await paper.capture_image()
	var guesses: Array = []

	if QuickDraw.loaded:
		# Only 15 classes, and the preprocessing here provably matches what
		# the model was trained on -- so its confidence means something.
		guesses = QuickDraw.classify(img, 3)
	elif DoodleAI.is_ready():
		guesses = await DoodleAI.classify_among(img, DoodleAI.PROMPTS, 3)
	else:
		yap.text = "\"...the bouncer's brain isn't loaded yet, hang on.\""
		round_timer.paused = false
		_busy = false
		submit_button.disabled = false
		reset_button.disabled = false
		return

	# Accept a top-3 match, not just the top guess -- a drawing made while
	# the paper was fleeing will legitimately rank second. See CLAUDE.md.
	var placed: int = -1
	for i in guesses.size():
		if guesses[i].label == _target:
			placed = i
			break

	if placed != -1:
		yap.text = "\"...alright, that IS a %s. Get in.\"" % _target
		paper.stop_bouncing()
		round_timer.paused = false
		round_timer.stop()
		timer_label.hide()
		submit_button.hide()
		reset_button.hide()
		await get_tree().create_timer(1.5).timeout

		_club_index += 1
		paper.set_club(_club_index)
		_reset_lives()
		
		current_level += 1
		_change_bouncer()
		
		start_round()
		return

	var guessed: String = guesses[0].label if not guesses.is_empty() else "nothing at all"
	yap.text = "\"that's a %s?? Try Again! Draw me a %s!\"" % [guessed, _target]
	_lose_life()

	_busy = false
	submit_button.disabled = false
	reset_button.disabled = false


func _lose_life() -> void:
	_lives -= 1
	var lost_index: int = 3 - _lives - 1  # 0, then 1, then 2
	if lost_index >= 0 and lost_index < _hearts.size():
		_hearts[lost_index].hide()

	if _lives <= 0:
		_game_over()
	else:
		# Any lives left -> same round, fresh clock for the next attempt.
		_start_timer()


## The clock ran out on this attempt -- treated exactly like a wrong guess:
## lose a life, and if any are left, _lose_life() already restarts the timer.
func _on_round_timer_timeout() -> void:
	time_left -= 1
	timer_label.text = str(time_left)

	if time_left <= 0:
		round_timer.stop()
		timer_label.text = "0"
		yap.text = "\"times up! Try Again! Draw me a %s!\"" % _target
		_lose_life()


func _game_over() -> void:
	paper.stop_bouncing()
	round_timer.paused = false
	round_timer.stop()
	timer_label.hide()
	submit_button.hide()
	reset_button.hide()
	me_bubble.hide()
	yap.text = "\"get outta here, you're cut off.\""

	# Ambience has been looping since HowToPlay -- cut it out (quick fade, not
	# an abrupt stop) right as the wasted screen takes over.
	Music.fade_out(0.3)

	# Low-opacity black over the whole game, "WASTED" banner centered on top --
	# faded/popped in rather than just appearing, same idea as the eventual
	# real lose/blackout scene (blur shader + shrinking bounce sprite) this is
	# standing in for. Swap this block out once that scene exists.
	game_over_dim.modulate.a = 0.0
	game_over_dim.show()
	wasted_image.scale = Vector2(0.6, 0.6)
	wasted_image.pivot_offset = wasted_image.size / 2.0
	wasted_image.show()
	wasted_sfx.play()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(game_over_dim, "modulate:a", 1.0, 0.4)
	tween.tween_property(wasted_image, "scale", Vector2.ONE, 0.4)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished

	# Hold on the wasted screen for as long as the sting actually plays,
	# instead of guessing a fixed delay. If the stream is short/empty for
	# some reason, `finished` never fires -- fall back to the old fixed
	# hold so the scene can't get stuck here forever.
	if wasted_sfx.playing:
		await wasted_sfx.finished
	else:
		await get_tree().create_timer(2.0).timeout

	# For now, just send the player back to the menu so the loop ends
	# instead of dead-ending on a frozen screen.
	Transition.change_scene("res://Scenes/Menu.tscn")

func _on_reset_pressed() -> void:
	if _busy:
		return
	paper.clear()
	paper.start_bouncing()
	_show_prompt_dialogue()

func _change_bouncer():
	match current_level:
		1:
			bouncer.play("Jake")
		2:
			bouncer.play("Aakash")
		3:
			bouncer.play("Cindy")
		4:
			bouncer.play("Patrick")
		_:
			bouncer.play("Jake")
