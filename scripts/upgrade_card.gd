extends Node2D

# Emitted once the flip-to-face-up reveal has actually happened: either
# the flip animation finished, or the face was applied directly because no
# flip animation was available. The draft screen awaits this so owned
# cards can be revealed strictly one at a time.
signal card_flip_finished

@onready var selection_icon = $Control/selection_icon
@onready var anim_player = $AnimationPlayer
@onready var card_control = $Control
@onready var card_back : Sprite2D = $Control/card_back
@onready var card_front : Sprite2D = $Control/card_front
@onready var card_icon : TextureRect = $Control/card_front/card_icon
@onready var title_label : Label = $Control/card_front/Title
@onready var description_label : Label = $Control/card_front/Description
@onready var parent_node = self.get_parent()
@onready var card_shader = preload("res://scripts/card_tear.gdshader")

const FLIP_ANIM := "card_flip"
# card_front's z_index while face-down (behind card_back) and face-up
# (tied with card_back, so plain sibling order draws it on top).
const FACE_DOWN_FRONT_Z := -1
const FACE_UP_FRONT_Z := 0
# The card's layer stack is: card_icon (the art) under card_front (the
# frame, which has a transparent window over the art) under card_back (the
# back, which hides both). card_icon reaches that by sitting at z_index -2
# *relative* to card_front, and card_front is at -1 while face-down, so the
# art layer lands 2 or 3 below whatever base z_index the card root is given,
# and the card's whole stack spans four z values (base -3 .. base).
#
# Two things follow for anything that spawns these cards:
#  1. Ordering two overlapping cards by sibling order alone is not enough,
#     because their layers do not share one z. A card that should be on top
#     needs its base raised by more than that four value spread, otherwise
#     the lower card's border draws across the upper card's art. card_hand
#     hands out bands card_z_step apart for exactly this.
#  2. Every layer of the card is at or below its base, and Godot draws every
#     negative z_index item before every z_index 0 item no matter where it
#     sits in the tree. So the base has to clear any opaque, full screen
#     sibling sitting at z_index 0 (the draft screen keeps its backdrop at
#     z_index -10 and starts cards at a positive band for this reason).
#     A card left at the default z_index 0 in front of a z_index 0 backdrop
#     shows its frame and back but no art.

var currently_highlighted : bool
var is_flipped : bool
## True for purely-display copies (the owned-cards stack). Those stay out
## of the hand's highlight/selection sweep entirely.
var is_display_only : bool = false
#var assoc_tres_file

# ── Debug ──
## Prints what flip_card() actually did (called, player valid, animation
## playing). This is what distinguishes "the flip never fired" from "the
## flip fired but was never seen", which look identical on screen.
@export var debug_flip: bool = false

# ── Juice settings ──
const IDLE_BOB_AMOUNT := 6.0
const IDLE_BOB_DURATION := 1.4
const HOVER_MULTIPLIER := 1.15
const HOVER_OVERSHOOT := 1.08
const HOVER_DURATION := 0.15

var _base_scale : Vector2
var _hover_tween : Tween

# NOTE cleaned up some of the remaining unused functions here

func _ready() -> void:
	selection_icon.hide()
	self.material = null
	_base_scale = card_control.scale
	# Establish the unflipped state here at runtime. The scene's saved
	# z_index and the (editor-only, never played) RESET animation are not
	# enough on their own to guarantee what a fresh card actually shows.
	_set_face_down()
	anim_player.animation_finished.connect(_on_anim_finished)
	_start_idle_bob()


func _set_face_down() -> void:
	card_back.visible = true
	card_front.visible = true
	card_front.z_index = FACE_DOWN_FRONT_Z
	is_flipped = false


func _apply_face_up() -> void:
	card_front.visible = true
	card_front.z_index = FACE_UP_FRONT_Z
	card_back.visible = false


func _on_anim_finished(anim_name: StringName) -> void:
	if anim_name == FLIP_ANIM:
		card_flip_finished.emit()
	

func _start_idle_bob() -> void:
	# Gentle up/down float so cards don't sit dead still. Runs forever,
	# independent of the hover/selection scale tweens below.
	var idle_tween := create_tween().set_loops()
	idle_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	idle_tween.tween_property(card_control, "position:y", card_control.position.y - IDLE_BOB_AMOUNT, IDLE_BOB_DURATION)
	idle_tween.tween_property(card_control, "position:y", card_control.position.y, IDLE_BOB_DURATION)


func _handle_highlight() -> void:
	if  currently_highlighted:
		for card in self.get_parent().get_children():
			# hand now also parents cardspawnarea and cardspawner alongside
			# the actual card instances, so a plain child check isn't
			# enough, skip anything that isn't a card
			if card == self or not card.has_method("_handle_highlight"):
				continue
			# Display-only copies (the owned-cards stack) are not part of
			# the pickable hand and must not be touched by this sweep.
			if card.is_display_only:
				continue
			card.currently_highlighted = false
			card.selection_icon.hide()
			card._play_unhover_tween()
		_play_selection_icon_pop()
		_play_hover_tween()
		flip_card()
	else:
		selection_icon.hide()
		_play_unhover_tween()

func flip_card() -> void:
	if is_flipped:
		if debug_flip:
			print("[CARD FLIP] %s skipped: already flipped" % name)
		return
	is_flipped = true
	if anim_player and anim_player.has_animation(FLIP_ANIM):
		anim_player.play(FLIP_ANIM)
		if debug_flip:
			print("[CARD FLIP] %s display_only=%s player=%s playing=%s anim=%s" % [
				name, is_display_only, anim_player, anim_player.is_playing(), anim_player.current_animation
			])
		# Safety net: if the flip animation isn't actually running (paused
		# player, zero speed, missing track), reveal the face directly so
		# a card can never be left stuck showing only its back.
		if not anim_player.is_playing():
			_apply_face_up()
			card_flip_finished.emit()
	else:
		push_warning("UpgradeCard: no '%s' animation on %s, revealing face directly" % [FLIP_ANIM, name])
		_apply_face_up()
		card_flip_finished.emit()
		

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
	# Elastic pop-in instead of a flat show(), then the existing blink anim.
	selection_icon.scale = Vector2.ZERO
	selection_icon.show()
	selection_icon.play("selector_blink")
	var icon_tween := create_tween()
	icon_tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	icon_tween.tween_property(selection_icon, "scale", Vector2(4, 4), 0.5)


# TODO This should handle the shader stuff if we decide to do that
#func _handle_shader() -> void:
	#var shader_material = ShaderMaterial.new()
	#print("\n" + str(shader_material))
	#shader_material.shader = card_shader
	#print(card_shader)
	#print(shader_material.shader)
	#self.material = shader_material
	#print(str(self.material) + "\n")

## Called by CardHand right after add_child, once the @onready refs are
## actually valid. Icon only overwrites if this upgrade has one assigned —
## otherwise the placeholder already on the node in the scene stays put.
func set_upgrade(upgrade : UpgradeData) -> void:
	if not upgrade:
		return
	if upgrade.icon:
		card_icon.texture = upgrade.icon
	title_label.text = upgrade.name
	description_label.text = upgrade.description


# NOTE what happens when a card is confirmed lives in CardHand now
# (_handle_clicked_card -> _resolve_pick): the draft runs in two steps, so
# deciding between "next step" and "done, go to the level" needs knowledge
# of the draft's step, which is the hand's business, not a single card's.
