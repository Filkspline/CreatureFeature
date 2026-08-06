extends CanvasLayer

# ── Assignment ──────────────────────────────────────────────
# Drag the Player nodes and the Camera2D in from the scene tree in the
# inspector, same as any other node reference. Can also be reassigned at
# runtime by just setting these (e.g. fight_ui.player_1 = some_player).
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

@export_group("Round / Timer")
@export var round_time: float = 99.0
@export var rounds_to_win: int = 2
@export var timer_running: bool = true

@export_group("Damage Numbers")
@export var damage_number_duration: float = 0.6
@export var damage_number_rise: float = 40.0
@export var damage_number_offset: Vector2 = Vector2(0, -20)
@export var damage_number_color: Color = Color(1, 1, 1)
@export var block_number_color: Color = Color(0.6, 0.8, 1)

signal timer_expired

var time_left: float
var p1_wins: int = 0
var p2_wins: int = 0

@onready var p1_health_bar: ProgressBar = $UIRoot/P1HealthBarBG/P1HealthBar
@onready var p2_health_bar: ProgressBar = $UIRoot/P2HealthBarBG/P2HealthBar
@onready var p1_name_label: Label = $UIRoot/P1NameLabel
@onready var p2_name_label: Label = $UIRoot/P2NameLabel
@onready var p1_round_pips: HBoxContainer = $UIRoot/P1RoundPips
@onready var p2_round_pips: HBoxContainer = $UIRoot/P2RoundPips
@onready var timer_label: Label = $UIRoot/TimerLabel
@onready var damage_layer: Control = $UIRoot/DamageNumberLayer


func _ready() -> void:
	_build_round_pips(p1_round_pips)
	_build_round_pips(p2_round_pips)
	_refresh_slot(1)
	_refresh_slot(2)

	time_left = round_time
	_update_timer_label()

	EventBus.player_health_changed.connect(_on_health_changed)
	EventBus.hit_confirmed.connect(_on_hit_confirmed)


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


# ── Player slot setup ───────────────────────────────────────
func _refresh_slot(slot: int) -> void:
	if not is_node_ready():
		return
	match slot:
		1:
			if player_1:
				p1_health_bar.max_value = player_1.max_health
				p1_health_bar.value = player_1.current_health
				p1_name_label.text = "Player %d" % player_1.player_id
		2:
			if player_2:
				p2_health_bar.max_value = player_2.max_health
				p2_health_bar.value = player_2.current_health
				p2_name_label.text = "Player %d" % player_2.player_id


# ── EventBus hooks ──────────────────────────────────────────
func _on_health_changed(player_id: int, new_health: float) -> void:
	if player_1 and player_id == player_1.player_id:
		p1_health_bar.value = new_health
	elif player_2 and player_id == player_2.player_id:
		p2_health_bar.value = new_health


func _on_hit_confirmed(impact_position: Vector2, move_data: MoveData, attacker: Node, defender: Node, was_blocked: bool) -> void:
	spawn_damage_number(int(move_data.damage), impact_position, was_blocked)


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


# ── Round pips ──────────────────────────────────────────────
func _build_round_pips(container: HBoxContainer) -> void:
	for child in container.get_children():
		child.queue_free()
	for i in rounds_to_win:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(14, 14)
		pip.color = Color(0.3, 0.3, 0.3)
		container.add_child(pip)


func _refresh_pips(container: HBoxContainer, wins: int) -> void:
	var children := container.get_children()
	for i in children.size():
		children[i].color = Color(1.0, 0.85, 0.1) if i < wins else Color(0.3, 0.3, 0.3)


# ── Public round/match API — call these from wherever your round-flow
# logic lives (a game manager, etc). This UI doesn't decide when a round
# ends, it just displays the state you give it. ──────────────────────
func award_round_win(player_id: int) -> void:
	if player_1 and player_id == player_1.player_id:
		p1_wins += 1
		_refresh_pips(p1_round_pips, p1_wins)
	elif player_2 and player_id == player_2.player_id:
		p2_wins += 1
		_refresh_pips(p2_round_pips, p2_wins)


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


func reset_match() -> void:
	p1_wins = 0
	p2_wins = 0
	_build_round_pips(p1_round_pips)
	_build_round_pips(p2_round_pips)
	reset_round()
