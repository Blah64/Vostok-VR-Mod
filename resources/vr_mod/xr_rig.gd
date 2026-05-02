extends RefCounted

# xr_rig.gd
# Origin/camera/controller install, recenter, per-frame origin/camera sync,
# snap/smooth turn rotation, mouse steering of the game camera (so bullets
# land where the controller points), physical-crouch detection, and the
# game-camera search.
#
# This module reaches the autoload only through explicit Callable ports.
# Origin/camera/controller refs themselves stay on the autoload because many
# other systems read them by name.


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
	# Per-frame rig work owned by xr_rig:
	#  * camera-lost polling (level transition / main-menu fallback)
	#  * weapon-reparent retry (game weapons load late after camera)
	#  * physical-crouch detection (standing-mode duck under cover)
	#  * standing-mode resnap + physical-crouch release resnap timers
	#  * origin->game-camera position sync (and steer-via-mouse for aim)
	#  * auto-recenter when HMD drifts > AUTO_RECENTER_DIST_M from character
	var origin = _p("get_origin").call()
	if not origin or not is_instance_valid(origin):
		return
	_poll_camera_lost()
	_retry_weapon_reparent()
	update_physical_crouch()
	_tick_standing_mode_resnap()
	_tick_physical_crouch_resnap()
	var gc = _p("get_game_camera").call()
	if gc and is_instance_valid(gc):
		if gc.environment != null:
			gc.environment = null
		if gc.attributes != null:
			gc.attributes = null
	sync_origin_to_game()
	_tick_auto_recenter(delta)


func _poll_camera_lost() -> void:
	var gc = _p("get_game_camera").call()
	if gc and is_instance_valid(gc):
		return
	# Camera lost or freed (level transition). Poll for new one.
	var lost: int = _p("get_camera_lost_frames").call() + 1
	_p("set_camera_lost_frames").call(lost)
	if _p("get_frames_waited").call() % _p("get_camera_poll_interval").call() == 0:
		if gc:
			_log("[VR Mod] Game camera lost (level transition?) — searching...")
		var new_gc = find_game_camera(_tree.root)
		_p("set_game_camera").call(new_gc)
		if new_gc:
			attach_rig_to_camera()
			_p("on_level_transition").call()
			_p("set_camera_lost_frames").call(0)
			_log("[VR Mod] Camera found again")
	# After ~2 seconds without a camera, enter main menu mode (once)
	elif lost > 120 and not _p("get_in_menu_mode").call():
		_p("on_main_menu_entered").call()


func _retry_weapon_reparent() -> void:
	# Weapon nodes load late — retry once a second until the reparent succeeds.
	if not _p("get_weapons_reparented").call() and _p("get_frames_waited").call() % 60 == 0:
		reparent_camera_children()


func _tick_standing_mode_resnap() -> void:
	# Re-snap origin a few frames after tracking mode switch (reference space settles).
	var n: int = _p("get_standing_mode_resnap").call()
	if n <= 0:
		return
	n -= 1
	_p("set_standing_mode_resnap").call(n)
	if n == 0:
		attach_rig_to_camera()
		_log("[VR Mod] Origin re-snapped after tracking mode change")
		var cam = _p("get_camera").call()
		if _p("get_standing_mode").call() and cam:
			var h: float = cam.position.y
			if h < 0.3:
				h = 1.6
			_p("set_standing_height_ref").call(h)
			_log("[VR Mod] Standing height reference: " + str(h) + "m")


func _tick_physical_crouch_resnap() -> void:
	var n: int = _p("get_physical_crouch_resnap").call()
	if n <= 0:
		return
	n -= 1
	_p("set_physical_crouch_resnap").call(n)
	if n == 0:
		attach_rig_to_camera()
		var cam = _p("get_camera").call()
		if _p("get_standing_mode").call() and cam:
			var h: float = cam.position.y
			if h < 0.3:
				h = 1.6
			_p("set_standing_height_ref").call(h)
		_log("[VR Mod] Origin re-snapped after physical crouch release")


func _tick_auto_recenter(delta: float) -> void:
	# Auto-recenter: snap origin back to camera if HMD drifts > AUTO_RECENTER_DIST_M
	# in XZ. Suppressed in any UI / decor mode so the player isn't yanked while
	# pointing at menus or placing furniture.
	var cooldown: float = _p("get_auto_recenter_cooldown").call()
	if cooldown > 0.0:
		_p("set_auto_recenter_cooldown").call(cooldown - delta)
		return
	if not _p("get_auto_recenter_enabled").call() or _p("get_interface_open").call() \
			or _p("get_config_screen_open").call() or _p("get_decor_mode").call():
		return
	var gc = _p("get_game_camera").call()
	var cam = _p("get_camera").call()
	if not gc or not is_instance_valid(gc) or not cam:
		return
	var hmd = cam.global_position
	var cam_pos = gc.global_position
	if Vector2(hmd.x - cam_pos.x, hmd.z - cam_pos.z).length() > _p("get_auto_recenter_dist").call():
		attach_rig_to_camera()


func install_xr_rig() -> void:
	_log("[VR Mod] Installing XR rig...")

	# xr_origin and xr_camera were created in _ready() for early HMD output.
	var origin = _p("get_origin").call()
	var cam = _p("get_camera").call()
	var iface = _p("get_xr_interface").call()
	origin.world_scale = _p("get_world_scale").call()
	iface.render_target_size_multiplier = _p("get_render_scale").call()

	var lc := XRController3D.new()
	lc.name = "LeftHand"
	lc.tracker = "left_hand"
	origin.add_child(lc)
	_p("set_left_controller").call(lc)

	var rc := XRController3D.new()
	rc.name = "RightHand"
	rc.tracker = "right_hand"
	origin.add_child(rc)
	_p("set_right_controller").call(rc)

	var on_pressed: Callable = _p("get_on_button_pressed").call()
	var on_released: Callable = _p("get_on_button_released").call()
	lc.button_pressed.connect(on_pressed.bind("left"))
	lc.button_released.connect(on_released.bind("left"))
	rc.button_pressed.connect(on_pressed.bind("right"))
	rc.button_released.connect(on_released.bind("right"))

	# Extract hand GLTF assets from Metro's VMZ cache to user:// so GLTFDocument
	# can read them (res://resources/hands/ is not mounted into Godot's VFS).
	if _p("extract_hand_assets_from_vmz").call():
		_p("set_assets_base").call("user://vr_mod/hands/")
	else:
		_p("append_hand_load_error").call("hand: VMZ extraction failed - hands will use box fallback")

	# Create simple controller hand models (visible when no weapon equipped)
	_log("[VR Mod] Creating hand models...")
	_p("create_hand_model").call(lc, "LeftHandModel")
	_p("create_hand_model").call(rc, "RightHandModel")

	# Grab raycasts on both controllers - short range for picking up items / holster detection
	for ctrl in [lc, rc]:
		var ray = RayCast3D.new()
		ray.name = "GrabRay"
		ray.target_position = Vector3(0, 0, -1.0)  # 1m forward from controller
		ray.enabled = true
		ray.collide_with_areas = true
		ray.collide_with_bodies = true
		ray.collision_mask = 0xFFFFF  # All 20 layers
		ctrl.add_child(ray)
	_p("set_grab_ray_left").call(lc.get_node("GrabRay"))
	_p("set_grab_ray_right").call(rc.get_node("GrabRay"))
	_log("[VR Mod] Grab raycasts added to both controllers")

	# xr_origin is already parented to autoload (done in _ready()).
	var gc = _p("get_game_camera").call()
	if gc and is_instance_valid(gc):
		# Use the actual tracked head height instead of a hardcoded constant.
		var actual_head_height: float = cam.position.y
		if actual_head_height < 0.3:
			actual_head_height = 1.6  # fallback: tracking not yet settled
			_log("[VR Mod] Head tracking not ready, using fallback 1.6m")
		else:
			_log("[VR Mod] Tracked head height: " + str(actual_head_height) + "m")
		var cam_pos = gc.global_position
		origin.global_position = Vector3(cam_pos.x, cam_pos.y - actual_head_height, cam_pos.z)
		origin.global_rotation = Vector3.ZERO
		_p("set_last_game_cam_pos").call(cam_pos)
		if _p("get_standing_mode").call():
			_p("set_standing_height_ref").call(actual_head_height)

		# Copy game camera's cull mask to XR camera so we can see
		# weapon viewmodels rendered on special visual layers
		cam.cull_mask = gc.cull_mask
		_log("[VR Mod] XR rig placed: origin=" + str(origin.global_position))
		_log("[VR Mod] Copied cull_mask from game_camera: " + str(gc.cull_mask))
	else:
		origin.global_position = Vector3.ZERO
		_p("set_last_game_cam_pos").call(Vector3(0, 1.7, 0))
		_p("set_in_menu_mode").call(true)  # No game camera - show menu panel once HUD is set up

	cam.current = true
	_p("get_main_viewport").call().use_xr = true

	var loader = _tree.root.get_node_or_null("Loader")
	if loader:
		loader.visible = false
		_log("[VR Mod] Hid Loader CanvasLayer")

	_p("reparent_camera_children").call()

	# Gameplay needs captured cursor for fire input; main menu needs visible cursor.
	if _p("get_in_menu_mode").call():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Ensure user data directory and default config exist
	DirAccess.make_dir_recursive_absolute("user://vr_mod")
	if not FileAccess.file_exists(_p("get_config_path").call()):
		_p("save_full_config").call()

	# Reset debug log - MUST stay here; hand creation above logs to the old file,
	# those messages are erased. _hand_load_errors buffers them across this reset.
	var dump_path: String = _p("get_log_path").call()
	var f = FileAccess.open(dump_path, FileAccess.WRITE)
	if f:
		f.store_line("=== VR Mod Debug Log ===")
		f.store_line("Session start: " + str(Time.get_ticks_msec()) + "ms")
		f.store_line("")
		f.store_line("=== InputMap Bindings for Fire-Related Actions ===")
		var fire_actions = ["fire", "left_mouse", "aim", "interact", "primary", "secondary"]
		for action_name in fire_actions:
			if InputMap.has_action(action_name):
				var events = InputMap.action_get_events(action_name)
				f.store_line(action_name + " (" + str(events.size()) + " bindings):")
				for ev in events:
					var ev_info = "  " + ev.get_class()
					if ev is InputEventKey:
						ev_info += " keycode=" + str(ev.keycode) + " phys=" + str(ev.physical_keycode)
					elif ev is InputEventMouseButton:
						ev_info += " button=" + str(ev.button_index)
					elif ev is InputEventJoypadButton:
						ev_info += " joy_button=" + str(ev.button_index)
					elif ev is InputEventJoypadMotion:
						ev_info += " joy_axis=" + str(ev.axis)
					f.store_line(ev_info)
			else:
				f.store_line(action_name + " (NOT FOUND)")
		f.close()
		_log("[VR Mod] Debug log reset: " + dump_path)

	# Flush buffered hand load messages (written before the reset above)
	_p("flush_hand_load_errors").call()

	# Create laser pointer mesh (hidden by default)
	var laser := MeshInstance3D.new()
	laser.name = "LaserPointer"
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.002
	cylinder.bottom_radius = 0.002
	cylinder.height = 5.0
	laser.mesh = cylinder
	var laser_mat = StandardMaterial3D.new()
	laser_mat.albedo_color = Color(0.2, 0.5, 1.0, 0.5)
	laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser_mat.no_depth_test = true
	laser_mat.render_priority = 20  # Render on top of HUD quad (priority 10)
	laser.material_override = laser_mat
	laser.visible = false
	# Cylinder is centered at origin along Y axis. We need it along -Z.
	laser.rotation.x = deg_to_rad(90)
	laser.position.z = -cylinder.height / 2.0

	var pointer_controller = _p("get_controller").call(_p("get_dominant_hand").call())
	pointer_controller.add_child(laser)
	_p("set_laser_mesh").call(laser)

	# Floating hover label - shows item/interactable name when laser aims at it
	var hover := Label3D.new()
	hover.name = "HoverLabel"
	hover.font_size = 48
	hover.pixel_size = 0.001
	hover.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hover.no_depth_test = true
	hover.render_priority = 10
	hover.outline_size = 6
	hover.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	hover.modulate = Color(1.0, 1.0, 1.0, 1.0)
	hover.visible = false
	_p("get_owner_node").call().add_child(hover)
	_p("set_hover_label").call(hover)

	_p("setup_comfort_vignette").call()
	_p("create_holster_holos").call()

	_log("[VR Mod] === VR rig active ===")


func attach_rig_to_camera() -> void:
	var gc = _p("get_game_camera").call()
	var origin = _p("get_origin").call()
	var cam = _p("get_camera").call()
	if not gc or not origin or not cam:
		return
	var cam_pos = gc.global_position
	# Place origin so HMD lands exactly at cam_pos.
	var head_local = cam.position
	if head_local.y < 0.3:
		head_local.y = 1.6
	origin.global_position = cam_pos - origin.global_basis * head_local
	_p("set_last_game_cam_pos").call(cam_pos)
	_p("set_auto_recenter_cooldown").call(3.0)
	cam.cull_mask = gc.cull_mask
	_p("set_in_menu_mode").call(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var reminder = _p("get_config_reminder_label").call()
	if reminder and is_instance_valid(reminder):
		reminder.visible = false
	_log("[VR Mod] Rig recentered to camera at " + str(cam_pos))


func sync_origin_to_game() -> void:
	var gc = _p("get_game_camera").call()
	var origin = _p("get_origin").call()
	if gc and is_instance_valid(gc) and origin:
		var current_pos = gc.global_position
		var last: Vector3 = _p("get_last_game_cam_pos").call()
		var delta_pos = current_pos - last
		if delta_pos.length() > 0.001:
			# Freeze Y while physically crouched
			if _p("get_physical_crouch_active").call() or _p("get_physical_crouch_resnap").call() > 0:
				delta_pos.y = 0.0
			origin.global_position += delta_pos
			_p("set_last_game_cam_pos").call(current_pos)

		# Steer game camera toward controller aim via mouse injection
		if not _p("get_interface_open").call():
			if _p("get_decor_mode").call():
				_p("steer_decor_camera_to_controller").call()
			else:
				steer_game_camera_via_mouse()


func steer_game_camera_via_mouse() -> void:
	# Steer game camera to match weapon barrel aim direction.
	var hs: int = _p("get_holster_state").call()
	var aim_hand: String
	if hs == _p("get_state_lowered").call() or hs == _p("get_state_sling").call():
		aim_hand = _p("get_dominant_hand").call()
	else:
		aim_hand = _p("get_weapon_hand").call()
	var aim_controller = _p("get_controller").call(aim_hand)
	if not aim_controller or not aim_controller.get_is_active():
		_p("set_sens_cal_pending").call(false)
		return

	# Compute barrel direction
	var aim_forward: Vector3

	if _p("get_support_grip_held").call():
		var off_controller = _p("get_controller").call(_p("get_support_hand").call())
		if off_controller and off_controller.get_is_active():
			var hand_dist = aim_controller.global_position.distance_to(off_controller.global_position)
			if hand_dist > _p("get_two_hand_min_dist").call():
				aim_forward = (off_controller.global_position - aim_controller.global_position).normalized()
			else:
				aim_forward = -aim_controller.global_basis.z
		else:
			aim_forward = -aim_controller.global_basis.z
	else:
		# Use raw controller forward for steering
		aim_forward = -aim_controller.global_basis.z
	# Aim deadzone
	var have_target: bool = _p("get_steer_have_target").call()
	var last_aim: Vector3 = _p("get_steer_last_aim").call()
	var deadzone_sq: float = _p("get_aim_deadzone_sq").call()
	var aim_unchanged = have_target and (aim_forward - last_aim).length_squared() < deadzone_sq
	var target_yaw: float
	var target_pitch: float
	if aim_unchanged:
		target_yaw = _p("get_steer_last_target_yaw").call()
		target_pitch = _p("get_steer_last_target_pitch").call()
	else:
		target_yaw = atan2(-aim_forward.x, -aim_forward.z)
		target_pitch = asin(clampf(aim_forward.y, -1.0, 1.0))
		_p("set_steer_last_aim").call(aim_forward)
		_p("set_steer_last_target_yaw").call(target_yaw)
		_p("set_steer_last_target_pitch").call(target_pitch)
		_p("set_steer_have_target").call(true)

	# Calibration disabled
	_p("set_sens_cal_pending").call(false)

	# Mouse injection
	var gc = _p("get_game_camera").call()
	if not aim_unchanged:
		var game_yaw = gc.global_rotation.y
		var game_pitch = gc.global_rotation.x
		var yaw_error = fmod(target_yaw - game_yaw + PI, TAU) - PI
		var pitch_error = target_pitch - game_pitch
		if abs(yaw_error) >= deg_to_rad(0.3) or abs(pitch_error) >= deg_to_rad(0.3):
			var correction_strength := 0.6
			var sens: float = _p("get_mouse_sens").call()
			var mouse_dx = -(yaw_error * correction_strength) / sens
			var mouse_dy = -(pitch_error * correction_strength) / sens
			var event = InputEventMouseMotion.new()
			event.relative = Vector2(mouse_dx, mouse_dy)
			event.position = _p("get_main_viewport").call().get_visible_rect().size / 2
			Input.parse_input_event(event)

	# Direct rotation override when weapon is drawn
	if hs == _p("get_state_drawn").call() and _p("get_weapon_loaded").call() and is_finite(target_yaw) and is_finite(target_pitch):
		gc.global_rotation = Vector3(target_pitch, target_yaw, 0.0)


func turn_origin(angle_deg: float) -> void:
	var cam = _p("get_camera").call()
	var origin = _p("get_origin").call()
	if not cam or not origin:
		return
	# Rotate xr_origin around the head's world position so the player turns in place.
	var head_world = cam.global_position
	var rot := Basis(Vector3.UP, deg_to_rad(angle_deg))
	origin.global_position = head_world + rot * (origin.global_position - head_world)
	origin.rotate_y(deg_to_rad(angle_deg))


func release_physical_crouch() -> void:
	# Clear state only - no injection.
	_p("set_physical_crouch_active").call(false)
	_p("set_physical_crouch_resnap").call(0)


func update_physical_crouch() -> void:
	var cam = _p("get_camera").call()
	if not _p("get_standing_mode").call() or _p("get_standing_height_ref").call() < 0.3 or not cam:
		return
	var drop: float = _p("get_standing_height_ref").call() - cam.position.y
	var threshold: float = _p("get_physical_crouch_threshold").call()
	var active: bool = _p("get_physical_crouch_active").call()
	if not active:
		if drop >= threshold:
			_p("set_physical_crouch_active").call(true)
			_p("inject_action").call("crouch", true, 1.0)   # toggle ON
			_p("inject_action").call("crouch", false, 1.0)  # clear held state
			_log("[VR Mod] Physical crouch: start (drop=" + str(drop) + "m)")
	else:
		if drop < threshold * 0.6:
			_p("set_physical_crouch_active").call(false)
			_p("set_physical_crouch_resnap").call(8)
			_p("inject_action").call("crouch", true, 1.0)   # toggle OFF
			_p("inject_action").call("crouch", false, 1.0)  # clear held state
			_log("[VR Mod] Physical crouch: end (drop=" + str(drop) + "m)")


func reparent_camera_children() -> void:
	# We no longer reparent. Instead we sync game_camera transform
	# to the controller each frame in _sync_origin_to_game().
	if _p("get_weapons_reparented").call():
		return
	var gc = _p("get_game_camera").call()
	if not gc:
		return

	if gc.get_child_count() == 0:
		return  # Wait for weapon nodes to be populated

	_log("[VR Mod] Weapon strategy: sync game_camera to controller (no reparent)")
	_log("[VR Mod] Game camera children: " + str(gc.get_child_count()))
	for i in gc.get_child_count():
		var c = gc.get_child(i)
		var info = "  " + c.name + " (" + c.get_class() + ")"
		if c is Node3D:
			info += " vis=" + str(c.visible)
		if c.get_child_count() > 0:
			info += " [" + str(c.get_child_count()) + " children]"
		_log("[VR Mod] " + info)
	_p("set_weapons_reparented").call(true)
	_log("[VR Mod] Controller-aim sync ACTIVE")


func find_game_camera(_node: Node) -> Camera3D:
	# Only detect the gameplay camera at /root/Map/Core/Camera
	var core_cam = _tree.root.get_node_or_null("Map/Core/Camera")
	if core_cam and core_cam is Camera3D:
		return core_cam
	return null
