extends RefCounted

# input.gd
# Per-frame thumbstick + button-state polling. Handles movement (WASD inject),
# turning (snap/smooth), config-screen scroll, scope variable-zoom, decor-mode
# scroll/move/turn, grip-adjust mode thumbstick offsets, and the inventory
# scroll branch.
#
# Button press/release dispatch (_on_button_pressed / _on_button_released)
# stays on the autoload because Godot's XRController3D signals bind to
# autoload methods by name; restructuring those would require disconnecting
# and reconnecting hundreds of bind targets without changing behavior.

var autoload: Node


func _init(p_autoload: Node) -> void:
	autoload = p_autoload


func process(_frame: Dictionary, delta: float) -> void:
	process_input(delta)


func process_input(delta: float) -> void:
	if autoload._interface_open:
		# Release movement keys when in inventory
		autoload._inject_key(KEY_W, false)
		autoload._inject_key(KEY_S, false)
		autoload._inject_key(KEY_A, false)
		autoload._inject_key(KEY_D, false)
		# Right thumbstick Y = scroll in all menus/inventories
		if autoload.right_controller and autoload.right_controller.get_is_active():
			var stick = autoload.right_controller.get_vector2("primary")
			if abs(stick.y) > 0.5 and autoload._scroll_cooldown <= 0:
				autoload._inject_scroll(1 if stick.y > 0 else -1)
				autoload._scroll_cooldown = 0.15
		return

	# --- Grip adjust mode: thumbsticks control offsets ---
	if autoload._adjust_mode and autoload._weapon_slot > 0:
		var changed := false
		var offset: Vector3 = autoload._get_weapon_grip_offset()
		var rot: float = autoload._get_weapon_grip_rotation()
		if autoload.left_controller and autoload.left_controller.get_is_active():
			var left = autoload.left_controller.get_vector2("primary")
			if left.length() > autoload.thumbstick_deadzone:
				offset.x += left.x * autoload.ADJUST_SPEED * delta
				offset.y += left.y * autoload.ADJUST_SPEED * delta
				changed = true
		if autoload.right_controller and autoload.right_controller.get_is_active():
			var right = autoload.right_controller.get_vector2("primary")
			if right.length() > autoload.thumbstick_deadzone:
				offset.z += right.y * autoload.ADJUST_SPEED * delta
				rot += right.x * autoload.ADJUST_ROT_SPEED * delta
				changed = true
		if changed:
			autoload._set_weapon_grip_offset(offset)
			autoload._set_weapon_grip_rotation(rot)
			if autoload._verbose_log:
				autoload._log("[VR Mod] ADJUST " + autoload._current_weapon_name
					+ ": x=" + str(snapped(offset.x, 0.001))
					+ " y=" + str(snapped(offset.y, 0.001))
					+ " z=" + str(snapped(offset.z, 0.001))
					+ " rot=" + str(snapped(rot, 0.1)) + " deg")
		# Release movement keys and skip normal input
		autoload._inject_key(KEY_W, false)
		autoload._inject_key(KEY_S, false)
		autoload._inject_key(KEY_A, false)
		autoload._inject_key(KEY_D, false)
		return

	# --- Foregrip adjust mode: gun is frozen, support hand follows controller freely ---
	# Movement is suppressed; player physically positions their hand on the gun, then presses A.
	if autoload._fg_adjust_mode:
		autoload._inject_key(KEY_W, false)
		autoload._inject_key(KEY_S, false)
		autoload._inject_key(KEY_A, false)
		autoload._inject_key(KEY_D, false)
		return

	# --- Decor mode: right stick Y = scroll (distance/rotation), left stick = move, right stick X = turn ---
	if autoload._decor_mode:
		# Decor scroll cooldown is owned by the Decor subsystem and ticks via
		# its process(); we only consume + arm it here for the right-stick
		# scroll-tick gating.
		var _dec = autoload._ensure_decor()

		# Right thumbstick Y = scroll for distance or rotation
		if autoload.right_controller and autoload.right_controller.get_is_active():
			var stick = autoload.right_controller.get_vector2("primary")
			if abs(stick.y) > 0.5 and _dec.scroll_cooldown <= 0:
				autoload._inject_scroll(1 if stick.y > 0 else -1)
				_dec.scroll_cooldown = 0.15

		# Left thumbstick = movement (still works in decor mode)
		if autoload.left_controller and autoload.left_controller.get_is_active():
			var move = autoload.left_controller.get_vector2("primary")
			if move.length() > autoload.thumbstick_deadzone:
				var strength = (move.length() - autoload.thumbstick_deadzone) / (1.0 - autoload.thumbstick_deadzone)
				move = move.normalized() * strength
				if autoload.game_camera and is_instance_valid(autoload.game_camera) and autoload.xr_camera:
					var yaw_diff = autoload.xr_camera.global_rotation.y - autoload.game_camera.global_rotation.y
					move = move.rotated(yaw_diff)
				autoload._inject_key(KEY_W, move.y > 0.3)
				autoload._inject_key(KEY_S, move.y < -0.3)
				autoload._inject_key(KEY_A, move.x < -0.3)
				autoload._inject_key(KEY_D, move.x > 0.3)
				autoload._ensure_nvg().hold_vignette(0.15)
			else:
				autoload._inject_key(KEY_W, false)
				autoload._inject_key(KEY_S, false)
				autoload._inject_key(KEY_A, false)
				autoload._inject_key(KEY_D, false)

		# Right thumbstick X = snap/smooth turn (fall through to turn section)
		if autoload.right_controller and autoload.right_controller.get_is_active():
			var turn_input = autoload.right_controller.get_vector2("primary")
			if abs(turn_input.x) > autoload.thumbstick_deadzone:
				if autoload.use_snap_turn:
					if not autoload._snap_turn_cooldown and abs(turn_input.x) > 0.6:
						var angle = -autoload.snap_turn_degrees if turn_input.x > 0 else autoload.snap_turn_degrees
						autoload._turn_origin(angle)
						autoload._snap_turn_cooldown = true
						autoload._ensure_nvg().hold_vignette(0.3)
				else:
					autoload._turn_origin(-turn_input.x * autoload.smooth_turn_speed * delta)
					autoload._ensure_nvg().hold_vignette(0.15)
			else:
				autoload._snap_turn_cooldown = false
		return

	# --- Left thumbstick: Movement ---
	if autoload.left_controller and autoload.left_controller.get_is_active():
		var move_input = autoload.left_controller.get_vector2("primary")
		if move_input.length() > autoload.thumbstick_deadzone:
			var strength = (move_input.length() - autoload.thumbstick_deadzone) / (1.0 - autoload.thumbstick_deadzone)
			move_input = move_input.normalized() * strength

			if autoload.game_camera and is_instance_valid(autoload.game_camera):
				var ref_yaw = autoload.xr_camera.global_rotation.y if autoload.xr_camera else 0.0
				if autoload._move_direction_mode == "controller":
					var move_ctrl = autoload.right_controller if autoload._move_direction_hand == "right" else autoload.left_controller
					if move_ctrl and move_ctrl.get_is_active():
						ref_yaw = move_ctrl.global_rotation.y
				var yaw_diff = ref_yaw - autoload.game_camera.global_rotation.y
				move_input = move_input.rotated(yaw_diff)

			autoload._inject_key(KEY_W, move_input.y > 0.3)
			autoload._inject_key(KEY_S, move_input.y < -0.3)
			autoload._inject_key(KEY_A, move_input.x < -0.3)
			autoload._inject_key(KEY_D, move_input.x > 0.3)
			autoload._ensure_nvg().hold_vignette(0.15)
		else:
			autoload._inject_key(KEY_W, false)
			autoload._inject_key(KEY_S, false)
			autoload._inject_key(KEY_A, false)
			autoload._inject_key(KEY_D, false)

	# --- Right thumbstick: Turn / Config scroll ---
	if autoload.right_controller and autoload.right_controller.get_is_active():
		var turn_input = autoload.right_controller.get_vector2("primary")
		if autoload._rail_mode and abs(turn_input.y) > 0.5:
			# Rail mode: right stick Y = Ctrl+scroll to slide optic along rail
			if autoload._rail_scroll_cooldown <= 0.0:
				autoload._inject_key(KEY_CTRL, true)
				autoload._inject_scroll(1 if turn_input.y > 0 else -1)
				autoload._inject_key(KEY_CTRL, false)
				autoload._rail_scroll_cooldown = 0.15
				var ctrl = autoload._get_controller(autoload._config_dominant_hand)
				if ctrl:
					ctrl.trigger_haptic_pulse("haptic", 0.0, 0.15, 0.05, 0.0)
		elif autoload._config_screen_open:
			# Y axis scrolls the config panel
			if abs(turn_input.y) > autoload.thumbstick_deadzone:
				autoload._scroll_config_panel(-turn_input.y * 600.0 * delta)
			autoload._snap_turn_cooldown = false
		elif autoload._scope_zoom_branch_eligible() and abs(turn_input.y) > autoload.thumbstick_deadzone:
			# Variable zoom scope: directly change weapon rig zoomLevel
			if autoload._scroll_cooldown <= 0.0 and abs(turn_input.y) > 0.6:
				autoload._cycle_scope_zoom(1 if turn_input.y > 0 else -1)
				autoload._scroll_cooldown = 0.3
		else:
			if abs(turn_input.x) > autoload.thumbstick_deadzone:
				if autoload.use_snap_turn:
					if not autoload._snap_turn_cooldown and abs(turn_input.x) > 0.6:
						var angle = -autoload.snap_turn_degrees if turn_input.x > 0 else autoload.snap_turn_degrees
						autoload._turn_origin(angle)
						autoload._snap_turn_cooldown = true
						autoload._ensure_nvg().hold_vignette(0.3)
				else:
					autoload._turn_origin(-turn_input.x * autoload.smooth_turn_speed * delta)
					autoload._ensure_nvg().hold_vignette(0.15)
			else:
				autoload._snap_turn_cooldown = false
