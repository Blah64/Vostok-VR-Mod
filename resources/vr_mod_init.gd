extends Node

# Road to Vostok VR Mod - Autoload Initialization Script
# HUD Strategy: Share main viewport's World2D with a secondary SubViewport
# (disable_3d=true). No node reparenting — all game references stay intact.
#
# When inventory is CLOSED: HUD quad follows head (head-locked)
# When inventory is OPEN: quad detaches, scales up, stays in world space
# Controller pointing + trigger click for inventory interaction.

var _log_path    := "user://vr_mod/vr_mod_debug.log"
var _config_path := "user://vr_mod/vr_mod_config.json"
var _assets_base := "res://resources/hands/"

var xr_interface: XRInterface
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var left_controller: XRController3D
var right_controller: XRController3D
var game_camera: Camera3D
var _phase := 0  # 0=waiting_for_camera, 1=xr_activating, 2=running
var _frames_waited := 0
var _level_transition_count := 0
var _xr_ready := false
var _weapons_reparented := false
var _camera_lost_frames := 0  # Frames since camera was lost; disables use_xr if > 120

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
var _weapon_is_long := false  # True for rifles/shotguns that support two-hand aim
var _recoil_rest_xform := Transform3D.IDENTITY  # Cached rest pose of recoil chain
var _prev_recoil_mag := 0.0         # recoil chain origin magnitude last frame; rising edge = shot
var _fire_haptic_cooldown := 0.0    # seconds until next fire haptic allowed
var _disable_walk_sway := false  # Skip Sway node contribution in chain delta (walk/movement bob); keeps Noise stamina wobble intact
var _grenade_pin_pulled := false   # True after pin pulled; grip release = throw
var _weapon_raise_timer := -1.0  # Timer to auto-raise weapon after equip
var _pending_holster_key: int = -1  # KEY_N pending delayed injection on holster; -1 = none
var _holster_cooldown := 0.0        # Seconds remaining before a new draw is allowed after holstering

# Holster system
enum HolsterState { UNARMED, DRAWN, LOWERED, SLING }
var _holster_state: int = HolsterState.UNARMED
var _weapon_hand := ""  # "left" or "right" — which hand currently holds weapon
var _weapon_slot := 0   # 1-4 mapped to KEY_1..KEY_4, 0 = none
var _transition_slot := 0   # slot saved across level transition (0 = was unarmed)
var _transition_hand := ""  # hand saved across level transition
var _weapon_subtype := ""           # "Shotgun", "Bolt", etc. — from data resource
var _weapon_uses_r_reload := false  # True for Bolt/Shotgun: action open/close + manual ammo load
var _action_open := false           # True while weapon action is open (Ctrl toggled)
var _pump_gesture_active := false   # True after forward phase detected
var _pump_fwd_dir := Vector3.ZERO   # Direction of support hand motion in forward phase
var _pump_prev_pos := Vector3.ZERO  # Support hand position last frame (zero = uninitialized)
var _pump_gesture_timer := 0.0      # Time remaining for reverse phase to complete
var _pump_cooldown := 0.0           # Prevents rapid repeat

const HOLSTER_ZONES := {
	1: {"name": "right_shoulder", "key": KEY_1},
	2: {"name": "right_hip",      "key": KEY_2},
	3: {"name": "left_hip",       "key": KEY_3},
	4: {"name": "chest",          "key": KEY_4},
}
# Per-slot offsets (runtime-tunable, loaded from config)
var _holster_offsets := {
	1: Vector3(0.25, -0.15,  0.0),
	2: Vector3(0.25, -0.55,  0.0),
	3: Vector3(-0.25, -0.55, 0.0),
	4: Vector3(0.0,  -0.15,  0.10),
}
var _holster_zone_radius := 0.27
var _sling_offset := Vector3(0.2, -0.31, -0.06)    # primary weapon sling pos relative to head (yaw only)
var _sling_rot_offset := Vector3(0.0, 60.0, 0.0)   # extra pitch/yaw/roll applied on top of slot rotation (degrees)
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
var _nvg_mono := true                   # config: mono vision (same image both eyes)
var _nvg_mono_viewport: SubViewport     # mono render SubViewport (created on demand)
var _nvg_mono_camera: Camera3D          # mono render camera (centered between eyes)
var _nvg_brightness := 5.0             # config: brightness multiplier
var _nvg_overlay_installed := false

# Decor mode (shelter furniture placement)
var _decor_mode := false
var _decor_scroll_mode := 0       # 0 = distance, 1 = rotation
var _decor_scroll_cooldown := 0.0
var _left_grip_held := false
var _right_grip_held := false
# Long-press X (left, UNARMED/LOWERED) to enter decor mode; short-press = flashlight
var _decor_x_pending := false
var _decor_x_press_time := 0.0

# Per-weapon grip offsets in aim-local space (keyed by weapon name, e.g. "MK18")
# Falls back to slot defaults when a weapon has no saved config.
var _weapon_grip_offsets := {}     # {weapon_name: Vector3}
var _weapon_grip_rotations := {}   # {weapon_name: float}
var _current_weapon_name := ""     # weapon rig name minus "_Rig"; set each frame from rig
# Slot-based fallback defaults used until a weapon is explicitly calibrated
var _slot_grip_defaults := {
	1: Vector3(0.122, -0.233, -0.876),
	2: Vector3(0.102, -0.301, -1.121),
	3: Vector3(0.105,  0.087, -0.327),
	4: Vector3(0.09,  -0.302, -0.958),
}
var _slot_rot_defaults := { 1: 1.1, 2: 3.0, 3: -94.7, 4: -69.7 }

# VR hand skeletal models (godot-xr-tools lowpoly hands loaded at runtime via GLTFDocument)
# Each controller gets a Node3D wrapper (required — MeshInstance3D cannot be a direct child
# of XRController3D in Forward Mobile) containing the .gltf scene with its Skeleton3D.
# Finger curl is driven procedurally from grip/trigger analog each frame.
var _hand_wrapper_left: Node3D = null
var _hand_load_errors: Array = []   # buffered across the log reset in _install_xr_rig
var _hand_wrapper_right: Node3D = null
var _hand_skel_left: Skeleton3D = null
var _hand_skel_right: Skeleton3D = null
var _hand_fingers_left: Dictionary = {}   # {"thumb":[bone_idx,..], "index":[...], ...}
var _hand_fingers_right: Dictionary = {}
var _hand_bone_rest_left: Dictionary = {}   # {bone_idx: Quaternion (rest rotation)}
var _hand_bone_rest_right: Dictionary = {}
var _hand_tex: ImageTexture = null         # shared skin texture (loaded once, reused for both hands)
# Smoothed per-finger curl values in [0, 1]
var _hand_curl_left := {"thumb": 0.0, "index": 0.0, "middle": 0.0, "ring": 0.0, "little": 0.0}
var _hand_curl_right := {"thumb": 0.0, "index": 0.0, "middle": 0.0, "ring": 0.0, "little": 0.0}
# Curl animation params. Stored as vars (not const) — Godot 4.6 rejects const Vector3(...)
# literals with a parse error.
# Thumb bones are oriented with their flexion axis along local X.
# Finger bones (index/middle/ring/little) are oriented with flexion along local Z
# (local X is the lateral / spread axis for finger bones).
# All angles are negated so the rotation curls toward the palm.
var HAND_CURL_AXIS_THUMB := Vector3(1, 0, 0)   # thumb flexion: local X, negative angle
var HAND_CURL_AXIS_FINGER := Vector3(0, 0, 1)  # finger flexion: local Z, negative angle
# Per-joint curl weight (proximal, intermediate, distal). Fingers use all 3; thumb uses [0, 2].
var HAND_FINGER_JOINT_WEIGHT := [0.9, 1.0, 1.0]
var HAND_FINGER_MAX_CURL := 1.45  # ~83 degrees per joint at full curl
var HAND_THUMB_MAX_CURL := 0.9
var HAND_CURL_SMOOTH_SPEED := 20.0
var HAND_GLTF_OFFSET_LEFT := Vector3(-0.03, -0.015, 0.195)
var HAND_GLTF_OFFSET_RIGHT := Vector3(0.025, 0.01, 0.195)
var HAND_GLTF_ROTATION_LEFT := Vector3(0.0, 0.0, 0.0)   # extra rotation offset in degrees for left hand wrapper
var HAND_GLTF_ROTATION_RIGHT := Vector3(0.0, 0.0, 0.0)  # extra rotation offset in degrees for right hand wrapper

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

# Rail movement (optic slide along rail)
var _rail_mode := false               # Rail slide mode active (X long-press while DRAWN)
var _rail_x_press_time := 0.0         # Time when X was pressed (for long-press detection)
var _rail_x_pending := false           # X pressed, waiting to determine short vs long press
var _rail_active := false              # Physical rail slide in progress (trigger held)
var _rail_grab_origin := 0.0           # Off-hand projected position at grab start
var _rail_scroll_accum := 0.0          # Accumulated movement for physical grab
var _rail_scroll_cooldown := 0.0       # Cooldown for stick-based scrolling

# Support trigger long-press detection (short = reload, long = ammo check)
var _support_trigger_pending := false
var _support_trigger_press_time := 0.0
var _ammo_check_timer := 0.0        # > 0 while ammo panel is visible; counts down to hide
var _ammo_panel_vp: SubViewport = null
var _ammo_panel_mesh: MeshInstance3D = null
var _ammo_read_delay := 0           # frames to wait before reading labels after KEY_V

# Grip adjust mode — tune offsets live with thumbsticks
var _gun_config_enabled := false      # Enables grip adjust and foregrip adjust modes
var _adjust_mode := false
var _adjust_saved_offset := Vector3.ZERO  # Backup to discard changes
var _adjust_saved_rotation := 0.0
const ADJUST_SPEED := 0.15  # Meters per second for position
const ADJUST_ROT_SPEED := 45.0  # Degrees per second for rotation

# Foregrip adjust mode — tune two-hand foregrip offset live (X while off-hand gripping)
var _slot_foregrip_offsets := { 1: Vector3(-0.11, 0.038, -0.108), 2: Vector3.ZERO, 3: Vector3.ZERO, 4: Vector3.ZERO }
var _fg_adjust_mode := false
var _fg_adjust_saved_offset := Vector3.ZERO  # kept for potential compat; not used for adjust
var _fg_adjust_frozen_xform := Transform3D.IDENTITY  # weapon transform frozen at adjust entry
var _fg_adjust_saved_p := Vector3.ZERO    # per-slot p saved for discard
var _fg_adjust_saved_r := Basis.IDENTITY  # per-slot r saved for discard
var _weapon_fg_p_local := {}   # weapon-local foregrip position per weapon name
var _weapon_fg_r_local := {}   # weapon-local foregrip rotation (Basis) per weapon name
var _fg_p_sup_local := Vector3.ZERO   # active foregrip position in weapon_rig local space
var _fg_r_sup_local := Basis.IDENTITY # active foregrip rotation in weapon_rig local space
var _fg_grip_captured := false         # true while the foregrip lock is active
var _cached_weapon_rig: Node3D = null  # last weapon_rig ref, used for adjust mode entry/save


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


func _is_decor_placing() -> bool:
	# Check if a furniture ghost preview is active (item selected for placement).
	# The game creates a "Hint" MeshInstance3D under /root/Map/ when placing.
	var map_node = get_tree().root.get_node_or_null("Map")
	if not map_node:
		return false
	var hint = map_node.get_node_or_null("Hint")
	return hint != null and hint is MeshInstance3D and hint.visible


func _toggle_decor_mode() -> void:
	_decor_mode = not _decor_mode
	_inject_key(KEY_F1, true)
	_inject_key(KEY_F1, false)
	if _decor_mode:
		_decor_scroll_mode = 0
		_decor_scroll_cooldown = 0.0
		# Ensure Placer starts in distance mode
		if game_camera:
			var placer = game_camera.get_node_or_null("Placer")
			if placer:
				placer.set("rotateMode", false)
		_log("[VR Mod] === DECOR MODE ON ===")
		if left_controller:
			left_controller.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.2, 0.0)
		if right_controller:
			right_controller.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.2, 0.0)
	else:
		# Reset Placer to distance mode on exit
		if game_camera:
			var placer = game_camera.get_node_or_null("Placer")
			if placer:
				placer.set("rotateMode", false)
		_log("[VR Mod] === DECOR MODE OFF ===")
		if left_controller:
			left_controller.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.15, 0.0)
		if right_controller:
			right_controller.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.15, 0.0)


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
	# Player manually drew — pre-transition slot is no longer relevant.
	_transition_slot = 0
	_transition_hand = ""

	# Cancel any pending holster KEY injection — prevents double-toggle when
	# holster and draw happen within 0.15 s of each other.
	_pending_holster_key = -1

	# Inject the key to equip this weapon slot
	var key: int = HOLSTER_ZONES[slot]["key"]
	_inject_key(key, true)
	get_tree().create_timer(0.1).timeout.connect(func(): _inject_key(key, false))

	# Start weapon load detection + auto-raise sequence
	_weapon_loaded = false
	_weapon_is_long = false
	_recoil_rest_xform = Transform3D.IDENTITY
	_prev_recoil_mag = 0.0
	_fire_haptic_cooldown = 0.0
	_walk_sway_captured = false
	_walk_sway_logged = false
	_rest_capture_pending = false
	_walk_sway_capture_delay = 0.0
	_clear_grenade_state()
	_weapon_raise_timer = 3.0
	_scroll_cooldown = 1.0
	_fixed_reticle_instances.clear()  # Re-scan for reticle on new weapon
	_cleanup_scope()  # Re-detect scope on new weapon


func _lower_weapon() -> void:
	print("[VR Mod] LOWER weapon (slot ", _weapon_slot, ")")
	_adjust_mode = false
	_fg_adjust_mode = false
	if _rail_mode:
		_exit_rail_mode()
	_clear_grenade_state()
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


func _enter_sling() -> void:
	print("[VR Mod] SLING weapon (slot ", _weapon_slot, ")")
	_adjust_mode = false
	_fg_adjust_mode = false
	if _rail_mode:
		_exit_rail_mode()
	_clear_grenade_state()
	_holster_state = HolsterState.SLING
	_support_grip_held = false
	# weapon_low signals the game to recharge arm stamina and show the aiming laser
	_inject_action("weapon_low", true)
	get_tree().create_timer(0.1).timeout.connect(func(): _inject_action("weapon_low", false))
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
	_fg_adjust_mode = false
	if _rail_mode:
		_exit_rail_mode()
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
	_current_weapon_name = ""
	_weapon_loaded = false
	_weapon_is_long = false
	_weapon_subtype = ""
	_weapon_uses_r_reload = false
	_action_open = false
	_pump_gesture_active = false
	_pump_prev_pos = Vector3.ZERO
	_pump_cooldown = 0.0
	_recoil_rest_xform = Transform3D.IDENTITY
	_prev_recoil_mag = 0.0
	_fire_haptic_cooldown = 0.0
	_walk_sway_captured = false
	_walk_sway_logged = false
	_rest_capture_pending = false
	_walk_sway_capture_delay = 0.0
	_clear_grenade_state()
	_support_grip_held = false
	_holster_cooldown = 0.8  # Block re-draw until animation completes


# HUD
var hud_viewport: SubViewport
var _watch_b_vp: SubViewport = null  # Second viewport for Medical element (separate crop)
var hud_mesh: MeshInstance3D
var _hud_installed := false
var _interface_open := false
var _prev_interface_open := false  # For detecting transitions
var _laser_mesh: MeshInstance3D   # Visual laser pointer line (dual-purpose: grab range + UI pointer)
var _laser_always_on := true      # When false, laser hidden unless pointing at something interactable
var _hover_label: Label3D = null  # Floating item name shown when aiming at interactable/grabbable
var _menu_open := false           # True while inventory/menu is visible
var _menu_ctrl_held := false      # True while support grip is held in menus (Ctrl modifier for fast transfer)
var _esc_menu_active := false     # True while ESC menu is open (toggled by menu button; forces _interface_open)
var _laser_screen_pos := Vector2(-1, -1)  # Current cursor position from laser
var _menu_click_pos := Vector2(-1, -1)    # Cursor position snapshotted at mouse-down for button release
var _menu_dragging := false               # True once cursor moved far enough from press to be a drag
var _laser_diag_logged := false  # One-shot diagnostic log on first laser update per menu open
var _esc_hovered_control: Control = null  # Currently hovered ESC menu control (for manual hover)

# HUD sizing (vars so config screen can change them at runtime)
var _hud_width := 2.3
var _hud_distance := 0.9
var _hud_height_offset := -0.05
var _menu_width := 3.0
var _menu_distance := 1.0
var _hud_lr_offset := 0.0
var _menu_lr_offset := 0.0
var _hud_smooth_follow := true
var _hud_smooth_speed := 2.0
var _hud_yaw := 0.0         # Lagged yaw for smooth follow — tracked separately, never read from mesh
var _hud_spread := 0.5      # HUD element spread (1.0 = default, <1 = closer together)
var _hud_spread_active := 1.0  # Spread value actually used by _apply_hud_spread (watch vs menu)
var _menu_laser_uv_x := 0.0  # Horizontal laser offset for menu/inventory (UV units)
var _menu_laser_uv_y := 0.0  # Vertical laser offset for menu/inventory (UV units)

# Wrist watch HUD
var _watch_mesh: MeshInstance3D       # Watch face quad, child of hand model Node3D
var _watch_alpha := 0.0               # Fade alpha (0=hidden, 1=visible)
var _watch_size := 0.15               # Watch quad side length (metres)
var _watch_glance_enabled := false    # Glance-to-reveal on/off (off = always visible)
var _watch_glance_angle := 40.0       # Max gaze angle (degrees) for reveal
var _watch_fade_speed := 8.0          # Alpha lerp speed (units/sec)
var _watch_spread := 0.15             # Compact spread for watch mode
var _watch_offset := Vector3(-0.06, -0.08, 0.34)  # X/Y/Z offset on hand model
var _watch_rot := Vector3(180.0, 90.0, -90.0)     # Extra rotation offset in degrees (base -90 X is always applied)
var _vitals_node: Control = null             # Reference only — stays in game HUD tree
var _medical_node: Control = null            # Reference only — stays in game HUD tree
var _watch_crop_delay := 0                   # Countdown frames before reading node rects
var _watch_crop_computed := false            # True once crop canvas_transform is applied
var _watch_crop_retries := 0                 # How many times _compute_watch_crop has run

# Config screen
var _config_screen_open := false
var _config_panel_vp: SubViewport = null
var _config_panel_quad: MeshInstance3D = null
var _config_laser_pos := Vector2.ZERO

# Config
var world_scale := 1.0
var _render_scale := 1.0
var snap_turn_degrees := 45.0
var smooth_turn_speed := 120.0
var use_snap_turn := false
var thumbstick_deadzone := 0.15
var _config_dominant_hand := "right"
var _standing_mode := false          # false = sitting (fixed height), true = standing (physical height)
var _standing_mode_resnap := 0       # frames remaining before re-snapping origin after mode change
var _standing_height_ref := 0.0      # xr_camera.position.y captured at full upright height (STAGE space)
var _physical_crouch_threshold := 0.4  # metres below standing height to trigger game crouch
var _physical_crouch_active := false
var _physical_crouch_resnap := 0      # frames to freeze Y + wait before re-snapping after release
var _snap_turn_cooldown := false
var _last_game_cam_pos := Vector3.ZERO

# Two-hand aim stabilization
var _two_hand_smooth_enabled := true
var _two_hand_smooth_speed := 14.0
var _two_hand_smooth_basis := Basis.IDENTITY
var _two_hand_was_active := false
var _arc_raw_aim_basis := Basis.IDENTITY  # unsmoothed raw aim for arc_comp; seeded on two-hand start to prevent position jump

# Comfort vignette
var _vignette_enabled := false
var _vignette_strength := 0.7
var _vignette_mesh: MeshInstance3D = null
var _vignette_radius := 1.0   # current inner edge (1.0 = off screen, smaller = more coverage)
var _vignette_hold := 0.0     # seconds; >0 = vignette active


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
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep running even if game pauses (ESC menu)
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

	# Create XR rig early so head tracking accumulates before _install_xr_rig() runs.
	# xr_camera.position.y is valid once the node is in the tree — no need for current=true.
	# use_xr stays false until the game camera is found (avoids gray screen during loading).
	xr_origin = XROrigin3D.new()
	xr_origin.name = "VRModOrigin"
	xr_origin.world_scale = world_scale
	add_child(xr_origin)
	xr_camera = XRCamera3D.new()
	xr_camera.name = "VRModCamera"
	xr_origin.add_child(xr_camera)
	# Apply tracking mode from config now that the interface is ready.
	if _standing_mode and xr_interface:
		xr_interface.play_area_mode = XRInterface.XR_PLAY_AREA_ROOMSCALE
		print("[VR Mod] Tracking: standing (roomscale)")
	else:
		print("[VR Mod] Tracking: sitting (local)")
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
				if not game_camera or not is_instance_valid(game_camera):
					# Camera lost or freed (level transition). Poll for new one.
					_camera_lost_frames += 1
					if _frames_waited % CAMERA_POLL_INTERVAL == 0:
						if game_camera:
							print("[VR Mod] Game camera lost (level transition?) — searching...")
						game_camera = _find_game_camera(get_tree().root)
						if game_camera:
							_attach_rig_to_camera()
							_on_level_transition()
							_camera_lost_frames = 0
							print("[VR Mod] Camera found again")
					# After ~2 seconds without a camera (main menu), gracefully quit
					elif _camera_lost_frames > 120 and get_viewport().use_xr:
						print("[VR Mod] Camera lost for 2+ seconds (main menu detected) — quitting game")
						get_tree().quit()

				if not _hud_installed and _frames_waited >= HUD_SETUP_DELAY:
					_setup_vr_hud()

				# Retry weapon reparenting until it succeeds (nodes may load late)
				if not _weapons_reparented and _frames_waited % 60 == 0:
					_reparent_camera_children()

				# Scroll cooldown tick
				if _scroll_cooldown > 0:
					_scroll_cooldown -= delta
				if _rail_scroll_cooldown > 0:
					_rail_scroll_cooldown -= delta

				# Rail mode: long-press detection for X button
				if _rail_x_pending:
					var elapsed = Time.get_ticks_msec() / 1000.0 - _rail_x_press_time
					if elapsed >= 0.3:
						_rail_x_pending = false
						_enter_rail_mode()

				# Decor mode: long-press X while unarmed/lowered
				if _decor_x_pending:
					var elapsed_dx: float = Time.get_ticks_msec() / 1000.0 - _decor_x_press_time
					if elapsed_dx >= 0.5:
						_decor_x_pending = false
						if _holster_state in [HolsterState.UNARMED, HolsterState.LOWERED] and not _interface_open:
							_toggle_decor_mode()
							left_controller.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.25, 0.0)

				# Support trigger: long-press = ammo check (KEY_V)
				if _support_trigger_pending:
					var elapsed = Time.get_ticks_msec() / 1000.0 - _support_trigger_press_time
					if elapsed >= 0.5:
						_support_trigger_pending = false
						_inject_key(KEY_V, true)
						_inject_key(KEY_V, false)
						var support_ctrl = _get_controller(_get_support_hand())
						if support_ctrl:
							support_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.2, 0.1, 0.0)
						_ammo_read_delay = 3
						print("[VR Mod] AMMO CHECK (support trigger long-press)")

				# Ammo check: wait a few frames for game to update labels after KEY_V
				if _ammo_read_delay > 0:
					_ammo_read_delay -= 1
					if _ammo_read_delay == 0:
						_show_ammo_check_panel()

				# Ammo check panel auto-hide countdown + weapon-hand tracking
				if _ammo_check_timer > 0.0:
					_ammo_check_timer -= delta
					if _ammo_check_timer <= 0.0:
						_hide_ammo_check_panel()
					elif _ammo_panel_mesh and is_instance_valid(_ammo_panel_mesh) and xr_camera:
						_update_ammo_panel_position()

				# Shotgun pump gesture: forward+back motion between hands injects R
				if _weapon_subtype == "Shotgun" and _holster_state == HolsterState.DRAWN and _support_grip_held and not _action_open:
					_update_pump_gesture(delta)

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
						_weapon_is_long = _classify_weapon_is_long(wep)
						_weapon_subtype = _get_weapon_subtype(wep)
						_weapon_uses_r_reload = _weapon_subtype == "Shotgun" or _weapon_subtype == "Bolt"
						_action_open = false
						_pump_gesture_active = false
						_pump_prev_pos = Vector3.ZERO
						# Defer rest capture until Handling.gd has animated the
						# weapon from pre-raise offset to its aimed position, so
						# _recoil_rest_xform and _walk_sway_rest agree on the
						# steady-state aimed pose. Capturing at load time locks
						# _recoil_rest_xform at (0,-0.5,-0.5) which creates a ~0.7m
						# jump whenever walk-sway is toggled.
						_recoil_rest_xform = Transform3D.IDENTITY
						_walk_sway_captured = false
						_walk_sway_logged = false
						_rest_capture_pending = true
						_walk_sway_capture_delay = _WALK_SWAY_CAPTURE_DELAY_LOAD
						# After a level transition with a weapon equipped, restore DRAWN
						# state so the mod resumes controlling weapon position/arm hiding.
						# The raise timer below will then inject weapon_high correctly.
						if _transition_slot > 0 and _holster_state == HolsterState.UNARMED:
							_holster_state = HolsterState.DRAWN
							_weapon_slot = _transition_slot
							_weapon_hand = _transition_hand
							print("[VR Mod] Restoring DRAWN state: slot=", _weapon_slot, " hand=", _weapon_hand)
							_transition_slot = 0
							_transition_hand = ""
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

				# Re-snap origin a few frames after tracking mode switch (reference space settles)
				if _standing_mode_resnap > 0:
					_standing_mode_resnap -= 1
					if _standing_mode_resnap == 0:
						_attach_rig_to_camera()
						print("[VR Mod] Origin re-snapped after tracking mode change")
						if _standing_mode and xr_camera:
							_standing_height_ref = xr_camera.position.y
							if _standing_height_ref < 0.3:
								_standing_height_ref = 1.6
							print("[VR Mod] Standing height reference: ", _standing_height_ref, "m")

				if _physical_crouch_resnap > 0:
					_physical_crouch_resnap -= 1
					if _physical_crouch_resnap == 0:
						_attach_rig_to_camera()
						if _standing_mode and xr_camera:
							_standing_height_ref = xr_camera.position.y
							if _standing_height_ref < 0.3:
								_standing_height_ref = 1.6
						print("[VR Mod] Origin re-snapped after physical crouch release")

				# Holster zone haptic feedback
				_update_holster_zone_haptics()
				_update_nvg_overlay(delta)
				_update_comfort_vignette(delta)
				_update_physical_crouch()

				# Keep game camera from reclaiming "current" (causes blur/glow artifacts)
				if game_camera and is_instance_valid(game_camera) and game_camera.current:
					game_camera.current = false
					xr_camera.current = true

				_update_interface_state()
				_sync_origin_to_game()
				_process_input(delta)
				_update_rail_slide()

				# Repeating haptic while grenade pin is pulled
				if _grenade_pin_pulled:
					var _wctrl = _get_controller(_get_weapon_hand())
					if _wctrl and _wctrl.get_is_active():
						_wctrl.trigger_haptic_pulse("haptic", 0.0, 0.15, 0.05, 0.0)

				# Sync weapon AFTER origin/camera so our position override wins
				if not _decor_mode:
					_sync_weapon_to_controller()
				_update_hand_visibility()
				_update_hand_poses(delta)
				_update_grabbed()

				_update_smooth_hud(delta)

				# Wrist watch glance-to-reveal (only during gameplay)
				if not _interface_open:
					_update_watch_glance(delta)

				# Delayed crop computation: wait for HUD layout to settle
				if _watch_crop_delay > 0:
					_watch_crop_delay -= 1
					if _watch_crop_delay == 0:
						_compute_watch_crop()

				if _config_screen_open:
					_update_config_laser()
				elif _interface_open:
					_update_laser_pointer()


func _install_xr_rig() -> void:
	print("[VR Mod] Installing XR rig...")

	# xr_origin and xr_camera were created in _ready() for early HMD output.
	# Just update settings and add controllers to the existing rig.
	xr_origin.world_scale = world_scale
	xr_interface.render_target_size_multiplier = _render_scale

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

	# Extract hand GLTF assets from Metro's VMZ cache to user:// so GLTFDocument
	# can read them (res://resources/hands/ is not mounted into Godot's VFS).
	if _extract_hand_assets_from_vmz():
		_assets_base = "user://vr_mod/hands/"
	else:
		_hand_load_errors.append("hand: VMZ extraction failed — hands will use box fallback")

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


	# xr_origin is already parented to self (done in _ready()).

	if game_camera and is_instance_valid(game_camera):
		# Use the actual tracked head height instead of a hardcoded constant.
		# xr_camera.position.y is the local Y relative to xr_origin (currently at 0,0,0),
		# which equals the runtime-reported head height above the tracking floor.
		var actual_head_height := xr_camera.position.y
		if actual_head_height < 0.3:
			actual_head_height = 1.6  # fallback: tracking not yet settled
			print("[VR Mod] Head tracking not ready, using fallback 1.6m")
		else:
			print("[VR Mod] Tracked head height: ", actual_head_height, "m")
		var cam_pos = game_camera.global_position
		xr_origin.global_position = Vector3(cam_pos.x, cam_pos.y - actual_head_height, cam_pos.z)
		xr_origin.global_rotation = Vector3.ZERO
		_last_game_cam_pos = cam_pos
		if _standing_mode:
			_standing_height_ref = actual_head_height

		# Copy game camera's cull mask to XR camera so we can see
		# weapon viewmodels rendered on special visual layers
		xr_camera.cull_mask = game_camera.cull_mask
		print("[VR Mod] XR rig placed: origin=", xr_origin.global_position)
		print("[VR Mod] Copied cull_mask from game_camera: ", game_camera.cull_mask)
	else:
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

	# Ensure user data directory and default config exist
	DirAccess.make_dir_recursive_absolute("user://vr_mod")
	if not FileAccess.file_exists(_config_path):
		_save_full_config()

	# Reset debug log — MUST stay here; hand creation above logs to the old file,
	# those messages are erased. _hand_load_errors buffers them across this reset.
	var dump_path = _log_path
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
		print("[VR Mod] Debug log reset: ", dump_path)

	# Flush buffered hand load messages (written before the reset above)
	for msg in _hand_load_errors:
		_log(msg)
	_hand_load_errors.clear()

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

	# Floating hover label — shows item/interactable name when laser aims at it
	_hover_label = Label3D.new()
	_hover_label.name = "HoverLabel"
	_hover_label.font_size = 48
	_hover_label.pixel_size = 0.001
	_hover_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hover_label.no_depth_test = true
	_hover_label.render_priority = 10
	_hover_label.outline_size = 6
	_hover_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_hover_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_hover_label.visible = false
	add_child(_hover_label)

	_setup_comfort_vignette()

	print("[VR Mod] === VR rig active ===")


func _setup_vr_hud() -> void:
	print("[VR Mod] Setting up VR HUD (World2D sharing)...")

	var main_vp = get_viewport()
	# Use the main viewport's visible rect as the canvas design size. This is the
	# coordinate space the game's 2D Controls are laid out in, and it's what we
	# need the SubViewport to match so UVs map 1:1 to Control positions.
	# Mouse-event positions are then mapped to the actual window pixel space via
	# the viewport's canvas_transform in _update_laser_pointer.
	var vp_size = main_vp.get_visible_rect().size
	var win_size_for_log = DisplayServer.window_get_size()
	var win := get_window()
	var cs_size = win.content_scale_size if win else Vector2i.ZERO
	_log("HUD sizes: visible_rect=" + str(vp_size) + " win=" + str(win_size_for_log) + " content_scale=" + str(cs_size) + " canvas_xform=" + str(main_vp.canvas_transform) + " global_canvas_xform=" + str(main_vp.global_canvas_transform))
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

	# Second viewport for Medical element — same setup, separate canvas_transform
	_watch_b_vp = SubViewport.new()
	_watch_b_vp.name = "VRWatchMedVP"
	_watch_b_vp.size = Vector2i(int(vp_size.x), int(vp_size.y))
	_watch_b_vp.transparent_bg = true
	_watch_b_vp.disable_3d = true
	_watch_b_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_watch_b_vp.world_2d = main_vp.world_2d
	_watch_b_vp.gui_disable_input = true
	add_child(_watch_b_vp)

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

	# Park hud_mesh invisibly under self — watch takes over during gameplay
	# hud_mesh is still used for menus/inventory (shown by _on_interface_opened)
	hud_mesh.visible = false
	add_child(hud_mesh)

	_hud_installed = true

	# Set compact spread, set up dedicated watch content VP, then create watch mesh
	_hud_spread_active = _watch_spread
	_apply_hud_spread()
	_setup_watch_content()
	_log("HUD viewport ready, creating watch mesh...")
	_create_watch_mesh()
	if _watch_mesh:
		_log("Watch mesh created OK, visible=" + str(_watch_mesh.visible) + " layers=" + str(_watch_mesh.layers))
	else:
		_log("WARNING: watch mesh is null after _create_watch_mesh!")

	print("[VR Mod] VR HUD installed (wrist watch mode)")

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


func _build_vignette_ring_mesh(steps: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize(2 * steps)
	indices.resize(6 * steps)
	for i in steps:
		var v := Vector3.RIGHT.rotated(Vector3.FORWARD, deg_to_rad(360.0 * i / steps))
		vertices[i] = v
		vertices[steps + i] = v * 2.0
		var off := i * 6
		var i2 := (i + 1) % steps
		indices[off + 0] = steps + i
		indices[off + 1] = steps + i2
		indices[off + 2] = i2
		indices[off + 3] = steps + i
		indices[off + 4] = i2
		indices[off + 5] = i
	var arr_mesh := ArrayMesh.new()
	var arr := []
	arr.resize(ArrayMesh.ARRAY_MAX)
	arr[ArrayMesh.ARRAY_VERTEX] = vertices
	arr[ArrayMesh.ARRAY_INDEX] = indices
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	arr_mesh.custom_aabb = AABB(Vector3(-2, -2, -1), Vector3(4, 4, 2))
	return arr_mesh


func _setup_comfort_vignette() -> void:
	_vignette_mesh = MeshInstance3D.new()
	_vignette_mesh.name = "ComfortVignette"
	_vignette_mesh.mesh = _build_vignette_ring_mesh(32)
	var shader = Shader.new()
	shader.code = COMFORT_VIGNETTE_SHADER
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = 126
	mat.set_shader_parameter("color", Color(0, 0, 0, 1))
	mat.set_shader_parameter("radius", 1.0)
	mat.set_shader_parameter("fade", 0.15)
	_vignette_mesh.material_override = mat
	_vignette_mesh.layers = (1 << 19)  # layer 20 only
	_vignette_mesh.visible = false
	xr_camera.add_child(_vignette_mesh)
	_vignette_radius = 1.0
	print("[VR Mod] Comfort vignette installed")


func _update_comfort_vignette(delta: float) -> void:
	if not _vignette_mesh or not is_instance_valid(_vignette_mesh):
		return
	# strength 0.1 -> inner radius 0.85 (subtle), strength 1.0 -> inner radius 0.2 (strong)
	var target_inner := 1.0 - _vignette_strength * 0.8
	var target_radius := 1.0
	if _vignette_enabled and _vignette_hold > 0.0:
		_vignette_hold -= delta
		target_radius = target_inner
	# Fast fade in, slow fade out
	var speed := 5.0 if target_radius < _vignette_radius else 1.0
	_vignette_radius = move_toward(_vignette_radius, target_radius, delta * speed)
	var show := _vignette_radius < 0.99
	_vignette_mesh.visible = show
	if show:
		(_vignette_mesh.material_override as ShaderMaterial).set_shader_parameter("radius", _vignette_radius)


func _release_physical_crouch() -> void:
	# Clear state only — no injection. Used on level transitions where the new
	# character spawns standing (injecting here would crouch the fresh character).
	_physical_crouch_active = false
	_physical_crouch_resnap = 0


func _update_physical_crouch() -> void:
	if not _standing_mode or _standing_height_ref < 0.3 or not xr_camera:
		return
	var drop := _standing_height_ref - xr_camera.position.y
	if not _physical_crouch_active:
		if drop >= _physical_crouch_threshold:
			_physical_crouch_active = true
			_inject_action("crouch", true)   # toggle ON
			_inject_action("crouch", false)  # clear held state
			print("[VR Mod] Physical crouch: start (drop=", drop, "m)")
	else:
		if drop < _physical_crouch_threshold * 0.6:
			_physical_crouch_active = false
			_physical_crouch_resnap = 8
			_inject_action("crouch", true)   # toggle OFF
			_inject_action("crouch", false)  # clear held state
			print("[VR Mod] Physical crouch: end (drop=", drop, "m)")


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
	var _detected_by := ""
	var ui_node = get_tree().root.get_node_or_null("Map/Core/UI")
	if ui_node:
		for child in ui_node.get_children():
			# Skip always-visible HUD elements
			if child.name in ["HUD", "Effects", "NVG"]:
				continue
			if child is CanvasItem and child.visible:
				_interface_open = true
				_detected_by = "Map/Core/UI/" + child.name + " (" + child.get_class() + ")"
				break

	# Also check siblings of UI under Map/Core — ESC menu may live there
	if not _interface_open:
		var core_node = get_tree().root.get_node_or_null("Map/Core")
		if core_node:
			for child in core_node.get_children():
				if child.name in ["Camera", "UI", "LOS", "Interactor"]:
					continue
				if child is CanvasItem and child.visible:
					_interface_open = true
					_detected_by = "Map/Core/" + child.name + " (" + child.get_class() + ")"
					break

	if _interface_open and not _prev_interface_open:
		_log("Interface opened: detected by " + _detected_by)

	# ESC menu always pauses the tree; inventory/loot pools do not.
	# Clear the flag the moment the tree is no longer paused.
	if _esc_menu_active and not get_tree().paused:
		_esc_menu_active = false
		_esc_clear_hover()
	if _esc_menu_active:
		_interface_open = true

	# Detect transitions
	if _interface_open and not _prev_interface_open:
		_on_interface_opened()
	elif not _interface_open and _prev_interface_open:
		_on_interface_closed()
	_prev_interface_open = _interface_open


func _on_interface_opened() -> void:
	print("[VR Mod] Interface OPENED - switching to world-fixed mode")
	_ammo_check_timer = 0.0
	_cleanup_ammo_panel()
	_laser_diag_logged = false
	if not hud_mesh:
		return

	# Hide watch during menus
	if _watch_mesh:
		_watch_mesh.visible = false
		_watch_alpha = 0.0
		var wmat = _watch_mesh.material_override as ShaderMaterial
		if wmat:
			wmat.set_shader_parameter("alpha", 0.0)

	# Restore normal spread and full canvas for floating menu
	_hud_spread_active = _hud_spread
	_apply_hud_spread()
	if hud_viewport:
		hud_viewport.canvas_transform = Transform2D.IDENTITY
	if _watch_b_vp:
		_watch_b_vp.canvas_transform = Transform2D.IDENTITY

	# Detach hud_mesh from parked location and place in world space
	if hud_mesh.get_parent():
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
	hud_mesh.visible = true
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
	print("[VR Mod] Interface CLOSED - switching to wrist watch mode")
	if not hud_mesh:
		return

	# Restore spread=1.0 for watch (elements at known positions for crop)
	_hud_spread_active = 1.0
	_apply_hud_spread()
	if _watch_crop_computed and hud_viewport:
		# Re-derive and apply the crop (spread may have changed positions)
		_watch_crop_delay = 1
		_watch_crop_retries = 0

	# Park hud_mesh invisibly — watch takes over during gameplay
	if hud_mesh.get_parent():
		hud_mesh.get_parent().remove_child(hud_mesh)
	hud_mesh.visible = false
	add_child(hud_mesh)

	# Release Ctrl modifier if held (support grip fast transfer)
	if _menu_ctrl_held:
		_menu_ctrl_held = false
		_inject_key(KEY_CTRL, false)

	# Hide laser pointer and return to grab-range mode
	_menu_open = false
	if _laser_mesh and not _config_screen_open:
		_laser_mesh.visible = false

	# Watch will be revealed by glance logic next frame


func _show_ammo_check_panel() -> void:
	if not xr_camera:
		return

	# Read counts directly from game HUD labels — no canvas coord issues
	var hud_node = get_tree().root.get_node_or_null("Map/Core/UI/HUD")
	var mag_text := "?"
	var chb_text := "?"
	if hud_node:
		var mag_lbl = hud_node.get_node_or_null("Magazine/Panel/Count")
		var chb_lbl = hud_node.get_node_or_null("Chamber/Panel/Count")
		if mag_lbl:
			mag_text = mag_lbl.text
		if chb_lbl:
			chb_text = chb_lbl.text

	_cleanup_ammo_panel()

	# Build a small SubViewport with two labels
	_ammo_panel_vp = SubViewport.new()
	_ammo_panel_vp.size = Vector2i(256, 128)
	_ammo_panel_vp.transparent_bg = true
	_ammo_panel_vp.disable_3d = true
	_ammo_panel_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_ammo_panel_vp)

	var bg = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ammo_panel_vp.add_child(bg)

	var mag_label = Label.new()
	mag_label.text = "MAG  " + mag_text
	mag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mag_label.anchor_left = 0.0
	mag_label.anchor_top = 0.0
	mag_label.anchor_right = 1.0
	mag_label.anchor_bottom = 0.5
	mag_label.add_theme_font_size_override("font_size", 40)
	mag_label.add_theme_color_override("font_color", Color.WHITE)
	_ammo_panel_vp.add_child(mag_label)

	var chb_label = Label.new()
	chb_label.text = "CHB  " + chb_text
	chb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chb_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chb_label.anchor_left = 0.0
	chb_label.anchor_top = 0.5
	chb_label.anchor_right = 1.0
	chb_label.anchor_bottom = 1.0
	chb_label.add_theme_font_size_override("font_size", 40)
	chb_label.add_theme_color_override("font_color", Color.WHITE)
	_ammo_panel_vp.add_child(chb_label)

	# QuadMesh using the SubViewport texture
	var quad = QuadMesh.new()
	quad.size = Vector2(0.22, 0.11)
	_ammo_panel_mesh = MeshInstance3D.new()
	_ammo_panel_mesh.mesh = quad
	_ammo_panel_mesh.layers = 1

	var mat = StandardMaterial3D.new()
	mat.albedo_texture = _ammo_panel_vp.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ammo_panel_mesh.material_override = mat

	get_tree().root.add_child(_ammo_panel_mesh)
	_update_ammo_panel_position()
	_ammo_check_timer = 3.0
	print("[VR Mod] Ammo check: MAG=", mag_text, " CHB=", chb_text)


func _hide_ammo_check_panel() -> void:
	_cleanup_ammo_panel()


func _cleanup_ammo_panel() -> void:
	if _ammo_panel_mesh and is_instance_valid(_ammo_panel_mesh):
		_ammo_panel_mesh.queue_free()
		_ammo_panel_mesh = null
	if _ammo_panel_vp and is_instance_valid(_ammo_panel_vp):
		_ammo_panel_vp.queue_free()
		_ammo_panel_vp = null


func _update_ammo_panel_position() -> void:
	if not _ammo_panel_mesh or not is_instance_valid(_ammo_panel_mesh):
		return
	var weapon_ctrl = _get_controller(_weapon_hand if _weapon_hand != "" else _config_dominant_hand)
	if not weapon_ctrl or not weapon_ctrl.get_is_active():
		return
	# Float just above and slightly forward of the weapon hand, facing the player
	var hand_pos = weapon_ctrl.global_position
	var up = xr_camera.global_basis.y.normalized()
	var to_cam = (xr_camera.global_position - hand_pos).normalized()
	_ammo_panel_mesh.global_position = hand_pos + up * 0.12 + to_cam * 0.05
	_ammo_panel_mesh.look_at(xr_camera.global_position, Vector3.UP)
	_ammo_panel_mesh.rotate_y(deg_to_rad(180))


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

	# Fail-path diagnostic (fires once per interface open)
	if not _laser_diag_logged and hit_pos == Vector3.INF:
		var qn := hud_mesh.global_basis.z.normalized()
		var denom := qn.dot(ray_dir)
		var t_val := qn.dot(hud_mesh.global_position - ray_origin) / denom if abs(denom) > 0.0001 else INF
		_log("Laser MISS: origin=" + str(ray_origin) + " dir=" + str(ray_dir) + " quad_pos=" + str(hud_mesh.global_position) + " quad_norm=" + str(qn) + " denom=" + str(denom) + " t=" + str(t_val))
		_laser_diag_logged = true

	if hit_pos != Vector3.INF:
		# Convert 3D hit point to 2D viewport coordinates
		var local_pos = hud_mesh.global_transform.affine_inverse() * hit_pos
		var quad_size = (hud_mesh.mesh as QuadMesh).size

		# QuadMesh goes from -size/2 to +size/2
		var uv_x = (local_pos.x + quad_size.x / 2.0) / quad_size.x
		var uv_y = (-local_pos.y + quad_size.y / 2.0) / quad_size.y

		# Range check on raw UV (did the ray actually hit the quad?)
		if not _laser_diag_logged and (uv_x < 0 or uv_x > 1 or uv_y < 0 or uv_y > 1):
			_log("Laser UV MISS: uv=(" + str(uv_x) + "," + str(uv_y) + ") local=" + str(local_pos) + " quad_size=" + str(quad_size))
			_laser_diag_logged = true
		if uv_x >= 0 and uv_x <= 1 and uv_y >= 0 and uv_y <= 1:
			# push_input(false) treats position as screen coords and goes through
			# the Window's content_scale pipeline — same as real OS mouse events.
			# Use hud_viewport.size so UV maps to the full stereo viewport range,
			# which Godot's content_scale inverse maps to the correct canvas position.
			# Both warp_mouse and push_input(false) use hud_viewport coords (3840x1080).
			# This matches pre-4750b39 behaviour where warp_mouse(uv*hud_vp_size) worked
			# for both buttons and items.
			var vp_pos = Vector2(
				(uv_x + _menu_laser_uv_x) * hud_viewport.size.x,
				(uv_y + _menu_laser_uv_y) * hud_viewport.size.y
			)
			_laser_screen_pos = vp_pos

			if not _laser_diag_logged:
				_laser_diag_logged = true
				var main_vp: Viewport = get_viewport()
				_log("Laser diag: uv=" + str(Vector2(uv_x, uv_y)) + " vp_pos=" + str(vp_pos) + " hud_vp_size=" + str(hud_viewport.size) + " visible_rect=" + str(main_vp.get_visible_rect().size) + " win=" + str(DisplayServer.window_get_size()))

			# warp_mouse always — keeps cursor at laser position for hover and drag.
			get_viewport().warp_mouse(vp_pos)

			# Laser tip flush with quad surface. no_depth_test=true prevents clipping.
			var dist = ray_origin.distance_to(hit_pos) - 0.01
			if dist > 0.1:
				(_laser_mesh.mesh as CylinderMesh).height = dist
				_laser_mesh.position.z = -dist / 2.0
				_laser_mesh.visible = true
			else:
				_laser_mesh.visible = false  # Too close, hide entirely
			# ESC menu hover: update each frame while laser hits the quad
			if _esc_menu_active:
				_update_esc_hover()
		else:
			_laser_screen_pos = Vector2(-1, -1)
			if _esc_menu_active:
				_esc_clear_hover()


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
	# xr_origin stays parented to self (autoload). Just snap position to new camera.
	var actual_head_height := xr_camera.position.y if xr_camera else 1.6
	if actual_head_height < 0.3:
		actual_head_height = 1.6
	var cam_pos = game_camera.global_position
	xr_origin.global_position = Vector3(cam_pos.x, cam_pos.y - actual_head_height, cam_pos.z)
	_last_game_cam_pos = cam_pos
	xr_camera.cull_mask = game_camera.cull_mask
	print("[VR Mod] Rig snapped to new camera at ", cam_pos)


func _on_level_transition() -> void:
	# Reset state that depends on game scene nodes (freed during level change).
	_level_transition_count += 1
	print("[VR Mod] Level transition #", _level_transition_count, " — resetting scene-dependent state")
	# Save weapon slot/hand so we can re-take control after the new scene loads.
	if _holster_state != HolsterState.UNARMED and _weapon_slot > 0:
		_transition_slot = _weapon_slot
		_transition_hand = _weapon_hand if _weapon_hand != "" else _config_dominant_hand
		print("[VR Mod] Saving pre-transition state: slot=", _transition_slot, " hand=", _transition_hand)
	else:
		_transition_slot = 0
		_transition_hand = ""
	_weapons_reparented = false
	_weapon_loaded = false
	_weapon_is_long = false
	_weapon_subtype = ""
	_weapon_uses_r_reload = false
	_action_open = false
	_pump_gesture_active = false
	_pump_prev_pos = Vector3.ZERO
	_pump_cooldown = 0.0
	_recoil_rest_xform = Transform3D.IDENTITY
	_prev_recoil_mag = 0.0
	_fire_haptic_cooldown = 0.0
	_walk_sway_captured = false
	_walk_sway_logged = false
	_rest_capture_pending = false
	_walk_sway_capture_delay = 0.0
	_clear_grenade_state()
	_esc_clear_hover()
	_esc_menu_active = false
	_holster_state = HolsterState.UNARMED
	_weapon_slot = 0
	_teardown_watch_content()
	_setup_watch_content()
	_cleanup_scope()
	if _grabbed_object and not is_instance_valid(_grabbed_object):
		_grabbed_object = null
		_grab_hand = ""
	_nvg_active = false
	if _nvg_overlay_mesh:
		_nvg_overlay_mesh.visible = false
	_release_physical_crouch()

	# Re-assert XR camera ownership — the new level's camera sets current=true,
	# which makes Godot apply its Environment/CameraAttributes (glow, DOF, etc.)
	# to the render pipeline, causing blurry menus.
	if xr_camera:
		xr_camera.current = true
	get_viewport().use_xr = true
	if game_camera:
		game_camera.current = false
	print("[VR Mod] XR camera re-asserted as current")

	_log("Level transition reset complete, camera at " + str(game_camera.global_position))


func _sync_origin_to_game() -> void:
	if game_camera and is_instance_valid(game_camera) and xr_origin:
		var current_pos = game_camera.global_position
		var delta_pos = current_pos - _last_game_cam_pos
		if delta_pos.length() > 0.001:
			# Freeze Y while physically crouched: the game camera drops due to the
			# crouch animation, but the VR height is already handled by physical tracking.
			if _physical_crouch_active or _physical_crouch_resnap > 0:
				delta_pos.y = 0.0
			xr_origin.global_position += delta_pos
			_last_game_cam_pos = current_pos

		# Steer game camera toward controller aim via mouse injection
		if not _interface_open:
			if _decor_mode:
				_steer_decor_camera_to_controller()
			else:
				_steer_game_camera_via_mouse()


func _steer_decor_camera_to_controller() -> void:
	# In decor mode, steer game camera to match dominant hand controller aim.
	# The game uses game camera direction for furniture placement, so this makes
	# the furniture ghost follow where the player points the controller.
	var ctrl = _get_controller(_config_dominant_hand)
	if not ctrl or not ctrl.get_is_active():
		return
	if not game_camera or not is_instance_valid(game_camera):
		return

	var aim_forward = -ctrl.global_basis.z
	var target_yaw = atan2(-aim_forward.x, -aim_forward.z)
	var target_pitch = asin(clampf(aim_forward.y, -1.0, 1.0))

	var game_yaw = game_camera.global_rotation.y
	var game_pitch = game_camera.global_rotation.x

	var yaw_error = fmod(target_yaw - game_yaw + PI, TAU) - PI
	var pitch_error = target_pitch - game_pitch

	if abs(yaw_error) < deg_to_rad(0.3) and abs(pitch_error) < deg_to_rad(0.3):
		return

	var mouse_sensitivity_estimate := 0.003
	var correction_strength := 0.8

	var mouse_dx = -(yaw_error * correction_strength) / mouse_sensitivity_estimate
	var mouse_dy = -(pitch_error * correction_strength) / mouse_sensitivity_estimate

	var event = InputEventMouseMotion.new()
	event.relative = Vector2(mouse_dx, mouse_dy)
	event.position = get_viewport().get_visible_rect().size / 2
	Input.parse_input_event(event)


func _steer_game_camera_via_mouse() -> void:
	# Steer game camera to match weapon barrel aim direction.
	# In LOWERED/SLING the weapon is not raised; use dominant hand so the
	# game's Interactor raycast follows the same hand as the laser pointer.
	var aim_hand: String
	if _holster_state == HolsterState.LOWERED or _holster_state == HolsterState.SLING:
		aim_hand = _config_dominant_hand
	else:
		aim_hand = _get_weapon_hand()
	var aim_controller = _get_controller(aim_hand)
	if not aim_controller or not aim_controller.get_is_active():
		return

	# Compute barrel direction: must match the aim_basis used in _sync_weapon_to_controller
	var aim_forward: Vector3

	if _support_grip_held:
		var off_controller = _get_controller(_get_support_hand())
		if off_controller and off_controller.get_is_active():
			var hand_dist = aim_controller.global_position.distance_to(off_controller.global_position)
			if hand_dist > 0.1:
				aim_forward = (off_controller.global_position - aim_controller.global_position).normalized()
			else:
				aim_forward = -aim_controller.global_basis.z
		else:
			aim_forward = -aim_controller.global_basis.z
	else:
		# Use raw controller forward for steering — slot grip rotations are visual offsets only
		aim_forward = -aim_controller.global_basis.z
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
	var correction_strength := 0.8

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
		# Right thumbstick Y = scroll in all menus/inventories
		if right_controller and right_controller.get_is_active():
			var stick = right_controller.get_vector2("primary")
			if abs(stick.y) > 0.5 and _scroll_cooldown <= 0:
				_inject_scroll(1 if stick.y > 0 else -1)
				_scroll_cooldown = 0.15
		return

	# --- Grip adjust mode: thumbsticks control offsets ---
	if _adjust_mode and _weapon_slot > 0:
		var changed := false
		var offset: Vector3 = _get_weapon_grip_offset()
		var rot: float = _get_weapon_grip_rotation()
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
			_set_weapon_grip_offset(offset)
			_set_weapon_grip_rotation(rot)
			print("[VR Mod] ADJUST ", _current_weapon_name, ": x=", snapped(offset.x, 0.001), " y=", snapped(offset.y, 0.001), " z=", snapped(offset.z, 0.001), " rot=", snapped(rot, 0.1), "°")
		# Release movement keys and skip normal input
		_inject_key(KEY_W, false)
		_inject_key(KEY_S, false)
		_inject_key(KEY_A, false)
		_inject_key(KEY_D, false)
		return

	# --- Foregrip adjust mode: gun is frozen, support hand follows controller freely ---
	# Movement is suppressed; player physically positions their hand on the gun, then presses A.
	if _fg_adjust_mode:
		_inject_key(KEY_W, false)
		_inject_key(KEY_S, false)
		_inject_key(KEY_A, false)
		_inject_key(KEY_D, false)
		return

	# --- Decor mode: right stick Y = scroll (distance/rotation), left stick = move, right stick X = turn ---
	if _decor_mode:
		# Tick decor scroll cooldown
		if _decor_scroll_cooldown > 0:
			_decor_scroll_cooldown -= delta

		# Right thumbstick Y = scroll for distance or rotation
		if right_controller and right_controller.get_is_active():
			var stick = right_controller.get_vector2("primary")
			if abs(stick.y) > 0.5 and _decor_scroll_cooldown <= 0:
				_inject_scroll(1 if stick.y > 0 else -1)
				_decor_scroll_cooldown = 0.15

		# Left thumbstick = movement (still works in decor mode)
		if left_controller and left_controller.get_is_active():
			var move = left_controller.get_vector2("primary")
			if move.length() > thumbstick_deadzone:
				var strength = (move.length() - thumbstick_deadzone) / (1.0 - thumbstick_deadzone)
				move = move.normalized() * strength
				if game_camera and is_instance_valid(game_camera) and xr_camera:
					var yaw_diff = xr_camera.global_rotation.y - game_camera.global_rotation.y
					move = move.rotated(yaw_diff)
				_inject_key(KEY_W, move.y > 0.3)
				_inject_key(KEY_S, move.y < -0.3)
				_inject_key(KEY_A, move.x < -0.3)
				_inject_key(KEY_D, move.x > 0.3)
			else:
				_inject_key(KEY_W, false)
				_inject_key(KEY_S, false)
				_inject_key(KEY_A, false)
				_inject_key(KEY_D, false)

		# Right thumbstick X = snap/smooth turn (fall through to turn section)
		if right_controller and right_controller.get_is_active():
			var turn_input = right_controller.get_vector2("primary")
			if abs(turn_input.x) > thumbstick_deadzone:
				if use_snap_turn:
					if not _snap_turn_cooldown and abs(turn_input.x) > 0.6:
						var angle = -snap_turn_degrees if turn_input.x > 0 else snap_turn_degrees
						xr_origin.rotate_y(deg_to_rad(angle))
						_snap_turn_cooldown = true
						_vignette_hold = maxf(_vignette_hold, 0.3)
				else:
					xr_origin.rotate_y(deg_to_rad(-turn_input.x * smooth_turn_speed * delta))
					_vignette_hold = maxf(_vignette_hold, 0.15)
			else:
				_snap_turn_cooldown = false
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
		if _rail_mode and abs(turn_input.y) > 0.5:
			# Rail mode: right stick Y = Ctrl+scroll to slide optic along rail
			if _rail_scroll_cooldown <= 0.0:
				_inject_key(KEY_CTRL, true)
				_inject_scroll(1 if turn_input.y > 0 else -1)
				_inject_key(KEY_CTRL, false)
				_rail_scroll_cooldown = 0.15
				var ctrl = _get_controller(_config_dominant_hand)
				if ctrl:
					ctrl.trigger_haptic_pulse("haptic", 0.0, 0.15, 0.05, 0.0)
		elif _config_screen_open:
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
						_vignette_hold = maxf(_vignette_hold, 0.3)
				else:
					xr_origin.rotate_y(deg_to_rad(-turn_input.x * smooth_turn_speed * delta))
					_vignette_hold = maxf(_vignette_hold, 0.15)
			else:
				_snap_turn_cooldown = false


func _on_button_pressed(button_name: String, hand: String) -> void:
	# Resolve hand roles dynamically based on holster state.
	# UNARMED and SLING both use config dominant hand — in sling the weapon is
	# hanging, not wielded, so _weapon_hand (which hand last grabbed it) should
	# not flip the support/weapon roles and break menu fast transfer.
	var _use_dominant := _holster_state == HolsterState.UNARMED or _holster_state == HolsterState.SLING
	var is_weapon_hand := (hand == _config_dominant_hand) if _use_dominant else (hand == _weapon_hand)
	var is_support_hand := not is_weapon_hand

	# Grip tracking must happen before any early return (needed for both-grips detection)
	if button_name == "grip_click":
		if hand == "left":
			_left_grip_held = true
		else:
			_right_grip_held = true

	# Decor mode remaps (before normal input handling)
	if _decor_mode and not _interface_open:
		match button_name:
			"trigger_click":
				if is_weapon_hand:
					_inject_key(KEY_G, true)  # Place furniture
					print("[VR Mod] DECOR: Place (G pressed)")
			"ax_button":
				if hand == "right":
					# A button = surface magnet toggle (left click)
					_inject_mouse_button(MOUSE_BUTTON_LEFT, true)
					_inject_mouse_button(MOUSE_BUTTON_LEFT, false)
					print("[VR Mod] DECOR: Surface magnet toggled")
				elif hand == "left" and not _is_decor_placing():
					# X button = exit decor mode (blocked while placing)
					_toggle_decor_mode()
			"by_button":
				if hand == "left":
					# Y button = furniture inventory (Tab)
					_inject_key(KEY_TAB, true)
					_inject_key(KEY_TAB, false)
					print("[VR Mod] DECOR: Furniture inventory (Tab)")
				elif hand == "right":
					# B button = store item to furniture inventory (middle mouse)
					_inject_mouse_button(MOUSE_BUTTON_MIDDLE, true)
					_inject_mouse_button(MOUSE_BUTTON_MIDDLE, false)
					print("[VR Mod] DECOR: Store to furniture inv (middle click)")
			"grip_click":
				# Both grips = exit decor mode (blocked while placing)
				if _left_grip_held and _right_grip_held and not _is_decor_placing():
					_toggle_decor_mode()
				# Single right grip = toggle distance/rotation mode via Placer.rotateMode
				elif hand == "right":
					_decor_scroll_mode = 1 - _decor_scroll_mode
					var placer = game_camera.get_node_or_null("Placer") if game_camera else null
					if placer:
						placer.set("rotateMode", _decor_scroll_mode == 1)
					var mode_name = "ROTATION" if _decor_scroll_mode == 1 else "DISTANCE"
					_log("[VR Mod] DECOR: Scroll mode -> " + mode_name)
					right_controller.trigger_haptic_pulse("haptic", 0.0, 0.2, 0.1, 0.0)
			"menu_button":
				_toggle_esc_menu()
		return  # Don't fall through to normal input handling

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
				elif is_weapon_hand and _holster_state == HolsterState.DRAWN and not (_weapon_uses_r_reload and _action_open):
					if _weapon_slot == 4:
						if not _grenade_pin_pulled:
							# Grenade: tap fire = pull pin (game click 1)
							_inject_mouse_button(MOUSE_BUTTON_LEFT, true)
							_inject_action("fire", true)
							_inject_action("left_mouse", true)
							Input.action_press("fire", 1.0)
							Input.action_press("left_mouse", 1.0)
							get_tree().create_timer(0.08).timeout.connect(_grenade_tap_release)
							_grenade_pin_pulled = true
							var ctrl = _get_controller(hand)
							if ctrl:
								ctrl.trigger_haptic_pulse("haptic", 0.0, 0.4, 0.1, 0.0)
							print("[VR Mod] Grenade pin pulled")
						else:
							# Second trigger: right click = replace pin (cancel)
							_grenade_replace_pin()
							print("[VR Mod] Grenade pin replaced")
					else:
						# Non-grenade weapons: existing fire logic
						Input.action_press("fire", 1.0)
						Input.action_press("left_mouse", 1.0)
						_inject_action("fire", true)
						_inject_action("left_mouse", true)
						_inject_mouse_button(MOUSE_BUTTON_LEFT, true)
				elif is_weapon_hand and _holster_state == HolsterState.LOWERED and _weapon_subtype == "Bolt":
					# Bolt-action: trigger while weapon lowered cycles the bolt (R)
					_inject_action("reload", true)
					_inject_action("reload", false)
					print("[VR Mod] BOLT CYCLED (dominant trigger, LOWERED)")
					var bolt_ctrl = _get_controller(_weapon_hand)
					if bolt_ctrl:
						bolt_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.1, 0.0)
					_raise_weapon()
				elif is_support_hand and _holster_state in [HolsterState.DRAWN, HolsterState.LOWERED]:
					# Support hand trigger = rail slide / reload / laser (drawn or lowered)
					if _rail_mode and _holster_state == HolsterState.DRAWN:
						_start_rail_slide()
					elif _support_grip_held and not _weapon_uses_r_reload:
						_inject_key(KEY_T, true)
						_inject_key(KEY_T, false)
						print("[VR Mod] LASER toggled (support trigger + grip)")
					else:
						if _weapon_uses_r_reload and _action_open:
							# Action open: support trigger loads one round/shell (LMB)
							_inject_mouse_button(MOUSE_BUTTON_LEFT, true)
							_inject_mouse_button(MOUSE_BUTTON_LEFT, false)
							print("[VR Mod] LOAD AMMO (support trigger, action open)")
						else:
							# Start long-press timer — short = reload, long = ammo check (KEY_V)
							_support_trigger_pending = true
							_support_trigger_press_time = Time.get_ticks_msec() / 1000.0
		"grip_click":
			if _interface_open:
				if is_weapon_hand:
					_try_grab(hand)
				if not _grabbed_object:
					if is_support_hand:
						_menu_ctrl_held = true
						_inject_key(KEY_CTRL, true)
						print("[VR Mod] MENU: Ctrl held (fast transfer mode)")
					else:
						_inject_mouse_button(MOUSE_BUTTON_RIGHT, true)
						_inject_action("context", true)
			elif _decor_mode:
				return
			elif _holster_cooldown > 0.0:
				print("[VR Mod] Grip blocked - holster cooldown (" + str(snappedf(_holster_cooldown, 0.01)) + "s remaining)")
			else:
				var ctrl = _get_controller(hand)
				var zone = _get_nearby_holster_zone(ctrl.global_position) if ctrl else 0
				match _holster_state:
					HolsterState.UNARMED:
						if is_weapon_hand:
							_try_grab(hand)
						if not _grabbed_object:
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
								# Support hand grip = two-hand aim (long weapons only)
								if _weapon_is_long:
									_support_grip_held = true
									_pump_gesture_active = false
									_pump_prev_pos = Vector3.ZERO
									print("[VR Mod] Support grip: two-hand aim ON")
								else:
									print("[VR Mod] Support grip ignored — short weapon, no two-hand aim")
					HolsterState.LOWERED:
						if is_weapon_hand:
							_try_grab(hand)
						if not _grabbed_object:
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
								if _weapon_is_long:
									_support_grip_held = true
					HolsterState.SLING:
						if is_weapon_hand:
							_try_grab(hand)
						if not _grabbed_object:
							if zone == _weapon_slot:
								# Near own holster zone — holster completely
								_holster_weapon()
							else:
								# Grab sling weapon; zone proximity to other holsters is ignored
								# (chest-level sling overlaps zone 4, so any zone check would misfire)
								_weapon_hand = hand
								_raise_weapon()
		"ax_button":  # A on right, X on left (physical mapping)
			if hand == "left":
				# X button: rail mode (long-press) / adjust mode (short press) / flashlight
				if _rail_mode:
					# X again while in rail mode = exit rail mode
					_exit_rail_mode()
				elif _fg_adjust_mode:
					# X while in foregrip adjust = discard and exit
					if _has_weapon_fg_p():
						_set_weapon_fg_p(_fg_adjust_saved_p)
						_set_weapon_fg_r(_fg_adjust_saved_r)
					_fg_grip_captured = false
					_fg_adjust_mode = false
					print("[VR Mod] === FG ADJUST MODE OFF (discarded) ===")
				elif _adjust_mode:
					# X again = discard changes and exit
					_set_weapon_grip_offset(_adjust_saved_offset)
					_set_weapon_grip_rotation(_adjust_saved_rotation)
					_adjust_mode = false
					print("[VR Mod] === ADJUST MODE OFF (discarded) ===")
				elif _holster_state == HolsterState.DRAWN:
					# Start long-press detection — will resolve on release or timeout
					_rail_x_pending = true
					_rail_x_press_time = Time.get_ticks_msec() / 1000.0
				elif _interface_open:
					# X = rotate dragged item (R key); flashlight/decor disabled while menu is open
					_inject_key(KEY_R, true)
					_inject_key(KEY_R, false)
					print("[VR Mod] INVENTORY: Rotate item (R)")
				else:
					# X button when unarmed/lowered: long-press (0.5s) = decor mode, short-press = flashlight
					_decor_x_pending = true
					_decor_x_press_time = Time.get_ticks_msec() / 1000.0
			else:
				if _fg_adjust_mode:
					var sup_ctrl_sv := _get_controller(_get_support_hand())
					var is_rw := _get_weapon_hand() == "right"
					var s_off := HAND_GLTF_OFFSET_LEFT if is_rw else HAND_GLTF_OFFSET_RIGHT
					var s_rot := HAND_GLTF_ROTATION_LEFT if is_rw else HAND_GLTF_ROTATION_RIGHT
					if sup_ctrl_sv and sup_ctrl_sv.get_is_active() and _cached_weapon_rig and is_instance_valid(_cached_weapon_rig):
						var wr := _cached_weapon_rig
						var hp := sup_ctrl_sv.global_position + sup_ctrl_sv.global_basis * s_off
						var hb := sup_ctrl_sv.global_basis * Basis.from_euler(s_rot * (PI / 180.0))
						var fg_p := wr.global_transform.affine_inverse() * hp
						var fg_r := wr.global_basis.inverse() * hb
						_set_weapon_fg_p(fg_p)
						_set_weapon_fg_r(fg_r)
						print("[VR Mod] FG ADJUST saved ", _current_weapon_name, ": p=", snapped(fg_p.x, 0.001), ",", snapped(fg_p.y, 0.001), ",", snapped(fg_p.z, 0.001))
					_fg_grip_captured = false
					_fg_adjust_mode = false
					_save_grip_config()
					print("[VR Mod] === FG ADJUST MODE OFF (saved) ===")
				elif _adjust_mode:
					_save_grip_config()
					_adjust_mode = false
					print("[VR Mod] === ADJUST MODE OFF (saved) ===")
				elif _interface_open and _laser_screen_pos.x >= 0:
					# A = instant button click while menu/inventory is open.
					# Atomic press+release in the same frame — cursor can't drift between them.
					var ev_dn := InputEventMouseButton.new()
					ev_dn.button_index = MOUSE_BUTTON_LEFT
					ev_dn.pressed = true
					ev_dn.position = _laser_screen_pos
					ev_dn.global_position = _laser_screen_pos
					ev_dn.button_mask = MOUSE_BUTTON_MASK_LEFT
					get_viewport().push_input(ev_dn, true)
					var ev_up := InputEventMouseButton.new()
					ev_up.button_index = MOUSE_BUTTON_LEFT
					ev_up.pressed = false
					ev_up.position = _laser_screen_pos
					ev_up.global_position = _laser_screen_pos
					ev_up.button_mask = 0
					get_viewport().push_input(ev_up, true)
				else:
					_inject_action("jump", true)
		"by_button":  # B on right, Y on left (physical mapping)
			if hand == "left":
				_inject_action("interface", true)  # Y = toggle inventory
			else:
				if _holster_state == HolsterState.DRAWN:
					if _weapon_uses_r_reload:
						_action_open = !_action_open
						_inject_key(KEY_CTRL, true)
						_inject_key(KEY_CTRL, false)
						if not _action_open:
							# Reset pump baseline so gesture doesn't misfire from stale position
							_pump_prev_pos = Vector3.ZERO
							_pump_gesture_active = false
						print("[VR Mod] ACTION ", "OPENED" if _action_open else "CLOSED", " (B, Ctrl)")
					else:
						_inject_key(KEY_F, true)
						_inject_key(KEY_F, false)
						print("[VR Mod] FIRE MODE toggled (B button)")
				else:
					_inject_action("interact", true)
		"menu_button":
			_toggle_esc_menu()
		"primary_click":
			if hand == "left":
				_inject_action("sprint", true)
			elif not _physical_crouch_active:
				_inject_action("crouch", true)


func _on_button_released(button_name: String, hand: String) -> void:
	var _use_dominant := _holster_state == HolsterState.UNARMED or _holster_state == HolsterState.SLING
	var is_weapon_hand := (hand == _config_dominant_hand) if _use_dominant else (hand == _weapon_hand)
	var is_support_hand := not is_weapon_hand

	# Grip release tracking must happen before any early return
	if button_name == "grip_click":
		if hand == "left":
			_left_grip_held = false
		else:
			_right_grip_held = false

	# Decor mode release handling
	if _decor_mode and not _interface_open:
		match button_name:
			"trigger_click":
				if is_weapon_hand:
					_inject_key(KEY_G, false)  # Release place key
			"menu_button":
				pass  # ESC release handled by _toggle_esc_menu
		return  # Don't fall through to normal release handling

	match button_name:
		"trigger_click":
			if _config_screen_open:
				_inject_config_click(false)
			elif _interface_open:
				_inject_mouse_button(MOUSE_BUTTON_LEFT, false)
				_inject_action("left_mouse", false)
			else:
				if is_weapon_hand and _weapon_slot != 4:
					Input.action_release("fire")
					Input.action_release("left_mouse")
					_inject_action("fire", false)
					_inject_action("left_mouse", false)
					_inject_mouse_button(MOUSE_BUTTON_LEFT, false)
				else:
					if _rail_active:
						_end_rail_slide()
					elif _support_trigger_pending:
						# Short press: do reload tap now
						_support_trigger_pending = false
						_inject_action("reload", true)
						_inject_action("reload", false)
						print("[VR Mod] RELOAD (support trigger short-press)")
					else:
						_inject_action("reload", false)
		"grip_click":
			# Grip release tracking already done above (before decor mode block)
			if _decor_mode and not _interface_open:
				return  # Don't process holster/drop while in decor mode
			if _interface_open:
				if is_support_hand:
					_menu_ctrl_held = false
					_inject_key(KEY_CTRL, false)
					print("[VR Mod] MENU: Ctrl released")
				else:
					_inject_mouse_button(MOUSE_BUTTON_RIGHT, false)
					_inject_action("context", false)
			elif _decor_mode:
				return
			else:
				if hand == _weapon_hand and _holster_state == HolsterState.DRAWN:
					if _weapon_slot == 4 and _grenade_pin_pulled:
						# Pin pulled: tap fire = throw (game click 2)
						_grenade_throw_tap()
						print("[VR Mod] Grenade thrown (grip release)")
					elif not _weapon_loaded:
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
							# Not near holster — slot 1 (primary) enters sling; all others auto-holster
							if _weapon_slot == 1:
								_enter_sling()
							else:
								_holster_weapon()
				elif is_support_hand:
					_support_grip_held = false
					_pump_gesture_active = false
					_pump_prev_pos = Vector3.ZERO
					_pump_fwd_dir = Vector3.ZERO
					if _fg_adjust_mode:
						_fg_adjust_mode = false
						print("[VR Mod] === FG ADJUST MODE OFF (support released) ===")
					print("[VR Mod] Support grip: two-hand aim OFF")
				# Always try to drop grabbed objects from this hand
				if _grab_hand == hand:
					_drop_grabbed()
		"ax_button":
			if hand == "left":
				if _rail_x_pending:
					_rail_x_pending = false
					if _holster_state == HolsterState.DRAWN and not _rail_mode:
						if _gun_config_enabled:
							if _support_grip_held:
								# Off-hand gripping — enter foregrip adjust mode:
								# gun freezes, support hand follows controller; press A to save, X to discard
								_fg_adjust_mode = true
								_fg_adjust_saved_p = _get_weapon_fg_p()
								_fg_adjust_saved_r = _get_weapon_fg_r()
								_fg_grip_captured = false
								if _cached_weapon_rig and is_instance_valid(_cached_weapon_rig):
									_fg_adjust_frozen_xform = _cached_weapon_rig.global_transform
								print("[VR Mod] === FG ADJUST MODE ON (slot ", _weapon_slot, ") ===")
								print("[VR Mod] Gun frozen. Move support hand to foregrip, then A=Save, X=Discard")
							else:
								# Main hand only — enter grip adjust mode
								_adjust_mode = true
								_adjust_saved_offset = _get_weapon_grip_offset()
								_adjust_saved_rotation = _get_weapon_grip_rotation()
								print("[VR Mod] === ADJUST MODE ON (slot ", _weapon_slot, ") ===")
								print("[VR Mod] Left stick=X/Y, Right stick X=Z Y=Rotation")
								print("[VR Mod] A=Save, X=Discard")
				elif _decor_x_pending:
					_decor_x_pending = false
					# Short press — toggle flashlight
					_inject_mouse_button(MOUSE_BUTTON_XBUTTON2, true)
					_inject_mouse_button(MOUSE_BUTTON_XBUTTON2, false)
					print("[VR Mod] FLASHLIGHT toggled (X short-press)")
			elif hand == "right":
				_inject_action("jump", false)
		"by_button":
			if hand == "left":
				_inject_action("interface", false)
			else:
				if _holster_state != HolsterState.DRAWN:
					_inject_action("interact", false)
		"menu_button":
			pass  # ESC release handled by _toggle_esc_menu
		"primary_click":
			if hand == "left":
				_inject_action("sprint", false)
			elif not _physical_crouch_active:
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
	get_viewport().push_input(event, false)


func _inject_mouse_button(button: int, pressed: bool) -> void:
	var current = _mouse_states.get(button, false)
	if current == pressed:
		return
	_mouse_states[button] = pressed
	var event = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.ctrl_pressed = _menu_ctrl_held
	if _interface_open and _laser_screen_pos.x >= 0:
		event.position = get_viewport().get_mouse_position()
	else:
		event.position = get_viewport().get_visible_rect().size / 2.0
	event.global_position = event.position
	var mask := 0
	for btn in _mouse_states:
		if _mouse_states[btn]:
			match btn:
				MOUSE_BUTTON_LEFT: mask |= MOUSE_BUTTON_MASK_LEFT
				MOUSE_BUTTON_RIGHT: mask |= MOUSE_BUTTON_MASK_RIGHT
				MOUSE_BUTTON_MIDDLE: mask |= MOUSE_BUTTON_MASK_MIDDLE
	event.button_mask = mask
	Input.parse_input_event(event)
	get_viewport().push_input(event, true)


func _inject_scroll(direction: int) -> void:
	# direction: 1 = scroll up, -1 = scroll down
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP if direction > 0 else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	if _interface_open and _laser_screen_pos.x >= 0:
		event.position = get_viewport().get_mouse_position()
	else:
		event.position = get_viewport().get_visible_rect().size / 2.0
	Input.parse_input_event(event)
	get_viewport().push_input(event, true)
	# Scroll events need immediate release
	var release = InputEventMouseButton.new()
	release.button_index = event.button_index
	release.pressed = false
	release.position = event.position
	Input.parse_input_event(release)
	get_viewport().push_input(release, true)


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
		var dump_path = _log_path
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


func _extract_hand_assets_from_vmz() -> bool:
	# Metro Mod Loader caches the VMZ as a zip at user://vmz_mount_cache/vr-mod.zip.
	# Godot's res:// VFS does not expose the VMZ contents, so we extract the hand
	# assets to user://vr_mod/hands/ where FileAccess and GLTFDocument can read them.
	var zip_path := "user://vmz_mount_cache/vr-mod.zip"

	var reader := ZIPReader.new()
	var open_err := reader.open(zip_path)
	if open_err != OK:
		_hand_load_errors.append("hand: ZIPReader.open failed for " + zip_path + " err=" + str(open_err))
		return false

	# Ensure destination directory exists.
	var da := DirAccess.open("user://")
	if da:
		da.make_dir_recursive("vr_mod/hands")

	# Assets to extract (stored in VMZ with backslash paths on Windows).
	var want := [
		"resources/hands/Hand_Nails_low_L.gltf",
		"resources/hands/Hand_Nails_low_R.gltf",
		"resources/hands/hand_col.png",
	]
	var all_entries := reader.get_files()

	for asset in want:
		var filename := (asset as String).get_file()
		# Match zip entry regardless of slash style.
		var entry := ""
		for f in all_entries:
			if (f as String).replace("\\", "/") == asset:
				entry = f
				break
		if entry.is_empty():
			_hand_load_errors.append("hand: entry not found in VMZ: " + asset)
			reader.close()
			return false
		var bytes := reader.read_file(entry)
		if bytes.is_empty():
			_hand_load_errors.append("hand: read_file empty for " + entry)
			reader.close()
			return false
		var dest_path := "user://vr_mod/hands/" + filename
		var wf := FileAccess.open(dest_path, FileAccess.WRITE)
		if not wf:
			_hand_load_errors.append("hand: cannot write " + dest_path + " err=" + str(FileAccess.get_open_error()))
			reader.close()
			return false
		wf.store_buffer(bytes)
		wf.close()

	reader.close()
	_hand_load_errors.append("hand: extracted assets to user://vr_mod/hands/")
	return true


func _create_hand_model(controller: XRController3D, model_name: String) -> void:
	var is_left := "Left" in model_name
	var gltf_name := "Hand_Nails_low_L.gltf" if is_left else "Hand_Nails_low_R.gltf"
	var gltf_path := _assets_base + gltf_name

	# Runtime GLTF import — append_from_file resolves relative texture references
	# (hand_col.png) automatically from the same directory. Assets are pre-extracted
	# from the VMZ cache to user://vr_mod/hands/ by _extract_hand_assets_from_vmz().
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var err := gltf_doc.append_from_file(gltf_path, gltf_state)
	if err != OK:
		_hand_load_errors.append("hand: append_from_file failed err=" + str(err) + " path=" + gltf_path)
		_create_fallback_box_hand(controller, model_name)
		return
	var scene: Node = gltf_doc.generate_scene(gltf_state)
	if not scene:
		_hand_load_errors.append("hand: generate_scene returned null for " + gltf_path)
		_create_fallback_box_hand(controller, model_name)
		return

	# CRITICAL (Forward Mobile): never add MeshInstance3D directly to XRController3D.
	# The wrapper Node3D is the direct child; the gltf scene (which contains meshes) goes
	# under the wrapper.
	var wrapper := Node3D.new()
	wrapper.name = model_name
	wrapper.position = HAND_GLTF_OFFSET_LEFT if is_left else HAND_GLTF_OFFSET_RIGHT
	wrapper.rotation_degrees = HAND_GLTF_ROTATION_LEFT if is_left else HAND_GLTF_ROTATION_RIGHT
	wrapper.add_child(scene)
	controller.add_child(wrapper)
	_apply_hand_texture(scene)

	# Cache skeleton and finger bone indices for runtime curl animation
	var skel: Skeleton3D = _find_node_by_class(scene, "Skeleton3D")
	if not skel:
		_hand_load_errors.append("hand: Skeleton3D not found inside " + gltf_name)
		return

	var suffix := "_L" if is_left else "_R"
	# Joint order is always proximal → intermediate → distal (base to tip).
	# Thumb has no Intermediate joint in anatomical rigs — only Proximal + Distal.
	var finger_map := {
		"thumb":  ["Thumb_Proximal",  "Thumb_Distal"],
		"index":  ["Index_Proximal",  "Index_Intermediate",  "Index_Distal"],
		"middle": ["Middle_Proximal", "Middle_Intermediate", "Middle_Distal"],
		"ring":   ["Ring_Proximal",   "Ring_Intermediate",   "Ring_Distal"],
		"little": ["Little_Proximal", "Little_Intermediate", "Little_Distal"],
	}
	var fingers := {}
	var rest := {}
	for finger_name in finger_map.keys():
		var indices: Array[int] = []
		for bone_base in finger_map[finger_name]:
			var bi := skel.find_bone(bone_base + suffix)
			if bi >= 0:
				indices.append(bi)
				rest[bi] = skel.get_bone_rest(bi).basis.get_rotation_quaternion()
			else:
				_hand_load_errors.append("hand: bone not found: " + bone_base + suffix)
		fingers[finger_name] = indices

	if is_left:
		_hand_wrapper_left = wrapper
		_hand_skel_left = skel
		_hand_fingers_left = fingers
		_hand_bone_rest_left = rest
	else:
		_hand_wrapper_right = wrapper
		_hand_skel_right = skel
		_hand_fingers_right = fingers
		_hand_bone_rest_right = rest

	_log("hand: loaded " + gltf_name + " bones=" + str(skel.get_bone_count()) + " fingers=" + str(fingers.keys()))


func _create_fallback_box_hand(controller: XRController3D, model_name: String) -> void:
	# Same simple 3-box hand we used before the skeletal upgrade. Only used if the
	# .gltf asset is missing or fails to load at runtime.
	var hand := Node3D.new()
	hand.name = model_name

	var palm_mesh := MeshInstance3D.new()
	palm_mesh.name = "Palm"
	var palm := BoxMesh.new()
	palm.size = Vector3(0.08, 0.03, 0.10)
	palm_mesh.mesh = palm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.55, 0.4)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	palm_mesh.material_override = mat
	palm_mesh.position = Vector3(0, 0, -0.05)
	hand.add_child(palm_mesh)

	var fingers_mesh := MeshInstance3D.new()
	fingers_mesh.name = "Fingers"
	var fingers := BoxMesh.new()
	fingers.size = Vector3(0.07, 0.02, 0.07)
	fingers_mesh.mesh = fingers
	fingers_mesh.material_override = mat
	fingers_mesh.position = Vector3(0, 0, -0.13)
	hand.add_child(fingers_mesh)

	var thumb_mesh := MeshInstance3D.new()
	thumb_mesh.name = "Thumb"
	var thumb := BoxMesh.new()
	thumb.size = Vector3(0.025, 0.025, 0.05)
	thumb_mesh.mesh = thumb
	thumb_mesh.material_override = mat
	var side := 1.0 if "Left" in model_name else -1.0
	thumb_mesh.position = Vector3(side * 0.045, 0, -0.06)
	hand.add_child(thumb_mesh)

	hand.rotation.z = deg_to_rad(90)
	hand.position = Vector3(0, 0, 0.20)
	controller.add_child(hand)
	print("[VR Mod] Created fallback box hand model: ", model_name)


func _apply_hand_texture(root: Node) -> void:
	# Load the shared skin texture on first call; reuse for both hands after that.
	if not _hand_tex:
		var tex_path := _assets_base + "hand_col.png"
		if FileAccess.file_exists(tex_path):
			var img := Image.load_from_file(tex_path)
			if img:
				_hand_tex = ImageTexture.create_from_image(img)
				_hand_load_errors.append("hand: loaded skin texture " + tex_path)
			else:
				_hand_load_errors.append("hand: Image.load_from_file failed for " + tex_path)
		else:
			_hand_load_errors.append("hand: skin texture not found at " + tex_path)
	# Build a StandardMaterial3D with the skin texture (or plain skin colour as fallback).
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.roughness = 0.85
	mat.metallic = 0.0
	if _hand_tex:
		mat.albedo_texture = _hand_tex
	else:
		mat.albedo_color = Color(0.76, 0.60, 0.46)  # neutral skin fallback
	# Apply material_override on every MeshInstance3D inside the scene.
	_hand_apply_mat_recursive(root, mat)


func _hand_apply_mat_recursive(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.material_override = mat
	for child in node.get_children():
		_hand_apply_mat_recursive(child, mat)


func _update_hand_poses(delta: float) -> void:
	# Procedural finger curl — blends each finger toward its target curl based on the
	# controller's grip/trigger analog values and thumb button state. This reproduces the
	# godot-xr-tools pose set (Open / Closed / Point / Thumbs Up) without needing its
	# AnimationTree machinery. Curl is applied around each bone's local X axis (finger
	# hinge axis) on top of the resting pose captured at load time.
	_update_one_hand("left", delta)
	_update_one_hand("right", delta)


func _update_one_hand(hand: String, delta: float) -> void:
	var skel: Skeleton3D = _hand_skel_left if hand == "left" else _hand_skel_right
	if not skel or not is_instance_valid(skel):
		return
	var ctrl := _get_controller(hand)
	if not ctrl or not ctrl.get_is_active():
		return

	# Read analog inputs (0.0–1.0). Quest/OpenXR action map uses these names.
	var grip_val: float = clampf(ctrl.get_float("grip"), 0.0, 1.0)
	var trig_val: float = clampf(ctrl.get_float("trigger"), 0.0, 1.0)

	# Thumb: extended (uncurled) only when no thumb-resting button is held. When either
	# face button is pressed, the thumb rests on the button → curled. Defaults to the
	# "thumbs up" pose (thumb uncurled) when nothing is pressed — classic xr-tools behavior.
	var thumb_down := ctrl.is_button_pressed("ax_button") or ctrl.is_button_pressed("by_button")
	# Touch sensors provide a finer signal on supported runtimes; fall back silently if absent.
	if not thumb_down:
		if ctrl.is_button_pressed("ax_touch") or ctrl.is_button_pressed("by_touch"):
			thumb_down = true
	var thumb_target: float = 1.0 if thumb_down else 0.0

	# Index tracks trigger; middle/ring/little track grip.
	var targets := {
		"thumb": thumb_target,
		"index": trig_val,
		"middle": grip_val,
		"ring": grip_val,
		"little": grip_val,
	}

	var curl_state: Dictionary = _hand_curl_left if hand == "left" else _hand_curl_right
	var fingers: Dictionary = _hand_fingers_left if hand == "left" else _hand_fingers_right
	var rest: Dictionary = _hand_bone_rest_left if hand == "left" else _hand_bone_rest_right
	var alpha := clampf(delta * HAND_CURL_SMOOTH_SPEED, 0.0, 1.0)
	# Right hand finger bones are mirrored so their local Z points opposite to the left hand.
	var finger_axis: Vector3 = HAND_CURL_AXIS_FINGER if hand == "left" else -HAND_CURL_AXIS_FINGER

	for finger_name in fingers.keys():
		# Smooth the curl value toward its target so fingers animate continuously instead
		# of snapping on button events.
		var cur: float = curl_state[finger_name]
		cur = lerpf(cur, targets[finger_name], alpha)
		curl_state[finger_name] = cur

		var bones: Array = fingers[finger_name]
		if bones.is_empty():
			continue
		var is_thumb: bool = (finger_name == "thumb")
		var max_curl: float = HAND_THUMB_MAX_CURL if is_thumb else HAND_FINGER_MAX_CURL
		var curl_axis: Vector3 = HAND_CURL_AXIS_THUMB if is_thumb else finger_axis

		for i in bones.size():
			var bi: int = bones[i]
			var weight: float = HAND_FINGER_JOINT_WEIGHT[min(i, HAND_FINGER_JOINT_WEIGHT.size() - 1)]
			# Negative angle so the rotation curls toward the palm.
			var angle: float = -cur * max_curl * weight
			var rest_q: Quaternion = rest[bi]
			var curl_q := Quaternion(curl_axis, angle)
			skel.set_bone_pose_rotation(bi, rest_q * curl_q)


func _create_watch_mesh() -> void:
	# Determine non-dominant hand
	var non_dom = "left" if _config_dominant_hand == "right" else "right"
	var controller = _get_controller(non_dom)
	if not controller:
		_log("WARNING: non-dominant controller not found for watch")
		return

	# Use a dedicated mount Node3D with no rotation — avoids hand model rotation complexity
	# CRITICAL: Never add MeshInstance3D directly to XRController3D; always wrap in Node3D
	var mount = Node3D.new()
	mount.name = "WatchMount"
	controller.add_child(mount)

	_watch_mesh = MeshInstance3D.new()
	_watch_mesh.name = "WristWatch"

	var quad = QuadMesh.new()
	quad.size = Vector2(_watch_size, _watch_size)
	_watch_mesh.mesh = quad

	# ShaderMaterial with UV crop + alpha fade
	var shader = Shader.new()
	shader.code = WATCH_CROP_SHADER
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("hud_texture", hud_viewport.get_texture())
	if _watch_b_vp:
		mat.set_shader_parameter("medical_tex", _watch_b_vp.get_texture())
	mat.set_shader_parameter("alpha", 0.0)
	mat.render_priority = 10
	_watch_mesh.material_override = mat

	# Use layer 1 so it's definitely in the XR camera cull_mask
	# (layer 20 would require game camera's cull_mask to include it)
	_watch_mesh.layers = 1

	# Position: slightly forward and up from the controller tracking point,
	# rotated so the face points upward (palm-up wrist position)
	# In controller space: +Z = forward/pointing, +Y = up, +X = right
	# Watch at 0.05m forward, 0.02m up, face pointing upward
	_watch_mesh.position = _watch_offset
	# Base -90 X points the quad face upward; _watch_rot is an additional user offset
	# applied before the base, giving three independent axes to tune.
	_watch_mesh.basis = _watch_rot_basis()

	mount.add_child(_watch_mesh)
	_watch_mesh.visible = false
	_log("Wrist watch installed on " + non_dom + " hand, mount at " + str(mount.get_path()))


func _destroy_watch_mesh() -> void:
	if _watch_mesh and is_instance_valid(_watch_mesh):
		# Free the WatchMount parent too
		var mount = _watch_mesh.get_parent()
		if mount and is_instance_valid(mount) and mount.name == "WatchMount":
			mount.queue_free()
		else:
			_watch_mesh.queue_free()
	_watch_mesh = null
	_watch_alpha = 0.0
	_teardown_watch_content()


func _setup_watch_content() -> void:
	# Find Vitals and Medical in the game HUD
	var stats = get_tree().root.get_node_or_null("Map/Core/UI/HUD/Stats")
	if not stats:
		_log("WARNING: HUD/Stats not found — watch will show full HUD texture")
		return

	_vitals_node = stats.get_node_or_null("Vitals") as Control
	_medical_node = stats.get_node_or_null("Medical") as Control

	if not _vitals_node and not _medical_node:
		_log("WARNING: Neither Vitals nor Medical found — watch will show full HUD texture")
		return

	# Nodes stay in the game HUD tree — reparenting breaks their size (containers).
	# Wait 30 frames for layout to compute, then read their screen rects.
	# If rects are still zero-size (tutorial / early game), fall back to a
	# geometry-guided crop after 60 attempts, then stop retrying.
	_watch_crop_computed = false
	_watch_crop_delay = 30
	_watch_crop_retries = 0
	_log("Watch: found Vitals=" + str(_vitals_node != null) + " Medical=" + str(_medical_node != null) + " — crop will be computed in 30 frames")


func _compute_watch_crop() -> void:
	if not hud_viewport:
		return

	var vp_w = float(hud_viewport.size.x)
	var vp_h = float(hud_viewport.size.y)

	# ── Force spread=1.0 so elements land at known canvas positions ──────────
	# At spread=1.0: Stats container at (vp_w/2, vp_h).
	# Vitals x = vp_w/2 - vp_w/4 = vp_w/4  (960 for 3840-wide canvas)
	# Medical x = vp_w/2 + vp_w/4 = 3*vp_w/4 (2880 for 3840-wide canvas)
	# Elements are ~800px wide and ~270px tall from the bottom of the canvas.
	_hud_spread_active = 1.0
	_apply_hud_spread()

	# ── Fixed crop rects proportional to viewport size ────────────────────────
	var elem_w  = vp_w * 0.208       # ~800 / 3840 at 3840-wide canvas
	var elem_h  = vp_h * 0.25        # ~270 / 1080
	var elem_top = vp_h - elem_h     # bottom-aligned
	var vitals_cx  = vp_w * 0.25    # x=960
	var medical_cx = vp_w * 0.75    # x=2880

	var vitals_rect  = Rect2(vitals_cx  - elem_w * 0.5, elem_top, elem_w, elem_h)
	var medical_rect = Rect2(medical_cx - elem_w * 0.5, elem_top, elem_w, elem_h)

	_log("Watch crop: vitals=" + str(vitals_rect) + " medical=" + str(medical_rect))

	# ── Apply canvas_transform — each viewport shows its own element only ─────
	var sx = vp_w / elem_w
	var sy = vp_h / elem_h

	var tv = Transform2D()
	tv[0] = Vector2(sx, 0.0)
	tv[1] = Vector2(0.0, sy)
	tv[2] = Vector2(-vitals_rect.position.x * sx, -vitals_rect.position.y * sy)
	hud_viewport.canvas_transform = tv

	if _watch_b_vp:
		var tm = Transform2D()
		tm[0] = Vector2(sx, 0.0)
		tm[1] = Vector2(0.0, sy)
		tm[2] = Vector2(-medical_rect.position.x * sx, -medical_rect.position.y * sy)
		_watch_b_vp.canvas_transform = tm

	_watch_crop_computed = true
	_log("Watch crop scale=(" + str(snapped(sx, 0.01)) + "," + str(snapped(sy, 0.01)) + ")")

	if _watch_mesh and is_instance_valid(_watch_mesh):
		# Each viewport is elem_w x elem_h; stacked vertically = elem_w x (2*elem_h)
		var stacked_aspect = elem_w / (elem_h * 2.0)
		var quad_w = clamp(_watch_size * stacked_aspect, 0.02, 1.0)
		var quad_h = _watch_size
		(_watch_mesh.mesh as QuadMesh).size = Vector2(quad_w, quad_h)
		_log("Watch quad: " + str(snapped(quad_w, 0.001)) + "m x " + str(snapped(quad_h, 0.001)) + "m (aspect " + str(snapped(stacked_aspect, 0.01)) + ")")


func _teardown_watch_content() -> void:
	# Reset canvas_transforms so the floating menu HUD renders correctly
	if hud_viewport:
		hud_viewport.canvas_transform = Transform2D.IDENTITY
	if _watch_b_vp:
		_watch_b_vp.canvas_transform = Transform2D.IDENTITY
	_vitals_node = null
	_medical_node = null
	_watch_crop_computed = false
	_watch_crop_delay = 0
	_watch_crop_retries = 0


func _esc_find_deepest_stop_control(node: Node, pos: Vector2) -> Control:
	# Recursively find the deepest visible STOP-filter Control containing pos.
	# Children are checked in reverse draw order (topmost first).
	if not (node is Control):
		return null
	var ctrl = node as Control
	if not ctrl.is_visible_in_tree():
		return null
	var r = ctrl.get_global_rect()
	if r.size.x <= 0 or r.size.y <= 0:
		return null
	if not r.has_point(pos):
		return null
	for i in range(ctrl.get_child_count() - 1, -1, -1):
		var found = _esc_find_deepest_stop_control(ctrl.get_child(i), pos)
		if found:
			return found
	if ctrl.mouse_filter == Control.MOUSE_FILTER_STOP:
		return ctrl
	return null


func _esc_click_at(pos: Vector2) -> void:
	var settings_node = get_tree().root.get_node_or_null("Map/Core/UI/Settings")
	if not settings_node:
		_log("ESC click: no Settings node at pos=" + str(pos))
		return
	var target = _esc_find_deepest_stop_control(settings_node, pos)
	if not target:
		_log("ESC click: no target at " + str(pos))
		return
	_log("ESC click -> " + str(target.name) + " [" + target.get_class() + "] rect=" + str(target.get_global_rect()))
	if target is Range:
		var r = target.get_global_rect()
		var ratio = clampf((pos.x - r.position.x) / r.size.x, 0.0, 1.0)
		var new_val = target.min_value + ratio * (target.max_value - target.min_value)
		_log("ESC slider -> " + str(target.name) + " val=" + str(new_val))
		target.value = new_val
	else:
		# Push real press+release events to the control's viewport so the
		# button state machine fires fully (emit_signal bypasses it).
		var click_pos = target.get_global_rect().get_center()
		var vp = target.get_viewport()
		var ev_press = InputEventMouseButton.new()
		ev_press.button_index = MOUSE_BUTTON_LEFT
		ev_press.pressed = true
		ev_press.position = click_pos
		ev_press.global_position = click_pos
		vp.push_input(ev_press, true)
		var ev_rel = InputEventMouseButton.new()
		ev_rel.button_index = MOUSE_BUTTON_LEFT
		ev_rel.pressed = false
		ev_rel.position = click_pos
		ev_rel.global_position = click_pos
		vp.push_input(ev_rel, true)


func _update_esc_hover() -> void:
	if not _esc_menu_active or _laser_screen_pos.x < 0:
		_esc_clear_hover()
		return
	var settings_node = get_tree().root.get_node_or_null("Map/Core/UI/Settings")
	if not settings_node:
		_esc_clear_hover()
		return
	var target = _esc_find_deepest_stop_control(settings_node, _laser_screen_pos)
	if target and not (target is BaseButton or target is Range):
		target = null
	if target == _esc_hovered_control:
		return
	if _esc_hovered_control and is_instance_valid(_esc_hovered_control):
		_esc_hovered_control.notification(Control.NOTIFICATION_MOUSE_EXIT)
	_esc_hovered_control = target
	if target:
		target.notification(Control.NOTIFICATION_MOUSE_ENTER)


func _esc_clear_hover() -> void:
	if _esc_hovered_control and is_instance_valid(_esc_hovered_control):
		_esc_hovered_control.notification(Control.NOTIFICATION_MOUSE_EXIT)
	_esc_hovered_control = null


func _toggle_esc_menu() -> void:
	# Use Input.parse_input_event only (no push_input) to avoid double-processing.
	var ev_press := InputEventKey.new()
	ev_press.keycode = KEY_ESCAPE
	ev_press.physical_keycode = KEY_ESCAPE
	ev_press.pressed = true
	var ev_release := InputEventKey.new()
	ev_release.keycode = KEY_ESCAPE
	ev_release.physical_keycode = KEY_ESCAPE
	ev_release.pressed = false

	if _interface_open and not _esc_menu_active:
		# An inventory/loot/trade screen is open — close it first.
		# A subsequent menu button press (after it closes) will open the ESC menu.
		_key_states.erase(KEY_ESCAPE)
		Input.parse_input_event(ev_press)
		get_tree().create_timer(0.08).timeout.connect(func(): Input.parse_input_event(ev_release))
		print("[VR Mod] Menu button: closing open interface screen")
	elif not _esc_menu_active:
		_esc_menu_active = true
		_key_states.erase(KEY_ESCAPE)
		Input.parse_input_event(ev_press)
		# No release — menu stays open until next press.
		print("[VR Mod] ESC menu opened")
	else:
		_esc_clear_hover()
		_esc_menu_active = false
		_key_states.erase(KEY_ESCAPE)
		Input.parse_input_event(ev_press)
		get_tree().create_timer(0.08).timeout.connect(func(): Input.parse_input_event(ev_release))
		print("[VR Mod] ESC menu closed (menu button)")


func _dump_visible_canvas_nodes() -> void:
	# Scan the entire scene tree for visible CanvasItem nodes not in our known HUD paths.
	# Fired 0.3 s after ESC menu opens to identify where the ESC menu node lives.
	_log("=== ESC MENU NODE SCAN ===")
	var known_paths := ["VRHudViewport", "VRWatchMedVP", "VRModOrigin", "VRHudPanel",
		"Map/Core/UI/HUD", "Map/Core/UI/Effects", "Map/Core/UI/NVG"]
	_scan_for_visible_canvas(get_tree().root, "", known_paths, 0)
	_log("=== END ESC MENU NODE SCAN ===")


func _scan_for_visible_canvas(node: Node, path: String, skip_prefixes: Array, depth: int) -> void:
	if depth > 20:
		return
	var full_path := path + "/" + node.name if path != "" else node.name
	if node == self or node == xr_origin:
		return
	for skip in skip_prefixes:
		if full_path.contains(skip):
			return
	if node is Control and (node as Control).is_visible_in_tree():
		var ctrl := node as Control
		var r := ctrl.get_global_rect()
		var mf := ctrl.mouse_filter
		var mf_str := "STOP" if mf == 0 else ("PASS" if mf == 1 else "IGNORE")
		# Only log controls with non-zero size and not IGNORE
		if r.size.x > 0 and r.size.y > 0 and mf != Control.MOUSE_FILTER_IGNORE:
			_log("  CTRL: " + full_path + " [" + node.get_class() + "] rect=" + str(r) + " mf=" + mf_str)
	for child in node.get_children():
		_scan_for_visible_canvas(child, full_path, skip_prefixes, depth + 1)


func _grenade_auto_holster() -> void:
	if _holster_state == HolsterState.DRAWN and _weapon_slot == 4:
		_holster_weapon()


func _clear_grenade_state() -> void:
	if _grenade_pin_pulled:
		Input.action_release("fire")
		Input.action_release("left_mouse")
		_inject_action("fire", false)
		_inject_action("left_mouse", false)
		_inject_mouse_button(MOUSE_BUTTON_LEFT, false)
	_grenade_pin_pulled = false


func _grenade_tap_release() -> void:
	_inject_mouse_button(MOUSE_BUTTON_LEFT, false)
	_inject_action("fire", false)
	_inject_action("left_mouse", false)
	Input.action_release("fire")
	Input.action_release("left_mouse")


func _grenade_replace_pin() -> void:
	_grenade_pin_pulled = false
	_inject_mouse_button(MOUSE_BUTTON_RIGHT, true)
	get_tree().create_timer(0.08).timeout.connect(_grenade_replace_pin_release)


func _grenade_replace_pin_release() -> void:
	_inject_mouse_button(MOUSE_BUTTON_RIGHT, false)


func _grenade_throw_tap() -> void:
	_grenade_pin_pulled = false
	_inject_mouse_button(MOUSE_BUTTON_LEFT, true)
	_inject_action("fire", true)
	_inject_action("left_mouse", true)
	Input.action_press("fire", 1.0)
	Input.action_press("left_mouse", 1.0)
	get_tree().create_timer(0.08).timeout.connect(_grenade_tap_release)
	get_tree().create_timer(0.5).timeout.connect(_grenade_auto_holster)


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

	# Reset hand wrappers to their canonical GLTF position/rotation when no weapon
	# sway is active (UNARMED / SLING), so a stale sway displacement from the last
	# DRAWN frame does not persist after holstering.
	if _holster_state == HolsterState.UNARMED or _holster_state == HolsterState.SLING:
		if _hand_wrapper_left:
			_hand_wrapper_left.position = HAND_GLTF_OFFSET_LEFT
			_hand_wrapper_left.rotation_degrees = HAND_GLTF_ROTATION_LEFT
		if _hand_wrapper_right:
			_hand_wrapper_right.position = HAND_GLTF_OFFSET_RIGHT
			_hand_wrapper_right.rotation_degrees = HAND_GLTF_ROTATION_RIGHT

	# Laser pointer: grab range when UNARMED, interact range when LOWERED (weapon hand)
	if _laser_mesh and not _menu_open and not _config_screen_open:
		var show_laser := false
		var laser_hand := _config_dominant_hand

		if _decor_mode:
			show_laser = true
			laser_hand = _config_dominant_hand
		elif _holster_state == HolsterState.UNARMED and _grabbed_object == null:
			show_laser = true
			laser_hand = _config_dominant_hand
		elif _holster_state == HolsterState.LOWERED or _holster_state == HolsterState.SLING:
			show_laser = true
			laser_hand = _config_dominant_hand

		if show_laser:
			# Reparent laser to correct controller if needed
			var target_ctrl = _get_controller(laser_hand)
			if target_ctrl and _laser_mesh.get_parent() != target_ctrl:
				_laser_mesh.get_parent().remove_child(_laser_mesh)
				target_ctrl.add_child(_laser_mesh)
				_laser_mesh.rotation.x = deg_to_rad(90)

			# Check what the ray is pointing at
			var grab_ray := _grab_ray_right if laser_hand == "right" else _grab_ray_left
			var pointing_at_grabbable := false
			var pointing_at_interactable := false
			var pointing_at_furniture := false
			var hover_collider: Node3D = null
			var hover_hit_pos := Vector3.ZERO
			if _decor_mode and game_camera and is_instance_valid(game_camera):
				# Use the game's Interactor raycast (driven by game camera we steer)
				var interactor = game_camera.get_node_or_null("Interactor")
				if interactor is RayCast3D and interactor.is_colliding():
					var col = interactor.get_collider()
					if col:
						# Check collider and its parent for furniture indicators
						var check = col
						for _i in range(4):
							if not check:
								break
							if check.is_in_group("Interactable") or check.is_in_group("Furniture") \
									or check.is_in_group("Placable") or check.is_in_group("Placeable"):
								pointing_at_furniture = true
								break
							if check.get_script():
								var sp: String = check.get_script().resource_path
								if "Furniture" in sp or "Placabl" in sp or "Decor" in sp:
									pointing_at_furniture = true
									break
							check = check.get_parent()
			else:
				# Grabbable: mod's GrabRay handles pickup directly (RigidBody3D layer 4, 1m)
				if grab_ray and grab_ray.is_colliding():
					var c = grab_ray.get_collider()
					if c is RigidBody3D and (c.collision_layer & 4) != 0:
						pointing_at_grabbable = true
						hover_collider = c as Node3D
						hover_hit_pos = grab_ray.get_collision_point()
				# B-button interactable: use game's Interactor so yellow = B actually works
				if not pointing_at_grabbable and game_camera and is_instance_valid(game_camera):
					var interactor = game_camera.get_node_or_null("Interactor")
					if interactor is RayCast3D and interactor.is_colliding():
						var ic = interactor.get_collider()
						var check = ic
						for _i in range(4):
							if not is_instance_valid(check):
								break
							if check.is_in_group("Interactable"):
								pointing_at_interactable = true
								hover_collider = check as Node3D
								hover_hit_pos = interactor.get_collision_point()
								break
							check = check.get_parent()
			var mat := _laser_mesh.material_override as StandardMaterial3D
			if mat:
				if _decor_mode and pointing_at_furniture:
					mat.albedo_color = Color(1.0, 0.65, 0.1, 0.8)  # Orange - furniture targeted
				elif _decor_mode:
					mat.albedo_color = Color(0.2, 0.8, 1.0, 0.7)   # Cyan - decor placement
				elif pointing_at_grabbable:
					mat.albedo_color = Color(0.1, 1.0, 0.2, 0.7)   # Green - grabbable item
				elif pointing_at_interactable:
					mat.albedo_color = Color(1.0, 0.8, 0.1, 0.7)   # Yellow - B-interact
				else:
					mat.albedo_color = Color(1.0, 0.2, 0.1, 0.6)   # Red - nothing
			var cyl := _laser_mesh.mesh as CylinderMesh
			if cyl:
				cyl.height = 1.0
				_laser_mesh.position.z = -0.5

			# Update hover label with target name
			if _hover_label:
				if hover_collider != null:
					if pointing_at_interactable:
						_hover_label.text = _find_interactable_display_name(hover_collider)
					else:
						_hover_label.text = _format_node_name(hover_collider.name)
					_hover_label.global_position = hover_hit_pos + Vector3.UP * 0.15
					_hover_label.visible = true
				else:
					_hover_label.visible = false
			var has_target := pointing_at_grabbable or pointing_at_interactable or pointing_at_furniture
			_laser_mesh.visible = _laser_always_on or has_target
		else:
			if _hover_label:
				_hover_label.visible = false
			_laser_mesh.visible = false



func _hand_laser_sees_grabbable(hand: String) -> bool:
	var ray = _grab_ray_right if hand == "right" else _grab_ray_left
	if not ray or not ray.is_colliding():
		return false
	var c = ray.get_collider()
	return c is RigidBody3D and (c.collision_layer & 4) != 0


func _try_grab(hand: String) -> void:
	if _grabbed_object:
		return  # Already holding something

	var grab_ray = _grab_ray_right if hand == "right" else _grab_ray_left
	if not grab_ray or not grab_ray.is_colliding():
		return

	var collider = grab_ray.get_collider()
	if not collider:
		return

	# Only grab loose items: RigidBody3D with collision layer 4
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
		# Hide ALL surfaces — arms (0-1) AND hands (2+). The game's hand surfaces can't be
		# individually detached so we hide the whole Arms mesh; our skeletal VR hands on the
		# controllers are visible in all states (including when the support hand releases
		# the weapon), which is why both need to go together.
		if mesh.mesh:
			for i in mesh.mesh.get_surface_count():
				mesh.set_surface_override_material(i, _invis_mat)
		return  # Arms found, no need to go deeper
	for child in node.get_children():
		_hide_arms_in_subtree(child)


func _weapon_key() -> String:
	return _weapon_hand + "|" + _current_weapon_name

func _get_weapon_grip_offset() -> Vector3:
	var k := _weapon_key()
	if _current_weapon_name != "" and _weapon_grip_offsets.has(k):
		return _weapon_grip_offsets[k]
	return _slot_grip_defaults.get(_weapon_slot, Vector3.ZERO)

func _get_weapon_grip_rotation() -> float:
	var k := _weapon_key()
	if _current_weapon_name != "" and _weapon_grip_rotations.has(k):
		return _weapon_grip_rotations[k]
	return _slot_rot_defaults.get(_weapon_slot, 0.0)

func _set_weapon_grip_offset(v: Vector3) -> void:
	if _current_weapon_name != "":
		_weapon_grip_offsets[_weapon_key()] = v

func _set_weapon_grip_rotation(v: float) -> void:
	if _current_weapon_name != "":
		_weapon_grip_rotations[_weapon_key()] = v

func _has_weapon_fg_p() -> bool:
	return _current_weapon_name != "" and _weapon_fg_p_local.has(_weapon_key())

func _get_weapon_fg_p() -> Vector3:
	if _current_weapon_name != "":
		return _weapon_fg_p_local.get(_weapon_key(), Vector3.ZERO)
	return Vector3.ZERO

func _get_weapon_fg_r() -> Basis:
	if _current_weapon_name != "":
		return _weapon_fg_r_local.get(_weapon_key(), Basis.IDENTITY)
	return Basis.IDENTITY

func _set_weapon_fg_p(v: Vector3) -> void:
	if _current_weapon_name != "":
		_weapon_fg_p_local[_weapon_key()] = v

func _set_weapon_fg_r(v: Basis) -> void:
	if _current_weapon_name != "":
		_weapon_fg_r_local[_weapon_key()] = v


func _sync_weapon_to_controller() -> void:
	if not game_camera or not is_instance_valid(game_camera):
		return
	if _interface_open:
		return

	var mgr = game_camera.get_node_or_null("Manager")
	if not mgr or mgr.get_child_count() == 0:
		# If we think a weapon is equipped but the rig is gone, the game unequipped it
		# externally (e.g. via inventory while drawn). Reset without injecting the unequip
		# key — the game already handled the unequip.
		if _holster_state != HolsterState.UNARMED and _weapon_loaded:
			print("[VR Mod] Weapon rig gone externally — resetting to UNARMED")
			_pending_holster_key = -1
			_adjust_mode = false
			_fg_adjust_mode = false
			if _rail_mode:
				_exit_rail_mode()
			_cleanup_scope()
			_inject_action("aim", false)
			_inject_action("weapon_high", false)
			_holster_state = HolsterState.UNARMED
			_weapon_hand = ""
			_weapon_slot = 0
			_current_weapon_name = ""
			_weapon_loaded = false
			_weapon_is_long = false
			_weapon_subtype = ""
			_weapon_uses_r_reload = false
			_action_open = false
			_pump_gesture_active = false
			_pump_prev_pos = Vector3.ZERO
			_pump_cooldown = 0.0
			_clear_grenade_state()
			_support_grip_held = false
		return

	var weapon_rig = mgr.get_child(0)
	if not weapon_rig or not weapon_rig is Node3D:
		return
	_cached_weapon_rig = weapon_rig
	_current_weapon_name = weapon_rig.name.trim_suffix("_Rig")

	# Only sync when weapon is equipped (DRAWN or LOWERED)
	if _holster_state == HolsterState.UNARMED:
		return

	# SLING: position weapon at chest, not at controller
	if _holster_state == HolsterState.SLING:
		_sync_weapon_to_sling(weapon_rig)
		return

	var controller = _get_controller(_get_weapon_hand())
	if not controller or not controller.get_is_active():
		return

	# Two-hand aiming: only when support grip is held
	var off_controller = _get_controller(_get_support_hand())
	var use_two_hand = false
	var aim_basis: Basis

	# Single-hand basis computed at function scope so the smooth-init path can also use it.
	# Grenades (slot 4): ignore grip rotation — throw direction must follow controller forward.
	var sh_rot_offset: float = 0.0 if _weapon_slot == 4 else _get_weapon_grip_rotation()
	var single_hand_basis: Basis = controller.global_basis * Basis(Vector3.UP, deg_to_rad(180 + sh_rot_offset))
	var local_offset: Vector3 = _get_weapon_grip_offset()

	# Foregrip adjust: freeze the weapon in place so the player can position their support
	# hand freely. Canonical hand resets are applied; normal sync skipped.
	if _fg_adjust_mode:
		weapon_rig.global_transform = _fg_adjust_frozen_xform
		_apply_sway_to_hands(weapon_rig, controller, off_controller, single_hand_basis, local_offset, Transform3D.IDENTITY, false, Vector3.ZERO)
		_hide_arms_in_subtree(weapon_rig)
		return

	if _support_grip_held and off_controller and off_controller.get_is_active():
		var hand_dist = controller.global_position.distance_to(off_controller.global_position)
		if hand_dist > 0.1:
			use_two_hand = true
			# Aim direction: from dominant hand model center toward off-hand controller.
			# Only the dominant side uses the GLTF offset (weapon grip is attached there).
			# The off-hand is a raw position target — applying its GLTF offset (19.5cm Z)
			# skews the aim when the off-hand controller is rotated relative to the aim line.
			var dom_hand_off = HAND_GLTF_OFFSET_RIGHT if _get_weapon_hand() == "right" else HAND_GLTF_OFFSET_LEFT
			var forward = (off_controller.global_position - controller.global_position - controller.global_basis * dom_hand_off).normalized()
			# Use world up; fall back to controller Y when aiming nearly vertical.
			# Godot is right-handed: right = forward x up (NOT up x forward, which gives LEFT
			# and produces an improper/mirrored basis). Previous bug flipped aim_basis.x and
			# mirrored the weapon mesh relative to single-hand mode.
			var up = Vector3.UP
			var right_vec = forward.cross(up)
			if right_vec.length_squared() < 0.01:
				up = controller.global_basis.y
				right_vec = forward.cross(up)
			right_vec = right_vec.normalized()
			var corrected_up = right_vec.cross(forward).normalized()
			aim_basis = Basis(right_vec, corrected_up, -forward)
			aim_basis = aim_basis * Basis(Vector3.UP, deg_to_rad(180))

	if not use_two_hand:
		aim_basis = single_hand_basis

	# Two-hand stabilization: slerp the FULL aim basis from single-hand to the two-hand target.
	# Slerping the complete basis (not just the forward vector) keeps both the dominant-hand grip
	# position AND orientation aligned with the hand model throughout the transition, because both
	# the GLTF hand offset and the weapon local_offset are defined in controller/aim-local space.
	if use_two_hand and _two_hand_smooth_enabled:
		var target_basis := aim_basis
		if not _two_hand_was_active:
			# First frame: seed from the exact single-hand basis so the weapon stays
			# exactly where it was the moment the off-hand grabs.
			_two_hand_smooth_basis = single_hand_basis
			# Also seed raw aim basis — arc_comp on first frame will be ZERO (no jump).
			_arc_raw_aim_basis = single_hand_basis
		else:
			# Subsequent frames: record unsmoothed raw aim for arc_comp (no lag).
			_arc_raw_aim_basis = target_basis
		_two_hand_smooth_basis = _two_hand_smooth_basis.slerp(target_basis, clampf(get_process_delta_time() * _two_hand_smooth_speed, 0.0, 1.0))
		aim_basis = _two_hand_smooth_basis

	if use_two_hand:
		_two_hand_was_active = true
		if not _two_hand_smooth_enabled:
			# Smooth disabled: aim_basis IS raw aim.
			_arc_raw_aim_basis = aim_basis
	else:
		_two_hand_was_active = false
		_fg_grip_captured = false
		_arc_raw_aim_basis = single_hand_basis  # reset so next grab starts clean

	# Handle deferred rest capture: wait for Handling.gd to animate the weapon
	# into its aimed steady state before sampling, so _recoil_rest_xform and
	# _walk_sway_rest both reflect the same calibrated pose. This avoids a ~0.7m
	# position jump when the walk-sway toggle is flipped.
	if _rest_capture_pending:
		_walk_sway_capture_delay -= get_process_delta_time()
		if _walk_sway_capture_delay <= 0.0:
			_rest_capture_pending = false
			_walk_sway_capture_delay = 0.0
			_recoil_rest_xform = _sample_recoil_chain(weapon_rig)
			_walk_sway_rest.clear()
			for node_name in _WALK_SWAY_NODES:
				var wn := _walk_chain_node(weapon_rig, node_name)
				if wn:
					_walk_sway_rest[node_name] = wn.transform
			_walk_sway_captured = true
			_walk_sway_logged = false

	# Suppress walk bob at the chain nodes (forced rest pose each frame) so they
	# neither contribute to the chain sample below nor to the mesh parent chain.
	# Only active once rest has been captured; otherwise we'd clamp to stale rest.
	if _disable_walk_sway and not _rest_capture_pending:
		_suppress_walk_sway(weapon_rig)

	# Sample recoil chain and apply delta on top of controller aim. While still
	# waiting for the first capture, force identity so the weapon sits at
	# controller+local_offset (matches the post-capture steady state).
	var recoil_delta := Transform3D.IDENTITY
	if not _rest_capture_pending:
		recoil_delta = _recoil_rest_xform.affine_inverse() * _sample_recoil_chain(weapon_rig)
	weapon_rig.global_basis = aim_basis * recoil_delta.basis

	# Fire haptics: rising recoil_delta magnitude = shot actually fired.
	# Works for empty chamber (no recoil) and full-auto (one pulse per shot).
	_fire_haptic_cooldown -= get_process_delta_time()
	var cur_recoil_mag := recoil_delta.origin.length()
	if cur_recoil_mag - _prev_recoil_mag > 0.003 and _fire_haptic_cooldown <= 0.0:
		var hap_dom := _get_controller(_weapon_hand)
		if hap_dom:
			hap_dom.trigger_haptic_pulse("haptic", 0.0, 0.8, 0.08, 0.0)
		if _support_grip_held:
			var hap_sup := _get_controller(_get_support_hand())
			if hap_sup:
				hap_sup.trigger_haptic_pulse("haptic", 0.0, 0.5, 0.08, 0.0)
		_fire_haptic_cooldown = 0.08
	_prev_recoil_mag = cur_recoil_mag

	# Pivot compensation: keep the weapon grip at the dominant hand model center.
	# Without this, aim_basis * local_offset shifts the weapon toward the off-hand as
	# the aim direction changes, making the weapon appear glued to the off-hand.
	# Uses _arc_raw_aim_basis (unsmoothed) to avoid lag on the dominant hand.
	# On the first frame of two-hand, _arc_raw_aim_basis == single_hand_basis so
	# arc_r_delta = Identity and arc_comp = 0 — no position jump at transition.
	var arc_comp := Vector3.ZERO
	var arc_is_right := _get_weapon_hand() == "right"
	var arc_dom_off := HAND_GLTF_OFFSET_RIGHT if arc_is_right else HAND_GLTF_OFFSET_LEFT
	var arc_dom_rot := HAND_GLTF_ROTATION_RIGHT if arc_is_right else HAND_GLTF_ROTATION_LEFT
	var arc_sh_rot := 0.0 if _weapon_slot == 4 else _get_weapon_grip_rotation()
	var arc_rot_b := Basis.from_euler(arc_dom_rot * (PI / 180.0))
	var arc_w2h := Basis(Vector3.UP, deg_to_rad(-(180.0 + arc_sh_rot))) * arc_rot_b
	var arc_r_delta := Basis.IDENTITY
	if use_two_hand:
		arc_r_delta = controller.global_basis.inverse() * _arc_raw_aim_basis * arc_w2h * arc_rot_b.inverse()
		arc_comp = controller.global_basis * (arc_dom_off - arc_r_delta * arc_dom_off)
	weapon_rig.global_position = controller.global_position + arc_comp + aim_basis * (local_offset + recoil_delta.origin)

	# Displace hand models so they visually follow weapon sway / recoil.
	_apply_sway_to_hands(weapon_rig, controller, off_controller, aim_basis, local_offset, recoil_delta, use_two_hand, arc_comp)

	# Hide all arm surfaces on every weapon type (guns, knives, grenades)
	_hide_arms_in_subtree(weapon_rig)

	# Fix reticle parallax for VR (once per sight mesh)
	_fix_reticle_parallax(weapon_rig)

	# Scope PIP: detect and activate game's scope SubViewport, position camera
	_setup_scope_pip(weapon_rig)
	_update_scope_camera()


func _apply_sway_to_hands(
		weapon_rig: Node3D,
		dom_ctrl: XRController3D, sup_ctrl: XRController3D,
		aim_basis: Basis, local_offset: Vector3,
		recoil_delta: Transform3D, use_two_hand: bool,
		arc_comp: Vector3) -> void:
	# Displace each hand wrapper so the hand appears to grip the gun rather than
	# floating at the raw controller position while the weapon bobs from sway/recoil.
	#
	# Displacement formula for a point P in weapon_rig-no-sway local space:
	#   world_disp(P) = aim_basis * (recoil_delta.origin + recoil_delta.basis * P - P)
	# Dominant grip: P_dom = -local_offset  (weapon_rig placed at ctrl + aim * local_offset)
	# Support grip: P_sup computed from off-hand controller world position
	#
	# Position displacement is applied as a controller-LOCAL offset so the configurable
	# HAND_GLTF_OFFSET_* is preserved (adding to it, not overwriting it).
	# Rotation: during two-hand aiming the dominant hand rotates to match the weapon
	# orientation (weapon_rig.global_basis), otherwise the canonical GLTF rotation is kept.
	#
	# Both wrappers are reset to their canonical GLTF position/rotation every call
	# so stale displacement from a previous frame never persists.

	var weapon_hand := _get_weapon_hand()
	var is_right_weapon := weapon_hand == "right"
	var dom_wrapper := _hand_wrapper_right if is_right_weapon else _hand_wrapper_left
	var sup_wrapper := _hand_wrapper_left  if is_right_weapon else _hand_wrapper_right
	var dom_off := HAND_GLTF_OFFSET_RIGHT    if is_right_weapon else HAND_GLTF_OFFSET_LEFT
	var dom_rot := HAND_GLTF_ROTATION_RIGHT  if is_right_weapon else HAND_GLTF_ROTATION_LEFT
	var sup_off := HAND_GLTF_OFFSET_LEFT     if is_right_weapon else HAND_GLTF_OFFSET_RIGHT
	var sup_rot := HAND_GLTF_ROTATION_LEFT   if is_right_weapon else HAND_GLTF_ROTATION_RIGHT

	# Always reset both wrappers to canonical pose first; sway is then additive
	if dom_wrapper:
		dom_wrapper.position = dom_off
		dom_wrapper.rotation_degrees = dom_rot
	if sup_wrapper:
		sup_wrapper.position = sup_off
		sup_wrapper.rotation_degrees = sup_rot

	# During two-hand aiming, rotate dominant hand to track the weapon tilt.
	# The weapon has a built-in 180 Y flip (+ slot rotation) relative to the controller.
	# weapon_to_hand undoes that flip before applying the GLTF offset, so the hand
	# carries the same grip-relative orientation as in single-hand mode but tilted with
	# the weapon. Verification: when aim_basis == single_hand_basis (no tilt) this
	# reduces to dom_rot_basis (canonical), matching the normal non-two-hand reset above.
	#
	# The hand stays at dom_off (anchored to the physical controller). The weapon
	# is shifted by arc_comp so its grip aligns with the hand model center.
	if use_two_hand and dom_wrapper:
		var sh_rot_deg := 0.0 if _weapon_slot == 4 else _get_weapon_grip_rotation()
		var dom_rot_basis := Basis.from_euler(dom_rot * (PI / 180.0))
		var weapon_to_hand := Basis(Vector3.UP, deg_to_rad(-(180.0 + sh_rot_deg))) * dom_rot_basis
		var new_hand_basis := dom_ctrl.global_basis.inverse() * weapon_rig.global_basis * weapon_to_hand
		dom_wrapper.transform = Transform3D(new_hand_basis, dom_off)

	if recoil_delta == Transform3D.IDENTITY:
		return

	# Direct tracking: read the exact world position of each grip point from the
	# weapon_rig transform, which already has every chain animation baked in.
	#
	# Dominant grip is at -local_offset in weapon_rig local space (by calibration:
	# weapon_rig was placed at controller + aim_basis*local_offset, so the controller
	# is at -local_offset in weapon_rig local).
	#
	# Support grip: p_sup is the off-hand position expressed in no-sway weapon_rig
	# local space; the sway transform maps it exactly to its displaced world position.
	if dom_wrapper:
		var grip_world := weapon_rig.global_transform * (-local_offset)
		var grip_disp := dom_ctrl.global_basis.inverse() * (grip_world - dom_ctrl.global_position)
		var arc_local := dom_ctrl.global_basis.inverse() * arc_comp
		dom_wrapper.position = dom_off + grip_disp - arc_local

	if use_two_hand and sup_ctrl and sup_ctrl.get_is_active() and sup_wrapper:
		# Foregrip adjust active: gun is frozen, support hand follows controller canonically.
		# The canonical reset at the top of this function already set sup_wrapper to sup_off/sup_rot,
		# so nothing more to do here.
		if not _fg_adjust_mode:
			# First frame of two-hand or after release: load per-slot saved position/rotation.
			# If slot has never been configured, fall back to capturing from the current
			# controller position (hand stays where the player grabbed) so unconfigured
			# slots still work naturally.
			if not _fg_grip_captured:
				if _has_weapon_fg_p():
					_fg_p_sup_local = _get_weapon_fg_p()
					_fg_r_sup_local = _get_weapon_fg_r()
				else:
					var hand_wp := sup_ctrl.global_position + sup_ctrl.global_basis * sup_off
					var hand_wb := sup_ctrl.global_basis * Basis.from_euler(sup_rot * (PI / 180.0))
					_fg_p_sup_local = weapon_rig.global_transform.affine_inverse() * hand_wp
					_fg_r_sup_local = weapon_rig.global_basis.inverse() * hand_wb
				_fg_grip_captured = true
			var sup_grip_world := weapon_rig.global_transform * _fg_p_sup_local
			var tgt_basis := weapon_rig.global_basis * _fg_r_sup_local
			sup_wrapper.position = sup_ctrl.global_basis.inverse() * (sup_grip_world - sup_ctrl.global_position)
			sup_wrapper.basis = sup_ctrl.global_basis.inverse() * tgt_basis


func _sync_weapon_to_sling(weapon_rig: Node3D) -> void:
	if not xr_camera or not is_instance_valid(xr_camera):
		return
	weapon_rig.visible = true  # override any game-side visibility flag each frame
	# Build a yaw-only basis from the camera so the weapon follows the player's turn
	# but not their head pitch/roll (hangs naturally at chest level)
	var head_yaw := xr_camera.global_rotation.y
	var yaw_basis := Basis(Vector3.UP, head_yaw)
	weapon_rig.global_position = xr_camera.global_position + yaw_basis * _sling_offset
	# Orient weapon to face forward with the same handedness as the drawn single-hand basis,
	# then apply the per-axis sling rotation offset (pitch/yaw/roll in degrees)
	var slot_y_rot: float = _get_weapon_grip_rotation()
	var base_basis := yaw_basis * Basis(Vector3.UP, deg_to_rad(180.0 + slot_y_rot))
	weapon_rig.global_basis = base_basis * Basis.from_euler(Vector3(
		deg_to_rad(_sling_rot_offset.x),
		deg_to_rad(_sling_rot_offset.y),
		deg_to_rad(_sling_rot_offset.z)))
	_hide_arms_in_subtree(weapon_rig)


const _RECOIL_CHAIN_NAMES: Array = ["Handling", "Sway", "Noise", "Tilt", "Impulse", "Recoil"]

func _sample_recoil_chain(weapon_rig: Node3D) -> Transform3D:
	var composed := Transform3D.IDENTITY
	var current: Node3D = weapon_rig
	for chain_name in _RECOIL_CHAIN_NAMES:
		var child = current.get_node_or_null(chain_name)
		if not child or not child is Node3D:
			break
		composed = composed * child.transform
		current = child
	return composed


# Walk-sway suppression: force specific chain nodes to their captured rest pose
# every frame so their walk-bob + stamina output is clamped. Rest is captured
# per-node on first suppression after a weapon load. Impulse/Recoil are left
# intact so hit reactions and firing recoil still work.
const _WALK_SWAY_NODES: Array = ["Handling", "Sway", "Noise", "Tilt"]
var _walk_sway_rest: Dictionary = {}   # name -> Transform3D
var _walk_sway_captured := false
var _walk_sway_logged := false
# Delay before we first capture + start clamping. At weapon load, the game's
# Handling.gd has not yet animated the weapon into its aimed position — capturing
# at that moment would lock the weapon at its pre-raise offset and create a
# visible jump between sway-on / sway-off modes. Waiting ~1s lets the chain
# settle so we capture the steady-state (calibrated) values instead.
var _walk_sway_capture_delay := 0.0
var _rest_capture_pending := false  # Waiting for Handling.gd to settle before capturing
const _WALK_SWAY_CAPTURE_DELAY_LOAD := 2.0
const _WALK_SWAY_CAPTURE_DELAY_TOGGLE := 0.1

func _walk_chain_node(weapon_rig: Node3D, node_name: String) -> Node3D:
	# Walk the chain parent-to-child until we hit node_name. Returns null if
	# the chain terminates early.
	var current: Node3D = weapon_rig
	for chain_name in _RECOIL_CHAIN_NAMES:
		var child = current.get_node_or_null(chain_name)
		if not child or not child is Node3D:
			return null
		if chain_name == node_name:
			return child
		current = child
	return null

func _suppress_walk_sway(weapon_rig: Node3D) -> void:
	# Capture rest poses once per weapon load, then slam the named nodes back
	# to rest each frame AFTER the game's scripts have updated them.
	if not _walk_sway_captured:
		_walk_sway_rest.clear()
		for node_name in _WALK_SWAY_NODES:
			var n := _walk_chain_node(weapon_rig, node_name)
			if n:
				_walk_sway_rest[node_name] = n.transform
		_walk_sway_captured = true
		_walk_sway_logged = false
	for node_name in _WALK_SWAY_NODES:
		if not _walk_sway_rest.has(node_name):
			continue
		var n := _walk_chain_node(weapon_rig, node_name)
		if n:
			n.transform = _walk_sway_rest[node_name]
	# One-time diagnostic so we can verify the override is actually landing.
	if not _walk_sway_logged:
		_walk_sway_logged = true
		var f = FileAccess.open(_log_path, FileAccess.READ_WRITE)
		if not f:
			f = FileAccess.open(_log_path, FileAccess.WRITE)
		if f:
			f.seek_end(0)
			f.store_line("[walk_sway] captured rest poses:")
			for node_name in _WALK_SWAY_NODES:
				if _walk_sway_rest.has(node_name):
					var t: Transform3D = _walk_sway_rest[node_name]
					f.store_line("  " + node_name + " origin=" + str(t.origin) + " basis_x=" + str(t.basis.x) + " basis_y=" + str(t.basis.y) + " basis_z=" + str(t.basis.z))
				else:
					f.store_line("  " + node_name + " NOT FOUND in chain")
			f.close()


func _format_node_name(raw: String) -> String:
	# Convert PascalCase to separate words ("AmmoBox" -> "Ammo Box")
	# and replace underscores with spaces ("ammo_box" -> "ammo box").
	var result := ""
	for i in range(raw.length()):
		var ch := raw[i]
		if i > 0 and ch >= "A" and ch <= "Z":
			result += " "
		result += ch
	return result.replace("_", " ").strip_edges()


func _find_interactable_display_name(collider: Node) -> String:
	# Walk up the ancestry from the collider to find the first node that has a
	# game script attached — that is the real object (LootContainer, Trader, Door, etc.).
	# Intermediate nodes like "Mesh" or "Collider" typically carry no script.
	var scene_root = get_tree().current_scene
	var check: Node = collider
	for _i in range(6):
		check = check.get_parent()
		if not check or check == scene_root or check == self:
			break
		if check.get_script() != null:
			return _format_node_name(check.name)
	# Fallback: direct parent name
	var p = collider.get_parent()
	if p and p != scene_root and p != self:
		return _format_node_name(p.name)
	return _format_node_name(collider.name)


func _log(msg: String) -> void:
	var path = _log_path
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


func _classify_weapon_is_long(weapon_rig: Node3D) -> bool:
	# Slots 3 (knife) and 4 (grenade) are never long weapons
	if _weapon_slot == 3 or _weapon_slot == 4:
		_log("Weapon class: short (slot " + str(_weapon_slot) + ")")
		return false
	# Check weapon data resource for weaponType property (authoritative)
	var data_res = weapon_rig.get("data")
	if data_res and data_res is Resource:
		var weapon_type = data_res.get("weaponType")
		var subtype = data_res.get("subtype")
		_log("Weapon classify: name=" + weapon_rig.name + " slot=" + str(_weapon_slot)
			+ " weaponType=" + str(weapon_type) + " subtype=" + str(subtype))
		if weapon_type != null:
			var wt: String = str(weapon_type).to_lower()
			# Long weapon types: rifle, shotgun, SMG, carbine, DMR, sniper, LMG, etc.
			# Short weapon types: pistol
			if "pistol" in wt:
				_log("Weapon class: short (weaponType=" + str(weapon_type) + ")")
				return false
			# Any non-pistol firearm type is long
			_log("Weapon class: long (weaponType=" + str(weapon_type) + ")")
			return true
	# Fallback: slot 2 defaults to short, slot 1 defaults to long
	_log("Weapon classify: name=" + weapon_rig.name + " slot=" + str(_weapon_slot) + " (no data resource)")
	if _weapon_slot == 2:
		_log("Weapon class: short (sidearm slot, no weaponType)")
		return false
	_log("Weapon class: long (default for slot " + str(_weapon_slot) + ")")
	return true


func _get_weapon_subtype(weapon_rig: Node3D) -> String:
	if _weapon_slot == 3:
		return "Melee"
	if _weapon_slot == 4:
		return "Grenade"
	var data_res = weapon_rig.get("data")
	if data_res and data_res is Resource:
		var st = data_res.get("subtype")
		if st != null:
			return str(st)
	return ""


func _update_pump_gesture(delta: float) -> void:
	_pump_cooldown -= delta
	var sup_ctrl = _get_controller(_get_support_hand())
	if not sup_ctrl:
		return
	var pos: Vector3 = sup_ctrl.position
	# Initialize reference on first call or after reset
	if _pump_prev_pos == Vector3.ZERO:
		_pump_prev_pos = pos
		return
	# PUMP_OUT: how far hand must move from reference to start the gesture.
	# PUMP_BACK: how close hand must return to the frozen reference to complete it.
	# Reference slowly tracks resting hand position (accounts for arm drift).
	# During forward phase the reference is frozen so only a real return fires the pump.
	const PUMP_OUT := 0.06        # 6 cm displacement from reference
	const PUMP_BACK := 0.03       # 3 cm from frozen reference = returned far enough
	const TRACK_RATE := 3.0       # reference lerp speed while idle (m/s equivalent)
	if not _pump_gesture_active:
		_pump_prev_pos = _pump_prev_pos.lerp(pos, delta * TRACK_RATE)
		if pos.distance_to(_pump_prev_pos) > PUMP_OUT:
			_pump_gesture_active = true
			_pump_gesture_timer = 1.2
			print("[VR Mod] PUMP: fwd phase dist=", snappedf(pos.distance_to(_pump_prev_pos) * 100.0, 0.1), "cm")
	else:
		_pump_gesture_timer -= delta
		var dist: float = pos.distance_to(_pump_prev_pos)
		if dist < PUMP_BACK:
			if _pump_cooldown <= 0.0:
				_inject_action("reload", true)
				_inject_action("reload", false)
				print("[VR Mod] PUMP — shell cycled (R)")
				var dom_ctrl = _get_controller(_weapon_hand)
				if dom_ctrl:
					dom_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.12, 0.0)
				_pump_cooldown = 0.5
			_pump_gesture_active = false
			_pump_prev_pos = pos
		elif _pump_gesture_timer <= 0.0:
			print("[VR Mod] PUMP: timeout dist=", snappedf(dist * 100.0, 0.1), "cm")
			_pump_gesture_active = false
			_pump_prev_pos = pos


# ── Wrist watch crop shader ───────────────────────────────────────────────

const WATCH_CROP_SHADER := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_test_disabled;

// hud_viewport is cropped to just the Vitals element.
// watch_b_vp is cropped to just the Medical element.
// Each viewport has its own canvas_transform so the elements never overlap.
uniform sampler2D hud_texture : source_color, filter_linear;
uniform sampler2D medical_tex : source_color, filter_linear;
uniform float alpha : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex;
	// QuadMesh: UV.y=1 is top of visible face, UV.y=0 is bottom
	if (UV.y >= 0.5) {
		// Top half of watch face: Vitals viewport
		tex = texture(hud_texture, vec2(UV.x, (UV.y - 0.5) * 2.0));
	} else {
		// Bottom half of watch face: Medical viewport
		tex = texture(medical_tex, vec2(UV.x, UV.y * 2.0));
	}
	ALBEDO = tex.rgb;
	ALPHA = tex.a * alpha;
}
"""


# ── Comfort vignette shader ─────────────────────────────────────────────────
# Darkens the screen periphery during rotation to reduce motion sickness.
# Parented to xr_camera as a 2m quad at z=-0.3m with depth_test_disabled.
# Center UV region stays transparent; edges fade to black via smoothstep.

const COMFORT_VIGNETTE_SHADER := """
shader_type spatial;
render_mode depth_test_disabled, skip_vertex_transform, unshaded, cull_disabled, blend_mix;

uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float radius = 1.0;
uniform float fade = 0.15;

varying float dist;

void vertex() {
    vec2 v = VERTEX.xy;
    dist = length(v);

    if (dist < 1.5) {
        dist = radius;
        v *= dist;
        vec4 eye = PROJECTION_MATRIX * vec4(0.0, 0.0, 100.0, 1.0);
        v += eye.xy / eye.w;
    }

    float z = PROJECTION_MATRIX[2][2] < 0.0 ? 0.0 : 1.0;
    POSITION = vec4(v, z, 1.0);
}

void fragment() {
    ALBEDO = color.rgb;
    ALPHA = clamp((dist - radius) / fade, 0.0, 1.0);
}
"""


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
uniform float eyebox_position = 0.30;
uniform float eyebox_tolerance = 0.025;
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
	vec2 depth_uv = UV - view_dir.xy * (scope_depth * 2.0);
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
		# Check if current scope attachment is still valid and visible
		# (player may have swapped scopes on the same weapon slot)
		if _scope_attachment and is_instance_valid(_scope_attachment) and _scope_attachment.visible:
			return
		# Scope changed — re-detect
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


# --- Rail movement (optic slide along weapon rail) ---

func _enter_rail_mode() -> void:
	_rail_mode = true
	_adjust_mode = false      # Cancel adjust mode if somehow active
	_fg_adjust_mode = false   # Cancel foregrip adjust mode if somehow active
	var ctrl = _get_controller(_get_support_hand())
	if ctrl:
		ctrl.trigger_haptic_pulse("haptic", 0.0, 0.4, 0.15, 0.0)
	print("[VR Mod] === RAIL MODE ON ===")

func _exit_rail_mode() -> void:
	if _rail_active:
		_end_rail_slide()
	_rail_mode = false
	_rail_x_pending = false
	print("[VR Mod] === RAIL MODE OFF ===")

func _start_rail_slide() -> void:
	_rail_active = true
	_rail_scroll_accum = 0.0
	# Record off-hand position projected onto weapon forward axis
	var support_ctrl = _get_controller(_get_support_hand())
	if support_ctrl and game_camera:
		var weapon_fwd = -game_camera.global_basis.z
		_rail_grab_origin = support_ctrl.global_position.dot(weapon_fwd)
	_inject_key(KEY_CTRL, true)
	if support_ctrl:
		support_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.1, 0.0)
	print("[VR Mod] Rail slide started (trigger grab)")

func _end_rail_slide() -> void:
	_rail_active = false
	_inject_key(KEY_CTRL, false)
	_rail_scroll_accum = 0.0
	print("[VR Mod] Rail slide ended")

func _update_rail_slide() -> void:
	if not _rail_active:
		return
	var support_ctrl = _get_controller(_get_support_hand())
	if not support_ctrl or not game_camera:
		return
	var weapon_fwd = -game_camera.global_basis.z
	var current_proj = support_ctrl.global_position.dot(weapon_fwd)
	var delta_proj = current_proj - _rail_grab_origin
	_rail_scroll_accum += delta_proj
	_rail_grab_origin = current_proj
	var threshold = 0.02  # 2cm per scroll tick
	while _rail_scroll_accum > threshold:
		_inject_scroll(1)
		_rail_scroll_accum -= threshold
		support_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.15, 0.05, 0.0)
	while _rail_scroll_accum < -threshold:
		_inject_scroll(-1)
		_rail_scroll_accum += threshold
		support_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.15, 0.05, 0.0)


func _force_debug_dump(label: String) -> void:
	if not game_camera or not is_instance_valid(game_camera):
		return
	var dump_path = _log_path
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
	var config_path = _config_path
	if not FileAccess.file_exists(config_path):
		var bundled := "res://resources/default_config.json"
		if FileAccess.file_exists(bundled):
			var src := FileAccess.open(bundled, FileAccess.READ)
			if src:
				var content := src.get_as_text()
				src.close()
				DirAccess.make_dir_recursive_absolute("user://vr_mod")
				var dst := FileAccess.open(config_path, FileAccess.WRITE)
				if dst:
					dst.store_string(content)
					dst.close()
					print("[VR Mod] Seeded config from bundled defaults: ", config_path)
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
				_render_scale = data["xr"].get("render_scale", 1.0)
			if data.has("comfort"):
				use_snap_turn = data["comfort"].get("turn_type", "smooth") == "snap"
				snap_turn_degrees = data["comfort"].get("snap_turn_degrees", 45.0)
				smooth_turn_speed = data["comfort"].get("smooth_turn_speed", 120.0)
				_vignette_enabled = data["comfort"].get("vignette_enabled", false)
				_vignette_strength = data["comfort"].get("vignette_strength", 0.7)
				_two_hand_smooth_enabled = data["comfort"].get("two_hand_smooth_enabled", true)
				_two_hand_smooth_speed = data["comfort"].get("two_hand_smooth_speed", 14.0)
				_disable_walk_sway = not data["comfort"].get("walk_sway_enabled", true)
			if data.has("controls"):
				thumbstick_deadzone = data["controls"].get("thumbstick_deadzone", 0.15)
				_config_dominant_hand = data["controls"].get("dominant_hand", "right")
				_standing_mode = data["controls"].get("standing_mode", false)
				_gun_config_enabled = data["controls"].get("gun_config_enabled", false)
				_laser_always_on = data["controls"].get("laser_always_on", true)
			if data.has("holsters"):
				_holster_zone_radius = data["holsters"].get("zone_radius", 0.27)
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
				_nvg_brightness = nz.get("brightness", 5.0)
				_nvg_mono = nz.get("mono", true)
			if data.has("weapon_offsets"):
				var wo = data["weapon_offsets"]
				for wname in wo:
					var o = wo[wname]
					_weapon_grip_offsets[wname] = Vector3(o.get("x", 0.0), o.get("y", 0.0), o.get("z", 0.0))
					_weapon_grip_rotations[wname] = o.get("rot", 0.0)
			if data.has("foregrip_p_local"):
				var fgp = data["foregrip_p_local"]
				for wname in fgp:
					var o = fgp[wname]
					_weapon_fg_p_local[wname] = Vector3(o.get("x", 0.0), o.get("y", 0.0), o.get("z", 0.0))
			if data.has("foregrip_r_local"):
				var fgr = data["foregrip_r_local"]
				for wname in fgr:
					var o = fgr[wname]
					var q := Quaternion(o.get("x", 0.0), o.get("y", 0.0), o.get("z", 0.0), o.get("w", 1.0))
					_weapon_fg_r_local[wname] = Basis(q)
			if data.has("hud"):
				var h = data["hud"]
				_hud_width = h.get("width", 2.3)
				_hud_distance = h.get("distance", 0.9)
				_hud_height_offset = h.get("height_offset", -0.05)
				_hud_lr_offset = h.get("lr_offset", 0.0)
				_hud_smooth_follow = h.get("smooth_follow", true)
				_hud_smooth_speed = h.get("smooth_speed", 2.0)
				_hud_spread = h.get("spread", 0.5)
			if data.has("watch"):
				var w = data["watch"]
				_watch_size = w.get("size", 0.15)
				_watch_glance_enabled = w.get("glance_enabled", false)
				_watch_glance_angle = w.get("glance_angle", 40.0)
				_watch_fade_speed = w.get("fade_speed", 8.0)
				_watch_spread = w.get("spread", 0.15)
				var wo = w.get("offset", {})
				_watch_offset = Vector3(wo.get("x", -0.06), wo.get("y", -0.08), wo.get("z", 0.34))
				var wr = w.get("rot", {})
				_watch_rot = Vector3(wr.get("x", 180.0), wr.get("y", 90.0), wr.get("z", -90.0))
			if data.has("hand_models"):
				var hm = data["hand_models"]
				var hl = hm.get("left", {})
				HAND_GLTF_OFFSET_LEFT = Vector3(hl.get("x", -0.03), hl.get("y", -0.015), hl.get("z", 0.195))
				var hlr = hl.get("rot", {})
				HAND_GLTF_ROTATION_LEFT = Vector3(hlr.get("x", 0.0), hlr.get("y", 0.0), hlr.get("z", 0.0))
				var hr = hm.get("right", {})
				HAND_GLTF_OFFSET_RIGHT = Vector3(hr.get("x", 0.025), hr.get("y", 0.01), hr.get("z", 0.195))
				var hrr = hr.get("rot", {})
				HAND_GLTF_ROTATION_RIGHT = Vector3(hrr.get("x", 0.0), hrr.get("y", 0.0), hrr.get("z", 0.0))
			if data.has("sling"):
				var sl = data["sling"]
				_sling_offset = Vector3(sl.get("x", 0.2), sl.get("y", -0.31), sl.get("z", -0.06))
				var slr = sl.get("rot", {})
				_sling_rot_offset = Vector3(slr.get("x", 0.0), slr.get("y", 60.0), slr.get("z", 0.0))
			if data.has("menu"):
				var m = data["menu"]
				_menu_width = m.get("width", 3.0)
				_menu_distance = m.get("distance", 1.0)
				_menu_lr_offset = m.get("lr_offset", 0.0)
				_menu_laser_uv_x = m.get("laser_uv_x", 0.0)
				_menu_laser_uv_y = m.get("laser_uv_y", 0.0)
			print("[VR Mod] Config loaded successfully")
	file.close()


func _save_grip_config() -> void:
	var config_path = _config_path
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
	for wname in _weapon_grip_offsets:
		var o := _weapon_grip_offsets[wname] as Vector3
		wo[wname] = {
			"x": snapped(o.x, 0.001),
			"y": snapped(o.y, 0.001),
			"z": snapped(o.z, 0.001),
			"rot": snapped(_weapon_grip_rotations.get(wname, 0.0), 0.1)
		}
	data["weapon_offsets"] = wo

	var fgp := {}
	for wname in _weapon_fg_p_local:
		var p: Vector3 = _weapon_fg_p_local[wname]
		fgp[wname] = {"x": snapped(p.x, 0.0001), "y": snapped(p.y, 0.0001), "z": snapped(p.z, 0.0001)}
	data["foregrip_p_local"] = fgp

	var fgr := {}
	for wname in _weapon_fg_r_local:
		var b: Basis = _weapon_fg_r_local[wname]
		var q := b.get_rotation_quaternion()
		fgr[wname] = {"x": snapped(q.x, 0.0001), "y": snapped(q.y, 0.0001), "z": snapped(q.z, 0.0001), "w": snapped(q.w, 0.0001)}
	data["foregrip_r_local"] = fgr

	var out = FileAccess.open(config_path, FileAccess.WRITE)
	if out:
		out.store_string(JSON.stringify(data, "\t"))
		out.close()
		print("[VR Mod] Grip config saved to: ", config_path)
		for wname in _weapon_grip_offsets:
			var o = _weapon_grip_offsets[wname]
			print("[VR Mod]   ", wname, ": grip x=", snapped(o.x, 0.001), " y=", snapped(o.y, 0.001), " z=", snapped(o.z, 0.001), " rot=", snapped(_weapon_grip_rotations.get(wname, 0.0), 0.1), "° foregrip_configured=", _weapon_fg_p_local.has(wname))


# ── Smooth HUD follow ──────────────────────────────────────────────────────────

func _update_smooth_hud(delta: float) -> void:
	if not _hud_smooth_follow:
		return
	if not hud_mesh:
		return
	if not hud_mesh.visible:
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


# ── Wrist watch glance ────────────────────────────────────────────────────────

func _update_watch_glance(delta: float) -> void:
	if not _watch_mesh or not xr_camera:
		return

	if not _watch_glance_enabled:
		# Glance disabled — always visible
		_watch_alpha = 1.0
		var mat = _watch_mesh.material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("alpha", 1.0)
		_watch_mesh.visible = true
		return

	# Gaze direction (camera forward, world space)
	var gaze_dir = -xr_camera.global_basis.z

	# Vector from eye to watch (world space)
	var eye_to_watch = _watch_mesh.global_position - xr_camera.global_position
	var dist = eye_to_watch.length()
	if dist < 0.01:
		return
	eye_to_watch = eye_to_watch / dist

	# One condition: gaze direction points toward watch
	var gaze_dot = gaze_dir.dot(eye_to_watch)

	var threshold = cos(deg_to_rad(_watch_glance_angle))
	var looking = gaze_dot > threshold

	# Smooth fade
	var target_alpha = 1.0 if looking else 0.0
	_watch_alpha = move_toward(_watch_alpha, target_alpha, _watch_fade_speed * delta)

	# Apply alpha to shader
	var mat = _watch_mesh.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("alpha", _watch_alpha)

	# Toggle visibility for render cost savings
	_watch_mesh.visible = _watch_alpha > 0.001


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
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_dump_ray_target()


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

	# Outer layout: title + tabs (expand) + button row (pinned)
	var outer = VBoxContainer.new()
	outer.name = "CfgOuter"
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(outer)

	# Title (pinned above tabs, never scrolls)
	var title = Label.new()
	title.text = "VR Mod Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	outer.add_child(title)

	_mk_sep(outer)

	# ── Tab container ──
	var tabs = TabContainer.new()
	tabs.name = "CfgTabs"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 22)
	# Tab selected style
	var tab_sel = StyleBoxFlat.new()
	tab_sel.bg_color = Color(0.18, 0.38, 0.65, 1.0)
	tab_sel.set_corner_radius_all(6)
	tab_sel.content_margin_left = 18
	tab_sel.content_margin_right = 18
	tab_sel.content_margin_top = 12
	tab_sel.content_margin_bottom = 12
	tabs.add_theme_stylebox_override("tab_selected", tab_sel)
	# Tab unselected style
	var tab_unsel = StyleBoxFlat.new()
	tab_unsel.bg_color = Color(0.13, 0.13, 0.18, 1.0)
	tab_unsel.set_corner_radius_all(6)
	tab_unsel.content_margin_left = 18
	tab_unsel.content_margin_right = 18
	tab_unsel.content_margin_top = 12
	tab_unsel.content_margin_bottom = 12
	tabs.add_theme_stylebox_override("tab_unselected", tab_unsel)
	# Tab hovered style
	var tab_hov = StyleBoxFlat.new()
	tab_hov.bg_color = Color(0.20, 0.20, 0.28, 1.0)
	tab_hov.set_corner_radius_all(6)
	tab_hov.content_margin_left = 18
	tab_hov.content_margin_right = 18
	tab_hov.content_margin_top = 12
	tab_hov.content_margin_bottom = 12
	tabs.add_theme_stylebox_override("tab_hovered", tab_hov)
	# Transparent content panel (outer PanelContainer already provides the bg)
	var tab_panel = StyleBoxFlat.new()
	tab_panel.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	tabs.add_theme_stylebox_override("panel", tab_panel)
	# Tab font colors
	tabs.add_theme_color_override("font_selected_color", Color(1.0, 1.0, 1.0))
	tabs.add_theme_color_override("font_unselected_color", Color(0.6, 0.6, 0.7))
	tabs.add_theme_color_override("font_hovered_color", Color(0.85, 0.85, 0.95))
	outer.add_child(tabs)

	# ── Tab 0: General ──
	var scroll_gen = ScrollContainer.new()
	scroll_gen.name = "General"
	scroll_gen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_gen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll_gen)
	var vbox_gen = VBoxContainer.new()
	vbox_gen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_gen.add_child(vbox_gen)

	_mk_header(vbox_gen, "Comfort")
	var grid_comfort = _mk_grid(vbox_gen)
	_add_toggle_row(grid_comfort, "Turn Mode", ["Snap", "Smooth"], 0 if use_snap_turn else 1, "_on_cfg_turn")
	_add_stepper_row(grid_comfort, "Snap Degrees", snap_turn_degrees, 15.0, 90.0, 5.0, "_on_cfg_snap_deg")
	_add_stepper_row(grid_comfort, "Smooth Speed", smooth_turn_speed, 30.0, 300.0, 10.0, "_on_cfg_smooth_spd")
	_add_toggle_row(grid_comfort, "Vignette", ["On", "Off"], 0 if _vignette_enabled else 1, "_on_cfg_vignette")
	_add_stepper_row(grid_comfort, "Vig. Strength", _vignette_strength, 0.1, 1.0, 0.1, "_on_cfg_vignette_str")
	_add_stepper_row(grid_comfort, "Render Scale", _render_scale, 0.5, 1.0, 0.05, "_on_cfg_render_scale")
	_add_toggle_row(grid_comfort, "2H Stabilize", ["On", "Off"], 0 if _two_hand_smooth_enabled else 1, "_on_cfg_2h_smooth")
	_add_stepper_row(grid_comfort, "2H Smooth", _two_hand_smooth_speed, 2.0, 30.0, 1.0, "_on_cfg_2h_smooth_spd")
	_add_toggle_row(grid_comfort, "Weapon Sway", ["On", "Off"], 1 if _disable_walk_sway else 0, "_on_cfg_walk_sway")

	_mk_sep(vbox_gen)

	_mk_header(vbox_gen, "Menu / Inventory")
	var grid_menu = _mk_grid(vbox_gen)
	_add_stepper_row(grid_menu, "Distance", _menu_distance, 0.5, 3.0, 0.1, "_on_cfg_menu_dist")
	_add_stepper_row(grid_menu, "Size", _menu_width, 0.5, 5.0, 0.1, "_on_cfg_menu_wid")
	_add_stepper_row(grid_menu, "Left/Right", _menu_lr_offset, -1.0, 1.0, 0.05, "_on_cfg_menu_lr")
	_add_stepper_row(grid_menu, "Height", _hud_height_offset, -1.0, 1.0, 0.05, "_on_cfg_hud_hgt")
	_add_stepper_row(grid_menu, "HUD Spread", _hud_spread, 0.1, 2.0, 0.1, "_on_cfg_hud_spread")
	_add_stepper_row(grid_menu, "Laser X", _menu_laser_uv_x, -5.0, 5.0, 0.01, "_on_cfg_laser_x")
	_add_stepper_row(grid_menu, "Laser Y", _menu_laser_uv_y, -5.0, 5.0, 0.01, "_on_cfg_laser_y")

	_mk_sep(vbox_gen)

	_mk_header(vbox_gen, "Controls")
	var grid_ctrl = _mk_grid(vbox_gen)
	_add_toggle_row(grid_ctrl, "Dominant Hand", ["Right", "Left"], 0 if _config_dominant_hand == "right" else 1, "_on_cfg_hand")
	_add_toggle_row(grid_ctrl, "Tracking Mode", ["Sitting", "Standing"], 1 if _standing_mode else 0, "_on_cfg_standing_mode")
	_add_toggle_row(grid_ctrl, "Gun Config", ["Off", "On"], 1 if _gun_config_enabled else 0, "_on_cfg_gun_config")
	_add_toggle_row(grid_ctrl, "Laser Always On", ["On", "Off"], 0 if _laser_always_on else 1, "_on_cfg_laser_always_on")

	# ── Tab 1: Zones ──
	var scroll_zone = ScrollContainer.new()
	scroll_zone.name = "Zones"
	scroll_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll_zone)
	var vbox_zone = VBoxContainer.new()
	vbox_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_zone.add_child(vbox_zone)

	_mk_header(vbox_zone, "Holster Zones")
	var grid_holsters = _mk_grid(vbox_zone)
	_add_stepper_row(grid_holsters, "Zone Radius", _holster_zone_radius, 0.05, 0.5, 0.01, "_on_cfg_hz_radius")
	var zone_names := ["1: R.Shoulder", "2: R.Hip", "3: L.Hip", "4: Chest"]
	for zi in range(4):
		var slot = zi + 1
		var o: Vector3 = _holster_offsets[slot]
		_mk_header(vbox_zone, zone_names[zi])
		var grid_z = _mk_grid(vbox_zone)
		_add_stepper_row(grid_z, "X (L/R)", o.x, -0.6, 0.6, 0.01, "_on_cfg_hz_x_" + str(slot))
		_add_stepper_row(grid_z, "Y (U/D)", o.y, -1.0, 0.2, 0.01, "_on_cfg_hz_y_" + str(slot))
		_add_stepper_row(grid_z, "Z (F/B)", o.z, -0.5, 0.5, 0.01, "_on_cfg_hz_z_" + str(slot))

	_mk_sep(vbox_zone)

	_mk_header(vbox_zone, "Bag Zone (Inventory)")
	var grid_bag = _mk_grid(vbox_zone)
	_add_stepper_row(grid_bag, "Radius", _bag_zone_radius, 0.05, 0.8, 0.01, "_on_cfg_bag_radius")
	_add_stepper_row(grid_bag, "X (L/R)", _bag_zone_offset.x, -0.5, 0.5, 0.01, "_on_cfg_bag_x")
	_add_stepper_row(grid_bag, "Y (U/D)", _bag_zone_offset.y, -0.5, 0.5, 0.01, "_on_cfg_bag_y")
	_add_stepper_row(grid_bag, "Z (F/B)", _bag_zone_offset.z, 0.0, 0.8, 0.01, "_on_cfg_bag_z")

	_mk_sep(vbox_zone)

	_mk_header(vbox_zone, "NVG Zone (Above Head)")
	var grid_nvg = _mk_grid(vbox_zone)
	_add_stepper_row(grid_nvg, "Radius", _nvg_zone_radius, 0.05, 0.5, 0.01, "_on_cfg_nvg_radius")
	_add_stepper_row(grid_nvg, "Y (Height)", _nvg_zone_offset.y, 0.0, 0.6, 0.01, "_on_cfg_nvg_y")
	_add_stepper_row(grid_nvg, "Brightness", _nvg_brightness, 1.0, 5.0, 0.25, "_on_cfg_nvg_brightness")
	_add_toggle_row(grid_nvg, "Mono Vision", ["Off", "On"], 1 if _nvg_mono else 0, "_on_cfg_nvg_mono")

	# ── Tab 2: Calibrate ──
	var scroll_cal = ScrollContainer.new()
	scroll_cal.name = "Calibrate"
	scroll_cal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_cal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll_cal)
	var vbox_cal = VBoxContainer.new()
	vbox_cal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_cal.add_child(vbox_cal)

	_mk_header(vbox_cal, "Wrist Watch")
	var grid_watch = _mk_grid(vbox_cal)
	_add_toggle_row(grid_watch, "Glance Reveal", ["Off", "On"], 1 if _watch_glance_enabled else 0, "_on_cfg_watch_glance")
	_add_stepper_row(grid_watch, "Glance Angle", _watch_glance_angle, 20.0, 70.0, 5.0, "_on_cfg_watch_angle")
	_add_stepper_row(grid_watch, "Glance Fade", _watch_fade_speed, 2.0, 20.0, 1.0, "_on_cfg_watch_fade")
	_add_stepper_row(grid_watch, "Size", _watch_size, 0.04, 0.50, 0.01, "_on_cfg_watch_size")
	_add_stepper_row(grid_watch, "X (L/R)", _watch_offset.x, -0.5, 0.5, 0.01, "_on_cfg_watch_x")
	_add_stepper_row(grid_watch, "Y (U/D)", _watch_offset.y, -0.5, 0.5, 0.01, "_on_cfg_watch_y")
	_add_stepper_row(grid_watch, "Z (F/B)", _watch_offset.z, -0.5, 0.5, 0.01, "_on_cfg_watch_z")
	_add_stepper_row(grid_watch, "Rot X", _watch_rot.x, -180.0, 180.0, 5.0, "_on_cfg_watch_rot_x")
	_add_stepper_row(grid_watch, "Rot Y", _watch_rot.y, -180.0, 180.0, 5.0, "_on_cfg_watch_rot_y")
	_add_stepper_row(grid_watch, "Rot Z", _watch_rot.z, -180.0, 180.0, 5.0, "_on_cfg_watch_rot_z")

	_mk_sep(vbox_cal)

	_mk_header(vbox_cal, "Hand Models")
	_mk_header(vbox_cal, "Left Hand")
	var grid_hand_l = _mk_grid(vbox_cal)
	_add_stepper_row(grid_hand_l, "X (L/R)", HAND_GLTF_OFFSET_LEFT.x, -0.2, 0.2, 0.005, "_on_cfg_hand_l_x")
	_add_stepper_row(grid_hand_l, "Y (U/D)", HAND_GLTF_OFFSET_LEFT.y, -0.2, 0.2, 0.005, "_on_cfg_hand_l_y")
	_add_stepper_row(grid_hand_l, "Z (F/B)", HAND_GLTF_OFFSET_LEFT.z, -0.2, 0.2, 0.005, "_on_cfg_hand_l_z")
	_add_stepper_row(grid_hand_l, "Rot X", HAND_GLTF_ROTATION_LEFT.x, -180.0, 180.0, 5.0, "_on_cfg_hand_l_rx")
	_add_stepper_row(grid_hand_l, "Rot Y", HAND_GLTF_ROTATION_LEFT.y, -180.0, 180.0, 5.0, "_on_cfg_hand_l_ry")
	_add_stepper_row(grid_hand_l, "Rot Z", HAND_GLTF_ROTATION_LEFT.z, -180.0, 180.0, 5.0, "_on_cfg_hand_l_rz")
	_mk_header(vbox_cal, "Right Hand")
	var grid_hand_r = _mk_grid(vbox_cal)
	_add_stepper_row(grid_hand_r, "X (L/R)", HAND_GLTF_OFFSET_RIGHT.x, -0.2, 0.2, 0.005, "_on_cfg_hand_r_x")
	_add_stepper_row(grid_hand_r, "Y (U/D)", HAND_GLTF_OFFSET_RIGHT.y, -0.2, 0.2, 0.005, "_on_cfg_hand_r_y")
	_add_stepper_row(grid_hand_r, "Z (F/B)", HAND_GLTF_OFFSET_RIGHT.z, -0.2, 0.2, 0.005, "_on_cfg_hand_r_z")
	_add_stepper_row(grid_hand_r, "Rot X", HAND_GLTF_ROTATION_RIGHT.x, -180.0, 180.0, 5.0, "_on_cfg_hand_r_rx")
	_add_stepper_row(grid_hand_r, "Rot Y", HAND_GLTF_ROTATION_RIGHT.y, -180.0, 180.0, 5.0, "_on_cfg_hand_r_ry")
	_add_stepper_row(grid_hand_r, "Rot Z", HAND_GLTF_ROTATION_RIGHT.z, -180.0, 180.0, 5.0, "_on_cfg_hand_r_rz")

	_mk_sep(vbox_cal)

	_mk_header(vbox_cal, "Primary Weapon Sling")
	var grid_sling = _mk_grid(vbox_cal)
	_add_stepper_row(grid_sling, "X (L/R)", _sling_offset.x, -0.6, 0.6, 0.01, "_on_cfg_sling_x")
	_add_stepper_row(grid_sling, "Y (U/D)", _sling_offset.y, -0.8, 0.2, 0.01, "_on_cfg_sling_y")
	_add_stepper_row(grid_sling, "Z (F/B)", _sling_offset.z, -0.6, 0.2, 0.01, "_on_cfg_sling_z")
	_add_stepper_row(grid_sling, "Rot X", _sling_rot_offset.x, -180.0, 180.0, 5.0, "_on_cfg_sling_rx")
	_add_stepper_row(grid_sling, "Rot Y", _sling_rot_offset.y, -180.0, 180.0, 5.0, "_on_cfg_sling_ry")
	_add_stepper_row(grid_sling, "Rot Z", _sling_rot_offset.z, -180.0, 180.0, 5.0, "_on_cfg_sling_rz")

	# ── Save & Close (pinned below tabs — always visible) ──
	var btn_sep = HSeparator.new()
	btn_sep.add_theme_constant_override("separation", 10)
	outer.add_child(btn_sep)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.custom_minimum_size = Vector2(0, 52)
	outer.add_child(btn_row)

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


func _on_cfg_vignette(idx: int) -> void:
	_vignette_enabled = (idx == 0)


func _on_cfg_vignette_str(val: float) -> void:
	_vignette_strength = val


func _on_cfg_render_scale(val: float) -> void:
	_render_scale = val
	if xr_interface and is_instance_valid(xr_interface):
		xr_interface.render_target_size_multiplier = _render_scale


func _on_cfg_2h_smooth(idx: int) -> void:
	_two_hand_smooth_enabled = (idx == 0)


func _on_cfg_2h_smooth_spd(val: float) -> void:
	_two_hand_smooth_speed = val


func _on_cfg_walk_sway(idx: int) -> void:
	_disable_walk_sway = (idx == 1)


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
	# Recreate watch on the other wrist
	_destroy_watch_mesh()
	_create_watch_mesh()


func _on_cfg_gun_config(idx: int) -> void:
	_gun_config_enabled = (idx == 1)
	if not _gun_config_enabled:
		_adjust_mode = false
		_fg_adjust_mode = false
	print("[VR Mod] Gun config: ", "on" if _gun_config_enabled else "off")


func _on_cfg_laser_always_on(idx: int) -> void:
	_laser_always_on = (idx == 0)
	print("[VR Mod] Laser always on: ", _laser_always_on)


func _on_cfg_standing_mode(idx: int) -> void:
	_standing_mode = (idx == 1)
	if xr_interface and is_instance_valid(xr_interface):
		if _standing_mode:
			xr_interface.play_area_mode = XRInterface.XR_PLAY_AREA_ROOMSCALE
		else:
			xr_interface.play_area_mode = XRInterface.XR_PLAY_AREA_SITTING
	if not _standing_mode:
		if _physical_crouch_active:
			_inject_action("crouch", true)
			_inject_action("crouch", false)
		_physical_crouch_active = false
		_physical_crouch_resnap = 0
		_standing_height_ref = 0.0
	# Re-snap origin after a few frames so the new reference space has settled
	_standing_mode_resnap = 3
	print("[VR Mod] Tracking mode: ", "standing" if _standing_mode else "sitting")


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


func _watch_rot_basis() -> Basis:
	# Base orientation: -90 X makes the quad face upward (palm-up wrist position).
	# _watch_rot is a user offset applied first (in the un-tilted local space),
	# giving three distinct independent adjustment axes.
	var base = Basis(Vector3(1.0, 0.0, 0.0), deg_to_rad(-90.0))
	var offset = Basis.from_euler(Vector3(deg_to_rad(_watch_rot.x), deg_to_rad(_watch_rot.y), deg_to_rad(_watch_rot.z)))
	return base * offset


func _on_cfg_watch_glance(idx: int) -> void:
	_watch_glance_enabled = (idx == 1)

func _on_cfg_watch_angle(val: float) -> void:
	_watch_glance_angle = val

func _on_cfg_watch_fade(val: float) -> void:
	_watch_fade_speed = val

func _on_cfg_watch_size(val: float) -> void:
	_watch_size = val
	if _watch_mesh:
		(_watch_mesh.mesh as QuadMesh).size = Vector2(_watch_size, _watch_size)

func _on_cfg_watch_spread(val: float) -> void:
	_watch_spread = val
	if not _interface_open:
		_hud_spread_active = _watch_spread
		_apply_hud_spread()

func _on_cfg_watch_x(val: float) -> void:
	_watch_offset.x = val
	if _watch_mesh:
		_watch_mesh.position = _watch_offset

func _on_cfg_watch_y(val: float) -> void:
	_watch_offset.y = val
	if _watch_mesh:
		_watch_mesh.position = _watch_offset

func _on_cfg_watch_z(val: float) -> void:
	_watch_offset.z = val
	if _watch_mesh:
		_watch_mesh.position = _watch_offset

func _on_cfg_watch_rot_x(val: float) -> void:
	_watch_rot.x = val
	if _watch_mesh:
		_watch_mesh.basis = _watch_rot_basis()

func _on_cfg_watch_rot_y(val: float) -> void:
	_watch_rot.y = val
	if _watch_mesh:
		_watch_mesh.basis = _watch_rot_basis()

func _on_cfg_watch_rot_z(val: float) -> void:
	_watch_rot.z = val
	if _watch_mesh:
		_watch_mesh.basis = _watch_rot_basis()

func _on_cfg_hand_l_x(val: float) -> void:
	HAND_GLTF_OFFSET_LEFT.x = val
	if _hand_wrapper_left:
		_hand_wrapper_left.position = HAND_GLTF_OFFSET_LEFT

func _on_cfg_hand_l_y(val: float) -> void:
	HAND_GLTF_OFFSET_LEFT.y = val
	if _hand_wrapper_left:
		_hand_wrapper_left.position = HAND_GLTF_OFFSET_LEFT

func _on_cfg_hand_l_z(val: float) -> void:
	HAND_GLTF_OFFSET_LEFT.z = val
	if _hand_wrapper_left:
		_hand_wrapper_left.position = HAND_GLTF_OFFSET_LEFT

func _on_cfg_hand_l_rx(val: float) -> void:
	HAND_GLTF_ROTATION_LEFT.x = val
	if _hand_wrapper_left:
		_hand_wrapper_left.rotation_degrees = HAND_GLTF_ROTATION_LEFT

func _on_cfg_hand_l_ry(val: float) -> void:
	HAND_GLTF_ROTATION_LEFT.y = val
	if _hand_wrapper_left:
		_hand_wrapper_left.rotation_degrees = HAND_GLTF_ROTATION_LEFT

func _on_cfg_hand_l_rz(val: float) -> void:
	HAND_GLTF_ROTATION_LEFT.z = val
	if _hand_wrapper_left:
		_hand_wrapper_left.rotation_degrees = HAND_GLTF_ROTATION_LEFT

func _on_cfg_hand_r_x(val: float) -> void:
	HAND_GLTF_OFFSET_RIGHT.x = val
	if _hand_wrapper_right:
		_hand_wrapper_right.position = HAND_GLTF_OFFSET_RIGHT

func _on_cfg_hand_r_y(val: float) -> void:
	HAND_GLTF_OFFSET_RIGHT.y = val
	if _hand_wrapper_right:
		_hand_wrapper_right.position = HAND_GLTF_OFFSET_RIGHT

func _on_cfg_hand_r_z(val: float) -> void:
	HAND_GLTF_OFFSET_RIGHT.z = val
	if _hand_wrapper_right:
		_hand_wrapper_right.position = HAND_GLTF_OFFSET_RIGHT

func _on_cfg_hand_r_rx(val: float) -> void:
	HAND_GLTF_ROTATION_RIGHT.x = val
	if _hand_wrapper_right:
		_hand_wrapper_right.rotation_degrees = HAND_GLTF_ROTATION_RIGHT

func _on_cfg_hand_r_ry(val: float) -> void:
	HAND_GLTF_ROTATION_RIGHT.y = val
	if _hand_wrapper_right:
		_hand_wrapper_right.rotation_degrees = HAND_GLTF_ROTATION_RIGHT

func _on_cfg_hand_r_rz(val: float) -> void:
	HAND_GLTF_ROTATION_RIGHT.z = val
	if _hand_wrapper_right:
		_hand_wrapper_right.rotation_degrees = HAND_GLTF_ROTATION_RIGHT

func _on_cfg_sling_x(val: float) -> void:
	_sling_offset.x = val

func _on_cfg_sling_y(val: float) -> void:
	_sling_offset.y = val

func _on_cfg_sling_z(val: float) -> void:
	_sling_offset.z = val

func _on_cfg_sling_rx(val: float) -> void:
	_sling_rot_offset.x = val

func _on_cfg_sling_ry(val: float) -> void:
	_sling_rot_offset.y = val

func _on_cfg_sling_rz(val: float) -> void:
	_sling_rot_offset.z = val

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
			vitals.position.x = -960.0 * _hud_spread_active
		var medical = stats.get_node_or_null("Medical")
		if medical and medical is Control:
			medical.position.x = 960.0 * _hud_spread_active
	# Top-left info (Map/FPS) — anchored top-left, default pos=(32, 32)
	var info = hud_node.get_node_or_null("Info")
	if info and info is Control:
		# Move inward from left edge: at spread=1.0 → x=32, at spread=0.5 → x=~928 (toward center)
		var half_w = 1920.0  # half of 3840 HUD width
		var default_x = 32.0
		info.position.x = half_w - (half_w - default_x) * _hud_spread_active


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
		var dist = ray_origin.distance_to(hit_pos) - 0.01
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
	var tabs = _config_panel_vp.get_node_or_null("CfgRoot/CfgOuter/CfgTabs")
	if not tabs or not (tabs is TabContainer):
		return
	var active_tab = (tabs as TabContainer).get_current_tab_control()
	if active_tab and active_tab is ScrollContainer:
		(active_tab as ScrollContainer).scroll_vertical += int(amount)


# ── Save full config ────────────────────────────────────────────────────────

func _save_full_config() -> void:
	var config_path = _config_path
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
	data["xr"] = {"world_scale": world_scale, "render_scale": _render_scale}

	# Comfort
	var turn_type = "snap"
	if not use_snap_turn:
		turn_type = "smooth"
	data["comfort"] = {
		"turn_type": turn_type,
		"snap_turn_degrees": snap_turn_degrees,
		"smooth_turn_speed": smooth_turn_speed,
		"vignette_enabled": _vignette_enabled,
		"vignette_strength": _vignette_strength,
		"two_hand_smooth_enabled": _two_hand_smooth_enabled,
		"two_hand_smooth_speed": _two_hand_smooth_speed,
		"walk_sway_enabled": not _disable_walk_sway
	}

	# Controls
	data["controls"] = {
		"thumbstick_deadzone": thumbstick_deadzone,
		"dominant_hand": _config_dominant_hand,
		"standing_mode": _standing_mode,
		"gun_config_enabled": _gun_config_enabled,
		"laser_always_on": _laser_always_on
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

	# Wrist watch
	data["watch"] = {
		"size": _watch_size,
		"glance_enabled": _watch_glance_enabled,
		"glance_angle": _watch_glance_angle,
		"fade_speed": _watch_fade_speed,
		"spread": _watch_spread,
		"offset": {
			"x": snapped(_watch_offset.x, 0.001),
			"y": snapped(_watch_offset.y, 0.001),
			"z": snapped(_watch_offset.z, 0.001)
		},
		"rot": {
			"x": snapped(_watch_rot.x, 0.1),
			"y": snapped(_watch_rot.y, 0.1),
			"z": snapped(_watch_rot.z, 0.1)
		}
	}

	# Preserve weapon_offsets and foregrip local data so Save & Close never drops them
	var wo2 := {}
	for wname in _weapon_grip_offsets:
		var o2 := _weapon_grip_offsets[wname] as Vector3
		wo2[wname] = {
			"x": snapped(o2.x, 0.001),
			"y": snapped(o2.y, 0.001),
			"z": snapped(o2.z, 0.001),
			"rot": snapped(_weapon_grip_rotations.get(wname, 0.0), 0.1)
		}
	data["weapon_offsets"] = wo2
	var fgp2 := {}
	for wname in _weapon_fg_p_local:
		var p2: Vector3 = _weapon_fg_p_local[wname]
		fgp2[wname] = {"x": snapped(p2.x, 0.0001), "y": snapped(p2.y, 0.0001), "z": snapped(p2.z, 0.0001)}
	data["foregrip_p_local"] = fgp2
	var fgr2 := {}
	for wname in _weapon_fg_r_local:
		var b2: Basis = _weapon_fg_r_local[wname]
		var q2 := b2.get_rotation_quaternion()
		fgr2[wname] = {"x": snapped(q2.x, 0.0001), "y": snapped(q2.y, 0.0001), "z": snapped(q2.z, 0.0001), "w": snapped(q2.w, 0.0001)}
	data["foregrip_r_local"] = fgr2

	# Hand models
	data["hand_models"] = {
		"left": {
			"x": snapped(HAND_GLTF_OFFSET_LEFT.x, 0.001),
			"y": snapped(HAND_GLTF_OFFSET_LEFT.y, 0.001),
			"z": snapped(HAND_GLTF_OFFSET_LEFT.z, 0.001),
			"rot": {
				"x": snapped(HAND_GLTF_ROTATION_LEFT.x, 0.1),
				"y": snapped(HAND_GLTF_ROTATION_LEFT.y, 0.1),
				"z": snapped(HAND_GLTF_ROTATION_LEFT.z, 0.1)
			}
		},
		"right": {
			"x": snapped(HAND_GLTF_OFFSET_RIGHT.x, 0.001),
			"y": snapped(HAND_GLTF_OFFSET_RIGHT.y, 0.001),
			"z": snapped(HAND_GLTF_OFFSET_RIGHT.z, 0.001),
			"rot": {
				"x": snapped(HAND_GLTF_ROTATION_RIGHT.x, 0.1),
				"y": snapped(HAND_GLTF_ROTATION_RIGHT.y, 0.1),
				"z": snapped(HAND_GLTF_ROTATION_RIGHT.z, 0.1)
			}
		}
	}

	# Primary weapon sling
	data["sling"] = {
		"x": snapped(_sling_offset.x, 0.001),
		"y": snapped(_sling_offset.y, 0.001),
		"z": snapped(_sling_offset.z, 0.001),
		"rot": {
			"x": snapped(_sling_rot_offset.x, 0.1),
			"y": snapped(_sling_rot_offset.y, 0.1),
			"z": snapped(_sling_rot_offset.z, 0.1)
		}
	}

	var out = FileAccess.open(config_path, FileAccess.WRITE)
	if out:
		out.store_string(JSON.stringify(data, "\t"))
		out.close()
		print("[VR Mod] Full config saved to: ", config_path)


# ── Weapon tree debug dump (F10) ──────────────────────────────────────────

func _dump_weapon_tree() -> void:
	var log_path = _log_path
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
			if prop["usage"] & 4096:  # PROPERTY_USAGE_SCRIPT_VARIABLE
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
				if rprop["usage"] & 4096:  # PROPERTY_USAGE_SCRIPT_VARIABLE
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


# ── Ray target debug dump (F12) ────────────────────────────────────────────

func _dump_ray_target() -> void:
	var log_path = _log_path
	var f = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if not f:
		return
	f.seek_end(0)
	f.store_line("")
	f.store_line("=== RAY TARGET DUMP (F12) " + Time.get_datetime_string_from_system() + " ===")
	# In decor mode, also dump the game's Interactor raycast
	if _decor_mode and game_camera and is_instance_valid(game_camera):
		var interactor = game_camera.get_node_or_null("Interactor")
		f.store_line("  Game Interactor (decor mode):")
		if interactor is RayCast3D and interactor.is_colliding():
			var c = interactor.get_collider()
			if c:
				f.store_line("    Class: " + c.get_class())
				f.store_line("    Path: " + str(c.get_path()))
				f.store_line("    Script: " + (str(c.get_script().resource_path) if c.get_script() else "none"))
				f.store_line("    Groups: " + str(c.get_groups()))
				var p = c.get_parent()
				var depth := 0
				while p and depth < 6:
					var pi = p.name + " (" + p.get_class() + ")" + (" script=" + str(p.get_script().resource_path) if p.get_script() else "") + " groups=" + str(p.get_groups())
					f.store_line("    -> " + pi)
					if p.name == "Map" or p == get_tree().root:
						break
					p = p.get_parent()
					depth += 1
		else:
			f.store_line("    (not colliding)")
	for ray_info in [["Right GrabRay", _grab_ray_right], ["Left GrabRay", _grab_ray_left]]:
		var label: String = ray_info[0]
		var ray: RayCast3D = ray_info[1]
		f.store_line("  " + label + ":")
		if not ray or not ray.is_colliding():
			f.store_line("    (not colliding)")
			continue
		var c = ray.get_collider()
		if not c:
			f.store_line("    (collider null)")
			continue
		f.store_line("    Class: " + c.get_class())
		f.store_line("    Path: " + str(c.get_path()))
		f.store_line("    Script: " + (str(c.get_script().resource_path) if c.get_script() else "none"))
		if c is CollisionObject3D:
			f.store_line("    collision_layer: " + str(c.collision_layer) + " (bin: " + _bits_str(c.collision_layer) + ")")
			f.store_line("    collision_mask: " + str(c.collision_mask) + " (bin: " + _bits_str(c.collision_mask) + ")")
		f.store_line("    Groups: " + str(c.get_groups()))
		f.store_line("    Visible: " + str(c.visible if c is CanvasItem or c is Node3D else "n/a"))
		# Walk parents up to /root/Map
		var parent_chain := ""
		var p = c.get_parent()
		var depth := 0
		while p and depth < 10:
			var pscript = str(p.get_script().resource_path) if p.get_script() else ""
			var pinfo = p.name + " (" + p.get_class() + ")"
			if pscript != "":
				pinfo += " script=" + pscript
			if p is CollisionObject3D:
				pinfo += " layer=" + str(p.collision_layer)
			parent_chain += "    -> " + pinfo + "\n"
			if p.name == "Map" or p == get_tree().root:
				break
			p = p.get_parent()
			depth += 1
		f.store_line("    Parent chain:")
		f.store_line(parent_chain)
	f.close()
	print("[VR Mod] Ray target dumped to log (F12)")

func _bits_str(val: int) -> String:
	var s := ""
	for i in range(20):
		if val & (1 << i):
			s += str(i + 1) + ","
	return s.trim_suffix(",") if s != "" else "none"


# ── HUD tree debug dump (F9) ───────────────────────────────────────────────

func _dump_hud_tree() -> void:
	var log_path = _log_path
	var f = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if not f:
		f = FileAccess.open(log_path, FileAccess.WRITE)
	if not f:
		print("[VR Mod] Cannot open debug log for HUD dump")
		return
	f.seek_end(0)
	f.store_line("")
	f.store_line("=== HUD TREE DUMP (" + str(Time.get_datetime_string_from_system()) + ") ===")
	f.store_line("interface_open=" + str(_interface_open) + " esc_active=" + str(_esc_menu_active) + " paused=" + str(get_tree().paused))

	# Dump ALL Map/Core/UI children with class and visibility for loot pool diagnosis
	var ui_node = get_tree().root.get_node_or_null("Map/Core/UI")
	if not ui_node:
		f.store_line("  Map/Core/UI not found!")
		f.close()
		return
	f.store_line("--- Map/Core/UI children ---")
	for c in ui_node.get_children():
		var vis_str = ""
		if c is CanvasItem:
			vis_str = " visible=" + str((c as CanvasItem).visible) + " vis_in_tree=" + str((c as CanvasItem).is_visible_in_tree())
		f.store_line("  " + c.name + " (" + c.get_class() + ")" + vis_str)
		for gc in c.get_children():
			var gvis_str = ""
			if gc is CanvasItem:
				gvis_str = " visible=" + str((gc as CanvasItem).visible) + " vis_in_tree=" + str((gc as CanvasItem).is_visible_in_tree())
			f.store_line("    " + gc.name + " (" + gc.get_class() + ")" + gvis_str)
			for ggc in gc.get_children():
				var ggvis_str = ""
				if ggc is CanvasItem:
					ggvis_str = " visible=" + str((ggc as CanvasItem).visible) + " vis_in_tree=" + str((ggc as CanvasItem).is_visible_in_tree())
				f.store_line("      " + ggc.name + " (" + ggc.get_class() + ")" + ggvis_str)
	f.store_line("--- Map/Core siblings ---")
	var core_node = get_tree().root.get_node_or_null("Map/Core")
	if core_node:
		for c in core_node.get_children():
			var vis_str = ""
			if c is CanvasItem:
				vis_str = " visible=" + str((c as CanvasItem).visible) + " vis_in_tree=" + str((c as CanvasItem).is_visible_in_tree())
			f.store_line("  " + c.name + " (" + c.get_class() + ")" + vis_str)

	var hud_node = ui_node.get_node_or_null("HUD")
	if not hud_node:
		f.store_line("  Map/Core/UI/HUD not found!")
		f.close()
		return

	f.store_line("--- HUD subtree ---")
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
	var log_path = _log_path
	var f = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if not f:
		f = FileAccess.open(log_path, FileAccess.WRITE)
	if not f:
		print("[VR Mod] Cannot open debug log for NVG dump")
		return
	f.seek_end(0)
	f.store_line("")
	f.store_line("=== NVG & ENVIRONMENT DUMP (" + str(Time.get_datetime_string_from_system()) + ") ===")

	# ── -1. Character/player node search ──
	f.store_line("")
	f.store_line("-- Core subtree: all scripted nodes + CharacterBody3D --")
	var core_node = get_tree().root.get_node_or_null("Map/Core")
	if core_node:
		var stack: Array = core_node.get_children()
		while stack.size() > 0:
			var n: Node = stack.pop_front()
			for c in n.get_children():
				stack.push_back(c)
			var ns = n.get_script()
			var is_char = n.get_class() == "CharacterBody3D"
			if ns or is_char:
				f.store_line("  " + str(n.get_path()) + " (" + n.get_class() + ")" + (" [script=" + str(ns.resource_path) + "]" if ns else ""))
				if ns:
					for prop in n.get_property_list():
						if prop["usage"] & 4096:
							f.store_line("    " + prop["name"] + " = " + str(n.get(prop["name"])))
	else:
		f.store_line("  /root/Map/Core not found")

	# ── 0. Decor mode state ──
	f.store_line("")
	f.store_line("-- Decor Mode --")
	f.store_line("  _decor_mode=" + str(_decor_mode))
	f.store_line("  _decor_scroll_mode=" + str(_decor_scroll_mode) + " (0=distance, 1=rotation)")
	f.store_line("  _left_grip_held=" + str(_left_grip_held) + " _right_grip_held=" + str(_right_grip_held))
	if _decor_mode and game_camera and is_instance_valid(game_camera):
		# Dump direct children of game_camera that might be decor-related
		f.store_line("  game_camera children:")
		for c in game_camera.get_children():
			var vis_str = ""
			if c is Node3D:
				vis_str = " vis=" + str(c.visible)
			elif c is CanvasItem:
				vis_str = " vis=" + str(c.visible)
			f.store_line("    " + c.name + " (" + c.get_class() + ")" + vis_str)
		# Check for Placer node
		var placer = game_camera.get_node_or_null("Placer")
		if placer:
			f.store_line("  Placer node found! Children:")
			for c in placer.get_children():
				var vis_str2 = ""
				if c is Node3D:
					vis_str2 = " vis=" + str(c.visible)
				f.store_line("    " + c.name + " (" + c.get_class() + ")" + vis_str2)
				if c.get_script():
					f.store_line("      script=" + str(c.get_script().resource_path))

	# ── 0b. Placer script properties + Map/Hint ghost node ──
	if _decor_mode:
		var placer = game_camera.get_node_or_null("Placer") if game_camera else null
		if placer and placer.get_script():
			f.store_line("  Placer script: " + str(placer.get_script().resource_path))
			f.store_line("  Placer PROPS:")
			var prop_list = placer.get_property_list()
			for prop in prop_list:
				# 4096 = PROPERTY_USAGE_SCRIPT_VARIABLE
				if prop["usage"] & 4096:
					var val = placer.get(prop["name"])
					f.store_line("    " + prop["name"] + " = " + str(val))
		var map_node = get_tree().root.get_node_or_null("Map")
		if map_node:
			f.store_line("  /root/Map/ direct children:")
			for c in map_node.get_children():
				var info = "    " + c.name + " (" + c.get_class() + ")"
				if c is Node3D:
					info += " vis=" + str(c.visible)
				if c.get_script():
					info += " script=" + str(c.get_script().resource_path)
				f.store_line(info)

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
			if prop["usage"] & 4096:  # PROPERTY_USAGE_SCRIPT_VARIABLE
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
