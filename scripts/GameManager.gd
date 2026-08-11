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

const CARD_SELECT_SCENE := "res://scenes/upgrade_card_ui.tscn"

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


func _ready() -> void:
	EventBus.player_hit_landed.connect(_on_player_hit_landed)
	EventBus.player_registered.connect(_on_player_registered)
	EventBus.player_defeated.connect(_on_player_defeated)

	# Deferred so every autoload (including UpgradePoolManager) has
	# finished its own _ready() and connected to match_started before we
	# fire it. Autoload _ready() order isn't guaranteed, and firing this
	# too early meant the pools never got built.
	call_deferred("start_match")


# Resets the score and tells anything listening (mainly the upgrade pool
# manager) to reset its pools. Only meant to run once per match.
func start_match() -> void:
	p1_rounds_won = 0
	p2_rounds_won = 0
	EventBus.match_started.emit()


func _on_player_registered(player_id: int, player_node: Node) -> void:
	if player_id == 1:
		p1_node = player_node
	elif player_id == 2:
		p2_node = player_node
	else:
		push_warning("GameManager: player_registered fired with unexpected player_id %d" % player_id)


func _on_player_defeated(player_id: int) -> void:
	_end_round(player_id)


# player_id here is the loser, since that is what we actually know when
# a round ends (their HP hit zero).
func _end_round(loser_id: int) -> void:
	var winner_id := _other_player_id(loser_id)
	_award_round_win(winner_id)

	if _has_won_match(winner_id):
		match_over.emit(winner_id)
		print("Match over, player %d wins" % winner_id)
		return

	EventBus.round_lost.emit(loser_id)

	# Deferred because this can run mid-hit-resolution (the hit that just
	# brought someone to zero HP is still finishing up things like the
	# damage number), and swapping the scene out from under that leaves
	# FightUI detached from the tree while it's still being used.
	get_tree().call_deferred("change_scene_to_file", CARD_SELECT_SCENE)


func _other_player_id(player_id: int) -> int:
	return 2 if player_id == 1 else 1


func _award_round_win(winner_id: int) -> void:
	if winner_id == 1:
		p1_rounds_won += 1
	else:
		p2_rounds_won += 1
	round_won.emit(winner_id, p1_rounds_won, p2_rounds_won)


func _has_won_match(player_id: int) -> bool:
	var rounds_won := p1_rounds_won if player_id == 1 else p2_rounds_won
	return rounds_won >= rounds_to_win


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
	# Dev shortcut: press 1 or 2 to simulate that player losing the round
	# right now, without needing to fight all the way down to zero HP.
	if not (event is InputEventKey and event.pressed):
		return

	if event.keycode == KEY_1:
		_end_round(1)
	elif event.keycode == KEY_2:
		_end_round(2)
