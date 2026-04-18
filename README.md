# Road to Vostok — VR Mod v1.1.5

A VR mod for **Road to Vostok** (Early Access). Play the full game in
virtual reality with full head tracking, motion controllers, and physical weapon handling.

---

## Requirements

- Road to Vostok installed via Steam
- A PC VR headset supported by OpenXR (Meta Quest via Link/AirLink, Valve Index, HTC Vive, WMR, etc.)

---

## Installation

### Step 1 — Install Metro Mod Loader

Install [Metro Mod Loader](https://modworkshop.net/mod/55623) by following its instructions.

### Step 2 — Extract the VR mod

Extract `vr-mod-full.zip` directly into the game root. You should end up with:

```
Road to Vostok\
  launch_vr.bat
  rtv_vr_bootstrap.dll
  librtv_vr_mod.windows.x86_64.dll
  mods\
    vr-mod.vmz
  VR Mod\
    README.md
    LICENSE
    THIRD_PARTY.md
    bin\
      rtv_vr_injector.exe
    resources\
      override.cfg
      rtv_vr_mod.gdextension
```

### Step 3 — Launch

Put on your headset, start SteamVR (or Meta PC app), then launch using **`launch_vr.bat`** in the game root — do **not** use Steam's Play button directly.

The Headset will have a black screen at the main menu.  It won't display anything until the world loads in.

Config and debug log are written to `%APPDATA%\Road to Vostok\vr_mod\`.

**To update the mod** (no native changes): replace `mods\vr-mod.vmz` with the new version — no other files need to be touched.

**To disable the mod:** remove or rename `mods\vr-mod.vmz` and replace override.cfg with Metro Mod Loader's version.

---

## Controls

### Movement

| Input | Action |
|-------|--------|
| Left stick | Move (forward / strafe) |
| Right stick left / right | Turn |
| A (right) | Jump / click UI button (when menu open) |
| Y (left) | Open / close inventory |
| Left stick click | Sprint |
| Right stick click | Crouch |
| Menu button | Pause / escape |
| X (left, weapon holstered, quick tap) | Toggle flashlight *(disabled when menu open)* |
| X (left, weapon holstered, hold 0.5 s) | Enter shelter decoration mode *(disabled when menu open)* |
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
| B (right, weapon drawn) | Cycle fire mode (standard weapons) / Open or close action (bolt-action & shotgun) |
| B (right, weapon lowered) | Interact with objects |
| X (left, while weapon drawn, quick tap) | Enter grip adjust mode *(Gun Config must be On)* |
| X (left, while weapon drawn, off-hand gripping, quick tap) | Enter foregrip adjust mode *(Gun Config must be On)* |
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

### Bolt-action Rifles & Pump-action Shotguns

These weapons require manually cycling the action between shots. **B** opens and closes
the loading port instead of changing fire mode.

**Loading:**

1. Press **B** to open the action
2. Press **support hand trigger** (without gripping for two-hand aim) to load one round or shell — repeat until full
3. Press **B** again to close the action

**Cycling between shots:**

| Weapon type | Action |
|-------------|--------|
| Bolt-action | Lower the weapon (release grip away from body), then press **dominant trigger** — the bolt cycles and the weapon automatically raises back |
| Pump-action shotgun | Grab with the **support hand grip**, then make a quick pump motion (push forward, pull back) — one shell is chambered per pump |

### Scope Zoom

On variable-zoom scopes, push **right stick up** to zoom in and **right stick down** to
zoom out while the weapon is drawn. A haptic pulse confirms each step.

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
| A (right) | Click button under laser |
| Dominant trigger (hold + move) | Drag item |
| Dominant grip | Right-click / context menu |
| X (left) | Rotate dragged item |
| Support grip (hold) + Trigger | Fast transfer (Ctrl + click) |
| Right stick up / down | Scroll |

**Clicking buttons:** Point the laser at a button and press **A** — the click is instantaneous so the cursor cannot drift between press and release.

**Dragging items:** Point at an item, **hold the trigger** to pick it up, move the controller to the destination, then release.

**Fast transfer:** Hold the **support hand grip** to activate a Ctrl modifier, then press **A** on each item you want to move. Release the support grip when done.

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

Press **F8** at any time during gameplay to open the VR settings panel. 
Press **Save & Close** to write all settings to `vr_mod_config.json`.
Press **Cancel** to discard changes for this session.

---

## Grip Adjust Mode

Dial in weapon grip position and rotation **while in-game** without editing files manually.

> **Requires Gun Config to be On** — enable it in the F8 config screen under **Controls**.

1. Draw a weapon (grip near a holster zone)
2. Press **X (left)** *(without the off-hand gripping)* → controller prints "ADJUST MODE ON" to the debug log
3. Use the sticks to tune:

| Input | Adjusts |
|-------|---------|
| Left stick X | Grip left / right (X) |
| Left stick Y | Grip up / down (Y) |
| Right stick X | Weapon rotation (Y axis) |
| Right stick Y | Grip forward / back (Z) |

4. Press **A (right)** to save the current slot's values to `vr_mod_config.json` and exit
5. Press **X (left)** again to discard changes and exit

Movement and turning are disabled while adjust mode is active. The mode exits
automatically if you lower or holster the weapon.

---

## Foregrip Adjust Mode

Calibrate exactly where the support hand visually grips the weapon during two-hand aiming.
The weapon model is frozen in place so you can position your hand precisely.

> **Requires Gun Config to be On** — enable it in the F8 config screen under **Controls**.

1. Draw a weapon and grab with the off-hand (support grip)
2. Press **X (left)** while the off-hand is gripping → the gun freezes in place
3. **Physically move your support hand** to the foregrip position on the frozen weapon
4. Press **A (right)** to save the current hand position as the foregrip point
5. Press **X (left)** to discard and exit without saving

The mode also exits automatically if you release the off-hand grip.

Once saved, the support hand visual will lock to that exact point on the weapon every time
you use a two-hand grip — regardless of where your controller physically is.

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

4. Release **X (left)** , or holster / lower the weapon, to exit Rail Mode

Both methods can be used interchangeably. A haptic pulse confirms each rail increment.

---

---

## Troubleshooting

**Black screen in headset after launch**
Make sure SteamVR or the Meta PC app is running *before* you start the game.
The Main Menu launches VR into a black screen, but a VR camera is not started until the world actually loads in.

**Mod behaves like an older version / changes have no effect**
A stale `vr_mod_init.gd` in the game root (`Road to Vostok\vr_mod_init.gd`) overrides the
script inside the VMZ. Delete that file — Metro loads the correct version from `mods\vr-mod.vmz`.

**Weapon floats at wrong position**
Enable **Gun Config** in F8 → Controls, then use Grip Adjust Mode (X while weapon drawn) to tune the grip offset live.
If the issue persists across sessions, check `vr_mod_debug.log` in `%APPDATA%\Road to Vostok\vr_mod\`.

**Can't click buttons in menu screens**
Click on buttons with 'A' button instead of trigger.
