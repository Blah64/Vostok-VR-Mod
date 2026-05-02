extends RefCounted

# decor.gd
# Shelter furniture placement mode. Long-press X (left, UNARMED/LOWERED) to
# enter; toggles game's flat-screen decor mode via KEY_F1 and steers the game
# camera to match the dominant-hand controller aim so the furniture ghost
# tracks where the player points.

var autoload: Node

# Subsystem-owned state. _decor_mode itself stays on the autoload because too
# many call sites (input handler, weapon sync gate, hand visibility, xr_rig
# steering, diagnostics) read it as a global mode flag. The interaction
# specifics — the long-press X timer that resolves to "enter decor" vs
# "flashlight toggle", and the scroll cooldown/mode for adjusting distance
# vs rotation — are decor-internal and live here.
var x_pending: bool = false
var x_press_time: float = 0.0
var scroll_cooldown: float = 0.0
var scroll_mode: int = 0  # 0 = distance, 1 = rotation


func _init(p_autoload: Node) -> void:
	autoload = p_autoload


func process(_frame: Dictionary, delta: float) -> void:
	# Resolve the X-button long-press into either decor entry or flashlight
	# toggle. Originally this lived in the autoload _process body alongside
	# rail-mode long-press; pulling it onto the module means the autoload
	# loop no longer owns decor-specific timing.
	if x_pending:
		var elapsed: float = Time.get_ticks_msec() / 1000.0 - x_press_time
		if elapsed >= autoload.DECOR_MODE_LONG_PRESS_SEC:
			x_pending = false
			if autoload._holster_state in [autoload.HolsterState.UNARMED, autoload.HolsterState.LOWERED] and not autoload._interface_open and not is_decor_placing():
				toggle_decor_mode()
				if autoload.left_controller:
					autoload.left_controller.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.25, 0.0)
	# Decor scroll cooldown ticks regardless of mode so re-entry into decor
	# starts with a clean slate. delta-driven so frame-rate independent.
	if scroll_cooldown > 0:
		scroll_cooldown = maxf(0.0, scroll_cooldown - delta)


func is_decor_placing() -> bool:
	# Check if a furniture ghost preview is active (item selected for placement).
	# The game creates a "Hint" MeshInstance3D under /root/Map/ when placing.
	var map_node = autoload.get_tree().root.get_node_or_null("Map")
	if not map_node:
		return false
	var hint = map_node.get_node_or_null("Hint")
	return hint != null and hint is MeshInstance3D and hint.visible


func toggle_decor_mode() -> void:
	autoload._decor_mode = not autoload._decor_mode
	autoload._inject_key(KEY_F1, true)
	autoload._inject_key(KEY_F1, false)
	if autoload._decor_mode:
		scroll_mode = 0
		scroll_cooldown = 0.0
		# Ensure Placer starts in distance mode
		if autoload.game_camera:
			var placer = autoload.game_camera.get_node_or_null("Placer")
			if placer:
				placer.set("rotateMode", false)
		autoload._log("[VR Mod] === DECOR MODE ON ===")
		if autoload.left_controller:
			autoload.left_controller.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.2, 0.0)
		if autoload.right_controller:
			autoload.right_controller.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.2, 0.0)
	else:
		# Reset Placer to distance mode on exit
		if autoload.game_camera:
			var placer = autoload.game_camera.get_node_or_null("Placer")
			if placer:
				placer.set("rotateMode", false)
		autoload._log("[VR Mod] === DECOR MODE OFF ===")
		if autoload.left_controller:
			autoload.left_controller.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.15, 0.0)
		if autoload.right_controller:
			autoload.right_controller.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.15, 0.0)


func steer_decor_camera_to_controller() -> void:
	# In decor mode, steer game camera to match dominant hand controller aim.
	# The game uses game camera direction for furniture placement, so this makes
	# the furniture ghost follow where the player points the controller.
	var ctrl = autoload._get_controller(autoload._config_dominant_hand)
	if not ctrl or not ctrl.get_is_active():
		return
	if not autoload.game_camera or not is_instance_valid(autoload.game_camera):
		return

	var aim_forward = -ctrl.global_basis.z
	# Deadzone: if controller aim has not moved this frame, skip the trig + injection.
	if (aim_forward - autoload._steer_decor_last_aim).length_squared() < autoload._STEER_AIM_DEADZONE_SQ:
		return
	autoload._steer_decor_last_aim = aim_forward
	var target_yaw = atan2(-aim_forward.x, -aim_forward.z)
	var target_pitch = asin(clampf(aim_forward.y, -1.0, 1.0))

	var game_yaw = autoload.game_camera.global_rotation.y
	var game_pitch = autoload.game_camera.global_rotation.x

	var yaw_error = fmod(target_yaw - game_yaw + PI, TAU) - PI
	var pitch_error = target_pitch - game_pitch

	if abs(yaw_error) < deg_to_rad(0.3) and abs(pitch_error) < deg_to_rad(0.3):
		return

	var correction_strength := 0.6

	var mouse_dx = -(yaw_error * correction_strength) / autoload._mouse_sens_estimate
	var mouse_dy = -(pitch_error * correction_strength) / autoload._mouse_sens_estimate

	var event = InputEventMouseMotion.new()
	event.relative = Vector2(mouse_dx, mouse_dy)
	event.position = autoload.get_viewport().get_visible_rect().size / 2
	Input.parse_input_event(event)
