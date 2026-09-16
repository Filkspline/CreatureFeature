extends Node2D

# ──────────────────────────────────────────────────────────────────
#  CutScene
#
#  The once-per-match intro that sits between the pre-fight card select
#  and the first round. Plays this scene's AnimationPlayer cuts back to
#  back, then hands off to the fight level through SceneTransition, same
#  as every other scene change in the project.
#
#  Only the pre-fight pick loads this scene (pre_fight_upgrade_hand.gd,
#  via GameManager.CUTSCENE_SCENE). The round-loss upgrade draft runs off
#  GameManager._end_round -> CARD_SELECT_SCENE and never comes through
#  here, so this plays exactly once per match, not once per round.

## Cuts, played in order. Each one starts when the previous one finishes
## and the hand off happens after the last one ends. The pacing itself
## lives in the AnimationPlayer, not here.
@export var cutscene_animations : Array[StringName] = [&"cut1", &"cut2"]
## Scene to hand off to once the cuts have played out. Defaults to the
## fight level, which is where the pre-fight pick went straight to before
## this scene was wired in.
@export var next_scene_path : String = "res://scenes/test_level.tscn"
## Beat before the first cut starts. SceneTransition swaps the scene part
## way through its 0.6s Mouth animation (at 0.2667s) and the mouth is still
## opening after that point, so without this beat the opening of cut1 plays
## out behind the transitioning mouth.
@export var start_delay : float = 0.15

@onready var anim_player : AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	_play_cutscene()


# Plays each cut in turn and waits on the real animation_finished signal
# rather than counting a timer, so retiming a cut in the AnimationPlayer is
# all it takes to change how long the cutscene runs.
func _play_cutscene() -> void:
	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout

	for anim_name in cutscene_animations:
		if not anim_player.has_animation(anim_name):
			push_warning("CutScene: '%s' isn't on %s, skipping it" % [anim_name, anim_player.name])
			continue
		anim_player.play(anim_name)
		await anim_player.animation_finished

	_advance_to_fight()


# Routed through SceneTransition rather than a raw change_scene_to_file, so
# the mouth wipe covers the swap from the cutscene into the level like it
# covers every other scene change.
func _advance_to_fight() -> void:
	SceneTransition.change_scene(next_scene_path)
