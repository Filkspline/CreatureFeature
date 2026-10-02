class_name SelectionPointer
extends AnimatedSprite2D

# ──────────────────────────────────────────────────────────────────
#  SelectionPointer
#
#  The little blinking selector used by the menus to show what is currently
#  selected: it sits beside the highlighted control and rotates to point at
#  it. Same sprite as the draft screen's card selector.
#
#  By default it follows whatever control currently has focus, which is how
#  every menu in this project drives its selection (they move an index and
#  call grab_focus()), so a menu only has to place this node and make sure the
#  focused button exists.
#
#  The sheet's art has some fixed orientation, so base_rotation_degrees is
#  exported: set it once so the pointer looks right, and every other angle is
#  measured relative to it.

## How far the pointer sits from the target's edge, along the target's
## horizontal centre line.
@export var edge_distance : float = 26.0
## Rotation added to the computed aim, so the art's own orientation can be
## corrected without touching code. Measured in degrees.
@export var base_rotation_degrees : float = 0.0
## Round the aim to the nearest 90 degrees, so the pointer snaps to pointing
## left/right/up/down rather than sitting at an odd angle.
@export var snap_to_cardinal : bool = true
@export var follow_focus : bool = true
## How long it takes to slide to a newly selected control.
@export var move_duration : float = 0.12
@export var move_transition : Tween.TransitionType = Tween.TRANS_QUAD
@export var move_ease : Tween.EaseType = Tween.EASE_OUT
@export var pointer_scale : float = 1.0

@export_group("Pop-in")
## Played the moment the pointer appears, and any time it comes back from
## hidden, so the selector pops in instead of blinking into existence. Same
## springy overshoot the card hand's own selector uses.
@export var pop_in_duration : float = 0.35
@export_range(0.0, 1.0, 0.05) var pop_in_start_scale : float = 0.0
@export var pop_in_transition : Tween.TransitionType = Tween.TRANS_BACK
@export var pop_in_ease : Tween.EaseType = Tween.EASE_OUT

var _target : Control = null
var _move_tween : Tween
var _pop_tween : Tween


func _ready() -> void:
	# Runs while paused too: the pause menu is exactly where this pointer
	# matters, and its buttons are PROCESS_MODE_ALWAYS for the same reason.
	process_mode = Node.PROCESS_MODE_ALWAYS
	scale = Vector2.ONE * pointer_scale
	visible = false
	if frames_available():
		play(&"selector_blink")


func _process(_delta: float) -> void:
	if not follow_focus:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus != _target:
		follow(focus)


## Points at this control (or hides when given null).
func follow(target: Control) -> void:
	_target = target
	if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
		visible = false
		return

	var was_hidden := not visible
	visible = true
	if was_hidden:
		_play_pop_in()
	var centre := target.global_position + target.size * 0.5
	var global_point := Vector2(target.global_position.x - edge_distance, centre.y)
	# The aim goes from the pointer towards the target, so the art can be a
	# plain arrow regardless of which side it ends up on.
	rotation = _aim_rotation(global_point, centre)

	if _move_tween:
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.set_trans(move_transition).set_ease(move_ease)
	_move_tween.tween_property(self, "global_position", global_point, move_duration)


# The arrival: scales up from (usually) nothing with a back-eased overshoot, so
# the selector lands on the menu rather than appearing already there.
func _play_pop_in() -> void:
	if _pop_tween:
		_pop_tween.kill()
	scale = Vector2.ONE * pop_in_start_scale
	_pop_tween = create_tween()
	_pop_tween.set_trans(pop_in_transition).set_ease(pop_in_ease)
	_pop_tween.tween_property(self, "scale", Vector2.ONE * pointer_scale, pop_in_duration)


func frames_available() -> bool:
	if sprite_frames == null:
		return false
	return sprite_frames.has_animation(&"selector_blink") or not sprite_frames.get_animation_names().is_empty()


func _aim_rotation(from_point: Vector2, to_point: Vector2) -> float:
	var aim := (to_point - from_point).angle() + deg_to_rad(base_rotation_degrees)
	if snap_to_cardinal:
		aim = snappedf(aim, PI * 0.5)
	return aim
