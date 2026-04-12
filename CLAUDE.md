# Road to Vostok VR Mod — CLAUDE.md

## Project Overview

A GDScript-only VR mod for **Road to Vostok** (Godot 4.6.1, Forward Mobile renderer, Vulkan 1.4).
No compiled extensions. The mod is a single autoload script injected via `override.cfg`.

**Key files:**
- `VR Mod/resources/vr_mod_init.gd` — source of truth, ALL edits go here
- After every edit, deploy with: `cp "VR Mod/resources/vr_mod_init.gd" "C:/Program Files (x86)/Steam/steamapps/common/Road to Vostok/vr_mod_init.gd"`
- `C:/Program Files (x86)/Steam/steamapps/common/Road to Vostok/vr_mod_debug.log` — diagnostic log
- `VR Mod/config/default_config.json` — user-tunable settings (holster radius, per-slot grip offsets)

## Critical Rules

1. **Always use `vr_mod_debug.log` for diagnostics** — never `godot.log` (truncates).
   Write via `FileAccess.open(path, FileAccess.READ_WRITE)` + `seek_end(0)` + `store_line()`.
2. **Deploy after every change** — the game loads from the game directory, not VR Mod/.
3. **Never add new MeshInstance3D nodes to XRController3D** — causes black HMD screen in Forward Mobile. Reuse existing nodes instead.
4. **process_priority = 1000** — mod runs after all game scripts; weapon/object position overrides stick.
5. **No freeze on grabbed RigidBody3D** — use position override + zero velocity each frame instead.
6. **No Co-Authored-By in commits** — user preference.

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
  └── _laser_mesh: MeshInstance3D (CylinderMesh, dual-purpose)
        Red/green 1m = grab range indicator (hand empty, no menu)
        Blue 5m      = UI laser pointer    (menu/inventory open)
```

## Scene Structure (game)

- Game camera: `/root/Map/Core/Camera` (Camera3D) — found by `_find_game_camera()`
- Weapon rig: `game_camera/Manager/<child 0>` (Node3D) — synced to controller each frame
- Weapon node chain: `Manager → weapon_rig → Handling → Sway → Noise → Tilt → Impulse → Recoil → Holder → [Weapon meshes]`
- Arm mesh: `MeshInstance3D` named `"Arms"` somewhere in weapon_rig subtree — surfaces 0-1 hidden via `_hide_arms_in_subtree()`
- Loose items: `RigidBody3D` with `collision_layer & 4 != 0`, direct children of `/root/Map/`, script `res://Scripts/Pickup.gd`, group `"Item"`, method `Interact()` adds to inventory
- HUD/UI: `game_camera/Core/UI` — shared via `World2D` into a `SubViewport`
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

```gdscript
const HOLSTER_ZONES := {
    1: {"name": "right_shoulder", "offset": Vector3(0.25, -0.15,  0.20), "key": KEY_1},
    2: {"name": "right_hip",      "offset": Vector3(0.25, -0.55,  0.0),  "key": KEY_2},
    3: {"name": "left_hip",       "offset": Vector3(-0.25, -0.55, 0.0),  "key": KEY_3},
    4: {"name": "chest",          "offset": Vector3(0.0,  -0.15,  0.10), "key": KEY_4},
}
var _holster_zone_radius := 0.20  # loaded from config: holsters.zone_radius
```

Weapon equip/unequip uses KEY injection (KEY_1–KEY_4). To avoid double-toggle on rapid
holster+redraw, holster KEY injection is delayed 0.15 s via `_pending_holster_key` —
`_draw_weapon()` cancels it if called within that window.

## Bag Zone (inventory pickup)

Reaching behind the right shoulder while holding a loose item and releasing grip calls
`item.Interact()` directly, adding the item to inventory.

```gdscript
const BAG_ZONE_OFFSET := Vector3(0.15, -0.10, 0.35)  # right-back, upper body
const BAG_ZONE_RADIUS := 0.35
```

Haptic buzz on zone entry (only when `_grabbed_object` is valid).

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
| Left trigger + DRAWN | Toggle flashlight (with support grip) or reload |
| Left stick | Move (WASD) |
| Right stick L/R | Snap turn (45°) |
| Right stick click | Crouch |
| A/X button | Jump |
| B (right, DRAWN) | Enter grip adjust mode |
| A (right, adjust mode) | Save grip offsets to config |
| B (right, adjust mode) | Discard and exit adjust mode |
| Release grabbed item near bag zone | Add item to inventory |

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
- Head-locked during gameplay (follows `xr_camera` at `HUD_DISTANCE = 1.5m`)
- World-fixed during menus (`MENU_DISTANCE = 1.3m`, `MENU_WIDTH = 3.0m`)
- `_interface_open` detected by checking `game_camera/Core/UI` visibility each frame
- Laser pointer: raycasts from dominant controller → intersects HUD quad plane → warps OS mouse

## Known Issues / Constraints

- Adding a `MeshInstance3D` directly to `XRController3D` causes black HMD (Forward Mobile bug). Always wrap in `Node3D` container OR reuse existing nodes.
- `godot.log` truncates on startup — all debug must go to `vr_mod_debug.log`.
- Weapon nodes load late (after camera); `_weapon_raise_timer` (3 s) detects load and auto-raises.
- Weapon can occasionally snap to camera position after rapid holster/draw sequences; holstering and re-drawing restores sync. Root cause: game may re-parent or reset weapon rig on reload/stance events.
