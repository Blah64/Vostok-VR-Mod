# Road to Vostok VR Mod — CLAUDE.md

## Project Overview

A GDScript-only VR mod for **Road to Vostok** (Godot 4.6.1, Forward Mobile renderer, Vulkan 1.4).
No compiled extensions. The mod is a single autoload script injected via `override.cfg`.

**Key files:**
- `VR Mod/resources/vr_mod_init.gd` — source of truth, ALL edits go here
- After every edit, deploy with: `cp "VR Mod/resources/vr_mod_init.gd" "C:/Program Files (x86)/Steam/steamapps/common/Road to Vostok/vr_mod_init.gd"`
- `C:/Program Files (x86)/Steam/steamapps/common/Road to Vostok/vr_mod_debug.log` — diagnostic log
- `VR Mod/config/default_config.json` — user-tunable settings (holster positions, grip offsets, HUD settings, etc.)

## Critical Rules

1. **Always use `vr_mod_debug.log` for diagnostics** — never `godot.log` (truncates).
   Write via `FileAccess.open(path, FileAccess.READ_WRITE)` + `seek_end(0)` + `store_line()`.
2. **Deploy after every change** — the game loads from the game directory, not VR Mod/.
3. **Never add new MeshInstance3D nodes to XRController3D** — causes black HMD screen in Forward Mobile. Reuse existing nodes instead.
4. **process_priority = 1000** — mod runs after all game scripts; weapon/object position overrides stick.
5. **No freeze on grabbed RigidBody3D** — use position override + zero velocity each frame instead.
6. **No Co-Authored-By in commits** — user preference.
7. **No inline lambdas with semicolons** — GDScript 4 inline lambda only accepts one statement. Semicolons end the lambda body and leave unmatched parens → parse error → black HMD. Always use named methods or multi-line lambdas.

## Architecture

```
vr_mod_init.gd (autoload, extends Node)
  ├── XROrigin3D ("VRModOrigin")
  │   ├── XRCamera3D ("VRModCamera")
  │   ├── XRController3D ("LeftHand", tracker="left_hand")
  │   │   ├── Node3D "LeftHandModel" → Palm/Fingers/Thumb MeshInstance3Ds
  │   │   └── RayCast3D "GrabRayLeft" (1m, all layers)
  │   └── XRController3D ("RightHand", tracker="right_hand")
  │       ├── Node3D "RightHandModel" → Palm/Fingers/Thumb MeshInstance3Ds
  │       └── RayCast3D "GrabRayRight" (1m, all layers)
  ├── _laser_mesh: MeshInstance3D (CylinderMesh, dual-purpose)
  │     Red/green 1m = grab range indicator (hand empty, no menu)
  │     Blue 5m      = UI laser pointer    (menu/inventory/config open)
  └── SubViewport "VRHudViewport" — shares World2D with main viewport
        ↳ hud_mesh: MeshInstance3D (QuadMesh) — parented to xr_camera or scene root
```

## Scene Structure (game)

- Game camera: `/root/Map/Core/Camera` (Camera3D) — found by `_find_game_camera()`
- Weapon rig: `game_camera/Manager/<child 0>` (Node3D) — synced to controller each frame
- Weapon node chain: `Manager → weapon_rig → Handling → Sway → Noise → Tilt → Impulse → Recoil → Holder → [Weapon meshes]`
- Arm mesh: `MeshInstance3D` named `"Arms"` somewhere in weapon_rig subtree — surfaces 0-1 hidden via `_hide_arms_in_subtree()`
- Loose items: `RigidBody3D` with `collision_layer & 4 != 0`, direct children of `/root/Map/`, script `res://Scripts/Pickup.gd`, group `"Item"`, method `Interact()` adds to inventory
- HUD/UI: `game_camera/Core/UI` — shared via `World2D` into a `SubViewport`
- HUD node tree (key elements):
  - `Map/Core/UI/HUD/Stats/Vitals` — Health/Energy/Hydration/Mental/Temp (bottom-left, pos.x = -960 * spread)
  - `Map/Core/UI/HUD/Stats/Medical` — Status effect icons (bottom-right, pos.x = 960 * spread)
  - `Map/Core/UI/HUD/Info` — Map/FPS labels (top-left)
- LOS: `game_camera/LOS` — BoxMesh raycast the game uses to detect interactable objects

## State Machine (_phase)

```
0 = waiting_for_camera   poll every 30 frames for Camera3D
1 = xr_activating        wait XR_SETTLE_FRAMES (10) then _install_xr_rig()
2 = running              every frame: sync weapon, handle input, update HUD
```

## Holster State Machine (_holster_state)

```
UNARMED  grip near zone → _draw_weapon()  → DRAWN
DRAWN    grip release near own zone       → _holster_weapon() → UNARMED
DRAWN    grip release away from zone      → _lower_weapon()   → LOWERED
LOWERED  re-grip (weapon hand)            → _raise_weapon()   → DRAWN
LOWERED  grip near different zone         → _holster_weapon() + _draw_weapon() → DRAWN
```

## Holster Zones

Body-relative positions using **yaw-only** rotation from `xr_camera` (ignores head pitch/roll).
Offsets are runtime-mutable (loaded from config, tunable via F8 config screen).

```gdscript
const HOLSTER_ZONES := {
    1: {"name": "right_shoulder", "key": KEY_1},
    2: {"name": "right_hip",      "key": KEY_2},
    3: {"name": "left_hip",       "key": KEY_3},
    4: {"name": "chest",          "key": KEY_4},
}
var _holster_offsets := {           # tunable via config screen
    1: Vector3(0.25, -0.15,  0.20),
    2: Vector3(0.25, -0.55,  0.0),
    3: Vector3(-0.25, -0.55, 0.0),
    4: Vector3(0.0,  -0.15,  0.10),
}
var _holster_zone_radius := 0.20    # loaded from config: holsters.zone_radius
```

Weapon equip/unequip uses KEY injection (KEY_1–KEY_4). To avoid double-toggle on rapid
holster+redraw, holster KEY injection is delayed 0.15 s via `_pending_holster_key` —
`_draw_weapon()` cancels it if called within that window.

## Bag Zone (inventory pickup)

Reaching behind the right shoulder while holding a loose item and releasing grip calls
`item.Interact()` directly, adding the item to inventory.

```gdscript
var _bag_zone_offset := Vector3(0.15, -0.10, 0.35)  # runtime-tunable
var _bag_zone_radius := 0.35
```

Haptic buzz on zone entry (only when `_grabbed_object` is valid).

## NVG Zone (night vision toggle)

Reaching either hand above the head (in the NVG zone) and pulling the trigger injects
`MOUSE_BUTTON_XBUTTON1` (game's NVG keybind). Haptic buzz on zone entry.

```gdscript
var _nvg_zone_offset := Vector3(0.0, 0.30, 0.0)   # head-relative, above head
var _nvg_zone_radius := 0.25
var _hand_in_nvg_zone := {"left": false, "right": false}  # edge-detection
```

Zone position offset is head-world-space (no yaw rotation applied — straight up).
Tunable via F8 config → "NVG Zone" section (Radius + Y height). Persisted as
`nvg_zone.y` and `nvg_zone.radius` in `default_config.json`.

## Input Bindings

| Button | Action |
|--------|--------|
| Right trigger (DRAWN) | Fire weapon |
| Right grip (UNARMED, near zone) | Draw weapon from that slot |
| Right grip (UNARMED, no zone) | Grab nearby loose item |
| Right grip release (near own zone) | Holster weapon |
| Right grip release (away from zone) | Lower weapon |
| Support grip (DRAWN) | Two-hand aim |
| Support grip (near different zone) | Swap weapon |
| Support trigger (DRAWN, no grip) | Reload |
| Support trigger (DRAWN, grip held) | Toggle laser attachment → injects KEY_T |
| X (left, UNARMED or LOWERED) | Toggle standalone flashlight → MOUSE_BUTTON_XBUTTON2 |
| X (left, DRAWN) | Enter grip adjust mode |
| Trigger (either hand, above head, no grab) | Toggle NVG → MOUSE_BUTTON_XBUTTON1 |
| Left stick | Move (WASD) |
| Right stick L/R | Snap/smooth turn |
| Right stick U/D (config screen open) | Scroll config panel |
| Right stick U/D (variable scope, DRAWN) | Zoom in / out |
| Right stick click | Crouch |
| A (right) | Jump |
| A (right, adjust mode) | Save grip offsets to config |
| X (left, adjust mode) | Discard and exit adjust mode |
| Y (left) | Open/close inventory |
| B (right) | Interact with objects |
| Release grabbed item near bag zone | Add item to inventory |
| F8 | Toggle in-game VR config screen |
| F9 | Dump HUD node tree to vr_mod_debug.log |
| F10 | Dump weapon node tree (with attachmentData) to vr_mod_debug.log |

## Weapon Sync

`_sync_weapon_to_controller()` runs every frame in phase 2 **after** `_sync_origin_to_game()`:
- Gets `weapon_rig = game_camera/Manager/<child 0>`
- Sets `weapon_rig.global_basis` from controller basis + 180° Y flip + slot rotation offset
- Sets `weapon_rig.global_position = controller.global_position + aim_basis * slot_grip_offset`
- Two-hand mode: when `_support_grip_held`, aims toward off-hand controller
- Calls `_hide_arms_in_subtree(weapon_rig)` every frame to hide game arm meshes (surfaces 0-1 of "Arms" node only; hand meshes surfaces 2+ stay visible)

**Execution order matters:** `_sync_origin_to_game()` → `_process_input()` → `_sync_weapon_to_controller()` → `_update_hand_visibility()` → `_update_grabbed()`

## Per-Slot Grip Offsets

Each weapon slot has its own position (in aim-local space) and roll rotation:

```gdscript
var _slot_grip_offsets := { 1: ..., 2: ..., 3: ..., 4: ... }
var _slot_grip_rotations := { 1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0 }
```

Loaded from `config/default_config.json` under `weapon_offsets.{slot}.{x,y,z,rot}`.
Tuned live in-game via **grip adjust mode** (B button when DRAWN).

## Grab System

- `_try_grab(hand)`: picks up `RigidBody3D` with `collision_layer & 4` within 1m
- `_update_grabbed()`: overrides position/basis to hand model each frame, zeros velocity
- `_drop_grabbed()`: checks bag zone first → if in zone calls `_pickup_to_inventory()`, else throws
- `_pickup_to_inventory()`: calls `item.Interact()` directly (Pickup.gd), haptic confirmation
- Throw velocity: last 3 of 8 hand position samples × 1.5

## HUD System

- `SubViewport` shares `World2D` with main viewport → renders game's 2D UI without reparenting nodes
- Head-locked during gameplay (follows `xr_camera`); world-fixed during menus
- `_hud_smooth_follow`: when true, HUD lerps toward head each frame instead of snapping
- `_interface_open` detected by checking `game_camera/Core/UI` visibility each frame
- Laser pointer: raycasts from dominant controller → intersects HUD quad plane → warps OS mouse
- HUD spread: `_apply_hud_spread()` adjusts `Stats/Vitals` and `Stats/Medical` x positions directly

## Runtime-Tunable HUD Variables

```gdscript
var _hud_width := 2.0          # quad width × height (uniform scale)
var _hud_distance := 1.5       # metres from head when head-locked
var _hud_height_offset := -0.1 # vertical offset
var _hud_lr_offset := 0.0      # left/right offset
var _hud_smooth_follow := false # smooth lerp vs instant snap
var _hud_smooth_speed := 3.0
var _hud_spread := 1.0         # HUD element spread (Vitals/Medical x position multiplier)
var _menu_width := 3.0
var _menu_distance := 1.3
var _menu_lr_offset := 0.0
var _menu_laser_uv_x := 0.02   # laser UV correction for menu quad
var _menu_laser_uv_y := 0.06
```

## Scope PIP System

Variable-zoom scopes (Leopard, Vudu) render a Picture-in-Picture view via a `SubViewport`
+ `Camera3D` + `ShaderMaterial` on the scope mesh.

- `_scope_active` (bool): set when a scope attachment's SubViewport is detected
- `_scope_is_variable` (bool): set from `attachmentData.variable` at scope setup time
- `_scope_zoom_index` (int): current zoom level (0-based)
- `_scope_zoom_fovs` (Array[float]): per-level FOV values derived from `attachmentData.reticleSize`
- `_scope_zoom_reticle_scales` (Array[float]): per-level reticle UV scale values
- Right stick U/D cycles zoom when `_scope_active and _scope_is_variable and DRAWN`
- Zoom changes: set `weapon_rig.zoomLevel`, update scope camera FOV, update `reticle_scale` shader uniform
- `_scroll_cooldown` (0.3 s) gates rapid zoom changes
- `_cleanup_scope()` resets all scope vars on weapon lower/holster
- F10 (`_dump_weapon_tree()`) dumps full weapon node tree + `attachmentData` resource properties

## Equipment Toggles

| Action | Game Input | VR Binding |
|--------|-----------|-----------|
| Laser attachment (weapon) | KEY_T | Support trigger + grip while DRAWN |
| Flashlight (standalone) | MOUSE_BUTTON_XBUTTON2 | X (left) when UNARMED/LOWERED |
| Night vision goggles | MOUSE_BUTTON_XBUTTON1 | Trigger above head (NVG zone) |

## F8 Config Screen

- Opens a SubViewport-based panel (`_config_panel_vp` / `_config_panel_quad`) in world space
- Laser from dominant hand drives `_config_laser_pos` → `push_input()` to SubViewport
- Right stick Y scrolls the `CfgRoot/CfgScroll` ScrollContainer
- All buttons use `Callable(self, "named_method_string")` — no inline lambdas
- Steppers work by disconnecting/reconnecting button signals with updated value in bound args
- Save & Close calls `_save_full_config()` which writes the full config JSON
- Sections: Comfort, HUD (Gameplay), Menu/Inventory, Controls, Holster Zones, Bag Zone, NVG Zone

## Known Issues / Constraints

- Adding a `MeshInstance3D` directly to `XRController3D` causes black HMD (Forward Mobile bug). Always wrap in `Node3D` container OR reuse existing nodes.
- `godot.log` truncates on startup — all debug must go to `vr_mod_debug.log`.
- Weapon nodes load late (after camera); `_weapon_raise_timer` (3 s) detects load and auto-raises.
- Weapon can occasionally snap to camera position after rapid holster/draw sequences; holstering and re-drawing restores sync.
- GDScript parse errors produce no output (mod silently fails to load → black HMD). If black HMD occurs after a code change, revert and add changes incrementally.
