extends RefCounted

# grab.gd
# Loose-item pickup/throw and the bag/NVG zone math used by both grab logic
# and zone haptics.
#
# Subsystem-owned state: per-frame throw sampling, the bag-zone latch (used
# only by holster.update_holster_zone_haptics), and the controller->object
# grab offset all live on this module. The grabbed object reference itself
# (_grabbed_object) and the active grab hand (_grab_hand) stay on the
# autoload because input handling, weapon sync, level-transition cleanup,
# and the holster state machine all branch on those values.

var autoload: Node
var grab_offset: Vector3 = Vector3.ZERO   # ctrl-to-object position offset
var throw_samples: Array = []             # ring buffer of [pos, t] for throw velocity
var in_bag_zone: bool = false             # latch for bag-zone haptic edge detect

func _init(p_autoload: Node) -> void:
	autoload = p_autoload


func process(_frame: Dictionary, _delta: float) -> void:
	# Per-frame grabbed-item position override (no freeze; we keep velocity
	# zeroed and reposition each frame so process_priority=1000 wins against
	# the game's physics step).
	update_grabbed()


func is_in_bag_zone(world_pos: Vector3) -> bool:
	if not autoload.xr_camera or not is_instance_valid(autoload.xr_camera):
		return false
	var yaw = autoload.xr_camera.global_rotation.y
	var yaw_basis := Basis(Vector3.UP, yaw)
	var local = yaw_basis.inverse() * (world_pos - autoload.xr_camera.global_position)
	return local.distance_to(autoload._bag_zone_offset) < autoload._bag_zone_radius


func is_in_nvg_zone(world_pos: Vector3) -> bool:
	if not autoload.xr_camera or not is_instance_valid(autoload.xr_camera):
		return false
	var head_pos = autoload.xr_camera.global_position
	return world_pos.distance_to(head_pos + autoload._nvg_zone_offset) < autoload._nvg_zone_radius


func hand_laser_sees_grabbable(hand: String) -> bool:
	var ray = autoload._grab_ray_right if hand == "right" else autoload._grab_ray_left
	if not ray or not ray.is_colliding():
		return false
	var c = ray.get_collider()
	return c is RigidBody3D and (c.collision_layer & 4) != 0


func try_grab(hand: String) -> void:
	if autoload._grabbed_object:
		return  # Already holding something

	var grab_ray = autoload._grab_ray_right if hand == "right" else autoload._grab_ray_left
	if not grab_ray or not grab_ray.is_colliding():
		return

	var collider = grab_ray.get_collider()
	if not collider:
		return

	# Only grab loose items: RigidBody3D with collision layer 4
	if not (collider is RigidBody3D and (collider.collision_layer & 4) != 0):
		return

	var controller = autoload._get_controller(hand)
	if not controller:
		return

	autoload._grabbed_object = collider
	autoload._grab_hand = hand
	throw_samples.clear()
	# No freeze - override position each frame at process_priority=1000
	autoload._log("[VR Mod] Grabbed: ", collider.name, " with ", hand, " hand")


func drop_grabbed() -> void:
	if not autoload._grabbed_object:
		return

	# If the grabbing hand is behind the shoulder, add to inventory instead of dropping
	var ctrl = autoload._get_controller(autoload._grab_hand) if autoload._grab_hand != "" else null
	if ctrl and is_in_bag_zone(ctrl.global_position):
		pickup_to_inventory()
		return

	# Compute throw velocity from the last 3 samples only (captures peak, not deceleration)
	var throw_vel := Vector3.ZERO
	if throw_samples.size() >= 2:
		var start_idx = max(0, throw_samples.size() - 3)
		var oldest = throw_samples[start_idx]
		var newest = throw_samples[-1]
		var dt: float = newest[1] - oldest[1]
		if dt > 0.001:
			throw_vel = (newest[0] - oldest[0]) / dt * 1.5

	if autoload._grabbed_object is RigidBody3D:
		var rb := autoload._grabbed_object as RigidBody3D
		rb.sleeping = false
		rb.linear_damp = 0.0
		rb.linear_velocity = throw_vel
		rb.angular_velocity = Vector3.ZERO

	autoload._log("[VR Mod] Dropped: ", autoload._grabbed_object.name, " vel=", throw_vel)
	autoload._grabbed_object = null
	autoload._grab_hand = ""
	grab_offset = Vector3.ZERO
	throw_samples.clear()


func pickup_to_inventory() -> void:
	if not autoload._grabbed_object or not is_instance_valid(autoload._grabbed_object):
		return

	autoload._log("[VR Mod] INVENTORY PICKUP: ", autoload._grabbed_object.name)

	# Haptic confirmation
	var ctrl = autoload._get_controller(autoload._grab_hand) if autoload._grab_hand != "" else null
	if ctrl:
		ctrl.trigger_haptic_pulse("haptic", 0.0, 1.0, 0.25, 0.0)

	var item = autoload._grabbed_object
	autoload._grabbed_object = null
	autoload._grab_hand = ""
	grab_offset = Vector3.ZERO
	throw_samples.clear()
	in_bag_zone = false

	# Call the game's Interact method directly (Pickup.gd script)
	if item.has_method("Interact"):
		item.call("Interact")
	else:
		# Fallback: drop at feet
		if autoload.xr_camera and is_instance_valid(autoload.xr_camera):
			var fwd = -autoload.xr_camera.global_basis.z
			fwd.y = 0.0
			if fwd.length_squared() > 0.001:
				fwd = fwd.normalized()
			item.global_position = autoload.xr_camera.global_position + Vector3(0, -1.5, 0) + fwd * 0.3
		if item is RigidBody3D:
			var rb := item as RigidBody3D
			rb.sleeping = false
			rb.linear_damp = 0.0
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO


func update_grabbed() -> void:
	if not autoload._grabbed_object or not is_instance_valid(autoload._grabbed_object):
		autoload._grabbed_object = null
		autoload._grab_hand = ""
		return

	var controller = autoload._get_controller(autoload._grab_hand) if autoload._grab_hand != "" else autoload._get_controller(autoload._config_dominant_hand)
	if not controller or not controller.get_is_active():
		return

	var hand_model_name = "RightHandModel" if autoload._grab_hand == "right" else "LeftHandModel"
	var hand_model = controller.get_node_or_null(hand_model_name)
	var hand_pos: Vector3
	if hand_model:
		hand_pos = hand_model.global_position
		autoload._grabbed_object.global_position = hand_pos
		autoload._grabbed_object.global_basis = hand_model.global_basis
	else:
		hand_pos = controller.global_position
		autoload._grabbed_object.global_position = hand_pos

	# Zero physics velocity each frame so gravity doesn't accumulate while held
	if autoload._grabbed_object is RigidBody3D:
		var rb := autoload._grabbed_object as RigidBody3D
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO

	# Track hand position over time for throw velocity
	var now := Time.get_ticks_msec() / 1000.0
	throw_samples.append([hand_pos, now])
	if throw_samples.size() > 8:
		throw_samples.pop_front()
