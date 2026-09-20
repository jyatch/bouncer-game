extends Node2D

## The real club scene. Ported from paper_test.gd's submit/classify logic
## (the dev harness), wired up to this scene's bouncer dialogue, hearts and
## club progression instead of a plain debug readout.

@onready var paper = $Panel/Paper
@onready var bouncer = $Bouncer
@onready var BG = $BG
@onready var speech_bubble = $SpeechBubble
@onready var yap = $SpeechBubble/Yap
@onready var bet_button = $BetButton
@onready var submit_button = $Submit
@onready var reset_button = $Reset
@onready var nametag = $Nametag
@onready var _hearts: Array[Sprite2D] = [$heart1, $heart2, $heart3]

# Keeps track of what the BetButton currently does
var waiting_for_bet := false

var _target: String = ""
var _lives: int = 3
var _club_index: int = 0
var _busy: bool = false


func _ready() -> void:
	nametag.text = "TONIGHT's Alcoholic: " + PlayerData.player_name
	bouncer.play("Jake")
	BG.play()

	paper.hide()
	speech_bubble.hide()
	submit_button.hide()
	reset_button.hide()

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

	# Button starts as HI!
	bet_button.text = "HI!"
	bet_button.show()

	waiting_for_bet = false

	_new_target()


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
		bet_button.hide()
		reset_button.show()
		submit_button.show()
		paper.clear()
		paper.show()
		paper.start_bouncing()


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
		submit_button.hide()
		reset_button.hide()
		await get_tree().create_timer(1.5).timeout

		_club_index += 1
		paper.set_club(_club_index)
		_reset_lives()
		start_round()
		return

	var guessed: String = guesses[0].label if not guesses.is_empty() else "nothing at all"
	yap.text = "\"that's a %s?? Try again.\"" % guessed
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


func _game_over() -> void:
	paper.stop_bouncing()
	submit_button.hide()
	reset_button.hide()
	yap.text = "\"get outta here, you're cut off.\""

	# TODO: swap this for the real lose/blackout scene (Transition.cover()
	# over a blur shader, plus the existing bounce code applied to a
	# shrinking sprite) once it exists -- see CLAUDE.md Next priorities.
	# For now, just send the player back to the menu so the loop ends
	# instead of dead-ending on a frozen screen.
	await get_tree().create_timer(2.5).timeout
	Transition.change_scene("res://Scenes/Menu.tscn")


func _on_reset_pressed() -> void:
	if _busy:
		return
	paper.clear()
	paper.start_bouncing()
	_show_prompt_dialogue()
