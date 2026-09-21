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
@export var cards_offered: int = 4

var card_array: Array[String] = []      ## every .tres path found in card_resource_dir
var pools: Dictionary = {}              ## int player_id -> Array[String] remaining picks
var current_upgrades: Dictionary = {}   ## int player_id -> Array[String] picked so far this match

## Remembers the most recent draft so a draft-UI scene that finishes
## loading AFTER round_lost already fired (the normal case — whoever
## decides the round ended calls change_scene_to_file right after
## emitting) can still catch up instead of missing the signal entirely.
## Both steps' offers are cached, since the UI catches up on whichever
## step it is currently on.
var last_offer_player_id: int = -1
var last_special_offer: Array[UpgradeData] = []   ## step one: special-move cards
var last_offer: Array[UpgradeData] = []           ## step two: everything else

var card_hand  ## still set by the draft UI scene on _ready, kept for backwards compat


func _ready() -> void:
	_get_files_from_dir()
	EventBus.match_started.connect(_on_match_started)
	EventBus.round_lost.connect(_on_round_lost)
	EventBus.upgrade_picked.connect(_on_upgrade_picked)
	EventBus.player_registered.connect(_on_player_registered)
	
	GameManager.request_first_upgrade_arrays.connect(_on_array_request)


## Fresh copy of the full pool for both players. Call at the start of
## every match — upgrades don't carry over match to match.
func _on_match_started() -> void:
	pools[1] = card_array.duplicate()
	pools[2] = card_array.duplicate()
	current_upgrades[1] = []
	current_upgrades[2] = []


## Draws this round's offer for whichever player lost, then broadcasts it.
## Nothing calls into the draft UI directly — it just listens for this.
## Both steps are drawn here, before the player has picked anything, so
## step two's offer is fixed up front and can't be skewed by the step one
## pick.
func _on_round_lost(loser_id: int) -> void:
	var special_offer := _load_cards(_draw_special_from_pool(loser_id))
	var normal_offer := _load_cards(_draw_normal_from_pool(loser_id))
	last_offer_player_id = loser_id
	last_special_offer = special_offer
	last_offer = normal_offer
	EventBus.upgrade_draft_ready.emit(loser_id, special_offer, normal_offer)


func _load_cards(paths: Array[String]) -> Array[UpgradeData]:
	var upgrades: Array[UpgradeData] = []
	for path in paths:
		var upgrade: UpgradeData = load(path)
		if upgrade:
			upgrades.append(upgrade)
	return upgrades


## True for the cards that set or replace the player's selected special
## move (Bite, Slam, Uppercut today). These are the draft's whole first
## step; every other card belongs to the second. Put a new special card
## resource in card_resource_dir and it lands in step one automatically.
func is_special_move_card(upgrade: UpgradeData) -> bool:
	if upgrade == null or upgrade.effect_type != UpgradeData.EffectType.UNLOCK_MOVE:
		return false
	var move: MoveData = upgrade.unlocked_move
	return move != null and move.kind == MoveData.Kind.SPECIAL


## The card that grants the special a player already has equipped, or null
## if no card in the directory grants it. Step one always adds this, so
## "keep the special I've got" is a legal pick no matter what the pool
## happens to still contain.
##
## Matched on move_name rather than the MoveData instance: move_name is what
## this project already treats as a move's identity (locked_move_names,
## all_moves keys), and the player's own copies get duplicated per instance,
## so comparing instances would be comparing the wrong thing.
func get_keep_special_card(player_id: int) -> UpgradeData:
	var current := GameManager.get_selected_special(player_id)
	if current == null:
		return null
	for path in card_array:
		var upgrade: UpgradeData = load(path)
		if upgrade and is_special_move_card(upgrade) and upgrade.unlocked_move.move_name == current.move_name:
			return upgrade
	return null


## Step one: the special-move cards left in this player's pool, plus the
## keep card. Picking the keep card costs nothing and leaves the pool
## exactly as it is (see _on_upgrade_picked), so this step can be a
## required choice without ever being a punishment.
func _draw_special_from_pool(player_id: int) -> Array[String]:
	var pool: Array = pools.get(player_id, [])
	var special_paths: Array[String] = []
	for path in pool:
		var upgrade: UpgradeData = load(path)
		if is_special_move_card(upgrade):
			special_paths.append(path)
	special_paths.shuffle()

	var keep_card := get_keep_special_card(player_id)
	var keep_path: String = keep_card.resource_path if keep_card else ""
	# Only as many pool cards as fit alongside the keep card, and never the
	# keep card twice: if the current special's own card is still in the
	# pool, picking it from there is the same free keep, so it needs no
	# second copy in the hand.
	var room: int = cards_offered - (1 if keep_card else 0)
	var offered: Array[String] = []
	for path in special_paths:
		if offered.size() >= room:
			break
		if path == keep_path:
			continue
		offered.append(path)
	if keep_card:
		offered.append(keep_path)
	return offered


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
##
## Keeping the special you already have never reaches here: the draft UI
## deliberately doesn't emit for that pick, which is what makes it free.
## Nothing is recorded, nothing leaves the pool, and nothing gets replayed.
func _on_upgrade_picked(player_id: int, upgrade: UpgradeData) -> void:
	var picked_path := upgrade.resource_path
	print("[TRACE] upgrade_picked received | player=%d upgrade='%s' path='%s'" % [player_id, upgrade.name, picked_path])
	if picked_path == "":
		print("[TRACE] WARNING: upgrade.resource_path is empty — this upgrade won't survive the scene reload replay")
	current_upgrades[player_id].append(picked_path)
	_remove_from_pool(picked_path, player_id)

	if last_offer_player_id == player_id:
		last_offer_player_id = -1
		last_special_offer = []
		last_offer = []


## Step two: the non-special cards left in that player's pool, drawn by the
## same rules the draft has always used. Special cards are filtered out
## here because they were step one's business and must not appear twice in
## one draft.
##
## Bounded by the player's OWN pool size, not the master card_array size —
## the old version indexed with numbers up to card_array.size() even
## though it was reading from the (shrinking) per-player pool, which could
## pull an out-of-range index once enough cards had been picked.
func _draw_normal_from_pool(player_id: int) -> Array[String]:
	var pool: Array = pools.get(player_id, [])
	var normal_paths: Array[String] = []
	for path in pool:
		var upgrade: UpgradeData = load(path)
		if upgrade and not is_special_move_card(upgrade):
			normal_paths.append(path)
	normal_paths.shuffle()

	var count: int = min(cards_offered, normal_paths.size())
	var picked: Array[String] = []
	for i in count:
		picked.append(normal_paths[i])
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


## Function to, upon request from the pre-fight upgrade screen, get an array of all the upgrades and
## unlocks to add them to a set of arrays to be returned to the pre-fight upgrade screen so it can
## handle the pre fight upgrades
func _on_array_request() -> void:
	var offered_upgrades: Array[UpgradeData] = []
	var offered_unlocks: Array[UpgradeData] = []
	for path in card_array:
		var upgrade: UpgradeData = load(path)
		if upgrade == null:
			continue
		# Only the pre-fight visibility toggle gates this screen; the
		# mid-round draft draws straight from the pool and is unaffected.
		if not upgrade.show_in_pre_fight:
			continue
		match upgrade.effect_type:
			UpgradeData.EffectType.STAT_BOOST, UpgradeData.EffectType.MULTI_STAT_BOOST, UpgradeData.EffectType.MOVE_MODIFY:
				offered_upgrades.append(upgrade)
			UpgradeData.EffectType.UNLOCK_MOVE:
				offered_unlocks.append(upgrade)
	GameManager.return_first_upgrade_arrays.emit(offered_unlocks, offered_upgrades)
