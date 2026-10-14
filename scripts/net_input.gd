extends Node

# ──────────────────────────────────────────────────────────────────
#  NetInput (autoload)
#
#  The input relay for online matches.
#
#  Both machines simulate BOTH characters, exactly as they do offline, so they
#  have to apply the same buttons on the same frame or the two fights drift
#  apart and the players stop seeing the same match. Offline each character
#  reads its own actions straight from the InputMap, and online that cannot
#  work: the character belonging to the other machine has no device bound on
#  this one - player select deliberately leaves the remote slot's actions empty
#  - so its actions would read as "nothing held" forever and the opponent would
#  stand still and never press anything.
#
#  So while an online match is running, every player's buttons come from here:
#
#    * this machine samples its own device every physics frame,
#    * sends that frame's buttons to the other machine, and
#    * applies every player's buttons delay_frames later, its own included.
#
#  The delay is the point. A press is applied on the same logical frame on both
#  machines, instead of immediately here and one network trip later there. The
#  two frame counters are aligned once, from the first packet, so it does not
#  matter that the two machines did not reach the fight on the same frame.
#
#  Offline this does nothing at all: active() is false, and the player script
#  reads the InputMap exactly as it always did.
# ──────────────────────────────────────────────────────────────────

## Buttons relayed, by their InputMap base names ("LeftP1", "NormalP2", ...).
const BASES: Array[String] = ["Left", "Right", "Up", "Down", "Normal", "Special", "Jump"]

## How many frames every player's input is delayed by, this machine's included.
## It has to cover one network trip plus the difference between when the two
## machines started counting, so: raise it if the two players end up seeing
## different things, lower it if the controls feel sluggish.
@export var delay_frames : int = 5

## Print every relayed frame. Noisy, but it is how you check packets arrive.
## The line it prints per packet reads "N frames from now", which is the delay
## that packet is actually being applied with - the number to watch if a fight
## ever feels slow to respond.
@export var log_frames : bool = false

## How much longer than delay_frames a relayed press may ever wait before it is
## dropped instead of obeyed. This is the safety net: the two machines' frame
## counters do NOT stay in step (one window unfocused, one instance behind on
## frames, a pause on one side), and an estimate of the difference between them
## that is not re-checked turns straight into input delay. The bound is what
## stops that becoming a fight that reacts seconds late.
@export var extra_slack_frames : int = 2

var _tick : int = 0
## tick -> { player_id: mask }, applied when _tick reaches that tick.
var _scheduled : Dictionary = {}
## player_id -> the mask applied for this tick, and for the previous tick, which
## is what makes "just pressed" work for a relayed player.
var _held : Dictionary = {}
var _previous : Dictionary = {}
## Aligns the two machines' frame counters, worked out from the first packet.
## Either machine can be ahead, so this can be negative.
var _remote_clock_offset : int = 0
var _clock_aligned : bool = false
var _packets : int = 0


func _ready() -> void:
	_clear()
	# A new opponent means a new frame-offset to work out.
	MultiplayerManager.peer_connected.connect(_on_peer_connected)


func _physics_process(_delta: float) -> void:
	if not active():
		return
	# Autoloads process before the scene, so the buttons for this frame are in
	# place before either character reads them.
	_tick += 1
	_apply_scheduled()
	_sample_and_send()


# ── What the player script asks ──

## True while an online match is being played on this machine.
func active() -> bool:
	if not GameManager.online_mode:
		return false
	if GameManager.online_player_id != 1 and GameManager.online_player_id != 2:
		return false
	return multiplayer.has_multiplayer_peer()


## True when this character's buttons are relayed rather than read from a device
## plugged into this machine. Online that is every character, the local one
## included: both machines have to delay it by the same amount, or the fights
## drift apart.
func active_for(_player_id: int) -> bool:
	return active()


## Whether this player is holding a relayed button on this frame.
func held(player_id: int, base: String) -> bool:
	var index := BASES.find(base)
	if index < 0:
		return false
	var mask : int = _held.get(player_id, 0)
	return (mask & (1 << index)) != 0


## Whether this player pressed a relayed button on this frame, in the frame the
## relay actually applies it on - which is the frame the character's own timers
## and buffers are counting on.
func just_pressed(player_id: int, base: String) -> bool:
	var index := BASES.find(base)
	if index < 0:
		return false
	var now : int = _held.get(player_id, 0)
	var before : int = _previous.get(player_id, 0)
	var bit := 1 << index
	return (now & bit) != 0 and (before & bit) == 0


## How many relayed packets have arrived. Useful for checking the link is alive.
func packet_count() -> int:
	return _packets


## Forget the buttons being held, so a new match cannot start with the last
## one's buttons stuck down. The frame counter and the clock alignment are
## deliberately KEPT: they are what keeps the two machines applying the same
## frame, they stay valid for the whole session, and re-aligning them mid-session
## would move every following frame. The fight scene calls this as it loads.
func reset() -> void:
	_clear()


func _on_peer_connected(_peer_id) -> void:
	_clock_aligned = false
	_clear()


# ── Relaying ──

func _sample_and_send() -> void:
	var player_id := GameManager.online_player_id
	var mask := 0
	for i in BASES.size():
		if Input.is_action_pressed(_action(BASES[i], player_id)):
			mask |= 1 << i
	_schedule(_tick + delay_frames, player_id, mask)
	_send_input.rpc(_tick, mask)


func _action(base: String, player_id: int) -> StringName:
	return StringName("%sP%d" % [base, player_id])


func _schedule(tick: int, player_id: int, mask: int) -> void:
	var slot : Dictionary = _scheduled.get(tick, {})
	slot[player_id] = mask
	_scheduled[tick] = slot


func _apply_scheduled() -> void:
	# Frames that have already gone by are never applied: a stall or a pause
	# must not make a stale press fire later. Neither is anything scheduled
	# further ahead than the relay is allowed to delay - that only happens once
	# the two counters have drifted apart, and obeying those frames is exactly
	# the multi-second lag the bound exists to prevent.
	var latest_allowed : int = _tick + delay_frames + extra_slack_frames
	for tick in _scheduled.keys():
		if tick < _tick or tick > latest_allowed:
			_scheduled.erase(tick)

	var slot : Dictionary = _scheduled.get(_tick, {})
	if slot.is_empty():
		return
	for player_id in slot:
		_previous[player_id] = _held.get(player_id, 0)
		_held[player_id] = slot[player_id]


@rpc("any_peer", "call_remote", "reliable")
func _send_input(tick: int, mask: int) -> void:
	if not active():
		return

	var sender := multiplayer.get_remote_sender_id()
	# The session's server peer is always 1 and is player 1, so the sender's id
	# says which character these buttons belong to.
	var player_id := 1 if sender == 1 else 2
	if player_id == GameManager.online_player_id:
		return

	# The difference between the two counters is re-measured on EVERY packet
	# instead of being trusted from the first one. The two machines do not tick
	# at the same rate for long: one window is unfocused, one instance is behind
	# on frames, someone pauses. A difference measured once is only correct
	# until then, and afterwards every frame of error is applied input delay -
	# which is how a five-frame relay turned into a fight that reacted seconds
	# late on whichever machine had fallen behind.
	_remote_clock_offset = _tick - tick
	_clock_aligned = true

	# ...and the result is bounded, so a wrong estimate can never hold a press
	# back for longer than the relay is meant to delay anything at all. Losing
	# the odd frame of timing is a much better failure than a fight that stops
	# responding.
	var apply_at : int = tick + _remote_clock_offset + delay_frames
	var latest_allowed : int = _tick + delay_frames + extra_slack_frames
	if apply_at > latest_allowed:
		apply_at = latest_allowed
	if apply_at <= _tick:
		# Arrived too late to be used on its own frame - typically the first
		# packet or a hitch. Use it on the next frame rather than dropping it,
		# so a press is never lost outright.
		apply_at = _tick + 1
	_schedule(apply_at, player_id, mask)
	_packets += 1

	if log_frames:
		print("[NetInput] their frame %d -> our frame %d (in %d frames, offset %d)" % [
			tick, apply_at, apply_at - _tick, _remote_clock_offset
		])


func _clear() -> void:
	_scheduled.clear()
	_held.clear()
	_previous.clear()
