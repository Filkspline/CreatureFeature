extends Node

# ──────────────────────────────────────────────────────────────────
#  GameManager (Autoload)
#
#  Reads from EventBus and reacts to game-wide events. For now: applies
#  hitstop (a brief freeze-frame) and camera shake whenever a hit lands,
#  and holds live references to both Player nodes so the upgrade system
#  has someone to apply upgrades to.

@export_group("Hitstop")
@export var enabled: bool = true
## Freeze duration (seconds, real-time) when a hit actually lands.
@export var hitstop_duration_hit: float = 0.1
## Freeze duration (seconds, real-time) when a hit is blocked.
@export var hitstop_duration_blocked: float = 0.02

@export_group("Camera Shake")
## Shake amount added per point of move damage. A 10-damage hit gives
## 10 * this much shake before the min/max clamp and blocked multiplier
## below are applied.
@export var shake_damage_scale: float = 0.15
## Floor and ceiling for the final shake amount, so a 1-damage poke
## still reads as a hit and a huge combo finisher doesn't fling the
## camera off screen.
@export var shake_min: float = 2.0
@export var shake_max: float = 1000.0
## Blocked hits shake less than the same move landing clean, same as
## the reduced hitstop below.
@export var shake_blocked_multiplier: float = 8.35

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

signal request_first_upgrade_arrays()
signal return_first_upgrade_arrays(move_array : Array[UpgradeData], upgrade_array : Array[UpgradeData])

# Bumped every time hitstop is (re)triggered. Only the timer holding the
# current token is allowed to restore time_scale, so a second hit landing
# mid-hitstop extends the freeze instead of ending it early.
var _hitstop_token: int = 0

# Set the instant a player dies and cleared only once FightUI's death
# sequence finishes (see _on_death_sequence_finished below). While true,
# _apply_hitstop()'s normal short-hitstop timer is not allowed to restore
# Engine.time_scale on its own — otherwise the killing blow's own
# ordinary hit_confirmed hitstop (fired a few lines after player_defeated,
# see Player._check_hit()) would un-freeze the game after ~0.1s even
# though the death sequence is still playing.
var death_freeze_active: bool = false

# Populated by EventBus.player_registered, fired from each Player's own
# _ready(). This survives scene changes — a fresh Player instance just
# re-registers itself when its new scene loads, no @export wiring needed
# across scene boundaries.
var p1_node: CharacterBody2D
var p2_node: CharacterBody2D

var p1_pre_fight_picked : bool = false
var p2_pre_fight_picked : bool = false
var is_pre_fight_pick : bool = true

func _ready() -> void:
	# hit_confirmed (rather than player_hit_landed) is what we want here
	# specifically because it already carries the MoveData that landed —
	# player_hit_landed only gives a move *name*, which would mean doing
	# a lookup just to get at .damage for the shake scaling below.
	EventBus.hit_confirmed.connect(_on_hit_confirmed)
	EventBus.player_registered.connect(_on_player_registered)
	EventBus.player_defeated.connect(_on_player_defeated)
	EventBus.death_sequence_finished.connect(_on_death_sequence_finished)
	
	EventBus.pre_fight_upgrade_check.connect(_handle_pre_fight_info)
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


# Freezes the game the instant someone dies, then just waits.
# FightUI listens for this same signal and plays the death sequence
# (teeth bar effect, impact flash, popup) entirely on unscaled time —
# _on_death_sequence_finished below is what actually unfreezes and
# moves the round forward once that's done.
func _on_player_defeated(player_id: int) -> void:
	death_freeze_active = true
	Engine.time_scale = 0.0


func _on_death_sequence_finished(player_id: int) -> void:
	death_freeze_active = false
	Engine.time_scale = 1.0
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

	# Routed through SceneTransition instead of a raw
	# change_scene_to_file. This doesn't need call_deferred() the way
	# the old direct change_scene_to_file() call did — by the time this
	# runs, time_scale is already back to normal and the death sequence
	# (and the hit that caused it) are fully resolved, and
	# SceneTransition.change_scene() doesn't actually swap the scene
	# until its own Call Method track key fires partway through the
	# mouth-close animation anyway.
	SceneTransition.change_scene(CARD_SELECT_SCENE)


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


func _on_hit_confirmed(_impact_position: Vector2, move_data: MoveData, _attacker: Node, _defender: Node, was_blocked: bool) -> void:
	if not enabled:
		return

	_apply_shake_for_hit(move_data, was_blocked)

	var duration := hitstop_duration_blocked if was_blocked else hitstop_duration_hit
	_apply_hitstop(duration)


# Scales shake off move_data.damage rather than a flat blocked/unblocked
# value, so a light poke barely rattles the camera while a heavy hit
# lands with real weight. Clamped so 1-damage jabs are still felt and
# nothing sends the camera flying.
func _apply_shake_for_hit(move_data: MoveData, was_blocked: bool) -> void:
	var shake_amount := move_data.damage * shake_damage_scale
	if was_blocked:
		shake_amount *= shake_blocked_multiplier
	shake_amount = clamp(shake_amount, shake_min, shake_max)
	EventBus.camera_shake.emit(shake_amount)


func _apply_hitstop(duration: float) -> void:
	if duration <= 0.0:
		return

	Engine.time_scale = 0.0
	_hitstop_token += 1
	var this_token := _hitstop_token

	# ignore_time_scale = true, so this timer counts real seconds even
	# though Engine.time_scale is 0 — otherwise it would never fire.
	await get_tree().create_timer(duration, true, false, true).timeout

	# Only restore time_scale if nothing re-triggered hitstop while we
	# waited, AND a death sequence isn't holding the freeze open. Without
	# that second check, the killing blow's own ordinary hit_confirmed
	# (which always fires right after player_defeated — see
	# Player._check_hit()) would restore time_scale after this short
	# duration and cut the death sequence off early.
	if this_token == _hitstop_token and not death_freeze_active:
		Engine.time_scale = 1.0


func _handle_pre_fight_info() -> void:
	if p1_pre_fight_picked == false:
		p1_pre_fight_picked = true
	
	elif p2_pre_fight_picked == false:
		p2_pre_fight_picked = true
		is_pre_fight_pick = false

		
func _input(event: InputEvent) -> void:
	# Dev shortcut: press 1 or 2 to simulate that player losing the round
	# right now, without needing to fight all the way down to zero HP.
	if not (event is InputEventKey and event.pressed):
		return

	if event.keycode == KEY_1:
		_end_round(1)
	elif event.keycode == KEY_2:
		_end_round(2)
