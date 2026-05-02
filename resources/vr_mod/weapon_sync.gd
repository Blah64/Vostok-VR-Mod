extends RefCounted

# weapon_sync.gd
# Per-frame weapon-rig sync to controller (single hand + two-hand smoothing),
# foregrip lock, sway/recoil sampling, walk-sway suppression, weapon
# classification, pump gesture, arm hiding, weapon cache, and per-weapon
# grip/foregrip key helpers.
#
# Owns: weapon_cache, two-hand smoothing basis, foregrip lock state, the
# shared invisible material used to hide game arm meshes. The per-weapon
# grip dictionaries (_weapon_grip_offsets, _weapon_fg_p_local, etc.) stay
# on the autoload because the F8 config screen and config_io serializer
# both write them directly.

var autoload: Node

# Subsystem-owned state. Previously these fields were dynamically assigned
# on the autoload (e.g. weapon_cache = {...}), which works because
# Node is duck-typed but bypassed any declaration. Owning them here makes
# the lifecycle explicit and keeps the autoload's surface clean.
var weapon_cache: Dictionary = {}
var weapon_cache_id: int = 0
var invis_mat: StandardMaterial3D = null

# Two-hand aim smoothing: smoothed Basis seeded each two-hand transition,
# plus an unsmoothed raw target used for arc-pivot compensation.
var two_hand_smooth_basis: Basis = Basis.IDENTITY
var two_hand_was_active: bool = false
var arc_raw_aim_basis: Basis = Basis.IDENTITY

# Foregrip lock: weapon-local position/rotation of the support hand on the
# foregrip, captured/loaded each two-hand grab, restored each frame.
var fg_p_sup_local: Vector3 = Vector3.ZERO
var fg_r_sup_local: Basis = Basis.IDENTITY
var fg_grip_captured: bool = false


func _init(p_autoload: Node) -> void:
	autoload = p_autoload


func process(frame: Dictionary, delta: float) -> void:
	# Weapon-related per-frame work owned by weapon_sync:
	#  * scroll cooldowns (general + rail-slide stick scroll)
	#  * rail-mode long-press X resolution
	#  * shotgun pump gesture detection (DRAWN + two-hand only)
	#  * weapon-load detection + DRAWN restore + auto-raise timer
	#  * weapon-rig per-frame transform/sway sync (skipped in decor mode)
	#  * rail slide (off-hand projection -> Ctrl+scroll injection)
	_tick_scroll_cooldowns(delta)
	_tick_rail_long_press()
	if autoload._weapon_subtype == "Shotgun" and autoload._holster_state == autoload.HolsterState.DRAWN and autoload._support_grip_held and not autoload._action_open:
		update_pump_gesture(delta)
	_detect_weapon_loaded()
	_tick_weapon_raise(delta)
	if not frame.get("decor_mode", false):
		sync_weapon_to_controller()
	update_rail_slide()


func _tick_scroll_cooldowns(delta: float) -> void:
	if autoload._scroll_cooldown > 0.0:
		autoload._scroll_cooldown -= delta
	if autoload._rail_scroll_cooldown > 0.0:
		autoload._rail_scroll_cooldown -= delta


func _tick_rail_long_press() -> void:
	# X held >= RAIL_MODE_LONG_PRESS_SEC while DRAWN -> enter rail-slide mode.
	if not autoload._rail_x_pending:
		return
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - autoload._rail_x_press_time
	if elapsed >= autoload.RAIL_MODE_LONG_PRESS_SEC:
		autoload._rail_x_pending = false
		autoload._enter_rail_mode()


func _detect_weapon_loaded() -> void:
	# Game weapon nodes appear under game_camera/Manager a few frames after the
	# camera does. When the first child appears, classify the weapon, defer
	# rest-pose capture until Handling.gd has finished its raise animation, and
	# restore DRAWN state if the player was armed before the load (level
	# transition or app-restart resume).
	if autoload._weapon_loaded or not autoload.game_camera or not is_instance_valid(autoload.game_camera):
		return
	var mgr = autoload.game_camera.get_node_or_null("Manager")
	if not mgr or mgr.get_child_count() <= 0:
		return
	autoload._weapon_loaded = true
	var wep = mgr.get_child(0)
	autoload._log("[VR Mod] *** WEAPON LOADED: ", wep.name, " ***")
	autoload._weapon_is_long = classify_weapon_is_long(wep)
	autoload._weapon_subtype = get_weapon_subtype(wep)
	autoload._weapon_uses_r_reload = autoload._weapon_subtype == "Shotgun" or autoload._weapon_subtype == "Bolt"
	autoload._action_open = false
	autoload._pump_gesture_active = false
	autoload._pump_prev_pos = Vector3.ZERO
	# Defer rest capture until Handling.gd has animated the weapon from
	# pre-raise offset to its aimed position so _recoil_rest_xform and
	# _walk_sway_rest agree on the steady-state aimed pose. Capturing at load
	# time locks _recoil_rest_xform at (0,-0.5,-0.5) which creates a ~0.7m jump
	# whenever walk-sway is toggled.
	autoload._recoil_rest_xform = Transform3D.IDENTITY
	autoload._recoil_rest_inv = Transform3D.IDENTITY
	autoload._walk_sway_captured = false
	autoload._walk_sway_logged = false
	autoload._rest_capture_pending = true
	autoload._walk_sway_capture_delay = autoload._WALK_SWAY_CAPTURE_DELAY_LOAD
	autoload._rest_capture_stability_count = 0
	# Restore DRAWN state whenever weapon loads and mod isn't controlling it.
	# Priority: _transition_slot (in-session zone change) -> _resume_slot
	# (persisted to config, survives app restarts) -> slot 1 fallback (handles
	# first-ever launch before any resume state exists).
	if autoload._holster_state == autoload.HolsterState.UNARMED:
		var restore_slot: int = autoload._transition_slot if autoload._transition_slot > 0 else autoload._resume_slot
		if restore_slot == 0:
			restore_slot = 1
		var restore_hand: String = autoload._transition_hand if autoload._transition_hand != "" else (autoload._resume_hand if autoload._resume_hand != "" else autoload._config_dominant_hand)
		autoload._holster_state = autoload.HolsterState.DRAWN
		autoload._weapon_slot = restore_slot
		autoload._weapon_hand = restore_hand
		autoload._log("[VR Mod] Restoring DRAWN state: slot=", autoload._weapon_slot, " hand=", autoload._weapon_hand)
		autoload._transition_slot = 0
		autoload._transition_hand = ""
		autoload._resume_slot = 0
		autoload._resume_hand = ""
	# Auto-raise weapon after short delay
	autoload._weapon_raise_timer = 0.5
	autoload._log("[VR Mod] Will auto-raise weapon in 0.5s")


func _tick_weapon_raise(delta: float) -> void:
	if autoload._weapon_raise_timer <= 0:
		return
	autoload._weapon_raise_timer -= delta
	if autoload._weapon_raise_timer > 0:
		return
	autoload._weapon_raise_timer = -1.0
	if autoload._holster_state != autoload.HolsterState.DRAWN:
		return
	if not autoload._weapon_loaded:
		# Slot was empty - abort and revert to unarmed
		autoload._log("[VR Mod] Slot ", autoload._weapon_slot, " empty, reverting to UNARMED")
		autoload._holster_state = autoload.HolsterState.UNARMED
		autoload._weapon_hand = ""
		autoload._weapon_slot = 0
		autoload._support_grip_held = false
	else:
		autoload._log("[VR Mod] Auto-raising weapon (weapon_high)")
		autoload._inject_action("weapon_high", true)
		autoload.get_tree().create_timer(0.1).timeout.connect(
			func(): autoload._inject_action("weapon_high", false)
		)


func update_rail_slide() -> void:
	if not autoload._rail_active:
		return
	var support_ctrl = autoload._get_controller(autoload._get_support_hand())
	if not support_ctrl or not autoload.game_camera:
		return
	var current_proj: float = support_ctrl.global_position.dot(autoload._rail_fwd)
	var delta_proj: float = current_proj - autoload._rail_grab_origin
	autoload._rail_scroll_accum += delta_proj
	autoload._rail_grab_origin = current_proj
	var threshold := 0.02  # 2 cm per scroll tick
	while autoload._rail_scroll_accum > threshold:
		autoload._inject_scroll(1)
		autoload._rail_scroll_accum -= threshold
		support_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.15, 0.05, 0.0)
	while autoload._rail_scroll_accum < -threshold:
		autoload._inject_scroll(-1)
		autoload._rail_scroll_accum += threshold
		support_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.15, 0.05, 0.0)


func collect_arms_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D and node.name == "Arms":
		out.append(node)
		return  # arms found at this branch - don't recurse below
	for child in node.get_children():
		collect_arms_meshes(child, out)


func ensure_weapon_cache(weapon_rig: Node3D) -> Dictionary:
	var id := weapon_rig.get_instance_id()
	# Reuse cache only when (a) same weapon_rig and (b) the chain was complete
	# last time. An incomplete chain means the game was still loading the weapon,
	# so we keep retrying each frame until all chain nodes are present.
	if id == weapon_cache_id and weapon_cache.get("chain_complete", false):
		return weapon_cache
	var prev_arms_hidden: bool = weapon_cache.get("arms_hidden", false) if id == weapon_cache_id else false
	weapon_cache_id = id
	var chain: Dictionary = {}
	var complete := true
	var current: Node3D = weapon_rig
	for chain_name in autoload._RECOIL_CHAIN_NAMES:
		var child = current.get_node_or_null(chain_name)
		if not child or not child is Node3D:
			complete = false
			break
		chain[chain_name] = child
		current = child
	var arms: Array = []
	collect_arms_meshes(weapon_rig, arms)
	# Resolve Skeleton3D + Attachments once chain is complete.
	var skeleton: Node = null
	var attachments: Node = null
	if complete:
		skeleton = autoload._find_node_by_class(weapon_rig, "Skeleton3D")
		if skeleton:
			attachments = skeleton.get_node_or_null("Attachments")
	weapon_cache = {
		"chain": chain,
		"chain_complete": complete,
		"arms": arms,
		"arms_hidden": prev_arms_hidden,
		"skeleton": skeleton,
		"attachments": attachments,
	}
	return weapon_cache


func hide_arms_in_subtree(weapon_rig: Node3D) -> void:
	var cache := ensure_weapon_cache(weapon_rig)
	if cache["arms_hidden"]:
		return
	# Hide ALL surfaces - arms (0-1) AND hands (2+).
	if not invis_mat:
		invis_mat = StandardMaterial3D.new()
		invis_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		invis_mat.albedo_color = Color(0, 0, 0, 0)
	var any_hidden := false
	for arms_mi in cache["arms"]:
		if not is_instance_valid(arms_mi):
			continue
		var mesh := arms_mi as MeshInstance3D
		if not mesh.mesh:
			continue
		for i in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(i, invis_mat)
		any_hidden = true
	if any_hidden:
		cache["arms_hidden"] = true
	else:
		# Arms not yet present - re-walk the subtree on next call so we pick them up
		var fresh: Array = []
		collect_arms_meshes(weapon_rig, fresh)
		cache["arms"] = fresh


func weapon_key() -> String:
	return autoload._weapon_hand + "|" + autoload._current_weapon_name


func get_weapon_grip_offset() -> Vector3:
	var k := weapon_key()
	if autoload._current_weapon_name != "" and autoload._weapon_grip_offsets.has(k):
		return autoload._weapon_grip_offsets[k]
	return autoload._slot_grip_defaults.get(autoload._weapon_slot, Vector3.ZERO)


func get_weapon_grip_rotation() -> float:
	var k := weapon_key()
	if autoload._current_weapon_name != "" and autoload._weapon_grip_rotations.has(k):
		return autoload._weapon_grip_rotations[k]
	return autoload._slot_rot_defaults.get(autoload._weapon_slot, 0.0)


func set_weapon_grip_offset(v: Vector3) -> void:
	if autoload._current_weapon_name != "":
		autoload._weapon_grip_offsets[weapon_key()] = v


func set_weapon_grip_rotation(v: float) -> void:
	if autoload._current_weapon_name != "":
		autoload._weapon_grip_rotations[weapon_key()] = v


func has_weapon_fg_p() -> bool:
	return autoload._current_weapon_name != "" and autoload._weapon_fg_p_local.has(weapon_key())


func get_weapon_fg_p() -> Vector3:
	if autoload._current_weapon_name != "":
		return autoload._weapon_fg_p_local.get(weapon_key(), Vector3.ZERO)
	return Vector3.ZERO


func get_weapon_fg_r() -> Basis:
	if autoload._current_weapon_name != "":
		return autoload._weapon_fg_r_local.get(weapon_key(), Basis.IDENTITY)
	return Basis.IDENTITY


func set_weapon_fg_p(v: Vector3) -> void:
	if autoload._current_weapon_name != "":
		autoload._weapon_fg_p_local[weapon_key()] = v


func set_weapon_fg_r(v: Basis) -> void:
	if autoload._current_weapon_name != "":
		autoload._weapon_fg_r_local[weapon_key()] = v


func sync_weapon_to_controller() -> void:
	if not autoload.game_camera or not is_instance_valid(autoload.game_camera):
		return
	if autoload._interface_open:
		return

	if not autoload._cached_mgr or not is_instance_valid(autoload._cached_mgr):
		autoload._cached_mgr = autoload.game_camera.get_node_or_null("Manager")
	var mgr = autoload._cached_mgr
	if not mgr or mgr.get_child_count() == 0:
		# If we think a weapon is equipped but the rig is gone, the game unequipped it
		# externally (e.g. via inventory while drawn).
		if autoload._holster_state != autoload.HolsterState.UNARMED and autoload._weapon_loaded:
			autoload._log("[VR Mod] Weapon rig gone externally - resetting to UNARMED")
			autoload._pending_holster_key = -1
			autoload._adjust_mode = false
			autoload._fg_adjust_mode = false
			if autoload._rail_mode:
				autoload._exit_rail_mode()
			autoload._cleanup_scope()
			autoload._inject_action("aim", false)
			autoload._inject_action("weapon_high", false)
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
			autoload._clear_grenade_state()
			autoload._support_grip_held = false
		return

	var weapon_rig = mgr.get_child(0)
	if not weapon_rig or not weapon_rig is Node3D:
		return
	autoload._cached_weapon_rig = weapon_rig
	autoload._current_weapon_name = weapon_rig.name.trim_suffix("_Rig")

	# Only sync when weapon is equipped (DRAWN or LOWERED)
	if autoload._holster_state == autoload.HolsterState.UNARMED:
		return

	# SLING: position weapon at chest, not at controller
	if autoload._holster_state == autoload.HolsterState.SLING:
		sync_weapon_to_sling(weapon_rig)
		return

	var controller = autoload._get_controller(autoload._get_weapon_hand())
	if not controller or not controller.get_is_active():
		return

	# Two-hand aiming: only when support grip is held
	var off_controller = autoload._get_controller(autoload._get_support_hand())
	var use_two_hand = false
	var aim_basis: Basis

	# Single-hand basis computed at function scope so the smooth-init path can also use it.
	# Grenades (slot 4): ignore grip rotation - throw direction must follow controller forward.
	var sh_rot_offset: float = 0.0 if autoload._weapon_slot == 4 else get_weapon_grip_rotation()
	var single_hand_basis: Basis = controller.global_basis * Basis(Vector3.UP, deg_to_rad(180 + sh_rot_offset))
	var local_offset: Vector3 = get_weapon_grip_offset()

	# Foregrip adjust: freeze the weapon in place so the player can position their support
	# hand freely. Canonical hand resets are applied; normal sync skipped.
	if autoload._fg_adjust_mode:
		weapon_rig.global_transform = autoload._fg_adjust_frozen_xform
		apply_sway_to_hands(weapon_rig, controller, off_controller, single_hand_basis, local_offset, Transform3D.IDENTITY, false, Vector3.ZERO)
		hide_arms_in_subtree(weapon_rig)
		return

	if autoload._support_grip_held and off_controller and off_controller.get_is_active():
		var hand_dist = controller.global_position.distance_to(off_controller.global_position)
		if hand_dist > autoload.TWO_HAND_MIN_DIST_M:
			use_two_hand = true
			# Aim direction: from dominant hand model center toward off-hand controller.
			var dom_hand_off = autoload.HAND_GLTF_OFFSET_RIGHT if autoload._get_weapon_hand() == "right" else autoload.HAND_GLTF_OFFSET_LEFT
			var forward = (off_controller.global_position - controller.global_position - controller.global_basis * dom_hand_off).normalized()
			# Use dominant hand's up as roll reference.
			var up = controller.global_basis.y
			var right_vec = forward.cross(up)
			if right_vec.length_squared() < 0.01:
				up = Vector3.UP
				right_vec = forward.cross(up)
			right_vec = right_vec.normalized()
			var corrected_up = right_vec.cross(forward).normalized()
			aim_basis = Basis(right_vec, corrected_up, -forward)
			aim_basis = aim_basis * Basis(Vector3.UP, deg_to_rad(180))

	if not use_two_hand:
		aim_basis = single_hand_basis

	# Two-hand stabilization: slerp the FULL aim basis from single-hand to the two-hand target.
	if use_two_hand and autoload._two_hand_smooth_enabled:
		var target_basis := aim_basis
		if not two_hand_was_active:
			# First frame: seed from the exact single-hand basis so the weapon stays
			# exactly where it was the moment the off-hand grabs.
			two_hand_smooth_basis = single_hand_basis
			# Also seed raw aim basis - arc_comp on first frame will be ZERO (no jump).
			arc_raw_aim_basis = single_hand_basis
		else:
			# Subsequent frames: record unsmoothed raw aim for arc_comp (no lag).
			arc_raw_aim_basis = target_basis
		two_hand_smooth_basis = two_hand_smooth_basis.slerp(target_basis, clampf(autoload.get_process_delta_time() * autoload._two_hand_smooth_speed, 0.0, 1.0))
		aim_basis = two_hand_smooth_basis

	if use_two_hand:
		two_hand_was_active = true
		if not autoload._two_hand_smooth_enabled:
			# Smooth disabled: aim_basis IS raw aim.
			arc_raw_aim_basis = aim_basis
	else:
		two_hand_was_active = false
		fg_grip_captured = false
		arc_raw_aim_basis = single_hand_basis  # reset so next grab starts clean

	# Handle deferred rest capture
	if autoload._rest_capture_pending:
		autoload._walk_sway_capture_delay -= autoload.get_process_delta_time()
		if autoload._walk_sway_capture_delay <= 0.0:
			# Stability gate
			var sample := sample_recoil_chain(weapon_rig)
			if autoload._rest_capture_stability_count == 0:
				autoload._rest_capture_hard_deadline = 2.0  # hard cap after initial 2s delay
				autoload._rest_capture_stability_count = 1
			else:
				autoload._rest_capture_hard_deadline -= autoload.get_process_delta_time()
				var fwd_now: Vector3 = sample.basis * Vector3(0, 0, 1)
				var fwd_prev: Vector3 = autoload._rest_capture_prev_sample.basis * Vector3(0, 0, 1)
				var angle_diff: float = fwd_now.angle_to(fwd_prev)
				var pos_diff: float = (sample.origin - autoload._rest_capture_prev_sample.origin).length()
				if pos_diff < 0.003 and angle_diff < 0.003:
					autoload._rest_capture_stability_count += 1
				else:
					autoload._rest_capture_stability_count = 1
			autoload._rest_capture_prev_sample = sample
			var force_commit: bool = autoload._rest_capture_hard_deadline <= 0.0
			if autoload._rest_capture_stability_count >= 5 or force_commit:
				autoload._rest_capture_pending = false
				autoload._walk_sway_capture_delay = 0.0
				autoload._recoil_rest_xform = sample
				autoload._recoil_rest_inv = sample.affine_inverse()
				autoload._walk_sway_rest.clear()
				for node_name in autoload._WALK_SWAY_NODES:
					var wn := walk_chain_node(weapon_rig, node_name)
					if wn:
						autoload._walk_sway_rest[node_name] = wn.transform
						if autoload._disable_walk_sway:
							wn.set_process(false)
							wn.set_physics_process(false)
				autoload._walk_sway_captured = true
				autoload._walk_sway_logged = false
				var ori: Vector3 = sample.origin
				var eul: Vector3 = sample.basis.get_euler()
				autoload._log("REST CAPTURE: weapon=" + autoload._current_weapon_name + " slot=" + str(autoload._weapon_slot)
					+ " origin=(" + str(snapped(ori.x, 0.0001)) + "," + str(snapped(ori.y, 0.0001)) + "," + str(snapped(ori.z, 0.0001)) + ")"
					+ " euler_deg=(" + str(snapped(rad_to_deg(eul.x), 0.01)) + "," + str(snapped(rad_to_deg(eul.y), 0.01)) + "," + str(snapped(rad_to_deg(eul.z), 0.01)) + ")"
					+ " stable_frames=" + str(autoload._rest_capture_stability_count)
					+ " forced=" + str(force_commit))
				autoload._rest_capture_stability_count = 0

	# Suppress walk bob at the chain nodes
	if autoload._disable_walk_sway and not autoload._rest_capture_pending:
		suppress_walk_sway(weapon_rig)

	# Sample recoil chain and apply delta on top of controller aim.
	var recoil_delta := Transform3D.IDENTITY
	if not autoload._rest_capture_pending:
		recoil_delta = autoload._recoil_rest_inv * sample_recoil_chain(weapon_rig)
	weapon_rig.global_basis = aim_basis * recoil_delta.basis

	# Fire haptics
	autoload._fire_haptic_cooldown -= autoload.get_process_delta_time()
	var cur_recoil_mag := recoil_delta.origin.length()
	if cur_recoil_mag - autoload._prev_recoil_mag > autoload.RECOIL_FIRE_RISE_EDGE and autoload._fire_haptic_cooldown <= 0.0:
		var hap_dom = autoload._get_controller(autoload._weapon_hand)
		if hap_dom:
			hap_dom.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.08, 0.0)
		if autoload._support_grip_held:
			var hap_sup = autoload._get_controller(autoload._get_support_hand())
			if hap_sup:
				hap_sup.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.08, 0.0)
		autoload._fire_haptic_cooldown = 0.08
		if autoload._verbose_log:
			var rfwd: Vector3 = recoil_delta.basis * Vector3(0, 0, 1)
			var rfwd_angle_deg: float = rad_to_deg(rfwd.angle_to(Vector3(0, 0, 1)))
			autoload._log("FIRE: weapon=" + autoload._current_weapon_name + " slot=" + str(autoload._weapon_slot)
				+ " delta_origin_m=" + str(snapped(recoil_delta.origin.length(), 0.0001))
				+ " delta_fwd_angle_deg=" + str(snapped(rfwd_angle_deg, 0.01))
				+ " prev_origin_m=" + str(snapped(autoload._prev_recoil_mag, 0.0001)))
	autoload._prev_recoil_mag = cur_recoil_mag

	# Pivot compensation
	var arc_comp := Vector3.ZERO
	var arc_is_right = autoload._get_weapon_hand() == "right"
	var arc_dom_off = autoload.HAND_GLTF_OFFSET_RIGHT if arc_is_right else autoload.HAND_GLTF_OFFSET_LEFT
	var arc_dom_rot = autoload.HAND_GLTF_ROTATION_RIGHT if arc_is_right else autoload.HAND_GLTF_ROTATION_LEFT
	var arc_sh_rot := 0.0 if autoload._weapon_slot == 4 else get_weapon_grip_rotation()
	var arc_rot_b := Basis.from_euler(arc_dom_rot * (PI / 180.0))
	var arc_w2h := Basis(Vector3.UP, deg_to_rad(-(180.0 + arc_sh_rot))) * arc_rot_b
	var arc_r_delta := Basis.IDENTITY
	if use_two_hand:
		arc_r_delta = controller.global_basis.inverse() * arc_raw_aim_basis * arc_w2h * arc_rot_b.inverse()
		arc_comp = controller.global_basis * (arc_dom_off - arc_r_delta * arc_dom_off)
	weapon_rig.global_position = controller.global_position + arc_comp + aim_basis * (local_offset + recoil_delta.origin)

	# Displace hand models so they visually follow weapon sway / recoil.
	apply_sway_to_hands(weapon_rig, controller, off_controller, aim_basis, local_offset, recoil_delta, use_two_hand, arc_comp)

	# Hide all arm surfaces on every weapon type
	hide_arms_in_subtree(weapon_rig)

	# Fix reticle parallax for VR (once per sight mesh)
	autoload._fix_reticle_parallax(weapon_rig)

	# Scope PIP: detect and activate game's scope SubViewport, position camera
	autoload._setup_scope_pip(weapon_rig)
	autoload._update_scope_camera()


func apply_sway_to_hands(
		weapon_rig: Node3D,
		dom_ctrl: XRController3D, sup_ctrl: XRController3D,
		aim_basis: Basis, local_offset: Vector3,
		recoil_delta: Transform3D, use_two_hand: bool,
		arc_comp: Vector3) -> void:
	var weapon_hand = autoload._get_weapon_hand()
	var is_right_weapon = weapon_hand == "right"
	var dom_wrapper = autoload._hand_wrapper_right if is_right_weapon else autoload._hand_wrapper_left
	var sup_wrapper = autoload._hand_wrapper_left  if is_right_weapon else autoload._hand_wrapper_right
	var dom_off = autoload.HAND_GLTF_OFFSET_RIGHT    if is_right_weapon else autoload.HAND_GLTF_OFFSET_LEFT
	var dom_rot = autoload.HAND_GLTF_ROTATION_RIGHT  if is_right_weapon else autoload.HAND_GLTF_ROTATION_LEFT
	var sup_off = autoload.HAND_GLTF_OFFSET_LEFT     if is_right_weapon else autoload.HAND_GLTF_OFFSET_RIGHT
	var sup_rot = autoload.HAND_GLTF_ROTATION_LEFT   if is_right_weapon else autoload.HAND_GLTF_ROTATION_RIGHT

	# Always reset both wrappers to canonical pose first; sway is then additive
	if dom_wrapper:
		dom_wrapper.position = dom_off
		dom_wrapper.rotation_degrees = dom_rot
	if sup_wrapper:
		sup_wrapper.position = sup_off
		sup_wrapper.rotation_degrees = sup_rot

	# During two-hand aiming, rotate dominant hand to track the weapon tilt.
	if use_two_hand and dom_wrapper:
		var sh_rot_deg := 0.0 if autoload._weapon_slot == 4 else get_weapon_grip_rotation()
		var dom_rot_basis := Basis.from_euler(dom_rot * (PI / 180.0))
		var weapon_to_hand := Basis(Vector3.UP, deg_to_rad(-(180.0 + sh_rot_deg))) * dom_rot_basis
		var new_hand_basis := dom_ctrl.global_basis.inverse() * weapon_rig.global_basis * weapon_to_hand
		dom_wrapper.transform = Transform3D(new_hand_basis, dom_off)

	if recoil_delta == Transform3D.IDENTITY:
		return

	# Direct tracking
	if dom_wrapper:
		var grip_world := weapon_rig.global_transform * (-local_offset)
		var grip_disp := dom_ctrl.global_basis.inverse() * (grip_world - dom_ctrl.global_position)
		var arc_local := dom_ctrl.global_basis.inverse() * arc_comp
		dom_wrapper.position = dom_off + grip_disp - arc_local

	if use_two_hand and sup_ctrl and sup_ctrl.get_is_active() and sup_wrapper:
		# Foregrip adjust active: gun is frozen, support hand follows controller canonically.
		if not autoload._fg_adjust_mode:
			# First frame of two-hand or after release: load per-slot saved position/rotation.
			if not fg_grip_captured:
				if has_weapon_fg_p():
					fg_p_sup_local = get_weapon_fg_p()
					fg_r_sup_local = get_weapon_fg_r()
				else:
					var hand_wp = sup_ctrl.global_position + sup_ctrl.global_basis * sup_off
					var hand_wb := sup_ctrl.global_basis * Basis.from_euler(sup_rot * (PI / 180.0))
					fg_p_sup_local = weapon_rig.global_transform.affine_inverse() * hand_wp
					fg_r_sup_local = weapon_rig.global_basis.inverse() * hand_wb
				fg_grip_captured = true
			var sup_grip_world := weapon_rig.global_transform * fg_p_sup_local
			var tgt_basis := weapon_rig.global_basis * fg_r_sup_local
			sup_wrapper.position = sup_ctrl.global_basis.inverse() * (sup_grip_world - sup_ctrl.global_position)
			sup_wrapper.basis = sup_ctrl.global_basis.inverse() * tgt_basis


func sync_weapon_to_sling(weapon_rig: Node3D) -> void:
	if not autoload.xr_camera or not is_instance_valid(autoload.xr_camera):
		return
	weapon_rig.visible = true  # override any game-side visibility flag each frame
	# Build a yaw-only basis from the camera so the weapon follows the player's turn
	var head_yaw = autoload.xr_camera.global_rotation.y
	var yaw_basis := Basis(Vector3.UP, head_yaw)
	weapon_rig.global_position = autoload.xr_camera.global_position + yaw_basis * autoload._sling_offset
	# Orient weapon to face forward with the same handedness as the drawn single-hand basis
	var slot_y_rot: float = get_weapon_grip_rotation()
	var base_basis := yaw_basis * Basis(Vector3.UP, deg_to_rad(180.0 + slot_y_rot))
	weapon_rig.global_basis = base_basis * Basis.from_euler(Vector3(
		deg_to_rad(autoload._sling_rot_offset.x),
		deg_to_rad(autoload._sling_rot_offset.y),
		deg_to_rad(autoload._sling_rot_offset.z)))
	hide_arms_in_subtree(weapon_rig)


func sample_recoil_chain(weapon_rig: Node3D) -> Transform3D:
	var chain: Dictionary = ensure_weapon_cache(weapon_rig)["chain"]
	var composed := Transform3D.IDENTITY
	for chain_name in autoload._RECOIL_CHAIN_NAMES:
		if not chain.has(chain_name):
			break
		var node: Node3D = chain[chain_name]
		if not is_instance_valid(node):
			# Cache stale (game replaced the chain); drop it and rebuild next frame.
			weapon_cache.clear()
			weapon_cache_id = 0
			break
		composed = composed * node.transform
	return composed


func walk_chain_node(weapon_rig: Node3D, node_name: String) -> Node3D:
	var chain: Dictionary = ensure_weapon_cache(weapon_rig)["chain"]
	if not chain.has(node_name):
		return null
	var node: Node3D = chain[node_name]
	if not is_instance_valid(node):
		weapon_cache.clear()
		weapon_cache_id = 0
		return null
	return node


func suppress_walk_sway(weapon_rig: Node3D) -> void:
	if not autoload._walk_sway_captured:
		autoload._walk_sway_rest.clear()
		for node_name in autoload._WALK_SWAY_NODES:
			var n := walk_chain_node(weapon_rig, node_name)
			if n:
				autoload._walk_sway_rest[node_name] = n.transform
				n.set_process(false)
				n.set_physics_process(false)
		autoload._walk_sway_captured = true
		autoload._walk_sway_logged = false
	for node_name in autoload._WALK_SWAY_NODES:
		if not autoload._walk_sway_rest.has(node_name):
			continue
		var n := walk_chain_node(weapon_rig, node_name)
		if n:
			n.transform = autoload._walk_sway_rest[node_name]
	# One-time diagnostic
	if not autoload._walk_sway_logged:
		autoload._walk_sway_logged = true
		var f = FileAccess.open(autoload._log_path, FileAccess.READ_WRITE)
		if not f:
			f = FileAccess.open(autoload._log_path, FileAccess.WRITE)
		if f:
			f.seek_end(0)
			f.store_line("[walk_sway] captured rest poses:")
			for node_name in autoload._WALK_SWAY_NODES:
				if autoload._walk_sway_rest.has(node_name):
					var t: Transform3D = autoload._walk_sway_rest[node_name]
					f.store_line("  " + node_name + " origin=" + str(t.origin) + " basis_x=" + str(t.basis.x) + " basis_y=" + str(t.basis.y) + " basis_z=" + str(t.basis.z))
				else:
					f.store_line("  " + node_name + " NOT FOUND in chain")
			f.close()


func classify_weapon_is_long(weapon_rig: Node3D) -> bool:
	# Slots 3 (knife) and 4 (grenade) are never long weapons
	if autoload._weapon_slot == 3 or autoload._weapon_slot == 4:
		autoload._log("Weapon class: short (slot " + str(autoload._weapon_slot) + ")")
		return false
	# Check weapon data resource for weaponType property (authoritative)
	var data_res = weapon_rig.get("data")
	if data_res and data_res is Resource:
		var weapon_type = data_res.get("weaponType")
		var subtype = data_res.get("subtype")
		autoload._log("Weapon classify: name=" + weapon_rig.name + " slot=" + str(autoload._weapon_slot)
			+ " weaponType=" + str(weapon_type) + " subtype=" + str(subtype))
		if weapon_type != null:
			var wt: String = str(weapon_type).to_lower()
			# Long weapon types: rifle, shotgun, SMG, carbine, DMR, sniper, LMG, etc.
			# Short weapon types: pistol
			if "pistol" in wt:
				autoload._log("Weapon class: short (weaponType=" + str(weapon_type) + ")")
				return false
			# Any non-pistol firearm type is long
			autoload._log("Weapon class: long (weaponType=" + str(weapon_type) + ")")
			return true
	# Fallback: slot 2 defaults to short, slot 1 defaults to long
	autoload._log("Weapon classify: name=" + weapon_rig.name + " slot=" + str(autoload._weapon_slot) + " (no data resource)")
	if autoload._weapon_slot == 2:
		autoload._log("Weapon class: short (sidearm slot, no weaponType)")
		return false
	autoload._log("Weapon class: long (default for slot " + str(autoload._weapon_slot) + ")")
	return true


func get_weapon_subtype(weapon_rig: Node3D) -> String:
	if autoload._weapon_slot == 3:
		return "Melee"
	if autoload._weapon_slot == 4:
		return "Grenade"
	var data_res = weapon_rig.get("data")
	if data_res and data_res is Resource:
		var st = data_res.get("subtype")
		if st != null:
			return str(st)
	return ""


func update_pump_gesture(delta: float) -> void:
	autoload._pump_cooldown -= delta
	var sup_ctrl = autoload._get_controller(autoload._get_support_hand())
	if not sup_ctrl:
		return
	var pos: Vector3 = sup_ctrl.position
	# Initialize reference on first call or after reset
	if autoload._pump_prev_pos == Vector3.ZERO:
		autoload._pump_prev_pos = pos
		return
	# PUMP_OUT: how far hand must move from reference to start the gesture.
	# PUMP_BACK: how close hand must return to the frozen reference to complete it.
	const PUMP_OUT := 0.04
	const PUMP_BACK := 0.03
	const TRACK_RATE := 2.0
	if not autoload._pump_gesture_active:
		autoload._pump_prev_pos = autoload._pump_prev_pos.lerp(pos, delta * TRACK_RATE)
		if pos.distance_to(autoload._pump_prev_pos) > PUMP_OUT:
			autoload._pump_gesture_active = true
			autoload._pump_gesture_timer = 1.2
			autoload._log("[VR Mod] PUMP: fwd phase dist=", snappedf(pos.distance_to(autoload._pump_prev_pos) * 100.0, 0.1), "cm")
	else:
		autoload._pump_gesture_timer -= delta
		var dist: float = pos.distance_to(autoload._pump_prev_pos)
		if dist < PUMP_BACK:
			if autoload._pump_cooldown <= 0.0:
				autoload._inject_action("reload", true)
				autoload._inject_action("reload", false)
				autoload._log("[VR Mod] PUMP - shell cycled (R)")
				var dom_ctrl = autoload._get_controller(autoload._weapon_hand)
				if dom_ctrl:
					dom_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.12, 0.0)
				autoload._pump_cooldown = 0.5
			autoload._pump_gesture_active = false
			autoload._pump_prev_pos = pos
		elif autoload._pump_gesture_timer <= 0.0:
			autoload._log("[VR Mod] PUMP: timeout dist=", snappedf(dist * 100.0, 0.1), "cm")
			autoload._pump_gesture_active = false
			autoload._pump_prev_pos = pos
