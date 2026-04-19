# VR Mod Controls

## Movement

| Input | Action |
|-------|--------|
| Left stick | Move (forward / strafe) |
| Right stick left / right | Turn |
| A (right) | Jump / click UI button (when menu open) |
| Y (left) | Open / close inventory |
| Left stick click | Sprint |
| Right stick click | Crouch |
| Both stick clicks | Open / close VR config screen |
| Menu button | Pause / escape |
| X (left, weapon holstered, quick tap) | Toggle flashlight |
| X (left, weapon holstered, hold 0.5 s) | Enter shelter decoration mode |
| Trigger (above head, unarmed) | Toggle night vision goggles |

## Holster System

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
| Release grip (slot 1, away from body) | Sling — weapon hangs at chest height |
| Release grip (slots 2-4, away from body) | Auto-holster immediately |
| Release grip near own holster zone | Holster completely |
| Grip near a different holster zone | Swap weapon |

## Sling (Primary Weapon Only)

Releasing your primary weapon (slot 1) away from a holster zone puts it in **sling position** — the weapon hangs at chest height and follows your yaw as you turn.

To raise from sling: grip with either hand.
To holster from sling: grip near your right-shoulder holster zone.

## Weapon

| Input | Action |
|-------|--------|
| Weapon hand trigger | Fire |
| Support hand trigger (quick press) | Reload |
| Support hand trigger (hold 0.5 s) | Ammo check |
| Support hand trigger (while gripping) | Toggle laser attachment |
| Support hand grip | Two-hand grip (stabilised aim) |
| Right stick up / down (variable scope) | Zoom in / out |
| B (right, weapon drawn) | Cycle fire mode / Open action (bolt-action) |
| B (right, weapon lowered) | Interact with objects |
| X (left, weapon drawn, quick tap) | Enter grip adjust mode |
| X (left, weapon drawn, off-hand gripping) | Enter foregrip adjust mode |
| X (left, weapon drawn, hold 0.3 s) | Enter optic rail adjust mode |

> All weapon inputs follow the weapon hand dynamically. If you draw with your left hand, left trigger fires and right trigger reloads.

## Grenades

| Input | Action |
|-------|--------|
| Weapon hand trigger (pin not pulled) | Pull pin — controller buzzes, grenade is armed |
| Weapon hand grip release (pin pulled) | Throw |
| Weapon hand trigger (pin pulled) | Replace pin — disarms grenade |

The grenade auto-holsters 0.5 s after throwing.

## Bolt-action Rifles & Pump-action Shotguns

**Loading:**

1. Press **B** to open the action
2. Press **support hand trigger** to load one round — repeat until full
3. Press **B** again to close the action

**Cycling between shots:**

| Weapon type | Action |
|-------------|--------|
| Bolt-action | Lower weapon (release grip away from body), then press **dominant trigger** |
| Pump-action | Grab with **support hand grip**, then push forward and pull back |

## Grabbing Items

| Input | Action |
|-------|--------|
| Either hand grip (unarmed, near item) | Grab item |
| Release grip near bag zone (behind right shoulder) | Add item to inventory |
| Release grip elsewhere | Drop / throw item |

Release the grip with arm motion to throw — velocity is calculated from your last few hand-position samples.

## Shelter Decoration Mode

**Enter:** Hold X (left) for 0.5 s while unarmed and not holding anything.
**Exit:** Press X (left) or squeeze both grips.

| Input | Action |
|-------|--------|
| Controller aim (dominant) | Aim furniture ghost |
| Right stick up / down | Adjust distance or rotation amount |
| Right grip (single) | Toggle distance / rotation scroll mode |
| Right trigger | Place furniture |
| A (right) | Toggle surface magnet |
| B (right) | Store item to furniture inventory |
| Y (left) | Open furniture inventory |
| Left stick | Move around the shelter |

## Laser Colors

| Color | Meaning |
|-------|---------|
| Red | Nothing interactable in range |
| Green | Grabbable loose item in range |
| Yellow | B-button interactable (trader, loot pool, etc.) |
| Blue | Menu / inventory open — 5 m UI pointer |
| Cyan | Decor mode — aiming for furniture placement |
| Orange | Decor mode — pointing at moveable furniture |

## Inventory / UI

| Input | Action |
|-------|--------|
| A (right) | Click button under laser |
| Dominant trigger (hold + move) | Drag item |
| Dominant grip | Right-click / context menu |
| X (left) | Rotate dragged item |
| Support grip (hold) + Trigger | Fast transfer (Ctrl + click) |
| Right stick up / down | Scroll |

---

## Grip Adjust Mode

Dial in weapon grip position and rotation live in-game.

> Requires **Gun Config** to be On — enable in F8 config under Controls.

1. Draw a weapon
2. Press **X (left)** (without off-hand gripping) to enter
3. Tune with the sticks:

| Input | Adjusts |
|-------|---------|
| Left stick X | Grip left / right |
| Left stick Y | Grip up / down |
| Right stick X | Weapon rotation |
| Right stick Y | Grip forward / back |

4. Press **A (right)** to save and exit
5. Press **X (left)** to discard and exit

## Foregrip Adjust Mode

Calibrate where the support hand visually grips the weapon during two-hand aiming.

> Requires **Gun Config** to be On.

1. Draw a weapon and grab with the off-hand
2. Press **X (left)** while off-hand is gripping — gun freezes in place
3. Physically move your support hand to the foregrip position
4. Press **A (right)** to save, or **X (left)** to discard

## Optic Rail Adjust Mode

Slide a mounted optic forward and backward along the rail live in-game.

1. Draw a weapon with a railed optic
2. Hold **X (left) for 0.3 s** to enter rail mode
3. Slide using the support hand trigger (grab + move) or right stick up / down
4. Release **X (left)** or holster to exit

---

## In-Game Config Screen

Press **F8** or click both thumbsticks during gameplay to open the VR settings panel.
Press **Save & Close** to write all settings to `vr_mod_config.json`.
Press **Cancel** to discard changes.
