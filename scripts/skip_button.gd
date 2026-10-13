extends Node2D

# ──────────────────────────────────────────────────────────────────
#  SkipButton (draft)
#
#  Step one's standalone "keep the special I already have" choice. It is a
#  button, not a card: it sits at its own marker in the draft scene
#  (Camera2D/hand/skipmarker), it never takes one of the hand's card slots, and
#  the special-move offer stays the full hand of real special cards.
#
#  It wears the death pop-up presentation: the same window art and the same
#  title/body label layout the fight UI uses for "player1.exe has stopped
#  working" (fight_ui_new2.tscn / DeathPopUp).
#
#  Its public surface matches upgrade_card.gd closely enough that the hand's
#  selector treats it as just another focus target: currently_highlighted,
#  is_display_only, selection_icon, _handle_highlight(), _play_unhover_tween().
#  Confirming it is CardHand's business (_handle_skip_pressed), since the
#  confirm input and the step sequencing both live there.

@onready var selection_icon : AnimatedSprite2D = $Control/selection_icon
@onready var card_control : Control = $Control

# ── Juice settings ──
# Same values as upgrade_card.gd on purpose: the selector has to feel the same
# on the button as it does on the cards it can also land on.
const IDLE_BOB_AMOUNT := 6.0
const IDLE_BOB_DURATION := 1.4
const HOVER_MULTIPLIER := 1.15
const HOVER_OVERSHOOT := 1.08
const HOVER_DURATION := 0.15

var currently_highlighted : bool = false
## Read by the hand's highlight sweep on every focus target. Never true here.
var is_display_only : bool = false

var _base_scale : Vector2
var _hover_tween : Tween


func _ready() -> void:
	selection_icon.hide()
	_base_scale = card_control.scale
	_start_idle_bob()


func _handle_highlight() -> void:
	# Same contract as UpgradeCard._handle_highlight(): whoever takes the focus
	# clears it from every other focus target, then pops its own selector and
	# hovers. Cards and this button find each other through
	# has_method("_handle_highlight"), so a mixed hand highlights correctly in
	# both directions.
	if currently_highlighted:
		for target in self.get_parent().get_children():
			if target == self or not target.has_method("_handle_highlight"):
				continue
			if target.is_display_only:
				continue
			target.currently_highlighted = false
			target.selection_icon.hide()
			target._play_unhover_tween()
		_play_selection_icon_pop()
		_play_hover_tween()
	else:
		selection_icon.hide()
		_play_unhover_tween()


func _start_idle_bob() -> void:
	# Gentle up/down float so the button doesn't sit dead still. Runs forever,
	# independent of the hover/selection scale tweens below, and bobs the inner
	# Control so the node's own position stays on its marker.
	var idle_tween := create_tween().set_loops()
	idle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	idle_tween.tween_property(card_control, "position:y", card_control.position.y - IDLE_BOB_AMOUNT, IDLE_BOB_DURATION)
	idle_tween.tween_property(card_control, "position:y", card_control.position.y, IDLE_BOB_DURATION)


func _play_hover_tween() -> void:
	# Overshoots slightly past the hover size then settles, for a springy pop
	# instead of a flat linear scale-up.
	if _hover_tween:
		_hover_tween.kill()
	var overshoot := _base_scale * HOVER_MULTIPLIER * HOVER_OVERSHOOT
	var target := _base_scale * HOVER_MULTIPLIER
	_hover_tween = create_tween()
	_hover_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(card_control, "scale", overshoot, HOVER_DURATION)
	_hover_tween.tween_property(card_control, "scale", target, HOVER_DURATION * 0.6)


func _play_unhover_tween() -> void:
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_hover_tween.tween_property(card_control, "scale", _base_scale, HOVER_DURATION)


func _play_selection_icon_pop() -> void:
	# Elastic pop-in instead of a flat show(), then the existing blink anim,
	# matching the cards' selector.
	selection_icon.scale = Vector2.ZERO
	selection_icon.show()
	selection_icon.play("selector_blink")
	var icon_tween := create_tween()
	icon_tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	icon_tween.tween_property(selection_icon, "scale", Vector2(4, 4), 0.5)
