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
#
# This subsystem genuinely touches a lot of cross-system state, so the port
# surface is large. Ports are reached through `_p(name).call(...)`.

# Subsystem-owned state.
var weapon_cache: Dictionary = {}
var weapon_cache_id: int = 0
var invis_mat: StandardMaterial3D = null

# Two-hand aim smoothing.
var two_hand_smooth_basis: Basis = Basis.IDENTITY
var two_hand_was_active: bool = false
var arc_raw_aim_basis: Basis = Basis.IDENTITY

# Foregrip lock.
var fg_p_sup_local: Vector3 = Vector3.ZERO
var fg_r_sup_local: Basis = Basis.IDENTITY
var fg_grip_captured: bool = false


# Ports
var _tree: SceneTree
var _ports: Dictionary
var _log_fn: Callable


func _init(tree: SceneTree, ports: Dictionary) -> void:
	_tree = tree
	_ports = ports
	_log_fn = ports.get("log", Callable())


func _log(msg: String) -> void:
	if _log_fn.is_valid():
		_log_fn.call(msg)


func _p(name: String) -> Callable:
	return _ports[name]


func process(frame: Dictionary, delta: float) -> void:
	# Weapon-related per-frame work owned by weapon_sync.
	_tick_scroll_cooldowns(delta)
	_tick_rail_long_press()
	if _p("get_weapon_subtype").call() == "Shotgun" \
			and _p("get_holster_state").call() == _p("get_state_drawn").call() \
			and _p("get_support_grip_held").call() \
			and not _p("get_action_open").call():
		update_pump_gesture(delta)
	_detect_weapon_loaded()
	_tick_weapon_raise(delta)
	if not frame.get("decor_mode", false):
		sync_weapon_to_controller()
	update_rail_slide()


func _tick_scroll_cooldowns(delta: float) -> void:
	var sc: float = _p("get_scroll_cooldown").call()
	if sc > 0.0:
		_p("set_scroll_cooldown").call(sc - delta)
	var rsc: float = _p("get_rail_scroll_cooldown").call()
	if rsc > 0.0:
		_p("set_rail_scroll_cooldown").call(rsc - delta)


func _tick_rail_long_press() -> void:
	if not _p("get_rail_x_pending").call():
		return
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - _p("get_rail_x_press_time").call()
	if elapsed >= _p("get_rail_long_press_sec").call():
		_p("set_rail_x_pending").call(false)
		_p("enter_rail_mode").call()


func _detect_weapon_loaded() -> void:
	if _p("get_weapon_loaded").call():
		return
	var gc = _p("get_game_camera").call()
	if not gc or not is_instance_valid(gc):
		return
	var mgr = gc.get_node_or_null("Manager")
	if not mgr or mgr.get_child_count() <= 0:
		return
	_p("set_weapon_loaded").call(true)
	var wep = mgr.get_child(0)
	_log("[VR Mod] *** WEAPON LOADED: " + str(wep.name) + " ***")
	_p("set_weapon_is_long").call(classify_weapon_is_long(wep))
	var subtype: String = get_weapon_subtype(wep)
	_p("set_weapon_subtype").call(subtype)
	_p("set_weapon_uses_r_reload").call(subtype == "Shotgun" or subtype == "Bolt")
	_p("set_action_open").call(false)
	_p("set_pump_gesture_active").call(false)
	_p("set_pump_prev_pos").call(Vector3.ZERO)
	_p("set_recoil_rest_xform").call(Transform3D.IDENTITY)
	_p("set_recoil_rest_inv").call(Transform3D.IDENTITY)
	_p("set_walk_sway_captured").call(false)
	_p("set_walk_sway_logged").call(false)
	_p("set_rest_capture_pending").call(true)
	_p("set_walk_sway_capture_delay").call(_p("get_walk_sway_capture_delay_load").call())
	_p("set_rest_capture_stability_count").call(0)
	if _p("get_holster_state").call() == _p("get_state_unarmed").call():
		var ts: int = _p("get_transition_slot").call()
		var rs: int = _p("get_resume_slot").call()
		var restore_slot: int = ts if ts > 0 else rs
		if restore_slot == 0:
			restore_slot = 1
		var th: String = _p("get_transition_hand").call()
		var rh: String = _p("get_resume_hand").call()
		var dh: String = _p("get_dominant_hand").call()
		var restore_hand: String = th if th != "" else (rh if rh != "" else dh)
		_p("set_holster_state").call(_p("get_state_drawn").call())
		_p("set_weapon_slot").call(restore_slot)
		_p("set_weapon_hand").call(restore_hand)
		_log("[VR Mod] Restoring DRAWN state: slot=" + str(restore_slot) + " hand=" + restore_hand)
		_p("set_transition_slot").call(0)
		_p("set_transition_hand").call("")
		_p("set_resume_slot").call(0)
		_p("set_resume_hand").call("")
	_p("set_weapon_raise_timer").call(0.5)
	_log("[VR Mod] Will auto-raise weapon in 0.5s")


func _tick_weapon_raise(delta: float) -> void:
	var t: float = _p("get_weapon_raise_timer").call()
	if t <= 0:
		return
	t -= delta
	_p("set_weapon_raise_timer").call(t)
	if t > 0:
		return
	_p("set_weapon_raise_timer").call(-1.0)
	if _p("get_holster_state").call() != _p("get_state_drawn").call():
		return
	if not _p("get_weapon_loaded").call():
		_log("[VR Mod] Slot " + str(_p("get_weapon_slot").call()) + " empty, reverting to UNARMED")
		_p("set_holster_state").call(_p("get_state_unarmed").call())
		_p("set_weapon_hand").call("")
		_p("set_weapon_slot").call(0)
		_p("set_support_grip_held").call(false)
	else:
		_log("[VR Mod] Auto-raising weapon (weapon_high)")
		_p("inject_action").call("weapon_high", true, 1.0)
		_tree.create_timer(0.1).timeout.connect(Callable(self, "_release_weapon_high"))


func _release_weapon_high() -> void:
	_p("inject_action").call("weapon_high", false, 1.0)


func update_rail_slide() -> void:
	if not _p("get_rail_active").call():
		return
	var support_ctrl = _p("get_controller").call(_p("get_support_hand").call())
	var gc = _p("get_game_camera").call()
	if not support_ctrl or not gc:
		return
	var rail_fwd: Vector3 = _p("get_rail_fwd").call()
	var rail_grab_origin: float = _p("get_rail_grab_origin").call()
	var rail_scroll_accum: float = _p("get_rail_scroll_accum").call()
	var current_proj: float = support_ctrl.global_position.dot(rail_fwd)
	var delta_proj: float = current_proj - rail_grab_origin
	rail_scroll_accum += delta_proj
	rail_grab_origin = current_proj
	var threshold := 0.02  # 2 cm per scroll tick
	while rail_scroll_accum > threshold:
		_p("inject_scroll").call(1)
		rail_scroll_accum -= threshold
		support_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.15, 0.05, 0.0)
	while rail_scroll_accum < -threshold:
		_p("inject_scroll").call(-1)
		rail_scroll_accum += threshold
		support_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.15, 0.05, 0.0)
	_p("set_rail_grab_origin").call(rail_grab_origin)
	_p("set_rail_scroll_accum").call(rail_scroll_accum)


func collect_arms_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D and node.name == "Arms":
		out.append(node)
		return  # arms found at this branch - don't recurse below
	for child in node.get_children():
		collect_arms_meshes(child, out)


func ensure_weapon_cache(weapon_rig: Node3D) -> Dictionary:
	var id := weapon_rig.get_instance_id()
	if id == weapon_cache_id and weapon_cache.get("chain_complete", false):
		return weapon_cache
	var prev_arms_hidden: bool = weapon_cache.get("arms_hidden", false) if id == weapon_cache_id else false
	weapon_cache_id = id
	var chain: Dictionary = {}
	var complete := true
	var current: Node3D = weapon_rig
	var chain_names: Array = _p("get_recoil_chain_names").call()
	for chain_name in chain_names:
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
		skeleton = _p("find_node_by_class").call(weapon_rig, "Skeleton3D")
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
	return _p("get_weapon_hand").call() + "|" + _p("get_current_weapon_name").call()


func get_weapon_grip_offset() -> Vector3:
	var k := weapon_key()
	var name: String = _p("get_current_weapon_name").call()
	var off_dict: Dictionary = _p("get_weapon_grip_offsets").call()
	if name != "" and off_dict.has(k):
		return off_dict[k]
	var slot_def: Dictionary = _p("get_slot_grip_defaults").call()
	return slot_def.get(_p("get_weapon_slot").call(), Vector3.ZERO)


func get_weapon_grip_rotation() -> float:
	var k := weapon_key()
	var name: String = _p("get_current_weapon_name").call()
	var rot_dict: Dictionary = _p("get_weapon_grip_rotations").call()
	if name != "" and rot_dict.has(k):
		return rot_dict[k]
	var slot_def: Dictionary = _p("get_slot_rot_defaults").call()
	return slot_def.get(_p("get_weapon_slot").call(), 0.0)


func set_weapon_grip_offset(v: Vector3) -> void:
	var name: String = _p("get_current_weapon_name").call()
	if name != "":
		var d: Dictionary = _p("get_weapon_grip_offsets").call()
		d[weapon_key()] = v


func set_weapon_grip_rotation(v: float) -> void:
	var name: String = _p("get_current_weapon_name").call()
	if name != "":
		var d: Dictionary = _p("get_weapon_grip_rotations").call()
		d[weapon_key()] = v


func has_weapon_fg_p() -> bool:
	var name: String = _p("get_current_weapon_name").call()
	if name == "":
		return false
	var d: Dictionary = _p("get_weapon_fg_p_local").call()
	return d.has(weapon_key())


func get_weapon_fg_p() -> Vector3:
	var name: String = _p("get_current_weapon_name").call()
	if name != "":
		var d: Dictionary = _p("get_weapon_fg_p_local").call()
		return d.get(weapon_key(), Vector3.ZERO)
	return Vector3.ZERO


func get_weapon_fg_r() -> Basis:
	var name: String = _p("get_current_weapon_name").call()
	if name != "":
		var d: Dictionary = _p("get_weapon_fg_r_local").call()
		return d.get(weapon_key(), Basis.IDENTITY)
	return Basis.IDENTITY


func set_weapon_fg_p(v: Vector3) -> void:
	var name: String = _p("get_current_weapon_name").call()
	if name != "":
		var d: Dictionary = _p("get_weapon_fg_p_local").call()
		d[weapon_key()] = v


func set_weapon_fg_r(v: Basis) -> void:
	var name: String = _p("get_current_weapon_name").call()
	if name != "":
		var d: Dictionary = _p("get_weapon_fg_r_local").call()
		d[weapon_key()] = v


func sync_weapon_to_controller() -> void:
	var gc = _p("get_game_camera").call()
	if not gc or not is_instance_valid(gc):
		return
	if _p("get_interface_open").call():
		return

	var cached_mgr = _p("get_cached_mgr").call()
	if not cached_mgr or not is_instance_valid(cached_mgr):
		cached_mgr = gc.get_node_or_null("Manager")
		_p("set_cached_mgr").call(cached_mgr)
	var mgr = cached_mgr
	if not mgr or mgr.get_child_count() == 0:
		# If we think a weapon is equipped but the rig is gone, the game unequipped it
		# externally (e.g. via inventory while drawn).
		if _p("get_holster_state").call() != _p("get_state_unarmed").call() and _p("get_weapon_loaded").call():
			_log("[VR Mod] Weapon rig gone externally - resetting to UNARMED")
			_p("set_pending_holster_key").call(-1)
			_p("set_adjust_mode").call(false)
			_p("set_fg_adjust_mode").call(false)
			if _p("get_rail_mode").call():
				_p("exit_rail_mode").call()
			_p("cleanup_scope").call()
			_p("inject_action").call("aim", false, 1.0)
			_p("inject_action").call("weapon_high", false, 1.0)
			_p("set_holster_state").call(_p("get_state_unarmed").call())
			_p("set_weapon_hand").call("")
			_p("set_weapon_slot").call(0)
			_p("set_current_weapon_name").call("")
			_p("set_weapon_loaded").call(false)
			_p("set_weapon_is_long").call(false)
			_p("set_weapon_subtype").call("")
			_p("set_weapon_uses_r_reload").call(false)
			_p("set_action_open").call(false)
			_p("set_pump_gesture_active").call(false)
			_p("set_pump_prev_pos").call(Vector3.ZERO)
			_p("set_pump_cooldown").call(0.0)
			_p("clear_grenade_state").call()
			_p("set_support_grip_held").call(false)
		return

	var weapon_rig = mgr.get_child(0)
	if not weapon_rig or not weapon_rig is Node3D:
		return
	_p("set_cached_weapon_rig").call(weapon_rig)
	_p("set_current_weapon_name").call(weapon_rig.name.trim_suffix("_Rig"))

	var hs: int = _p("get_holster_state").call()
	# Only sync when weapon is equipped (DRAWN or LOWERED)
	if hs == _p("get_state_unarmed").call():
		return

	# SLING: position weapon at chest, not at controller
	if hs == _p("get_state_sling").call():
		sync_weapon_to_sling(weapon_rig)
		return

	var weapon_hand: String = _p("get_weapon_hand_resolved").call()
	var support_hand: String = _p("get_support_hand").call()
	var controller = _p("get_controller").call(weapon_hand)
	if not controller or not controller.get_is_active():
		return

	# Two-hand aiming: only when support grip is held
	var off_controller = _p("get_controller").call(support_hand)
	var use_two_hand = false
	var aim_basis: Basis

	# Single-hand basis computed at function scope so the smooth-init path can also use it.
	# Grenades (slot 4): ignore grip rotation - throw direction must follow controller forward.
	var weapon_slot: int = _p("get_weapon_slot").call()
	var sh_rot_offset: float = 0.0 if weapon_slot == 4 else get_weapon_grip_rotation()
	var single_hand_basis: Basis = controller.global_basis * Basis(Vector3.UP, deg_to_rad(180 + sh_rot_offset))
	var local_offset: Vector3 = get_weapon_grip_offset()

	# Foregrip adjust: freeze the weapon in place so the player can position their support hand freely.
	if _p("get_fg_adjust_mode").call():
		weapon_rig.global_transform = _p("get_fg_adjust_frozen_xform").call()
		apply_sway_to_hands(weapon_rig, controller, off_controller, single_hand_basis, local_offset, Transform3D.IDENTITY, false, Vector3.ZERO)
		hide_arms_in_subtree(weapon_rig)
		return

	var two_hand_min_dist: float = _p("get_two_hand_min_dist").call()
	var hand_offset_left: Vector3 = _p("get_hand_offset_left").call()
	var hand_offset_right: Vector3 = _p("get_hand_offset_right").call()

	if _p("get_support_grip_held").call() and off_controller and off_controller.get_is_active():
		var hand_dist = controller.global_position.distance_to(off_controller.global_position)
		if hand_dist > two_hand_min_dist:
			use_two_hand = true
			# Aim direction: from dominant hand model center toward off-hand controller.
			var dom_hand_off = hand_offset_right if weapon_hand == "right" else hand_offset_left
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

	# Two-hand stabilization
	if use_two_hand and _p("get_two_hand_smooth_enabled").call():
		var target_basis := aim_basis
		if not two_hand_was_active:
			two_hand_smooth_basis = single_hand_basis
			arc_raw_aim_basis = single_hand_basis
		else:
			arc_raw_aim_basis = target_basis
		var smooth_speed: float = _p("get_two_hand_smooth_speed").call()
		two_hand_smooth_basis = two_hand_smooth_basis.slerp(target_basis, clampf(_p("get_process_delta").call() * smooth_speed, 0.0, 1.0))
		aim_basis = two_hand_smooth_basis

	if use_two_hand:
		two_hand_was_active = true
		if not _p("get_two_hand_smooth_enabled").call():
			arc_raw_aim_basis = aim_basis
	else:
		two_hand_was_active = false
		fg_grip_captured = false
		arc_raw_aim_basis = single_hand_basis  # reset so next grab starts clean

	# Handle deferred rest capture
	if _p("get_rest_capture_pending").call():
		var delay: float = _p("get_walk_sway_capture_delay").call() - _p("get_process_delta").call()
		_p("set_walk_sway_capture_delay").call(delay)
		if delay <= 0.0:
			# Stability gate
			var sample := sample_recoil_chain(weapon_rig)
			var stability: int = _p("get_rest_capture_stability_count").call()
			if stability == 0:
				_p("set_rest_capture_hard_deadline").call(2.0)
				_p("set_rest_capture_stability_count").call(1)
			else:
				_p("set_rest_capture_hard_deadline").call(_p("get_rest_capture_hard_deadline").call() - _p("get_process_delta").call())
				var prev_sample: Transform3D = _p("get_rest_capture_prev_sample").call()
				var fwd_now: Vector3 = sample.basis * Vector3(0, 0, 1)
				var fwd_prev: Vector3 = prev_sample.basis * Vector3(0, 0, 1)
				var angle_diff: float = fwd_now.angle_to(fwd_prev)
				var pos_diff: float = (sample.origin - prev_sample.origin).length()
				if pos_diff < 0.003 and angle_diff < 0.003:
					_p("set_rest_capture_stability_count").call(stability + 1)
				else:
					_p("set_rest_capture_stability_count").call(1)
			_p("set_rest_capture_prev_sample").call(sample)
			var force_commit: bool = _p("get_rest_capture_hard_deadline").call() <= 0.0
			if _p("get_rest_capture_stability_count").call() >= 5 or force_commit:
				_p("set_rest_capture_pending").call(false)
				_p("set_walk_sway_capture_delay").call(0.0)
				_p("set_recoil_rest_xform").call(sample)
				_p("set_recoil_rest_inv").call(sample.affine_inverse())
				var ws_rest: Dictionary = _p("get_walk_sway_rest").call()
				ws_rest.clear()
				var ws_nodes: Array = _p("get_walk_sway_nodes").call()
				var disable_walk: bool = _p("get_disable_walk_sway").call()
				for node_name in ws_nodes:
					var wn := walk_chain_node(weapon_rig, node_name)
					if wn:
						ws_rest[node_name] = wn.transform
						if disable_walk:
							wn.set_process(false)
							wn.set_physics_process(false)
				_p("set_walk_sway_captured").call(true)
				_p("set_walk_sway_logged").call(false)
				var ori: Vector3 = sample.origin
				var eul: Vector3 = sample.basis.get_euler()
				_log("REST CAPTURE: weapon=" + _p("get_current_weapon_name").call() + " slot=" + str(_p("get_weapon_slot").call())
					+ " origin=(" + str(snapped(ori.x, 0.0001)) + "," + str(snapped(ori.y, 0.0001)) + "," + str(snapped(ori.z, 0.0001)) + ")"
					+ " euler_deg=(" + str(snapped(rad_to_deg(eul.x), 0.01)) + "," + str(snapped(rad_to_deg(eul.y), 0.01)) + "," + str(snapped(rad_to_deg(eul.z), 0.01)) + ")"
					+ " stable_frames=" + str(_p("get_rest_capture_stability_count").call())
					+ " forced=" + str(force_commit))
				_p("set_rest_capture_stability_count").call(0)

	# Suppress walk bob at the chain nodes
	if _p("get_disable_walk_sway").call() and not _p("get_rest_capture_pending").call():
		suppress_walk_sway(weapon_rig)

	# Sample recoil chain and apply delta on top of controller aim.
	var recoil_delta := Transform3D.IDENTITY
	if not _p("get_rest_capture_pending").call():
		recoil_delta = _p("get_recoil_rest_inv").call() * sample_recoil_chain(weapon_rig)
	weapon_rig.global_basis = aim_basis * recoil_delta.basis

	# Fire haptics
	var fire_haptic_cd: float = _p("get_fire_haptic_cooldown").call() - _p("get_process_delta").call()
	_p("set_fire_haptic_cooldown").call(fire_haptic_cd)
	var cur_recoil_mag := recoil_delta.origin.length()
	var prev_recoil_mag: float = _p("get_prev_recoil_mag").call()
	if cur_recoil_mag - prev_recoil_mag > _p("get_recoil_fire_rise_edge").call() and fire_haptic_cd <= 0.0:
		var hap_dom = _p("get_controller").call(_p("get_weapon_hand").call())
		if hap_dom:
			hap_dom.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.08, 0.0)
		if _p("get_support_grip_held").call():
			var hap_sup = _p("get_controller").call(_p("get_support_hand").call())
			if hap_sup:
				hap_sup.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.08, 0.0)
		_p("set_fire_haptic_cooldown").call(0.08)
		if _p("get_verbose_log").call():
			var rfwd: Vector3 = recoil_delta.basis * Vector3(0, 0, 1)
			var rfwd_angle_deg: float = rad_to_deg(rfwd.angle_to(Vector3(0, 0, 1)))
			_log("FIRE: weapon=" + _p("get_current_weapon_name").call() + " slot=" + str(_p("get_weapon_slot").call())
				+ " delta_origin_m=" + str(snapped(recoil_delta.origin.length(), 0.0001))
				+ " delta_fwd_angle_deg=" + str(snapped(rfwd_angle_deg, 0.01))
				+ " prev_origin_m=" + str(snapped(prev_recoil_mag, 0.0001)))
	_p("set_prev_recoil_mag").call(cur_recoil_mag)

	# Pivot compensation
	var arc_comp := Vector3.ZERO
	var arc_is_right = weapon_hand == "right"
	var arc_dom_off = hand_offset_right if arc_is_right else hand_offset_left
	var arc_dom_rot = _p("get_hand_rot_right").call() if arc_is_right else _p("get_hand_rot_left").call()
	var arc_sh_rot := 0.0 if weapon_slot == 4 else get_weapon_grip_rotation()
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
	_p("fix_reticle_parallax").call(weapon_rig)

	# Scope PIP: detect and activate game's scope SubViewport, position camera
	_p("setup_scope_pip").call(weapon_rig)
	_p("update_scope_camera").call()


func apply_sway_to_hands(
		weapon_rig: Node3D,
		dom_ctrl: XRController3D, sup_ctrl: XRController3D,
		aim_basis: Basis, local_offset: Vector3,
		recoil_delta: Transform3D, use_two_hand: bool,
		arc_comp: Vector3) -> void:
	var weapon_hand = _p("get_weapon_hand_resolved").call()
	var is_right_weapon = weapon_hand == "right"
	var hand_offset_left: Vector3 = _p("get_hand_offset_left").call()
	var hand_offset_right: Vector3 = _p("get_hand_offset_right").call()
	var hand_rot_left: Vector3 = _p("get_hand_rot_left").call()
	var hand_rot_right: Vector3 = _p("get_hand_rot_right").call()
	var dom_wrapper: Node3D = _p("get_hand_wrapper").call("right" if is_right_weapon else "left")
	var sup_wrapper: Node3D = _p("get_hand_wrapper").call("left" if is_right_weapon else "right")
	var dom_off = hand_offset_right if is_right_weapon else hand_offset_left
	var dom_rot = hand_rot_right if is_right_weapon else hand_rot_left
	var sup_off = hand_offset_left if is_right_weapon else hand_offset_right
	var sup_rot = hand_rot_left if is_right_weapon else hand_rot_right

	# Always reset both wrappers to canonical pose first; sway is then additive
	if dom_wrapper:
		dom_wrapper.position = dom_off
		dom_wrapper.rotation_degrees = dom_rot
	if sup_wrapper:
		sup_wrapper.position = sup_off
		sup_wrapper.rotation_degrees = sup_rot

	# During two-hand aiming, rotate dominant hand to track the weapon tilt.
	if use_two_hand and dom_wrapper:
		var weapon_slot: int = _p("get_weapon_slot").call()
		var sh_rot_deg := 0.0 if weapon_slot == 4 else get_weapon_grip_rotation()
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
		if not _p("get_fg_adjust_mode").call():
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
	var cam = _p("get_camera").call()
	if not cam or not is_instance_valid(cam):
		return
	weapon_rig.visible = true  # override any game-side visibility flag each frame
	# Build a yaw-only basis from the camera so the weapon follows the player's turn
	var head_yaw = cam.global_rotation.y
	var yaw_basis := Basis(Vector3.UP, head_yaw)
	weapon_rig.global_position = cam.global_position + yaw_basis * _p("get_sling_offset").call()
	# Orient weapon to face forward with the same handedness as the drawn single-hand basis
	var slot_y_rot: float = get_weapon_grip_rotation()
	var base_basis := yaw_basis * Basis(Vector3.UP, deg_to_rad(180.0 + slot_y_rot))
	var sling_rot: Vector3 = _p("get_sling_rot_offset").call()
	weapon_rig.global_basis = base_basis * Basis.from_euler(Vector3(
		deg_to_rad(sling_rot.x),
		deg_to_rad(sling_rot.y),
		deg_to_rad(sling_rot.z)))
	hide_arms_in_subtree(weapon_rig)


func sample_recoil_chain(weapon_rig: Node3D) -> Transform3D:
	var chain: Dictionary = ensure_weapon_cache(weapon_rig)["chain"]
	var composed := Transform3D.IDENTITY
	var chain_names: Array = _p("get_recoil_chain_names").call()
	for chain_name in chain_names:
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
	var ws_rest: Dictionary = _p("get_walk_sway_rest").call()
	var ws_nodes: Array = _p("get_walk_sway_nodes").call()
	if not _p("get_walk_sway_captured").call():
		ws_rest.clear()
		for node_name in ws_nodes:
			var n := walk_chain_node(weapon_rig, node_name)
			if n:
				ws_rest[node_name] = n.transform
				n.set_process(false)
				n.set_physics_process(false)
		_p("set_walk_sway_captured").call(true)
		_p("set_walk_sway_logged").call(false)
	for node_name in ws_nodes:
		if not ws_rest.has(node_name):
			continue
		var n := walk_chain_node(weapon_rig, node_name)
		if n:
			n.transform = ws_rest[node_name]
	# One-time diagnostic
	if not _p("get_walk_sway_logged").call():
		_p("set_walk_sway_logged").call(true)
		var log_path: String = _p("get_log_path").call()
		var f = FileAccess.open(log_path, FileAccess.READ_WRITE)
		if not f:
			f = FileAccess.open(log_path, FileAccess.WRITE)
		if f:
			f.seek_end(0)
			f.store_line("[walk_sway] captured rest poses:")
			for node_name in ws_nodes:
				if ws_rest.has(node_name):
					var t: Transform3D = ws_rest[node_name]
					f.store_line("  " + node_name + " origin=" + str(t.origin) + " basis_x=" + str(t.basis.x) + " basis_y=" + str(t.basis.y) + " basis_z=" + str(t.basis.z))
				else:
					f.store_line("  " + node_name + " NOT FOUND in chain")
			f.close()


func classify_weapon_is_long(weapon_rig: Node3D) -> bool:
	var weapon_slot: int = _p("get_weapon_slot").call()
	# Slots 3 (knife) and 4 (grenade) are never long weapons
	if weapon_slot == 3 or weapon_slot == 4:
		_log("Weapon class: short (slot " + str(weapon_slot) + ")")
		return false
	# Check weapon data resource for weaponType property (authoritative)
	var data_res = weapon_rig.get("data")
	if data_res and data_res is Resource:
		var weapon_type = data_res.get("weaponType")
		var subtype = data_res.get("subtype")
		_log("Weapon classify: name=" + weapon_rig.name + " slot=" + str(weapon_slot)
			+ " weaponType=" + str(weapon_type) + " subtype=" + str(subtype))
		if weapon_type != null:
			var wt: String = str(weapon_type).to_lower()
			if "pistol" in wt:
				_log("Weapon class: short (weaponType=" + str(weapon_type) + ")")
				return false
			# Any non-pistol firearm type is long
			_log("Weapon class: long (weaponType=" + str(weapon_type) + ")")
			return true
	# Fallback: slot 2 defaults to short, slot 1 defaults to long
	_log("Weapon classify: name=" + weapon_rig.name + " slot=" + str(weapon_slot) + " (no data resource)")
	if weapon_slot == 2:
		_log("Weapon class: short (sidearm slot, no weaponType)")
		return false
	_log("Weapon class: long (default for slot " + str(weapon_slot) + ")")
	return true


func get_weapon_subtype(weapon_rig: Node3D) -> String:
	var weapon_slot: int = _p("get_weapon_slot").call()
	if weapon_slot == 3:
		return "Melee"
	if weapon_slot == 4:
		return "Grenade"
	var data_res = weapon_rig.get("data")
	if data_res and data_res is Resource:
		var st = data_res.get("subtype")
		if st != null:
			return str(st)
	return ""


func update_pump_gesture(delta: float) -> void:
	_p("set_pump_cooldown").call(_p("get_pump_cooldown").call() - delta)
	var sup_ctrl = _p("get_controller").call(_p("get_support_hand").call())
	if not sup_ctrl:
		return
	var pos: Vector3 = sup_ctrl.position
	var pump_prev: Vector3 = _p("get_pump_prev_pos").call()
	# Initialize reference on first call or after reset
	if pump_prev == Vector3.ZERO:
		_p("set_pump_prev_pos").call(pos)
		return
	# PUMP_OUT: how far hand must move from reference to start the gesture.
	# PUMP_BACK: how close hand must return to the frozen reference to complete it.
	const PUMP_OUT := 0.04
	const PUMP_BACK := 0.03
	const TRACK_RATE := 2.0
	if not _p("get_pump_gesture_active").call():
		pump_prev = pump_prev.lerp(pos, delta * TRACK_RATE)
		_p("set_pump_prev_pos").call(pump_prev)
		if pos.distance_to(pump_prev) > PUMP_OUT:
			_p("set_pump_gesture_active").call(true)
			_p("set_pump_gesture_timer").call(1.2)
			_log("[VR Mod] PUMP: fwd phase dist=" + str(snappedf(pos.distance_to(pump_prev) * 100.0, 0.1)) + "cm")
	else:
		_p("set_pump_gesture_timer").call(_p("get_pump_gesture_timer").call() - delta)
		var dist: float = pos.distance_to(pump_prev)
		if dist < PUMP_BACK:
			if _p("get_pump_cooldown").call() <= 0.0:
				_p("inject_action").call("reload", true, 1.0)
				_p("inject_action").call("reload", false, 1.0)
				_log("[VR Mod] PUMP - shell cycled (R)")
				var dom_ctrl = _p("get_controller").call(_p("get_weapon_hand").call())
				if dom_ctrl:
					dom_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.12, 0.0)
				_p("set_pump_cooldown").call(0.5)
			_p("set_pump_gesture_active").call(false)
			_p("set_pump_prev_pos").call(pos)
		elif _p("get_pump_gesture_timer").call() <= 0.0:
			_log("[VR Mod] PUMP: timeout dist=" + str(snappedf(dist * 100.0, 0.1)) + "cm")
			_p("set_pump_gesture_active").call(false)
			_p("set_pump_prev_pos").call(pos)
