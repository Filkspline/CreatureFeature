class_name PlayerInputDevice
extends RefCounted

# ──────────────────────────────────────────────────────────────────
#  PlayerInputDevice
#
#  Plain data object (RefCounted, not a scene Node - no reason to pay
#  for a tree entry just to carry a few fields) representing one
#  physical input source a player can be controlling with: either one
#  of the two fixed keyboard key sets, or a specific connected joypad.
#
#  Keyboard devices carry their own native_action_suffix ("P1"/"P2")
#  because the two keyboard key sets are physically distinct and
#  already authored that way in the InputMap - a keyboard device
#  always drives the same named actions no matter which player slot
#  claims it.
#
#  Joypad devices carry no such suffix. Which physical device drives
#  "player 1" vs "player 2" is decided by which character slot its
#  cursor locks on the select screen (slot 1 -> player 1, slot 2 ->
#  player 2) - see player_select.gd. This is what lets any connected
#  controller end up on either player side instead of being hardcoded.

enum Kind { KEYBOARD, JOYPAD }

var kind : Kind
var device_id : int = -1 # joypad device id from Input.get_connected_joypads(), unused for keyboard
var display_name : String = ""
var native_action_suffix : String = "" # "P1" or "P2", keyboard only


static func make_keyboard(display_name : String, native_action_suffix : String) -> PlayerInputDevice:
	var device := PlayerInputDevice.new()
	device.kind = Kind.KEYBOARD
	device.display_name = display_name
	device.native_action_suffix = native_action_suffix
	return device


static func make_joypad(device_id : int) -> PlayerInputDevice:
	var device := PlayerInputDevice.new()
	device.kind = Kind.JOYPAD
	device.device_id = device_id
	device.display_name = Input.get_joy_name(device_id)
	return device
