# Road to Vostok — VR Mod

A community VR mod for **Road to Vostok** (Early Access). Play the full game in
virtual reality with full head tracking, motion controls, and physical weapon handling.

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
| A (right) or X (left) | Jump |
| B (right) | Interact with objects |
| Y (left) | Open / close inventory |
| Left stick click | Sprint |
| Menu button | Pause / escape |

### Weapon

| Input | Action |
|-------|--------|
| Right trigger | Fire |
| Right grip (weapon equipped) | Aim down sights |
| Left grip (weapon equipped) | Two-hand grip (stabilised aim) |
| Left trigger (weapon equipped, while holding left grip) | Toggle flashlight |
| Right stick click | Equip primary weapon |
| A (right) | Reload |

### Grabbing Items

| Input | Action |
|-------|--------|
| Right grip (no weapon equipped) | Grab item in range |
| Release right grip | Drop / throw item |

Point the **red laser** from your right hand at a loose item to target it. The laser
turns **green** when a grabbable item is in range. Release the grip with arm motion
to throw — the mod uses your last few hand-position samples to calculate throw velocity.

### Inventory / UI

When a menu or inventory panel is open the laser switches to **blue** and extends to
5 m. Point and pull the right trigger to click. Right grip acts as right-click.

---

## Configuration

Edit `VR Mod\config\default_config.json` in the game root. Changes take effect on
the next game launch.

### Turning

```json
"comfort": {
    "turn_type": "snap",
    "snap_turn_degrees": 45,
    "smooth_turn_speed": 120.0
}
```

| Setting | Values | Description |
|---------|--------|-------------|
| `turn_type` | `"snap"` or `"smooth"` | Snap jumps by a fixed angle; smooth turns continuously |
| `snap_turn_degrees` | Number (default `45`) | Degrees per snap step |
| `smooth_turn_speed` | Number (default `120`) | Degrees per second for smooth turn |

### Controls

```json
"controls": {
    "dominant_hand": "right",
    "thumbstick_deadzone": 0.15
}
```

| Setting | Values | Description |
|---------|--------|-------------|
| `dominant_hand` | `"right"` or `"left"` | Which hand holds the weapon and fires |
| `thumbstick_deadzone` | `0.0`–`1.0` | Stick dead zone; increase if drift is a problem |

### World Scale

```json
"xr": {
    "world_scale": 1.0
}
```

Adjust if the world feels too large or too small relative to your height. Values
above `1.0` make you feel taller; below `1.0` makes the world feel bigger.

---

## Known Issues

- **Melee / unarmed** is not yet mapped to a VR gesture.
- **Crouching** relies on the game's toggle and does not track physical crouch height.
- **Item containers** (crates, loot bodies) can be opened via the inventory UI but
  do not yet have dedicated VR interaction.
- The HUD may take a second to appear after the map loads — this is normal.

---

## Troubleshooting

**Black screen in headset after launch**
Make sure SteamVR or the Meta PC app is running *before* you start the game.

**Mod not activating (flat screen only)**
Confirm `override.cfg` and `vr_mod_init.gd` are in the game root (same folder as
`Road to Vostok.exe`), not inside a sub-folder.

**Config changes not taking effect**
The config is read once at startup. Fully quit and relaunch the game after editing.

**Weapon floats at wrong position / bad grip feel**
Try adjusting `"world_scale"` in the config. If the game updates and resets weapon
nodes, the mod logs details to `vr_mod_debug.log` in the game root folder — share
that file when reporting issues.

**Stuttering or low framerate**
Reduce your headset's render resolution in SteamVR / Oculus settings. The mod
itself adds minimal CPU overhead.

---

## Reporting Issues

Include `vr_mod_debug.log` (found in the game root folder) with any bug report —
it contains the diagnostic output the mod writes during each session.
