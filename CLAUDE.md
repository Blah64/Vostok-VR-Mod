# Road to Vostok VR Mod — CLAUDE.md

## Project Overview

A VR mod for **Road to Vostok** (Godot 4.6.1, Forward Mobile renderer, Vulkan 1.4).
Distributed as two components:

- **`vr-mod-full.zip`** — native release: `rtv_vr_bootstrap.dll` (Vulkan/OpenXR injector),
  `librtv_vr_mod.windows.x86_64.dll` (GDExtension), `rtv_vr_injector.exe`, `launch_vr.bat`
- **`vr-mod.vmz`** — Metro Mod Loader package: `vr_mod_init.gd` (GDScript autoload), hand assets

**Why the injector is required:** Godot's Vulkan swapchain is created before any GDScript autoload
runs. Setting `use_xr = true` from GDScript after that point does not redirect frames to the OpenXR
compositor — the headset stays black. `rtv_vr_bootstrap.dll` hooks Vulkan/OpenXR at process init
(before Godot's renderer starts) so the swapchain is wired to OpenXR from the beginning.
**Metro Mod Loader is required.** Steam's Play button does not work — always use `launch_vr.bat`.

**Key files:**
- `VR Mod/resources/vr_mod_init.gd` — GDScript source of truth, ALL edits go here
- After every edit, rebuild and redeploy the VMZ to `mods/` (see `build.bat`).
  **Do NOT copy `vr_mod_init.gd` to the game root** — Metro loads it from the VMZ at
  `res://resources/vr_mod_init.gd`. A stale game-root copy shadows the VMZ version.
  **VMZ must use forward-slash zip entry paths** — Metro rejects backslash paths.
  `build.bat` uses `System.IO.Compression.ZipArchive` (not `Compress-Archive`) for this.
- `%APPDATA%\Road to Vostok\vr_mod\vr_mod_debug.log` — diagnostic log (Metro writes to user data)
- `%APPDATA%\Road to Vostok\vr_mod\vr_mod_config.json` — runtime config (created on first launch, seeded from bundled defaults)
- `VR Mod/config/default_config.json` — reference/defaults (not read at runtime; bundled in VMZ as `resources/default_config.json`)
- GitHub: https://github.com/Blah64/Vostok-VR-Mod

## Critical Rules

1. **Always use `vr_mod_debug.log` for diagnostics** — never `godot.log` (truncates).
   Write via `FileAccess.open(path, FileAccess.READ_WRITE)` + `seek_end(0)` + `store_line()`.
   Log path is `_log_path = "user://vr_mod/vr_mod_debug.log"` → `%APPDATA%\Road to Vostok\vr_mod\vr_mod_debug.log`.
2. **Deploy after every change** — rebuild and redeploy the VMZ to `mods/` (run `build.bat`). Never copy `vr_mod_init.gd` to the game root — a stale game-root copy shadows the VMZ-mounted version and runs old code.
3. **Never add new MeshInstance3D nodes to XRController3D** — causes black HMD screen in Forward Mobile. Reuse existing nodes instead.
4. **process_priority = 1000** — mod runs after all game scripts; weapon/object position overrides stick.
5. **No freeze on grabbed RigidBody3D** — use position override + zero velocity each frame instead.
6. **No Co-Authored-By in commits** — user preference.
7. **No inline lambdas with semicolons** — GDScript 4 inline lambda only accepts one statement. Semicolons end the lambda body and leave unmatched parens → parse error → black HMD. Always use named methods or multi-line lambdas.
8. **Do not commit unless explicitly told to

## Architecture

```
vr_mod_init.gd (autoload, extends Node)
  ├── XROrigin3D ("VRModOrigin")
  │   ├── XRCamera3D ("VRModCamera")
  │   ├── XRController3D ("LeftHand", tracker="left_hand")
  │   │   ├── Node3D "LeftHandModel" → GLTF scene (Hand_Nails_low_L.gltf)
  │   │   │     └── Skeleton3D (cached as _hand_skel_left) — bones driven each frame
  │   │   ├── Node3D "WatchMount" → _watch_mesh: MeshInstance3D (QuadMesh)
  │   │   └── RayCast3D "GrabRayLeft" (1m, all layers)
  │   └── XRController3D ("RightHand", tracker="right_hand")
  │       ├── Node3D "RightHandModel" → GLTF scene (Hand_Nails_low_R.gltf)
  │       │     └── Skeleton3D (cached as _hand_skel_right) — bones driven each frame
  │       └── RayCast3D "GrabRayRight" (1m, all layers)
  ├── _laser_mesh: MeshInstance3D (CylinderMesh, tri-purpose)
  │     Red   1m = nothing interactable in range
  │     Green 1m = grabbable RigidBody3D (layer 4) in range
  │     Yellow 1m = group "Interactable" object in range (trader, loot pool, etc.)
  │     Blue  5m = UI laser pointer (menu/inventory/config open)
  ├── SubViewport "VRHudViewport" — shares World2D with main viewport
  │     canvas_transform = identity when interface open (full 2D UI for hud_mesh)
  │     canvas_transform = cropped to Vitals region when watch active
  │     ↳ hud_mesh: MeshInstance3D (QuadMesh, layers=1<<19)
  │           parked under self (invisible) during gameplay
  │           world-space floating panel during menus/inventory
  └── SubViewport "VRWatchMedVP" — shares World2D with main viewport
        canvas_transform = cropped to Medical region when watch active
        (second viewport needed because Vitals/Medical are 1920px apart at spread=1.0)
```

**Watch mesh** (`_watch_mesh`, layers=`1<<19`) lives inside `Node3D "WatchMount"` which is a
child of the non-dominant hand controller. WatchMount is NOT a MeshInstance3D — safe on
XRController3D. Shader: `WATCH_CROP_SHADER` — dual-texture quad (top half = Vitals viewport,
bottom half = Medical viewport), transparent background, alpha fade controlled by glance logic.

## VR Hand System

Godot-XR-Tools lowpoly hand GLTFs loaded at runtime via `GLTFDocument.append_from_file()`.
Assets live in `VR Mod/resources/hands/` (committed to repo):
- `Hand_Nails_low_L.gltf` / `Hand_Nails_low_R.gltf` — mesh + skeleton (CC0)
- `hand_col.png` — caucasian skin base-colour texture (CC0, loaded once, shared)

**Loading:** `_create_hand_model()` is called for both hands during `_install_xr_rig()`.
Falls back to simple box hand if the .gltf is missing. Texture applied via
`_apply_hand_texture()` → `_hand_apply_mat_recursive()` which sets `material_override`
on every `MeshInstance3D` in the GLTF scene.

**Finger curl (procedural):** `_update_hand_poses(delta)` → `_update_one_hand(hand, delta)`
runs every frame. Each finger is smoothed toward a target curl value (0–1) then mapped to
bone rotations via `set_bone_pose_rotation(bi, rest_q * Quaternion(axis, angle))`.

| Finger | Input | Curl axis (local bone space) |
|--------|-------|------------------------------|
| Thumb | ax_button / ax_touch pressed | Local X (same sign both hands) |
| Index | Trigger analog | Local Z (negated for right hand) |
| Middle / Ring / Little | Grip analog | Local Z (negated for right hand) |

**Critical axis detail:** Finger bones (index–little) have their flexion axis on local Z.
The right-hand GLTF is a mirror of the left, so local Z points opposite — negate
`HAND_CURL_AXIS_FINGER` for the right hand in `_update_one_hand`.
Thumb bones have their flexion axis on local X (same sign both hands).

**Key state variables:**
```gdscript
var _hand_skel_left: Skeleton3D       # cached from GLTF scene
var _hand_skel_right: Skeleton3D
var _hand_fingers_left: Dictionary    # {"thumb":[bone_idx,...], "index":[...], ...}
var _hand_fingers_right: Dictionary
var _hand_bone_rest_left: Dictionary  # {bone_idx: Quaternion} rest rotations
var _hand_bone_rest_right: Dictionary
var _hand_curl_left: Dictionary       # {"thumb": 0.0, ..., "little": 0.0} smoothed [0,1]
var _hand_curl_right: Dictionary
var _hand_tex: ImageTexture           # shared skin texture (loaded once)
var HAND_CURL_AXIS_THUMB := Vector3(1, 0, 0)
var HAND_CURL_AXIS_FINGER := Vector3(0, 0, 1)  # negated for right hand at runtime
var HAND_FINGER_MAX_CURL := 1.45     # radians per joint at full curl
var HAND_THUMB_MAX_CURL := 0.9
var HAND_CURL_SMOOTH_SPEED := 20.0
```

## Scene Structure (game)

- Game camera: `/root/Map/Core/Camera` (Camera3D) — found by `_find_game_camera()`
- Weapon rig: `game_camera/Manager/<child 0>` (Node3D) — synced to controller each frame
- Weapon node chain: `Manager → weapon_rig → Handling → Sway → Noise → Tilt → Impulse → Recoil → Holder → [Weapon meshes]`
- Arm mesh: `MeshInstance3D` named `"Arms"` somewhere in weapon_rig subtree — **all surfaces hidden** via `_hide_arms_in_subtree()` (surfaces 0-1 = arms, 2+ = game hands; all hidden because the game's hand surfaces cannot be hidden independently from arms)
- Loose items: `RigidBody3D` with `collision_layer & 4 != 0`, direct children of `/root/Map/`, script `res://Scripts/Pickup.gd`, group `"Item"`, method `Interact()` adds to inventory
- B-button interactables: `StaticBody3D` in group `"Interactable"` — traders, loot containers, doors, etc. Parent node has the relevant script (e.g. `Trader.gd`, `LootContainer.gd`). Geometry with `Surface.gd` is NOT in this group.
- HUD/UI: `game_camera/Core/UI` — shared via `World2D` into SubViewports
- HUD node tree (key elements):
  - `Map/Core/UI/HUD/Stats/Vitals` — Health/Energy/Hydration/Mental/Temp (bottom-left, pos.x = -960 * spread)
  - `Map/Core/UI/HUD/Stats/Medical` — Status effect icons (bottom-right, pos.x = 960 * spread)
  - `Map/Core/UI/HUD/Info` — Map/FPS labels (top-left)
- LOS: `game_camera/LOS` — BoxMesh the game uses to detect interactable objects
- Game's own interact raycast: `game_camera/Interactor` (RayCast3D)

## State Machine (_phase)

```
0 = waiting_for_camera   poll every 30 frames for Camera3D
1 = xr_activating        wait XR_SETTLE_FRAMES (10) then _install_xr_rig()
2 = running              every frame: sync weapon, handle input, update HUD/watch
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
`nvg_zone.y` and `nvg_zone.radius` in `vr_mod_config.json`.

## NVG Overlay System

Replaces the game's 2D NVG shader overlay with a 3D spatial shader quad parented to
`xr_camera`. Supports stereo and mono (same image both eyes) modes.

**Game NVG detection:** Poll `Map/Core/UI/NVG/Overlay.visible` each frame. When visible,
set `modulate.a = 0` to hide the 2D overlay from the HUD quad while keeping `visible=true`
so the game's toggle logic still works. Restore `modulate.a = 1` on deactivation.

**Stereo mode:** Quad at z=-0.15m, 4×4m, samples `hint_screen_texture` via `SCREEN_UV`.
Each eye renders its own view with green tint + brightness + noise + vignette.

**Mono mode:** Separate `SubViewport` + `Camera3D` renders the scene from `xr_camera`'s
position (centered between eyes). Quad placed at z=-1.0m (IPD parallax ~3.6° — negligible).
Samples SubViewport texture via mesh `UV`. Camera synced to `xr_camera.global_transform`
every frame.

**Critical — visual layer isolation (prevents feedback loop):**
- `hud_mesh.layers = (1 << 19)` — layer 20 only
- `_nvg_overlay_mesh.layers = (1 << 19)` — layer 20 only
- `_watch_mesh.layers = (1 << 19)` — layer 20 only
- `_nvg_mono_camera.cull_mask = 0xFFFFF & ~(1 << 19)` — all layers except 20
- Without this: mono camera sees overlay/watch quads → samples itself → blows out instantly
- XR cameras default cull_mask includes all 20 layers, so they still see all meshes

**Shader:** `NVG_OVERLAY_SHADER` — `render_mode blend_mix, unshaded, cull_disabled, depth_test_disabled`.
`hint_screen_texture` / `SCREEN_UV` do NOT work in VR eye passes (stereo mode shows tint
on the desktop mirror but not in HMD — accepted limitation).

**State variables:**
```gdscript
var _nvg_active := false
var _nvg_overlay_mesh: MeshInstance3D
var _nvg_mono := false               # config: mono vision (same image both eyes)
var _nvg_mono_viewport: SubViewport  # created on demand
var _nvg_mono_camera: Camera3D
var _nvg_brightness := 2.0           # config: brightness multiplier
var _nvg_overlay_installed := false
```

**Config:** `nvg_zone` dict in `vr_mod_config.json` — keys: `y`, `radius`, `brightness`, `mono`.
F8 config screen → NVG Zone section: Radius, Y Height, Brightness, Mono Vision toggle.

## Comfort Vignette

Darkens the screen periphery during rotation to reduce motion sickness. Activates on both
snap and smooth turns; fades out when rotation stops.

**Implementation:** A ring-shaped `ArrayMesh` (32 steps, inner ring at NDC radius 1.0, outer
ring at NDC radius 2.0) parented to `xr_camera`. Uses `skip_vertex_transform` so the vertex
shader positions vertices in clip space directly — the only correct approach for a screen-space
effect in Godot 4 VR (SCREEN_UV / hint_screen_texture do not work in VR eye passes).

**Shader (COMFORT_VIGNETTE_SHADER):**
- Inner ring vertices (dist < 1.5): scaled by `radius` parameter and offset by `PROJECTION_MATRIX * (0,0,100)` to account for each eye's projection center in stereo
- Outer ring vertices (dist ≥ 1.5): fixed at NDC radius 2.0 (always off-screen)
- Fragment: `ALPHA = clamp((dist - radius) / fade, 0.0, 1.0)` — transparent at inner edge, opaque outward
- `radius` = 1.0 means inner edge is at screen boundary (invisible); shrinks inward as vignette activates

**Activation logic:**
- Snap turn → `_vignette_hold = 0.3 s`
- Smooth turn (each frame) → `_vignette_hold = max(_vignette_hold, 0.15)`
- `_update_comfort_vignette`: fast fade-in (speed 5.0/s), slow fade-out (speed 1.0/s)
- `_vignette_radius` animates from 1.0 toward `1.0 - strength * 0.8` while hold > 0

**State variables:**
```gdscript
var _vignette_enabled := true
var _vignette_strength := 0.8     # config: 0.1–1.0; maps to inner radius 0.85–0.2
var _vignette_mesh: MeshInstance3D
var _vignette_radius := 1.0       # current inner ring radius in NDC (1.0 = off)
var _vignette_hold := 0.0         # seconds remaining; >0 = vignette active
```

**Config:** `comfort.vignette_enabled` (bool) and `comfort.vignette_strength` (float 0.1–1.0).
F8 config screen → Comfort section: Vignette toggle + Vig. Strength stepper.

**Layer:** `1 << 19` (layer 20 only) — same as NVG overlay and watch mesh.

## Decor Mode (Shelter Furniture Placement)

When in a shelter, the player can enter decoration/furniture placement mode.
The game's flat-screen decor mode is activated by F1 and uses mouse aim for positioning.

**Activation:** Long-press X (left hand, 0.5 s) while UNARMED or LOWERED and not holding an
object. Injects KEY_F1 to toggle the game's decor mode. The game handles shelter detection
internally (F1 does nothing outside a shelter). Left controller buzzes on entry.

**Exit:** Short-press X (left) while in decor mode, OR squeeze both grips.

**Controller pointing:** During decor mode, `_steer_decor_camera_to_controller()` overrides
the game camera's basis to match the dominant-hand controller's aim direction via mouse injection.
The game's internal raycast follows the controller, so the furniture ghost tracks where the
player points. The XR camera (HMD view) is unaffected.

**State variables:**
```gdscript
var _decor_mode := false
var _decor_scroll_mode := 0       # 0 = distance, 1 = rotation
var _decor_scroll_cooldown := 0.0
var _left_grip_held := false
var _right_grip_held := false
var _decor_x_pending := false      # X held while unarmed/lowered; resolves to decor or flashlight
var _decor_x_press_time := 0.0
```

**Decor mode input mapping:**

| VR Control | Game Input | Action |
|-----------|-----------|--------|
| X (left, hold 0.5 s, UNARMED/LOWERED) | F1 | Enter decor mode |
| X (left) | F1 | Exit decor mode |
| Both grips | — | Exit decor mode |
| Controller aim (dominant) | Game camera direction | Position furniture preview |
| Right thumbstick Y | Scroll wheel | Adjust distance or rotation |
| Right grip (single) | (internal toggle) | Switch between distance/rotation mode |
| Right trigger (dominant) | G key | Place furniture |
| A (right) | Left mouse click | Toggle surface magnet |
| B (right) | Middle mouse button | Store item to furniture inventory |
| Y (left) | Tab key | Open furniture inventory |
| Left thumbstick | WASD | Movement (repositioning in shelter) |
| Right thumbstick X | Snap/smooth turn | Turn |

**Laser color:** Cyan (0.2, 0.8, 1.0) during decor mode.

**Weapon sync** is skipped during decor mode (no weapon equipped while decorating).

**Debug:** F11 dump includes decor mode state and game_camera/Placer node children when active.

## Input Bindings

| Button | Action |
|--------|--------|
| Right trigger (DRAWN, slot != 4) | Fire weapon |
| Right trigger (DRAWN, slot 4, pin not pulled) | Pull grenade pin → left click tap |
| Right trigger (DRAWN, slot 4, pin pulled) | Replace pin → right click tap (cancel) |
| Right grip release (DRAWN, slot 4, pin pulled) | Throw grenade → left click tap, auto-holster |
| Right grip (UNARMED, near zone) | Draw weapon from that slot |
| Right grip (UNARMED, no zone) | Grab nearby loose item |
| Right grip release (near own zone) | Holster weapon |
| Right grip release (away from zone) | Lower weapon |
| X (left, hold 0.5 s, UNARMED/LOWERED) | Enter decor mode → KEY_F1 |
| Support grip (DRAWN) | Two-hand aim |
| Support grip (near different zone) | Swap weapon |
| Support trigger (DRAWN, no grip, short press) | Reload |
| Support trigger (DRAWN, no grip, hold 0.5 s) | Ammo check → injects KEY_V |
| Support trigger (DRAWN, grip held) | Toggle laser attachment → injects KEY_T |
| X (left, UNARMED or LOWERED, short press) | Toggle standalone flashlight → MOUSE_BUTTON_XBUTTON2 |
| X (left, UNARMED or LOWERED, hold 0.5 s) | Enter decor mode → KEY_F1 |
| X (left, DRAWN) | Enter grip adjust mode |
| X (left, DECOR) | Exit decor mode → KEY_F1 |
| Trigger (either hand, above head, no grab) | Toggle NVG → MOUSE_BUTTON_XBUTTON1 |
| Right trigger (DECOR) | Place furniture → KEY_G |
| A (right, DECOR) | Surface magnet → MOUSE_BUTTON_LEFT |
| B (right, DECOR) | Store to furniture inv → MOUSE_BUTTON_MIDDLE |
| Y (left, DECOR) | Furniture inventory → KEY_TAB |
| Right stick Y (DECOR) | Distance/rotation scroll |
| Right grip (DECOR, single) | Toggle distance/rotation scroll mode |
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
| F11 | Dump NVG, environment, and decor state to vr_mod_debug.log |
| F12 | Dump ray target info (both GrabRays) to vr_mod_debug.log |

## Weapon Sync

`_sync_weapon_to_controller()` runs every frame in phase 2 **after** `_sync_origin_to_game()`:
- Gets `weapon_rig = game_camera/Manager/<child 0>`
- Sets `weapon_rig.global_basis` from controller basis + 180° Y flip + slot rotation offset (slot 4 uses 0° rotation — see Grenade System)
- Sets `weapon_rig.global_position = controller.global_position + arc_comp + aim_basis * (local_offset + recoil_delta.origin)`
- Two-hand mode: when `_support_grip_held`, aims from dominant hand model centre (`controller.global_position + controller.global_basis * HAND_GLTF_OFFSET`) toward the raw off-hand controller position. Only the dominant side uses the GLTF offset — adding the off-hand GLTF offset to the aim target skews aim when the off-hand controller is rotated.
- **Two-hand stabilization:** `_two_hand_smooth_basis` (full `Basis`) is slerped toward the raw two-hand `aim_basis` each frame at `_two_hand_smooth_speed`. Seeded to `single_hand_basis` on the first two-hand frame so there is no jump at transition. The smoothed result replaces `aim_basis`.
- **`_arc_raw_aim_basis` (pivot compensation):** stores the unsmoothed raw two-hand aim each frame. Seeded to `single_hand_basis` on the first two-hand frame so `arc_comp = 0` at transition (no position jump). Used in the `arc_comp` formula instead of `weapon_rig.global_basis` (which lagged behind the smoothed aim and made the dominant hand feel dampened). Single-hand: `arc_comp = 0` always.
- Calls `_hide_arms_in_subtree(weapon_rig)` every frame to hide game arm meshes (surfaces 0-1 of "Arms" node only; hand meshes surfaces 2+ stay visible)

**Execution order matters:** `_sync_origin_to_game()` → `_process_input()` → `_sync_weapon_to_controller()` → `_update_hand_visibility()` → `_update_grabbed()`

## Per-Slot Grip Offsets

Each weapon slot has its own position (in aim-local space) and roll rotation:

```gdscript
var _slot_grip_offsets := { 1: ..., 2: ..., 3: ..., 4: ... }
var _slot_grip_rotations := { 1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0 }
```

Loaded from `vr_mod_config.json` under `weapon_offsets.{weapon_key}.{x,y,z,rot}`.
Tuned live in-game via **grip adjust mode** (X button when DRAWN).

## Foregrip Lock System

Locks the support hand visual to a calibrated weapon-local position during two-hand aiming.

- **Arc 1 — visual lock:** `_apply_sway_to_hands` positions `sup_wrapper` at `weapon_rig.global_transform * _fg_p_sup_local` each frame, so the support hand model stays on the foregrip regardless of where the off-hand controller physically is.
- **Arc 2 — adjust mode:** X + off-hand grip while DRAWN → gun freezes at `_fg_adjust_frozen_xform`; player physically moves support hand to the foregrip location; A saves the sampled position to `_slot_fg_p_local[slot]`, X discards.
- **Arc 3 — load on grab:** `_fg_grip_captured` is false on the first frame of two-hand. `_apply_sway_to_hands` loads `_slot_fg_p_local[slot]` into `_fg_p_sup_local` and sets `_fg_grip_captured = true`. Subsequent frames skip the load.

**State variables:**
```gdscript
var _slot_fg_p_local := {}               # weapon-local foregrip position per slot
var _slot_fg_r_local := {}               # weapon-local foregrip rotation (Basis) per slot
var _fg_p_sup_local := Vector3.ZERO      # active foregrip world pos in weapon_rig local space
var _fg_r_sup_local := Basis.IDENTITY    # active foregrip rotation in weapon_rig local space
var _fg_grip_captured := false           # true once foregrip loaded for current grab
var _cached_weapon_rig: Node3D = null    # last weapon_rig ref; used at adjust entry/save
var _fg_adjust_mode := false             # gun frozen; support hand physically moved to foregrip
var _fg_adjust_frozen_xform := Transform3D.IDENTITY  # weapon transform at adjust entry
var _fg_adjust_saved_p := Vector3.ZERO   # pre-adjust p for discard
var _fg_adjust_saved_r := Basis.IDENTITY # pre-adjust r for discard
var _arc_raw_aim_basis := Basis.IDENTITY # unsmoothed raw aim for arc_comp; seeded on two-hand start
```

**Adjust mode flow:**
1. X pressed while DRAWN + off-hand gripping → `_fg_adjust_mode = true`, weapon frozen, `_fg_grip_captured = false`.
2. Each frame while in adjust mode: `_apply_sway_to_hands` skips the foregrip lock — support hand model follows the raw controller (live preview).
3. A pressed → sample support hand controller position/basis, convert to weapon-local space, write to `_slot_fg_p_local[slot]` / `_slot_fg_r_local[slot]`, call `_save_grip_config()`, exit.
4. X pressed → restore `_fg_adjust_saved_p/_r`, exit without saving.
5. Off-hand grip released → exit without saving.

**Config keys:** `foregrip_p_local.{slot}.{x,y,z}` and `foregrip_r_local.{slot}.{w,x,y,z}`.

## Grab System

- `_try_grab(hand)`: picks up `RigidBody3D` with `collision_layer & 4` within 1m
- `_update_grabbed()`: overrides position/basis to hand model each frame, zeros velocity
- `_drop_grabbed()`: checks bag zone first → if in zone calls `_pickup_to_inventory()`, else throws
- `_pickup_to_inventory()`: calls `item.Interact()` directly (Pickup.gd), haptic confirmation
- Throw velocity: last 3 of 8 hand position samples × 1.5

## HUD / Wrist Watch System

During **menus/inventory** (`_interface_open = true`):
- `hud_mesh` is reparented to world space and floats at a fixed position in front of the player
- Both SubViewports use `canvas_transform = Transform2D.IDENTITY` (full 2D canvas)
- `_hud_spread_active = _hud_spread` (config value, default 1.0)

During **gameplay** (`_interface_open = false`):
- `hud_mesh` is parked under `self` with `visible = false`
- `_hud_spread_active = 1.0` is forced so elements land at known canvas positions for the fixed crop rects
- `_watch_mesh` on the non-dominant wrist renders HUD content via `WATCH_CROP_SHADER`
- Glance-to-reveal: `_update_watch_glance(delta)` fades alpha in/out based on gaze angle

**Two-viewport crop approach** (required because Vitals/Medical are ~1920px apart at spread=1.0):
- `hud_viewport` canvas_transform is scaled/translated to show only the Vitals region (bottom-left)
- `_watch_b_vp` canvas_transform shows only the Medical region (bottom-right)
- Fixed proportional rects: Vitals centered at `vp_w * 0.25`, Medical at `vp_w * 0.75`,
  each `vp_w*0.208` wide × `vp_h*0.25` tall, bottom-aligned
- `_compute_watch_crop()` calculates transforms; `_watch_crop_computed` flag gates first run

**`WATCH_CROP_SHADER`** (dual-texture, transparent background):
- `UV.y >= 0.5` → top half of quad → samples `hud_texture` (Vitals viewport)
- `UV.y < 0.5` → bottom half of quad → samples `medical_tex` (Medical viewport)
- `ALPHA = tex.a * alpha` — transparent background; alpha driven by glance system
- All GLSL comments must use ASCII only (non-ASCII → silent shader failure → black watch)

**Watch state variables:**
```gdscript
var _watch_mesh: MeshInstance3D
var _watch_b_vp: SubViewport          # second viewport for Medical element
var _watch_alpha := 0.0
var _watch_size := 0.08               # quad height in metres
var _watch_glance_enabled := true
var _watch_glance_angle := 40.0       # max gaze angle (degrees) for reveal
var _watch_fade_speed := 8.0
var _watch_offset := Vector3(0.0, 0.02, -0.05)  # position on wrist
var _watch_crop_computed := false
var _hud_spread_active := 1.0         # actual value used by _apply_hud_spread()
```

**Key functions:**
- `_create_watch_mesh()` — creates WatchMount Node3D + MeshInstance3D on non-dominant hand
- `_compute_watch_crop()` — sets canvas_transform on both viewports, sizes quad
- `_update_watch_glance(delta)` — dot-product gaze check, fades alpha, toggles visible
- `_teardown_watch_content()` — resets canvas_transforms, clears cached node refs
- `_on_interface_opened()` — hides watch, resets viewports to identity, shows hud_mesh
- `_on_interface_closed()` — hides hud_mesh, restores watch crop, watch takes over

## Runtime-Tunable Variables (still active)

```gdscript
# Menu/inventory panel
var _hud_height_offset := -0.1  # vertical position of floating menu panel
var _hud_spread := 1.0          # 2D element spread during menus (Vitals/Medical x multiplier)
var _menu_width := 3.0
var _menu_distance := 1.3
var _menu_lr_offset := 0.0
var _menu_laser_uv_x := 0.02    # laser UV correction for menu quad
var _menu_laser_uv_y := 0.06

# Watch
var _watch_size := 0.08
var _watch_glance_enabled := true
var _watch_glance_angle := 40.0
var _watch_fade_speed := 8.0
var _watch_offset := Vector3(0.0, 0.02, -0.05)
```

Note: `_hud_width`, `_hud_distance`, `_hud_smooth_follow`, `_hud_smooth_speed` still exist
as variables but are no longer exposed in F8 (head-locked gameplay HUD was replaced by watch).

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

## Grenade System (Slot 4)

The game uses two separate mouse clicks for grenades — click 1 pulls the pin, click 2 throws.
The mod maps this to a VR-friendly two-step flow:

**Flow:**
- Trigger (pin not pulled) → left click tap → pin pulled, `_grenade_pin_pulled = true`, haptic buzz
- Trigger (pin pulled) → right click tap → pin replaced, `_grenade_pin_pulled = false`
- Grip release (pin pulled) → left click tap → throw, auto-holster after 0.5 s
- Holster / lower / level transition → `_clear_grenade_state()` releases fire if needed

**Throw direction:** The game uses `weapon_rig.global_basis.z` (not the game camera) for the throw
direction. Therefore:
- `_sync_weapon_to_controller()` uses `rot_offset = 0` for slot 4 — the slot grip rotation is
  ignored so the rig always faces the controller's raw forward direction.
- `_steer_game_camera_via_mouse()` also ignores slot rotation for all slots (uses `-controller.global_basis.z`
  directly), keeping the camera aligned with the controller regardless of grip rotation tuning.

**State variables:**
```gdscript
var _grenade_pin_pulled := false   # True after pin pulled; grip release = throw
```

**Helper functions:**
- `_grenade_tap_release()` — releases the fire input after an 80 ms tap
- `_grenade_throw_tap()` — injects a left click tap + schedules auto-holster
- `_grenade_replace_pin()` — injects a right click tap to cancel the throw
- `_grenade_replace_pin_release()` — releases the right click after 80 ms
- `_grenade_auto_holster()` — holsters slot 4 if still DRAWN (0.5 s timer callback)
- `_clear_grenade_state()` — releases fire if pin pulled, resets flag; called on holster/lower/transition

**Note:** Adjusting slot 4 grip rotation via X adjust mode only affects the weapon model position.
It does not affect throw direction.

## F8 Config Screen

- Opens a SubViewport-based panel (`_config_panel_vp` / `_config_panel_quad`) in world space
- Laser from dominant hand drives `_config_laser_pos` → `push_input()` to SubViewport
- Right stick Y scrolls the `CfgRoot/CfgOuter/CfgScroll` ScrollContainer
- **Save & Cancel are pinned outside the scroll** (in outer VBoxContainer `CfgOuter`), always visible
- Layout: `CfgRoot → CfgOuter (VBoxContainer) → [CfgScroll (ScrollContainer, expand), HSeparator, btn_row (HBoxContainer)]`
- All buttons use `Callable(self, "named_method_string")` — no inline lambdas
- Steppers work by disconnecting/reconnecting button signals with updated value in bound args
- Save & Close calls `_save_full_config()` which writes the full config JSON
- Sections: **Comfort, Menu/Inventory, Wrist Watch, Controls, Holster Zones, Bag Zone, NVG Zone**
- Comfort section includes vignette toggle, strength, render scale, and two-hand stabilization toggle + speed (added after snap/smooth turn rows)
- `_scroll_config_panel()` uses path `"CfgRoot/CfgOuter/CfgScroll"`

## Known Issues / Constraints

- Adding a `MeshInstance3D` directly to `XRController3D` causes black HMD (Forward Mobile bug). Always wrap in `Node3D` container OR reuse existing nodes.
- `godot.log` truncates on startup — all debug must go to `vr_mod_debug.log`.
- Weapon nodes load late (after camera); `_weapon_raise_timer` (3 s) detects load and auto-raises.
- Weapon can occasionally snap to camera position after rapid holster/draw sequences; holstering and re-drawing restores sync.
- GDScript parse errors produce no output (mod silently fails to load → black HMD). If black HMD occurs after a code change, revert and add changes incrementally.
- `hint_screen_texture` / `SCREEN_UV` do not work in VR eye passes (Forward Mobile + multiview limitation). Stereo NVG tint is visible on desktop mirror only; mono mode works correctly via SubViewport.
- NVG overlay, `hud_mesh`, and `_watch_mesh` must be on visual layer 20 only — if placed on layer 1, the NVG mono camera renders them, causing a feedback loop.
- `get_global_rect()` always returns zero for 2D nodes inside a shared-World2D SubViewport — use proportional canvas coordinates instead of querying node rects.
- Non-ASCII characters in GLSL shader source (e.g. `→`) cause silent shader compilation failure — watch quad renders black. Use ASCII comments only in all shader strings.
