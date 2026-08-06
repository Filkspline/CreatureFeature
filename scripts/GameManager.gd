extends Node

# ──────────────────────────────────────────────────────────────────
#  GameManager (Autoload)
#
#  Reads from EventBus and reacts to game-wide events. For now: applies
#  hitstop (a brief freeze-frame) whenever a hit lands.

@export_group("Hitstop")
@export var enabled: bool = true
## Freeze duration (seconds, real-time) when a hit actually lands.
@export var hitstop_duration_hit: float = 0.1
## Freeze duration (seconds, real-time) when a hit is blocked.
@export var hitstop_duration_blocked: float = 0.02

# Bumped every time hitstop is (re)triggered. Only the timer holding the
# current token is allowed to restore time_scale, so a second hit landing
# mid-hitstop extends the freeze instead of ending it early.
var _hitstop_token: int = 0
var p1_lose : bool # NOTE this may be changed in the future but currently just uses a bool to decide who wins and loses

func _ready() -> void:
	EventBus.player_hit_landed.connect(_on_player_hit_landed)


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

# ──────────────────────────────────────────────────────────────────
# Game manager debug items

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_1 and event.pressed:
			print("Test1")
			UpgradePoolManager._duplicate_card_pools()
			p1_lose = true
			get_tree().change_scene_to_file("res://scenes/upgrade_card_ui.tscn")
		elif event.keycode == KEY_2 and event.pressed:
			print("Test2")
			UpgradePoolManager._duplicate_card_pools()
			p1_lose = false
			get_tree().change_scene_to_file("res://scenes/upgrade_card_ui.tscn")
		else:
			pass
	
	pass
