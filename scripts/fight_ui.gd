extends CanvasLayer

# ── Assignment ──────────────────────────────────────────────
# Can be dragged in manually in the inspector, but will also auto-fill
# from EventBus.player_registered if your Player scripts emit it (which
# is how GameManager gets its p1_node/p2_node too) — so this works even
# if the Player nodes get recreated across scene changes.
@export_group("Assignment")
@export var player_1: Player:
	set(value):
		player_1 = value
		if is_node_ready():
			_refresh_slot(1)
@export var player_2: Player:
	set(value):
		player_2 = value
		if is_node_ready():
			_refresh_slot(2)
@export var camera: Camera2D

# Bar textures (under/progress/over) and the border AnimatedSprite2D are
# set directly on the P1BarContainer/P2BarContainer nodes in the editor.
# IMPORTANT: the "Fill" TextureProgressBar needs a texture in its
# *Progress* slot (texture_progress) — that's the part that actually
# grows/shrinks with .value. texture_under and texture_over are both
# always drawn at full size regardless of value, so if only those two
# are set, damage will never be visible even though .value is changing
# correctly under the hood.

@export_group("Bar Feel")
@export var fill_tween_time: float = 0.12   # how fast the bar tweens to the new value
@export var hit_shake_strength: float = 4.0
@export var hit_shake_duration: float = 0.18
@export var hit_punch_scale: float = 1.08
@export var hit_punch_duration: float = 0.15
@export var low_health_threshold: float = 0.25
@export var low_health_pulse_color: Color = Color(1, 0.2, 0.2)
@export var low_health_pulse_speed: float = 2.5

@export_group("Round / Timer")
@export var round_time: float = 99.0
@export var timer_running: bool = true

@export_group("Damage Numbers")
@export var damage_number_duration: float = 0.6
@export var damage_number_rise: float = 40.0
@export var damage_number_offset: Vector2 = Vector2(0, -20)
@export var damage_number_color: Color = Color(1, 1, 1)
@export var block_number_color: Color = Color(0.6, 0.8, 1)

# ── Death sequence ──────────────────────────────────────────
# Runs entirely during hitstop (Engine.time_scale == 0), so every tween
# here uses set_ignore_time_scale(true) and every real-time wait uses
# create_timer(..., ignore_time_scale = true) — otherwise delta is 0
# and nothing would ever actually play.
@export_group("Death Sequence")
## How long DeathImpactEffect sits fully visible before it starts fading.
@export var death_impact_hold_time: float = 0.4
@export var death_impact_fade_time: float = 0.8
@export var death_popup_pop_duration: float = 1.65

signal timer_expired

var time_left: float
var p1_wins: int = 0
var p2_wins: int = 0

# bars[1] / bars[2] each hold: container, fill, last_health, pulsing,
# plus dynamically-added tween keys (pulse_tween, shake_tween, punch_tween).
var bars: Dictionary = {}

# pips[1] / pips[2] are arrays of {"open": AnimatedSprite2D, "idle": AnimatedSprite2D}
# built by scanning the actual "Pip*" nodes under P1RoundPips/P2RoundPips —
# these are real, editable nodes in the scene, not generated at runtime.
var pips: Dictionary = {1: [], 2: []}

var _death_popup_base_scale: Vector2

@onready var p1_name_label: Label = $UIRoot/P1NameLabel
@onready var p2_name_label: Label = $UIRoot/P2NameLabel
@onready var p1_round_pips: HBoxContainer = $UIRoot/P1RoundPips
@onready var p2_round_pips: HBoxContainer = $UIRoot/P2RoundPips
@onready var timer_label: Label = $UIRoot/TimerLabel
@onready var damage_layer: Control = $UIRoot/DamageNumberLayer
@onready var death_anim_player: AnimationPlayer = $UIRoot/AnimationPlayer
@onready var death_impact_effect: Sprite2D = $UIRoot/DeathImpactEffect
@onready var death_popup: Sprite2D = $DeathPopUp
@onready var death_popup_text: Label = $DeathPopUp/text

# The "teeth" sprites driven by the player1death/player2death animation
# tracks. Whether these start hidden depends on whatever visible = ...
# happens to be baked into the .tscn for each node — P1's has been set
# to false in the editor, but P2's (deathhealthbareffect2) currently has
# no visible key at all, which defaults to true and shows it immediately
# on scene load. Hiding both explicitly here means that no longer matters.
@onready var death_health_bar_effects: Array[Sprite2D] = [
	$UIRoot/P1BarContainer/deathhealthbareffect,
	$UIRoot/P2BarContainer/deathhealthbareffect2,
]


func _ready() -> void:
	bars[1] = _collect_bar_refs($UIRoot/P1BarContainer)
	bars[2] = _collect_bar_refs($UIRoot/P2BarContainer)

	for slot in [1, 2]:
		var b: Dictionary = bars[slot]
		b.container.pivot_offset = b.container.size * 0.5
		b.container.resized.connect(func(): b.container.pivot_offset = b.container.size * 0.5)

	pips[1] = _collect_pips(p1_round_pips)
	pips[2] = _collect_pips(p2_round_pips)

	_refresh_slot(1)
	_refresh_slot(2)

	time_left = round_time
	_update_timer_label()

	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.hit_confirmed.connect(_on_hit_confirmed)
	EventBus.player_defeated.connect(_on_player_defeated)
	GameManager.round_won.connect(_on_round_won)

	if EventBus.has_signal("player_registered"):
		EventBus.player_registered.connect(_on_player_registered)

	# All hidden until a death sequence actually needs them. Don't rely
	# on the .tscn's baked visible state for the teeth sprites — see the
	# comment on death_health_bar_effects above.
	death_impact_effect.visible = false
	for teeth_sprite in death_health_bar_effects:
		teeth_sprite.visible = false
	_death_popup_base_scale = death_popup.scale
	death_popup.visible = false

	_sync_existing_wins()


func _collect_bar_refs(container: Control) -> Dictionary:
	return {
		"container": container,
		"fill": container.get_node("Fill"),
		"last_health": 0.0,
		"pulsing": false,
	}


func _process(delta: float) -> void:
	if not timer_running or time_left <= 0.0:
		return
	time_left = max(time_left - delta, 0.0)
	_update_timer_label()
	if time_left == 0.0:
		timer_running = false
		timer_expired.emit()


func _update_timer_label() -> void:
	timer_label.text = str(int(ceil(time_left)))


# ── Player wiring ────────────────────────────────────────────
func _on_player_registered(player_id: int, player_node: Node) -> void:
	if player_id == 1:
		player_1 = player_node
	elif player_id == 2:
		player_2 = player_node


func _refresh_slot(slot: int) -> void:
	if not is_node_ready() or not bars.has(slot):
		return
	var player: Player = player_1 if slot == 1 else player_2
	var name_label: Label = p1_name_label if slot == 1 else p2_name_label
	if not player:
		return

	var b: Dictionary = bars[slot]
	b.fill.max_value = player.max_health
	b.fill.value = player.current_health
	b.last_health = player.current_health
	name_label.text = "Player %d" % player.player_id


# ── EventBus hooks ──────────────────────────────────────────
func _on_health_changed(player_id: int, new_health: float) -> void:
	if player_1 and player_id == player_1.player_id:
		_update_bar(1, new_health)
	elif player_2 and player_id == player_2.player_id:
		_update_bar(2, new_health)


func _on_hit_confirmed(impact_position: Vector2, move_data: MoveData, attacker: Node, defender: Node, was_blocked: bool) -> void:
	spawn_damage_number(int(move_data.damage), impact_position, was_blocked)


# ── Bar update + juice ──────────────────────────────────────
func _update_bar(slot: int, new_health: float) -> void:
	var b: Dictionary = bars[slot]
	var took_damage: bool = new_health < b.last_health

	var fill_tween := create_tween()
	fill_tween.tween_property(b.fill, "value", new_health, fill_tween_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if took_damage:
		_shake_bar(slot)
		_punch_bar(slot)

	_update_low_health_pulse(slot, new_health)
	b.last_health = new_health


func _shake_bar(slot: int) -> void:
	var b: Dictionary = bars[slot]
	_kill_tween(b, "shake_tween")

	var container: Control = b.container
	var original_pos: Vector2 = container.position
	var steps := 5
	var shake_tween := create_tween()
	for i in steps:
		var offset := Vector2(randf_range(-hit_shake_strength, hit_shake_strength), randf_range(-hit_shake_strength, hit_shake_strength))
		shake_tween.tween_property(container, "position", original_pos + offset, hit_shake_duration / steps)
	shake_tween.tween_property(container, "position", original_pos, hit_shake_duration / steps)
	b["shake_tween"] = shake_tween


func _punch_bar(slot: int) -> void:
	var b: Dictionary = bars[slot]
	_kill_tween(b, "punch_tween")

	var container: Control = b.container
	container.scale = Vector2.ONE
	var punch_tween := create_tween()
	punch_tween.tween_property(container, "scale", Vector2(hit_punch_scale, hit_punch_scale), hit_punch_duration * 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	punch_tween.tween_property(container, "scale", Vector2.ONE, hit_punch_duration * 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	b["punch_tween"] = punch_tween


func _update_low_health_pulse(slot: int, new_health: float) -> void:
	var b: Dictionary = bars[slot]
	var max_h: float = b.fill.max_value
	var ratio: float = new_health / max_h if max_h > 0.0 else 0.0
	var is_low: bool = ratio <= low_health_threshold and new_health > 0.0

	if is_low and not b.pulsing:
		b.pulsing = true
		_kill_tween(b, "pulse_tween")
		var pulse_tween := create_tween()
		pulse_tween.set_loops()
		pulse_tween.tween_property(b.fill, "self_modulate", low_health_pulse_color, 1.0 / low_health_pulse_speed) \
			.set_trans(Tween.TRANS_SINE)
		pulse_tween.tween_property(b.fill, "self_modulate", Color(1, 1, 1), 1.0 / low_health_pulse_speed) \
			.set_trans(Tween.TRANS_SINE)
		b["pulse_tween"] = pulse_tween
	elif not is_low and b.pulsing:
		b.pulsing = false
		_kill_tween(b, "pulse_tween")
		b.fill.self_modulate = Color(1, 1, 1)


func _kill_tween(b: Dictionary, key: String) -> void:
	if b.has(key):
		var t: Tween = b[key]
		if t and t.is_valid():
			t.kill()


# ── Damage numbers ──────────────────────────────────────────
func spawn_damage_number(amount: int, world_pos: Vector2, was_blocked: bool = false) -> void:
	if not damage_layer:
		return

	var label := Label.new()
	label.text = "BLOCKED" if was_blocked else str(amount)
	label.add_theme_font_size_override("font_size", 16 if was_blocked else 22)
	label.add_theme_color_override("font_color", block_number_color if was_blocked else damage_number_color)
	label.z_index = 10
	label.position = _world_to_screen(world_pos) + damage_number_offset
	damage_layer.add_child(label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - damage_number_rise, damage_number_duration)
	tween.tween_property(label, "modulate:a", 0.0, damage_number_duration).set_delay(damage_number_duration * 0.4)
	tween.chain().tween_callback(label.queue_free)


func _world_to_screen(world_pos: Vector2) -> Vector2:
	var cam := camera if camera else get_viewport().get_camera_2d()
	if not cam:
		return world_pos
	var vp_size := get_viewport().get_visible_rect().size
	return (world_pos - cam.global_position) * cam.zoom + vp_size * 0.5


func _on_round_won(winner_id: int, _p1_rounds: int, _p2_rounds: int) -> void:
	award_round_win(winner_id)


# ── Death sequence ───────────────────────────────────────────
# GameManager freezes Engine.time_scale to 0 the instant player_defeated
# fires (see GameManager._on_player_defeated) and stays frozen until we
# emit death_sequence_finished below — so this whole sequence needs to
# run on real, unscaled time or it would just hang forever at frame 0.
func _on_player_defeated(player_id: int) -> void:
	var slot := 0
	if player_1 and player_id == player_1.player_id:
		slot = 1
	elif player_2 and player_id == player_2.player_id:
		slot = 2

	if slot == 0:
		# No matching Player node registered with this UI — nothing to
		# animate against, so don't leave the game frozen waiting on us.
		EventBus.death_sequence_finished.emit(player_id)
		return

	_play_death_sequence(slot, player_id)


func _play_death_sequence(slot: int, player_id: int) -> void:
	var dead_player: Player = player_1 if slot == 1 else player_2
	var screen_pos: Vector2 = _world_to_screen(dead_player.global_position)

	# Bar teeth-close effect and the impact flash both fire the instant
	# the death lands — they run independently of each other and of the
	# popup below, which is what "lots of tweens" mid-sequence looks like.
	_play_bar_death_animation(slot)
	_show_death_impact(screen_pos)

	await get_tree().create_timer(death_impact_hold_time, true, false, true).timeout
	await _fade_death_impact()

	await _show_death_popup(screen_pos, player_id)

	EventBus.death_sequence_finished.emit(player_id)


# The "player1death"/"player2death" animations already exist on
# death_anim_player (frame + visible + z_index keys on the
# deathhealthbareffect sprites), authored in the editor. Calling
# .play() directly would freeze it instantly, though — AnimationPlayer
# advances using Engine-scaled delta same as everything else, and that
# delta is 0 during hitstop. So instead: play() just applies frame 0,
# then we immediately pause() the player's own internal advance and
# drive its timeline ourselves via seek(), fed from an
# ignore_time_scale tween. Same animation, immune to the freeze.
func _play_bar_death_animation(slot: int) -> void:
	var anim_name: StringName = "player1death" if slot == 1 else "player2death"
	if not death_anim_player.has_animation(anim_name):
		print("[FIGHT UI] no '%s' animation found — skipping teeth bar effect" % anim_name)
		return

	var length: float = death_anim_player.get_animation(anim_name).length
	death_anim_player.play(anim_name)
	death_anim_player.pause()

	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_method(func(t): death_anim_player.seek(t, true), 0.0, length, length)


func _show_death_impact(screen_pos: Vector2) -> void:
	death_impact_effect.position = screen_pos
	death_impact_effect.modulate.a = 1.0
	death_impact_effect.visible = true


func _fade_death_impact() -> void:
	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(death_impact_effect, "modulate:a", 0.0, death_impact_fade_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished
	death_impact_effect.visible = false


func _show_death_popup(screen_pos: Vector2, player_id: int) -> void:
	death_popup_text.text = "player%d.exe \nhas stopped working" % player_id
	death_popup.position = screen_pos
	death_popup.position.y = death_popup.position.y - 100 
	death_popup.scale = Vector2.ZERO
	death_popup.modulate.a = 1.0
	death_popup.visible = true

	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	tween.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(death_popup, "scale", _death_popup_base_scale, death_popup_pop_duration)
	await tween.finished


# ── Round pips (eyes) ────────────────────────────────────────
# Each pip in the scene is a small Control with two AnimatedSprite2D
# children: "Open" (closed pose by default, plays its opening animation
# once a round is won) and "Idle" (hidden until Open finishes, then
# takes over with its own looping look-around animation). Add/remove
# "Pip*" nodes under P1RoundPips/P2RoundPips directly in the editor to
# change how many rounds are needed to win.
func _collect_pips(container: HBoxContainer) -> Array:
	var result: Array = []
	for pip_node in container.get_children():
		var open_sprite: AnimatedSprite2D = pip_node.get_node_or_null("Open")
		var idle_sprite: AnimatedSprite2D = pip_node.get_node_or_null("Idle")
		if not open_sprite or not idle_sprite:
			continue
		var pip := {"open": open_sprite, "idle": idle_sprite}
		_close_pip(pip)
		open_sprite.animation_finished.connect(_on_pip_open_finished.bind(pip))
		result.append(pip)
	return result


func _close_pip(pip: Dictionary) -> void:
	pip.open.visible = true
	pip.open.stop()
	pip.open.frame = 0
	pip.idle.visible = false
	pip.idle.stop()


func _open_pip(pip: Dictionary) -> void:
	pip.open.visible = true
	pip.idle.visible = false
	pip.open.play()


# Skips straight to the idle "already open" look, used when this FightUI
# is a fresh instance catching up to wins that happened before it existed.
func _open_pip_instant(pip: Dictionary) -> void:
	pip.open.visible = false
	pip.idle.visible = true
	pip.idle.play()


# GameManager is the autoload holding the real score, so a brand new
# FightUI (recreated every time the fight scene reloads after a draft)
# needs to catch its pips up to whatever GameManager already has.
func _sync_existing_wins() -> void:
	_sync_slot_wins(1, GameManager.p1_rounds_won)
	_sync_slot_wins(2, GameManager.p2_rounds_won)


func _sync_slot_wins(slot: int, rounds_won: int) -> void:
	var slot_pips: Array = pips[slot]
	var pip_count: int = min(rounds_won, slot_pips.size())
	for i in pip_count:
		_open_pip_instant(slot_pips[i])

	if slot == 1:
		p1_wins = rounds_won
	else:
		p2_wins = rounds_won


func _on_pip_open_finished(pip: Dictionary) -> void:
	pip.open.visible = false
	pip.idle.visible = true
	pip.idle.play()


# ── Public round/match API — call these from wherever your round-flow
# logic lives (a game manager, etc). This UI doesn't decide when a round
# ends, it just displays the state you give it. ──────────────────────
func award_round_win(player_id: int) -> void:
	if player_1 and player_id == player_1.player_id:
		if p1_wins < pips[1].size():
			_open_pip(pips[1][p1_wins])
		p1_wins += 1
	elif player_2 and player_id == player_2.player_id:
		if p2_wins < pips[2].size():
			_open_pip(pips[2][p2_wins])
		p2_wins += 1


func reset_round(new_round_time: float = -1.0) -> void:
	if new_round_time > 0.0:
		round_time = new_round_time
	time_left = round_time
	timer_running = true
	_update_timer_label()

	if player_1:
		player_1.reset_health()
	if player_2:
		player_2.reset_health()

	_reset_bar(1)
	_reset_bar(2)


func _reset_bar(slot: int) -> void:
	if not bars.has(slot):
		return
	var b: Dictionary = bars[slot]
	_kill_tween(b, "pulse_tween")
	b.pulsing = false
	b.fill.self_modulate = Color(1, 1, 1)
	var max_h: float = b.fill.max_value
	b.fill.value = max_h
	b.last_health = max_h


func reset_match() -> void:
	p1_wins = 0
	p2_wins = 0
	for pip in pips[1]:
		_close_pip(pip)
	for pip in pips[2]:
		_close_pip(pip)
	reset_round()
