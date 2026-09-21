extends Node
# ── Per-instance events — player_id identifies which Player fired it ──
signal player_state_changed(player_id: int, new_state: int)
signal player_health_changed(player_id: int, new_health: float)
signal player_attack_started(player_id: int, move_name: String)
signal player_hit_landed(player_id: int, move_name: String, was_blocked: bool)
signal player_defeated(player_id: int)
# Fired by FightUI once the full death sequence (teeth bar effect, impact
# fade, popup) finishes playing. GameManager holds Engine.time_scale at 0
# from player_defeated until this fires, then unfreezes and ends the round.
signal death_sequence_finished(player_id: int)
# Not player-specific
signal camera_shake(amount: float)
signal npc_cheer
# Already carries attacker/defender node refs directly — no id needed
signal hit_confirmed(impact_position: Vector2, move_data: MoveData, attacker: Node, defender: Node, was_blocked: bool)
# ── Upgrade draft ──
# player_registered: a Player fires this in its own _ready() so GameManager
# can hold a live reference to it. This is what lets the draft apply an
# upgrade to the right node even after a scene change swaps the Player
# instance out — nothing needs an @export slot pointing across scenes.
signal player_registered(player_id: int, player_node: Node)
signal match_started                                          # reset/duplicate both pools
signal round_lost(loser_id: int)                               # who lost, needs to draft
# The loser's draft runs in two steps: the special-move cards first (Bite,
# Slam, Uppercut...), then everything else. Both offers ride on this one
# signal because both are drawn from that player's pool at round_lost time,
# before they have picked anything, which is what keeps step two's offer
# unaffected by what they choose in step one.
signal upgrade_draft_ready(player_id: int, special_offer: Array[UpgradeData], normal_offer: Array[UpgradeData])
signal upgrade_picked(player_id: int, upgrade: UpgradeData)    # UI -> pool manager
signal upgrade_applied(player_id: int, upgrade: UpgradeData)   # pool manager -> anyone (vfx, ui)
signal game_ended(loser_id: int)

# ── Continuous per-frame state, keyed by player_id ──
var player_position: Dictionary = {}     # int -> Vector2
var player_velocity: Dictionary = {}     # int -> Vector2
var player_is_airborne: Dictionary = {}  # int -> bool
var player_state: Dictionary = {}        # int -> int
var player_crouching: Dictionary = {}    # int -> bool
var player_blocking_low: Dictionary = {} # int -> bool
