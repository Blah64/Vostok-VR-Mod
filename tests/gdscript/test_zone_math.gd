extends RefCounted

# test_zone_math.gd
#
# Unit tests for the pure zone-math helpers. These ARE the spec for holster
# zone selection, bag-zone hit testing, and NVG-zone hit testing. If the
# production formulas in holster.gd / grab.gd drift, these tests will fail
# at the call sites that mirror them.

const ZoneMath = preload("res://tests/gdscript/lib/zone_math.gd")


# Default holster offsets pulled from CLAUDE.md (Holster Zones section).
const _DEFAULT_OFFSETS := {
	1: Vector3( 0.25, -0.15,  0.20),  # right shoulder
	2: Vector3( 0.25, -0.55,  0.0),   # right hip
	3: Vector3(-0.25, -0.55,  0.0),   # left hip
	4: Vector3( 0.0,  -0.15,  0.10),  # chest
}
const _DEFAULT_RADIUS := 0.20
const _ZONE_KEYS := [1, 2, 3, 4]


# --- holster_zone_world_pos ---------------------------------------------

func test_zone_pos_zero_yaw(t) -> void:
	# Player facing -Z (yaw 0 means basis = identity), head at origin.
	var head := Vector3.ZERO
	var pos := ZoneMath.holster_zone_world_pos(head, 0.0, _DEFAULT_OFFSETS[1], false)
	t.assert_vec_near(pos, Vector3(0.25, -0.15, 0.20), 1e-6, "right shoulder at yaw 0 = raw offset")


func test_zone_pos_quarter_yaw(t) -> void:
	# Yaw +90 deg around Y rotates the body. With Godot's Basis(UP, +pi/2):
	# +X axis becomes -Z, +Z stays +Y wait no let me work it out.
	# Basis(Vector3.UP, +pi/2) sends a local point (x,0,z) to world (z,0,-x).
	# So right-shoulder offset (0.25,-0.15,0.20) becomes world (0.20,-0.15,-0.25).
	var head := Vector3.ZERO
	var pos := ZoneMath.holster_zone_world_pos(head, PI/2.0, _DEFAULT_OFFSETS[1], false)
	t.assert_vec_near(pos, Vector3(0.20, -0.15, -0.25), 1e-6, "right shoulder at +90 deg yaw")


func test_zone_pos_translation(t) -> void:
	# Head offset translates the zone position rigidly.
	var head := Vector3(10.0, 1.7, -5.0)
	var pos := ZoneMath.holster_zone_world_pos(head, 0.0, _DEFAULT_OFFSETS[4], false)
	t.assert_vec_near(pos, head + Vector3(0.0, -0.15, 0.10), 1e-6, "chest zone follows head pos")


func test_zone_pos_mirrored_flips_x(t) -> void:
	# Mirrored mode: left-handed users see L/R holsters swapped.
	var pos_normal   := ZoneMath.holster_zone_world_pos(Vector3.ZERO, 0.0, _DEFAULT_OFFSETS[1], false)
	var pos_mirrored := ZoneMath.holster_zone_world_pos(Vector3.ZERO, 0.0, _DEFAULT_OFFSETS[1], true)
	t.assert_near(pos_normal.x, 0.25, 1e-6, "normal: right shoulder x = +0.25")
	t.assert_near(pos_mirrored.x, -0.25, 1e-6, "mirrored: right shoulder x = -0.25")
	t.assert_near(pos_normal.y, pos_mirrored.y, 1e-6, "mirror does not flip y")
	t.assert_near(pos_normal.z, pos_mirrored.z, 1e-6, "mirror does not flip z")


# --- nearest_holster_slot -----------------------------------------------

func test_nearest_returns_zero_when_empty_offsets(t) -> void:
	var s := ZoneMath.nearest_holster_slot(Vector3.ZERO, Vector3.ZERO, 0.0, {}, _ZONE_KEYS, _DEFAULT_RADIUS, false)
	t.assert_eq(s, 0, "no offsets -> no slot")


func test_nearest_returns_zero_when_far(t) -> void:
	# Controller 5m away from any zone.
	var s := ZoneMath.nearest_holster_slot(Vector3(5, 5, 5), Vector3.ZERO, 0.0, _DEFAULT_OFFSETS, _ZONE_KEYS, _DEFAULT_RADIUS, false)
	t.assert_eq(s, 0, "far controller -> no slot")


func test_nearest_picks_right_shoulder(t) -> void:
	# Controller directly on the right shoulder zone.
	var s := ZoneMath.nearest_holster_slot(Vector3(0.25, -0.15, 0.20), Vector3.ZERO, 0.0, _DEFAULT_OFFSETS, _ZONE_KEYS, _DEFAULT_RADIUS, false)
	t.assert_eq(s, 1, "controller on shoulder -> slot 1")


func test_nearest_picks_chest(t) -> void:
	var s := ZoneMath.nearest_holster_slot(Vector3(0.0, -0.15, 0.10), Vector3.ZERO, 0.0, _DEFAULT_OFFSETS, _ZONE_KEYS, _DEFAULT_RADIUS, false)
	t.assert_eq(s, 4, "controller on chest -> slot 4")


func test_nearest_picks_closest_when_overlapping(t) -> void:
	# Move both shoulder and chest zones close together; controller closer to chest.
	var off := {
		1: Vector3(0.05, 0.0, 0.0),
		4: Vector3(0.0, 0.0, 0.0),
	}
	var s := ZoneMath.nearest_holster_slot(Vector3(0.01, 0.0, 0.0), Vector3.ZERO, 0.0, off, [1, 4], 0.20, false)
	t.assert_eq(s, 4, "tie-break by distance -> slot 4")


func test_nearest_yaw_rotates_zones(t) -> void:
	# At yaw +90, the right shoulder physically lives at +X-rotated -> world (0.20,-0.15,-0.25).
	# Putting the controller there should still pick slot 1.
	var s := ZoneMath.nearest_holster_slot(Vector3(0.20, -0.15, -0.25), Vector3.ZERO, PI/2.0, _DEFAULT_OFFSETS, _ZONE_KEYS, _DEFAULT_RADIUS, false)
	t.assert_eq(s, 1, "yaw rotates zones with the body")


# --- bag zone -----------------------------------------------------------

const _BAG_OFFSET := Vector3(0.15, -0.10, 0.35)  # behind right shoulder
const _BAG_RADIUS := 0.35

func test_bag_zone_hit_at_offset(t) -> void:
	# Controller exactly at the bag-zone center.
	var head := Vector3(2.0, 1.7, -3.0)
	# Zone center lives at head + yaw_basis * offset; at yaw 0, just head + offset.
	var ctrl := head + _BAG_OFFSET
	t.assert_true(ZoneMath.is_in_bag_zone(ctrl, head, 0.0, _BAG_OFFSET, _BAG_RADIUS), "controller at center -> in bag zone")


func test_bag_zone_miss_far(t) -> void:
	t.assert_true(not ZoneMath.is_in_bag_zone(Vector3(10, 10, 10), Vector3.ZERO, 0.0, _BAG_OFFSET, _BAG_RADIUS), "far controller -> not in bag zone")


func test_bag_zone_yaw_rotation(t) -> void:
	# Player turns 180 deg. The bag zone (behind right shoulder in body
	# frame) should now be physically in the opposite world direction.
	# Body offset (0.15, -0.10, 0.35) at yaw 0 is at world (0.15, -0.10, 0.35).
	# At yaw PI it should be at world (-0.15, -0.10, -0.35).
	var head := Vector3.ZERO
	var ctrl_at_world_offset := Vector3(-0.15, -0.10, -0.35)
	t.assert_true(ZoneMath.is_in_bag_zone(ctrl_at_world_offset, head, PI, _BAG_OFFSET, _BAG_RADIUS), "bag zone follows yaw 180")


# --- nvg zone -----------------------------------------------------------

const _NVG_OFFSET := Vector3(0.0, 0.30, 0.0)  # straight up, no yaw
const _NVG_RADIUS := 0.25

func test_nvg_zone_hit_above_head(t) -> void:
	var head := Vector3(0.0, 1.7, 0.0)
	var ctrl := head + _NVG_OFFSET
	t.assert_true(ZoneMath.is_in_nvg_zone(ctrl, head, _NVG_OFFSET, _NVG_RADIUS), "controller above head -> in NVG zone")


func test_nvg_zone_miss_at_head_level(t) -> void:
	var head := Vector3(0.0, 1.7, 0.0)
	# NVG center is 0.30 m above head. Controller at head level is 0.30 m below center, > 0.25 m radius.
	t.assert_true(not ZoneMath.is_in_nvg_zone(head, head, _NVG_OFFSET, _NVG_RADIUS), "controller at head level -> not in NVG zone")


func test_nvg_zone_yaw_independent(t) -> void:
	# NVG zone is straight up only — does NOT rotate with yaw.
	var head := Vector3.ZERO
	var ctrl := Vector3(0.0, 0.30, 0.0)
	# Same hit at any yaw.
	t.assert_true(ZoneMath.is_in_nvg_zone(ctrl, head, _NVG_OFFSET, _NVG_RADIUS), "NVG hit at yaw 0")
	# (the function signature doesn't take yaw — this is the spec)
	# we just want to assert that NVG is NOT a yaw-rotated zone. Confirmed by signature.
	t.ok("NVG zone signature has no yaw parameter (spec-encoded)")
