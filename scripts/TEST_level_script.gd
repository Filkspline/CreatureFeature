extends Node2D

# ──────────────────────────────────────────────────────────────────
#  TestLevel
#
#  The fight level. Every round is a fresh load of this scene, both the
#  first round of a match and every round that follows an upgrade draft
#  (GameManager._end_round sends the loser to the card select, and that
#  hands back here), so per-round setup belongs in this script rather than
#  anywhere tied to match start.

## Round-start "3, 2, 1". Kept in its own scene so the timing and the
## squash/stretch juice are tunable in the Inspector without touching this
## script; this only spawns it.
@export var round_countdown_scene : PackedScene = preload("res://scenes/countdown.tscn")


func _ready() -> void:
	_start_round_countdown()


# Spawned from _ready because children run their _ready first: by the time
# a scene root gets here, both players have registered and had their picked
# upgrades replayed onto them, so the round is fully set up and the
# countdown can take the controls away until it finishes. It releases them
# itself when it ends, or on its way out if it never gets that far.
func _start_round_countdown() -> void:
	if not round_countdown_scene:
		push_warning("TestLevel: no round_countdown_scene assigned, no countdown this round")
		return
	add_child(round_countdown_scene.instantiate())
