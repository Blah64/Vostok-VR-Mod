# VR Mod — Session Handover

## What This Is

A GDScript-only VR mod for **Road to Vostok** (Godot 4.6.1, Forward Mobile, Vulkan 1.4).
Single autoload script injected via `override.cfg`. No compiled extensions.

**Source of truth:** `VR Mod/resources/vr_mod_init.gd`  
**After every edit, deploy:** `cp "VR Mod/resources/vr_mod_init.gd" "C:/Program Files (x86)/Steam/steamapps/common/Road to Vostok/vr_mod_init.gd"`  
**Debug log:** `C:/Program Files (x86)/Steam/steamapps/common/Road to Vostok/vr_mod_debug.log`

Always read CLAUDE.md before making changes — it contains critical rules, architecture,
and all current input bindings.

---

## Current State (as of last commit)

All core systems are working and committed to `master`. Latest commits:

```
34f3361 Add laser, flashlight and NVG toggles
41148a7 Block all grip actions during holster cooldown, not just zone draws
a563eac Block re-draw during holster animation with 0.8s cooldown
e237601 Fix README config section formatting
1b32839 Simplify README scope zoom docs to controls only
c3ff1e8 Add haptic feedback on scope zoom and document scope features in README
```

### Working Features

- **Full weapon handling**: draw/holster/lower/raise via body zones, two-hand aim
- **Scope PIP**: SubViewport scopes render correctly; variable-zoom scopes (Leopard, Vudu) use right stick U/D
- **Equipment toggles**:
  - Laser attachment: support trigger + grip → KEY_T
  - Flashlight: X (left, weapon holstered) → MOUSE_BUTTON_XBUTTON2
  - NVG: trigger above head in NVG zone → MOUSE_BUTTON_XBUTTON1
- **Grab system**: pick up loose items, throw, or deposit into inventory via bag zone
- **HUD**: SubViewport sharing World2D, head-locked, smooth follow option
- **F8 config screen**: all zones, HUD, grip offsets, NVG zone tunable in-game
- **F9**: dump HUD tree; **F10**: dump weapon tree + attachmentData

---

## Known Gaps / Possible Next Features

These are **not implemented yet** — pick up from here:

### High Priority
- **Physical reloading** — currently reload is just a button press; could require reaching to a mag pouch zone on the body
- **Melee gesture** — no unarmed/melee mapped; could be a punch/swing gesture or button combo
- **Two-handed weapon raise** — currently raising requires re-gripping with weapon hand; could let support-hand grip also raise

### Medium Priority
- **Item containers** — crates/loot bodies open via inventory UI but don't have VR grab/open gesture
- **Scope eye relief** — PIP quad currently floats at fixed distance; should snap to scope model position when weapon is raised
- **Flashlight direction** — game flashlight tracks camera/head; ideally it should track the weapon hand or an off-hand controller
- **Smooth crouch** — currently uses game toggle, doesn't track physical crouch from HMD height

### Low Priority / Polish
- **Holster zone visual indicators** — currently only haptic; could render subtle glowing spheres at each zone
- **Hand poses** — current hand meshes are static; could animate finger curl from trigger/grip analog values
- **Voice/proximity chat** — no push-to-talk mapped

---

## Game Node Structure (reference)

```
/root/Map/
  Core/
    Camera (Camera3D) — game_camera; found by _find_game_camera()
      Manager (Node3D)
        <child 0> (Node3D) — weapon_rig; synced to controller every frame
          Handling → Sway → Noise → Tilt → Impulse → Recoil → Holder → [weapon meshes]
          Attachments/
            [optic node] — has attachmentData Resource; variable=true for zoom scopes
              SubViewport — scope PIP view
              Camera (Camera3D) — scope PIP camera
      Core/
        UI (CanvasLayer) — HUD; shared into VRHudViewport via World2D
          HUD/Stats/Vitals  — health bars (bottom-left)
          HUD/Stats/Medical — status icons (bottom-right)
          HUD/Info          — map/FPS labels (top-left)
          NVG               — night vision overlay (skipped in interface detection)
      Flashlight (Node3D) — camera-mounted flashlight (SpotLight3D + OmniLight3D)
  [loose items] — RigidBody3D, collision_layer & 4, script Pickup.gd, group "Item"
```

---

## Critical Rules (summary — read CLAUDE.md for full list)

1. **Debug log** → `vr_mod_debug.log` (not godot.log, it truncates)
2. **Deploy after every edit** — game loads from game dir, not VR Mod/
3. **Never add MeshInstance3D directly to XRController3D** → black HMD
4. **No inline lambdas with semicolons** → GDScript parse error → black HMD
5. **No Co-Authored-By in commits**
6. **process_priority = 1000** — mod runs after game scripts

---

## Config File Structure (`VR Mod/config/default_config.json`)

```json
{
  "xr": { "world_scale": 1.0 },
  "controls": { "dominant_hand": "right", "snap_turn": true, "snap_degrees": 30.0, "smooth_turn_speed": 60.0 },
  "hud": { "width": 2.0, "distance": 1.5, "height_offset": -0.1, "lr_offset": 0.0, "smooth_follow": false, "smooth_speed": 3.0, "spread": 1.0 },
  "menu": { "width": 3.0, "distance": 1.3, "lr_offset": 0.0, "laser_uv_x": 0.02, "laser_uv_y": 0.06 },
  "holsters": {
    "zone_radius": 0.20,
    "offsets": { "1": {"x":0.25,"y":-0.15,"z":0.20}, "2": {"x":0.25,"y":-0.55,"z":0.0}, "3": {"x":-0.25,"y":-0.55,"z":0.0}, "4": {"x":0.0,"y":-0.15,"z":0.10} },
    "bag": { "x": 0.15, "y": -0.10, "z": 0.35, "radius": 0.35 }
  },
  "nvg_zone": { "y": 0.30, "radius": 0.25 },
  "weapon_offsets": { "1": { "x":0, "y":0.15, "z":-0.20, "rot":0.0 }, "2": {...}, "3": {...}, "4": {...} }
}
```
