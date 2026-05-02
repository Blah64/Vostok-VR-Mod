extends RefCounted

# input_routing.gd
#
# Pure mode-routing helpers for VR controller button presses. Captures the
# decision tree currently inlined in vr_mod_init.gd:_on_button_pressed.
#
# Routing modes (in priority order):
#   "decor_y_tab" -- decor + interface open + button by_button on left
#                    (special pass-through so Y -> TAB still works inside the
#                    furniture inventory while decor is active)
#   "decor"       -- decor mode active, interface NOT open
#   "config"      -- F8 config screen quad open
#   "interface"   -- main menu / inventory / loot panel open
#   "weapon"      -- holster state == DRAWN
#   "default"     -- everything else (UNARMED / LOWERED / SLING)
#
# When the route is "decor" the calling code performs decor-specific button
# remaps and then RETURNS without falling through. The other modes are
# advisory: weapon_sync vs default still share button handlers but route
# through different state machines.


# Hand role resolution: which hand is "weapon" vs "support" depends on
# holster state. UNARMED and SLING use the configured dominant hand;
# DRAWN/LOWERED use whichever hand is currently holding the weapon.
#
# Returns true iff `hand` is the weapon hand under the current state.
static func is_weapon_hand(
	hand: String,
	holster_state: int,
	state_unarmed: int,
	state_sling: int,
	weapon_hand: String,
	dominant_hand: String
) -> bool:
	var use_dominant := (holster_state == state_unarmed) or (holster_state == state_sling)
	if use_dominant:
		return hand == dominant_hand
	return hand == weapon_hand


# Single-call mode resolver. Returns the routing label.
static func resolve_mode(
	button_name: String,
	hand: String,
	decor_mode: bool,
	interface_open: bool,
	config_screen_open: bool,
	holster_state: int,
	state_drawn: int
) -> String:
	# Y-button while decor + interface open is the only press that survives
	# both mode gates -- the Tab pass-through in vr_mod_init.gd:1836-1838.
	if decor_mode and interface_open and button_name == "by_button" and hand == "left":
		return "decor_y_tab"
	if decor_mode and not interface_open:
		return "decor"
	if config_screen_open:
		return "config"
	if interface_open:
		return "interface"
	if holster_state == state_drawn:
		return "weapon"
	return "default"


# Convenience: should the press fall through to the default match block?
# Decor mode short-circuits with "return" in production, so any "decor*"
# label MUST NOT fall through. config / interface / weapon / default DO.
static func falls_through_to_default(mode: String) -> bool:
	return mode != "decor" and mode != "decor_y_tab"
