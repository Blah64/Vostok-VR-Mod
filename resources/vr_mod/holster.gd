extends RefCounted

# holster.gd
# Holster zone math, holographic preview meshes, draw / lower / sling / raise /
# holster state transitions.
#
# This module reaches the autoload only through explicit Callable ports passed
# at _init time. The state itself (holster_state, weapon_hand, weapon_slot,
# zone offsets, etc.) lives on the autoload because too many other call sites
# branch on it; the ports are thin getters/setters and a single
# `reset_weapon_session` callback that wipes the cross-subsystem cleanup fields
# on holster (those fields belong logically to weapon_sync but are flushed
# here as part of the same transition).
#
# Port contract (state — getters/setters):
#   get_holster_state          : Callable() -> int
#   set_holster_state          : Callable(value) -> void
#   get_weapon_hand            : Callable() -> String
#   set_weapon_hand            : Callable(value) -> void
#   get_weapon_slot            : Callable() -> int
#   set_weapon_slot            : Callable(value) -> void
#   set_transition_state       : Callable(slot, hand) -> void
#   get_holster_state_unarmed  : Callable() -> int
#   get_holster_state_drawn    : Callable() -> int
#   get_holster_state_lowered  : Callable() -> int
#   get_holster_state_sling    : Callable() -> int
#   get_holster_zones          : Callable() -> Dictionary  (HOLSTER_ZONES const)
#   get_holster_offsets        : Callable() -> Dictionary  (per-slot Vector3)
#   get_holster_zones_mirrored : Callable() -> bool
#   get_holster_zone_radius    : Callable() -> float
#   get_zone_cache             : Callable() -> Dictionary
#   set_zone_cache_frame       : Callable(frame) -> void
#   get_zone_cache_frame       : Callable() -> int
#   get_holo_nodes             : Callable() -> Dictionary
#   get_holos_enabled          : Callable() -> bool
#   get_holster_cooldown       : Callable() -> float
#   set_holster_cooldown       : Callable(value) -> void
#   get_pending_holster_key    : Callable() -> int
#   set_pending_holster_key    : Callable(value) -> void
#   set_weapon_raise_timer     : Callable(value) -> void
#   set_scroll_cooldown        : Callable(value) -> void
#   get_hand_in_zone           : Callable() -> Dictionary
#   get_camera                 : Callable() -> XRCamera3D
#   get_controller             : Callable(hand) -> XRController3D
#   get_owner_node             : Callable() -> Node       (parent for holo Node3Ds)
#   get_vrframe                : Callable() -> Dictionary (refreshes if stale)
#
# Port contract (side effects):
#   inject_key                 : Callable(keycode, pressed) -> void
#   inject_action              : Callable(action, pressed, strength) -> void
#   inject_mouse               : Callable(button, pressed) -> void
#   reset_for_draw             : Callable() -> void   (clears recoil/walk-sway/load fields)
#   reset_for_lower            : Callable() -> void   (clears adjust modes + support grip)
#   reset_for_holster          : Callable() -> void   (clears full weapon session — names, subtypes, pump, sway, adjust)
#   exit_rail_mode             : Callable() -> void
#   cleanup_scope              : Callable() -> void
#   clear_grenade_state        : Callable() -> void
#   patch_resume_state         : Callable(slot, hand) -> void
#   reset_scope_reticle_cache  : Callable() -> void
#   ensure_grab_in_bag_zone_get: Callable() -> bool   (read grab.in_bag_zone)
#   ensure_grab_in_bag_zone_set: Callable(value) -> void
#   is_in_bag_zone             : Callable(world_pos) -> bool
#   is_in_nvg_zone             : Callable(world_pos) -> bool
#   get_grabbed_object         : Callable() -> Node3D
#   get_grab_hand              : Callable() -> String
#   nvg_get_hand_in_zone       : Callable() -> Dictionary  (nvg subsystem latch dict)
#
#   get_holster_key_delay      : Callable() -> float
#   get_holster_key_release    : Callable() -> float
#
#   log                        : Callable(msg) -> void


# Ports — state
var _tree: SceneTree
var _get_holster_state: Callable
var _set_holster_state: Callable
var _get_weapon_hand: Callable
var _set_weapon_hand: Callable
var _get_weapon_slot: Callable
var _set_weapon_slot: Callable
var _set_transition_state: Callable
var _get_state_unarmed: Callable
var _get_state_drawn: Callable
var _get_state_lowered: Callable
var _get_state_sling: Callable
var _get_holster_zones: Callable
var _get_holster_offsets: Callable
var _get_zones_mirrored: Callable
var _get_zone_radius: Callable
var _get_zone_cache: Callable
var _set_zone_cache_frame: Callable
var _get_zone_cache_frame: Callable
var _get_holo_nodes: Callable
var _get_holos_enabled: Callable
var _get_holster_cooldown: Callable
var _set_holster_cooldown: Callable
var _get_pending_holster_key: Callable
var _set_pending_holster_key: Callable
var _set_weapon_raise_timer: Callable
var _set_scroll_cooldown: Callable
var _get_hand_in_zone: Callable
var _get_camera: Callable
var _get_controller: Callable
var _get_owner_node: Callable
var _get_vrframe: Callable
var _get_key_delay: Callable
var _get_key_release: Callable

# Ports — side effects
var _inject_key: Callable
var _inject_action: Callable
var _inject_mouse: Callable
var _reset_for_draw: Callable
var _reset_for_lower: Callable
var _reset_for_holster: Callable
var _exit_rail_mode_fn: Callable
var _cleanup_scope_fn: Callable
var _clear_grenade_state_fn: Callable
var _patch_resume_state_fn: Callable
var _reset_scope_reticle_cache: Callable
var _grab_in_bag_zone_get: Callable
var _grab_in_bag_zone_set: Callable
var _is_in_bag_zone_fn: Callable
var _is_in_nvg_zone_fn: Callable
var _get_grabbed_object: Callable
var _get_grab_hand: Callable
var _nvg_get_hand_in_zone: Callable

var _log_fn: Callable


func _init(tree: SceneTree, ports: Dictionary) -> void:
	_tree = tree
	_get_holster_state = ports["get_holster_state"]
	_set_holster_state = ports["set_holster_state"]
	_get_weapon_hand = ports["get_weapon_hand"]
	_set_weapon_hand = ports["set_weapon_hand"]
	_get_weapon_slot = ports["get_weapon_slot"]
	_set_weapon_slot = ports["set_weapon_slot"]
	_set_transition_state = ports["set_transition_state"]
	_get_state_unarmed = ports["get_holster_state_unarmed"]
	_get_state_drawn = ports["get_holster_state_drawn"]
	_get_state_lowered = ports["get_holster_state_lowered"]
	_get_state_sling = ports["get_holster_state_sling"]
	_get_holster_zones = ports["get_holster_zones"]
	_get_holster_offsets = ports["get_holster_offsets"]
	_get_zones_mirrored = ports["get_holster_zones_mirrored"]
	_get_zone_radius = ports["get_holster_zone_radius"]
	_get_zone_cache = ports["get_zone_cache"]
	_set_zone_cache_frame = ports["set_zone_cache_frame"]
	_get_zone_cache_frame = ports["get_zone_cache_frame"]
	_get_holo_nodes = ports["get_holo_nodes"]
	_get_holos_enabled = ports["get_holos_enabled"]
	_get_holster_cooldown = ports["get_holster_cooldown"]
	_set_holster_cooldown = ports["set_holster_cooldown"]
	_get_pending_holster_key = ports["get_pending_holster_key"]
	_set_pending_holster_key = ports["set_pending_holster_key"]
	_set_weapon_raise_timer = ports["set_weapon_raise_timer"]
	_set_scroll_cooldown = ports["set_scroll_cooldown"]
	_get_hand_in_zone = ports["get_hand_in_zone"]
	_get_camera = ports["get_camera"]
	_get_controller = ports["get_controller"]
	_get_owner_node = ports["get_owner_node"]
	_get_vrframe = ports["get_vrframe"]
	_get_key_delay = ports["get_holster_key_delay"]
	_get_key_release = ports["get_holster_key_release"]

	_inject_key = ports["inject_key"]
	_inject_action = ports["inject_action"]
	_inject_mouse = ports["inject_mouse"]
	_reset_for_draw = ports["reset_for_draw"]
	_reset_for_lower = ports["reset_for_lower"]
	_reset_for_holster = ports["reset_for_holster"]
	_exit_rail_mode_fn = ports["exit_rail_mode"]
	_cleanup_scope_fn = ports["cleanup_scope"]
	_clear_grenade_state_fn = ports["clear_grenade_state"]
	_patch_resume_state_fn = ports["patch_resume_state"]
	_reset_scope_reticle_cache = ports["reset_scope_reticle_cache"]
	_grab_in_bag_zone_get = ports["grab_in_bag_zone_get"]
	_grab_in_bag_zone_set = ports["grab_in_bag_zone_set"]
	_is_in_bag_zone_fn = ports["is_in_bag_zone"]
	_is_in_nvg_zone_fn = ports["is_in_nvg_zone"]
	_get_grabbed_object = ports["get_grabbed_object"]
	_get_grab_hand = ports["get_grab_hand"]
	_nvg_get_hand_in_zone = ports["nvg_get_hand_in_zone"]

	_log_fn = ports.get("log", Callable())


func _log(msg: String) -> void:
	if _log_fn.is_valid():
		_log_fn.call(msg)


func process(_frame: Dictionary, delta: float) -> void:
	# Per-frame holster work: zone-entry haptic feedback + holographic preview
	# meshes that mark each holster slot relative to the player's torso. Also
	# ticks down the post-holster re-draw cooldown.
	var cd: float = _get_holster_cooldown.call()
	if cd > 0.0:
		_set_holster_cooldown.call(cd - delta)
	update_holster_zone_haptics()
	update_holster_holos()


func refresh_holster_zone_cache() -> void:
	var frame := Engine.get_process_frames()
	if frame == _get_zone_cache_frame.call():
		return
	_set_zone_cache_frame.call(frame)
	var cache: Dictionary = _get_zone_cache.call()
	cache.clear()
	var snap: Dictionary = _get_vrframe.call()
	if not snap["cam_valid"]:
		return
	var head_pos: Vector3 = snap["cam_pos"]
	var yaw_basis: Basis = snap["yaw_basis"]
	var zones: Dictionary = _get_holster_zones.call()
	var offsets: Dictionary = _get_holster_offsets.call()
	var mirrored: bool = _get_zones_mirrored.call()
	for slot in zones:
		var o: Vector3 = offsets[slot]
		var eff := Vector3(-o.x, o.y, o.z) if mirrored else o
		cache[slot] = head_pos + yaw_basis * eff


func get_nearby_holster_zone(controller_pos: Vector3) -> int:
	refresh_holster_zone_cache()
	var cache: Dictionary = _get_zone_cache.call()
	if cache.is_empty():
		return 0
	var closest_zone := 0
	var closest_dist: float = _get_zone_radius.call()
	var zones: Dictionary = _get_holster_zones.call()
	for slot in zones:
		var dist: float = controller_pos.distance_to(cache[slot])
		if dist < closest_dist:
			closest_dist = dist
			closest_zone = slot
	return closest_zone


func update_holster_zone_haptics() -> void:
	# Check each controller against holster zones and pulse haptic on entry
	var hand_in_zone: Dictionary = _get_hand_in_zone.call()
	var zones: Dictionary = _get_holster_zones.call()
	for hand in ["left", "right"]:
		var ctrl = _get_controller.call(hand)
		if not ctrl or not ctrl.get_is_active():
			continue
		var zone = get_nearby_holster_zone(ctrl.global_position)
		var prev_zone: int = hand_in_zone[hand]
		if zone != prev_zone:
			if zone > 0 and _get_holster_cooldown.call() <= 0.0:
				# Entered a new zone - haptic buzz (suppressed during holster cooldown)
				ctrl.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.15, 0.0)
				_log("[VR Mod] " + hand + " hand entered zone: " + str(zones[zone]["name"]))
			hand_in_zone[hand] = zone

	# Bag zone haptic: buzz when the grabbing hand enters the bag zone while
	# holding a loose item.
	var grabbed = _get_grabbed_object.call()
	var grab_hand: String = _get_grab_hand.call()
	if grabbed and is_instance_valid(grabbed) and grab_hand != "":
		var grab_ctrl = _get_controller.call(grab_hand)
		if grab_ctrl and grab_ctrl.get_is_active():
			var in_zone = _is_in_bag_zone_fn.call(grab_ctrl.global_position)
			if in_zone and not _grab_in_bag_zone_get.call():
				grab_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.2, 0.0)
				_log("[VR Mod] Grab hand entered bag zone")
			_grab_in_bag_zone_set.call(in_zone)
	else:
		_grab_in_bag_zone_set.call(false)

	# NVG zone haptic: buzz when either hand enters the NVG zone above head.
	var nvg_latch: Dictionary = _nvg_get_hand_in_zone.call()
	for hand in ["left", "right"]:
		var ctrl = _get_controller.call(hand)
		if not ctrl or not ctrl.get_is_active():
			nvg_latch[hand] = false
			continue
		var in_zone = _is_in_nvg_zone_fn.call(ctrl.global_position)
		if in_zone and not nvg_latch[hand]:
			ctrl.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.15, 0.0)
			_log("[VR Mod] " + hand + " hand entered NVG zone")
		nvg_latch[hand] = in_zone


func mk_holo_mat() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.7, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.5, 1.0)
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func add_holo_box(parent: Node3D, size: Vector3, pos: Vector3, euler: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.set_surface_override_material(0, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = pos
	if euler != Vector3.ZERO:
		mi.rotation = euler


func add_holo_cyl(parent: Node3D, radius: float, height: float, pos: Vector3, euler: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.set_surface_override_material(0, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = pos
	if euler != Vector3.ZERO:
		mi.rotation = euler


func add_holo_sph(parent: Node3D, radius: float, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.set_surface_override_material(0, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = pos


func create_holster_holos() -> void:
	destroy_holster_holos()
	var mat := mk_holo_mat()
	var owner_node: Node = _get_owner_node.call()
	var holo_nodes: Dictionary = _get_holo_nodes.call()

	# Slot 2: pistol - slide along Z (barrel forward), grip hanging below
	var pistol := Node3D.new()
	pistol.name = "HoloPistol"
	owner_node.add_child(pistol)
	add_holo_box(pistol, Vector3(0.026, 0.038, 0.100), Vector3(0.0, 0.008, 0.0), Vector3.ZERO, mat)
	add_holo_box(pistol, Vector3(0.022, 0.058, 0.030), Vector3(0.0, -0.037, 0.018), Vector3(deg_to_rad(10.0), 0.0, 0.0), mat)
	add_holo_box(pistol, Vector3(0.022, 0.014, 0.034), Vector3(0.0, -0.010, 0.006), Vector3.ZERO, mat)
	add_holo_cyl(pistol, 0.007, 0.028, Vector3(0.0, 0.003, -0.064), Vector3(PI / 2.0, 0.0, 0.0), mat)
	holo_nodes[2] = pistol

	# Slot 3: knife - blade pointing up, guard at centre, handle cylinder below
	var knife := Node3D.new()
	knife.name = "HoloKnife"
	owner_node.add_child(knife)
	add_holo_box(knife, Vector3(0.016, 0.115, 0.004), Vector3(0.0, 0.072, 0.0), Vector3.ZERO, mat)
	add_holo_box(knife, Vector3(0.040, 0.009, 0.006), Vector3(0.0, 0.010, 0.0), Vector3.ZERO, mat)
	add_holo_cyl(knife, 0.009, 0.060, Vector3(0.0, -0.035, 0.0), Vector3.ZERO, mat)
	holo_nodes[3] = knife

	# Slot 4: grenade - sphere body, safety lever bar, fuse cylinder on top, pin nub
	var grenade := Node3D.new()
	grenade.name = "HoloGrenade"
	owner_node.add_child(grenade)
	add_holo_sph(grenade, 0.030, Vector3(0.0, 0.0, 0.0), mat)
	add_holo_box(grenade, Vector3(0.058, 0.009, 0.014), Vector3(0.0, 0.012, 0.0), Vector3.ZERO, mat)
	add_holo_cyl(grenade, 0.007, 0.018, Vector3(0.0, 0.038, 0.0), Vector3.ZERO, mat)
	add_holo_box(grenade, Vector3(0.006, 0.006, 0.020), Vector3(0.018, 0.030, 0.0), Vector3.ZERO, mat)
	holo_nodes[4] = grenade


func destroy_holster_holos() -> void:
	var holo_nodes: Dictionary = _get_holo_nodes.call()
	for slot in holo_nodes.keys():
		var node = holo_nodes[slot]
		if node and is_instance_valid(node):
			node.queue_free()
	holo_nodes.clear()


func update_holster_holos() -> void:
	var holo_nodes: Dictionary = _get_holo_nodes.call()
	if holo_nodes.is_empty():
		return
	var cam = _get_camera.call()
	if not cam or not is_instance_valid(cam):
		return
	var head_pos = cam.global_position
	var yaw_basis := Basis(Vector3.UP, cam.global_rotation.y)
	var enabled: bool = _get_holos_enabled.call()
	var current_slot: int = _get_weapon_slot.call()
	var offsets: Dictionary = _get_holster_offsets.call()
	var mirrored: bool = _get_zones_mirrored.call()
	for slot in holo_nodes.keys():
		var node: Node3D = holo_nodes[slot]
		if not is_instance_valid(node):
			continue
		node.visible = enabled and (current_slot != slot)
		if not node.visible:
			continue
		var o: Vector3 = offsets[slot]
		var eff := Vector3(-o.x, o.y, o.z) if mirrored else o
		node.global_position = head_pos + yaw_basis * eff
		node.global_basis = yaw_basis


func draw_weapon(hand: String, slot: int) -> void:
	var zones: Dictionary = _get_holster_zones.call()
	_log("[VR Mod] DRAW weapon slot " + str(slot) + " (" + str(zones[slot]["name"]) + ") with " + hand + " hand")
	_set_holster_state.call(_get_state_drawn.call())
	_set_weapon_hand.call(hand)
	_set_weapon_slot.call(slot)
	# Player manually drew - pre-transition slot is no longer relevant.
	_set_transition_state.call(0, "")

	# Cancel any pending holster KEY injection - prevents double-toggle when
	# holster and draw happen within 0.15 s of each other.
	_set_pending_holster_key.call(-1)

	# Inject the key to equip this weapon slot
	var key: int = zones[slot]["key"]
	_inject_key.call(key, true)
	_tree.create_timer(0.1).timeout.connect(Callable(self, "_release_draw_key").bind(key))

	# Start weapon load detection + auto-raise sequence (clears scope reticle cache,
	# weapon-session transient state, then schedules auto-raise).
	_reset_for_draw.call()
	_set_weapon_raise_timer.call(3.0)
	_set_scroll_cooldown.call(1.0)
	_reset_scope_reticle_cache.call()  # Re-scan for reticle on new weapon
	_cleanup_scope_fn.call()  # Re-detect scope on new weapon
	_patch_resume_state_fn.call(_get_weapon_slot.call(), _get_weapon_hand.call())


func _release_draw_key(key: int) -> void:
	_inject_key.call(key, false)


func lower_weapon() -> void:
	_log("[VR Mod] LOWER weapon (slot " + str(_get_weapon_slot.call()) + ")")
	_reset_for_lower.call()
	_exit_rail_mode_fn.call()
	_clear_grenade_state_fn.call()
	_set_holster_state.call(_get_state_lowered.call())
	# Set weapon_low to lower the weapon visually
	_inject_action.call("weapon_low", true, 1.0)
	_tree.create_timer(0.1).timeout.connect(Callable(self, "_release_weapon_low"))
	# Release fire/aim in case they were held
	Input.action_release("fire")
	Input.action_release("left_mouse")
	_inject_action.call("fire", false, 1.0)
	_inject_action.call("left_mouse", false, 1.0)
	_inject_mouse.call(MOUSE_BUTTON_LEFT, false)
	_inject_action.call("aim", false, 1.0)
	_inject_mouse.call(MOUSE_BUTTON_RIGHT, false)


func _release_weapon_low() -> void:
	_inject_action.call("weapon_low", false, 1.0)


func enter_sling() -> void:
	_log("[VR Mod] SLING weapon (slot " + str(_get_weapon_slot.call()) + ")")
	_reset_for_lower.call()
	_exit_rail_mode_fn.call()
	_clear_grenade_state_fn.call()
	_set_holster_state.call(_get_state_sling.call())
	# weapon_low signals the game to recharge arm stamina and show the aiming laser
	_inject_action.call("weapon_low", true, 1.0)
	_tree.create_timer(0.1).timeout.connect(Callable(self, "_release_weapon_low"))
	Input.action_release("fire")
	Input.action_release("left_mouse")
	_inject_action.call("fire", false, 1.0)
	_inject_action.call("left_mouse", false, 1.0)
	_inject_mouse.call(MOUSE_BUTTON_LEFT, false)
	_inject_action.call("aim", false, 1.0)
	_inject_mouse.call(MOUSE_BUTTON_RIGHT, false)


func raise_weapon() -> void:
	_log("[VR Mod] RAISE weapon (slot " + str(_get_weapon_slot.call()) + ")")
	_set_holster_state.call(_get_state_drawn.call())
	# Re-raise the weapon
	_inject_action.call("weapon_high", true, 1.0)
	_tree.create_timer(0.1).timeout.connect(Callable(self, "_release_weapon_high"))


func _release_weapon_high() -> void:
	_inject_action.call("weapon_high", false, 1.0)


func holster_weapon() -> void:
	_log("[VR Mod] HOLSTER weapon (slot " + str(_get_weapon_slot.call()) + ")")
	_exit_rail_mode_fn.call()
	_cleanup_scope_fn.call()
	# Release aim
	_inject_action.call("aim", false, 1.0)
	_inject_mouse.call(MOUSE_BUTTON_RIGHT, false)
	_inject_action.call("weapon_high", false, 1.0)

	# Unequip: inject the same key to toggle off, but delay by HOLSTER_KEY_DELAY_SEC so that a
	# draw_weapon() call in the same frame (or within that window) can cancel it
	# via _pending_holster_key, avoiding a double-toggle that leaves the weapon stuck.
	var current_slot: int = _get_weapon_slot.call()
	var zones: Dictionary = _get_holster_zones.call()
	if current_slot > 0 and zones.has(current_slot):
		var key: int = zones[current_slot]["key"]
		_set_pending_holster_key.call(key)
		_tree.create_timer(_get_key_delay.call()).timeout.connect(Callable(self, "_fire_pending_holster_key").bind(key))

	_set_holster_state.call(_get_state_unarmed.call())
	_set_weapon_hand.call("")
	_set_weapon_slot.call(0)
	_clear_grenade_state_fn.call()
	# Wipe weapon_sync cleanup fields (recoil, walk-sway, current_weapon_name, etc.).
	_reset_for_holster.call()
	_set_holster_cooldown.call(0.8)  # Block re-draw until animation completes
	_patch_resume_state_fn.call(0, "")


func _fire_pending_holster_key(key: int) -> void:
	if _get_pending_holster_key.call() == key:
		_set_pending_holster_key.call(-1)
		_inject_key.call(key, true)
		_tree.create_timer(_get_key_release.call()).timeout.connect(Callable(self, "_release_pending_holster_key").bind(key))


func _release_pending_holster_key(key: int) -> void:
	_inject_key.call(key, false)
