extends RefCounted

# xr_rig.gd
# Origin/camera/controller install, recenter, per-frame origin/camera sync,
# snap/smooth turn rotation, mouse steering of the game camera (so bullets
# land where the controller points), physical-crouch detection, and the
# game-camera search.

var autoload: Node

func _init(p_autoload: Node) -> void:
	autoload = p_autoload


func process(_frame: Dictionary, delta: float) -> void:
	# Per-frame rig work owned by xr_rig:
	#  * camera-lost polling (level transition / main-menu fallback)
	#  * weapon-reparent retry (game weapons load late after camera)
	#  * physical-crouch detection (standing-mode duck under cover)
	#  * standing-mode resnap + physical-crouch release resnap timers
	#  * origin->game-camera position sync (and steer-via-mouse for aim)
	#  * auto-recenter when HMD drifts > AUTO_RECENTER_DIST_M from character
	if not autoload.xr_origin or not is_instance_valid(autoload.xr_origin):
		return
	_poll_camera_lost()
	_retry_weapon_reparent()
	update_physical_crouch()
	_tick_standing_mode_resnap()
	_tick_physical_crouch_resnap()
	if autoload.game_camera and is_instance_valid(autoload.game_camera):
		if autoload.game_camera.environment != null:
			autoload.game_camera.environment = null
		if autoload.game_camera.attributes != null:
			autoload.game_camera.attributes = null
	sync_origin_to_game()
	_tick_auto_recenter(delta)


func _poll_camera_lost() -> void:
	if autoload.game_camera and is_instance_valid(autoload.game_camera):
		return
	# Camera lost or freed (level transition). Poll for new one.
	autoload._camera_lost_frames += 1
	if autoload._frames_waited % autoload.CAMERA_POLL_INTERVAL == 0:
		if autoload.game_camera:
			autoload._log("[VR Mod] Game camera lost (level transition?) — searching...")
		autoload.game_camera = find_game_camera(autoload.get_tree().root)
		if autoload.game_camera:
			attach_rig_to_camera()
			autoload._on_level_transition()
			autoload._camera_lost_frames = 0
			autoload._log("[VR Mod] Camera found again")
	# After ~2 seconds without a camera, enter main menu mode (once)
	elif autoload._camera_lost_frames > 120 and not autoload._in_menu_mode:
		autoload._on_main_menu_entered()


func _retry_weapon_reparent() -> void:
	# Weapon nodes load late — retry once a second until the reparent succeeds.
	if not autoload._weapons_reparented and autoload._frames_waited % 60 == 0:
		reparent_camera_children()


func _tick_standing_mode_resnap() -> void:
	# Re-snap origin a few frames after tracking mode switch (reference space settles).
	if autoload._standing_mode_resnap <= 0:
		return
	autoload._standing_mode_resnap -= 1
	if autoload._standing_mode_resnap == 0:
		attach_rig_to_camera()
		autoload._log("[VR Mod] Origin re-snapped after tracking mode change")
		if autoload._standing_mode and autoload.xr_camera:
			autoload._standing_height_ref = autoload.xr_camera.position.y
			if autoload._standing_height_ref < 0.3:
				autoload._standing_height_ref = 1.6
			autoload._log("[VR Mod] Standing height reference: ", autoload._standing_height_ref, "m")


func _tick_physical_crouch_resnap() -> void:
	if autoload._physical_crouch_resnap <= 0:
		return
	autoload._physical_crouch_resnap -= 1
	if autoload._physical_crouch_resnap == 0:
		attach_rig_to_camera()
		if autoload._standing_mode and autoload.xr_camera:
			autoload._standing_height_ref = autoload.xr_camera.position.y
			if autoload._standing_height_ref < 0.3:
				autoload._standing_height_ref = 1.6
		autoload._log("[VR Mod] Origin re-snapped after physical crouch release")


func _tick_auto_recenter(delta: float) -> void:
	# Auto-recenter: snap origin back to camera if HMD drifts > AUTO_RECENTER_DIST_M
	# in XZ. Suppressed in any UI / decor mode so the player isn't yanked while
	# pointing at menus or placing furniture. Cooldown lives on autoload because
	# attach_rig_to_camera() seeds it directly.
	if autoload._auto_recenter_cooldown > 0.0:
		autoload._auto_recenter_cooldown -= delta
		return
	if not autoload._auto_recenter_enabled or autoload._interface_open or autoload._config_screen_open or autoload._decor_mode:
		return
	if not autoload.game_camera or not is_instance_valid(autoload.game_camera) or not autoload.xr_camera:
		return
	var hmd = autoload.xr_camera.global_position
	var cam = autoload.game_camera.global_position
	if Vector2(hmd.x - cam.x, hmd.z - cam.z).length() > autoload.AUTO_RECENTER_DIST_M:
		attach_rig_to_camera()


func install_xr_rig() -> void:
	autoload._log("[VR Mod] Installing XR rig...")

	# xr_origin and xr_camera were created in _ready() for early HMD output.
	autoload.xr_origin.world_scale = autoload.world_scale
	autoload.xr_interface.render_target_size_multiplier = autoload._render_scale

	autoload.left_controller = XRController3D.new()
	autoload.left_controller.name = "LeftHand"
	autoload.left_controller.tracker = "left_hand"
	autoload.xr_origin.add_child(autoload.left_controller)

	autoload.right_controller = XRController3D.new()
	autoload.right_controller.name = "RightHand"
	autoload.right_controller.tracker = "right_hand"
	autoload.xr_origin.add_child(autoload.right_controller)

	autoload.left_controller.button_pressed.connect(autoload._on_button_pressed.bind("left"))
	autoload.left_controller.button_released.connect(autoload._on_button_released.bind("left"))
	autoload.right_controller.button_pressed.connect(autoload._on_button_pressed.bind("right"))
	autoload.right_controller.button_released.connect(autoload._on_button_released.bind("right"))

	# Extract hand GLTF assets from Metro's VMZ cache to user:// so GLTFDocument
	# can read them (res://resources/hands/ is not mounted into Godot's VFS).
	if autoload._extract_hand_assets_from_vmz():
		autoload._assets_base = "user://vr_mod/hands/"
	else:
		autoload._hand_load_errors.append("hand: VMZ extraction failed - hands will use box fallback")

	# Create simple controller hand models (visible when no weapon equipped)
	autoload._log("[VR Mod] Creating hand models...")
	autoload._create_hand_model(autoload.left_controller, "LeftHandModel")
	autoload._create_hand_model(autoload.right_controller, "RightHandModel")

	# Grab raycasts on both controllers - short range for picking up items / holster detection
	for ctrl in [autoload.left_controller, autoload.right_controller]:
		var ray = RayCast3D.new()
		ray.name = "GrabRay"
		ray.target_position = Vector3(0, 0, -1.0)  # 1m forward from controller
		ray.enabled = true
		ray.collide_with_areas = true
		ray.collide_with_bodies = true
		ray.collision_mask = 0xFFFFF  # All 20 layers
		ctrl.add_child(ray)
	autoload._grab_ray_left = autoload.left_controller.get_node("GrabRay")
	autoload._grab_ray_right = autoload.right_controller.get_node("GrabRay")
	autoload._log("[VR Mod] Grab raycasts added to both controllers")

	# xr_origin is already parented to autoload (done in _ready()).

	if autoload.game_camera and is_instance_valid(autoload.game_camera):
		# Use the actual tracked head height instead of a hardcoded constant.
		var actual_head_height = autoload.xr_camera.position.y
		if actual_head_height < 0.3:
			actual_head_height = 1.6  # fallback: tracking not yet settled
			autoload._log("[VR Mod] Head tracking not ready, using fallback 1.6m")
		else:
			autoload._log("[VR Mod] Tracked head height: ", actual_head_height, "m")
		var cam_pos = autoload.game_camera.global_position
		autoload.xr_origin.global_position = Vector3(cam_pos.x, cam_pos.y - actual_head_height, cam_pos.z)
		autoload.xr_origin.global_rotation = Vector3.ZERO
		autoload._last_game_cam_pos = cam_pos
		if autoload._standing_mode:
			autoload._standing_height_ref = actual_head_height

		# Copy game camera's cull mask to XR camera so we can see
		# weapon viewmodels rendered on special visual layers
		autoload.xr_camera.cull_mask = autoload.game_camera.cull_mask
		autoload._log("[VR Mod] XR rig placed: origin=", autoload.xr_origin.global_position)
		autoload._log("[VR Mod] Copied cull_mask from game_camera: ", autoload.game_camera.cull_mask)
	else:
		autoload.xr_origin.global_position = Vector3.ZERO
		autoload._last_game_cam_pos = Vector3(0, 1.7, 0)
		autoload._in_menu_mode = true  # No game camera - show menu panel once HUD is set up

	autoload.xr_camera.current = true
	autoload.get_viewport().use_xr = true

	var loader = autoload.get_tree().root.get_node_or_null("Loader")
	if loader:
		loader.visible = false
		autoload._log("[VR Mod] Hid Loader CanvasLayer")

	autoload._reparent_camera_children()

	# Gameplay needs captured cursor for fire input; main menu needs visible cursor.
	if autoload._in_menu_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Ensure user data directory and default config exist
	DirAccess.make_dir_recursive_absolute("user://vr_mod")
	if not FileAccess.file_exists(autoload._config_path):
		autoload._save_full_config()

	# Reset debug log - MUST stay here; hand creation above logs to the old file,
	# those messages are erased. _hand_load_errors buffers them across this reset.
	var dump_path = autoload._log_path
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
		autoload._log("[VR Mod] Debug log reset: ", dump_path)

	# Flush buffered hand load messages (written before the reset above)
	for msg in autoload._hand_load_errors:
		autoload._log(msg)
	autoload._hand_load_errors.clear()

	# Create laser pointer mesh (hidden by default)
	autoload._laser_mesh = MeshInstance3D.new()
	autoload._laser_mesh.name = "LaserPointer"
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.002
	cylinder.bottom_radius = 0.002
	cylinder.height = 5.0
	autoload._laser_mesh.mesh = cylinder
	var laser_mat = StandardMaterial3D.new()
	laser_mat.albedo_color = Color(0.2, 0.5, 1.0, 0.5)
	laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser_mat.no_depth_test = true
	laser_mat.render_priority = 20  # Render on top of HUD quad (priority 10)
	autoload._laser_mesh.material_override = laser_mat
	autoload._laser_mesh.visible = false
	# Cylinder is centered at origin along Y axis. We need it along -Z.
	autoload._laser_mesh.rotation.x = deg_to_rad(90)
	autoload._laser_mesh.position.z = -cylinder.height / 2.0

	var pointer_controller = autoload._get_controller(autoload._config_dominant_hand)
	pointer_controller.add_child(autoload._laser_mesh)

	# Floating hover label - shows item/interactable name when laser aims at it
	autoload._hover_label = Label3D.new()
	autoload._hover_label.name = "HoverLabel"
	autoload._hover_label.font_size = 48
	autoload._hover_label.pixel_size = 0.001
	autoload._hover_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	autoload._hover_label.no_depth_test = true
	autoload._hover_label.render_priority = 10
	autoload._hover_label.outline_size = 6
	autoload._hover_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	autoload._hover_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	autoload._hover_label.visible = false
	autoload.add_child(autoload._hover_label)

	autoload._setup_comfort_vignette()
	autoload._create_holster_holos()

	autoload._log("[VR Mod] === VR rig active ===")


func attach_rig_to_camera() -> void:
	if not autoload.game_camera or not autoload.xr_origin or not autoload.xr_camera:
		return
	var cam_pos = autoload.game_camera.global_position
	# Place origin so HMD lands exactly at cam_pos.
	var head_local = autoload.xr_camera.position
	if head_local.y < 0.3:
		head_local.y = 1.6
	autoload.xr_origin.global_position = cam_pos - autoload.xr_origin.global_basis * head_local
	autoload._last_game_cam_pos = cam_pos
	autoload._auto_recenter_cooldown = 3.0
	autoload.xr_camera.cull_mask = autoload.game_camera.cull_mask
	autoload._in_menu_mode = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if autoload._config_reminder_label and is_instance_valid(autoload._config_reminder_label):
		autoload._config_reminder_label.visible = false
	autoload._log("[VR Mod] Rig recentered to camera at ", cam_pos)


func sync_origin_to_game() -> void:
	if autoload.game_camera and is_instance_valid(autoload.game_camera) and autoload.xr_origin:
		var current_pos = autoload.game_camera.global_position
		var delta_pos = current_pos - autoload._last_game_cam_pos
		if delta_pos.length() > 0.001:
			# Freeze Y while physically crouched
			if autoload._physical_crouch_active or autoload._physical_crouch_resnap > 0:
				delta_pos.y = 0.0
			autoload.xr_origin.global_position += delta_pos
			autoload._last_game_cam_pos = current_pos

		# Steer game camera toward controller aim via mouse injection
		if not autoload._interface_open:
			if autoload._decor_mode:
				autoload._steer_decor_camera_to_controller()
			else:
				steer_game_camera_via_mouse()


func steer_game_camera_via_mouse() -> void:
	# Steer game camera to match weapon barrel aim direction.
	var aim_hand: String
	if autoload._holster_state == autoload.HolsterState.LOWERED or autoload._holster_state == autoload.HolsterState.SLING:
		aim_hand = autoload._config_dominant_hand
	else:
		aim_hand = autoload._get_weapon_hand()
	var aim_controller = autoload._get_controller(aim_hand)
	if not aim_controller or not aim_controller.get_is_active():
		autoload._sens_cal_pending = false
		return

	# Compute barrel direction
	var aim_forward: Vector3

	if autoload._support_grip_held:
		var off_controller = autoload._get_controller(autoload._get_support_hand())
		if off_controller and off_controller.get_is_active():
			var hand_dist = aim_controller.global_position.distance_to(off_controller.global_position)
			if hand_dist > autoload.TWO_HAND_MIN_DIST_M:
				aim_forward = (off_controller.global_position - aim_controller.global_position).normalized()
			else:
				aim_forward = -aim_controller.global_basis.z
		else:
			aim_forward = -aim_controller.global_basis.z
	else:
		# Use raw controller forward for steering
		aim_forward = -aim_controller.global_basis.z
	# Aim deadzone
	var aim_unchanged = autoload._steer_game_have_target and (aim_forward - autoload._steer_game_last_aim).length_squared() < autoload._STEER_AIM_DEADZONE_SQ
	var target_yaw: float
	var target_pitch: float
	if aim_unchanged:
		target_yaw = autoload._steer_game_last_target_yaw
		target_pitch = autoload._steer_game_last_target_pitch
	else:
		target_yaw = atan2(-aim_forward.x, -aim_forward.z)
		target_pitch = asin(clampf(aim_forward.y, -1.0, 1.0))
		autoload._steer_game_last_aim = aim_forward
		autoload._steer_game_last_target_yaw = target_yaw
		autoload._steer_game_last_target_pitch = target_pitch
		autoload._steer_game_have_target = true

	# Calibration disabled
	autoload._sens_cal_pending = false

	# Mouse injection
	if not aim_unchanged:
		var game_yaw = autoload.game_camera.global_rotation.y
		var game_pitch = autoload.game_camera.global_rotation.x
		var yaw_error = fmod(target_yaw - game_yaw + PI, TAU) - PI
		var pitch_error = target_pitch - game_pitch
		if abs(yaw_error) >= deg_to_rad(0.3) or abs(pitch_error) >= deg_to_rad(0.3):
			var correction_strength := 0.6
			var mouse_dx = -(yaw_error * correction_strength) / autoload._mouse_sens_estimate
			var mouse_dy = -(pitch_error * correction_strength) / autoload._mouse_sens_estimate
			var event = InputEventMouseMotion.new()
			event.relative = Vector2(mouse_dx, mouse_dy)
			event.position = autoload.get_viewport().get_visible_rect().size / 2
			Input.parse_input_event(event)

	# Direct rotation override when weapon is drawn
	if autoload._holster_state == autoload.HolsterState.DRAWN and autoload._weapon_loaded and is_finite(target_yaw) and is_finite(target_pitch):
		autoload.game_camera.global_rotation = Vector3(target_pitch, target_yaw, 0.0)


func turn_origin(angle_deg: float) -> void:
	if not autoload.xr_camera or not autoload.xr_origin:
		return
	# Rotate xr_origin around the head's world position so the player turns in place.
	var head_world = autoload.xr_camera.global_position
	var rot := Basis(Vector3.UP, deg_to_rad(angle_deg))
	autoload.xr_origin.global_position = head_world + rot * (autoload.xr_origin.global_position - head_world)
	autoload.xr_origin.rotate_y(deg_to_rad(angle_deg))


func release_physical_crouch() -> void:
	# Clear state only - no injection.
	autoload._physical_crouch_active = false
	autoload._physical_crouch_resnap = 0


func update_physical_crouch() -> void:
	if not autoload._standing_mode or autoload._standing_height_ref < 0.3 or not autoload.xr_camera:
		return
	var drop = autoload._standing_height_ref - autoload.xr_camera.position.y
	if not autoload._physical_crouch_active:
		if drop >= autoload._physical_crouch_threshold:
			autoload._physical_crouch_active = true
			autoload._inject_action("crouch", true)   # toggle ON
			autoload._inject_action("crouch", false)  # clear held state
			autoload._log("[VR Mod] Physical crouch: start (drop=", drop, "m)")
	else:
		if drop < autoload._physical_crouch_threshold * 0.6:
			autoload._physical_crouch_active = false
			autoload._physical_crouch_resnap = 8
			autoload._inject_action("crouch", true)   # toggle OFF
			autoload._inject_action("crouch", false)  # clear held state
			autoload._log("[VR Mod] Physical crouch: end (drop=", drop, "m)")


func reparent_camera_children() -> void:
	# We no longer reparent. Instead we sync game_camera transform
	# to the controller each frame in _sync_origin_to_game().
	if autoload._weapons_reparented:
		return
	if not autoload.game_camera:
		return

	if autoload.game_camera.get_child_count() == 0:
		return  # Wait for weapon nodes to be populated

	autoload._log("[VR Mod] Weapon strategy: sync game_camera to controller (no reparent)")
	autoload._log("[VR Mod] Game camera children: ", autoload.game_camera.get_child_count())
	for i in autoload.game_camera.get_child_count():
		var c = autoload.game_camera.get_child(i)
		var info = "  " + c.name + " (" + c.get_class() + ")"
		if c is Node3D:
			info += " vis=" + str(c.visible)
		if c.get_child_count() > 0:
			info += " [" + str(c.get_child_count()) + " children]"
		autoload._log("[VR Mod] ", info)
	autoload._weapons_reparented = true
	autoload._log("[VR Mod] Controller-aim sync ACTIVE")


func find_game_camera(node: Node) -> Camera3D:
	# Only detect the gameplay camera at /root/Map/Core/Camera
	var core_cam = autoload.get_tree().root.get_node_or_null("Map/Core/Camera")
	if core_cam and core_cam is Camera3D:
		return core_cam
	return null
