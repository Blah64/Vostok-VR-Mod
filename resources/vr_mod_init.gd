extends Node

# Road to Vostok VR Mod - Autoload Initialization Script
# HUD Strategy: Share main viewport's World2D with a secondary SubViewport
# (disable_3d=true). No node reparenting — all game references stay intact.
#
# When inventory is CLOSED: HUD quad follows head (head-locked)
# When inventory is OPEN: quad detaches, scales up, stays in world space
# Controller pointing + trigger click for inventory interaction.

var xr_interface: XRInterface
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var left_controller: XRController3D
var right_controller: XRController3D
var game_camera: Camera3D
var _phase := 0  # 0=waiting_for_camera, 1=xr_activating, 2=running
var _frames_waited := 0
var _xr_ready := false
var _weapons_reparented := false

# Weapon debug
var _weapon_debug_timer := 0.0
var _last_cam_child_snapshot := []  # Track changes to camera children
var _scroll_cooldown := 0.0  # Prevent rapid-fire scroll
var _support_grip_held := false  # Support hand grip held = two-hand weapon grip
var _grabbed_object: Node3D = null  # Currently grabbed loose item
var _grab_offset := Vector3.ZERO  # Offset from controller to grabbed object
var _grab_hand := ""  # Which hand holds the grabbed object ("left" or "right")
var _grab_ray_left: RayCast3D   # Grab raycast on left controller
var _grab_ray_right: RayCast3D  # Grab raycast on right controller
var _throw_samples: Array = []  # Recent [position, time] pairs for throw velocity
var _weapon_loaded := false  # Track if weapon appeared
var _weapon_raise_timer := -1.0  # Timer to auto-raise weapon after equip
var _pending_holster_key: int = -1  # KEY_N pending delayed injection on holster; -1 = none
var _holster_cooldown := 0.0        # Seconds remaining before a new draw is allowed after holstering

# Holster system
enum HolsterState { UNARMED, DRAWN, LOWERED }
var _holster_state: int = HolsterState.UNARMED
var _weapon_hand := ""  # "left" or "right" — which hand currently holds weapon
var _weapon_slot := 0   # 1-4 mapped to KEY_1..KEY_4, 0 = none

const HOLSTER_ZONES := {
	1: {"name": "right_shoulder", "key": KEY_1},
	2: {"name": "right_hip",      "key": KEY_2},
	3: {"name": "left_hip",       "key": KEY_3},
	4: {"name": "chest",          "key": KEY_4},
}
# Per-slot offsets (runtime-tunable, loaded from config)
var _holster_offsets := {
	1: Vector3(0.25, -0.15,  0.20),
	2: Vector3(0.25, -0.55,  0.0),
	3: Vector3(-0.25, -0.55, 0.0),
	4: Vector3(0.0,  -0.15,  0.10),
}
var _holster_zone_radius := 0.20
var _left_in_zone := 0   # Which zone left controller is in (0 = none)
var _right_in_zone := 0  # Which zone right controller is in (0 = none)

# Bag zone: reach behind the right shoulder to add a held item to inventory
var _bag_zone_offset := Vector3(0.15, -0.10, 0.35)  # Right-back, upper body (yaw-relative)
var _bag_zone_radius := 0.35
var _grab_in_bag_zone := false  # For haptic edge-detection while holding item

# NVG zone: reach above head to toggle night vision goggles
var _nvg_zone_offset := Vector3(0.0, 0.30, 0.0)   # Head-relative, above head
var _nvg_zone_radius := 0.25
var _hand_in_nvg_zone := {"left": false, "right": false}  # Edge-detection for haptic

# NVG overlay system
var _nvg_active := false                # tracks game's NVG Overlay.visible
var _nvg_overlay_mesh: MeshInstance3D   # fullscreen quad parented to xr_camera
var _nvg_mono := false                  # config: mono vision (same image both eyes)
var _nvg_mono_viewport: SubViewport     # mono render SubViewport (created on demand)
var _nvg_mono_camera: Camera3D          # mono render camera (centered between eyes)
var _nvg_brightness := 2.0             # config: brightness multiplier
var _nvg_overlay_installed := false

# Per-slot grip offsets in aim-local space (up, forward from controller)
# Slot 1=primary, 2=sidearm, 3=knife, 4=grenade
var _slot_grip_offsets := {
	1: Vector3(0, 0.15, -0.20),   # Primary / long gun
	2: Vector3(0, 0.10, -0.13),   # Sidearm / pistol
	3: Vector3(0, 0.05, -0.10),   # Knife
	4: Vector3(0, 0.08, -0.10),   # Grenade
}
# Per-slot Y rotation offset in degrees (added to the 180° flip)
var _slot_grip_rotations := { 1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0 }

# Reticle parallax fix — patch fragment shader with VR-compatible ray-plane intersection
var _fixed_reticle_instances := {}  # MeshInstance3D instance_id → true

# Scope PIP — our own SubViewport + Camera3D for VR scope rendering
var _scope_camera: Camera3D = null       # Our scope camera
var _scope_viewport: SubViewport = null  # Our rendering viewport
var _scope_attachment: Node3D = null     # The visible scope attachment node
var _scope_lens_mesh: MeshInstance3D = null  # MeshInstance3D with the lens surface
var _scope_overridden_surfaces: Array = []   # [{surf: int, original: Material}]
var _scope_active := false
var _scope_weapon_slot := 0
var _scope_vp_created := false           # True once our VP is created (reuse across weapons)
var _scope_is_variable := false          # True if active scope supports variable zoom
var _scope_zoom_fovs := []               # FOV per zoom level (derived from reticleSize ratios)
var _scope_zoom_reticle_scales := []     # Reticle UV scale per zoom level
var _scope_zoom_index := 0               # Current zoom level index

# Grip adjust mode — tune offsets live with thumbsticks
var _adjust_mode := false
var _adjust_saved_offset := Vector3.ZERO  # Backup to discard changes
var _adjust_saved_rotation := 0.0
const ADJUST_SPEED := 0.15  # Meters per second for position
const ADJUST_ROT_SPEED := 45.0  # Degrees per second for rotation


func _get_weapon_hand() -> String:
	if _holster_state != HolsterState.UNARMED and _weapon_hand != "":
		return _weapon_hand
	return _config_dominant_hand


func _get_support_hand() -> String:
	return "left" if _get_weapon_hand() == "right" else "right"


func _get_controller(hand: String) -> XRController3D:
	return right_controller if hand == "right" else left_controller


func _get_nearby_holster_zone(controller_pos: Vector3) -> int:
	if not xr_camera or not is_instance_valid(xr_camera):
		return 0
	var head_pos = xr_camera.global_position
	var head_yaw = xr_camera.global_rotation.y
	var yaw_basis = Basis(Vector3.UP, head_yaw)
	var closest_zone := 0
	var closest_dist := _holster_zone_radius
	for slot in HOLSTER_ZONES:
		var zone_world_pos = head_pos + yaw_basis * _holster_offsets[slot]
		var dist = controller_pos.distance_to(zone_world_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest_zone = slot
	return closest_zone


func _is_in_bag_zone(world_pos: Vector3) -> bool:
	if not xr_camera or not is_instance_valid(xr_camera):
		return false
	var yaw := xr_camera.global_rotation.y
	var yaw_basis := Basis(Vector3.UP, yaw)
	var local := yaw_basis.inverse() * (world_pos - xr_camera.global_position)
	return local.distance_to(_bag_zone_offset) < _bag_zone_radius


func _is_in_nvg_zone(world_pos: Vector3) -> bool:
	if not xr_camera or not is_instance_valid(xr_camera):
		return false
	var head_pos = xr_camera.global_position
	return world_pos.distance_to(head_pos + _nvg_zone_offset) < _nvg_zone_radius


func _update_holster_zone_haptics() -> void:
	# Check each controller against holster zones and pulse haptic on entry
	for hand in ["left", "right"]:
		var ctrl = _get_controller(hand)
		if not ctrl or not ctrl.get_is_active():
			continue
		var zone = _get_nearby_holster_zone(ctrl.global_position)
		var prev_zone = _left_in_zone if hand == "left" else _right_in_zone
		if zone != prev_zone:
			if zone > 0 and _holster_cooldown <= 0.0:
				# Entered a new zone — haptic buzz (suppressed during holster cooldown)
				ctrl.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.15, 0.0)
				print("[VR Mod] ", hand, " hand entered zone: ", HOLSTER_ZONES[zone]["name"])
			if hand == "left":
				_left_in_zone = zone
			else:
				_right_in_zone = zone

	# Bag zone haptic: buzz when the grabbing hand enters the bag zone while holding a loose item
	if _grabbed_object and is_instance_valid(_grabbed_object) and _grab_hand != "":
		var grab_ctrl = _get_controller(_grab_hand)
		if grab_ctrl and grab_ctrl.get_is_active():
			var in_zone := _is_in_bag_zone(grab_ctrl.global_position)
			if in_zone and not _grab_in_bag_zone:
				grab_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.2, 0.0)
				print("[VR Mod] Grab hand entered bag zone")
			_grab_in_bag_zone = in_zone
	else:
		_grab_in_bag_zone = false

	# NVG zone haptic: buzz when either hand enters the NVG zone above head
	for hand in ["left", "right"]:
		var ctrl = _get_controller(hand)
		if not ctrl or not ctrl.get_is_active():
			_hand_in_nvg_zone[hand] = false
			continue
		var in_zone := _is_in_nvg_zone(ctrl.global_position)
		if in_zone and not _hand_in_nvg_zone[hand]:
			ctrl.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.15, 0.0)
			print("[VR Mod] ", hand, " hand entered NVG zone")
		_hand_in_nvg_zone[hand] = in_zone


func _update_nvg_overlay(_delta: float) -> void:
	if not _nvg_overlay_installed:
		return

	# Poll game's NVG overlay visibility as the true NVG state.
	# We use modulate.a=0 to hide it visually (not visible=false), so the game's
	# NVG.gd script can still toggle overlay.visible freely and we can read it.
	var overlay = get_tree().root.get_node_or_null("Map/Core/UI/NVG/Overlay")
	if not overlay:
		return
	var game_nvg_on: bool = overlay.visible

	# State transition: NVG just turned on
	if game_nvg_on and not _nvg_active:
		_nvg_active = true
		overlay.modulate.a = 0.0  # hide game's 2D overlay from HUD quad (keep visible=true)
		_nvg_overlay_mesh.visible = true
		var mat = _nvg_overlay_mesh.material_override as ShaderMaterial
		mat.set_shader_parameter("brightness", _nvg_brightness)
		if _nvg_mono:
			_create_nvg_mono_viewport()
			_nvg_mono_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			var vp_tex = _nvg_mono_viewport.get_texture()
			mat.set_shader_parameter("mono_tex", vp_tex)
			mat.set_shader_parameter("use_mono", true)
			# Place far enough that IPD parallax is negligible (~3° at 1m)
			# Size to overfill FOV: 2*tan(60°)*1.0 ≈ 3.46m, use 4.0m
			(_nvg_overlay_mesh.mesh as QuadMesh).size = Vector2(4.0, 4.0)
			_nvg_overlay_mesh.position = Vector3(0.0, 0.0, -1.0)
		else:
			mat.set_shader_parameter("use_mono", false)
			# Stereo: close to camera, oversized for SCREEN_UV coverage
			(_nvg_overlay_mesh.mesh as QuadMesh).size = Vector2(4.0, 4.0)
			_nvg_overlay_mesh.position = Vector3(0.0, 0.0, -0.15)
		print("[VR Mod] NVG overlay activated (mono=", _nvg_mono, ")")

	# State transition: NVG just turned off
	elif not game_nvg_on and _nvg_active:
		_nvg_active = false
		overlay.modulate.a = 1.0  # restore game overlay opacity for next activation
		_nvg_overlay_mesh.visible = false
		if _nvg_mono_viewport:
			_nvg_mono_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		print("[VR Mod] NVG overlay deactivated")

	# While NVG active: update shader time + sync mono camera
	if _nvg_active:
		# Keep game overlay hidden
		if overlay:
			overlay.modulate.a = 0.0
		var mat = _nvg_overlay_mesh.material_override as ShaderMaterial
		mat.set_shader_parameter("time_val", Time.get_ticks_msec() / 1000.0)
		if _nvg_mono and _nvg_mono_camera and xr_camera:
			_nvg_mono_camera.global_transform = xr_camera.global_transform


func _draw_weapon(hand: String, slot: int) -> void:
	print("[VR Mod] DRAW weapon slot ", slot, " (", HOLSTER_ZONES[slot]["name"], ") with ", hand, " hand")
	_holster_state = HolsterState.DRAWN
	_weapon_hand = hand
	_weapon_slot = slot

	# Cancel any pending holster KEY injection — prevents double-toggle when
	# holster and draw happen within 0.15 s of each other.
	_pending_holster_key = -1

	# Inject the key to equip this weapon slot
	var key: int = HOLSTER_ZONES[slot]["key"]
	_inject_key(key, true)
	get_tree().create_timer(0.1).timeout.connect(func(): _inject_key(key, false))

	# Start weapon load detection + auto-raise sequence
	_weapon_loaded = false
	_weapon_raise_timer = 3.0
	_scroll_cooldown = 1.0
	_fixed_reticle_instances.clear()  # Re-scan for reticle on new weapon
	_cleanup_scope()  # Re-detect scope on new weapon


func _lower_weapon() -> void:
	print("[VR Mod] LOWER weapon (slot ", _weapon_slot, ")")
	_adjust_mode = false
	_holster_state = HolsterState.LOWERED
	_support_grip_held = false
	# Set weapon_low to lower the weapon visually
	_inject_action("weapon_low", true)
	get_tree().create_timer(0.1).timeout.connect(func(): _inject_action("weapon_low", false))
	# Release fire/aim in case they were held
	Input.action_release("fire")
	Input.action_release("left_mouse")
	_inject_action("fire", false)
	_inject_action("left_mouse", false)
	_inject_mouse_button(MOUSE_BUTTON_LEFT, false)
	_inject_action("aim", false)
	_inject_mouse_button(MOUSE_BUTTON_RIGHT, false)


func _raise_weapon() -> void:
	print("[VR Mod] RAISE weapon (slot ", _weapon_slot, ")")
	_holster_state = HolsterState.DRAWN
	# Re-raise the weapon
	_inject_action("weapon_high", true)
	get_tree().create_timer(0.1).timeout.connect(func(): _inject_action("weapon_high", false))


func _holster_weapon() -> void:
	print("[VR Mod] HOLSTER weapon (slot ", _weapon_slot, ")")
	_adjust_mode = false
	_cleanup_scope()
	# Release aim
	_inject_action("aim", false)
	_inject_mouse_button(MOUSE_BUTTON_RIGHT, false)
	_inject_action("weapon_high", false)

	# Unequip: inject the same key to toggle off, but delay by 0.15 s so that a
	# _draw_weapon() call in the same frame (or within that window) can cancel it
	# via _pending_holster_key, avoiding a double-toggle that leaves the weapon stuck.
	if _weapon_slot > 0 and HOLSTER_ZONES.has(_weapon_slot):
		var key: int = HOLSTER_ZONES[_weapon_slot]["key"]
		_pending_holster_key = key
		get_tree().create_timer(0.15).timeout.connect(func():
			if _pending_holster_key == key:
				_pending_holster_key = -1
				_inject_key(key, true)
				get_tree().create_timer(0.1).timeout.connect(func(): _inject_key(key, false))
		)

	_holster_state = HolsterState.UNARMED
	_weapon_hand = ""
	_weapon_slot = 0
	_weapon_loaded = false
	_support_grip_held = false
	_holster_cooldown = 0.8  # Block re-draw until animation completes


# HUD
var hud_viewport: SubViewport
var hud_mesh: MeshInstance3D
var _hud_installed := false
var _interface_open := false
var _prev_interface_open := false  # For detecting transitions
var _laser_mesh: MeshInstance3D   # Visual laser pointer line (dual-purpose: grab range + UI pointer)
var _menu_open := false           # True while inventory/menu is visible
var _laser_screen_pos := Vector2(-1, -1)  # Current cursor position from laser

# HUD sizing (vars so config screen can change them at runtime)
var _hud_width := 2.0
var _hud_distance := 1.5
var _hud_height_offset := -0.1
var _menu_width := 3.0
var _menu_distance := 1.3
var _hud_lr_offset := 0.0
var _menu_lr_offset := 0.0
var _hud_smooth_follow := false
var _hud_smooth_speed := 3.0
var _hud_yaw := 0.0         # Lagged yaw for smooth follow — tracked separately, never read from mesh
var _hud_spread := 1.0      # HUD element spread (1.0 = default, <1 = closer together)
var _menu_laser_uv_x := 0.02  # Horizontal laser offset for menu/inventory (UV units)
var _menu_laser_uv_y := 0.06  # Vertical laser offset for menu/inventory (UV units)

# Config screen
var _config_screen_open := false
var _config_panel_vp: SubViewport = null
var _config_panel_quad: MeshInstance3D = null
var _config_laser_pos := Vector2.ZERO

# Config
var world_scale := 1.0
var snap_turn_degrees := 45.0
var smooth_turn_speed := 120.0
var use_snap_turn := true
var thumbstick_deadzone := 0.15
var _config_dominant_hand := "right"
var _snap_turn_cooldown := false
var _last_game_cam_pos := Vector3.ZERO

# Timing
const CAMERA_POLL_INTERVAL := 30
const XR_SETTLE_FRAMES := 10
const HUD_SETUP_DELAY := 30


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		get_viewport().use_xr = false
		print("[VR Mod] Viewport use_xr = FALSE (waiting for gameplay)")


func _ready() -> void:
	# Run AFTER game scripts so our weapon transform override sticks
	process_priority = 1000
	process_physics_priority = 1000
	print("[VR Mod] === VR Mod initializing (priority=1000) ===")

	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface:
		print("[VR Mod] Found OpenXR interface")
		if not xr_interface.is_initialized():
			if xr_interface.initialize():
				print("[VR Mod] OpenXR interface initialized")
			else:
				printerr("[VR Mod] ERROR: Failed to initialize OpenXR interface")
				return
		else:
			print("[VR Mod] OpenXR interface already initialized")
		XRServer.primary_interface = xr_interface
		_xr_ready = true
		print("[VR Mod] OpenXR ready (view count: ", xr_interface.get_view_count(), ")")
	else:
		printerr("[VR Mod] ERROR: OpenXR interface not found!")
		return

	_load_config()
	print("[VR Mod] Waiting for 3D camera (gameplay start)...")


func _process(delta: float) -> void:
	if not _xr_ready:
		return

	_frames_waited += 1

	match _phase:
		0:
			if _frames_waited % CAMERA_POLL_INTERVAL == 0:
				game_camera = _find_game_camera(get_tree().root)
				if game_camera:
					print("[VR Mod] === Game camera detected! ===")
					print("[VR Mod] Camera: ", game_camera.get_path())
					get_viewport().use_xr = true
					_phase = 1
					_frames_waited = 0

		1:
			if _frames_waited >= XR_SETTLE_FRAMES:
				_install_xr_rig()
				_phase = 2
				_frames_waited = 0

		2:
			if xr_origin and is_instance_valid(xr_origin):
				if game_camera and not is_instance_valid(game_camera):
					game_camera = _find_game_camera(get_tree().root)
					if game_camera:
						_attach_rig_to_camera()

				if not _hud_installed and _frames_waited >= HUD_SETUP_DELAY:
					_setup_vr_hud()

				# Retry weapon reparenting until it succeeds (nodes may load late)
				if not _weapons_reparented and _frames_waited % 60 == 0:
					_reparent_camera_children()

				# Scroll cooldown tick
				if _scroll_cooldown > 0:
					_scroll_cooldown -= delta

				# Post-scroll delayed debug dump
				if _post_scroll_timer > 0:
					_post_scroll_timer -= delta
					if _post_scroll_timer <= 0:
						_post_scroll_timer = -1.0
						_force_debug_dump("AFTER_SCROLL_3SEC")
						print("[VR Mod] Post-scroll debug dumped!")

				# Check if weapon just loaded
				if not _weapon_loaded and game_camera and is_instance_valid(game_camera):
					var mgr = game_camera.get_node_or_null("Manager")
					if mgr and mgr.get_child_count() > 0:
						_weapon_loaded = true
						var wep = mgr.get_child(0)
						print("[VR Mod] *** WEAPON LOADED: ", wep.name, " ***")
						# Auto-raise weapon after short delay
						_weapon_raise_timer = 0.5
						print("[VR Mod] Will auto-raise weapon in 0.5s")

				# Auto-raise weapon timer (only if weapon is still DRAWN)
				if _weapon_raise_timer > 0:
					_weapon_raise_timer -= delta
					if _weapon_raise_timer <= 0:
						_weapon_raise_timer = -1.0
						if _holster_state == HolsterState.DRAWN:
							if not _weapon_loaded:
								# Slot was empty — abort and revert to unarmed
								print("[VR Mod] Slot ", _weapon_slot, " empty, reverting to UNARMED")
								_holster_state = HolsterState.UNARMED
								_weapon_hand = ""
								_weapon_slot = 0
								_support_grip_held = false
							else:
								print("[VR Mod] Auto-raising weapon (weapon_high)")
								_inject_action("weapon_high", true)
								get_tree().create_timer(0.1).timeout.connect(
									func(): _inject_action("weapon_high", false)
								)

				# Continuous weapon debug: detect any changes to camera subtree
				_weapon_debug_timer += delta
				if _weapon_debug_timer >= 3.0:
					_weapon_debug_timer = 0.0
					_deep_camera_debug()

				# Tick down holster cooldown
				if _holster_cooldown > 0.0:
					_holster_cooldown -= delta

				# Holster zone haptic feedback
				_update_holster_zone_haptics()
				_update_nvg_overlay(delta)

				_update_interface_state()
				_sync_origin_to_game()
				_process_input(delta)

				# Sync weapon AFTER origin/camera so our position override wins
				_sync_weapon_to_controller()
				_update_hand_visibility()
				_update_grabbed()

				_update_smooth_hud(delta)

				if _config_screen_open:
					_update_config_laser()
				elif _interface_open:
					_update_laser_pointer()


func _install_xr_rig() -> void:
	print("[VR Mod] Installing XR rig...")

	xr_origin = XROrigin3D.new()
	xr_origin.name = "VRModOrigin"
	xr_origin.world_scale = world_scale

	xr_camera = XRCamera3D.new()
	xr_camera.name = "VRModCamera"
	xr_origin.add_child(xr_camera)

	left_controller = XRController3D.new()
	left_controller.name = "LeftHand"
	left_controller.tracker = "left_hand"
	xr_origin.add_child(left_controller)

	right_controller = XRController3D.new()
	right_controller.name = "RightHand"
	right_controller.tracker = "right_hand"
	xr_origin.add_child(right_controller)

	left_controller.button_pressed.connect(_on_button_pressed.bind("left"))
	left_controller.button_released.connect(_on_button_released.bind("left"))
	right_controller.button_pressed.connect(_on_button_pressed.bind("right"))
	right_controller.button_released.connect(_on_button_released.bind("right"))

	# Create simple controller hand models (visible when no weapon equipped)
	print("[VR Mod] Creating hand models...")
	_create_hand_model(left_controller, "LeftHandModel")
	_create_hand_model(right_controller, "RightHandModel")

	# Grab raycasts on both controllers - short range for picking up items / holster detection
	for ctrl in [left_controller, right_controller]:
		var ray = RayCast3D.new()
		ray.name = "GrabRay"
		ray.target_position = Vector3(0, 0, -1.0)  # 1m forward from controller
		ray.enabled = true
		ray.collide_with_areas = true
		ray.collide_with_bodies = true
		ray.collision_mask = 0xFFFFF  # All 20 layers
		ctrl.add_child(ray)
	_grab_ray_left = left_controller.get_node("GrabRay")
	_grab_ray_right = right_controller.get_node("GrabRay")
	print("[VR Mod] Grab raycasts added to both controllers")


	if game_camera and is_instance_valid(game_camera):
		var parent = game_camera.get_parent()
		if parent:
			parent.add_child(xr_origin)
		else:
			get_tree().root.add_child(xr_origin)

		var approx_head_height := 1.6
		var cam_pos = game_camera.global_position
		xr_origin.global_position = Vector3(cam_pos.x, cam_pos.y - approx_head_height, cam_pos.z)
		xr_origin.global_rotation = Vector3.ZERO
		_last_game_cam_pos = cam_pos

		# Copy game camera's cull mask to XR camera so we can see
		# weapon viewmodels rendered on special visual layers
		xr_camera.cull_mask = game_camera.cull_mask
		print("[VR Mod] XR rig placed: origin=", xr_origin.global_position)
		print("[VR Mod] Copied cull_mask from game_camera: ", game_camera.cull_mask)
	else:
		get_tree().root.add_child(xr_origin)
		xr_origin.global_position = Vector3.ZERO
		_last_game_cam_pos = Vector3(0, 1.7, 0)

	xr_camera.current = true
	get_viewport().use_xr = true

	var loader = get_tree().root.get_node_or_null("Loader")
	if loader:
		loader.visible = false
		print("[VR Mod] Hid Loader CanvasLayer")

	_reparent_camera_children()

	# Ensure mouse is captured so fire input works
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Clear debug log and dump fire-related InputMap bindings
	var dump_path = OS.get_executable_path().get_base_dir() + "/vr_mod_debug.log"
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
		print("[VR Mod] Debug log with InputMap bindings: ", dump_path)

	# Create laser pointer mesh (hidden by default)
	_laser_mesh = MeshInstance3D.new()
	_laser_mesh.name = "LaserPointer"
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.002
	cylinder.bottom_radius = 0.002
	cylinder.height = 5.0
	_laser_mesh.mesh = cylinder
	var laser_mat = StandardMaterial3D.new()
	laser_mat.albedo_color = Color(0.2, 0.5, 1.0, 0.5)
	laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser_mat.no_depth_test = true
	laser_mat.render_priority = 20  # Render on top of HUD quad (priority 10)
	_laser_mesh.material_override = laser_mat
	_laser_mesh.visible = false
	# Cylinder is centered at origin along Y axis. We need it along -Z.
	# Rotate 90 degrees on X, offset half height on Z.
	_laser_mesh.rotation.x = deg_to_rad(90)
	_laser_mesh.position.z = -cylinder.height / 2.0

	var pointer_controller = _get_controller(_config_dominant_hand)
	pointer_controller.add_child(_laser_mesh)

	print("[VR Mod] === VR rig active ===")


func _setup_vr_hud() -> void:
	print("[VR Mod] Setting up VR HUD (World2D sharing)...")

	var main_vp = get_viewport()
	var vp_size = main_vp.get_visible_rect().size

	var ui_node = get_tree().root.get_node_or_null("Map/Core/UI")
	if ui_node:
		print("[VR Mod] UI node: ", ui_node.get_path(), " vis=", ui_node.visible)

	hud_viewport = SubViewport.new()
	hud_viewport.name = "VRHudViewport"
	hud_viewport.size = Vector2i(int(vp_size.x), int(vp_size.y))
	hud_viewport.transparent_bg = true
	hud_viewport.disable_3d = true
	hud_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	hud_viewport.world_2d = main_vp.world_2d
	hud_viewport.gui_disable_input = true
	add_child(hud_viewport)

	hud_mesh = MeshInstance3D.new()
	hud_mesh.name = "VRHudPanel"

	var quad = QuadMesh.new()
	var aspect = float(hud_viewport.size.y) / float(hud_viewport.size.x)
	quad.size = Vector2(_hud_width, _hud_width * aspect)
	hud_mesh.mesh = quad

	var mat = StandardMaterial3D.new()
	mat.albedo_texture = hud_viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 10
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hud_mesh.material_override = mat

	# Put HUD on layer 20 only so NVG mono camera doesn't render it
	hud_mesh.layers = (1 << 19)
	# Start head-locked
	hud_mesh.position = Vector3(_hud_lr_offset, _hud_height_offset, -_hud_distance)
	xr_camera.add_child(hud_mesh)

	_hud_installed = true
	_apply_hud_spread()
	print("[VR Mod] VR HUD installed (head-locked, ", _hud_width, "m wide)")

	_setup_nvg_overlay()
	print("[VR Mod] === VR fully active ===")


func _setup_nvg_overlay() -> void:
	_nvg_overlay_mesh = MeshInstance3D.new()
	_nvg_overlay_mesh.name = "NVGOverlay"
	var quad = QuadMesh.new()
	quad.size = Vector2(4.0, 4.0)
	_nvg_overlay_mesh.mesh = quad

	var shader = Shader.new()
	shader.code = NVG_OVERLAY_SHADER
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = 127
	mat.set_shader_parameter("tint", Color(0.47, 0.67, 0.51, 1.0))
	mat.set_shader_parameter("brightness", _nvg_brightness)
	mat.set_shader_parameter("use_mono", _nvg_mono)
	_nvg_overlay_mesh.material_override = mat

	# Put overlay on layer 20 ONLY so the mono camera can exclude it (prevents feedback loop)
	# XR cameras default cull_mask includes all 20 layers, so they still see it
	_nvg_overlay_mesh.layers = (1 << 19)  # layer 20 only
	_nvg_overlay_mesh.position = Vector3(0.0, 0.0, -0.15)
	_nvg_overlay_mesh.visible = false
	xr_camera.add_child(_nvg_overlay_mesh)
	_nvg_overlay_installed = true
	print("[VR Mod] NVG overlay installed (mono=", _nvg_mono, " brightness=", _nvg_brightness, ")")


func _create_nvg_mono_viewport() -> void:
	if _nvg_mono_viewport:
		return
	# Use XR per-eye render size for correct aspect ratio, scaled down for perf
	var xr_iface = XRServer.primary_interface
	var vp_size := Vector2i(1024, 1024)
	if xr_iface:
		var eye_size = xr_iface.get_render_target_size()
		var scale_factor := 0.5
		vp_size = Vector2i(maxi(int(eye_size.x * scale_factor), 512), maxi(int(eye_size.y * scale_factor), 512))

	_nvg_mono_viewport = SubViewport.new()
	_nvg_mono_viewport.name = "NVGMonoVP"
	_nvg_mono_viewport.size = vp_size
	_nvg_mono_viewport.transparent_bg = false
	_nvg_mono_viewport.disable_3d = false
	_nvg_mono_viewport.world_3d = get_viewport().world_3d
	_nvg_mono_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_nvg_mono_viewport)

	_nvg_mono_camera = Camera3D.new()
	_nvg_mono_camera.name = "NVGMonoCamera"
	_nvg_mono_camera.fov = 90.0
	_nvg_mono_camera.near = 0.05
	_nvg_mono_camera.far = 4000.0
	# Exclude layer 20 so mono camera doesn't see the NVG overlay quad (prevents feedback loop)
	_nvg_mono_camera.cull_mask = 0xFFFFF & ~(1 << 19)  # all 20 layers except layer 20
	_nvg_mono_viewport.add_child(_nvg_mono_camera)
	print("[VR Mod] NVG mono viewport created (", vp_size.x, "x", vp_size.y, ")")


func _update_interface_state() -> void:
	# Check if any UI panel that's normally hidden is now visible
	# (inventory, settings, loot pool, etc.)
	_interface_open = false
	var ui_node = get_tree().root.get_node_or_null("Map/Core/UI")
	if ui_node:
		for child in ui_node.get_children():
			# Skip always-visible HUD elements
			if child.name in ["HUD", "Effects", "NVG"]:
				continue
			if child is CanvasItem and child.visible:
				_interface_open = true
				break

	# Detect transitions
	if _interface_open and not _prev_interface_open:
		_on_interface_opened()
	elif not _interface_open and _prev_interface_open:
		_on_interface_closed()
	_prev_interface_open = _interface_open


func _on_interface_opened() -> void:
	print("[VR Mod] Interface OPENED - switching to world-fixed mode")
	if not hud_mesh:
		return

	# Detach from camera and place in world space in front of player
	var global_xform = hud_mesh.global_transform
	hud_mesh.get_parent().remove_child(hud_mesh)

	# Place in front of camera at current look direction
	var cam_pos = xr_camera.global_position
	var cam_forward = -xr_camera.global_basis.z
	cam_forward.y = 0  # Keep it level
	cam_forward = cam_forward.normalized()

	var menu_pos = cam_pos + cam_forward * _menu_distance
	var cam_right = xr_camera.global_basis.x
	menu_pos += cam_right * _menu_lr_offset
	menu_pos.y = cam_pos.y + _hud_height_offset

	# Add to scene root so it's world-fixed
	get_tree().root.add_child(hud_mesh)
	hud_mesh.global_position = menu_pos
	hud_mesh.look_at(cam_pos, Vector3.UP)
	# look_at makes it face camera, but quad's front might be wrong direction
	# QuadMesh faces +Z by default, look_at makes -Z face target, so flip 180
	hud_mesh.rotate_y(deg_to_rad(180))

	# Scale up for menu
	var aspect = float(hud_viewport.size.y) / float(hud_viewport.size.x)
	(hud_mesh.mesh as QuadMesh).size = Vector2(_menu_width, _menu_width * aspect)

	# Show laser pointer (restore to UI blue/full-length mode)
	_menu_open = true
	if _laser_mesh:
		var mat := _laser_mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.2, 0.5, 1.0, 0.5)
		var cyl := _laser_mesh.mesh as CylinderMesh
		if cyl:
			cyl.height = 5.0
			_laser_mesh.position.z = -cyl.height / 2.0
		_laser_mesh.visible = true

	print("[VR Mod] Menu placed at ", menu_pos)


func _on_interface_closed() -> void:
	print("[VR Mod] Interface CLOSED - switching to head-locked mode")
	if not hud_mesh:
		return

	if _hud_smooth_follow:
		# Seed yaw from camera direction so smooth follow resumes correctly
		if xr_camera:
			_hud_yaw = xr_camera.global_rotation.y
		# HUD is already in world space (placed there by _on_interface_opened) — leave it
		# _update_smooth_hud will take over next frame
	else:
		# Instant: reparent back to camera
		if hud_mesh.get_parent():
			hud_mesh.get_parent().remove_child(hud_mesh)
		xr_camera.add_child(hud_mesh)
		hud_mesh.position = Vector3(_hud_lr_offset, _hud_height_offset, -_hud_distance)
		hud_mesh.rotation = Vector3.ZERO

	# Scale back down for HUD
	var aspect = float(hud_viewport.size.y) / float(hud_viewport.size.x)
	(hud_mesh.mesh as QuadMesh).size = Vector2(_hud_width, _hud_width * aspect)

	# Hide laser pointer and return to grab-range mode
	_menu_open = false
	if _laser_mesh and not _config_screen_open:
		_laser_mesh.visible = false


func _update_laser_pointer() -> void:
	if not hud_mesh or not _laser_mesh:
		return

	# Get the pointer controller (config dominant hand for UI)
	var controller = _get_controller(_config_dominant_hand)
	if not controller or not controller.get_is_active():
		return

	# Raycast from controller forward direction
	var ray_origin = controller.global_position
	var ray_dir = -controller.global_basis.z  # Controller forward = -Z

	# Intersect with the HUD quad plane
	var hit_pos = _ray_quad_intersection(ray_origin, ray_dir, hud_mesh)
	if hit_pos != Vector3.INF:
		# Convert 3D hit point to 2D viewport coordinates
		var local_pos = hud_mesh.global_transform.affine_inverse() * hit_pos
		var quad_size = (hud_mesh.mesh as QuadMesh).size

		# QuadMesh goes from -size/2 to +size/2
		var uv_x = (local_pos.x + quad_size.x / 2.0) / quad_size.x
		var uv_y = (-local_pos.y + quad_size.y / 2.0) / quad_size.y
		# Offset to compensate for controller alignment (tunable in config screen)
		uv_y += _menu_laser_uv_y
		uv_x += _menu_laser_uv_x

		if uv_x >= 0 and uv_x <= 1 and uv_y >= 0 and uv_y <= 1:
			# Map UV to screen coordinates
			var screen_pos = Vector2(
				uv_x * hud_viewport.size.x,
				uv_y * hud_viewport.size.y
			)
			_laser_screen_pos = screen_pos

			# Actually move the OS mouse cursor to the laser position.
			# This triggers hover effects in the game's UI system, which checks
			# Input.get_mouse_position() / Viewport.get_mouse_position().
			Input.warp_mouse(screen_pos)

			# Also inject mouse motion event for drag support
			var motion = InputEventMouseMotion.new()
			motion.position = screen_pos
			motion.global_position = screen_pos
			motion.relative = Vector2.ZERO
			var mask := 0
			if _mouse_states.get(MOUSE_BUTTON_LEFT, false):
				mask |= 1
			if _mouse_states.get(MOUSE_BUTTON_RIGHT, false):
				mask |= 2
			motion.button_mask = mask
			Input.parse_input_event(motion)

			# Update laser length - stop 15cm before the quad to avoid clipping
			var dist = ray_origin.distance_to(hit_pos) - 0.15
			if dist > 0.1:
				(_laser_mesh.mesh as CylinderMesh).height = dist
				_laser_mesh.position.z = -dist / 2.0
				_laser_mesh.visible = true
			else:
				_laser_mesh.visible = false  # Too close, hide entirely
		else:
			_laser_screen_pos = Vector2(-1, -1)


func _ray_quad_intersection(ray_origin: Vector3, ray_dir: Vector3, quad: MeshInstance3D) -> Vector3:
	# Get the quad's plane (normal = quad's local Z axis in world space)
	var quad_normal = quad.global_basis.z.normalized()
	var quad_center = quad.global_position

	# Ray-plane intersection
	var denom = quad_normal.dot(ray_dir)
	if abs(denom) < 0.0001:
		return Vector3.INF  # Ray parallel to plane

	var t = quad_normal.dot(quad_center - ray_origin) / denom
	if t < 0:
		return Vector3.INF  # Hit behind ray origin

	return ray_origin + ray_dir * t


func _attach_rig_to_camera() -> void:
	if not game_camera or not xr_origin:
		return
	var parent = game_camera.get_parent()
	if parent:
		if xr_origin.get_parent():
			xr_origin.get_parent().remove_child(xr_origin)
		parent.add_child(xr_origin)
		var approx_head_height := 1.6
		var cam_pos = game_camera.global_position
		xr_origin.global_position = Vector3(cam_pos.x, cam_pos.y - approx_head_height, cam_pos.z)
		_last_game_cam_pos = cam_pos


func _sync_origin_to_game() -> void:
	if game_camera and is_instance_valid(game_camera) and xr_origin:
		var current_pos = game_camera.global_position
		var delta_pos = current_pos - _last_game_cam_pos
		if delta_pos.length() > 0.001:
			xr_origin.global_position += delta_pos
			_last_game_cam_pos = current_pos

		# Steer game camera toward controller aim via mouse injection
		if not _interface_open:
			_steer_game_camera_via_mouse()



func _steer_game_camera_via_mouse() -> void:
	# Steer game camera to match weapon barrel aim direction.
	var aim_controller = _get_controller(_get_weapon_hand())
	if not aim_controller or not aim_controller.get_is_active():
		return

	# Compute barrel direction: must match the aim_basis used in _sync_weapon_to_controller
	var aim_forward: Vector3
	var off_controller = _get_controller(_get_support_hand())
	if _support_grip_held and off_controller and off_controller.get_is_active():
		var hand_dist = aim_controller.global_position.distance_to(off_controller.global_position)
		if hand_dist > 0.1:
			aim_forward = (off_controller.global_position - aim_controller.global_position).normalized()
		else:
			aim_forward = -aim_controller.global_basis.z
	else:
		var rot_offset: float = _slot_grip_rotations.get(_weapon_slot, 0.0)
		var aim_basis = aim_controller.global_basis * Basis(Vector3.UP, deg_to_rad(180 + rot_offset))
		aim_forward = aim_basis.z
	# Convert to yaw/pitch
	var target_yaw = atan2(-aim_forward.x, -aim_forward.z)
	var target_pitch = asin(aim_forward.y)

	var game_yaw = game_camera.global_rotation.y
	var game_pitch = game_camera.global_rotation.x

	var yaw_error = fmod(target_yaw - game_yaw + PI, TAU) - PI
	var pitch_error = target_pitch - game_pitch

	if abs(yaw_error) < deg_to_rad(0.3) and abs(pitch_error) < deg_to_rad(0.3):
		return

	var mouse_sensitivity_estimate := 0.003
	var correction_strength := 0.8  # More aggressive for responsive aiming

	var mouse_dx = -(yaw_error * correction_strength) / mouse_sensitivity_estimate
	var mouse_dy = -(pitch_error * correction_strength) / mouse_sensitivity_estimate

	var event = InputEventMouseMotion.new()
	event.relative = Vector2(mouse_dx, mouse_dy)
	event.position = get_viewport().get_visible_rect().size / 2
	Input.parse_input_event(event)


func _process_input(delta: float) -> void:
	if _interface_open:
		# Release movement keys when in inventory
		_inject_key(KEY_W, false)
		_inject_key(KEY_S, false)
		_inject_key(KEY_A, false)
		_inject_key(KEY_D, false)
		return

	# --- Grip adjust mode: thumbsticks control offsets ---
	if _adjust_mode and _weapon_slot > 0:
		var changed := false
		var offset: Vector3 = _slot_grip_offsets[_weapon_slot]
		var rot: float = _slot_grip_rotations[_weapon_slot]
		if left_controller and left_controller.get_is_active():
			var left = left_controller.get_vector2("primary")
			if left.length() > thumbstick_deadzone:
				offset.x += left.x * ADJUST_SPEED * delta
				offset.y += left.y * ADJUST_SPEED * delta
				changed = true
		if right_controller and right_controller.get_is_active():
			var right = right_controller.get_vector2("primary")
			if right.length() > thumbstick_deadzone:
				offset.z += right.y * ADJUST_SPEED * delta
				rot += right.x * ADJUST_ROT_SPEED * delta
				changed = true
		if changed:
			_slot_grip_offsets[_weapon_slot] = offset
			_slot_grip_rotations[_weapon_slot] = rot
			print("[VR Mod] ADJUST slot ", _weapon_slot, ": x=", snapped(offset.x, 0.001), " y=", snapped(offset.y, 0.001), " z=", snapped(offset.z, 0.001), " rot=", snapped(rot, 0.1), "°")
		# Release movement keys and skip normal input
		_inject_key(KEY_W, false)
		_inject_key(KEY_S, false)
		_inject_key(KEY_A, false)
		_inject_key(KEY_D, false)
		return

	# --- Left thumbstick: Movement ---
	if left_controller and left_controller.get_is_active():
		var move_input = left_controller.get_vector2("primary")
		if move_input.length() > thumbstick_deadzone:
			var strength = (move_input.length() - thumbstick_deadzone) / (1.0 - thumbstick_deadzone)
			move_input = move_input.normalized() * strength

			if game_camera and is_instance_valid(game_camera) and xr_camera:
				var yaw_diff = xr_camera.global_rotation.y - game_camera.global_rotation.y
				move_input = move_input.rotated(yaw_diff)

			_inject_key(KEY_W, move_input.y > 0.3)
			_inject_key(KEY_S, move_input.y < -0.3)
			_inject_key(KEY_A, move_input.x < -0.3)
			_inject_key(KEY_D, move_input.x > 0.3)
		else:
			_inject_key(KEY_W, false)
			_inject_key(KEY_S, false)
			_inject_key(KEY_A, false)
			_inject_key(KEY_D, false)

	# --- Right thumbstick: Turn / Config scroll ---
	if right_controller and right_controller.get_is_active():
		var turn_input = right_controller.get_vector2("primary")
		if _config_screen_open:
			# Y axis scrolls the config panel
			if abs(turn_input.y) > thumbstick_deadzone:
				_scroll_config_panel(-turn_input.y * 600.0 * delta)
			_snap_turn_cooldown = false
		elif _scope_active and _scope_is_variable and _holster_state == HolsterState.DRAWN and abs(turn_input.y) > thumbstick_deadzone:
			# Variable zoom scope: directly change weapon rig zoomLevel
			if _scroll_cooldown <= 0.0 and abs(turn_input.y) > 0.6:
				_cycle_scope_zoom(1 if turn_input.y > 0 else -1)
				_scroll_cooldown = 0.3
		else:
			if abs(turn_input.x) > thumbstick_deadzone:
				if use_snap_turn:
					if not _snap_turn_cooldown and abs(turn_input.x) > 0.6:
						var angle = -snap_turn_degrees if turn_input.x > 0 else snap_turn_degrees
						xr_origin.rotate_y(deg_to_rad(angle))
						_snap_turn_cooldown = true
				else:
					xr_origin.rotate_y(deg_to_rad(-turn_input.x * smooth_turn_speed * delta))
			else:
				_snap_turn_cooldown = false


func _on_button_pressed(button_name: String, hand: String) -> void:
	# Resolve hand roles dynamically based on holster state
	var is_weapon_hand := (hand == _weapon_hand) if _holster_state != HolsterState.UNARMED else (hand == _config_dominant_hand)
	var is_support_hand := not is_weapon_hand

	match button_name:
		"trigger_click":
			if _config_screen_open:
				_inject_config_click(true)
			elif _interface_open:
				_inject_mouse_button(MOUSE_BUTTON_LEFT, true)
				_inject_action("left_mouse", true)
			else:
				# NVG zone: trigger above head toggles night vision
				var _trig_ctrl = _get_controller(hand)
				var _in_nvg = _trig_ctrl and _is_in_nvg_zone(_trig_ctrl.global_position) and _grabbed_object == null
				if _in_nvg and not (is_weapon_hand and _holster_state == HolsterState.DRAWN):
					_inject_mouse_button(MOUSE_BUTTON_XBUTTON1, true)
					_inject_mouse_button(MOUSE_BUTTON_XBUTTON1, false)
					_trig_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.4, 0.15, 0.0)
					print("[VR Mod] NVG toggled (trigger above head)")
				elif is_weapon_hand and _holster_state == HolsterState.DRAWN:
					# Weapon hand trigger = fire (only when weapon is raised/drawn)
					Input.action_press("fire", 1.0)
					Input.action_press("left_mouse", 1.0)
					_inject_action("fire", true)
					_inject_action("left_mouse", true)
					_inject_mouse_button(MOUSE_BUTTON_LEFT, true)
				elif is_support_hand and _holster_state in [HolsterState.DRAWN, HolsterState.LOWERED]:
					# Support hand trigger = reload or laser (drawn or lowered)
					if _support_grip_held:
						_inject_key(KEY_T, true)
						_inject_key(KEY_T, false)
						print("[VR Mod] LASER toggled (support trigger + grip)")
					else:
						_inject_action("reload", true)
						print("[VR Mod] RELOAD pressed (support trigger)")
		"grip_click":
			if _interface_open:
				_inject_mouse_button(MOUSE_BUTTON_RIGHT, true)
				_inject_action("context", true)
			elif _holster_cooldown > 0.0:
				print("[VR Mod] Grip blocked - holster cooldown (" + str(snappedf(_holster_cooldown, 0.01)) + "s remaining)")
			else:
				var ctrl = _get_controller(hand)
				var zone = _get_nearby_holster_zone(ctrl.global_position) if ctrl else 0
				match _holster_state:
					HolsterState.UNARMED:
						if zone > 0:
							_draw_weapon(hand, zone)
						else:
							_try_grab(hand)
					HolsterState.DRAWN:
						if hand == _weapon_hand:
							pass  # Already gripping weapon
						else:
							if zone > 0 and zone != _weapon_slot:
								# Support hand near different holster — holster current, draw new
								_holster_weapon()
								_draw_weapon(hand, zone)
							else:
								# Support hand grip = two-hand aim
								_support_grip_held = true
								print("[VR Mod] Support grip: two-hand aim ON")
					HolsterState.LOWERED:
						if zone > 0 and zone != _weapon_slot:
							# Near a different holster — holster old, draw new
							_holster_weapon()
							_draw_weapon(hand, zone)
						elif hand == _weapon_hand:
							# Same hand re-gripping — raise weapon
							_raise_weapon()
						else:
							# Different hand, no new holster — raise with original hand
							_raise_weapon()
							_support_grip_held = true
		"ax_button":  # A on right, X on left (physical mapping)
			if hand == "left":
				# X button: adjust mode when weapon drawn
				if _adjust_mode:
					# X again = discard changes and exit
					_slot_grip_offsets[_weapon_slot] = _adjust_saved_offset
					_slot_grip_rotations[_weapon_slot] = _adjust_saved_rotation
					_adjust_mode = false
					print("[VR Mod] === ADJUST MODE OFF (discarded) ===")
				elif _holster_state == HolsterState.DRAWN:
					_adjust_mode = true
					_adjust_saved_offset = _slot_grip_offsets[_weapon_slot]
					_adjust_saved_rotation = _slot_grip_rotations[_weapon_slot]
					print("[VR Mod] === ADJUST MODE ON (slot ", _weapon_slot, ") ===")
					print("[VR Mod] Left stick=X/Y, Right stick X=Z Y=Rotation")
					print("[VR Mod] A=Save, X=Discard")
				else:
					# X button when unarmed/lowered = toggle flashlight
					_inject_mouse_button(MOUSE_BUTTON_XBUTTON2, true)
					_inject_mouse_button(MOUSE_BUTTON_XBUTTON2, false)
					print("[VR Mod] FLASHLIGHT toggled (X button)")
			else:
				if _adjust_mode:
					_save_grip_config()
					_adjust_mode = false
					print("[VR Mod] === ADJUST MODE OFF (saved) ===")
				else:
					_inject_action("jump", true)
		"by_button":  # B on right, Y on left (physical mapping)
			if hand == "left":
				_inject_action("interface", true)  # Y = toggle inventory
			else:
				_inject_action("interact", true)
		"menu_button":
			_inject_action("escape", true)
		"primary_click":
			if hand == "left":
				_inject_action("sprint", true)
			else:
				_inject_action("crouch", true)


func _on_button_released(button_name: String, hand: String) -> void:
	var is_weapon_hand := (hand == _weapon_hand) if _holster_state != HolsterState.UNARMED else (hand == _config_dominant_hand)
	var is_support_hand := not is_weapon_hand

	match button_name:
		"trigger_click":
			if _config_screen_open:
				_inject_config_click(false)
			elif _interface_open:
				_inject_mouse_button(MOUSE_BUTTON_LEFT, false)
				_inject_action("left_mouse", false)
			else:
				if is_weapon_hand:
					Input.action_release("fire")
					Input.action_release("left_mouse")
					_inject_action("fire", false)
					_inject_action("left_mouse", false)
					_inject_mouse_button(MOUSE_BUTTON_LEFT, false)
				else:
					_inject_action("reload", false)
		"grip_click":
			if _interface_open:
				_inject_mouse_button(MOUSE_BUTTON_RIGHT, false)
				_inject_action("context", false)
			else:
				if hand == _weapon_hand and _holster_state == HolsterState.DRAWN:
					if not _weapon_loaded:
						# Slot was empty — revert to unarmed regardless of position
						_holster_weapon()
					else:
						# Weapon hand releasing grip — check holster zone
						var ctrl = _get_controller(hand)
						var zone = _get_nearby_holster_zone(ctrl.global_position) if ctrl else 0
						if zone == _weapon_slot:
							# Near own holster zone — holster completely
							_holster_weapon()
						else:
							# Not near holster — lower weapon
							_lower_weapon()
				elif is_support_hand:
					_support_grip_held = false
					print("[VR Mod] Support grip: two-hand aim OFF")
				# Always try to drop grabbed objects from this hand
				if _grab_hand == hand:
					_drop_grabbed()
		"ax_button":
			if hand == "right":
				_inject_action("jump", false)
		"by_button":
			if hand == "left":
				_inject_action("interface", false)
			else:
				_inject_action("interact", false)
		"menu_button":
			_inject_action("escape", false)
		"primary_click":
			if hand == "left":
				_inject_action("sprint", false)
			else:
				_inject_action("crouch", false)


var _key_states := {}
var _mouse_states := {}

func _inject_key(keycode: int, pressed: bool) -> void:
	var current = _key_states.get(keycode, false)
	if current == pressed:
		return
	_key_states[keycode] = pressed
	var event = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _inject_mouse_button(button: int, pressed: bool) -> void:
	var current = _mouse_states.get(button, false)
	if current == pressed:
		return
	_mouse_states[button] = pressed
	var event = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	# Use laser pointer position when in inventory, center of screen otherwise
	if _interface_open and _laser_screen_pos.x >= 0:
		event.position = _laser_screen_pos
	else:
		event.position = get_viewport().get_visible_rect().size / 2
	# Set button_mask - required for proper mouse event processing
	var mask := 0
	for btn in _mouse_states:
		if _mouse_states[btn]:
			match btn:
				MOUSE_BUTTON_LEFT: mask |= MOUSE_BUTTON_MASK_LEFT
				MOUSE_BUTTON_RIGHT: mask |= MOUSE_BUTTON_MASK_RIGHT
				MOUSE_BUTTON_MIDDLE: mask |= MOUSE_BUTTON_MASK_MIDDLE
	event.button_mask = mask
	# Send through BOTH paths to maximize chances of game receiving it
	Input.parse_input_event(event)
	get_viewport().push_input(event, false)


func _inject_scroll(direction: int) -> void:
	# direction: 1 = scroll up (next weapon), -1 = scroll down (prev weapon)
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP if direction > 0 else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	event.position = get_viewport().get_visible_rect().size / 2
	Input.parse_input_event(event)
	# Scroll events need immediate release
	var release = InputEventMouseButton.new()
	release.button_index = event.button_index
	release.pressed = false
	release.position = event.position
	Input.parse_input_event(release)


func _inject_action(action_name: String, pressed: bool, strength: float = 1.0) -> void:
	if not InputMap.has_action(action_name):
		if pressed:
			print("[VR Mod] Action not found: ", action_name)
		return
	var event = InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	event.strength = strength if pressed else 0.0
	Input.parse_input_event(event)


func _deep_camera_debug() -> void:
	# Deep scan of game_camera subtree to find where weapon nodes appear
	if not game_camera or not is_instance_valid(game_camera):
		return

	var snapshot = []
	var log_lines = []
	_snapshot_tree(game_camera, 0, 12, snapshot, log_lines)

	# Compare with previous snapshot to detect changes
	if snapshot != _last_cam_child_snapshot:
		# Something changed! Log it to file (append mode)
		var dump_path = OS.get_executable_path().get_base_dir() + "/vr_mod_debug.log"
		var f = FileAccess.open(dump_path, FileAccess.READ_WRITE)
		if not f:
			f = FileAccess.open(dump_path, FileAccess.WRITE)
		if f:
			f.seek_end(0)
			f.store_line("")
			f.store_line("=== Camera Subtree Snapshot (changed!) ===")
			f.store_line("Time: " + str(Time.get_ticks_msec()) + "ms")
			f.store_line("game_camera.current: " + str(game_camera.current))
			f.store_line("game_camera.global_pos: " + str(game_camera.global_position))
			f.store_line("Total nodes in subtree: " + str(snapshot.size()))
			f.store_line("")
			for line in log_lines:
				f.store_line(line)
			f.store_line("")
			f.store_line("=== MeshInstance3D within 5m of camera ===")
			var near_meshes = []
			_find_meshes_near_to_list(get_tree().root, game_camera.global_position, 5.0, 0, 15, near_meshes)
			for entry in near_meshes:
				f.store_line(entry)
			if near_meshes.is_empty():
				f.store_line("(none found)")
			f.close()

		print("[VR Mod] CAMERA TREE CHANGED! Nodes: ", snapshot.size(), " (logged to vr_mod_debug.log)")
		_last_cam_child_snapshot = snapshot
	else:
		# No change, just print summary
		var mgr = game_camera.get_node_or_null("Manager")
		var mgr_count = mgr.get_child_count() if mgr else -1
		print("[VR Mod] cam_tree: ", snapshot.size(), " nodes, mgr_children=", mgr_count, " cam.current=", game_camera.current)


func _snapshot_tree(node: Node, depth: int, max_depth: int, snapshot: Array, log_lines: Array) -> void:
	var indent = "  ".repeat(depth)
	var info = node.name + " (" + node.get_class() + ")"
	if node is Node3D:
		info += " pos=" + str(node.position)
		info += " gpos=" + str(node.global_position)
		info += " vis=" + str(node.visible)
	if node is MeshInstance3D:
		info += " mesh=" + str(node.mesh.get_class() if node.mesh else "null")
		info += " layers=" + str(node.layers)
		if node.mesh:
			info += " surf_count=" + str(node.mesh.get_surface_count())
	if node is Skeleton3D:
		info += " bones=" + str((node as Skeleton3D).get_bone_count())
	snapshot.append(node.name + ":" + node.get_class() + ":" + str(node.get_child_count()))
	log_lines.append(indent + info + " [" + str(node.get_child_count()) + " children]")

	if depth < max_depth:
		for child in node.get_children():
			_snapshot_tree(child, depth + 1, max_depth, snapshot, log_lines)


func _find_all_typed_under(node: Node, type_name: String, depth: int, max_depth: int, result: Array) -> void:
	if node.get_class() == type_name or node.is_class(type_name):
		var info = str(node.get_path()) + " (" + node.get_class() + ")"
		if node is Node3D:
			info += " vis=" + str(node.visible) + " gpos=" + str(node.global_position)
		if node is MeshInstance3D:
			info += " layers=" + str(node.layers)
			if node.mesh:
				info += " mesh=" + node.mesh.get_class() + " surfs=" + str(node.mesh.get_surface_count())
			else:
				info += " mesh=null"
		result.append(info)
	if depth < max_depth:
		for child in node.get_children():
			_find_all_typed_under(child, type_name, depth + 1, max_depth, result)


func _find_meshes_near_to_list(node: Node, pos: Vector3, radius: float, depth: int, max_depth: int, result: Array) -> void:
	if node == xr_origin:
		return
	if node is MeshInstance3D:
		var dist = node.global_position.distance_to(pos)
		if dist < radius:
			var info = str(node.get_path()) + " dist=" + str(snapped(dist, 0.01))
			info += " vis=" + str(node.visible) + " mesh=" + str(node.mesh.get_class() if node.mesh else "null")
			info += " layers=" + str(node.layers)
			result.append(info)
	if depth < max_depth:
		for child in node.get_children():
			_find_meshes_near_to_list(child, pos, radius, depth + 1, max_depth, result)


var _post_scroll_timer := -1.0

func _create_hand_model(controller: XRController3D, model_name: String) -> void:
	var hand = Node3D.new()
	hand.name = model_name

	# Palm - flat box
	var palm_mesh = MeshInstance3D.new()
	palm_mesh.name = "Palm"
	var palm = BoxMesh.new()
	palm.size = Vector3(0.08, 0.03, 0.10)
	palm_mesh.mesh = palm
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.55, 0.4)  # Skin tone
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	palm_mesh.material_override = mat
	palm_mesh.position = Vector3(0, 0, -0.05)
	hand.add_child(palm_mesh)

	# Fingers - smaller box extending forward
	var fingers_mesh = MeshInstance3D.new()
	fingers_mesh.name = "Fingers"
	var fingers = BoxMesh.new()
	fingers.size = Vector3(0.07, 0.02, 0.07)
	fingers_mesh.mesh = fingers
	fingers_mesh.material_override = mat
	fingers_mesh.position = Vector3(0, 0, -0.13)
	hand.add_child(fingers_mesh)

	# Thumb - small box to the side
	var thumb_mesh = MeshInstance3D.new()
	thumb_mesh.name = "Thumb"
	var thumb = BoxMesh.new()
	thumb.size = Vector3(0.025, 0.025, 0.05)
	thumb_mesh.mesh = thumb
	thumb_mesh.material_override = mat
	var side = 1.0 if "Left" in model_name else -1.0
	thumb_mesh.position = Vector3(side * 0.045, 0, -0.06)
	hand.add_child(thumb_mesh)

	# Roll 90° and move back toward controller position
	hand.rotation.z = deg_to_rad(90)
	hand.position = Vector3(0, 0, 0.20)
	controller.add_child(hand)
	print("[VR Mod] Created hand model: ", model_name)


func _update_hand_visibility() -> void:
	var left_hand = left_controller.get_node_or_null("LeftHandModel")
	var right_hand = right_controller.get_node_or_null("RightHandModel")

	# Check if the game actually has a weapon model visible
	var game_has_weapon := false
	if game_camera and is_instance_valid(game_camera):
		var mgr = game_camera.get_node_or_null("Manager")
		if mgr and mgr.get_child_count() > 0:
			game_has_weapon = true

	# Hide weapon hand only when the game actually has a weapon model present.
	# This prevents hands vanishing during the draw-pending window on empty slots.
	# Always show VR hand models — the game's first-person arm mesh is
	# hidden separately via _hide_arms_in_subtree on the weapon rig.
	if left_hand: left_hand.visible = true
	if right_hand: right_hand.visible = true

	# Laser pointer: grab range when UNARMED, interact range when LOWERED (weapon hand)
	if _laser_mesh and not _menu_open and not _config_screen_open:
		var show_laser := false
		var laser_hand := _config_dominant_hand

		if _holster_state == HolsterState.UNARMED and _grabbed_object == null:
			show_laser = true
			laser_hand = _config_dominant_hand
		elif _holster_state == HolsterState.LOWERED:
			show_laser = true
			laser_hand = _weapon_hand

		if show_laser:
			# Reparent laser to correct controller if needed
			var target_ctrl = _get_controller(laser_hand)
			if target_ctrl and _laser_mesh.get_parent() != target_ctrl:
				_laser_mesh.get_parent().remove_child(_laser_mesh)
				target_ctrl.add_child(_laser_mesh)
				_laser_mesh.rotation.x = deg_to_rad(90)

			# Check what the ray is pointing at (loose item on layer 4)
			var grab_ray := _grab_ray_right if laser_hand == "right" else _grab_ray_left
			var pointing_at_grabbable := false
			if grab_ray and grab_ray.is_colliding():
				var c = grab_ray.get_collider()
				pointing_at_grabbable = c is RigidBody3D and (c.collision_layer & 4) != 0
			var mat := _laser_mesh.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = Color(0.1, 1.0, 0.2, 0.7) if pointing_at_grabbable else Color(1.0, 0.2, 0.1, 0.6)
			var cyl := _laser_mesh.mesh as CylinderMesh
			if cyl:
				cyl.height = 1.0
				_laser_mesh.position.z = -0.5
		_laser_mesh.visible = show_laser



func _try_grab(hand: String) -> void:
	if _grabbed_object:
		return  # Already holding something

	var grab_ray = _grab_ray_right if hand == "right" else _grab_ray_left
	if not grab_ray or not grab_ray.is_colliding():
		return

	var collider = grab_ray.get_collider()
	if not collider:
		return

	# Only grab loose items: RigidBody3D with collision layer 4 (bit 2)
	if not (collider is RigidBody3D and (collider.collision_layer & 4) != 0):
		return

	var controller = _get_controller(hand)
	if not controller:
		return

	_grabbed_object = collider
	_grab_hand = hand
	_throw_samples.clear()
	# No freeze — override position each frame at process_priority=1000
	print("[VR Mod] Grabbed: ", collider.name, " with ", hand, " hand")


func _drop_grabbed() -> void:
	if not _grabbed_object:
		return

	# If the grabbing hand is behind the shoulder, add to inventory instead of dropping
	var ctrl = _get_controller(_grab_hand) if _grab_hand != "" else null
	if ctrl and _is_in_bag_zone(ctrl.global_position):
		_pickup_to_inventory()
		return

	# Compute throw velocity from the last 3 samples only (captures peak, not deceleration)
	var throw_vel := Vector3.ZERO
	if _throw_samples.size() >= 2:
		var start_idx = max(0, _throw_samples.size() - 3)
		var oldest = _throw_samples[start_idx]
		var newest = _throw_samples[-1]
		var dt: float = newest[1] - oldest[1]
		if dt > 0.001:
			throw_vel = (newest[0] - oldest[0]) / dt * 1.5

	if _grabbed_object is RigidBody3D:
		var rb := _grabbed_object as RigidBody3D
		rb.sleeping = false
		rb.linear_damp = 0.0
		rb.linear_velocity = throw_vel
		rb.angular_velocity = Vector3.ZERO

	print("[VR Mod] Dropped: ", _grabbed_object.name, " vel=", throw_vel)
	_grabbed_object = null
	_grab_hand = ""
	_grab_offset = Vector3.ZERO
	_throw_samples.clear()


func _pickup_to_inventory() -> void:
	if not _grabbed_object or not is_instance_valid(_grabbed_object):
		return

	print("[VR Mod] INVENTORY PICKUP: ", _grabbed_object.name)

	# Haptic confirmation
	var ctrl = _get_controller(_grab_hand) if _grab_hand != "" else null
	if ctrl:
		ctrl.trigger_haptic_pulse("haptic", 0.0, 1.0, 0.25, 0.0)

	var item := _grabbed_object
	_grabbed_object = null
	_grab_hand = ""
	_grab_offset = Vector3.ZERO
	_throw_samples.clear()
	_grab_in_bag_zone = false

	# Call the game's Interact method directly (Pickup.gd script)
	if item.has_method("Interact"):
		item.call("Interact")
	else:
		# Fallback: drop at feet
		if xr_camera and is_instance_valid(xr_camera):
			var fwd := -xr_camera.global_basis.z
			fwd.y = 0.0
			if fwd.length_squared() > 0.001:
				fwd = fwd.normalized()
			item.global_position = xr_camera.global_position + Vector3(0, -1.5, 0) + fwd * 0.3
		if item is RigidBody3D:
			var rb := item as RigidBody3D
			rb.sleeping = false
			rb.linear_damp = 0.0
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO


func _update_grabbed() -> void:
	if not _grabbed_object or not is_instance_valid(_grabbed_object):
		_grabbed_object = null
		_grab_hand = ""
		return

	var controller = _get_controller(_grab_hand) if _grab_hand != "" else _get_controller(_config_dominant_hand)
	if not controller or not controller.get_is_active():
		return

	var hand_model_name = "RightHandModel" if _grab_hand == "right" else "LeftHandModel"
	var hand_model = controller.get_node_or_null(hand_model_name)
	var hand_pos: Vector3
	if hand_model:
		hand_pos = hand_model.global_position
		_grabbed_object.global_position = hand_pos
		_grabbed_object.global_basis = hand_model.global_basis
	else:
		hand_pos = controller.global_position
		_grabbed_object.global_position = hand_pos

	# Zero physics velocity each frame so gravity doesn't accumulate while held
	if _grabbed_object is RigidBody3D:
		var rb := _grabbed_object as RigidBody3D
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO

	# Track hand position over time for throw velocity
	var now := Time.get_ticks_msec() / 1000.0
	_throw_samples.append([hand_pos, now])
	if _throw_samples.size() > 8:
		_throw_samples.pop_front()


var _invis_mat: StandardMaterial3D = null

func _hide_arms_in_subtree(node: Node) -> void:
	if node is MeshInstance3D and node.name == "Arms":
		if not _invis_mat:
			_invis_mat = StandardMaterial3D.new()
			_invis_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_invis_mat.albedo_color = Color(0, 0, 0, 0)
		var mesh := node as MeshInstance3D
		# Hide only surfaces 0 and 1 (left/right arm). Surface 2+ are hands — leave visible.
		for i in min(2, mesh.mesh.get_surface_count()):
			mesh.set_surface_override_material(i, _invis_mat)
		return  # Arms found, no need to go deeper
	for child in node.get_children():
		_hide_arms_in_subtree(child)


func _sync_weapon_to_controller() -> void:
	if not game_camera or not is_instance_valid(game_camera):
		return
	if _interface_open:
		return

	var mgr = game_camera.get_node_or_null("Manager")
	if not mgr or mgr.get_child_count() == 0:
		return

	var weapon_rig = mgr.get_child(0)
	if not weapon_rig or not weapon_rig is Node3D:
		return

	# Only sync when weapon is equipped (DRAWN or LOWERED)
	if _holster_state == HolsterState.UNARMED:
		return

	var controller = _get_controller(_get_weapon_hand())
	if not controller or not controller.get_is_active():
		return

	# Two-hand aiming: only when support grip is held
	var off_controller = _get_controller(_get_support_hand())
	var use_two_hand = false
	var aim_basis: Basis

	if _support_grip_held and off_controller and off_controller.get_is_active():
		var hand_dist = controller.global_position.distance_to(off_controller.global_position)
		if hand_dist > 0.1:
			use_two_hand = true
			# Forward = from dominant hand toward off-hand
			var forward = (off_controller.global_position - controller.global_position).normalized()
			var up = controller.global_basis.y
			var right_vec = up.cross(forward).normalized()
			var corrected_up = forward.cross(right_vec).normalized()
			aim_basis = Basis(right_vec, corrected_up, -forward)
			aim_basis = aim_basis * Basis(Vector3.UP, deg_to_rad(180))

	if not use_two_hand:
		var rot_offset: float = _slot_grip_rotations.get(_weapon_slot, 0.0)
		aim_basis = controller.global_basis * Basis(Vector3.UP, deg_to_rad(180 + rot_offset))

	weapon_rig.global_basis = aim_basis
	var local_offset: Vector3 = _slot_grip_offsets.get(_weapon_slot, Vector3(0, 0.15, -0.20))
	weapon_rig.global_position = controller.global_position + aim_basis * local_offset

	# Hide all arm surfaces on every weapon type (guns, knives, grenades)
	_hide_arms_in_subtree(weapon_rig)

	# Fix reticle parallax for VR (once per sight mesh)
	_fix_reticle_parallax(weapon_rig)

	# Scope PIP: detect and activate game's scope SubViewport, position camera
	_setup_scope_pip(weapon_rig)
	_update_scope_camera()


func _log(msg: String) -> void:
	var path = OS.get_executable_path().get_base_dir() + "/vr_mod_debug.log"
	var f = FileAccess.open(path, FileAccess.READ_WRITE)
	if not f:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.seek_end(0)
		f.store_line(msg)
		f.close()


func _fix_reticle_parallax(weapon_rig: Node3D) -> void:
	# VR parallax fix: the game's Reticle shader uses normalize(reticlePosition)+NORMAL
	# for UV, which is an approximation that breaks in stereo VR. Replace with a proper
	# ray-plane intersection (Addmix collimator method) that uses only rotation matrices
	# (same for both eyes) and the per-eye VIEW direction for correct collimation.
	var skel = _find_node_by_class(weapon_rig, "Skeleton3D")
	if not skel:
		return
	var attachments = skel.get_node_or_null("Attachments")
	if not attachments:
		return
	for child in attachments.get_children():
		if not child is Node3D or not child.visible:
			continue
		_patch_reticle_shader(child)


func _patch_reticle_shader(node: Node) -> void:
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		var inst_id = mi.get_instance_id()
		if _fixed_reticle_instances.has(inst_id):
			return
		if not mi.mesh:
			return
		var found_reticle := false
		for s in range(mi.mesh.get_surface_count()):
			var mat = mi.get_active_material(s)
			if not (mat is ShaderMaterial and mat.shader and "Reticle" in mat.shader.resource_path):
				continue
			found_reticle = true
			var code: String = mat.shader.code
			if "vr_reticle_fix" in code:
				continue
			# Replace the reticle UV computation in the fragment shader with a
			# VR-compatible ray-plane intersection. Uses mat3() (rotation only) of
			# VIEW_MATRIX and MODEL_MATRIX — identical for both eyes. The per-eye
			# VIEW direction provides correct collimated dot shift per eye.
			var old_frag = "vec3 reticleOffset = normalize(reticlePosition) + NORMAL;\n\tvec2 reticleUV = (reticleOffset.xy / size) * vec2(1.0, -1.0);"
			var new_frag = "// vr_reticle_fix: ray-plane intersection for VR collimation\n\tmat3 _mvr = mat3(VIEW_MATRIX[0].xyz, VIEW_MATRIX[1].xyz, VIEW_MATRIX[2].xyz) * mat3(MODEL_MATRIX[0].xyz, MODEL_MATRIX[1].xyz, MODEL_MATRIX[2].xyz);\n\tvec3 _sn = _mvr * vec3(0.0, 0.0, -1.0);\n\tvec3 _su = _mvr * vec3(1.0, 0.0, 0.0);\n\tvec3 _sv = _mvr * vec3(0.0, 1.0, 0.0);\n\tvec3 _vp = VIEW / dot(VIEW, _sn);\n\tvec2 reticleUV = vec2(-dot(_vp, _su), dot(_vp, _sv)) / (-size);"
			var patched = code.replace(old_frag, new_frag)
			if patched == code:
				_log("reticle: WARNING — fragment target not found")
				var idx = code.find("reticleOffset")
				if idx >= 0:
					_log("reticle: actual code: " + code.substr(idx, 120))
				continue
			var new_shader = Shader.new()
			new_shader.code = patched
			var new_mat = ShaderMaterial.new()
			new_mat.shader = new_shader
			for param in mat.shader.get_shader_uniform_list():
				var val = mat.get_shader_parameter(param["name"])
				if val != null:
					new_mat.set_shader_parameter(param["name"], val)
			mi.set_surface_override_material(s, new_mat)
			_log("reticle: patched fragment surf=" + str(s) + " on " + mi.name)
		if found_reticle:
			_fixed_reticle_instances[inst_id] = true
	for child in node.get_children():
		_patch_reticle_shader(child)


func _find_node_by_class(root: Node, class_name_str: String) -> Node:
	if root.get_class() == class_name_str or root.is_class(class_name_str):
		return root
	for child in root.get_children():
		var found = _find_node_by_class(child, class_name_str)
		if found:
			return found
	return null


# ── NVG overlay shader ─────────────────────────────────────────────────────

const NVG_OVERLAY_SHADER := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_test_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D mono_tex : filter_linear;
uniform bool use_mono = false;
uniform vec4 tint : source_color = vec4(0.47, 0.67, 0.51, 1.0);
uniform float brightness = 2.0;
uniform float noise_intensity = 0.15;
uniform float vignette_strength = 0.8;
uniform float vignette_radius = 0.9;
uniform float time_val = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv;
	vec3 col;
	if (use_mono) {
		uv = UV;
		col = texture(mono_tex, uv).rgb;
	} else {
		uv = SCREEN_UV;
		col = texture(screen_tex, uv).rgb;
	}
	col *= brightness;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = vec3(lum) * tint.rgb;
	float n = hash(uv * 500.0 + vec2(time_val * 10.0, 0.0));
	col += (n - 0.5) * noise_intensity;
	float dist = length(uv - 0.5) * 2.0;
	float vig = smoothstep(vignette_radius, vignette_radius - vignette_strength, dist);
	col *= vig;
	ALBEDO = col;
	ALPHA = 1.0;
}
"""


# ── Scope PIP system — hijack game's SubViewport + Camera for VR ─────────

const SCOPE_PIP_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform sampler2D scope_texture : source_color;
uniform sampler2D reticle : source_color;
uniform float intensity = 5.0;
uniform float scope_depth = 1.0;
uniform float scope_inner_radius : hint_range(0.0, 1.0) = 0.7;
uniform float scope_fade_size = 0.03;
uniform float scope_parallax_factor : hint_range(0.0, 0.3) = 0.1;
uniform float eyebox_position = 0.40;
uniform float eyebox_tolerance = 0.08;
uniform float eyebox_fade_distance = 0.15;
uniform float shadow_inner_radius : hint_range(0.0, 1.0) = 1.0;
uniform float shadow_fade_factor = 0.2;
uniform float shadow_movement_factor : hint_range(0.5, 1.0) = 1.0;
uniform float reticle_scale = 1.0;

varying vec3 view;

void vertex() {
	view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz - (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

void fragment() {
	float eye_dist = length(NODE_POSITION_WORLD - CAMERA_POSITION_WORLD);
	vec3 view_dir = normalize(normalize(-VERTEX + EYE_OFFSET) * mat3(TANGENT, -BINORMAL, NORMAL));

	// Depth UV — pushes the scope view deeper into the tube
	vec2 depth_uv = vec2(1.0 - UV.x, UV.y) - view_dir.xy * (scope_depth * 2.0);
	depth_uv = (depth_uv - vec2(0.5)) * 0.5 + vec2(0.5);

	vec3 col = texture(scope_texture, depth_uv).rgb;

	// Scope shadow — shifts with eye misalignment
	float delta = eye_dist - eyebox_position;
	vec2 eye_offset = view_dir.xy / -shadow_movement_factor;
	vec2 shifted_uv = UV - eye_offset;
	float shadow_dist = length((shifted_uv - vec2(0.5)) * 2.0);
	float fade_near = smoothstep(-eyebox_tolerance, -eyebox_tolerance - eyebox_fade_distance, delta);
	float fade_far = smoothstep(eyebox_tolerance, eyebox_tolerance + eyebox_fade_distance, delta);
	float distance_fade = max(fade_near, fade_far);
	float dynamic_radius = mix(0.0, shadow_inner_radius, 1.0 - distance_fade);
	float shadow_inner = dynamic_radius - shadow_fade_factor;
	float shadow = smoothstep(shadow_inner, dynamic_radius, shadow_dist);
	col = mix(col, vec3(0.0), shadow);

	// Scope edge fade — darkens at the very edge of the view circle
	float edge_dist = length(depth_uv - vec2(0.5));
	float fade_end = scope_inner_radius / 2.0;
	float fade_start = fade_end - scope_fade_size;
	col = mix(col, vec3(0.0), smoothstep(fade_start, fade_end, edge_dist));

	// Reticle overlay — fixed on the glass, scaled by zoom level
	vec2 ret_uv = (UV - vec2(0.5)) / reticle_scale + vec2(0.5);
	vec4 ret = texture(reticle, ret_uv);
	// Hide reticle outside 0-1 UV range (when zoomed in past texture edge)
	float in_bounds = step(0.0, ret_uv.x) * step(ret_uv.x, 1.0) * step(0.0, ret_uv.y) * step(ret_uv.y, 1.0);
	ALBEDO = mix(col, ret.rgb * intensity, ret.a * in_bounds);
}
"""

func _setup_scope_pip(weapon_rig: Node3D) -> void:
	if _scope_active and _scope_weapon_slot == _weapon_slot:
		return
	_cleanup_scope()
	var skel = _find_node_by_class(weapon_rig, "Skeleton3D")
	if not skel:
		return
	var attachments = skel.get_node_or_null("Attachments")
	if not attachments:
		return
	for child in attachments.get_children():
		if not child is Node3D or not child.visible:
			continue
		var game_vp = child.get_node_or_null("Viewport")
		if not game_vp or not (game_vp is SubViewport):
			continue
		# Found a visible scope attachment with a SubViewport — it's a zoom scope
		var mesh_node = child.get_node_or_null("Mesh")
		if not mesh_node or not (mesh_node is MeshInstance3D):
			continue
		var mi = mesh_node as MeshInstance3D
		if not mi.mesh:
			continue
		_scope_attachment = child
		_scope_lens_mesh = mi
		_scope_weapon_slot = _weapon_slot
		_scope_active = true
		# Detect variable zoom capability and build per-level FOV/reticle arrays
		var att_data = child.get("attachmentData")
		_scope_is_variable = att_data != null and att_data.get("variable") == true
		if _scope_is_variable and att_data:
			var ret_sizes = att_data.get("reticleSize")  # Vector3 with per-level sizes
			if ret_sizes and ret_sizes is Vector3:
				var num_levels := 3
				_scope_zoom_fovs.clear()
				_scope_zoom_reticle_scales.clear()
				# Base reticle size is level 0 (widest zoom)
				var base_size: float = ret_sizes.x
				for i in range(num_levels):
					var s: float = [ret_sizes.x, ret_sizes.y, ret_sizes.z][i]
					# Reticle scale: how much bigger the reticle appears vs level 0
					_scope_zoom_reticle_scales.append(s / base_size if base_size > 0.0 else 1.0)
					# FOV: inversely proportional to magnification (reticle ratio)
					# Use game camera FOV at default zoom as reference
					_scope_zoom_fovs.append(0.0)  # Will be filled after reading game cam FOV
			# Initialize zoom index from game's current zoom level
			var wr_zoom = weapon_rig.get("zoomLevel")
			if wr_zoom != null:
				_scope_zoom_index = clampi(int(wr_zoom), 0, _scope_zoom_fovs.size() - 1)
			else:
				_scope_zoom_index = 0
		# Create our own SubViewport + Camera if not already done
		if not _scope_vp_created:
			_scope_viewport = SubViewport.new()
			_scope_viewport.name = "VRScopeVP"
			_scope_viewport.size = Vector2i(512, 512)
			_scope_viewport.transparent_bg = false
			_scope_viewport.disable_3d = false
			_scope_viewport.world_3d = get_viewport().world_3d
			add_child(_scope_viewport)
			_scope_camera = Camera3D.new()
			_scope_camera.name = "ScopeCamera"
			_scope_camera.fov = 3.0
			_scope_camera.near = 0.05
			_scope_camera.far = 4000.0
			_scope_viewport.add_child(_scope_camera)
			_scope_vp_created = true
			_log("scope: created own SubViewport + Camera, world_3d=" + str(_scope_viewport.world_3d))
		# Read FOV from the game's scope camera
		var game_cam: Camera3D = null
		for vp_child in game_vp.get_children():
			if vp_child is Camera3D:
				game_cam = vp_child as Camera3D
				break
		var scope_fov := 3.0
		if game_cam:
			scope_fov = game_cam.fov
		if _scope_is_variable and _scope_zoom_fovs.size() > 0 and _scope_zoom_reticle_scales.size() > 0:
			# Derive per-level FOVs from game camera FOV and reticle size ratios
			# Game camera FOV corresponds to _scope_zoom_index (current zoomLevel)
			var base_scale: float = _scope_zoom_reticle_scales[_scope_zoom_index] if _scope_zoom_index < _scope_zoom_reticle_scales.size() else 1.0
			for i in range(_scope_zoom_fovs.size()):
				# FOV is inversely proportional to magnification ratio
				var ratio: float = _scope_zoom_reticle_scales[i] / base_scale if base_scale > 0.0 else 1.0
				_scope_zoom_fovs[i] = scope_fov / ratio
			_scope_camera.fov = _scope_zoom_fovs[_scope_zoom_index]
			_log("scope: variable zoom fovs=" + str(_scope_zoom_fovs) + " reticle_scales=" + str(_scope_zoom_reticle_scales) + " index=" + str(_scope_zoom_index))
		else:
			_scope_camera.fov = scope_fov
		# Re-enable rendering (may have been disabled by cleanup)
		_scope_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# Disable game's scope viewport to save perf
		(game_vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
		# Build PIP shader + material
		var shader = Shader.new()
		shader.code = SCOPE_PIP_SHADER
		# Find the scope lens surface (has "reticle" uniform AND "scope" = true)
		_scope_overridden_surfaces.clear()
		var patched_count := 0
		for s in range(mi.mesh.get_surface_count()):
			var mat = mi.get_active_material(s)
			if not (mat is ShaderMaterial) or not mat.shader:
				continue
			var has_reticle := false
			var scope_flag = false
			for param in mat.shader.get_shader_uniform_list():
				if param["name"] == "reticle":
					has_reticle = true
				if param["name"] == "scope":
					scope_flag = true
			if not has_reticle:
				continue
			# Only patch the main scope lens (scope=true), not mini red dots (scope=false)
			if scope_flag:
				var scope_val = mat.get_shader_parameter("scope")
				if not scope_val:
					continue
			# This is the scope lens surface — replace with PIP+reticle combo
			_scope_overridden_surfaces.append({"surf": s, "original": mat})
			var pip_mat = ShaderMaterial.new()
			pip_mat.shader = shader
			pip_mat.set_shader_parameter("scope_texture", _scope_viewport.get_texture())
			# Copy reticle uniforms from original material
			var reticle_tex = mat.get_shader_parameter("reticle")
			if reticle_tex:
				pip_mat.set_shader_parameter("reticle", reticle_tex)
			var ret_intensity = mat.get_shader_parameter("intensity")
			if ret_intensity != null:
				pip_mat.set_shader_parameter("intensity", ret_intensity)
			mi.set_surface_override_material(s, pip_mat)
			patched_count += 1
			_log("scope: patched lens surf " + str(s) + " scope_flag=" + str(scope_flag))
		_log("scope: activated on " + child.name + " patched=" + str(patched_count) + " fov=" + str(scope_fov))
		return


func _update_scope_camera() -> void:
	if not _scope_active or not _scope_camera or not is_instance_valid(_scope_camera):
		_scope_active = false
		return
	if not _scope_attachment or not is_instance_valid(_scope_attachment):
		_scope_active = false
		return
	# Position scope camera at the scope, looking along weapon barrel
	if not game_camera or not is_instance_valid(game_camera):
		return
	var mgr = game_camera.get_node_or_null("Manager")
	if not mgr or mgr.get_child_count() == 0:
		return
	var weapon_rig = mgr.get_child(0)
	if not weapon_rig:
		return
	var scope_pos = _scope_attachment.global_position
	# Weapon rig basis has 180° Y flip, so +Z is barrel forward
	var barrel_forward = weapon_rig.global_basis.z
	var barrel_up = weapon_rig.global_basis.y
	_scope_camera.global_position = scope_pos
	_scope_camera.look_at(scope_pos + barrel_forward * 100.0, barrel_up)


func _cycle_scope_zoom(direction: int) -> void:
	# direction: +1 = zoom in (higher index = narrower FOV), -1 = zoom out
	var new_index = clampi(_scope_zoom_index + direction, 0, _scope_zoom_fovs.size() - 1)
	if new_index == _scope_zoom_index:
		return
	_scope_zoom_index = new_index
	_scope_camera.fov = _scope_zoom_fovs[_scope_zoom_index]
	# Update reticle scale on PIP material
	if _scope_zoom_reticle_scales.size() > _scope_zoom_index:
		var ret_scale: float = _scope_zoom_reticle_scales[_scope_zoom_index]
		if _scope_lens_mesh and is_instance_valid(_scope_lens_mesh):
			for entry in _scope_overridden_surfaces:
				var mat = _scope_lens_mesh.get_surface_override_material(entry["surf"])
				if mat and mat is ShaderMaterial:
					mat.set_shader_parameter("reticle_scale", ret_scale)
	# Sync game's weapon rig zoomLevel so reticle size etc. stays consistent
	if game_camera and is_instance_valid(game_camera):
		var mgr = game_camera.get_node_or_null("Manager")
		if mgr and mgr.get_child_count() > 0:
			var wr = mgr.get_child(0)
			wr.set("zoomLevel", _scope_zoom_index)
	# Haptic feedback on weapon hand
	var ctrl = _get_controller(_weapon_hand)
	if ctrl:
		ctrl.trigger_haptic_pulse("haptic", 0.0, 0.4, 0.1, 0.0)
	_log("scope zoom: level=" + str(_scope_zoom_index) + " fov=" + str(_scope_zoom_fovs[_scope_zoom_index]))


func _cleanup_scope() -> void:
	if _scope_lens_mesh and is_instance_valid(_scope_lens_mesh):
		for entry in _scope_overridden_surfaces:
			_scope_lens_mesh.set_surface_override_material(entry["surf"], entry["original"])
	_scope_overridden_surfaces.clear()
	_scope_lens_mesh = null
	_scope_attachment = null
	_scope_active = false
	_scope_weapon_slot = 0
	_scope_is_variable = false
	_scope_zoom_index = 0
	_scope_zoom_fovs.clear()
	_scope_zoom_reticle_scales.clear()
	# Don't destroy viewport/camera — reuse across weapon changes
	if _scope_viewport and is_instance_valid(_scope_viewport):
		_scope_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _force_debug_dump(label: String) -> void:
	if not game_camera or not is_instance_valid(game_camera):
		return
	var dump_path = OS.get_executable_path().get_base_dir() + "/vr_mod_debug.log"
	var f = FileAccess.open(dump_path, FileAccess.READ_WRITE)
	if not f:
		f = FileAccess.open(dump_path, FileAccess.WRITE)
	if f:
		f.seek_end(0)
		f.store_line("")
		f.store_line("=== " + label + " ===")
		f.store_line("Time: " + str(Time.get_ticks_msec()) + "ms")
		f.store_line("game_camera.current: " + str(game_camera.current))
		f.store_line("")
		var log_lines = []
		var snapshot = []
		_snapshot_tree(game_camera, 0, 20, snapshot, log_lines)
		for line in log_lines:
			f.store_line(line)
		f.store_line("")
		# Scan for meshes starting from camera (not root) to reach deep weapon meshes
		f.store_line("=== All MeshInstance3D under Camera ===")
		var cam_meshes = []
		_find_all_typed_under(game_camera, "MeshInstance3D", 0, 20, cam_meshes)
		for entry in cam_meshes:
			f.store_line(entry)
		if cam_meshes.is_empty():
			f.store_line("(none)")
		f.close()
	print("[VR Mod] Debug dump: ", label)


func _schedule_post_scroll_debug() -> void:
	_post_scroll_timer = 3.0  # Check 3 seconds after scroll (weapon takes time to load)


func _reparent_camera_children() -> void:
	# We no longer reparent. Instead we sync game_camera transform
	# to the controller each frame in _sync_origin_to_game().
	# This preserves game's internal node paths so weapon system still works.
	# Only activate once camera has children (weapon nodes loaded).
	if _weapons_reparented:
		return
	if not game_camera:
		return

	if game_camera.get_child_count() == 0:
		return  # Wait for weapon nodes to be populated

	print("[VR Mod] Weapon strategy: sync game_camera to controller (no reparent)")
	print("[VR Mod] Game camera children: ", game_camera.get_child_count())
	for i in game_camera.get_child_count():
		var c = game_camera.get_child(i)
		var info = "  " + c.name + " (" + c.get_class() + ")"
		if c is Node3D:
			info += " vis=" + str(c.visible)
		if c.get_child_count() > 0:
			info += " [" + str(c.get_child_count()) + " children]"
		print("[VR Mod] ", info)
	_weapons_reparented = true
	print("[VR Mod] Controller-aim sync ACTIVE")


func _dump_weapon_state() -> void:
	if not game_camera or not is_instance_valid(game_camera):
		return
	# Count all MeshInstance3D in entire scene and find ones near camera
	var cam_pos = game_camera.global_position
	var all_meshes = _find_all_meshes(get_tree().root, 0)
	var near_meshes = []
	for m in all_meshes:
		if is_instance_valid(m) and m.visible:
			var dist = m.global_position.distance_to(cam_pos)
			if dist < 3.0:
				near_meshes.append([m, dist])
	print("[VR Mod] WEAPON: total meshes=", all_meshes.size(), " near cam(<3m)=", near_meshes.size())
	for entry in near_meshes:
		var m = entry[0]
		var d = entry[1]
		print("[VR Mod] WEAPON NEAR: ", m.get_path(), " d=", snapped(d, 0.01), " mesh_type=", m.mesh.get_class() if m.mesh else "null")


func _find_all_meshes(node: Node, depth: int) -> Array:
	var result = []
	if node == xr_origin:
		return result
	if node is MeshInstance3D:
		result.append(node)
	if depth < 10:
		for child in node.get_children():
			result.append_array(_find_all_meshes(child, depth + 1))
	return result


func _restore_xr_camera() -> void:
	if xr_camera and is_instance_valid(xr_camera):
		xr_camera.current = true
		print("[VR Mod] XR camera restored as current")


func _find_meshes_near(node: Node, pos: Vector3, radius: float, depth: int, max_depth: int) -> void:
	if node == xr_origin:
		return
	if node is MeshInstance3D and node.visible:
		var dist = node.global_position.distance_to(pos)
		if dist < radius:
			print("[VR Mod] MESH NEAR CAM: ", node.get_path(), " dist=", snapped(dist, 0.01), " mesh=", node.mesh)
	if depth < max_depth:
		for child in node.get_children():
			_find_meshes_near(child, pos, radius, depth + 1, max_depth)


func _dump_tree(node: Node, depth: int, max_depth: int) -> void:
	var indent = "  ".repeat(depth)
	var info = indent + node.name + " (" + node.get_class() + ")"
	if node is Node3D:
		info += " pos=" + str(node.position)
	print("[VR Mod] ", info)
	if depth < max_depth:
		for child in node.get_children():
			_dump_tree(child, depth + 1, max_depth)


func _find_game_camera(node: Node) -> Camera3D:
	# Only detect the gameplay camera at /root/Map/Core/Camera
	# Skip intro/loading cameras to avoid activating VR too early
	var core_cam = get_tree().root.get_node_or_null("Map/Core/Camera")
	if core_cam and core_cam is Camera3D:
		return core_cam
	return null


func _load_config() -> void:
	var config_path = OS.get_executable_path().get_base_dir() + "/VR Mod/config/default_config.json"
	if not FileAccess.file_exists(config_path):
		print("[VR Mod] Config not found at: ", config_path, ", using defaults")
		return

	var file = FileAccess.open(config_path, FileAccess.READ)
	if not file:
		return

	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		var data = json.data
		if data is Dictionary:
			if data.has("xr"):
				world_scale = data["xr"].get("world_scale", 1.0)
			if data.has("comfort"):
				use_snap_turn = data["comfort"].get("turn_type", "snap") == "snap"
				snap_turn_degrees = data["comfort"].get("snap_turn_degrees", 45.0)
				smooth_turn_speed = data["comfort"].get("smooth_turn_speed", 120.0)
			if data.has("controls"):
				thumbstick_deadzone = data["controls"].get("thumbstick_deadzone", 0.15)
				_config_dominant_hand = data["controls"].get("dominant_hand", "right")
			if data.has("holsters"):
				_holster_zone_radius = data["holsters"].get("zone_radius", 0.20)
				for slot in [1, 2, 3, 4]:
					var key = str(slot)
					var def = _holster_offsets[slot]
					var ho = data["holsters"].get("offsets", {})
					if ho.has(key):
						var o = ho[key]
						_holster_offsets[slot] = Vector3(o.get("x", def.x), o.get("y", def.y), o.get("z", def.z))
				if data["holsters"].has("bag"):
					var b = data["holsters"]["bag"]
					_bag_zone_offset = Vector3(b.get("x", 0.15), b.get("y", -0.10), b.get("z", 0.35))
					_bag_zone_radius = b.get("radius", 0.35)
			if data.has("nvg_zone"):
				var nz = data["nvg_zone"]
				_nvg_zone_offset.y = nz.get("y", 0.30)
				_nvg_zone_radius = nz.get("radius", 0.25)
				_nvg_brightness = nz.get("brightness", 2.0)
				_nvg_mono = nz.get("mono", false)
			if data.has("weapon_offsets"):
				var wo = data["weapon_offsets"]
				for slot in [1, 2, 3, 4]:
					var key = str(slot)
					if wo.has(key):
						var o = wo[key]
						_slot_grip_offsets[slot] = Vector3(o.get("x", 0), o.get("y", 0.15), o.get("z", -0.20))
						_slot_grip_rotations[slot] = o.get("rot", 0.0)
			if data.has("hud"):
				var h = data["hud"]
				_hud_width = h.get("width", 2.0)
				_hud_distance = h.get("distance", 1.5)
				_hud_height_offset = h.get("height_offset", -0.1)
				_hud_lr_offset = h.get("lr_offset", 0.0)
				_hud_smooth_follow = h.get("smooth_follow", false)
				_hud_smooth_speed = h.get("smooth_speed", 3.0)
				_hud_spread = h.get("spread", 1.0)
			if data.has("menu"):
				var m = data["menu"]
				_menu_width = m.get("width", 3.0)
				_menu_distance = m.get("distance", 1.3)
				_menu_lr_offset = m.get("lr_offset", 0.0)
				_menu_laser_uv_x = m.get("laser_uv_x", 0.02)
				_menu_laser_uv_y = m.get("laser_uv_y", 0.06)
			print("[VR Mod] Config loaded successfully")
	file.close()


func _save_grip_config() -> void:
	var config_path = OS.get_executable_path().get_base_dir() + "/VR Mod/config/default_config.json"
	if not FileAccess.file_exists(config_path):
		print("[VR Mod] Config not found, cannot save: ", config_path)
		return

	var file = FileAccess.open(config_path, FileAccess.READ)
	if not file:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return
	var data = json.data
	file.close()

	if not data is Dictionary:
		return

	# Update weapon_offsets section with current values
	var wo := {}
	for slot in [1, 2, 3, 4]:
		var o := _slot_grip_offsets[slot] as Vector3
		wo[str(slot)] = {
			"x": snapped(o.x, 0.001),
			"y": snapped(o.y, 0.001),
			"z": snapped(o.z, 0.001),
			"rot": snapped(_slot_grip_rotations[slot], 0.1)
		}
	data["weapon_offsets"] = wo

	var out = FileAccess.open(config_path, FileAccess.WRITE)
	if out:
		out.store_string(JSON.stringify(data, "\t"))
		out.close()
		print("[VR Mod] Grip config saved to: ", config_path)
		for slot in [1, 2, 3, 4]:
			var o = _slot_grip_offsets[slot]
			print("[VR Mod]   Slot ", slot, ": x=", snapped(o.x, 0.001), " y=", snapped(o.y, 0.001), " z=", snapped(o.z, 0.001), " rot=", snapped(_slot_grip_rotations[slot], 0.1), "°")


# ── Smooth HUD follow ──────────────────────────────────────────────────────────

func _update_smooth_hud(delta: float) -> void:
	if not _hud_smooth_follow:
		return
	if not hud_mesh:
		return
	if _interface_open:
		return
	if hud_mesh.get_parent() == xr_camera:
		return

	var cam_yaw = xr_camera.global_rotation.y

	# Shortest-path yaw lerp — use _hud_yaw member, never read back from mesh
	var diff = fmod(cam_yaw - _hud_yaw + PI, TAU) - PI
	_hud_yaw += diff * clampf(_hud_smooth_speed * delta, 0.0, 1.0)

	# Position: instantly at exact offset from camera, rotated by lagged yaw
	var lagged_basis = Basis(Vector3.UP, _hud_yaw)
	hud_mesh.global_position = xr_camera.global_position + lagged_basis * Vector3(_hud_lr_offset, _hud_height_offset, -_hud_distance)

	# Orientation: quad local +Z faces toward player when rotation.y == _hud_yaw
	# (no PI offset needed — lagged_basis already points HUD away from player,
	#  so +Z normal naturally faces back toward player)
	hud_mesh.global_rotation = Vector3(0.0, _hud_yaw, 0.0)


# ── Config Screen (F8) ──────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F8:
		_toggle_config_screen()
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		_dump_hud_tree()
	if event is InputEventKey and event.pressed and event.keycode == KEY_F10:
		_dump_weapon_tree()
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		_dump_nvg_and_environment()


func _toggle_config_screen() -> void:
	if _config_screen_open:
		_close_config_screen()
	else:
		_open_config_screen()


func _open_config_screen() -> void:
	if _config_screen_open:
		return
	_config_screen_open = true
	_build_config_panel()
	_populate_config_ui()
	# Show laser in blue/UI mode
	if _laser_mesh:
		var mat := _laser_mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.2, 0.5, 1.0, 0.5)
		var cyl := _laser_mesh.mesh as CylinderMesh
		if cyl:
			cyl.height = 5.0
			_laser_mesh.position.z = -cyl.height / 2.0
		_laser_mesh.visible = true
	print("[VR Mod] Config screen opened")


func _close_config_screen() -> void:
	if not _config_screen_open:
		return
	_config_screen_open = false
	if _config_panel_quad and is_instance_valid(_config_panel_quad):
		_config_panel_quad.queue_free()
		_config_panel_quad = null
	if _config_panel_vp and is_instance_valid(_config_panel_vp):
		_config_panel_vp.queue_free()
		_config_panel_vp = null
	if _laser_mesh and not _interface_open:
		_laser_mesh.visible = false
	print("[VR Mod] Config screen closed")


func _build_config_panel() -> void:
	# SubViewport for config UI
	_config_panel_vp = SubViewport.new()
	_config_panel_vp.name = "ConfigPanelVP"
	_config_panel_vp.size = Vector2i(800, 900)
	_config_panel_vp.transparent_bg = true
	_config_panel_vp.disable_3d = true
	_config_panel_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_config_panel_vp.gui_disable_input = false
	add_child(_config_panel_vp)

	# Place quad in world space in front of camera
	_config_panel_quad = MeshInstance3D.new()
	_config_panel_quad.name = "ConfigPanelQuad"
	var quad = QuadMesh.new()
	var aspect = 900.0 / 800.0
	quad.size = Vector2(1.6, 1.6 * aspect)
	_config_panel_quad.mesh = quad

	var mat = StandardMaterial3D.new()
	mat.albedo_texture = _config_panel_vp.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 20
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_config_panel_quad.material_override = mat

	var cam_pos = xr_camera.global_position
	var cam_fwd = -xr_camera.global_basis.z
	cam_fwd.y = 0
	cam_fwd = cam_fwd.normalized()
	var panel_pos = cam_pos + cam_fwd * 1.3
	panel_pos.y = cam_pos.y

	get_tree().root.add_child(_config_panel_quad)
	_config_panel_quad.global_position = panel_pos
	_config_panel_quad.look_at(cam_pos, Vector3.UP)
	_config_panel_quad.rotate_y(deg_to_rad(180))


func _populate_config_ui() -> void:
	if not _config_panel_vp:
		return

	var root = PanelContainer.new()
	root.name = "CfgRoot"
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	bg.corner_radius_top_left = 16
	bg.corner_radius_top_right = 16
	bg.corner_radius_bottom_left = 16
	bg.corner_radius_bottom_right = 16
	bg.content_margin_left = 20
	bg.content_margin_right = 20
	bg.content_margin_top = 16
	bg.content_margin_bottom = 16
	root.add_theme_stylebox_override("panel", bg)
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0

	var scroll = ScrollContainer.new()
	scroll.name = "CfgScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.name = "CfgVBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "VR Mod Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	vbox.add_child(title)

	_mk_sep(vbox)

	# ── Turn Mode ──
	_mk_header(vbox, "Comfort")
	var grid_comfort = _mk_grid(vbox)
	_add_toggle_row(grid_comfort, "Turn Mode", ["Snap", "Smooth"], 0 if use_snap_turn else 1, "_on_cfg_turn")
	_add_stepper_row(grid_comfort, "Snap Degrees", snap_turn_degrees, 15.0, 90.0, 5.0, "_on_cfg_snap_deg")
	_add_stepper_row(grid_comfort, "Smooth Speed", smooth_turn_speed, 30.0, 300.0, 10.0, "_on_cfg_smooth_spd")

	_mk_sep(vbox)

	# ── HUD ──
	_mk_header(vbox, "HUD (Gameplay)")
	var grid_hud = _mk_grid(vbox)
	_add_stepper_row(grid_hud, "Distance", _hud_distance, 0.5, 3.0, 0.1, "_on_cfg_hud_dist")
	_add_stepper_row(grid_hud, "Size", _hud_width, 0.5, 4.0, 0.1, "_on_cfg_hud_wid")
	_add_stepper_row(grid_hud, "Height", _hud_height_offset, -1.0, 1.0, 0.05, "_on_cfg_hud_hgt")
	_add_stepper_row(grid_hud, "Left/Right", _hud_lr_offset, -1.0, 1.0, 0.05, "_on_cfg_hud_lr")
	_add_toggle_row(grid_hud, "Follow Mode", ["Instant", "Smooth"], 1 if _hud_smooth_follow else 0, "_on_cfg_hud_follow")
	_add_stepper_row(grid_hud, "Smooth Speed", _hud_smooth_speed, 0.5, 10.0, 0.5, "_on_cfg_hud_smooth_spd")
	_add_stepper_row(grid_hud, "Spread", _hud_spread, 0.1, 2.0, 0.1, "_on_cfg_hud_spread")

	_mk_sep(vbox)

	# ── Menu ──
	_mk_header(vbox, "Menu / Inventory")
	var grid_menu = _mk_grid(vbox)
	_add_stepper_row(grid_menu, "Distance", _menu_distance, 0.5, 3.0, 0.1, "_on_cfg_menu_dist")
	_add_stepper_row(grid_menu, "Size", _menu_width, 0.5, 5.0, 0.1, "_on_cfg_menu_wid")
	_add_stepper_row(grid_menu, "Left/Right", _menu_lr_offset, -1.0, 1.0, 0.05, "_on_cfg_menu_lr")
	_add_stepper_row(grid_menu, "Laser X", _menu_laser_uv_x, -0.2, 0.2, 0.01, "_on_cfg_laser_x")
	_add_stepper_row(grid_menu, "Laser Y", _menu_laser_uv_y, -0.2, 0.2, 0.01, "_on_cfg_laser_y")

	_mk_sep(vbox)

	# ── Controls ──
	_mk_header(vbox, "Controls")
	var grid_ctrl = _mk_grid(vbox)
	_add_toggle_row(grid_ctrl, "Dominant Hand", ["Right", "Left"], 0 if _config_dominant_hand == "right" else 1, "_on_cfg_hand")

	_mk_sep(vbox)

	# ── Holster Zones ──
	_mk_header(vbox, "Holster Zones")
	var grid_holsters = _mk_grid(vbox)
	_add_stepper_row(grid_holsters, "Zone Radius", _holster_zone_radius, 0.05, 0.5, 0.01, "_on_cfg_hz_radius")
	var zone_names := ["1: R.Shoulder", "2: R.Hip", "3: L.Hip", "4: Chest"]
	for zi in range(4):
		var slot = zi + 1
		var o: Vector3 = _holster_offsets[slot]
		_mk_header(vbox, zone_names[zi])
		var grid_z = _mk_grid(vbox)
		_add_stepper_row(grid_z, "X (L/R)", o.x, -0.6, 0.6, 0.01, "_on_cfg_hz_x_" + str(slot))
		_add_stepper_row(grid_z, "Y (U/D)", o.y, -1.0, 0.2, 0.01, "_on_cfg_hz_y_" + str(slot))
		_add_stepper_row(grid_z, "Z (F/B)", o.z, -0.5, 0.5, 0.01, "_on_cfg_hz_z_" + str(slot))

	_mk_sep(vbox)

	# ── Bag Zone (Inventory) ──
	_mk_header(vbox, "Bag Zone (Inventory)")
	var grid_bag = _mk_grid(vbox)
	_add_stepper_row(grid_bag, "Radius", _bag_zone_radius, 0.05, 0.8, 0.01, "_on_cfg_bag_radius")
	_add_stepper_row(grid_bag, "X (L/R)", _bag_zone_offset.x, -0.5, 0.5, 0.01, "_on_cfg_bag_x")
	_add_stepper_row(grid_bag, "Y (U/D)", _bag_zone_offset.y, -0.5, 0.5, 0.01, "_on_cfg_bag_y")
	_add_stepper_row(grid_bag, "Z (F/B)", _bag_zone_offset.z, 0.0, 0.8, 0.01, "_on_cfg_bag_z")

	_mk_sep(vbox)

	# ── NVG Zone (Above Head) ──
	_mk_header(vbox, "NVG Zone (Above Head)")
	var grid_nvg = _mk_grid(vbox)
	_add_stepper_row(grid_nvg, "Radius", _nvg_zone_radius, 0.05, 0.5, 0.01, "_on_cfg_nvg_radius")
	_add_stepper_row(grid_nvg, "Y (Height)", _nvg_zone_offset.y, 0.0, 0.6, 0.01, "_on_cfg_nvg_y")
	_add_stepper_row(grid_nvg, "Brightness", _nvg_brightness, 1.0, 5.0, 0.25, "_on_cfg_nvg_brightness")
	_add_toggle_row(grid_nvg, "Mono Vision", ["Off", "On"], 1 if _nvg_mono else 0, "_on_cfg_nvg_mono")

	_mk_sep(vbox)

	# ── Save & Close ──
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var save_btn = _mk_btn("Save & Close", Color(0.2, 0.7, 0.3))
	save_btn.pressed.connect(Callable(self, "_on_cfg_save_close"))
	btn_row.add_child(save_btn)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	btn_row.add_child(spacer)

	var cancel_btn = _mk_btn("Cancel", Color(0.7, 0.3, 0.3))
	cancel_btn.pressed.connect(Callable(self, "_close_config_screen"))
	btn_row.add_child(cancel_btn)

	_config_panel_vp.add_child(root)


# ── UI builder helpers ──────────────────────────────────────────────────────

func _mk_sep(parent: Control) -> void:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 12)
	parent.add_child(sep)


func _mk_header(parent: Control, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	parent.add_child(lbl)


func _mk_grid(parent: Control) -> GridContainer:
	var g = GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(g)
	return g


func _mk_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	return lbl


func _mk_btn(text: String, color: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(100, 40)
	var sb = StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", sb)
	var hover = sb.duplicate()
	hover.bg_color = color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_font_size_override("font_size", 18)
	return btn


func _mk_style(color: Color) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


# ── Row builders ────────────────────────────────────────────────────────────

func _add_toggle_row(grid: GridContainer, label: String, options: Array, active: int, callback_name: String) -> void:
	grid.add_child(_mk_label(label))
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	var buttons := []
	for i in range(options.size()):
		var btn = Button.new()
		btn.text = options[i]
		btn.custom_minimum_size = Vector2(90, 36)
		btn.add_theme_font_size_override("font_size", 16)
		buttons.append(btn)
		hbox.add_child(btn)
	_highlight_toggle(buttons, active)
	for i in range(buttons.size()):
		var idx = i
		var b_arr = buttons
		var cb = callback_name
		buttons[i].pressed.connect(Callable(self, "_on_toggle_pressed").bind(b_arr, idx, cb))
	grid.add_child(hbox)


func _on_toggle_pressed(buttons: Array, idx: int, callback_name: String) -> void:
	_highlight_toggle(buttons, idx)
	call(callback_name, idx)


func _highlight_toggle(buttons: Array, active: int) -> void:
	for i in range(buttons.size()):
		var btn = buttons[i] as Button
		if i == active:
			btn.add_theme_stylebox_override("normal", _mk_style(Color(0.2, 0.5, 0.8)))
			btn.add_theme_stylebox_override("hover", _mk_style(Color(0.3, 0.6, 0.9)))
		else:
			btn.add_theme_stylebox_override("normal", _mk_style(Color(0.25, 0.25, 0.3)))
			btn.add_theme_stylebox_override("hover", _mk_style(Color(0.35, 0.35, 0.4)))


func _add_stepper_row(grid: GridContainer, label: String, value: float, min_val: float, max_val: float, step: float, callback_name: String) -> void:
	grid.add_child(_mk_label(label))
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var dec_btn = _mk_btn("-", Color(0.35, 0.35, 0.4))
	dec_btn.custom_minimum_size = Vector2(40, 36)
	hbox.add_child(dec_btn)

	var val_lbl = Label.new()
	val_lbl.text = _fmt_val(value)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.custom_minimum_size = Vector2(70, 0)
	val_lbl.add_theme_font_size_override("font_size", 18)
	val_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	hbox.add_child(val_lbl)

	var inc_btn = _mk_btn("+", Color(0.35, 0.35, 0.4))
	inc_btn.custom_minimum_size = Vector2(40, 36)
	hbox.add_child(inc_btn)

	dec_btn.pressed.connect(Callable(self, "_on_stepper_dec").bind(val_lbl, value, min_val, max_val, step, callback_name))
	inc_btn.pressed.connect(Callable(self, "_on_stepper_inc").bind(val_lbl, value, min_val, max_val, step, callback_name))

	grid.add_child(hbox)


func _on_stepper_dec(val_lbl: Label, current: float, min_val: float, max_val: float, step: float, callback_name: String) -> void:
	var new_val = clampf(snapped(current - step, step), min_val, max_val)
	val_lbl.text = _fmt_val(new_val)
	# Update the bound args for next press by reconnecting
	_reconnect_stepper(val_lbl, new_val, min_val, max_val, step, callback_name)
	call(callback_name, new_val)


func _on_stepper_inc(val_lbl: Label, current: float, min_val: float, max_val: float, step: float, callback_name: String) -> void:
	var new_val = clampf(snapped(current + step, step), min_val, max_val)
	val_lbl.text = _fmt_val(new_val)
	_reconnect_stepper(val_lbl, new_val, min_val, max_val, step, callback_name)
	call(callback_name, new_val)


func _reconnect_stepper(val_lbl: Label, new_val: float, min_val: float, max_val: float, step: float, callback_name: String) -> void:
	var hbox = val_lbl.get_parent()
	var dec_btn = hbox.get_child(0) as Button
	var inc_btn = hbox.get_child(2) as Button
	# Disconnect all existing connections
	var dec_conns = dec_btn.pressed.get_connections()
	for c in dec_conns:
		dec_btn.pressed.disconnect(c["callable"])
	var inc_conns = inc_btn.pressed.get_connections()
	for c in inc_conns:
		inc_btn.pressed.disconnect(c["callable"])
	# Reconnect with updated value
	dec_btn.pressed.connect(Callable(self, "_on_stepper_dec").bind(val_lbl, new_val, min_val, max_val, step, callback_name))
	inc_btn.pressed.connect(Callable(self, "_on_stepper_inc").bind(val_lbl, new_val, min_val, max_val, step, callback_name))


func _fmt_val(v: float) -> String:
	if absf(v - roundf(v)) < 0.001:
		return str(int(v))
	return str(snapped(v, 0.01))


# ── Config callbacks ────────────────────────────────────────────────────────

func _on_cfg_turn(idx: int) -> void:
	use_snap_turn = (idx == 0)


func _on_cfg_snap_deg(val: float) -> void:
	snap_turn_degrees = val


func _on_cfg_smooth_spd(val: float) -> void:
	smooth_turn_speed = val


func _on_cfg_hud_dist(val: float) -> void:
	_hud_distance = val
	_apply_hud_settings()


func _on_cfg_hud_wid(val: float) -> void:
	_hud_width = val
	_apply_hud_settings()


func _on_cfg_hud_hgt(val: float) -> void:
	_hud_height_offset = val
	_apply_hud_settings()


func _on_cfg_hud_lr(val: float) -> void:
	_hud_lr_offset = val
	_apply_hud_settings()


func _on_cfg_hud_follow(idx: int) -> void:
	_hud_smooth_follow = (idx == 1)
	_apply_hud_follow_mode()


func _on_cfg_hud_smooth_spd(val: float) -> void:
	_hud_smooth_speed = val


func _on_cfg_hud_spread(val: float) -> void:
	_hud_spread = val
	_apply_hud_spread()


func _on_cfg_menu_dist(val: float) -> void:
	_menu_distance = val


func _on_cfg_menu_wid(val: float) -> void:
	_menu_width = val


func _on_cfg_menu_lr(val: float) -> void:
	_menu_lr_offset = val


func _on_cfg_laser_x(val: float) -> void:
	_menu_laser_uv_x = val


func _on_cfg_laser_y(val: float) -> void:
	_menu_laser_uv_y = val


func _on_cfg_hand(idx: int) -> void:
	if idx == 0:
		_config_dominant_hand = "right"
	else:
		_config_dominant_hand = "left"


func _on_cfg_hz_radius(val: float) -> void:
	_holster_zone_radius = val

func _on_cfg_hz_x_1(val: float) -> void:
	_holster_offsets[1].x = val
func _on_cfg_hz_y_1(val: float) -> void:
	_holster_offsets[1].y = val
func _on_cfg_hz_z_1(val: float) -> void:
	_holster_offsets[1].z = val

func _on_cfg_hz_x_2(val: float) -> void:
	_holster_offsets[2].x = val
func _on_cfg_hz_y_2(val: float) -> void:
	_holster_offsets[2].y = val
func _on_cfg_hz_z_2(val: float) -> void:
	_holster_offsets[2].z = val

func _on_cfg_hz_x_3(val: float) -> void:
	_holster_offsets[3].x = val
func _on_cfg_hz_y_3(val: float) -> void:
	_holster_offsets[3].y = val
func _on_cfg_hz_z_3(val: float) -> void:
	_holster_offsets[3].z = val

func _on_cfg_hz_x_4(val: float) -> void:
	_holster_offsets[4].x = val
func _on_cfg_hz_y_4(val: float) -> void:
	_holster_offsets[4].y = val
func _on_cfg_hz_z_4(val: float) -> void:
	_holster_offsets[4].z = val

func _on_cfg_bag_radius(val: float) -> void:
	_bag_zone_radius = val
func _on_cfg_bag_x(val: float) -> void:
	_bag_zone_offset.x = val
func _on_cfg_bag_y(val: float) -> void:
	_bag_zone_offset.y = val
func _on_cfg_bag_z(val: float) -> void:
	_bag_zone_offset.z = val

func _on_cfg_nvg_radius(val: float) -> void:
	_nvg_zone_radius = val
func _on_cfg_nvg_y(val: float) -> void:
	_nvg_zone_offset.y = val
func _on_cfg_nvg_brightness(val: float) -> void:
	_nvg_brightness = val
	if _nvg_overlay_installed and _nvg_overlay_mesh and _nvg_overlay_mesh.material_override:
		(_nvg_overlay_mesh.material_override as ShaderMaterial).set_shader_parameter("brightness", val)
func _on_cfg_nvg_mono(idx: int) -> void:
	_nvg_mono = (idx == 1)
	if _nvg_active and _nvg_overlay_mesh and _nvg_overlay_mesh.material_override:
		var mat = _nvg_overlay_mesh.material_override as ShaderMaterial
		if _nvg_mono:
			_create_nvg_mono_viewport()
			_nvg_mono_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			mat.set_shader_parameter("mono_tex", _nvg_mono_viewport.get_texture())
		else:
			if _nvg_mono_viewport:
				_nvg_mono_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		mat.set_shader_parameter("use_mono", _nvg_mono)


func _on_cfg_save_close() -> void:
	_save_full_config()
	_close_config_screen()


# ── Apply helpers ───────────────────────────────────────────────────────────

func _apply_hud_settings() -> void:
	if not hud_mesh:
		return
	var aspect = float(hud_viewport.size.y) / float(hud_viewport.size.x)
	(hud_mesh.mesh as QuadMesh).size = Vector2(_hud_width, _hud_width * aspect)
	if hud_mesh.get_parent() == xr_camera:
		hud_mesh.position = Vector3(_hud_lr_offset, _hud_height_offset, -_hud_distance)


func _apply_hud_follow_mode() -> void:
	if not hud_mesh:
		return
	if _hud_smooth_follow:
		# Seed yaw from current camera so there's no snap on first frame
		if xr_camera:
			_hud_yaw = xr_camera.global_rotation.y
		# Switch to world-space
		if hud_mesh.get_parent() == xr_camera:
			xr_camera.remove_child(hud_mesh)
			get_tree().root.add_child(hud_mesh)
			# Place immediately at correct position using seeded yaw
			var lagged_basis = Basis(Vector3.UP, _hud_yaw)
			hud_mesh.global_position = xr_camera.global_position + lagged_basis * Vector3(_hud_lr_offset, _hud_height_offset, -_hud_distance)
			hud_mesh.global_rotation = Vector3(0.0, _hud_yaw, 0.0)
	else:
		# Switch to head-locked
		if hud_mesh.get_parent() != xr_camera:
			if hud_mesh.get_parent():
				hud_mesh.get_parent().remove_child(hud_mesh)
			xr_camera.add_child(hud_mesh)
			hud_mesh.position = Vector3(_hud_lr_offset, _hud_height_offset, -_hud_distance)
			hud_mesh.rotation = Vector3.ZERO


func _apply_hud_spread() -> void:
	var hud_node = get_tree().root.get_node_or_null("Map/Core/UI/HUD")
	if not hud_node:
		return
	# Bottom stats: Vitals (left) and Medical (right)
	var stats = hud_node.get_node_or_null("Stats")
	if stats:
		var vitals = stats.get_node_or_null("Vitals")
		if vitals and vitals is Control:
			vitals.position.x = -960.0 * _hud_spread
		var medical = stats.get_node_or_null("Medical")
		if medical and medical is Control:
			medical.position.x = 960.0 * _hud_spread
	# Top-left info (Map/FPS) — anchored top-left, default pos=(32, 32)
	var info = hud_node.get_node_or_null("Info")
	if info and info is Control:
		# Move inward from left edge: at spread=1.0 → x=32, at spread=0.5 → x=~928 (toward center)
		var half_w = 1920.0  # half of 3840 HUD width
		var default_x = 32.0
		info.position.x = half_w - (half_w - default_x) * _hud_spread


# ── Config laser & click ────────────────────────────────────────────────────

func _update_config_laser() -> void:
	if not _config_panel_quad or not _config_panel_vp or not _laser_mesh:
		return
	var controller = _get_controller(_config_dominant_hand)
	if not controller or not controller.get_is_active():
		return
	var ray_origin = controller.global_position
	var ray_dir = -controller.global_basis.z
	var hit_pos = _ray_quad_intersection(ray_origin, ray_dir, _config_panel_quad)
	if hit_pos == Vector3.INF:
		return
	var local_pos = _config_panel_quad.global_transform.affine_inverse() * hit_pos
	var quad_size = (_config_panel_quad.mesh as QuadMesh).size
	var uv_x = (local_pos.x + quad_size.x / 2.0) / quad_size.x
	var uv_y = (-local_pos.y + quad_size.y / 2.0) / quad_size.y
	if uv_x >= 0 and uv_x <= 1 and uv_y >= 0 and uv_y <= 1:
		_config_laser_pos = Vector2(uv_x * _config_panel_vp.size.x, uv_y * _config_panel_vp.size.y)
		# Send mouse motion to config viewport
		var motion = InputEventMouseMotion.new()
		motion.position = _config_laser_pos
		motion.global_position = _config_laser_pos
		_config_panel_vp.push_input(motion)
		# Update laser visual
		var dist = ray_origin.distance_to(hit_pos) - 0.15
		if dist > 0.1:
			(_laser_mesh.mesh as CylinderMesh).height = dist
			_laser_mesh.position.z = -dist / 2.0
			_laser_mesh.visible = true


func _inject_config_click(pressed: bool) -> void:
	if not _config_panel_vp:
		return
	var ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = _config_laser_pos
	ev.global_position = _config_laser_pos
	_config_panel_vp.push_input(ev)


func _scroll_config_panel(amount: float) -> void:
	if not _config_panel_vp:
		return
	var scroll = _config_panel_vp.get_node_or_null("CfgRoot/CfgScroll")
	if scroll and scroll is ScrollContainer:
		scroll.scroll_vertical += int(amount)


# ── Save full config ────────────────────────────────────────────────────────

func _save_full_config() -> void:
	var config_path = OS.get_executable_path().get_base_dir() + "/VR Mod/config/default_config.json"
	var data := {}

	# Read existing config first
	if FileAccess.file_exists(config_path):
		var file = FileAccess.open(config_path, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				if json.data is Dictionary:
					data = json.data
			file.close()

	# XR
	data["xr"] = {"world_scale": world_scale}

	# Comfort
	var turn_type = "snap"
	if not use_snap_turn:
		turn_type = "smooth"
	data["comfort"] = {
		"turn_type": turn_type,
		"snap_turn_degrees": snap_turn_degrees,
		"smooth_turn_speed": smooth_turn_speed
	}

	# Controls
	data["controls"] = {
		"thumbstick_deadzone": thumbstick_deadzone,
		"dominant_hand": _config_dominant_hand
	}

	# HUD
	data["hud"] = {
		"width": _hud_width,
		"distance": _hud_distance,
		"height_offset": _hud_height_offset,
		"lr_offset": _hud_lr_offset,
		"smooth_follow": _hud_smooth_follow,
		"smooth_speed": _hud_smooth_speed,
		"spread": _hud_spread
	}

	# Menu
	data["menu"] = {
		"width": _menu_width,
		"distance": _menu_distance,
		"lr_offset": _menu_lr_offset,
		"laser_uv_x": _menu_laser_uv_x,
		"laser_uv_y": _menu_laser_uv_y
	}

	# Holsters (zone offsets + bag zone)
	var holster_offsets_data := {}
	for slot in [1, 2, 3, 4]:
		var o: Vector3 = _holster_offsets[slot]
		holster_offsets_data[str(slot)] = {"x": snapped(o.x, 0.001), "y": snapped(o.y, 0.001), "z": snapped(o.z, 0.001)}
	data["holsters"] = {
		"zone_radius": _holster_zone_radius,
		"offsets": holster_offsets_data,
		"bag": {
			"x": snapped(_bag_zone_offset.x, 0.001),
			"y": snapped(_bag_zone_offset.y, 0.001),
			"z": snapped(_bag_zone_offset.z, 0.001),
			"radius": _bag_zone_radius
		}
	}

	# NVG zone
	data["nvg_zone"] = {
		"y": snapped(_nvg_zone_offset.y, 0.001),
		"radius": _nvg_zone_radius,
		"brightness": _nvg_brightness,
		"mono": _nvg_mono
	}

	# Preserve existing weapon_offsets (already in data from the read above)

	var out = FileAccess.open(config_path, FileAccess.WRITE)
	if out:
		out.store_string(JSON.stringify(data, "\t"))
		out.close()
		print("[VR Mod] Full config saved to: ", config_path)


# ── Weapon tree debug dump (F10) ──────────────────────────────────────────

func _dump_weapon_tree() -> void:
	var log_path = OS.get_executable_path().get_base_dir() + "/vr_mod_debug.log"
	var f = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if not f:
		f = FileAccess.open(log_path, FileAccess.WRITE)
	if not f:
		print("[VR Mod] Cannot open debug log for weapon dump")
		return
	f.seek_end(0)
	f.store_line("")
	f.store_line("=== WEAPON TREE DUMP (" + str(Time.get_datetime_string_from_system()) + ") ===")

	if not game_camera or not is_instance_valid(game_camera):
		f.store_line("  No game camera!")
		f.close()
		return

	var mgr = game_camera.get_node_or_null("Manager")
	if not mgr or mgr.get_child_count() == 0:
		f.store_line("  No weapon rig (Manager empty)")
		f.close()
		return

	var weapon_rig = mgr.get_child(0)
	f.store_line("Weapon rig: " + weapon_rig.name)
	_dump_weapon_node(f, weapon_rig, 0, 30)
	f.store_line("")
	f.close()
	print("[VR Mod] Weapon tree dumped to vr_mod_debug.log")


func _dump_weapon_node(f: FileAccess, node: Node, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		return
	var indent = "  ".repeat(depth)
	var line = indent + node.name + " (" + node.get_class() + ")"
	if node.get_script():
		line += " script=" + str(node.get_script().resource_path)
		# Dump script properties (exported/user vars)
		var prop_strs := []
		for prop in node.get_property_list():
			if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var pname: String = prop["name"]
				var val = node.get(pname)
				if val != null and str(val).length() < 200:
					prop_strs.append(pname + "=" + str(val))
		if prop_strs.size() > 0:
			line += "\n" + indent + "  PROPS: " + " | ".join(prop_strs)
		# Dump attachmentData resource properties if present
		var att_data = node.get("attachmentData")
		if att_data and att_data is Resource:
			var res_strs := []
			for rprop in att_data.get_property_list():
				if rprop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
					var rpname: String = rprop["name"]
					var rval = att_data.get(rpname)
					if rval != null and str(rval).length() < 300:
						res_strs.append(rpname + "=" + str(rval))
			if res_strs.size() > 0:
				line += "\n" + indent + "  ATTACHMENT_DATA: " + " | ".join(res_strs)
	if node is Node3D:
		line += " pos=" + str(node.position) + " vis=" + str(node.visible)
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		line += " layers=" + str(mi.layers)
		if mi.mesh:
			line += " mesh=" + mi.mesh.get_class()
			line += " surfs=" + str(mi.mesh.get_surface_count())
			var aabb = mi.mesh.get_aabb()
			line += " aabb_size=" + str(aabb.size)
			if mi.mesh.resource_path != "":
				line += " res=" + mi.mesh.resource_path
		# Log material info for each surface
		var surf_count = mi.mesh.get_surface_count() if mi.mesh else 0
		for s in range(surf_count):
			var mat = mi.get_active_material(s)
			if mat:
				var mat_line = indent + "  [surf " + str(s) + "] " + mat.get_class()
				if mat is ShaderMaterial:
					mat_line += " shader=" + str(mat.shader.resource_path if mat.shader else "null")
					if mat.shader:
						for param in mat.shader.get_shader_uniform_list():
							var pname: String = param["name"]
							var ptype: int = param["type"]
							var val = mat.get_shader_parameter(pname)
							var val_str = str(val)
							if val is Texture2D and val.resource_path != "":
								val_str = val.resource_path
							elif val is ViewportTexture:
								val_str = "ViewportTexture:" + str(val.viewport_path)
							mat_line += "\n" + indent + "    uniform " + pname + " type=" + str(ptype) + " val=" + val_str
				if mat is BaseMaterial3D:
					var bm = mat as BaseMaterial3D
					mat_line += " transp=" + str(bm.transparency)
					mat_line += " blend=" + str(bm.blend_mode)
					mat_line += " shading=" + str(bm.shading_mode)
					mat_line += " no_depth=" + str(bm.no_depth_test)
					mat_line += " albedo=" + str(bm.albedo_color)
					mat_line += " emission=" + str(bm.emission_enabled)
					if bm.emission_enabled:
						mat_line += " emission_col=" + str(bm.emission)
						mat_line += " emission_energy=" + str(bm.emission_energy_multiplier)
					if bm.albedo_texture:
						mat_line += " albedo_tex=" + str(bm.albedo_texture.resource_path)
						if bm.albedo_texture is ViewportTexture:
							mat_line += " (ViewportTexture:" + str(bm.albedo_texture.viewport_path) + ")"
				line += "\n" + mat_line
			else:
				line += "\n" + indent + "  [surf " + str(s) + "] null material"
	if node is Skeleton3D:
		line += " bones=" + str((node as Skeleton3D).get_bone_count())
	if node is SubViewport:
		var sv = node as SubViewport
		line += " vp_size=" + str(sv.size) + " update=" + str(sv.render_target_update_mode)
	if node is Camera3D:
		var cam = node as Camera3D
		line += " fov=" + str(cam.fov) + " near=" + str(cam.near) + " far=" + str(cam.far) + " current=" + str(cam.current)
	f.store_line(line)
	for child in node.get_children():
		_dump_weapon_node(f, child, depth + 1, max_depth)


# ── HUD tree debug dump (F9) ───────────────────────────────────────────────

func _dump_hud_tree() -> void:
	var log_path = OS.get_executable_path().get_base_dir() + "/vr_mod_debug.log"
	var f = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if not f:
		f = FileAccess.open(log_path, FileAccess.WRITE)
	if not f:
		print("[VR Mod] Cannot open debug log for HUD dump")
		return
	f.seek_end(0)
	f.store_line("")
	f.store_line("=== HUD TREE DUMP (" + str(Time.get_datetime_string_from_system()) + ") ===")

	var ui_node = get_tree().root.get_node_or_null("Map/Core/UI")
	if not ui_node:
		f.store_line("  Map/Core/UI not found!")
		f.close()
		return

	var hud_node = ui_node.get_node_or_null("HUD")
	if not hud_node:
		f.store_line("  Map/Core/UI/HUD not found! Children of UI:")
		for c in ui_node.get_children():
			f.store_line("    " + c.name + " (" + c.get_class() + ")")
		f.close()
		return

	_dump_node_recursive(f, hud_node, 0)
	f.store_line("=== END HUD TREE DUMP ===")
	f.close()
	print("[VR Mod] HUD tree dumped to vr_mod_debug.log")


func _dump_node_recursive(f: FileAccess, node: Node, depth: int) -> void:
	var indent = ""
	for i in range(depth):
		indent += "  "
	var line = indent + node.name + " (" + node.get_class() + ")"
	if node is Control:
		var ctrl = node as Control
		line += " pos=" + str(ctrl.position)
		line += " size=" + str(ctrl.size)
		line += " anchors=(" + str(ctrl.anchor_left) + "," + str(ctrl.anchor_top) + "," + str(ctrl.anchor_right) + "," + str(ctrl.anchor_bottom) + ")"
		line += " vis=" + str(ctrl.visible)
		if ctrl.layout_direction != Control.LAYOUT_DIRECTION_INHERITED:
			line += " layout_dir=" + str(ctrl.layout_direction)
	elif node is CanvasItem:
		line += " vis=" + str((node as CanvasItem).visible)
	f.store_line(line)
	for child in node.get_children():
		_dump_node_recursive(f, child, depth + 1)


# ── NVG & Environment debug dump (F11) ────────────────────────────────────

func _dump_nvg_and_environment() -> void:
	var log_path = OS.get_executable_path().get_base_dir() + "/vr_mod_debug.log"
	var f = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if not f:
		f = FileAccess.open(log_path, FileAccess.WRITE)
	if not f:
		print("[VR Mod] Cannot open debug log for NVG dump")
		return
	f.seek_end(0)
	f.store_line("")
	f.store_line("=== NVG & ENVIRONMENT DUMP (" + str(Time.get_datetime_string_from_system()) + ") ===")

	# ── 1. Dump the NVG node under Map/Core/UI ──
	var ui_node = get_tree().root.get_node_or_null("Map/Core/UI")
	if ui_node:
		var nvg_node = ui_node.get_node_or_null("NVG")
		if nvg_node:
			f.store_line("")
			f.store_line("── NVG Node (" + nvg_node.get_class() + ") vis=" + str(nvg_node.visible) + " ──")
			if nvg_node.get_script():
				f.store_line("  script=" + str(nvg_node.get_script().resource_path))
			if nvg_node is CanvasItem:
				f.store_line("  modulate=" + str(nvg_node.modulate))
				f.store_line("  self_modulate=" + str(nvg_node.self_modulate))
				f.store_line("  z_index=" + str(nvg_node.z_index))
				f.store_line("  light_mask=" + str(nvg_node.light_mask))
			if nvg_node is CanvasLayer:
				f.store_line("  layer=" + str((nvg_node as CanvasLayer).layer))
				f.store_line("  follow_viewport=" + str((nvg_node as CanvasLayer).follow_viewport_enabled))
			_dump_nvg_node(f, nvg_node, 0, 15)
		else:
			f.store_line("  NVG node not found under Map/Core/UI")
			f.store_line("  Children of UI:")
			for c in ui_node.get_children():
				f.store_line("    " + c.name + " (" + c.get_class() + ") vis=" + str(c.visible if c is CanvasItem else "n/a"))

		# Also dump Effects node since it might contain NVG-related overlays
		var effects_node = ui_node.get_node_or_null("Effects")
		if effects_node:
			f.store_line("")
			f.store_line("── Effects Node (" + effects_node.get_class() + ") vis=" + str(effects_node.visible) + " ──")
			_dump_nvg_node(f, effects_node, 0, 10)
	else:
		f.store_line("  Map/Core/UI not found!")

	# ── 2. Scan for all WorldEnvironment nodes in the scene ──
	f.store_line("")
	f.store_line("── WorldEnvironment Nodes ──")
	var we_nodes = _find_nodes_of_class(get_tree().root, "WorldEnvironment", 6)
	if we_nodes.size() == 0:
		f.store_line("  (none found in scene, depth 6)")
	for we in we_nodes:
		f.store_line("  " + str(we.get_path()) + " vis=" + str(we.visible if we is Node3D else "n/a"))
		var env = we.get("environment")
		if env and env is Environment:
			_dump_environment(f, env, "    ")

	# ── 3. Check camera's own environment ──
	f.store_line("")
	f.store_line("── Camera Environments ──")
	if game_camera and is_instance_valid(game_camera):
		var cam_env = game_camera.get("environment")
		if cam_env and cam_env is Environment:
			f.store_line("  game_camera (" + str(game_camera.get_path()) + ") has environment:")
			_dump_environment(f, cam_env, "    ")
		else:
			f.store_line("  game_camera has no environment override")
	if xr_camera and is_instance_valid(xr_camera):
		var xr_env = xr_camera.get("environment")
		if xr_env and xr_env is Environment:
			f.store_line("  xr_camera has environment:")
			_dump_environment(f, xr_env, "    ")
		else:
			f.store_line("  xr_camera has no environment override")

	# ── 4. Check for CanvasLayer nodes at the root level (post-processing overlays) ──
	f.store_line("")
	f.store_line("── Root-level CanvasLayers ──")
	for child in get_tree().root.get_children():
		if child is CanvasLayer:
			f.store_line("  " + child.name + " layer=" + str((child as CanvasLayer).layer) + " vis=" + str(child.visible))
	var map_node = get_tree().root.get_node_or_null("Map")
	if map_node:
		for child in map_node.get_children():
			if child is CanvasLayer:
				f.store_line("  Map/" + child.name + " layer=" + str((child as CanvasLayer).layer) + " vis=" + str(child.visible))

	f.store_line("")
	f.store_line("=== END NVG & ENVIRONMENT DUMP ===")
	f.close()
	print("[VR Mod] NVG & environment dump written to vr_mod_debug.log (F11)")


func _dump_nvg_node(f: FileAccess, node: Node, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		return
	var indent = "  ".repeat(depth + 1)
	var line = indent + node.name + " (" + node.get_class() + ")"

	if node.get_script():
		line += " script=" + str(node.get_script().resource_path)
		# Dump script variables
		var prop_strs := []
		for prop in node.get_property_list():
			if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var pname: String = prop["name"]
				var val = node.get(pname)
				if val != null and str(val).length() < 200:
					prop_strs.append(pname + "=" + str(val))
		if prop_strs.size() > 0:
			line += "\n" + indent + "  PROPS: " + " | ".join(prop_strs)

	if node is CanvasItem:
		var ci = node as CanvasItem
		line += " vis=" + str(ci.visible)
		if ci.modulate != Color(1, 1, 1, 1):
			line += " modulate=" + str(ci.modulate)
		if ci.self_modulate != Color(1, 1, 1, 1):
			line += " self_mod=" + str(ci.self_modulate)
		if ci.material:
			line += " mat=" + ci.material.get_class()
			if ci.material is ShaderMaterial:
				var sm = ci.material as ShaderMaterial
				line += " shader=" + str(sm.shader.resource_path if sm.shader else "null")
				if sm.shader:
					for param in sm.shader.get_shader_uniform_list():
						var pname: String = param["name"]
						var val = sm.get_shader_parameter(pname)
						var val_str = str(val)
						if val is Texture2D and val.resource_path != "":
							val_str = val.resource_path
						line += "\n" + indent + "  uniform " + pname + " type=" + str(param["type"]) + " val=" + val_str

	if node is Control:
		var ctrl = node as Control
		line += " pos=" + str(ctrl.position) + " size=" + str(ctrl.size)
		line += " anchors=(" + str(ctrl.anchor_left) + "," + str(ctrl.anchor_top) + "," + str(ctrl.anchor_right) + "," + str(ctrl.anchor_bottom) + ")"

	if node is TextureRect:
		var tr = node as TextureRect
		if tr.texture:
			line += " tex=" + tr.texture.get_class()
			if tr.texture.resource_path != "":
				line += " res=" + tr.texture.resource_path
			if tr.texture is ViewportTexture:
				line += " vp=" + str(tr.texture.viewport_path)
			line += " tex_size=" + str(tr.texture.get_size())
		line += " stretch=" + str(tr.stretch_mode)

	if node is ColorRect:
		line += " color=" + str((node as ColorRect).color)

	if node is CanvasLayer:
		var cl = node as CanvasLayer
		line += " layer=" + str(cl.layer)
		line += " follow_vp=" + str(cl.follow_viewport_enabled)

	if node is SubViewport:
		var sv = node as SubViewport
		line += " vp_size=" + str(sv.size) + " update=" + str(sv.render_target_update_mode)
		line += " transparent=" + str(sv.transparent_bg)

	f.store_line(line)
	for child in node.get_children():
		_dump_nvg_node(f, child, depth + 1, max_depth)


func _dump_environment(f: FileAccess, env: Environment, indent: String) -> void:
	f.store_line(indent + "bg_mode=" + str(env.background_mode))
	f.store_line(indent + "ambient_mode=" + str(env.ambient_light_source))
	f.store_line(indent + "ambient_color=" + str(env.ambient_light_color))
	f.store_line(indent + "ambient_energy=" + str(env.ambient_light_energy))
	f.store_line(indent + "tonemap_mode=" + str(env.tonemap_mode))
	f.store_line(indent + "tonemap_exposure=" + str(env.tonemap_exposure))
	f.store_line(indent + "tonemap_white=" + str(env.tonemap_white))
	# Adjustment (color correction)
	f.store_line(indent + "adjustment_enabled=" + str(env.adjustment_enabled))
	if env.adjustment_enabled:
		f.store_line(indent + "  brightness=" + str(env.adjustment_brightness))
		f.store_line(indent + "  contrast=" + str(env.adjustment_contrast))
		f.store_line(indent + "  saturation=" + str(env.adjustment_saturation))
		if env.adjustment_color_correction:
			f.store_line(indent + "  color_correction=" + str(env.adjustment_color_correction.resource_path))
	# Glow
	f.store_line(indent + "glow_enabled=" + str(env.glow_enabled))
	if env.glow_enabled:
		f.store_line(indent + "  glow_intensity=" + str(env.glow_intensity))
		f.store_line(indent + "  glow_strength=" + str(env.glow_strength))
		f.store_line(indent + "  glow_bloom=" + str(env.glow_bloom))
		f.store_line(indent + "  glow_blend_mode=" + str(env.glow_blend_mode))
	# Fog
	f.store_line(indent + "fog_enabled=" + str(env.fog_enabled))
	if env.fog_enabled:
		f.store_line(indent + "  fog_color=" + str(env.fog_light_color))
		f.store_line(indent + "  fog_density=" + str(env.fog_density))
	# SSAO / SSIL / SSR (may not all be available in Forward Mobile)
	f.store_line(indent + "ssao_enabled=" + str(env.ssao_enabled))
	f.store_line(indent + "ssil_enabled=" + str(env.ssil_enabled))
	f.store_line(indent + "ssr_enabled=" + str(env.ssr_enabled))


func _find_nodes_of_class(root: Node, class_name_str: String, max_depth: int, _depth: int = 0) -> Array:
	var result := []
	if root.get_class() == class_name_str or root.is_class(class_name_str):
		result.append(root)
	if _depth < max_depth:
		for child in root.get_children():
			result.append_array(_find_nodes_of_class(child, class_name_str, max_depth, _depth + 1))
	return result
