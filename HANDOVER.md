# VR Mod — Session Handover

## What This Is

A VR mod for **Road to Vostok** (Godot 4.6.1, Forward Mobile, Vulkan 1.4).
Two-component distribution: a native release (injector + GDExtension) and a Metro VMZ (GDScript mod).

**GitHub:** https://github.com/Blah64/Vostok-VR-Mod

**Source of truth:** `VR Mod/resources/vr_mod_init.gd`

**After every GDScript edit:**
1. Deploy to game root: `cp "VR Mod/resources/vr_mod_init.gd" "<game root>/vr_mod_init.gd"`
2. Rebuild VMZ and redeploy to `mods/` (run `build.bat` or use the bash staging flow)

**Debug log:** `%APPDATA%\Road to Vostok\vr_mod\vr_mod_debug.log`  
**Config:** `%APPDATA%\Road to Vostok\vr_mod\default_config.json` (created on first launch)

Always read CLAUDE.md before making changes — it contains critical rules, architecture,
and all current input bindings.

---

## Architecture

### Why the injector is required

Godot's Vulkan swapchain is created before any GDScript autoload runs. Setting `use_xr = true`
from GDScript after that point does not redirect frames to the OpenXR compositor — the HMD stays
solid black. `rtv_vr_bootstrap.dll` hooks Vulkan/OpenXR at process init so the swapchain is wired
to OpenXR before Godot's renderer starts. **Metro Mod Loader is also required.** Steam's Play
button does not work — always use `launch_vr.bat`.

### Launch flow

1. `launch_vr.bat` → `rtv_vr_injector.exe` injects `rtv_vr_bootstrap.dll` into `RTV.exe`
2. Bootstrap deploys `VR Mod/resources/{override.cfg, vr_mod_init.gd, rtv_vr_mod.gdextension}` to game root
3. Game boots → `override.cfg` loads `ModLoader` autoload → Metro loads `mods/vr-mod.vmz`
4. Metro instantiates `vr_mod_init.gd` under `/root/ModLoader/VRModInit`
5. `vr_mod_init.gd` creates XROrigin3D/XRCamera3D rig — VR renders because injector already wired the swapchain

### Path variables (hardcoded, Metro-only)

```gdscript
var _log_path    := "user://vr_mod/vr_mod_debug.log"
var _config_path := "user://vr_mod/default_config.json"
var _assets_base := "res://resources/hands/"
```

`res://resources/hands/` resolves into the VMZ via Metro's resource pack mounting.

### Build / release

`build.bat` (gitignored, local only) produces two artifacts in `releases/`:
- **`vr-mod-full.zip`** — extract into game root for a full install; contains all native binaries,
  `VR Mod/resources/` (including hands), and `mods/vr-mod.vmz`
- **`vr-mod.vmz`** — Metro-only update when only GDScript has changed

---

## Current State (as of last commit)

All core systems are working and committed to `master`. Recent commits:

```
5ccc05e Fix release zip: add hands, LICENSE, THIRD_PARTY.md
e00d48e Include README.md in full release zip; note black screen at main menu
590e00b Simplify install to single zip: vr-mod-full.zip extracts to game root
5b4ecd7 Fix installation instructions: document native release + VMZ
e8b736e Simplify path detection: hardcode Metro-only paths
9d58d34 Drop standalone support, require Metro Mod Loader
```

### Working Features

- **Full weapon handling**: draw/holster/lower/raise via body zones, two-hand aim
- **Grenade throwing** (slot 4): trigger pulls pin (haptic), grip release throws, second trigger replaces pin
- **Scope PIP**: SubViewport scopes render correctly; variable-zoom scopes use right stick U/D
- **Equipment toggles**: laser attachment (KEY_T), flashlight (XBUTTON2), NVG (XBUTTON1 via head zone)
- **Grab system**: pick up loose items, throw, or deposit into inventory via bag zone
- **Wrist Watch HUD**: glance-to-reveal on non-dominant wrist; dual-viewport crop for Vitals + Medical
- **Laser colors**: red = nothing, green = grabbable, yellow = B-button interactable, blue = UI, cyan = decor
- **F8 config screen**: all zones, watch, grip offsets, NVG, comfort settings tunable in-game
- **Comfort vignette**: activates on snap/smooth turn, fades out when rotation stops
- **NVG overlay**: 3D spatial shader quad; mono mode via SubViewport+Camera3D
- **Decor mode**: long-press X (left, unarmed) → shelter furniture placement via controller aim
- **F9/F10/F11/F12**: debug dumps for HUD tree, weapon tree, NVG/environment, GrabRay targets

---

## Known Gaps / Possible Next Features

### High Priority
- **Physical reloading** — currently a button press; could require reaching to a mag pouch zone
- **Melee gesture** — no unarmed/melee mapped
- **Two-handed weapon raise** — support-hand grip could also raise a lowered weapon

### Medium Priority
- **Scope eye relief** — PIP quad at fixed distance; ideally snaps to scope model position
- **Flashlight direction** — currently tracks game camera; should track weapon or off-hand
- **Smooth crouch** — game toggle only, doesn't track physical HMD height
- **Watch Info panel** — map/FPS info not shown during gameplay

### Low Priority / Polish
- **Holster zone visual indicators** — haptic only; could render subtle zone spheres
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
      Interactor (RayCast3D) — game's own interact detection raycast
      Core/
        UI (CanvasLayer) — HUD; shared into SubViewports via World2D
          HUD/Stats/Vitals  — health bars (bottom-left, x = -960 * spread)
          HUD/Stats/Medical — status icons (bottom-right, x = 960 * spread)
          HUD/Info          — map/FPS labels (top-left)
          NVG               — night vision overlay
  [loose items] — RigidBody3D, collision_layer & 4, script Pickup.gd, group "Item"
  [interactables] — StaticBody3D in group "Interactable"
```

---

## Critical Rules (summary — read CLAUDE.md for full list)

1. **Debug log** → `%APPDATA%\Road to Vostok\vr_mod\vr_mod_debug.log` (not godot.log)
2. **Deploy after every edit** — game root AND VMZ rebuild/redeploy to `mods/`
3. **Never add MeshInstance3D directly to XRController3D** → black HMD; wrap in Node3D
4. **No inline lambdas with semicolons** → GDScript parse error → black HMD
5. **No Co-Authored-By in commits**
6. **process_priority = 1000** — mod runs after game scripts
7. **No non-ASCII in GLSL shader strings** → silent shader failure → black watch/mesh
8. **Do not commit unless explicitly told to**
