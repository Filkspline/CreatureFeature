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

@export_group("Music")
## Looping background track for the match. WAV doesn't carry loop
## points the way ogg can, so looping is handled manually in
## _on_music_finished() below by restarting playback whenever the
## stream ends, rather than relying on the AudioStream's own loop flag.
@export var background_music: AudioStream = preload("res://assets/MusicTrack1.wav")

var _music_player: AudioStreamPlayer

const CARD_SELECT_SCENE := "res://scenes/upgrade_card_ui.tscn"
const MATCH_END_SCREEN_SCENE := "res://scenes/end_screen.tscn"

const INPUT_BASES: Array[String] = ["Left", "Right", "Up", "Down", "Normal", "Special", "Jump"]

var p1_rounds_won: int = 0
var p2_rounds_won: int = 0

signal round_won(winner_id: int, p1_rounds: int, p2_rounds: int)
signal match_over(winner_id: int)

signal request_first_upgrade_arrays()
signal return_first_upgrade_arrays(move_array : Array[UpgradeData], upgrade_array : Array[UpgradeData])


var _hitstop_token: int = 0

var death_freeze_active: bool = false

var p1_node: CharacterBody2D
var p2_node: CharacterBody2D

var p1_pre_fight_picked : bool = false
var p2_pre_fight_picked : bool = false
var is_pre_fight_pick : bool = true

var p1_character_id : int = 0
var p2_character_id : int = 0

var p1_device : PlayerInputDevice
var p2_device : PlayerInputDevice

var keyboard_layouts : Dictionary = {}


func _ready() -> void:
	_capture_keyboard_layouts()

	EventBus.hit_confirmed.connect(_on_hit_confirmed)
	EventBus.player_registered.connect(_on_player_registered)
	EventBus.player_defeated.connect(_on_player_defeated)
	EventBus.death_sequence_finished.connect(_on_death_sequence_finished)

	_setup_music_player()

	call_deferred("start_match")


# WAV doesn't support loop points the way ogg can, so this manually
# restarts playback every time the stream finishes (see
# _on_music_finished()) instead of relying on the stream's own loop
# flag, which WAV files don't have.
func _setup_music_player() -> void:
	if not background_music:
		push_warning("GameManager: background_music not assigned, skipping music playback")
		return

	_music_player = AudioStreamPlayer.new()
	_music_player.stream = background_music
	add_child(_music_player)
	_music_player.finished.connect(_on_music_finished)
	_music_player.play()


func _on_music_finished() -> void:
	_music_player.play()


# Resets the score and tells anything listening (mainly the upgrade pool
# manager) to reset its pools. Only meant to run once per match.
func start_match() -> void:
	p1_rounds_won = 0
	p2_rounds_won = 0
	EventBus.match_started.emit()


func reset_player_select() -> void:
	p1_character_id = 0
	p2_character_id = 0
	p1_device = null
	p2_device = null



func _capture_keyboard_layouts() -> void:
	keyboard_layouts.clear()
	for suffix: String in ["P1", "P2"]:
		var layout := {}
		for base in INPUT_BASES:
			var action := base + suffix
			var keys: Array = []
			if InputMap.has_action(action):
				for event in InputMap.action_get_events(action):
					if event is InputEventKey:
						keys.append(event)
			layout[base] = keys
		keyboard_layouts[suffix] = layout


func bind_player_inputs() -> void:
	_bind_slot_actions(1, p1_device)
	_bind_slot_actions(2, p2_device)


func _bind_slot_actions(slot: int, device: PlayerInputDevice) -> void:
	var suffix := "P%d" % slot
	for base in INPUT_BASES:
		var action := base + suffix
		if not InputMap.has_action(action):
			push_warning("GameManager: InputMap is missing action '%s', skipping" % action)
			continue
		for existing in InputMap.action_get_events(action):
			InputMap.action_erase_event(action, existing)
		if device == null:
			continue
		if device.kind == PlayerInputDevice.Kind.KEYBOARD:
			_add_keyboard_events(action, device.native_action_suffix, base)
		else:
			_add_joypad_events(action, device.device_id, base)


func _add_keyboard_events(action: StringName, layout_suffix: String, base: String) -> void:
	for key in keyboard_layouts.get(layout_suffix, {}).get(base, []):
		if not (key is InputEventKey):
			continue
		var key_event := key as InputEventKey
		var copy := InputEventKey.new()
		copy.physical_keycode = key_event.physical_keycode
		copy.keycode = key_event.keycode
		InputMap.action_add_event(action, copy)


func _add_joypad_events(action: StringName, device_id: int, base: String) -> void:
	match base:
		"Left":
			_add_joypad_button(action, device_id, JOY_BUTTON_DPAD_LEFT)
			_add_joypad_axis(action, device_id, JOY_AXIS_LEFT_X, -1.0)
		"Right":
			_add_joypad_button(action, device_id, JOY_BUTTON_DPAD_RIGHT)
			_add_joypad_axis(action, device_id, JOY_AXIS_LEFT_X, 1.0)
		"Up":
			_add_joypad_button(action, device_id, JOY_BUTTON_DPAD_UP)
			_add_joypad_axis(action, device_id, JOY_AXIS_LEFT_Y, -1.0)
		"Down":
			_add_joypad_button(action, device_id, JOY_BUTTON_DPAD_DOWN)
			_add_joypad_axis(action, device_id, JOY_AXIS_LEFT_Y, 1.0)
		"Normal":
			_add_joypad_button(action, device_id, JOY_BUTTON_A)
		"Special":
			_add_joypad_button(action, device_id, JOY_BUTTON_B)
		"Jump":
			_add_joypad_button(action, device_id, JOY_BUTTON_X)


func _add_joypad_button(action: StringName, device_id: int, button_index: int) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device_id
	event.button_index = button_index
	InputMap.action_add_event(action, event)


func _add_joypad_axis(action: StringName, device_id: int, axis: int, axis_value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device_id
	event.axis = axis
	event.axis_value = axis_value
	InputMap.action_add_event(action, event)


func _on_player_registered(player_id: int, player_node: Node) -> void:
	if player_id == 1:
		p1_node = player_node
	elif player_id == 2:
		p2_node = player_node
	else:
		push_warning("GameManager: player_registered fired with unexpected player_id %d" % player_id)


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
		#EventBus.game_ended.emit(_other_player_id(winner_id))
		SceneTransition.change_scene(MATCH_END_SCREEN_SCENE)
		return

	EventBus.round_lost.emit(loser_id)

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

	await get_tree().create_timer(duration, true, false, true).timeout

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
