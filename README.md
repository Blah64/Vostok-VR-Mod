# Road to Vostok — VR Mod v1.0.0

A community VR mod for **Road to Vostok** (Early Access). Play the full game in
virtual reality with full head tracking, motion controllers, and physical weapon handling.

---

## Requirements

- Road to Vostok installed via Steam
- A PC VR headset supported by OpenXR (Meta Quest via Link/AirLink, Valve Index, HTC Vive, WMR, etc.)
- SteamVR or Meta PC app running before launching the game

---

## Installation

### Option A — Standalone (no other mods)

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

### Option B — Metro Mod Loader (recommended if running multiple mods)

[Metro Mod Loader](https://modworkshop.net/mod/55623) lets you enable and disable mods by moving a
single file, and handles load order automatically when running multiple mods alongside each other
(e.g. Mod Configuration Menu).

1. Install Metro Mod Loader by following its instructions — this replaces `override.cfg` in the game
   root with Metro's own copy. Do **not** also install the standalone `override.cfg` from this mod.
2. Drop `vr-mod.vmz` into the `mods\` folder in the game root:
   ```
   C:\Program Files (x86)\Steam\steamapps\common\Road to Vostok\mods\vr-mod.vmz
   ```
3. Put on your headset, start SteamVR (or Meta PC app), then launch Road to Vostok normally through Steam.

Config and debug log are written to `%APPDATA%\Road to Vostok\vr_mod\` in Metro mode.

**To disable the mod:** remove or rename `vr-mod.vmz`. No other files need to be touched.

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
| X (left, weapon holstered, quick tap) | Toggle flashlight |
| X (left, weapon holstered, hold 0.5 s) | Enter shelter decoration mode |
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
| Release grip (slot 1, away from body) | Sling — weapon hangs at chest height, follows player yaw |
| Release grip (slots 2–4, away from body) | Auto-holster immediately |
| Release grip near own holster zone | Holster completely |
| Grip near a different holster zone | Swap weapon |

If a slot has no weapon equipped, releasing the grip immediately holsters with no effect.

### Sling (Primary Weapon Only)

Releasing the grip on your **primary weapon (slot 1)** away from a holster zone puts it in
**sling position** — the weapon hangs at chest height in front of you and follows your yaw
as you turn, just like a rifle on a real sling.

To raise the weapon from sling: grip with either hand (dominant or off-hand).
To holster from sling: grip near your right-shoulder holster zone.

> Slots 2, 3, and 4 (sidearm, knife, grenade) auto-holster when you release the grip.

### Weapon

| Input | Action |
|-------|--------|
| Weapon hand trigger | Fire |
| Support hand trigger (quick press) | Reload |
| Support hand trigger (hold 0.5 s) | Ammo check |
| Support hand trigger (while gripping) | Toggle laser attachment |
| Support hand grip | Two-hand grip (stabilised aim, rifles/shotguns only) |
| Right stick up / down (weapon drawn, variable scope) | Zoom in / out |
| B (right, weapon drawn) | Cycle fire mode |
| B (right, weapon lowered) | Interact with objects |
| X (left, while weapon drawn, quick tap) | Enter grip adjust mode |
| X (left, while weapon drawn, off-hand gripping, quick tap) | Enter foregrip adjust mode |
| X (left, while weapon drawn, hold 0.3 s) | Enter optic rail adjust mode |

> **Note:** All weapon inputs follow the weapon hand dynamically. If you draw with your
> left hand, left trigger fires and right trigger reloads.

### Grenades

Grenades (slot 4, chest holster) use a two-step mechanic:

| Input | Action |
|-------|--------|
| Weapon hand trigger (pin not pulled) | Pull pin — controller buzzes, grenade is armed |
| Weapon hand grip release (pin pulled) | Throw — grenade flies in controller aim direction |
| Weapon hand trigger (pin pulled) | Replace pin — disarms grenade, cancels throw |

The grenade is automatically holstered 0.5 s after throwing. Aim with your controller —
the throw direction follows wherever the weapon hand is pointing at the moment you release
the grip. The controller buzzes continuously while the pin is pulled.

### Scope Zoom

On variable-zoom scopes, push **right stick up** to zoom in and **right stick down** to
zoom out while the weapon is drawn. A haptic pulse confirms each step.

### Lowered Weapon

Release the weapon hand grip (away from a holster zone) to **lower** the weapon — it stays
in your hand but you no longer grip it. A laser appears on the weapon hand to help aim
interactions. Press **B** to interact with whatever you're pointing at. Re-grip with the
weapon hand (or support hand) to raise the weapon again.

### Grabbing Items

| Input | Action |
|-------|--------|
| Either hand grip (unarmed, near item) | Grab item |
| Release grip near bag zone (behind right shoulder) | Add item to inventory |
| Release grip elsewhere | Drop / throw item |

Point the laser from your dominant hand at a loose item to target it. Release the grip with
arm motion to throw — velocity is calculated from your last few hand-position samples.

### Shelter Decoration Mode

When inside a shelter you can enter furniture placement mode to arrange your base.

**Enter:** **Hold X (left) for 0.5 s** while unarmed and not holding anything. The
controller buzzes to confirm.

**Exit:** Press **X (left)** or squeeze **both grips** while in decor mode.
Exiting is blocked while a furniture ghost preview is active — place or cancel the item first.

| Input | Action |
|-------|--------|
| X (left, hold 0.5 s, unarmed) | Enter decor mode |
| X (left) | Exit decor mode |
| Both grips | Exit decor mode |
| Controller aim (dominant) | Aim furniture ghost / target placed furniture |
| Right stick up / down | Adjust distance or rotation amount |
| Right grip (single) | Toggle between distance and rotation scroll |
| Right trigger | Place furniture (G) |
| A (right) | Toggle surface magnet |
| B (right) | Store item back to furniture inventory |
| Y (left) | Open furniture inventory |
| Left stick | Move around the shelter |
| Right stick left / right | Turn |

### Laser Colors

| Color | Meaning |
|-------|---------|
| 🔴 Red | Nothing interactable in range |
| 🟢 Green | Grabbable loose item in range (grip to pick up) |
| 🟡 Yellow | B-button interactable in range (trader, loot pool, etc.) |
| 🔵 Blue | Menu / inventory open — laser extends to 5 m for UI pointing |
| 🩵 Cyan | Decor mode active — aiming for furniture placement |
| 🟠 Orange | Decor mode — pointing at furniture that can be moved |

### Inventory / UI

When a menu or inventory panel is open the laser switches to **blue** and extends to 5 m.

| Input | Action |
|-------|--------|
| Dominant trigger | Click (left mouse) |
| Dominant grip | Right-click / context menu |
| Support grip (hold) + dominant trigger | Fast transfer (Ctrl + click) |
| Right stick up / down | Scroll |

**Fast transfer:** Hold the **support hand grip** to activate a Ctrl modifier, then
trigger-click each item you want to move. Release the support grip when done.

---

## Comfort Vignette

The mod automatically darkens the edges of your view while you turn — a standard VR comfort
technique to reduce motion sickness. It fades in when rotation starts and fades out when
rotation stops.

You can toggle it on/off and adjust the strength in the **F8 config screen → Comfort** section.
Higher strength values shrink the clear center area further, providing a stronger effect.
At strength 0.8 (default) the vignette is noticeable but unobtrusive; at 1.0 it covers
roughly 80% of the peripheral view at peak turn speed.

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
| **Comfort** | Turn mode (Snap / Smooth), snap degrees, smooth speed, comfort vignette on/off, vignette strength, render scale, two-hand stabilization on/off, smoothing speed |
| **Menu / Inventory** | Distance, size, height, left/right offset, HUD element spread, laser X/Y calibration |
| **Wrist Watch** | Glance reveal on/off, glance angle, fade speed, watch size, X/Y/Z position on wrist |
| **Controls** | Dominant hand |
| **Holster Zones** | Zone radius, per-slot X/Y/Z position for all 4 holsters, primary weapon sling X/Y/Z position and rotation offsets |
| **Bag Zone** | Inventory pickup zone radius and X/Y/Z position |
| **NVG Zone** | Night vision toggle zone radius, height above head, brightness, mono vision |

---

## Grip Adjust Mode

Dial in weapon grip position and rotation **while in-game** without editing files manually.

1. Draw a weapon (grip near a holster zone)
2. Press **X (left)** *(without the off-hand gripping)* → controller prints "ADJUST MODE ON" to the debug log
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

## Foregrip Adjust Mode

Align the weapon model's foregrip with where your off-hand controller actually sits when
you use a two-hand grip. This affects **aim direction only** — the dominant-hand grip
position is unchanged.

1. Draw a weapon and grab with the off-hand (support grip)
2. Press **X (left)** while the off-hand is gripping → controller prints "FG ADJUST MODE ON"
3. Use the sticks to tune the foregrip offset:

| Input | Adjusts |
|-------|---------|
| Left stick X | Foregrip left / right (X) |
| Left stick Y | Foregrip up / down (Y) |
| Right stick Y | Foregrip forward / back (Z) |

4. Press **A (right)** to save to `default_config.json` and exit
5. Press **X (left)** again to discard changes and exit

The mode also exits automatically if you release the off-hand grip.

---

## Optic Rail Adjust Mode

Slide a mounted optic forward and backward along the weapon rail **while in-game**.

1. Draw a weapon that has a railed optic attached
2. **Hold X (left) for 0.3 s** → controller buzzes to confirm Rail Mode is on
3. Move the optic using either method:

**Physical grab (preferred):**

| Input | Action |
|-------|--------|
| Support hand trigger | Grab the optic |
| Move support hand forward / back | Slide optic along rail |
| Release support hand trigger | Release grab |

**Stick method:**

| Input | Action |
|-------|--------|
| Right stick up | Slide optic forward |
| Right stick down | Slide optic backward |

4. Press **X (left)** again, or holster / lower the weapon, to exit Rail Mode

Both methods can be used interchangeably. A haptic pulse confirms each rail increment.

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

### Foregrip Offsets

Offsets that shift the effective off-hand reference point for two-hand aim direction.
Affects only the aim vector — the dominant-hand grip position is unchanged.
Tuned live via **Foregrip Adjust Mode** (X while off-hand gripping).

```json
"foregrip_offsets": {
    "1": { "x": 0.0, "y": 0.0, "z": 0.0 },
    "2": { "x": 0.0, "y": 0.0, "z": 0.0 },
    "3": { "x": 0.0, "y": 0.0, "z": 0.0 },
    "4": { "x": 0.0, "y": 0.0, "z": 0.0 }
}
```

| Field | Description |
|-------|-------------|
| `x` | Left / right shift of the foregrip reference point (metres) |
| `y` | Up / down shift (metres) |
| `z` | Forward / back shift (metres) |

### World Scale

```json
"xr": { "world_scale": 1.0 }
```

Adjust if the world feels too large or too small. Values above `1.0` make you feel
taller; below `1.0` makes the world feel bigger.

### Two-Hand Aim Stabilization

```json
"comfort": { "two_hand_smooth_enabled": true, "two_hand_smooth_speed": 12.0 }
```

When gripping with the support hand, the aim direction is smoothed each frame to reduce
jitter and hand tremor. Higher speed values (range 2–30) track your hands more closely;
lower values give a floatier, more stabilized feel. Toggle and speed are both tunable live
in the **F8 config screen → Comfort** section ("2H Stabilize" and "2H Smooth").

---

### Render Scale

```json
"xr": { "render_scale": 1.0 }
```

Scales the VR render target resolution. Lower values improve performance at the cost of
sharpness. `0.75` is a good balance; `0.5` is aggressive but useful on weaker hardware.
Also tunable live in the **F8 config screen → Comfort** section.

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
