# VR Mod — New Session Handover

## What This Is

A working GDScript VR mod for Road to Vostok (Godot 4.6.1). Single autoload script,
no compiled code. OpenXR is already built into the game binary.

## Working Directory

`C:\Program Files (x86)\Steam\steamapps\common\Road to Vostok\VR Mod\`

Read `CLAUDE.md` first — it has the full architecture, constraints, and critical rules.

## What Works Today

- **Head tracking** — XRCamera3D follows HMD
- **Hand models** — simple box-mesh hands, always visible; game arm meshes hidden separately
- **Weapon sync** — gun follows controller orientation and position in real-time, per-slot grip offsets
- **Location-based holster system** — reach to right shoulder / right hip / left hip / chest to draw each slot; dynamic dominant hand; haptic buzz on zone entry
- **Holster states** — DRAWN / LOWERED / UNARMED with full transition logic
- **Two-hand aiming** — hold support grip to aim with both hands
- **Live grip adjust mode** — B button when drawn; thumbsticks tune position/rotation; A to save, B to discard
- **Grab system** — point red/green laser at loose items (layer 4), grip picks up; throw on release
- **Bag zone pickup** — reach behind right shoulder while holding a loose item, release grip → calls `item.Interact()` to add to inventory; haptic on zone entry
- **Arm hiding** — game first-person arm mesh hidden via surface override
- **Flashlight / Reload** — support hand trigger
- **UI / Inventory** — HUD in world space via shared World2D SubViewport, laser pointer + mouse warp
- **Snap and smooth turn** — right stick left/right
- **Movement** — left stick → WASD injection; crouch = right stick click; jump = A/X
- **F8 Config Screen** — in-game VR settings panel with laser pointer interaction and right-stick scrolling. Covers: turn mode/speed, HUD distance/size/height/LR/spread/follow mode, menu distance/size/LR/laser calibration, dominant hand, holster zone positions and radii, bag zone position and radius. Save & Close writes `default_config.json`.

## Key State Variables

```gdscript
_holster_state        # HolsterState enum: UNARMED / DRAWN / LOWERED
_weapon_hand          # "left" or "right" — whichever hand drew the weapon
_weapon_slot          # int 1-4, active holster slot
_config_dominant_hand # preferred hand for UI/grab when unarmed
_support_grip_held    # true when off-hand grip held (two-hand aim)
_grabbed_object       # currently held loose RigidBody3D (null if none)
_grab_hand            # which hand holds the grabbed object
_adjust_mode          # true when in live grip adjust mode
_pending_holster_key  # delayed KEY injection guard (prevents double-toggle)
_config_screen_open   # true while F8 config panel is visible
_interface_open       # true while game menu/inventory is open
_hud_smooth_follow    # HUD lerp mode vs instant snap
_hud_spread           # HUD element spread multiplier (0.1–2.0)
```

## Config File

`VR Mod/config/default_config.json` — written by F8 config screen and grip adjust mode.
Current tuned values:

```json
{
  "comfort":  { "turn_type": "smooth", "snap_turn_degrees": 45, "smooth_turn_speed": 120 },
  "controls": { "dominant_hand": "right", "thumbstick_deadzone": 0.15 },
  "holsters": { "zone_radius": 0.25 },
  "hud": {
    "width": 2.3, "distance": 0.9, "height_offset": -0.05,
    "lr_offset": 0.0, "smooth_follow": true, "smooth_speed": 1.5, "spread": 0.5
  },
  "menu": { "width": 3.0, "distance": 1.3, "lr_offset": 0.0, "laser_uv_x": 0.03, "laser_uv_y": 0.06 },
  "weapon_offsets": {
    "1": { "rot": 0.7,   "x": 0.046, "y": 0.119, "z": -0.237 },
    "2": { "rot": -4.3,  "x": 0.01,  "y": 0.076, "z": -0.369 },
    "3": { "rot": -94.7, "x": 0.105, "y": 0.087, "z": -0.327 },
    "4": { "rot": -29.4, "x": 0.079, "y": 0.061, "z": -0.343 }
  },
  "xr": { "world_scale": 1.0 }
}
```

## Critical GDScript Rules (learned the hard way)

- **No inline lambda semicolons** — `func(v): a = v; b()` causes parse error → black HMD with no output. Use named methods instead.
- **Black HMD = parse error** — if the script fails to parse, the mod loads silently with no output anywhere. If you get black HMD after a code change, revert immediately and add changes in small steps.
- **No MeshInstance3D directly on XRController3D** — wraps in Node3D or reuse existing.

## Known Quirks

- Weapon can occasionally snap to camera on rapid holster/draw; holstering and re-drawing restores it.
- HUD spread adjusts `Map/Core/UI/HUD/Stats/Vitals` and `Stats/Medical` x positions directly (960px from center at default spread=1.0).
- F9 dumps the full HUD node tree to `vr_mod_debug.log` for debugging.

## Possible Next Features

- Procedural hand grip poses (fingers curl around weapon/item)
- Melee gesture (swing arm to melee)
- Comfort vignette on locomotion
- Physical crouch tracking (map real squat to in-game crouch)
- Iron sights / scope alignment to eye level
- Haptic recoil patterns per weapon type
- Inventory container interaction (open crates/bodies in VR)
- World-space notifications (damage numbers, zone text) instead of 2D HUD

## Git Log (recent)

```
eb61ab2 Add holster/bag zone position settings in config screen; update README
bcd822f Add tunable laser UV offsets for inventory menu in config screen
62f33ea Right thumbstick up/down scrolls config screen; suppress turn while open
fcb448e Add HUD spread control and fix config screen settings preview
071b1cf Add F8 in-game config screen for VR settings
3d7d72c Make HUD/menu sizing runtime-configurable for in-game config screen
f78f514 Update CLAUDE.md and HANDOVER.md for new session handover
093702e Add bag zone: reach behind shoulder to add grabbed item to inventory
1ff46de Fix weapon stuck to camera on rapid holster/redraw
5dd8b37 Always show VR hands; move right shoulder holster zone back 1 foot
```
