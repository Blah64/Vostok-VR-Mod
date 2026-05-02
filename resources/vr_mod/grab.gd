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
# and the holster state machine all branch on those values; this module
# reads/writes them via explicit Callable ports rather than back-reference.
#
# Port contract:
#   get_camera                : Callable() -> XRCamera3D            (current XRCamera3D; may be null)
#   get_controller            : Callable(hand) -> XRController3D    (left/right XRController3D; may be null)
#   get_grab_ray              : Callable(hand) -> RayCast3D         (per-hand grab raycast; may be null)
#   get_bag_zone_offset       : Callable() -> Vector3               (yaw-relative bag-zone position)
#   get_bag_zone_radius       : Callable() -> float                 (bag-zone radius in metres)
#   get_nvg_zone_offset       : Callable() -> Vector3               (head-world-space NVG zone offset)
#   get_nvg_zone_radius       : Callable() -> float                 (NVG zone radius in metres)
#   get_dominant_hand         : Callable() -> String                ("left" or "right")
#   get_grabbed_object        : Callable() -> Node3D                (currently-grabbed item or null)
#   set_grabbed_object        : Callable(obj) -> void               (writes autoload _grabbed_object)
#   get_grab_hand             : Callable() -> String                ("left"/"right" or "")
#   set_grab_hand             : Callable(hand) -> void              (writes autoload _grab_hand)
#   log                       : Callable(msg) -> void               (optional; ignored if invalid)


var grab_offset: Vector3 = Vector3.ZERO   # ctrl-to-object position offset
var throw_samples: Array = []             # ring buffer of [pos, t] for throw velocity
var in_bag_zone: bool = false             # latch for bag-zone haptic edge detect


# Ports
var _get_camera: Callable
var _get_controller: Callable
var _get_grab_ray: Callable
var _get_bag_zone_offset: Callable
var _get_bag_zone_radius: Callable
var _get_nvg_zone_offset: Callable
var _get_nvg_zone_radius: Callable
var _get_dominant_hand: Callable
var _get_grabbed_object: Callable
var _set_grabbed_object: Callable
var _get_grab_hand: Callable
var _set_grab_hand: Callable
var _log_fn: Callable


func _init(_tree: SceneTree, ports: Dictionary) -> void:
	_get_camera = ports["get_camera"]
	_get_controller = ports["get_controller"]
	_get_grab_ray = ports["get_grab_ray"]
	_get_bag_zone_offset = ports["get_bag_zone_offset"]
	_get_bag_zone_radius = ports["get_bag_zone_radius"]
	_get_nvg_zone_offset = ports["get_nvg_zone_offset"]
	_get_nvg_zone_radius = ports["get_nvg_zone_radius"]
	_get_dominant_hand = ports["get_dominant_hand"]
	_get_grabbed_object = ports["get_grabbed_object"]
	_set_grabbed_object = ports["set_grabbed_object"]
	_get_grab_hand = ports["get_grab_hand"]
	_set_grab_hand = ports["set_grab_hand"]
	_log_fn = ports.get("log", Callable())


func _log(msg: String) -> void:
	if _log_fn.is_valid():
		_log_fn.call(msg)


func process(_frame: Dictionary, _delta: float) -> void:
	# Per-frame grabbed-item position override (no freeze; we keep velocity
	# zeroed and reposition each frame so process_priority=1000 wins against
	# the game's physics step).
	update_grabbed()


func is_in_bag_zone(world_pos: Vector3) -> bool:
	var cam = _get_camera.call()
	if not cam or not is_instance_valid(cam):
		return false
	var yaw = cam.global_rotation.y
	var yaw_basis := Basis(Vector3.UP, yaw)
	var local = yaw_basis.inverse() * (world_pos - cam.global_position)
	return local.distance_to(_get_bag_zone_offset.call()) < _get_bag_zone_radius.call()


func is_in_nvg_zone(world_pos: Vector3) -> bool:
	var cam = _get_camera.call()
	if not cam or not is_instance_valid(cam):
		return false
	var head_pos = cam.global_position
	return world_pos.distance_to(head_pos + _get_nvg_zone_offset.call()) < _get_nvg_zone_radius.call()


func hand_laser_sees_grabbable(hand: String) -> bool:
	var ray = _get_grab_ray.call(hand)
	if not ray or not ray.is_colliding():
		return false
	var c = ray.get_collider()
	return c is RigidBody3D and (c.collision_layer & 4) != 0


func try_grab(hand: String) -> void:
	if _get_grabbed_object.call():
		return  # Already holding something

	var grab_ray = _get_grab_ray.call(hand)
	if not grab_ray or not grab_ray.is_colliding():
		return

	var collider = grab_ray.get_collider()
	if not collider:
		return

	# Only grab loose items: RigidBody3D with collision layer 4
	if not (collider is RigidBody3D and (collider.collision_layer & 4) != 0):
		return

	var controller = _get_controller.call(hand)
	if not controller:
		return

	_set_grabbed_object.call(collider)
	_set_grab_hand.call(hand)
	throw_samples.clear()
	# No freeze - override position each frame at process_priority=1000
	_log("[VR Mod] Grabbed: " + str(collider.name) + " with " + hand + " hand")


func drop_grabbed() -> void:
	var grabbed = _get_grabbed_object.call()
	if not grabbed:
		return

	# If the grabbing hand is behind the shoulder, add to inventory instead of dropping
	var grab_hand = _get_grab_hand.call()
	var ctrl = _get_controller.call(grab_hand) if grab_hand != "" else null
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

	if grabbed is RigidBody3D:
		var rb := grabbed as RigidBody3D
		rb.sleeping = false
		rb.linear_damp = 0.0
		rb.linear_velocity = throw_vel
		rb.angular_velocity = Vector3.ZERO

	_log("[VR Mod] Dropped: " + str(grabbed.name) + " vel=" + str(throw_vel))
	_set_grabbed_object.call(null)
	_set_grab_hand.call("")
	grab_offset = Vector3.ZERO
	throw_samples.clear()


func pickup_to_inventory() -> void:
	var grabbed = _get_grabbed_object.call()
	if not grabbed or not is_instance_valid(grabbed):
		return

	_log("[VR Mod] INVENTORY PICKUP: " + str(grabbed.name))

	# Haptic confirmation
	var grab_hand = _get_grab_hand.call()
	var ctrl = _get_controller.call(grab_hand) if grab_hand != "" else null
	if ctrl:
		ctrl.trigger_haptic_pulse("haptic", 0.0, 1.0, 0.25, 0.0)

	var item = grabbed
	_set_grabbed_object.call(null)
	_set_grab_hand.call("")
	grab_offset = Vector3.ZERO
	throw_samples.clear()
	in_bag_zone = false

	# Call the game's Interact method directly (Pickup.gd script)
	if item.has_method("Interact"):
		item.call("Interact")
	else:
		# Fallback: drop at feet
		var cam = _get_camera.call()
		if cam and is_instance_valid(cam):
			var fwd = -cam.global_basis.z
			fwd.y = 0.0
			if fwd.length_squared() > 0.001:
				fwd = fwd.normalized()
			item.global_position = cam.global_position + Vector3(0, -1.5, 0) + fwd * 0.3
		if item is RigidBody3D:
			var rb := item as RigidBody3D
			rb.sleeping = false
			rb.linear_damp = 0.0
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO


func update_grabbed() -> void:
	var grabbed = _get_grabbed_object.call()
	if not grabbed or not is_instance_valid(grabbed):
		_set_grabbed_object.call(null)
		_set_grab_hand.call("")
		return

	var grab_hand = _get_grab_hand.call()
	var controller = _get_controller.call(grab_hand) if grab_hand != "" else _get_controller.call(_get_dominant_hand.call())
	if not controller or not controller.get_is_active():
		return

	var hand_model_name = "RightHandModel" if grab_hand == "right" else "LeftHandModel"
	var hand_model = controller.get_node_or_null(hand_model_name)
	var hand_pos: Vector3
	if hand_model:
		hand_pos = hand_model.global_position
		grabbed.global_position = hand_pos
		grabbed.global_basis = hand_model.global_basis
	else:
		hand_pos = controller.global_position
		grabbed.global_position = hand_pos

	# Zero physics velocity each frame so gravity doesn't accumulate while held
	if grabbed is RigidBody3D:
		var rb := grabbed as RigidBody3D
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO

	# Track hand position over time for throw velocity
	var now := Time.get_ticks_msec() / 1000.0
	throw_samples.append([hand_pos, now])
	if throw_samples.size() > 8:
		throw_samples.pop_front()
