extends RefCounted

# input.gd
# Per-frame thumbstick + button-state polling. Handles movement (WASD inject),
# turning (snap/smooth), config-screen scroll, scope variable-zoom, decor-mode
# scroll/move/turn, grip-adjust mode thumbstick offsets, and the inventory
# scroll branch.
#
# Button press/release dispatch (_on_button_pressed / _on_button_released)
# stays on the autoload because Godot's XRController3D signals bind to
# autoload methods by name.


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


func process(_frame: Dictionary, delta: float) -> void:
	process_input(delta)


func process_input(delta: float) -> void:
	var lc: XRController3D = _p("get_left_controller").call()
	var rc: XRController3D = _p("get_right_controller").call()
	var deadzone: float = _p("get_deadzone").call()
	var snap: bool = _p("get_use_snap_turn").call()
	var snap_deg: float = _p("get_snap_turn_degrees").call()
	var smooth_speed: float = _p("get_smooth_turn_speed").call()

	if _p("get_interface_open").call():
		# Release movement keys when in inventory
		_p("inject_key").call(KEY_W, false)
		_p("inject_key").call(KEY_S, false)
		_p("inject_key").call(KEY_A, false)
		_p("inject_key").call(KEY_D, false)
		# Right thumbstick Y = scroll in all menus/inventories
		if rc and rc.get_is_active():
			var stick = rc.get_vector2("primary")
			if abs(stick.y) > 0.5 and _p("get_scroll_cooldown").call() <= 0:
				_p("inject_scroll").call(1 if stick.y > 0 else -1)
				_p("set_scroll_cooldown").call(0.15)
		return

	# --- Grip adjust mode: thumbsticks control offsets ---
	if _p("get_adjust_mode").call() and _p("get_weapon_slot").call() > 0:
		var changed := false
		var offset: Vector3 = _p("get_weapon_grip_offset").call()
		var rot: float = _p("get_weapon_grip_rotation").call()
		var adjust_speed: float = _p("get_adjust_speed").call()
		var adjust_rot_speed: float = _p("get_adjust_rot_speed").call()
		if lc and lc.get_is_active():
			var left = lc.get_vector2("primary")
			if left.length() > deadzone:
				offset.x += left.x * adjust_speed * delta
				offset.y += left.y * adjust_speed * delta
				changed = true
		if rc and rc.get_is_active():
			var right = rc.get_vector2("primary")
			if right.length() > deadzone:
				offset.z += right.y * adjust_speed * delta
				rot += right.x * adjust_rot_speed * delta
				changed = true
		if changed:
			_p("set_weapon_grip_offset").call(offset)
			_p("set_weapon_grip_rotation").call(rot)
			if _p("get_verbose_log").call():
				_log("[VR Mod] ADJUST " + _p("get_current_weapon_name").call()
					+ ": x=" + str(snapped(offset.x, 0.001))
					+ " y=" + str(snapped(offset.y, 0.001))
					+ " z=" + str(snapped(offset.z, 0.001))
					+ " rot=" + str(snapped(rot, 0.1)) + " deg")
		# Release movement keys and skip normal input
		_p("inject_key").call(KEY_W, false)
		_p("inject_key").call(KEY_S, false)
		_p("inject_key").call(KEY_A, false)
		_p("inject_key").call(KEY_D, false)
		return

	# --- Foregrip adjust mode: gun is frozen, support hand follows controller freely ---
	if _p("get_fg_adjust_mode").call():
		_p("inject_key").call(KEY_W, false)
		_p("inject_key").call(KEY_S, false)
		_p("inject_key").call(KEY_A, false)
		_p("inject_key").call(KEY_D, false)
		return

	var nvg = _p("ensure_nvg").call()

	# --- Decor mode: right stick Y = scroll (distance/rotation), left stick = move, right stick X = turn ---
	if _p("get_decor_mode").call():
		var dec = _p("ensure_decor").call()

		# Right thumbstick Y = scroll for distance or rotation
		if rc and rc.get_is_active():
			var stick = rc.get_vector2("primary")
			if abs(stick.y) > 0.5 and dec.scroll_cooldown <= 0:
				_p("inject_scroll").call(1 if stick.y > 0 else -1)
				dec.scroll_cooldown = 0.15

		# Left thumbstick = movement (still works in decor mode)
		var gc = _p("get_game_camera").call()
		var cam = _p("get_camera").call()
		if lc and lc.get_is_active():
			var move = lc.get_vector2("primary")
			if move.length() > deadzone:
				var strength = (move.length() - deadzone) / (1.0 - deadzone)
				move = move.normalized() * strength
				if gc and is_instance_valid(gc) and cam:
					var yaw_diff = cam.global_rotation.y - gc.global_rotation.y
					move = move.rotated(yaw_diff)
				_p("inject_key").call(KEY_W, move.y > 0.3)
				_p("inject_key").call(KEY_S, move.y < -0.3)
				_p("inject_key").call(KEY_A, move.x < -0.3)
				_p("inject_key").call(KEY_D, move.x > 0.3)
				nvg.hold_vignette(0.15)
			else:
				_p("inject_key").call(KEY_W, false)
				_p("inject_key").call(KEY_S, false)
				_p("inject_key").call(KEY_A, false)
				_p("inject_key").call(KEY_D, false)

		# Right thumbstick X = snap/smooth turn (fall through to turn section)
		if rc and rc.get_is_active():
			var turn_input = rc.get_vector2("primary")
			if abs(turn_input.x) > deadzone:
				if snap:
					if not _p("get_snap_turn_cooldown").call() and abs(turn_input.x) > 0.6:
						var angle = -snap_deg if turn_input.x > 0 else snap_deg
						_p("turn_origin").call(angle)
						_p("set_snap_turn_cooldown").call(true)
						nvg.hold_vignette(0.3)
				else:
					_p("turn_origin").call(-turn_input.x * smooth_speed * delta)
					nvg.hold_vignette(0.15)
			else:
				_p("set_snap_turn_cooldown").call(false)
		return

	# --- Left thumbstick: Movement ---
	var gc2 = _p("get_game_camera").call()
	var cam2 = _p("get_camera").call()
	if lc and lc.get_is_active():
		var move_input = lc.get_vector2("primary")
		if move_input.length() > deadzone:
			var strength = (move_input.length() - deadzone) / (1.0 - deadzone)
			move_input = move_input.normalized() * strength

			if gc2 and is_instance_valid(gc2):
				var ref_yaw: float = cam2.global_rotation.y if cam2 else 0.0
				if _p("get_move_direction_mode").call() == "controller":
					var move_ctrl = rc if _p("get_move_direction_hand").call() == "right" else lc
					if move_ctrl and move_ctrl.get_is_active():
						ref_yaw = move_ctrl.global_rotation.y
				var yaw_diff = ref_yaw - gc2.global_rotation.y
				move_input = move_input.rotated(yaw_diff)

			_p("inject_key").call(KEY_W, move_input.y > 0.3)
			_p("inject_key").call(KEY_S, move_input.y < -0.3)
			_p("inject_key").call(KEY_A, move_input.x < -0.3)
			_p("inject_key").call(KEY_D, move_input.x > 0.3)
			nvg.hold_vignette(0.15)
		else:
			_p("inject_key").call(KEY_W, false)
			_p("inject_key").call(KEY_S, false)
			_p("inject_key").call(KEY_A, false)
			_p("inject_key").call(KEY_D, false)

	# --- Right thumbstick: Turn / Config scroll ---
	if rc and rc.get_is_active():
		var turn_input = rc.get_vector2("primary")
		if _p("get_rail_mode").call() and abs(turn_input.y) > 0.5:
			# Rail mode: right stick Y = Ctrl+scroll to slide optic along rail
			if _p("get_rail_scroll_cooldown").call() <= 0.0:
				_p("inject_key").call(KEY_CTRL, true)
				_p("inject_scroll").call(1 if turn_input.y > 0 else -1)
				_p("inject_key").call(KEY_CTRL, false)
				_p("set_rail_scroll_cooldown").call(0.15)
				var ctrl = _p("get_controller").call(_p("get_dominant_hand").call())
				if ctrl:
					ctrl.trigger_haptic_pulse("haptic", 0.0, 0.15, 0.05, 0.0)
		elif _p("get_config_screen_open").call():
			# Y axis scrolls the config panel
			if abs(turn_input.y) > deadzone:
				_p("scroll_config_panel").call(-turn_input.y * 600.0 * delta)
			_p("set_snap_turn_cooldown").call(false)
		elif _p("scope_zoom_branch_eligible").call() and abs(turn_input.y) > deadzone:
			# Variable zoom scope: directly change weapon rig zoomLevel
			if _p("get_scroll_cooldown").call() <= 0.0 and abs(turn_input.y) > 0.6:
				_p("cycle_scope_zoom").call(1 if turn_input.y > 0 else -1)
				_p("set_scroll_cooldown").call(0.3)
		else:
			if abs(turn_input.x) > deadzone:
				if snap:
					if not _p("get_snap_turn_cooldown").call() and abs(turn_input.x) > 0.6:
						var angle = -snap_deg if turn_input.x > 0 else snap_deg
						_p("turn_origin").call(angle)
						_p("set_snap_turn_cooldown").call(true)
						nvg.hold_vignette(0.3)
				else:
					_p("turn_origin").call(-turn_input.x * smooth_speed * delta)
					nvg.hold_vignette(0.15)
			else:
				_p("set_snap_turn_cooldown").call(false)
