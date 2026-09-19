extends Node2D

@onready var paper = $Panel/Paper
@onready var bouncer = $Bouncer
@onready var speech_bubble = $SpeechBubble
@onready var yap = $SpeechBubble/Yap
@onready var bet_button = $BetButton
@onready var submit_button = $Submit
@onready var reset_button = $Reset

# Keeps track of what the BetButton currently does
var waiting_for_bet := false

func _ready() -> void:
	bouncer.play("Jake")

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

	# Button starts as HI!
	bet_button.text = "HI!"
	bet_button.show()

	waiting_for_bet = false


func _on_bet_button_pressed() -> void:
	if waiting_for_bet == false:
		# Player pressed HI!

		speech_bubble.show()
		yap.text = "If you're really sober, draw me a _____"

		bet_button.text = "BET!"

		waiting_for_bet = true

	else:
		# Player pressed BET!
		bet_button.hide()
		reset_button.show()
		submit_button.show()
		paper.show()
		paper.start_bouncing()


func _on_submit_pressed() -> void:
	reset_button.hide()
	submit_button.hide()
	paper.stop_bouncing()

func _on_reset_pressed() -> void:
	# Reset drawing here later
	pass
