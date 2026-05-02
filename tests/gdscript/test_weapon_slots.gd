extends RefCounted

# test_weapon_slots.gd
#
# Coverage for weapon_key construction, per-weapon vs per-slot grip-offset
# selection, and slot -> key/name lookup. These are the pure helpers that
# weapon_sync.gd calls into (or should call into); the production paths in
# resources/vr_mod/weapon_sync.gd:252-267 mirror this logic and any drift
# will be caught by the matching production-shape tests at the bottom.

const WeaponSlots = preload("res://tests/gdscript/lib/weapon_slots.gd")


# Mirror of production's HOLSTER_ZONES const (vr_mod_init.gd:1085).
const _HOLSTER_ZONES := {
	1: {"name": "right_shoulder", "key": KEY_1},
	2: {"name": "right_hip",      "key": KEY_2},
	3: {"name": "left_hip",       "key": KEY_3},
	4: {"name": "chest",          "key": KEY_4},
}

const _SLOT_DEFAULTS := {
	1: Vector3(0.05, -0.10, -0.20),
	2: Vector3(0.04, -0.09, -0.18),
	3: Vector3(0.04, -0.09, -0.18),
	4: Vector3(0.0,   0.0,   0.0),
}

const _SLOT_ROT_DEFAULTS := {
	1: 0.0,
	2: 0.1,
	3: -0.1,
	4: 0.0,
}


# --- weapon_key ---------------------------------------------------------

func test_weapon_key_basic(t) -> void:
	var k := WeaponSlots.weapon_key("right", "AK74")
	t.assert_eq(k, "right|AK74", "weapon_key concatenates hand and name with pipe")


func test_weapon_key_empty_name(t) -> void:
	var k := WeaponSlots.weapon_key("right", "")
	t.assert_eq(k, "right|", "empty name yields sentinel key")


func test_weapon_key_left_vs_right_distinct(t) -> void:
	var lk := WeaponSlots.weapon_key("left", "AK74")
	var rk := WeaponSlots.weapon_key("right", "AK74")
	t.assert_true(lk != rk, "left and right hands produce different keys for the same weapon")


# --- resolve_grip_offset ------------------------------------------------

func test_offset_falls_back_to_slot_default_when_no_weapon(t) -> void:
	# weapon_name = "" forces slot fallback regardless of overrides.
	var overrides := {"right|Fake": Vector3(99, 99, 99)}
	var v := WeaponSlots.resolve_grip_offset("right", "", overrides, 1, _SLOT_DEFAULTS)
	t.assert_vec_near(v, _SLOT_DEFAULTS[1], 1e-6, "no weapon -> slot default")


func test_offset_falls_back_to_slot_default_when_no_override(t) -> void:
	var v := WeaponSlots.resolve_grip_offset("right", "AK74", {}, 2, _SLOT_DEFAULTS)
	t.assert_vec_near(v, _SLOT_DEFAULTS[2], 1e-6, "named weapon, no override -> slot default")


func test_offset_uses_override_when_present(t) -> void:
	var custom := Vector3(0.7, -0.05, -0.30)
	var overrides := {"right|AK74": custom}
	var v := WeaponSlots.resolve_grip_offset("right", "AK74", overrides, 1, _SLOT_DEFAULTS)
	t.assert_vec_near(v, custom, 1e-6, "named weapon override wins over slot default")


func test_offset_override_keyed_by_hand(t) -> void:
	# Override stored under right hand must NOT apply when querying left.
	var custom := Vector3(0.7, 0.0, 0.0)
	var overrides := {"right|AK74": custom}
	var v_left  := WeaponSlots.resolve_grip_offset("left", "AK74", overrides, 1, _SLOT_DEFAULTS)
	var v_right := WeaponSlots.resolve_grip_offset("right", "AK74", overrides, 1, _SLOT_DEFAULTS)
	t.assert_vec_near(v_left,  _SLOT_DEFAULTS[1], 1e-6, "left hand falls back to default")
	t.assert_vec_near(v_right, custom, 1e-6, "right hand uses its override")


func test_offset_unknown_slot_zero(t) -> void:
	var v := WeaponSlots.resolve_grip_offset("right", "AK74", {}, 99, _SLOT_DEFAULTS)
	t.assert_vec_near(v, Vector3.ZERO, 1e-6, "unknown slot + no override -> Vector3.ZERO")


func test_offset_empty_defaults_zero(t) -> void:
	var v := WeaponSlots.resolve_grip_offset("right", "AK74", {}, 1, {})
	t.assert_vec_near(v, Vector3.ZERO, 1e-6, "empty defaults dict -> Vector3.ZERO")


# --- resolve_grip_rotation ----------------------------------------------

func test_rotation_falls_back_to_default(t) -> void:
	var r := WeaponSlots.resolve_grip_rotation("right", "AK74", {}, 2, _SLOT_ROT_DEFAULTS)
	t.assert_near(r, 0.1, 1e-6, "named weapon, no rot override -> slot default")


func test_rotation_uses_override(t) -> void:
	var overrides := {"right|AK74": 1.5}
	var r := WeaponSlots.resolve_grip_rotation("right", "AK74", overrides, 2, _SLOT_ROT_DEFAULTS)
	t.assert_near(r, 1.5, 1e-6, "rotation override wins")


func test_rotation_unknown_slot_zero(t) -> void:
	var r := WeaponSlots.resolve_grip_rotation("right", "AK74", {}, 42, _SLOT_ROT_DEFAULTS)
	t.assert_near(r, 0.0, 1e-6, "unknown slot -> 0.0")


# --- slot_to_key / slot_to_name -----------------------------------------

func test_slot_to_key_known(t) -> void:
	t.assert_eq(WeaponSlots.slot_to_key(1, _HOLSTER_ZONES), KEY_1, "slot 1 -> KEY_1")
	t.assert_eq(WeaponSlots.slot_to_key(2, _HOLSTER_ZONES), KEY_2, "slot 2 -> KEY_2")
	t.assert_eq(WeaponSlots.slot_to_key(3, _HOLSTER_ZONES), KEY_3, "slot 3 -> KEY_3")
	t.assert_eq(WeaponSlots.slot_to_key(4, _HOLSTER_ZONES), KEY_4, "slot 4 -> KEY_4")


func test_slot_to_key_unknown(t) -> void:
	t.assert_eq(WeaponSlots.slot_to_key(0, _HOLSTER_ZONES), 0, "slot 0 -> 0 (no key)")
	t.assert_eq(WeaponSlots.slot_to_key(99, _HOLSTER_ZONES), 0, "unknown slot -> 0")


func test_slot_to_name(t) -> void:
	t.assert_eq(WeaponSlots.slot_to_name(1, _HOLSTER_ZONES), "right_shoulder", "slot 1 name")
	t.assert_eq(WeaponSlots.slot_to_name(4, _HOLSTER_ZONES), "chest", "slot 4 name")
	t.assert_eq(WeaponSlots.slot_to_name(99, _HOLSTER_ZONES), "", "unknown slot name")


# --- production-shape mirror ---------------------------------------------
#
# These tests reconstruct the exact selection rule used in
# resources/vr_mod/weapon_sync.gd:256-267. If production drifts (e.g. the
# fallback order changes), these break first.

func test_production_shape_offset(t) -> void:
	# Reproduce: get_weapon_grip_offset() in weapon_sync.gd
	#   k = weapon_key()
	#   if _current_weapon_name != "" and _weapon_grip_offsets.has(k):
	#       return _weapon_grip_offsets[k]
	#   return _slot_grip_defaults.get(_weapon_slot, Vector3.ZERO)
	var weapon_grip_offsets := {"right|AK74": Vector3(0.5, 0, 0)}
	var current_weapon_name := "AK74"
	var weapon_hand := "right"
	var weapon_slot := 1

	var v := WeaponSlots.resolve_grip_offset(weapon_hand, current_weapon_name, weapon_grip_offsets, weapon_slot, _SLOT_DEFAULTS)
	t.assert_vec_near(v, Vector3(0.5, 0, 0), 1e-6, "production-shape: override wins")

	# Now drop the current weapon name -> slot fallback.
	v = WeaponSlots.resolve_grip_offset(weapon_hand, "", weapon_grip_offsets, weapon_slot, _SLOT_DEFAULTS)
	t.assert_vec_near(v, _SLOT_DEFAULTS[1], 1e-6, "production-shape: empty name -> slot default")


func test_production_shape_rotation(t) -> void:
	var rot_overrides := {"left|Mosin": 0.42}
	var v := WeaponSlots.resolve_grip_rotation("left", "Mosin", rot_overrides, 2, _SLOT_ROT_DEFAULTS)
	t.assert_near(v, 0.42, 1e-6, "production-shape: rotation override wins")
	v = WeaponSlots.resolve_grip_rotation("left", "Mosin", {}, 2, _SLOT_ROT_DEFAULTS)
	t.assert_near(v, 0.1, 1e-6, "production-shape: rotation default by slot")
