extends RefCounted

# test_input_routing.gd
#
# Coverage for the input-mode routing decision tree. The production
# implementation lives inline in vr_mod_init.gd:_on_button_pressed; these
# tests pin down the priority order so any future refactor that hoists the
# logic into its own dispatcher must preserve the same observable routing.

const InputRouting = preload("res://tests/gdscript/lib/input_routing.gd")

# Mirror HolsterState.UNARMED / DRAWN / LOWERED / SLING constants.
# The actual int values don't matter to the routing helpers as long as we
# pass the same numbers through everywhere.
const _UNARMED := 0
const _DRAWN   := 1
const _LOWERED := 2
const _SLING   := 3


# --- is_weapon_hand -----------------------------------------------------

func test_unarmed_uses_dominant_hand(t) -> void:
	# Right-handed config, no weapon held: right hand is weapon hand.
	var rw := InputRouting.is_weapon_hand("right", _UNARMED, _UNARMED, _SLING, "", "right")
	var lw := InputRouting.is_weapon_hand("left",  _UNARMED, _UNARMED, _SLING, "", "right")
	t.assert_true(rw, "UNARMED right-dominant: right is weapon hand")
	t.assert_true(not lw, "UNARMED right-dominant: left is support hand")


func test_sling_uses_dominant_hand(t) -> void:
	# Slung weapon: dominant hand still drives the role mapping (so menu
	# fast-transfer works).
	var w := InputRouting.is_weapon_hand("right", _SLING, _UNARMED, _SLING, "left", "right")
	t.assert_true(w, "SLING with last grab=left: dominant=right still wins")


func test_drawn_uses_weapon_hand(t) -> void:
	# Held weapon: whichever hand grabbed it is the weapon hand, regardless
	# of dominant config.
	var lw := InputRouting.is_weapon_hand("left",  _DRAWN, _UNARMED, _SLING, "left", "right")
	var rw := InputRouting.is_weapon_hand("right", _DRAWN, _UNARMED, _SLING, "left", "right")
	t.assert_true(lw, "DRAWN left-handed grab: left is weapon hand")
	t.assert_true(not rw, "DRAWN left-handed grab: right is support hand")


func test_lowered_uses_weapon_hand(t) -> void:
	var lw := InputRouting.is_weapon_hand("left", _LOWERED, _UNARMED, _SLING, "left", "right")
	t.assert_true(lw, "LOWERED follows last weapon hand")


# --- resolve_mode -------------------------------------------------------

func test_default_when_unarmed_no_modes(t) -> void:
	var m := InputRouting.resolve_mode("trigger_click", "right", false, false, false, _UNARMED, _DRAWN)
	t.assert_eq(m, "default", "unarmed + nothing else open -> default")


func test_weapon_when_drawn_no_modes(t) -> void:
	var m := InputRouting.resolve_mode("trigger_click", "right", false, false, false, _DRAWN, _DRAWN)
	t.assert_eq(m, "weapon", "drawn + nothing else open -> weapon")


func test_interface_beats_weapon(t) -> void:
	# Inventory open while drawn -> interface routing (menu clicks, not fire)
	var m := InputRouting.resolve_mode("trigger_click", "right", false, true, false, _DRAWN, _DRAWN)
	t.assert_eq(m, "interface", "interface open beats weapon mode")


func test_config_beats_interface(t) -> void:
	var m := InputRouting.resolve_mode("trigger_click", "right", false, true, true, _DRAWN, _DRAWN)
	t.assert_eq(m, "config", "config screen beats interface")


func test_decor_beats_weapon_and_config(t) -> void:
	# Decor mode (interface NOT open) beats every other mode.
	var m := InputRouting.resolve_mode("trigger_click", "right", true, false, true, _DRAWN, _DRAWN)
	t.assert_eq(m, "decor", "decor wins when interface is closed")


func test_decor_y_tab_passthrough(t) -> void:
	# Decor + interface + Y on left -> dedicated label so caller sends TAB.
	var m := InputRouting.resolve_mode("by_button", "left", true, true, false, _UNARMED, _DRAWN)
	t.assert_eq(m, "decor_y_tab", "decor+interface+Y(left) -> decor_y_tab")


func test_decor_with_interface_other_buttons_not_decor(t) -> void:
	# Once interface is open under decor, other buttons fall back to interface.
	var m := InputRouting.resolve_mode("ax_button", "right", true, true, false, _UNARMED, _DRAWN)
	t.assert_eq(m, "interface", "decor+interface+A(right) -> interface (not decor)")


func test_decor_with_interface_y_right_not_special(t) -> void:
	# The decor_y_tab pass-through is left-hand only.
	var m := InputRouting.resolve_mode("by_button", "right", true, true, false, _UNARMED, _DRAWN)
	t.assert_eq(m, "interface", "decor+interface+Y(right) -> interface")


# --- falls_through_to_default ------------------------------------------

func test_decor_does_not_fall_through(t) -> void:
	t.assert_true(not InputRouting.falls_through_to_default("decor"), "decor short-circuits")
	t.assert_true(not InputRouting.falls_through_to_default("decor_y_tab"), "decor_y_tab short-circuits")


func test_other_modes_fall_through(t) -> void:
	# config / interface / weapon / default share the trailing match block.
	t.assert_true(InputRouting.falls_through_to_default("config"), "config falls through")
	t.assert_true(InputRouting.falls_through_to_default("interface"), "interface falls through")
	t.assert_true(InputRouting.falls_through_to_default("weapon"), "weapon falls through")
	t.assert_true(InputRouting.falls_through_to_default("default"), "default falls through")
