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
  Local Multiplayer / Back. Buttons carry their art via `StyleBoxTexture` sub-resources in the scene,
  plus `text` using the project font, sizes, colours and `texture_filter`. Play and Back reuse the
  shared `Multiplayer.png` art.
- Practice Range routes to `scenes/single_player_select.tscn` with `GameManager.mode_id = 2`.
- NOTE: the button art already contains its own label, so the `text` field doubles it. Blank whichever
  side you prefer, in the Inspector.

**Single-player select** (`scenes/single_player_select.tscn`, `scripts/single_player_select.gd`)
- One creature slot, any input mode joins by pressing a button, Normal/Enter confirms (a pop on the
  READY label plus a border colour change), Special unlocks, Start binds the device and enters the lab.
- Per-device input helpers (keyboard layouts + d-pad/stick), Escape backs out, pad unplug releases.
- This screen is a **custom one-slot version of `player_select.gd`**. The requested change is to
  delete it and reuse `player_select.gd` with the second slot hidden, which is what makes
  browse/assign/confirm/change-your-mind behave identically to local multiplayer. Not done.

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
