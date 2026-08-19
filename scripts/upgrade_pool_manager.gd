extends Node

# ──────────────────────────────────────────────────────────────────
#  UpgradePoolManager (Autoload)
#
#  Owns both players' upgrade pools and the whole pick -> apply flow.
#  Everything comes in/out through EventBus, so the fight scene and the
#  draft UI scene never need a direct reference to each other or to this.
#
#  player_id is 1 or 2 throughout — replaces the old p1_selecting bool,
#  which had no way to extend past two hardcoded branches.

@export_group("Card source")
@export_dir var card_resource_dir: String = "res://scripts/card_resource_files/"

@export_group("Draft")
@export var cards_offered: int = 5

var card_array: Array[String] = []      ## every .tres path found in card_resource_dir
var pools: Dictionary = {}              ## int player_id -> Array[String] remaining picks
var current_upgrades: Dictionary = {}   ## int player_id -> Array[String] picked so far this match

## Remembers the most recent draft so a draft-UI scene that finishes
## loading AFTER round_lost already fired (the normal case — whoever
## decides the round ended calls change_scene_to_file right after
## emitting) can still catch up instead of missing the signal entirely.
var last_offer_player_id: int = -1
var last_offer: Array[UpgradeData] = []

var card_hand  ## still set by the draft UI scene on _ready, kept for backwards compat


func _ready() -> void:
	_get_files_from_dir()
	EventBus.match_started.connect(_on_match_started)
	EventBus.round_lost.connect(_on_round_lost)
	EventBus.upgrade_picked.connect(_on_upgrade_picked)
	EventBus.player_registered.connect(_on_player_registered)


## Fresh copy of the full pool for both players. Call at the start of
## every match — upgrades don't carry over match to match.
func _on_match_started() -> void:
	pools[1] = card_array.duplicate()
	pools[2] = card_array.duplicate()
	current_upgrades[1] = []
	current_upgrades[2] = []


## Draws this round's offer for whichever player lost, then broadcasts it.
## Nothing calls into the draft UI directly — it just listens for this.
func _on_round_lost(loser_id: int) -> void:
	var paths := _draw_from_pool(loser_id)
	var offered: Array[UpgradeData] = []
	for path in paths:
		var upgrade: UpgradeData = load(path)
		offered.append(upgrade)
	last_offer_player_id = loser_id
	last_offer = offered
	EventBus.upgrade_draft_ready.emit(loser_id, offered)


## The fight scene reloads with a brand new Player at base stats every
## round, so whatever this player has picked so far this match needs to
## be replayed onto it here — this is the only place upgrades actually
## get applied. Trying to apply directly at pick time was the actual bug:
## by the time a pick happens, the Player that existed when the draft
## opened has already been freed by the scene change into the draft UI.
func _on_player_registered(player_id: int, player_node: Node) -> void:
	var picked: Array = current_upgrades.get(player_id, [])
	print("[TRACE] player_registered for player %d | replaying %d picked upgrade(s): %s" % [player_id, picked.size(), picked])
	for path in picked:
		var upgrade: UpgradeData = load(path)
		if upgrade == null:
			print("[TRACE] FAILED to load upgrade at path: %s" % path)
			continue
		upgrade.apply_to(player_node)
		EventBus.upgrade_applied.emit(player_id, upgrade)


## The draft UI fires upgrade_picked once a card is confirmed. This just
## records the pick and removes it from the pool — actually applying it
## happens later, in _on_player_registered, once there's a live Player
## instance to apply it to.
func _on_upgrade_picked(player_id: int, upgrade: UpgradeData) -> void:
	var picked_path := upgrade.resource_path
	print("[TRACE] upgrade_picked received | player=%d upgrade='%s' path='%s'" % [player_id, upgrade.name, picked_path])
	if picked_path == "":
		print("[TRACE] WARNING: upgrade.resource_path is empty — this upgrade won't survive the scene reload replay")
	current_upgrades[player_id].append(picked_path)
	_remove_from_pool(picked_path, player_id)

	if last_offer_player_id == player_id:
		last_offer_player_id = -1
		last_offer = []


## Picks cards_offered unique cards from that player's remaining pool.
## Bounded by the player's OWN pool size, not the master card_array size —
## the old version indexed with numbers up to card_array.size() even
## though it was reading from the (shrinking) per-player pool, which could
## pull an out-of-range index once enough cards had been picked.
func _draw_from_pool(player_id: int) -> Array[String]:
	var pool: Array = pools.get(player_id, [])
	var count: int = min(cards_offered, pool.size())
	var indices: Array = range(pool.size())
	indices.shuffle()

	var picked: Array[String] = []
	for i in indices.slice(0, count):
		picked.append(pool[i])
	return picked


## Grabs every .tres file from card_resource_dir into card_array.
func _get_files_from_dir() -> void:
	card_array.clear()
	var dir := DirAccess.open(card_resource_dir)
	if dir == null:
		push_error("UpgradePoolManager: couldn't open %s" % card_resource_dir)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			card_array.append(card_resource_dir + file_name)
		file_name = dir.get_next()


func _remove_from_pool(tres_path: String, player_id: int) -> void:
	var pool: Array = pools.get(player_id, [])
	var idx := pool.find(tres_path)
	if idx != -1:
		pool.remove_at(idx)
