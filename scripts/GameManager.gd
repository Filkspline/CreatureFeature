extends Node

# ──────────────────────────────────────────────────────────────────
#  GameManager (Autoload)
#
#  Reads from EventBus and reacts to game-wide events. For now: applies
#  hitstop (a brief freeze-frame) whenever a hit lands, and holds live
#  references to both Player nodes so the upgrade system has someone
#  to apply upgrades to.

@export_group("Hitstop")
@export var enabled: bool = true
## Freeze duration (seconds, real-time) when a hit actually lands.
@export var hitstop_duration_hit: float = 0.1
## Freeze duration (seconds, real-time) when a hit is blocked.
@export var hitstop_duration_blocked: float = 0.02

@export_group("Match")
## Rounds a player needs to win the match (best-of-5 = 3).
@export var rounds_to_win: int = 3

# Canonical round score, held here rather than on the UI because
# FightUI lives inside the fight scene and gets torn down/recreated
# every time we go to the upgrade draft and back. GameManager is an
# autoload, so it's the thing that actually survives across that.
var p1_rounds_won: int = 0
var p2_rounds_won: int = 0

# Fired the instant a round is won, with the score already updated.
# Anything (UI, draft flow, etc) can listen instead of polling.
signal round_won(winner_id: int, p1_rounds: int, p2_rounds: int)
signal match_over(winner_id: int)

# Bumped every time hitstop is (re)triggered. Only the timer holding the
# current token is allowed to restore time_scale, so a second hit landing
# mid-hitstop extends the freeze instead of ending it early.
var _hitstop_token: int = 0

# Populated by EventBus.player_registered, fired from each Player's own
# _ready(). This survives scene changes — a fresh Player instance just
# re-registers itself when its new scene loads, no @export wiring needed
# across scene boundaries.
var p1_node: CharacterBody2D
var p2_node: CharacterBody2D

var card_ui_scene = preload("res://scenes/upgrade_card_ui.tscn")


func _ready() -> void:
	EventBus.player_hit_landed.connect(_on_player_hit_landed)
	EventBus.player_registered.connect(_on_player_registered)


func _on_player_registered(player_id: int, player_node: Node) -> void:
	if player_id == 1:
		p1_node = player_node
	elif player_id == 2:
		p2_node = player_node
	else:
		push_warning("GameManager: player_registered fired with unexpected player_id %d" % player_id)


func _on_player_hit_landed(player_id: int, _move_name: String, was_blocked: bool) -> void:
	if not enabled:
		return
	
	# Trigger camera shake
	if was_blocked:
		EventBus.camera_shake.emit(1.0)
	else:
		EventBus.camera_shake.emit(2.0)
	
	var duration := hitstop_duration_blocked if was_blocked else hitstop_duration_hit
	_apply_hitstop(duration)


func _apply_hitstop(duration: float) -> void:
	if duration <= 0.0:
		return

	Engine.time_scale = 0.0
	_hitstop_token += 1
	var this_token := _hitstop_token

	# ignore_time_scale = true, so this timer counts real seconds even
	# though Engine.time_scale is 0 — otherwise it would never fire.
	await get_tree().create_timer(duration, true, false, true).timeout

	# Only restore time_scale if nothing re-triggered hitstop while we waited.
	if this_token == _hitstop_token:
		Engine.time_scale = 1.0
		
		
func _input(event: InputEvent) -> void:
	# NOTE this is just a temp dev solution for forcing a transition into the 
	# card upgrade system
	if event is InputEventKey:
		if event.keycode == KEY_1 and event.pressed:
			print("Test1")
			EventBus.match_started.emit()
			EventBus.round_lost.emit(1)
			get_tree().change_scene_to_file("res://scenes/upgrade_card_ui.tscn")
		elif event.keycode == KEY_2 and event.pressed:
			print("Test2")
			EventBus.match_started.emit()
			EventBus.round_lost.emit(2)
			get_tree().change_scene_to_file("res://scenes/upgrade_card_ui.tscn")
