# Road to Vostok — VR Mod

A community VR mod for **Road to Vostok** (Early Access). Play the full game in
virtual reality with full head tracking, motion controllers, and physical weapon handling.

---

## Requirements

- Road to Vostok installed via Steam
- A PC VR headset supported by OpenXR (Meta Quest via Link/AirLink, Valve Index, HTC Vive, WMR, etc.)
- SteamVR or Meta PC app running before launching the game

---

## Installation

1. Copy `override.cfg` and `vr_mod_init.gd` into the game root folder:
   ```
   C:\Program Files (x86)\Steam\steamapps\common\Road to Vostok\
   ```
2. Copy the `VR Mod\config\` folder into the game root so you have:
   ```
   C:\Program Files (x86)\Steam\steamapps\common\Road to Vostok\VR Mod\config\default_config.json
   ```
3. Put on your headset, start SteamVR (or Meta PC app), then launch Road to Vostok normally through Steam.
4. The mod activates automatically once the game loads into a map — no launcher needed.

---

## Controls

### Movement

| Input | Action |
|-------|--------|
| Left stick | Move (forward / strafe) |
| Right stick left / right | Turn |
| A (right) | Jump |
| Y (left) | Open / close inventory |
| Left stick click | Sprint |
| Right stick click | Crouch |
| Menu button | Pause / escape |
| X (left, weapon holstered) | Toggle flashlight |
| Trigger (above head, unarmed) | Toggle night vision goggles |

### Holster System

Weapons are drawn and holstered by reaching to body locations and gripping.
Your controller will **buzz** when your hand enters a holster zone.

| Location | Weapon Slot |
|----------|------------|
| Right shoulder | Primary weapon |
| Right hip | Sidearm |
| Left hip | Knife |
| Chest | Grenades |

**Whichever hand draws the weapon becomes the weapon hand** — the other hand is the support hand.

| Action | Result |
|--------|--------|
| Grip near a holster zone | Draw weapon into that hand |
| Release grip (away from body) | Lower weapon — still in hand, can re-grip to raise |
| Release grip near own holster zone | Holster completely |
| Grip near a different holster zone | Swap weapon |

If a slot has no weapon equipped, releasing the grip immediately holsters with no effect.

### Weapon

| Input | Action |
|-------|--------|
| Weapon hand trigger | Fire |
| Support hand trigger | Reload |
| Support hand trigger (while gripping) | Toggle laser attachment |
| Support hand grip | Two-hand grip (stabilised aim) |
| Right stick up / down (weapon drawn, variable scope) | Zoom in / out |
| B (right) | Interact with objects |
| X (left, while weapon drawn) | Enter grip adjust mode |

> **Note:** All weapon inputs follow the weapon hand dynamically. If you draw with your
> left hand, left trigger fires and right trigger reloads.

### Scope Zoom

On variable-zoom scopes, push **right stick up** to zoom in and **right stick down** to
zoom out while the weapon is drawn. A haptic pulse confirms each step.

### Lowered Weapon

Release the weapon hand grip (away from a holster zone) to **lower** the weapon — it stays
in your hand but you no longer grip it. A laser appears on the weapon hand to help aim
interactions. Press **B** to interact with whatever you're pointing at. Re-grip with the
weapon hand to raise the weapon again.

### Grabbing Items

| Input | Action |
|-------|--------|
| Either hand grip (unarmed, near item) | Grab item |
| Release grip near bag zone (behind right shoulder) | Add item to inventory |
| Release grip elsewhere | Drop / throw item |

Point the laser from your dominant hand at a loose item to target it. Release the grip with
arm motion to throw — velocity is calculated from your last few hand-position samples.

### Laser Colors

| Color | Meaning |
|-------|---------|
| 🔴 Red | Nothing interactable in range |
| 🟢 Green | Grabbable loose item in range (grip to pick up) |
| 🟡 Yellow | B-button interactable in range (trader, loot pool, etc.) |
| 🔵 Blue | Menu / inventory open — laser extends to 5 m for UI pointing |

### Inventory / UI

When a menu or inventory panel is open the laser switches to **blue** and extends to 5 m.
Point and pull the trigger to click. Grip acts as right-click.

---

## Wrist Watch HUD

During gameplay your health, status effects, and other HUD info are displayed on a
**wrist-mounted watch** on your non-dominant hand. Raise your wrist toward your face to
reveal it — the display fades in when you look at it and fades out when you look away.

All watch settings (glance angle, fade speed, size, position on wrist) are tunable in the
F8 config screen under **Wrist Watch**. You can also disable glance-to-reveal so the watch
is always visible.

---

## In-Game Config Screen

Press **F8** at any time during gameplay to open the VR settings panel. It floats in
world space in front of you. Point your dominant-hand controller at it and pull the
trigger to interact. **Right stick up/down** scrolls the panel.

**Save & Close** and **Cancel** are pinned at the bottom of the panel and always visible
without scrolling. Press **Save & Close** to write all settings to `default_config.json`.
Press **Cancel** to discard changes for this session.

### Settings available in the config screen

| Section | Settings |
|---------|---------|
| **Comfort** | Turn mode (Snap / Smooth), snap degrees, smooth speed |
| **Menu / Inventory** | Distance, size, height, left/right offset, HUD element spread, laser X/Y calibration |
| **Wrist Watch** | Glance reveal on/off, glance angle, fade speed, watch size, X/Y/Z position on wrist |
| **Controls** | Dominant hand |
| **Holster Zones** | Zone radius, per-slot X/Y/Z position for all 4 holsters |
| **Bag Zone** | Inventory pickup zone radius and X/Y/Z position |
| **NVG Zone** | Night vision toggle zone radius, height above head, brightness, mono vision |

---

## Grip Adjust Mode

Dial in weapon grip position and rotation **while in-game** without editing files manually.

1. Draw a weapon (grip near a holster zone)
2. Press **X (left)** → controller prints "ADJUST MODE ON" to the debug log
3. Use the sticks to tune:

| Input | Adjusts |
|-------|---------|
| Left stick X | Grip left / right (X) |
| Left stick Y | Grip up / down (Y) |
| Right stick X | Weapon rotation (Y axis) |
| Right stick Y | Grip forward / back (Z) |

4. Press **A (right)** to save the current slot's values to `default_config.json` and exit
5. Press **X (left)** again to discard changes and exit

Movement and turning are disabled while adjust mode is active. The mode exits
automatically if you lower or holster the weapon.

---

## Configuration File

All settings are stored in `VR Mod\config\default_config.json`. The F8 config screen
writes this file automatically. You can also edit it manually — changes take effect on
the next game launch.

### Holster Zones

```json
"holsters": {
    "zone_radius": 0.20,
    "offsets": {
        "1": { "x": 0.25, "y": -0.15, "z": 0.20 },
        "2": { "x": 0.25, "y": -0.55, "z": 0.0  },
        "3": { "x": -0.25, "y": -0.55, "z": 0.0 },
        "4": { "x": 0.0,  "y": -0.15, "z": 0.10 }
    },
    "bag": { "x": 0.15, "y": -0.10, "z": 0.35, "radius": 0.35 }
}
```

### Weapon Grip Offsets

```json
"weapon_offsets": {
    "1": { "x": 0.0, "y": 0.15, "z": -0.20, "rot": 0.0 },
    "2": { "x": 0.0, "y": 0.10, "z": -0.13, "rot": 0.0 },
    "3": { "x": 0.0, "y": 0.05, "z": -0.10, "rot": 0.0 },
    "4": { "x": 0.0, "y": 0.08, "z": -0.10, "rot": 0.0 }
}
```

| Field | Description |
|-------|-------------|
| `x` | Left / right offset from controller (metres) |
| `y` | Up / down offset from controller (metres) |
| `z` | Forward / back offset — negative = back toward body |
| `rot` | Y-axis rotation in degrees |

### World Scale

```json
"xr": { "world_scale": 1.0 }
```

Adjust if the world feels too large or too small. Values above `1.0` make you feel
taller; below `1.0` makes the world feel bigger.

---

## Known Issues

- **Melee / unarmed** is not yet mapped to a VR gesture.
- **Crouching** uses the game's toggle and does not track physical crouch height.
- Occasionally the weapon snaps back to the camera position mid-session; holstering
  and re-drawing the weapon restores tracking.
- The wrist watch may take a second to appear after the map loads — this is normal.

---

## Troubleshooting

**Black screen in headset after launch**
Make sure SteamVR or the Meta PC app is running *before* you start the game.

**Mod not activating (flat screen only)**
Confirm `override.cfg` and `vr_mod_init.gd` are in the game root (same folder as
`Road to Vostok.exe`), not inside a sub-folder.

**Config changes not taking effect**
Most settings apply immediately via the F8 config screen. If editing the JSON file
manually, fully quit and relaunch the game.

**Weapon floats at wrong position**
Use Grip Adjust Mode (X button while weapon drawn) to tune the grip offset live.
If the issue persists across sessions, check `vr_mod_debug.log` in the game root.

**Stuttering or low framerate**
Reduce your headset's render resolution in SteamVR / Oculus settings. The mod
itself adds minimal CPU overhead.

---

## Reporting Issues

Include `vr_mod_debug.log` (found in the game root folder) with any bug report —
it contains the diagnostic output the mod writes during each session.
