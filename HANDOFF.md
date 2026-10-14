# Handoff: Creature Features (single player / UI work in progress)

Written at the end of a long session whose context filled up. Read this before touching
anything in the single-player or main-menu area. It records what is done, what is
outstanding, and the traps that have already cost this project several rounds.

## Project facts

- Godot 4.7, GDScript. Canvas is **640x360** (`project.godot`, `window/stretch/mode = canvas_items`),
  upscaled to 1920x1080. Anything you place is in 640x360 space.
- Autoloads: `SfxManager`, `HitEffectManager`, `GameManager`, `EventBus`, `UpgradePoolManager`,
  `SceneTransition`, `ComboManager`, `MultiplayerManager` (this last one is a **scene**, so
  `$TubeClient` inside it resolves).
- Palette is strictly **white, blue and black**. Blue accent is `cbdbfc` = `Color(0.79607844, 0.85882354, 0.9882353)`.
  No green, no amber. (Console `_dbg` colour tags don't count; `debug_color` on collision shapes is
  editor-only and also doesn't count.)
- UI font is `res://assets/card_assets/m3x6.ttf` (uid `uid://bc0aavecw2ud2`).
- Scene changes always go through `SceneTransition.change_scene(...)`.
- Tuning values are `@export` and set **in the scene**, not in code (see the rules below).
- Card / selection visuals reuse: `scripts/upgrade_card.gd`, `scripts/selector_anim.tres`
  (`selector_blink`), `scripts/selection_pointer.gd`, `scripts/menu_focus_emphasis.gd`,
  `scripts/control_prompts.gd` + `scenes/control_prompts.tscn`.

## The rules this project is held to

1. **Anything settable in the scene or Inspector must be set there.** If a value can't be seen and
   edited by selecting a node, it is set up wrong. Node references are stored as
   `some_export = NodePath("...")` in the `.tscn` (Godot resolves them for typed node exports).
2. **Assignments are the recurring failure.** Every bug in the last few passes that looked like
   "the feature isn't implemented" turned out to be a node reference pointing at the wrong thing or
   at nothing. When something doesn't appear or doesn't play, check the assignment first.
3. **Verify by reading the files back.** Do not assume a patch applied, and do not assume a previous
   fix worked. Read the file from disk after writing it.
4. Test in the editor. If a Godot binary is available, `godot --headless --check-only --script <file>`
   catches GDScript parse errors, which have been the other recurring time sink.

## What is done

**Main menu** (`scenes/main_menu.tscn`, `scripts/main_menu.gd`)
- Two button sets swapping in place: Play / Settings / Quit, then Practice Range / Online Multiplayer /
  Local Multiplayer / Back. Each button's art is a child `Art` Sprite2D (`z_index = -1`,
  `texture_filter` nearest, `scale` 0.5) inside a button whose four stylebox slots are all
  `StyleBoxEmpty`, so the **sprite** is what gets sized and positioned in the Inspector and no
  stylebox ever draws. Play and Back reuse the shared `Multiplayer.png` art. The button's own `text`
  still doubles the label baked into the art - blank whichever side you prefer.
- Practice Range routes to `scenes/single_player_select.tscn` with `GameManager.mode_id = 2`.
- NOTE: the button art already contains its own label, so the `text` field doubles it. Blank whichever
  side you prefer, in the Inspector.

**Single-player select** (`scenes/single_player_select.tscn`, `scripts/single_player_select.gd`)
- Practice Range's own input select, reached from the main menu with `GameManager.mode_id = 2`.
  `player_select.tscn` is now the two-player/online screen only: its single-player mode - and the
  `single_player_slot_offset` that slid the surviving creature's box to the middle of the screen - is
  gone.
- The layout keeps "where my input is" and "what my input has claimed" apart: the creature's **slot**
  is the box in the upper middle, and every detected input mode waits in its own outlined **bay** in
  the tray along the bottom. Up (or Select) takes the creature, Select locks it in (SELECTED! pops,
  the slot border turns blue, Start appears), Down or Special gives it back and returns the cursor to
  its bay. Only one cursor may hold it.
- Two `ControlPrompts` legends follow the device on the slot, or the most recently joined device:
  "ON THIS SCREEN" (Select/Deselect) and "IN THE LAB" (Normal/Special/Jump).
- Per-device input helpers as in `player_select.gd` (both keyboard layouts, every connected pad,
  d-pad and left stick). Enter counts as Select for a keyboard device and Escape backs out to the
  main menu; a pad unplugged drops its claim and its bay closes up.
- Everything is set in the scene - cursor size, `TrayBayTemplate` bay size and look, bay spacing, the
  `TrayArea` rect, border colours, pop timings. Only the bay row itself is built at runtime, from the
  template panel, because the number of devices is not known until someone presses a button.
- Deliberately not carried over from the multiplayer screen: the second creature's box, and the
  online cursor sync and its RPCs.

**Online multiplayer** (`scripts/MultiplayerManager.gd`, `scenes/MultiplayerManager.tscn`, `scenes/OnlineLobby.tscn`, `scripts/net_input.gd`)
- Transport is the **Tube** addon (`addons/tube`: WebRTC peer-to-peer, no server to deploy). Its `TubeContext`
  lives inline in `scenes/MultiplayerManager.tscn` and needs **tracker URLs and STUN servers** as well as the
  15-character app id: with no trackers configured, `create_session()` only opens a LAN-only session, which is
  why two machines on different networks could never find each other. The desktop half of that is
  `addons/webrtc_native` (Windows DLLs are present; without that GDExtension Tube fails with no error at all).
- Flow: `OnlineLobby` → the host shows the session id / the other player types it in → on `peer_connected`
  both peers set `GameManager.online_mode` + `online_player_id` (host = 1, client = 2) and change to
  `player_select.tscn`. The id is shown as soon as Host is pressed, not when a tracker answers: with trackers
  configured, "session created" only arrives once a tracker WebSocket is up.
- `player_select.tscn` syncs the other player's cursor with `_sync_cursor_state.rpc`, and
  `_start_online_match` sets **this** machine's device, calls `GameManager.bind_player_inputs()` (the online
  path never did, so the fight had no controls) and deliberately leaves the remote slot's actions unbound.
- `NetInput` (autoload) is the fight's input relay. Both machines simulate both characters, so the character
  belonging to the other machine has no device here; `testplayer1.gd` reads every button through
  `_held()` / `_pressed()`, which switch to `NetInput` while an online match is live. Every player's input -
  the local one included - is delayed by the same `delay_frames` on both machines, which is what keeps the two
  simulations applying the same press on the same frame. Raise `delay_frames` if the two players end up seeing
  different things, lower it if the controls feel sluggish.
- `GameManager.clear_online_state()` runs when a session closes and whenever the main menu loads, so a
  finished or abandoned online match cannot leave later local play stuck in the online branch.
- Known limits: no round-end/rematch RPC (each machine ends the round from its own identical simulation), no
  reconnect handling, no TURN server (symmetric-NAT pairs will still fail to connect), and both peers must be
  running the same build.

**Settings** (`scenes/settings.tscn`, `scenes/settings_tab_container.tscn`, `scripts/game_settings.gd`)
- `GameSettings` (autoload) owns the values, applies them and saves them to `user://settings.cfg` - the only
  file the game writes at runtime. Volume is stored as a **multiplier**: every sound in the project is
  hand-tuned, so the level each system starts with is captured as its reference and the row scales it
  (100% = the mix the project shipped with, 0% = silent).
- Tabs: **General** (window mode, V-Sync), **Sound** (sound effects, music, menu sounds), **Controls** (the
  current P1/P2 key bindings read from `GameManager.keyboard_layouts`, plus the pad mapping).
- Volume rows are a value plus two buttons rather than sliders, because a slider is the one control a d-pad
  cannot drive. `MenuTabLeft` / `MenuTabRight` switch tabs; `MenuSelect` confirms, `MenuBack` leaves.
- Music has no audio bus, so `GameManager.set_music_volume()` sets the music player's `volume_db` directly.

**Training dummy** (`scenes/labbing_dummy.tscn`, `scripts/labbing_dummy.gd`)
- Three block states (none / crouch / stand) with the player's rules: overhead beats a crouch block,
  low beats a stand block, mid is blocked by either, not blocking blocks nothing. Mismatched attacks
  are blocked and deal no damage. Blocked hits go out as `player_hit_landed(..., true)` and
  `hit_confirmed(..., true)`.
- Uses the **player's own barrier sprites** (`blockwarningeffct2.png`, values copied from
  `player.tscn`), driven by the same phase sequence as `PlayerVisuals.update_block_warning()`
  (`block_warning_start_frames = [0, 1]`, `block_warning_frame_duration = 0.04`,
  `block_warning_end_frame = 2`). The horse's own colour is never used to show blocking.
- `cycle_block_states = true` is set on the dummy node in its scene; cycling is permanent by design
  now, and the practice menu no longer touches it.
- Hit animation: `_playing_hit` guard stops any rest pose being played over `take_hit`. This was the
  cause of the hit animation appearing not to play (the damage readout was calling
  `_apply_state_visuals()` on the same frame).
- Damage readout: per-hit numbers float from a template inside a `CanvasLayer` named `DamageNumbers`
  (so they draw above the level art), and a separate prominent `TotalDamageLabel` shows cumulative
  damage, framed by a `TotalDamageFrame` sprite using the Quit button art. That art has "Quit" baked
  into it, so it reads through the numbers - swap the texture on that node if it looks wrong.
- `player_id` is 2 (it used to be 3, which systems assuming 1/2 do not understand).
- The horse sheet (`assets/Horse-Sheet.png`) only has `default` and `take_hit`; there is no crouch or
  block artwork, so the barriers carry the blocking read.

**Practice menu** (`scenes/singleplayer_upgrade_screen.tscn`, `scripts/singleplayer_upgrade_screen.gd`)
- Two card columns (unlocks, upgrades) plus a third focus row, device-aware input via the same helper
  pattern as the other menus, Enter confirms as well as the device's Normal button.
- The cycling toggle and fixed-state picker are hidden now that cycling is permanent.
- Owned-card display works (`card_default_scale` is captured from the card scene).

**Fixes carried in from earlier passes**: projectile special works in single player (its `Player`-typed
parameters/members were rejecting the dummy - now `Node2D` with guards); projectile one-per-player with
the old one playing its death; uppercut launcher grace frame; aerial gates cleared at both ends of a
jump; air control additive; pause menu selector retries when a target isn't visible yet
(`_needs_refresh` in `selection_pointer.gd`).

## Outstanding (the user's current list)

1. ~~Cycling permanently on~~ - done.
2. Per-hit numbers: readable, positioned, tweened. Duration is 1.15s; the font is still 20 on
   `DamageNumbers/FloatLabelTemplate` (a bump to 24 didn't apply). Consider placing the number at the
   attacker's hitbox rather than a fixed offset.
3. Total damage prominence - done (framed label). Re-check the frame art choice.
4. **Tutorial instructions** - `scenes/single_player_tutorial_background.tscn` holds them. **Read this
   file before editing it: it has been modified outside the agent passes and has never been inspected
   by an agent.** Needs: combat controls, card select/deselect, menu navigation, damage numbers
   explained, "Enter opens the menu" (implement `ui_accept` alongside the existing
   `UpgradeMenuToggle` check in `singleplayer_upgrade_screen.gd`, plus the pad equivalent), and the
   text must match what actually works.
5. **Large Quit button on the tutorial background**, separate from the sprite framing the damage display.
6. **Practice menu reorg**: dummy selection on top, other options beneath, cards below; selector follows
   the active section; opacity distinguishes inactive options; multiplayer-style selection borders on
   chosen cards; finish the floating card animation.
7. **Special input deselects cards**, with the control shown on screen.
8. **Back button** at the bottom of the practice menu, main-menu style.
9. **Input selection** reworked to match multiplayer (see the note under single-player select).
10. Keep the palette, reuse systems, test in game.

## Traps already hit (do not repeat)

- A global `class_name` can fail to resolve if the project's class cache is stale
  (`.godot/global_script_class_cache.cfg` had no `Dummy` entry, so `p is Dummy` failed to compile).
  Prefer duck-typing - `p.has_method("take_hit")` - for the dummy/player distinction; that is what the
  code does now.
- GDScript: `var x := something.dynamic_property` cannot infer a type. Annotate explicitly
  (`var move : MoveData = ...`).
- Patches written through shell scripts can silently skip when an anchor doesn't match, and one pass
  introduced a double-tab indent that produced `Expected statement, found "Indent"`. Always read back.
- The editor can rewrite open files; if the game behaves as if a change didn't land, save/reload in
  Godot and re-check.
