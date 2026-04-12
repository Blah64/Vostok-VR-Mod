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
- **Location-based holster system** — reach to right shoulder / right hip / left hip / chest to draw each slot; dynamic dominant hand (whichever hand draws becomes weapon hand); haptic buzz on zone entry
- **Holster states** — DRAWN (weapon raised) / LOWERED (weapon_low) / UNARMED; release grip near own zone to holster, away to lower
- **Two-hand aiming** — hold support grip to aim with both hands
- **Live grip adjust mode** — B button when drawn; thumbsticks tune position/rotation live; A to save, B to discard
- **Grab system** — point red/green laser at loose items (layer 4), grip picks up; throw on release
- **Bag zone pickup** — reach behind right shoulder while holding a loose item, release grip → calls `item.Interact()` to add to inventory; haptic feedback on zone entry
- **Arm hiding** — game first-person arm mesh hidden via surface override (surfaces 0-1 of "Arms" node only)
- **Flashlight** — support hand trigger toggles when weapon drawn + support grip held
- **Reload** — support hand trigger when weapon drawn (no support grip)
- **UI / Inventory** — HUD in world space, laser pointer + mouse warp for interaction
- **Snap turn** — right stick left/right, 45° increments
- **Smooth turn** — enabled by default
- **Movement** — left stick → WASD injection
- **Crouch** — right stick click
- **Jump** — A/X button

## Key State Variables

```gdscript
_holster_state     # HolsterState enum: UNARMED / DRAWN / LOWERED
_weapon_hand       # "left" or "right" — whichever hand drew the weapon
_weapon_slot       # int 1-4, active holster slot
_config_dominant_hand  # preferred hand for UI/grab when unarmed
_support_grip_held # true when off-hand grip held (two-hand aim)
_grabbed_object    # currently held loose RigidBody3D (null if none)
_grab_hand         # which hand holds the grabbed object
_adjust_mode       # true when in live grip adjust mode
_pending_holster_key  # delayed KEY injection guard (prevents double-toggle)
```

## Config File

`config/default_config.json` — edited by grip adjust mode in-game:
```json
{
  "holsters": { "zone_radius": 0.25 },
  "weapon_offsets": {
    "1": { "rot": 0.7,   "x": 0.046, "y": 0.119, "z": -0.237 },
    "2": { "rot": -4.3,  "x": 0.01,  "y": 0.076, "z": -0.369 },
    "3": { "rot": -94.7, "x": 0.105, "y": 0.087, "z": -0.327 },
    "4": { "rot": -29.4, "x": 0.079, "y": 0.061, "z": -0.343 }
  }
}
```

## Known Quirks

- Any NEW `MeshInstance3D` added directly to `XRController3D` causes black HMD screen. Always wrap in `Node3D` or reuse existing nodes.
- All diagnostics go to `vr_mod_debug.log` in the game root — never godot.log (truncates).
- Deploy after every edit: `cp "VR Mod/resources/vr_mod_init.gd" "<game root>/vr_mod_init.gd"`
- Weapon can occasionally snap to camera on rapid holster/draw; holstering and re-drawing restores it.
- No Co-Authored-By lines in commits.

## Possible Next Features

- Inventory/container interaction in VR (open crates, loot bodies)
- Procedural hand animations (grip pose when holding weapon/item)
- Smooth locomotion option (alternative to snap turn)
- Weapon iron sights alignment to eye level
- Comfort vignette on movement
- Physical magazine reload (bring mag pouch to gun)
- Two-handed carry for large items

## Git Log

```
5c7bffb Add bag zone: reach behind shoulder to add grabbed item to inventory
0286b62 Fix weapon stuck to camera on rapid holster/redraw
a298728 Always show VR hands; move right shoulder holster zone back 1 foot
d38d660 Update README with holster system and adjust mode; save tuned weapon offsets
9fdbfc3 Add live grip adjust mode and per-slot rotation offsets
2e0ddc4 Add per-slot weapon grip offsets; fix arm-only hiding
435ae27 Holster empty slot on grip release; hide all arms for all weapon types
6199bf1 Increase holster zone radius to 0.25m
7f4f851 Fix hand visibility on empty holster grab; add crouch to right stick click
7411b0a Add location-based holster system with haptic feedback
```
