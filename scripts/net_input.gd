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

## The input delay every player's presses are held back by, in frames, this
## machine's included. Set from measured latency when a match starts and then
## kept: a delay that keeps moving is worse than one a frame too generous,
## because moving it shifts the timing of every press already in flight.
##
## Both machines use the same value - the host picks it and tells the other -
## because it is the number of frames the two simulations have to agree on.
@export var delay_frames : int = 5

@export_group("Delay from latency")
## Bounds on the delay. The point of measuring is to sit at the bottom of this
## range on a good connection - 2 frames is a same-machine or LAN match - and to
## climb only as far as a bad one actually needs.
@export var min_delay_frames : int = 2
@export var max_delay_frames : int = 12

## Added to half the measured round trip before rounding up. This is the jitter
## headroom, and it is the part that decides whether a press arrives before the
## frame that needs it.
@export var jitter_margin_frames : int = 2

## How much of each new measurement to take. A single sample is as likely to be
## a hitch as a measurement, so the estimate moves a quarter of the way at a
## time.
@export var ping_smoothing : float = 0.25

## How often the round trip is measured, in seconds. Pings are unreliable on
## purpose: a lost one just means the estimate is a little older.
@export var ping_interval_seconds : float = 0.5

## Print every relayed frame. Noisy, but it is how you check packets arrive.
## The line it prints per packet reads "N frames from now", which is the delay
## that packet is actually being applied with - the number to watch if a fight
## ever feels slow to respond.
@export var log_frames : bool = false

@export_group("Resync")
## How often the host re-sends the match's health and round counts, in seconds.
## The two machines simulate the fight independently, so they can drift apart -
## and a round that ends differently on the two screens is the one desync a
## player actually sees.
@export var state_sync_resend_seconds : float = 0.25

@export_group("Relaying")
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
## Seconds since the last resync was sent.
var _sync_timer : float = 0.0
## Smoothed round trip in frames, and time since the last ping.
var _rtt_frames : float = 0.0
var _ping_timer : float = 0.0
## Whether this match has settled on a delay yet.
var _delay_decided : bool = false


func _ready() -> void:
	_clear()
	# A new opponent means a new frame-offset to work out.
	MultiplayerManager.peer_connected.connect(_on_peer_connected)


func _physics_process(delta: float) -> void:
	if not active():
		return
	# Autoloads process before the scene, so the buttons for this frame are in
	# place before either character reads them.
	_tick += 1
	_apply_scheduled()
	_sample_and_send()

	_ping_timer += delta
	if _ping_timer >= ping_interval_seconds:
		_ping_timer = 0.0
		_measure_latency()

	_sync_timer += delta
	if _sync_timer >= state_sync_resend_seconds:
		_sync_timer = 0.0
		_send_state_snapshot()


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


# ── Resync ──
# Both machines simulate the fight, so they can drift: one can land the killing
# hit a frame before the other, and then the two screens disagree about who won
# the round. Instead of trying to make two independent simulations perfectly
# identical, the host is treated as the authority for the two values that decide
# a round - health and rounds won - and re-sends them a few times a second, so a
# fight that drifted is pulled back together rather than ending differently.
#
# Positions are deliberately NOT synced. They are driven every frame by input
# both machines already agree on, so they track each other closely, and snapping
# them would show as a stutter to fix a difference nobody can see. Health is the
# one that changes who wins.

func _send_state_snapshot() -> void:
	# The session's server peer is player 1, and is the authority.
	if not multiplayer.is_server():
		return
	_state_snapshot.rpc(
		_health_of(GameManager.p1_node),
		_health_of(GameManager.p2_node),
		GameManager.p1_rounds_won,
		GameManager.p2_rounds_won
	)


# "authority", not "any_peer": the host is the node's multiplayer authority, so
# only the machine that owns the truth is allowed to send this.
@rpc("authority", "call_remote", "reliable")
func _state_snapshot(p1_health: float, p2_health: float, p1_rounds: int, p2_rounds: int) -> void:
	_apply_health(GameManager.p1_node, p1_health)
	_apply_health(GameManager.p2_node, p2_health)
	GameManager.p1_rounds_won = p1_rounds
	GameManager.p2_rounds_won = p2_rounds


# -1.0 means "there is no such character here to sync", which is true between
# rounds, while a scene change is in flight.
func _health_of(player_node: Node) -> float:
	if player_node == null or not player_node.has_method("set_health_from_network"):
		return -1.0
	var health : float = player_node.get("current_health")
	return health


# Asked for rather than assumed, the same way the rest of the project treats
# anything that can take a hit: the node arrives as a plain Node.
func _apply_health(player_node: Node, health: float) -> void:
	if health < 0.0:
		return
	if player_node != null and player_node.has_method("set_health_from_network"):
		player_node.call("set_health_from_network", health)


# ── Input delay from measured latency ──
# A fixed delay is either too small - the other player's press arrives after the
# frame that needed it, and the two machines disagree about that frame - or too
# large, and the game feels heavy for no reason. So the delay is derived from
# the round trip actually being made: half of it is the one-way trip a press has
# to survive, plus a margin for jitter, rounded up to whole frames.
#
# The HOST decides it and tells the other machine, because both simulations have
# to hold inputs back by the same number of frames. A delay differing by one
# frame between the machines would be exactly the disagreement the delay is
# there to prevent.
#
# It is only ever raised during a match, never lowered: the first estimate can
# be too optimistic and needs to loosen, but tightening mid-match would shift
# the timing of presses already in flight for no gain the player can feel.
#
# Measured in frames rather than milliseconds, so it needs no wall clock and
# agrees with the numbering the inputs themselves use.

func _measure_latency() -> void:
	_ping.rpc(_tick)


@rpc("any_peer", "call_remote", "unreliable")
func _ping(their_frame: int) -> void:
	if not active():
		return
	# Straight back: the sender measures the trip on its own counter, so nothing
	# here needs to know anything about their clock.
	_pong.rpc(their_frame)


@rpc("any_peer", "call_remote", "unreliable")
func _pong(our_frame: int) -> void:
	if not active():
		return
	var sample := float(_tick - our_frame)
	if _rtt_frames <= 0.0:
		_rtt_frames = sample
	else:
		_rtt_frames = lerpf(_rtt_frames, sample, ping_smoothing)
	if multiplayer.is_server():
		_choose_delay()


## Turns the measured round trip into a delay, and tells the other machine when
## it changes. Host only.
func _choose_delay() -> void:
	var wanted : int = clampi(
		int(ceil(_rtt_frames * 0.5)) + jitter_margin_frames,
		min_delay_frames,
		max_delay_frames
	)
	if not _delay_decided:
		_delay_decided = true
		delay_frames = wanted
		_set_delay.rpc(wanted)
		return
	if wanted > delay_frames:
		delay_frames = wanted
		_set_delay.rpc(wanted)


@rpc("authority", "call_remote", "reliable")
func _set_delay(frames: int) -> void:
	delay_frames = clampi(frames, min_delay_frames, max_delay_frames)
	_delay_decided = true
