extends RefCounted

# zone_math.gd
#
# Pure geometric helpers for VR holster / bag / NVG zones. Extracted into a
# standalone module so they can be exercised by the headless test harness
# without instantiating the full XR rig + autoload graph.
#
# These mirror the production formulas in resources/vr_mod/holster.gd
# (refresh_holster_zone_cache + get_nearby_holster_zone) and
# resources/vr_mod/grab.gd (is_in_bag_zone + is_in_nvg_zone). When changing
# either side, change both.


# Compute the world-space position of a single holster slot.
#
# head_pos     : XR camera world position
# head_yaw     : camera yaw in radians (camera global_rotation.y)
# offset       : per-slot body-relative offset (right-positive +X, up +Y, forward -Z)
# mirrored     : if true, mirror across body midline (negate offset.x)
static func holster_zone_world_pos(head_pos: Vector3, head_yaw: float, offset: Vector3, mirrored: bool) -> Vector3:
	var yaw_basis := Basis(Vector3.UP, head_yaw)
	var eff := Vector3(-offset.x, offset.y, offset.z) if mirrored else offset
	return head_pos + yaw_basis * eff


# Find the nearest holster slot whose zone contains controller_pos.
# Returns 0 if no slot is within radius.
#
# offsets    : Dictionary { slot_int: Vector3 }
# zone_keys  : Array of slot ints to test (typically [1,2,3,4])
static func nearest_holster_slot(
	controller_pos: Vector3,
	head_pos: Vector3,
	head_yaw: float,
	offsets: Dictionary,
	zone_keys: Array,
	radius: float,
	mirrored: bool
) -> int:
	var closest_slot := 0
	var closest_dist := radius
	for slot in zone_keys:
		if not offsets.has(slot):
			continue
		var zone_pos := holster_zone_world_pos(head_pos, head_yaw, offsets[slot], mirrored)
		var d := controller_pos.distance_to(zone_pos)
		if d < closest_dist:
			closest_dist = d
			closest_slot = slot
	return closest_slot


# Bag-zone test: world_pos is "in the bag" if it lands inside a sphere
# anchored at body-relative bag_zone_offset (yaw-only, no pitch/roll).
static func is_in_bag_zone(
	world_pos: Vector3,
	head_pos: Vector3,
	head_yaw: float,
	bag_zone_offset: Vector3,
	bag_zone_radius: float
) -> bool:
	var yaw_basis := Basis(Vector3.UP, head_yaw)
	var local := yaw_basis.inverse() * (world_pos - head_pos)
	return local.distance_to(bag_zone_offset) < bag_zone_radius


# NVG-zone test: world_pos is "above the head" if it lands inside a sphere
# anchored at head_pos + nvg_zone_offset (offset is world-up only — no yaw).
static func is_in_nvg_zone(
	world_pos: Vector3,
	head_pos: Vector3,
	nvg_zone_offset: Vector3,
	nvg_zone_radius: float
) -> bool:
	return world_pos.distance_to(head_pos + nvg_zone_offset) < nvg_zone_radius
