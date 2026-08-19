extends CanvasLayer



@export var transition_animation_name: StringName = "Transition"

## Ignores a second change_scene() call that comes in while one is
## already mid-transition, instead of stomping the first and leaving
## the mouth in a half-finished state.
var is_transitioning: bool = false

var _pending_scene_path: String = ""

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var mouth: Sprite2D = $Mouth


func _ready() -> void:
	# PROCESS_MODE_ALWAYS so a transition triggered right as a hit
	# lands (mid-hitstop, Engine.time_scale == 0) still plays instead
	# of stalling — same reasoning as Camera2D's shake system.
	process_mode = Node.PROCESS_MODE_ALWAYS
	animation_player.process_mode = Node.PROCESS_MODE_ALWAYS
	mouth.process_mode = Node.PROCESS_MODE_ALWAYS

	mouth.hide()
	animation_player.animation_finished.connect(_on_transition_finished)


## Call this instead of get_tree().change_scene_to_file(path) anywhere
## a scene transition is needed. Just kicks off the "transition"
## animation — the actual scene swap happens later, mid-animation, off
## the Call Method key described above.
func change_scene(path: String) -> void:
	if is_transitioning:
		push_warning("[SceneTransition] change_scene('%s') ignored — already mid-transition" % path)
		return
	is_transitioning = true
	_pending_scene_path = path
	mouth.show()
	animation_player.play(transition_animation_name)


## Wired up as a Call Method track key on the "transition" animation,
## placed at the frame where the mouth is fully closed and the screen
## is completely covered.
func _perform_scene_change() -> void:
	get_tree().change_scene_to_file(_pending_scene_path)
	_pending_scene_path = ""


## Fires whenever ANY animation on this AnimationPlayer finishes —
## there's only ever "transition" here, so no need to check anim_name.
func _on_transition_finished(_anim_name: StringName) -> void:
	mouth.hide()
	is_transitioning = false
