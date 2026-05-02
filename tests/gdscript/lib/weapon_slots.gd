extends RefCounted

# weapon_slots.gd
#
# Pure helpers for weapon-key construction and slot/offset selection. Mirrors
# the logic in resources/vr_mod/weapon_sync.gd (weapon_key,
# get_weapon_grip_offset, get_weapon_grip_rotation) without needing the
# autoload graph.
#
# Selection contract (from production):
#   weapon_key(hand, weapon_name) = hand + "|" + weapon_name
#   offset = per_weapon_overrides[key] if (weapon_name != "" and override exists)
#            else slot_defaults[slot] if slot in defaults
#            else Vector3.ZERO
#   rotation follows the same pattern with slot_rot_defaults / 0.0


# Build the dictionary key used to store per-weapon grip overrides.
# Empty string for weapon_name produces a sentinel key that is never matched
# by the override path (matches production's "if name != ''" guard).
static func weapon_key(hand: String, weapon_name: String) -> String:
	return hand + "|" + weapon_name


# Resolve the position offset to use for the given weapon.
#
# weapon_name        : "" when no weapon is current; forces slot fallback.
# weapon_overrides   : Dictionary { key_string: Vector3 }
# slot               : int 1..4 (matches HOLSTER_ZONES keys)
# slot_defaults      : Dictionary { slot_int: Vector3 }
static func resolve_grip_offset(
	hand: String,
	weapon_name: String,
	weapon_overrides: Dictionary,
	slot: int,
	slot_defaults: Dictionary
) -> Vector3:
	if weapon_name != "":
		var k := weapon_key(hand, weapon_name)
		if weapon_overrides.has(k):
			return weapon_overrides[k]
	if slot_defaults.has(slot):
		return slot_defaults[slot]
	return Vector3.ZERO


# Same selection rule for grip rotation (single float, not Vector3).
static func resolve_grip_rotation(
	hand: String,
	weapon_name: String,
	rot_overrides: Dictionary,
	slot: int,
	slot_rot_defaults: Dictionary
) -> float:
	if weapon_name != "":
		var k := weapon_key(hand, weapon_name)
		if rot_overrides.has(k):
			return rot_overrides[k]
	if slot_rot_defaults.has(slot):
		return slot_rot_defaults[slot]
	return 0.0


# Resolve the keybind for "draw weapon at slot N" from HOLSTER_ZONES-shaped
# data. Returns 0 if the slot is unknown.
static func slot_to_key(slot: int, holster_zones: Dictionary) -> int:
	if not holster_zones.has(slot):
		return 0
	var entry: Dictionary = holster_zones[slot]
	return entry.get("key", 0)


# Resolve the human-readable name for a slot (right_shoulder / right_hip /
# left_hip / chest). Returns "" if the slot is unknown.
static func slot_to_name(slot: int, holster_zones: Dictionary) -> String:
	if not holster_zones.has(slot):
		return ""
	var entry: Dictionary = holster_zones[slot]
	return entry.get("name", "")
