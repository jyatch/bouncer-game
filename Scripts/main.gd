extends Node2D

@onready var round_timer = $RoundTimer
@onready var timer_label = $TimerLabel

var time_left: int = 15


func _ready() -> void:
	$Bouncer.play("Jake")
	$SpeechBubble.hide()

	timer_label.text = str(time_left)
	round_timer.timeout.connect(_on_round_timer_timeout)


func _on_round_timer_timeout() -> void:
	time_left -= 1
	timer_label.text = str(time_left)

	if time_left <= 0:
		round_timer.stop()
		timer_label.text = "0"
