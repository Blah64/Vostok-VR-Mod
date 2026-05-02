extends RefCounted

# holster.gd
# Holster zone math, holographic preview meshes, draw / lower / sling / raise /
# holster state transitions. State (HOLSTER_ZONES, _holster_state, _weapon_*,
# offsets, etc.) stays on the autoload; this module owns the methods only.

var autoload: Node

func _init(p_autoload: Node) -> void:
	autoload = p_autoload


func process(_frame: Dictionary, delta: float) -> void:
	# Per-frame holster work: zone-entry haptic feedback + holographic preview
	# meshes that mark each holster slot relative to the player's torso. Also
	# ticks down the post-holster re-draw cooldown (lives on the autoload as
	# _holster_cooldown so input and the F8 panel can read it).
	if autoload._holster_cooldown > 0.0:
		autoload._holster_cooldown -= delta
	update_holster_zone_haptics()
	update_holster_holos()


func refresh_holster_zone_cache() -> void:
	var frame := Engine.get_process_frames()
	if frame == autoload._holster_zone_cache_frame:
		return
	autoload._holster_zone_cache_frame = frame
	autoload._holster_zone_world_cache.clear()
	var snap = autoload._refresh_vrframe()
	if not snap["cam_valid"]:
		return
	var head_pos: Vector3 = snap["cam_pos"]
	var yaw_basis: Basis = snap["yaw_basis"]
	for slot in autoload.HOLSTER_ZONES:
		var o: Vector3 = autoload._holster_offsets[slot]
		var eff := Vector3(-o.x, o.y, o.z) if autoload._holster_zones_mirrored else o
		autoload._holster_zone_world_cache[slot] = head_pos + yaw_basis * eff


func get_nearby_holster_zone(controller_pos: Vector3) -> int:
	refresh_holster_zone_cache()
	if autoload._holster_zone_world_cache.is_empty():
		return 0
	var closest_zone := 0
	var closest_dist = autoload._holster_zone_radius
	for slot in autoload.HOLSTER_ZONES:
		var dist: float = controller_pos.distance_to(autoload._holster_zone_world_cache[slot])
		if dist < closest_dist:
			closest_dist = dist
			closest_zone = slot
	return closest_zone


func update_holster_zone_haptics() -> void:
	# Check each controller against holster zones and pulse haptic on entry
	for hand in ["left", "right"]:
		var ctrl = autoload._get_controller(hand)
		if not ctrl or not ctrl.get_is_active():
			continue
		var zone = get_nearby_holster_zone(ctrl.global_position)
		var prev_zone: int = autoload._hand_in_zone[hand]
		if zone != prev_zone:
			if zone > 0 and autoload._holster_cooldown <= 0.0:
				# Entered a new zone - haptic buzz (suppressed during holster cooldown)
				ctrl.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.15, 0.0)
				autoload._log("[VR Mod] ", hand, " hand entered zone: ", autoload.HOLSTER_ZONES[zone]["name"])
			autoload._hand_in_zone[hand] = zone

	# Bag zone haptic: buzz when the grabbing hand enters the bag zone while
	# holding a loose item. The grabbed-object reference and grab hand stay
	# on the autoload (broadly read), but the bag-zone latch is grab-internal.
	var grab_sys = autoload._ensure_grab()
	if autoload._grabbed_object and is_instance_valid(autoload._grabbed_object) and autoload._grab_hand != "":
		var grab_ctrl = autoload._get_controller(autoload._grab_hand)
		if grab_ctrl and grab_ctrl.get_is_active():
			var in_zone = autoload._is_in_bag_zone(grab_ctrl.global_position)
			if in_zone and not grab_sys.in_bag_zone:
				grab_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.2, 0.0)
				autoload._log("[VR Mod] Grab hand entered bag zone")
			grab_sys.in_bag_zone = in_zone
	else:
		grab_sys.in_bag_zone = false

	# NVG zone haptic: buzz when either hand enters the NVG zone above head.
	# The latch lives on the Nvg subsystem (only this loop writes it).
	var nvg_sys = autoload._ensure_nvg()
	for hand in ["left", "right"]:
		var ctrl = autoload._get_controller(hand)
		if not ctrl or not ctrl.get_is_active():
			nvg_sys.hand_in_zone[hand] = false
			continue
		var in_zone = autoload._is_in_nvg_zone(ctrl.global_position)
		if in_zone and not nvg_sys.hand_in_zone[hand]:
			ctrl.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.15, 0.0)
			autoload._log("[VR Mod] ", hand, " hand entered NVG zone")
		nvg_sys.hand_in_zone[hand] = in_zone


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

	# Slot 2: pistol - slide along Z (barrel forward), grip hanging below
	var pistol := Node3D.new()
	pistol.name = "HoloPistol"
	autoload.add_child(pistol)
	add_holo_box(pistol, Vector3(0.026, 0.038, 0.100), Vector3(0.0, 0.008, 0.0), Vector3.ZERO, mat)
	add_holo_box(pistol, Vector3(0.022, 0.058, 0.030), Vector3(0.0, -0.037, 0.018), Vector3(deg_to_rad(10.0), 0.0, 0.0), mat)
	add_holo_box(pistol, Vector3(0.022, 0.014, 0.034), Vector3(0.0, -0.010, 0.006), Vector3.ZERO, mat)
	add_holo_cyl(pistol, 0.007, 0.028, Vector3(0.0, 0.003, -0.064), Vector3(PI / 2.0, 0.0, 0.0), mat)
	autoload._holster_holo_nodes[2] = pistol

	# Slot 3: knife - blade pointing up, guard at centre, handle cylinder below
	var knife := Node3D.new()
	knife.name = "HoloKnife"
	autoload.add_child(knife)
	add_holo_box(knife, Vector3(0.016, 0.115, 0.004), Vector3(0.0, 0.072, 0.0), Vector3.ZERO, mat)
	add_holo_box(knife, Vector3(0.040, 0.009, 0.006), Vector3(0.0, 0.010, 0.0), Vector3.ZERO, mat)
	add_holo_cyl(knife, 0.009, 0.060, Vector3(0.0, -0.035, 0.0), Vector3.ZERO, mat)
	autoload._holster_holo_nodes[3] = knife

	# Slot 4: grenade - sphere body, safety lever bar, fuse cylinder on top, pin nub
	var grenade := Node3D.new()
	grenade.name = "HoloGrenade"
	autoload.add_child(grenade)
	add_holo_sph(grenade, 0.030, Vector3(0.0, 0.0, 0.0), mat)
	add_holo_box(grenade, Vector3(0.058, 0.009, 0.014), Vector3(0.0, 0.012, 0.0), Vector3.ZERO, mat)
	add_holo_cyl(grenade, 0.007, 0.018, Vector3(0.0, 0.038, 0.0), Vector3.ZERO, mat)
	add_holo_box(grenade, Vector3(0.006, 0.006, 0.020), Vector3(0.018, 0.030, 0.0), Vector3.ZERO, mat)
	autoload._holster_holo_nodes[4] = grenade


func destroy_holster_holos() -> void:
	for slot in autoload._holster_holo_nodes.keys():
		var node = autoload._holster_holo_nodes[slot]
		if node and is_instance_valid(node):
			node.queue_free()
	autoload._holster_holo_nodes.clear()


func update_holster_holos() -> void:
	if autoload._holster_holo_nodes.is_empty():
		return
	if not autoload.xr_camera or not is_instance_valid(autoload.xr_camera):
		return
	var head_pos = autoload.xr_camera.global_position
	var yaw_basis := Basis(Vector3.UP, autoload.xr_camera.global_rotation.y)
	for slot in autoload._holster_holo_nodes.keys():
		var node: Node3D = autoload._holster_holo_nodes[slot]
		if not is_instance_valid(node):
			continue
		node.visible = autoload._holster_holos_enabled and (autoload._weapon_slot != slot)
		if not node.visible:
			continue
		var o: Vector3 = autoload._holster_offsets[slot]
		var eff := Vector3(-o.x, o.y, o.z) if autoload._holster_zones_mirrored else o
		node.global_position = head_pos + yaw_basis * eff
		node.global_basis = yaw_basis


func draw_weapon(hand: String, slot: int) -> void:
	autoload._log("[VR Mod] DRAW weapon slot ", slot, " (", autoload.HOLSTER_ZONES[slot]["name"], ") with ", hand, " hand")
	autoload._holster_state = autoload.HolsterState.DRAWN
	autoload._weapon_hand = hand
	autoload._weapon_slot = slot
	# Player manually drew - pre-transition slot is no longer relevant.
	autoload._transition_slot = 0
	autoload._transition_hand = ""

	# Cancel any pending holster KEY injection - prevents double-toggle when
	# holster and draw happen within 0.15 s of each other.
	autoload._pending_holster_key = -1

	# Inject the key to equip this weapon slot
	var key: int = autoload.HOLSTER_ZONES[slot]["key"]
	autoload._inject_key(key, true)
	autoload.get_tree().create_timer(0.1).timeout.connect(func(): autoload._inject_key(key, false))

	# Start weapon load detection + auto-raise sequence
	autoload._weapon_loaded = false
	autoload._weapon_is_long = false
	autoload._recoil_rest_xform = Transform3D.IDENTITY
	autoload._recoil_rest_inv = Transform3D.IDENTITY
	autoload._prev_recoil_mag = 0.0
	autoload._fire_haptic_cooldown = 0.0
	autoload._walk_sway_captured = false
	autoload._walk_sway_logged = false
	autoload._rest_capture_pending = false
	autoload._walk_sway_capture_delay = 0.0
	autoload._clear_grenade_state()
	autoload._weapon_raise_timer = 3.0
	autoload._scroll_cooldown = 1.0
	autoload._ensure_scope_pip().fixed_reticle_instances.clear()  # Re-scan for reticle on new weapon
	autoload._cleanup_scope()  # Re-detect scope on new weapon
	autoload._patch_resume_state(autoload._weapon_slot, autoload._weapon_hand)


func lower_weapon() -> void:
	autoload._log("[VR Mod] LOWER weapon (slot ", autoload._weapon_slot, ")")
	autoload._adjust_mode = false
	autoload._fg_adjust_mode = false
	if autoload._rail_mode:
		autoload._exit_rail_mode()
	autoload._clear_grenade_state()
	autoload._holster_state = autoload.HolsterState.LOWERED
	autoload._support_grip_held = false
	# Set weapon_low to lower the weapon visually
	autoload._inject_action("weapon_low", true)
	autoload.get_tree().create_timer(0.1).timeout.connect(func(): autoload._inject_action("weapon_low", false))
	# Release fire/aim in case they were held
	Input.action_release("fire")
	Input.action_release("left_mouse")
	autoload._inject_action("fire", false)
	autoload._inject_action("left_mouse", false)
	autoload._inject_mouse_button(MOUSE_BUTTON_LEFT, false)
	autoload._inject_action("aim", false)
	autoload._inject_mouse_button(MOUSE_BUTTON_RIGHT, false)


func enter_sling() -> void:
	autoload._log("[VR Mod] SLING weapon (slot ", autoload._weapon_slot, ")")
	autoload._adjust_mode = false
	autoload._fg_adjust_mode = false
	if autoload._rail_mode:
		autoload._exit_rail_mode()
	autoload._clear_grenade_state()
	autoload._holster_state = autoload.HolsterState.SLING
	autoload._support_grip_held = false
	# weapon_low signals the game to recharge arm stamina and show the aiming laser
	autoload._inject_action("weapon_low", true)
	autoload.get_tree().create_timer(0.1).timeout.connect(func(): autoload._inject_action("weapon_low", false))
	Input.action_release("fire")
	Input.action_release("left_mouse")
	autoload._inject_action("fire", false)
	autoload._inject_action("left_mouse", false)
	autoload._inject_mouse_button(MOUSE_BUTTON_LEFT, false)
	autoload._inject_action("aim", false)
	autoload._inject_mouse_button(MOUSE_BUTTON_RIGHT, false)


func raise_weapon() -> void:
	autoload._log("[VR Mod] RAISE weapon (slot ", autoload._weapon_slot, ")")
	autoload._holster_state = autoload.HolsterState.DRAWN
	# Re-raise the weapon
	autoload._inject_action("weapon_high", true)
	autoload.get_tree().create_timer(0.1).timeout.connect(func(): autoload._inject_action("weapon_high", false))


func holster_weapon() -> void:
	autoload._log("[VR Mod] HOLSTER weapon (slot ", autoload._weapon_slot, ")")
	autoload._adjust_mode = false
	autoload._fg_adjust_mode = false
	if autoload._rail_mode:
		autoload._exit_rail_mode()
	autoload._cleanup_scope()
	# Release aim
	autoload._inject_action("aim", false)
	autoload._inject_mouse_button(MOUSE_BUTTON_RIGHT, false)
	autoload._inject_action("weapon_high", false)

	# Unequip: inject the same key to toggle off, but delay by HOLSTER_KEY_DELAY_SEC so that a
	# draw_weapon() call in the same frame (or within that window) can cancel it
	# via _pending_holster_key, avoiding a double-toggle that leaves the weapon stuck.
	if autoload._weapon_slot > 0 and autoload.HOLSTER_ZONES.has(autoload._weapon_slot):
		var key: int = autoload.HOLSTER_ZONES[autoload._weapon_slot]["key"]
		autoload._pending_holster_key = key
		autoload.get_tree().create_timer(autoload.HOLSTER_KEY_DELAY_SEC).timeout.connect(func():
			if autoload._pending_holster_key == key:
				autoload._pending_holster_key = -1
				autoload._inject_key(key, true)
				autoload.get_tree().create_timer(autoload.HOLSTER_KEY_RELEASE_SEC).timeout.connect(func(): autoload._inject_key(key, false))
		)

	autoload._holster_state = autoload.HolsterState.UNARMED
	autoload._weapon_hand = ""
	autoload._weapon_slot = 0
	autoload._current_weapon_name = ""
	autoload._weapon_loaded = false
	autoload._weapon_is_long = false
	autoload._weapon_subtype = ""
	autoload._weapon_uses_r_reload = false
	autoload._action_open = false
	autoload._pump_gesture_active = false
	autoload._pump_prev_pos = Vector3.ZERO
	autoload._pump_cooldown = 0.0
	autoload._recoil_rest_xform = Transform3D.IDENTITY
	autoload._recoil_rest_inv = Transform3D.IDENTITY
	autoload._prev_recoil_mag = 0.0
	autoload._fire_haptic_cooldown = 0.0
	autoload._walk_sway_captured = false
	autoload._walk_sway_logged = false
	autoload._rest_capture_pending = false
	autoload._walk_sway_capture_delay = 0.0
	autoload._clear_grenade_state()
	autoload._support_grip_held = false
	autoload._holster_cooldown = 0.8  # Block re-draw until animation completes
	autoload._patch_resume_state(0, "")
