extends RefCounted

# decor.gd
# Shelter furniture placement mode. Long-press X (left, UNARMED/LOWERED) to
# enter; toggles game's flat-screen decor mode via KEY_F1 and steers the game
# camera to match the dominant-hand controller aim so the furniture ghost
# tracks where the player points.
#
# Subsystem-owned state. _decor_mode itself stays on the autoload because too
# many call sites (input handler, weapon sync gate, hand visibility, xr_rig
# steering, diagnostics) read it as a global mode flag; this module reads/
# writes it via explicit Callable ports rather than back-reference.
#
# Port contract:
#   tree                       : SceneTree         (used to walk the scene tree for hint detection)
#   get_camera                 : Callable() -> XRCamera3D
#   get_game_camera            : Callable() -> Camera3D
#   get_left_controller        : Callable() -> XRController3D
#   get_right_controller       : Callable() -> XRController3D
#   get_controller             : Callable(hand) -> XRController3D
#   get_dominant_hand          : Callable() -> String
#   get_holster_state          : Callable() -> int
#   get_holster_unarmed        : Callable() -> int   (HolsterState.UNARMED enum value)
#   get_holster_lowered        : Callable() -> int   (HolsterState.LOWERED enum value)
#   get_interface_open         : Callable() -> bool
#   get_decor_mode             : Callable() -> bool
#   set_decor_mode             : Callable(value) -> void
#   inject_key                 : Callable(keycode, pressed) -> void
#   get_long_press_sec         : Callable() -> float (DECOR_MODE_LONG_PRESS_SEC)
#   get_aim_deadzone_sq        : Callable() -> float (_STEER_AIM_DEADZONE_SQ)
#   get_steer_last_aim         : Callable() -> Vector3
#   set_steer_last_aim         : Callable(value) -> void
#   get_mouse_sens             : Callable() -> float
#   get_viewport               : Callable() -> Viewport
#   log                        : Callable(msg) -> void

# Subsystem-owned state.
var x_pending: bool = false
var x_press_time: float = 0.0
var scroll_cooldown: float = 0.0
var scroll_mode: int = 0  # 0 = distance, 1 = rotation


# Ports
var _tree: SceneTree
var _get_camera: Callable
var _get_game_camera: Callable
var _get_left_controller: Callable
var _get_right_controller: Callable
var _get_controller: Callable
var _get_dominant_hand: Callable
var _get_holster_state: Callable
var _get_holster_unarmed: Callable
var _get_holster_lowered: Callable
var _get_interface_open: Callable
var _get_decor_mode: Callable
var _set_decor_mode: Callable
var _inject_key: Callable
var _get_long_press_sec: Callable
var _get_aim_deadzone_sq: Callable
var _get_steer_last_aim: Callable
var _set_steer_last_aim: Callable
var _get_mouse_sens: Callable
var _get_viewport: Callable
var _log_fn: Callable


func _init(tree: SceneTree, ports: Dictionary) -> void:
	_tree = tree
	_get_camera = ports["get_camera"]
	_get_game_camera = ports["get_game_camera"]
	_get_left_controller = ports["get_left_controller"]
	_get_right_controller = ports["get_right_controller"]
	_get_controller = ports["get_controller"]
	_get_dominant_hand = ports["get_dominant_hand"]
	_get_holster_state = ports["get_holster_state"]
	_get_holster_unarmed = ports["get_holster_unarmed"]
	_get_holster_lowered = ports["get_holster_lowered"]
	_get_interface_open = ports["get_interface_open"]
	_get_decor_mode = ports["get_decor_mode"]
	_set_decor_mode = ports["set_decor_mode"]
	_inject_key = ports["inject_key"]
	_get_long_press_sec = ports["get_long_press_sec"]
	_get_aim_deadzone_sq = ports["get_aim_deadzone_sq"]
	_get_steer_last_aim = ports["get_steer_last_aim"]
	_set_steer_last_aim = ports["set_steer_last_aim"]
	_get_mouse_sens = ports["get_mouse_sens"]
	_get_viewport = ports["get_viewport"]
	_log_fn = ports.get("log", Callable())


func _log(msg: String) -> void:
	if _log_fn.is_valid():
		_log_fn.call(msg)


func process(_frame: Dictionary, delta: float) -> void:
	# Resolve the X-button long-press into either decor entry or flashlight
	# toggle. Originally this lived in the autoload _process body alongside
	# rail-mode long-press; pulling it onto the module means the autoload
	# loop no longer owns decor-specific timing.
	if x_pending:
		var elapsed: float = Time.get_ticks_msec() / 1000.0 - x_press_time
		if elapsed >= _get_long_press_sec.call():
			x_pending = false
			var hs: int = _get_holster_state.call()
			var unarmed: int = _get_holster_unarmed.call()
			var lowered: int = _get_holster_lowered.call()
			if (hs == unarmed or hs == lowered) and not _get_interface_open.call() and not is_decor_placing():
				toggle_decor_mode()
				var lc = _get_left_controller.call()
				if lc:
					lc.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.25, 0.0)
	# Decor scroll cooldown ticks regardless of mode so re-entry into decor
	# starts with a clean slate. delta-driven so frame-rate independent.
	if scroll_cooldown > 0:
		scroll_cooldown = maxf(0.0, scroll_cooldown - delta)


func is_decor_placing() -> bool:
	# Check if a furniture ghost preview is active (item selected for placement).
	# The game creates a "Hint" MeshInstance3D under /root/Map/ when placing.
	var map_node = _tree.root.get_node_or_null("Map")
	if not map_node:
		return false
	var hint = map_node.get_node_or_null("Hint")
	return hint != null and hint is MeshInstance3D and hint.visible


func toggle_decor_mode() -> void:
	var new_state: bool = not _get_decor_mode.call()
	_set_decor_mode.call(new_state)
	_inject_key.call(KEY_F1, true)
	_inject_key.call(KEY_F1, false)
	var gc = _get_game_camera.call()
	if new_state:
		scroll_mode = 0
		scroll_cooldown = 0.0
		# Ensure Placer starts in distance mode
		if gc:
			var placer = gc.get_node_or_null("Placer")
			if placer:
				placer.set("rotateMode", false)
		_log("[VR Mod] === DECOR MODE ON ===")
		var lc = _get_left_controller.call()
		if lc:
			lc.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.2, 0.0)
		var rc = _get_right_controller.call()
		if rc:
			rc.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.2, 0.0)
	else:
		# Reset Placer to distance mode on exit
		if gc:
			var placer = gc.get_node_or_null("Placer")
			if placer:
				placer.set("rotateMode", false)
		_log("[VR Mod] === DECOR MODE OFF ===")
		var lc2 = _get_left_controller.call()
		if lc2:
			lc2.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.15, 0.0)
		var rc2 = _get_right_controller.call()
		if rc2:
			rc2.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.15, 0.0)


func steer_decor_camera_to_controller() -> void:
	# In decor mode, steer game camera to match dominant hand controller aim.
	# The game uses game camera direction for furniture placement, so this makes
	# the furniture ghost follow where the player points the controller.
	var ctrl = _get_controller.call(_get_dominant_hand.call())
	if not ctrl or not ctrl.get_is_active():
		return
	var gc = _get_game_camera.call()
	if not gc or not is_instance_valid(gc):
		return

	var aim_forward = -ctrl.global_basis.z
	# Deadzone: if controller aim has not moved this frame, skip the trig + injection.
	var last_aim: Vector3 = _get_steer_last_aim.call()
	if (aim_forward - last_aim).length_squared() < _get_aim_deadzone_sq.call():
		return
	_set_steer_last_aim.call(aim_forward)
	var target_yaw = atan2(-aim_forward.x, -aim_forward.z)
	var target_pitch = asin(clampf(aim_forward.y, -1.0, 1.0))

	var game_yaw = gc.global_rotation.y
	var game_pitch = gc.global_rotation.x

	var yaw_error = fmod(target_yaw - game_yaw + PI, TAU) - PI
	var pitch_error = target_pitch - game_pitch

	if abs(yaw_error) < deg_to_rad(0.3) and abs(pitch_error) < deg_to_rad(0.3):
		return

	var correction_strength := 0.6
	var sens: float = _get_mouse_sens.call()

	var mouse_dx = -(yaw_error * correction_strength) / sens
	var mouse_dy = -(pitch_error * correction_strength) / sens

	var event = InputEventMouseMotion.new()
	event.relative = Vector2(mouse_dx, mouse_dy)
	var vp = _get_viewport.call()
	event.position = vp.get_visible_rect().size / 2
	Input.parse_input_event(event)
