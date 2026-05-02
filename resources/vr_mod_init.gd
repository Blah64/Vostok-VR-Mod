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
var _verbose_log := false  # set true to enable high-frequency debug logging

# Subsystem modules. preload() fails the parse if the path is missing, so the
# corresponding file MUST be in the VMZ (see build.bat manifest). Instances
# are constructed via the _ensure_*() getters below.
const ConfigIO = preload("res://resources/vr_mod/config_io.gd")
var _config_io = null

const Diagnostics = preload("res://resources/vr_mod/diagnostics.gd")
var _diagnostics = null

const ConfigUI = preload("res://resources/vr_mod/config_ui.gd")
var _config_ui = null

const Holster = preload("res://resources/vr_mod/holster.gd")
var _holster = null

const Hands = preload("res://resources/vr_mod/hands.gd")
var _hands = null

const HudWatch = preload("res://resources/vr_mod/hud_watch.gd")
var _hud_watch = null

const ScopePip = preload("res://resources/vr_mod/scope_pip.gd")
var _scope_pip = null

const Nvg = preload("res://resources/vr_mod/nvg.gd")
var _nvg = null

const Decor = preload("res://resources/vr_mod/decor.gd")
var _decor = null

const Grenade = preload("res://resources/vr_mod/grenade.gd")
var _grenade = null

const Grab = preload("res://resources/vr_mod/grab.gd")
var _grab = null

const WeaponSync = preload("res://resources/vr_mod/weapon_sync.gd")
var _weapon_sync = null

const XrRig = preload("res://resources/vr_mod/xr_rig.gd")
var _xr_rig = null

const InputDispatch = preload("res://resources/vr_mod/input.gd")
var _input = null

func _ensure_config_io():
	if not _config_io:
		_config_io = ConfigIO.new(_config_path, Callable(self, "_log_str"))
	return _config_io

func _ensure_diagnostics():
	if not _diagnostics:
		_diagnostics = Diagnostics.new(self)
	return _diagnostics

func _ensure_config_ui():
	if not _config_ui:
		_config_ui = ConfigUI.new(self)
	return _config_ui

func _ensure_holster():
	if not _holster:
		_holster = Holster.new(get_tree(), {
			"get_holster_state": Callable(self, "_holster_port_get_state"),
			"set_holster_state": Callable(self, "_holster_port_set_state"),
			"get_weapon_hand": Callable(self, "_holster_port_get_weapon_hand"),
			"set_weapon_hand": Callable(self, "_holster_port_set_weapon_hand"),
			"get_weapon_slot": Callable(self, "_holster_port_get_weapon_slot"),
			"set_weapon_slot": Callable(self, "_holster_port_set_weapon_slot"),
			"set_transition_state": Callable(self, "_holster_port_set_transition_state"),
			"get_holster_state_unarmed": Callable(self, "_holster_port_get_state_unarmed"),
			"get_holster_state_drawn": Callable(self, "_holster_port_get_state_drawn"),
			"get_holster_state_lowered": Callable(self, "_holster_port_get_state_lowered"),
			"get_holster_state_sling": Callable(self, "_holster_port_get_state_sling"),
			"get_holster_zones": Callable(self, "_holster_port_get_zones"),
			"get_holster_offsets": Callable(self, "_holster_port_get_offsets"),
			"get_holster_zones_mirrored": Callable(self, "_holster_port_get_zones_mirrored"),
			"get_holster_zone_radius": Callable(self, "_holster_port_get_zone_radius"),
			"get_zone_cache": Callable(self, "_holster_port_get_zone_cache"),
			"set_zone_cache_frame": Callable(self, "_holster_port_set_zone_cache_frame"),
			"get_zone_cache_frame": Callable(self, "_holster_port_get_zone_cache_frame"),
			"get_holo_nodes": Callable(self, "_holster_port_get_holo_nodes"),
			"get_holos_enabled": Callable(self, "_holster_port_get_holos_enabled"),
			"get_holster_cooldown": Callable(self, "_holster_port_get_cooldown"),
			"set_holster_cooldown": Callable(self, "_holster_port_set_cooldown"),
			"get_pending_holster_key": Callable(self, "_holster_port_get_pending_key"),
			"set_pending_holster_key": Callable(self, "_holster_port_set_pending_key"),
			"set_weapon_raise_timer": Callable(self, "_holster_port_set_weapon_raise_timer"),
			"set_scroll_cooldown": Callable(self, "_holster_port_set_scroll_cooldown"),
			"get_hand_in_zone": Callable(self, "_holster_port_get_hand_in_zone"),
			"get_camera": Callable(self, "_holster_port_get_camera"),
			"get_controller": Callable(self, "_get_controller"),
			"get_owner_node": Callable(self, "_holster_port_get_owner"),
			"get_vrframe": Callable(self, "_holster_port_get_vrframe"),
			"get_holster_key_delay": Callable(self, "_holster_port_get_key_delay"),
			"get_holster_key_release": Callable(self, "_holster_port_get_key_release"),
			"inject_key": Callable(self, "_inject_key"),
			"inject_action": Callable(self, "_inject_action"),
			"inject_mouse": Callable(self, "_inject_mouse_button"),
			"reset_for_draw": Callable(self, "_holster_port_reset_for_draw"),
			"reset_for_lower": Callable(self, "_holster_port_reset_for_lower"),
			"reset_for_holster": Callable(self, "_holster_port_reset_for_holster"),
			"exit_rail_mode": Callable(self, "_holster_port_exit_rail_mode"),
			"cleanup_scope": Callable(self, "_cleanup_scope"),
			"clear_grenade_state": Callable(self, "_clear_grenade_state"),
			"patch_resume_state": Callable(self, "_patch_resume_state"),
			"reset_scope_reticle_cache": Callable(self, "_holster_port_reset_scope_reticle_cache"),
			"grab_in_bag_zone_get": Callable(self, "_holster_port_grab_in_bag_zone_get"),
			"grab_in_bag_zone_set": Callable(self, "_holster_port_grab_in_bag_zone_set"),
			"is_in_bag_zone": Callable(self, "_is_in_bag_zone"),
			"is_in_nvg_zone": Callable(self, "_is_in_nvg_zone"),
			"get_grabbed_object": Callable(self, "_grab_port_get_grabbed_object"),
			"get_grab_hand": Callable(self, "_grab_port_get_grab_hand"),
			"nvg_get_hand_in_zone": Callable(self, "_holster_port_nvg_get_hand_in_zone"),
			"log": Callable(self, "_log_str"),
		})
	return _holster


# Ports for holster.gd
func _holster_port_get_state() -> int:
	return _holster_state

func _holster_port_set_state(value: int) -> void:
	_holster_state = value

func _holster_port_get_weapon_hand() -> String:
	return _weapon_hand

func _holster_port_set_weapon_hand(value: String) -> void:
	_weapon_hand = value

func _holster_port_get_weapon_slot() -> int:
	return _weapon_slot

func _holster_port_set_weapon_slot(value: int) -> void:
	_weapon_slot = value

func _holster_port_set_transition_state(slot: int, hand: String) -> void:
	_transition_slot = slot
	_transition_hand = hand

func _holster_port_get_state_unarmed() -> int:
	return HolsterState.UNARMED

func _holster_port_get_state_drawn() -> int:
	return HolsterState.DRAWN

func _holster_port_get_state_lowered() -> int:
	return HolsterState.LOWERED

func _holster_port_get_state_sling() -> int:
	return HolsterState.SLING

func _holster_port_get_zones() -> Dictionary:
	return HOLSTER_ZONES

func _holster_port_get_offsets() -> Dictionary:
	return _holster_offsets

func _holster_port_get_zones_mirrored() -> bool:
	return _holster_zones_mirrored

func _holster_port_get_zone_radius() -> float:
	return _holster_zone_radius

func _holster_port_get_zone_cache() -> Dictionary:
	return _holster_zone_world_cache

func _holster_port_set_zone_cache_frame(frame: int) -> void:
	_holster_zone_cache_frame = frame

func _holster_port_get_zone_cache_frame() -> int:
	return _holster_zone_cache_frame

func _holster_port_get_holo_nodes() -> Dictionary:
	return _holster_holo_nodes

func _holster_port_get_holos_enabled() -> bool:
	return _holster_holos_enabled

func _holster_port_get_cooldown() -> float:
	return _holster_cooldown

func _holster_port_set_cooldown(value: float) -> void:
	_holster_cooldown = value

func _holster_port_get_pending_key() -> int:
	return _pending_holster_key

func _holster_port_set_pending_key(value: int) -> void:
	_pending_holster_key = value

func _holster_port_set_weapon_raise_timer(value: float) -> void:
	_weapon_raise_timer = value

func _holster_port_set_scroll_cooldown(value: float) -> void:
	_scroll_cooldown = value

func _holster_port_get_hand_in_zone() -> Dictionary:
	return _hand_in_zone

func _holster_port_get_camera() -> XRCamera3D:
	return xr_camera

func _holster_port_get_owner() -> Node:
	return self

func _holster_port_get_vrframe() -> Dictionary:
	return _refresh_vrframe()

func _holster_port_get_key_delay() -> float:
	return HOLSTER_KEY_DELAY_SEC

func _holster_port_get_key_release() -> float:
	return HOLSTER_KEY_RELEASE_SEC

func _holster_port_exit_rail_mode() -> void:
	if _rail_mode:
		_exit_rail_mode()

func _holster_port_reset_scope_reticle_cache() -> void:
	_ensure_scope_pip().fixed_reticle_instances.clear()

func _holster_port_grab_in_bag_zone_get() -> bool:
	return _ensure_grab().in_bag_zone

func _holster_port_grab_in_bag_zone_set(value: bool) -> void:
	_ensure_grab().in_bag_zone = value

func _holster_port_nvg_get_hand_in_zone() -> Dictionary:
	return _ensure_nvg().hand_in_zone

# Three reset variants — called from holster transitions to clear cross-system
# fields that logically belong to weapon_sync but must be flushed in lockstep
# with the holster transition. Kept on the autoload because the fields they
# touch (recoil, walk-sway, pump gesture, adjust modes, support grip) are
# read by many other places.
func _holster_port_reset_for_draw() -> void:
	# DRAW: clear weapon-load detection + recoil + walk-sway state. Other
	# fields (current_weapon_name, subtype, support grip, adjust modes) are
	# preserved so the new weapon picks them up cleanly.
	_weapon_loaded = false
	_weapon_is_long = false
	_recoil_rest_xform = Transform3D.IDENTITY
	_recoil_rest_inv = Transform3D.IDENTITY
	_prev_recoil_mag = 0.0
	_fire_haptic_cooldown = 0.0
	_walk_sway_captured = false
	_walk_sway_logged = false
	_rest_capture_pending = false
	_walk_sway_capture_delay = 0.0

func _holster_port_reset_for_lower() -> void:
	# LOWER / SLING: weapon stays equipped; clear grip/adjust state.
	_adjust_mode = false
	_fg_adjust_mode = false
	_support_grip_held = false

func _holster_port_reset_for_holster() -> void:
	# HOLSTER: weapon fully unequipped; clear everything except cooldown.
	_adjust_mode = false
	_fg_adjust_mode = false
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
	_recoil_rest_inv = Transform3D.IDENTITY
	_prev_recoil_mag = 0.0
	_fire_haptic_cooldown = 0.0
	_walk_sway_captured = false
	_walk_sway_logged = false
	_rest_capture_pending = false
	_walk_sway_capture_delay = 0.0
	_support_grip_held = false

func _ensure_hands():
	if not _hands:
		_hands = Hands.new(get_tree(), {
			"get_assets_base": Callable(self, "_hands_port_get_assets_base"),
			"get_left_controller": Callable(self, "_hands_port_get_left_controller"),
			"get_right_controller": Callable(self, "_hands_port_get_right_controller"),
			"get_controller": Callable(self, "_get_controller"),
			"get_game_camera": Callable(self, "_hands_port_get_game_camera"),
			"get_holster_state": Callable(self, "_hands_port_get_holster_state"),
			"get_state_unarmed": Callable(self, "_hands_port_get_state_unarmed"),
			"get_state_sling": Callable(self, "_hands_port_get_state_sling"),
			"get_state_lowered": Callable(self, "_hands_port_get_state_lowered"),
			"get_decor_mode": Callable(self, "_hands_port_get_decor_mode"),
			"get_grabbed_object": Callable(self, "_grab_port_get_grabbed_object"),
			"get_dominant_hand": Callable(self, "_hands_port_get_dominant_hand"),
			"get_menu_open": Callable(self, "_hands_port_get_menu_open"),
			"get_config_screen_open": Callable(self, "_hands_port_get_config_screen_open"),
			"get_laser_mesh": Callable(self, "_hands_port_get_laser_mesh"),
			"get_laser_always_on": Callable(self, "_hands_port_get_laser_always_on"),
			"get_hover_label": Callable(self, "_hands_port_get_hover_label"),
			"get_grab_ray": Callable(self, "_grab_port_get_ray"),
			"is_transition_node": Callable(self, "_is_transition_node"),
			"find_interactable_name": Callable(self, "_find_interactable_display_name"),
			"format_node_name": Callable(self, "_format_node_name"),
			"find_node_by_class": Callable(self, "_find_node_by_class"),
			"get_hand_offset_left": Callable(self, "_hands_port_get_offset_left"),
			"get_hand_offset_right": Callable(self, "_hands_port_get_offset_right"),
			"get_hand_rot_left": Callable(self, "_hands_port_get_rot_left"),
			"get_hand_rot_right": Callable(self, "_hands_port_get_rot_right"),
			"get_curl_axis_thumb": Callable(self, "_hands_port_get_curl_axis_thumb"),
			"get_curl_axis_finger": Callable(self, "_hands_port_get_curl_axis_finger"),
			"get_finger_max_curl": Callable(self, "_hands_port_get_finger_max_curl"),
			"get_thumb_max_curl": Callable(self, "_hands_port_get_thumb_max_curl"),
			"get_curl_smooth_speed": Callable(self, "_hands_port_get_curl_smooth_speed"),
			"get_finger_joint_weight": Callable(self, "_hands_port_get_finger_joint_weight"),
			"get_hand_skel": Callable(self, "_hands_port_get_skel"),
			"get_hand_curl": Callable(self, "_hands_port_get_curl"),
			"get_hand_fingers": Callable(self, "_hands_port_get_fingers"),
			"get_hand_bone_rest": Callable(self, "_hands_port_get_bone_rest"),
			"get_hand_wrapper": Callable(self, "_hands_port_get_wrapper"),
			"set_hand_wrapper": Callable(self, "_hands_port_set_wrapper"),
			"set_hand_skel": Callable(self, "_hands_port_set_skel"),
			"set_hand_fingers": Callable(self, "_hands_port_set_fingers"),
			"set_hand_bone_rest": Callable(self, "_hands_port_set_bone_rest"),
			"get_hand_tex": Callable(self, "_hands_port_get_tex"),
			"set_hand_tex": Callable(self, "_hands_port_set_tex"),
			"append_load_error": Callable(self, "_hands_port_append_load_error"),
			"log": Callable(self, "_log_str"),
		})
	return _hands


# Ports for hands.gd
func _hands_port_get_assets_base() -> String:
	return _assets_base

func _hands_port_get_left_controller() -> XRController3D:
	return left_controller

func _hands_port_get_right_controller() -> XRController3D:
	return right_controller

func _hands_port_get_game_camera() -> Camera3D:
	return game_camera

func _hands_port_get_holster_state() -> int:
	return _holster_state

func _hands_port_get_state_unarmed() -> int:
	return HolsterState.UNARMED

func _hands_port_get_state_sling() -> int:
	return HolsterState.SLING

func _hands_port_get_state_lowered() -> int:
	return HolsterState.LOWERED

func _hands_port_get_decor_mode() -> bool:
	return _decor_mode

func _hands_port_get_dominant_hand() -> String:
	return _config_dominant_hand

func _hands_port_get_menu_open() -> bool:
	return _menu_open

func _hands_port_get_config_screen_open() -> bool:
	return _config_screen_open

func _hands_port_get_laser_mesh() -> MeshInstance3D:
	return _laser_mesh

func _hands_port_get_laser_always_on() -> bool:
	return _laser_always_on

func _hands_port_get_hover_label() -> Label3D:
	return _hover_label

func _hands_port_get_offset_left() -> Vector3:
	return HAND_GLTF_OFFSET_LEFT

func _hands_port_get_offset_right() -> Vector3:
	return HAND_GLTF_OFFSET_RIGHT

func _hands_port_get_rot_left() -> Vector3:
	return HAND_GLTF_ROTATION_LEFT

func _hands_port_get_rot_right() -> Vector3:
	return HAND_GLTF_ROTATION_RIGHT

func _hands_port_get_curl_axis_thumb() -> Vector3:
	return HAND_CURL_AXIS_THUMB

func _hands_port_get_curl_axis_finger() -> Vector3:
	return HAND_CURL_AXIS_FINGER

func _hands_port_get_finger_max_curl() -> float:
	return HAND_FINGER_MAX_CURL

func _hands_port_get_thumb_max_curl() -> float:
	return HAND_THUMB_MAX_CURL

func _hands_port_get_curl_smooth_speed() -> float:
	return HAND_CURL_SMOOTH_SPEED

func _hands_port_get_finger_joint_weight() -> Array:
	return HAND_FINGER_JOINT_WEIGHT

func _hands_port_get_skel(hand: String) -> Skeleton3D:
	return _hand_skel_left if hand == "left" else _hand_skel_right

func _hands_port_get_curl(hand: String) -> Dictionary:
	return _hand_curl_left if hand == "left" else _hand_curl_right

func _hands_port_get_fingers(hand: String) -> Dictionary:
	return _hand_fingers_left if hand == "left" else _hand_fingers_right

func _hands_port_get_bone_rest(hand: String) -> Dictionary:
	return _hand_bone_rest_left if hand == "left" else _hand_bone_rest_right

func _hands_port_get_wrapper(hand: String) -> Node3D:
	return _hand_wrapper_left if hand == "left" else _hand_wrapper_right

func _hands_port_set_wrapper(hand: String, node: Node3D) -> void:
	if hand == "left":
		_hand_wrapper_left = node
	else:
		_hand_wrapper_right = node

func _hands_port_set_skel(hand: String, skel: Skeleton3D) -> void:
	if hand == "left":
		_hand_skel_left = skel
	else:
		_hand_skel_right = skel

func _hands_port_set_fingers(hand: String, dict: Dictionary) -> void:
	if hand == "left":
		_hand_fingers_left = dict
	else:
		_hand_fingers_right = dict

func _hands_port_set_bone_rest(hand: String, dict: Dictionary) -> void:
	if hand == "left":
		_hand_bone_rest_left = dict
	else:
		_hand_bone_rest_right = dict

func _hands_port_get_tex() -> ImageTexture:
	return _hand_tex

func _hands_port_set_tex(tex: ImageTexture) -> void:
	_hand_tex = tex

func _hands_port_append_load_error(msg: String) -> void:
	_hand_load_errors.append(msg)

func _ensure_hud_watch():
	if not _hud_watch:
		_hud_watch = HudWatch.new(get_tree(), {
			# Scene refs
			"get_owner_node": Callable(self, "_hud_port_get_owner"),
			"get_main_viewport": Callable(self, "_hud_port_get_main_viewport"),
			"get_window": Callable(self, "_hud_port_get_window"),
			"get_camera": Callable(self, "_hud_port_get_camera"),
			"get_controller": Callable(self, "_get_controller"),
			"get_hud_viewport": Callable(self, "_hud_port_get_hud_viewport"),
			"set_hud_viewport": Callable(self, "_hud_port_set_hud_viewport"),
			"get_hud_mesh": Callable(self, "_hud_port_get_hud_mesh"),
			"set_hud_mesh": Callable(self, "_hud_port_set_hud_mesh"),
			"get_watch_mesh": Callable(self, "_hud_port_get_watch_mesh"),
			"set_watch_mesh": Callable(self, "_hud_port_set_watch_mesh"),
			"get_laser_mesh": Callable(self, "_hud_port_get_laser_mesh"),
			"get_ammo_panel_vp": Callable(self, "_hud_port_get_ammo_panel_vp"),
			"set_ammo_panel_vp": Callable(self, "_hud_port_set_ammo_panel_vp"),
			"get_ammo_panel_mesh": Callable(self, "_hud_port_get_ammo_panel_mesh"),
			"set_ammo_panel_mesh": Callable(self, "_hud_port_set_ammo_panel_mesh"),
			# Per-frame state
			"get_hud_installed": Callable(self, "_hud_port_get_hud_installed"),
			"set_hud_installed": Callable(self, "_hud_port_set_hud_installed"),
			"get_frames_waited": Callable(self, "_hud_port_get_frames_waited"),
			"get_in_menu_mode": Callable(self, "_hud_port_get_in_menu_mode"),
			"get_prev_interface_open": Callable(self, "_hud_port_get_prev_interface_open"),
			"set_prev_interface_open": Callable(self, "_hud_port_set_prev_interface_open"),
			"get_interface_open": Callable(self, "_hud_port_get_interface_open"),
			"set_interface_open": Callable(self, "_hud_port_set_interface_open"),
			"get_esc_menu_active": Callable(self, "_hud_port_get_esc_menu_active"),
			"set_esc_menu_active": Callable(self, "_hud_port_set_esc_menu_active"),
			"get_menu_open": Callable(self, "_hud_port_get_menu_open"),
			"set_menu_open": Callable(self, "_hud_port_set_menu_open"),
			"get_menu_ctrl_held": Callable(self, "_hud_port_get_menu_ctrl_held"),
			"set_menu_ctrl_held": Callable(self, "_hud_port_set_menu_ctrl_held"),
			"get_config_screen_open": Callable(self, "_hud_port_get_config_screen_open"),
			"get_support_trigger_pending": Callable(self, "_hud_port_get_support_trigger_pending"),
			"set_support_trigger_pending": Callable(self, "_hud_port_set_support_trigger_pending"),
			"get_support_trigger_press_time": Callable(self, "_hud_port_get_support_trigger_press_time"),
			"get_ammo_check_timer": Callable(self, "_hud_port_get_ammo_check_timer"),
			"set_ammo_check_timer": Callable(self, "_hud_port_set_ammo_check_timer"),
			"get_ammo_read_delay": Callable(self, "_hud_port_get_ammo_read_delay"),
			"set_ammo_read_delay": Callable(self, "_hud_port_set_ammo_read_delay"),
			"get_laser_diag_logged": Callable(self, "_hud_port_get_laser_diag_logged"),
			"set_laser_diag_logged": Callable(self, "_hud_port_set_laser_diag_logged"),
			"get_laser_locked_pos": Callable(self, "_hud_port_get_laser_locked_pos"),
			"set_laser_locked_pos": Callable(self, "_hud_port_set_laser_locked_pos"),
			"set_laser_screen_pos": Callable(self, "_hud_port_set_laser_screen_pos"),
			"get_hud_yaw": Callable(self, "_hud_port_get_hud_yaw"),
			"set_hud_yaw": Callable(self, "_hud_port_set_hud_yaw"),
			# Tunables
			"get_hud_smooth_follow": Callable(self, "_hud_port_get_hud_smooth_follow"),
			"get_hud_smooth_speed": Callable(self, "_hud_port_get_hud_smooth_speed"),
			"get_hud_lr_offset": Callable(self, "_hud_port_get_hud_lr_offset"),
			"get_hud_height_offset": Callable(self, "_hud_port_get_hud_height_offset"),
			"get_hud_distance": Callable(self, "_hud_port_get_hud_distance"),
			"get_menu_distance": Callable(self, "_hud_port_get_menu_distance"),
			"get_menu_lr_offset": Callable(self, "_hud_port_get_menu_lr_offset"),
			"get_menu_width": Callable(self, "_hud_port_get_menu_width"),
			"get_menu_laser_uv_x": Callable(self, "_hud_port_get_menu_laser_uv_x"),
			"get_menu_laser_uv_y": Callable(self, "_hud_port_get_menu_laser_uv_y"),
			"get_hud_width": Callable(self, "_hud_port_get_hud_width"),
			"get_hud_spread": Callable(self, "_hud_port_get_hud_spread"),
			"set_hud_spread_active": Callable(self, "_hud_port_set_hud_spread_active"),
			"get_watch_spread": Callable(self, "_hud_port_get_watch_spread"),
			"get_watch_size": Callable(self, "_hud_port_get_watch_size"),
			"get_watch_offset": Callable(self, "_hud_port_get_watch_offset"),
			"get_watch_glance_enabled": Callable(self, "_hud_port_get_watch_glance_enabled"),
			"get_watch_glance_angle": Callable(self, "_hud_port_get_watch_glance_angle"),
			"get_watch_fade_speed": Callable(self, "_hud_port_get_watch_fade_speed"),
			"get_dominant_hand": Callable(self, "_hud_port_get_dominant_hand"),
			"get_support_hand": Callable(self, "_get_support_hand"),
			"get_weapon_hand": Callable(self, "_hud_port_get_weapon_hand"),
			# Constants
			"get_hud_setup_delay": Callable(self, "_hud_port_get_setup_delay"),
			"get_watch_crop_shader": Callable(self, "_hud_port_get_watch_crop_shader"),
			# Side effects
			"inject_key": Callable(self, "_inject_key"),
			"apply_hud_spread": Callable(self, "_apply_hud_spread"),
			"setup_nvg_overlay": Callable(self, "_setup_nvg_overlay"),
			"watch_rot_basis": Callable(self, "_watch_rot_basis"),
			"esc_clear_hover": Callable(self, "_esc_clear_hover"),
			"update_esc_hover": Callable(self, "_update_esc_hover"),
			"log": Callable(self, "_log_str"),
		})
	return _hud_watch


# Ports for hud_watch.gd
func _hud_port_get_owner() -> Node: return self
func _hud_port_get_main_viewport() -> Viewport: return get_viewport()
func _hud_port_get_window() -> Window: return get_window()
func _hud_port_get_camera() -> XRCamera3D: return xr_camera

func _hud_port_get_hud_viewport() -> SubViewport: return hud_viewport
func _hud_port_set_hud_viewport(vp: SubViewport) -> void: hud_viewport = vp
func _hud_port_get_hud_mesh() -> MeshInstance3D: return hud_mesh
func _hud_port_set_hud_mesh(m: MeshInstance3D) -> void: hud_mesh = m
func _hud_port_get_watch_mesh() -> MeshInstance3D: return _watch_mesh
func _hud_port_set_watch_mesh(m: MeshInstance3D) -> void: _watch_mesh = m
func _hud_port_get_laser_mesh() -> MeshInstance3D: return _laser_mesh
func _hud_port_get_ammo_panel_vp() -> SubViewport: return _ammo_panel_vp
func _hud_port_set_ammo_panel_vp(vp: SubViewport) -> void: _ammo_panel_vp = vp
func _hud_port_get_ammo_panel_mesh() -> MeshInstance3D: return _ammo_panel_mesh
func _hud_port_set_ammo_panel_mesh(m: MeshInstance3D) -> void: _ammo_panel_mesh = m

func _hud_port_get_hud_installed() -> bool: return _hud_installed
func _hud_port_set_hud_installed(v: bool) -> void: _hud_installed = v
func _hud_port_get_frames_waited() -> int: return _frames_waited
func _hud_port_get_in_menu_mode() -> bool: return _in_menu_mode
func _hud_port_get_prev_interface_open() -> bool: return _prev_interface_open
func _hud_port_set_prev_interface_open(v: bool) -> void: _prev_interface_open = v
func _hud_port_get_interface_open() -> bool: return _interface_open
func _hud_port_set_interface_open(v: bool) -> void: _interface_open = v
func _hud_port_get_esc_menu_active() -> bool: return _esc_menu_active
func _hud_port_set_esc_menu_active(v: bool) -> void: _esc_menu_active = v
func _hud_port_get_menu_open() -> bool: return _menu_open
func _hud_port_set_menu_open(v: bool) -> void: _menu_open = v
func _hud_port_get_menu_ctrl_held() -> bool: return _menu_ctrl_held
func _hud_port_set_menu_ctrl_held(v: bool) -> void: _menu_ctrl_held = v
func _hud_port_get_config_screen_open() -> bool: return _config_screen_open
func _hud_port_get_support_trigger_pending() -> bool: return _support_trigger_pending
func _hud_port_set_support_trigger_pending(v: bool) -> void: _support_trigger_pending = v
func _hud_port_get_support_trigger_press_time() -> float: return _support_trigger_press_time
func _hud_port_get_ammo_check_timer() -> float: return _ammo_check_timer
func _hud_port_set_ammo_check_timer(v: float) -> void: _ammo_check_timer = v
func _hud_port_get_ammo_read_delay() -> int: return _ammo_read_delay
func _hud_port_set_ammo_read_delay(v: int) -> void: _ammo_read_delay = v
func _hud_port_get_laser_diag_logged() -> bool: return _laser_diag_logged
func _hud_port_set_laser_diag_logged(v: bool) -> void: _laser_diag_logged = v
func _hud_port_get_laser_locked_pos() -> Vector2: return _laser_locked_pos
func _hud_port_set_laser_locked_pos(v: Vector2) -> void: _laser_locked_pos = v
func _hud_port_set_laser_screen_pos(v: Vector2) -> void: _laser_screen_pos = v
func _hud_port_get_hud_yaw() -> float: return _hud_yaw
func _hud_port_set_hud_yaw(v: float) -> void: _hud_yaw = v

func _hud_port_get_hud_smooth_follow() -> bool: return _hud_smooth_follow
func _hud_port_get_hud_smooth_speed() -> float: return _hud_smooth_speed
func _hud_port_get_hud_lr_offset() -> float: return _hud_lr_offset
func _hud_port_get_hud_height_offset() -> float: return _hud_height_offset
func _hud_port_get_hud_distance() -> float: return _hud_distance
func _hud_port_get_menu_distance() -> float: return _menu_distance
func _hud_port_get_menu_lr_offset() -> float: return _menu_lr_offset
func _hud_port_get_menu_width() -> float: return _menu_width
func _hud_port_get_menu_laser_uv_x() -> float: return _menu_laser_uv_x
func _hud_port_get_menu_laser_uv_y() -> float: return _menu_laser_uv_y
func _hud_port_get_hud_width() -> float: return _hud_width
func _hud_port_get_hud_spread() -> float: return _hud_spread
func _hud_port_set_hud_spread_active(v: float) -> void: _hud_spread_active = v
func _hud_port_get_watch_spread() -> float: return _watch_spread
func _hud_port_get_watch_size() -> float: return _watch_size
func _hud_port_get_watch_offset() -> Vector3: return _watch_offset
func _hud_port_get_watch_glance_enabled() -> bool: return _watch_glance_enabled
func _hud_port_get_watch_glance_angle() -> float: return _watch_glance_angle
func _hud_port_get_watch_fade_speed() -> float: return _watch_fade_speed
func _hud_port_get_dominant_hand() -> String: return _config_dominant_hand
func _hud_port_get_weapon_hand() -> String: return _weapon_hand

func _hud_port_get_setup_delay() -> int: return HUD_SETUP_DELAY
func _hud_port_get_watch_crop_shader() -> String: return WATCH_CROP_SHADER

func _ensure_scope_pip():
	if not _scope_pip:
		_scope_pip = ScopePip.new(get_tree(), {
			"get_owner_node": Callable(self, "_scope_port_get_owner"),
			"get_main_viewport": Callable(self, "_scope_port_get_main_viewport"),
			"get_game_camera": Callable(self, "_scope_port_get_game_camera"),
			"get_weapon_slot": Callable(self, "_scope_port_get_weapon_slot"),
			"get_weapon_hand": Callable(self, "_scope_port_get_weapon_hand"),
			"get_controller": Callable(self, "_get_controller"),
			"get_weapon_cache": Callable(self, "_ensure_weapon_cache"),
			"sample_recoil_chain": Callable(self, "_sample_recoil_chain"),
			"get_pip_shader_source": Callable(self, "_scope_port_get_pip_shader_source"),
			"log": Callable(self, "_log_str"),
		})
	return _scope_pip


# Ports for scope_pip.gd
func _scope_port_get_owner() -> Node:
	return self

func _scope_port_get_main_viewport() -> Viewport:
	return get_viewport()

func _scope_port_get_game_camera() -> Camera3D:
	return game_camera

func _scope_port_get_weapon_slot() -> int:
	return _weapon_slot

func _scope_port_get_weapon_hand() -> String:
	return _weapon_hand

func _scope_port_get_pip_shader_source() -> String:
	return SCOPE_PIP_SHADER

func _ensure_nvg():
	if not _nvg:
		_nvg = Nvg.new(get_tree(), {
			"get_owner_node": Callable(self, "_nvg_port_get_owner"),
			"get_main_viewport": Callable(self, "_nvg_port_get_main_viewport"),
			"get_camera": Callable(self, "_nvg_port_get_camera"),
			"get_nvg_brightness": Callable(self, "_nvg_port_get_brightness"),
			"get_nvg_mono": Callable(self, "_nvg_port_get_mono"),
			"get_vignette_enabled": Callable(self, "_nvg_port_get_vignette_enabled"),
			"get_vignette_strength": Callable(self, "_nvg_port_get_vignette_strength"),
			"get_overlay_shader_source": Callable(self, "_nvg_port_get_overlay_shader"),
			"get_vignette_shader_source": Callable(self, "_nvg_port_get_vignette_shader"),
			"log": Callable(self, "_log_str"),
		})
	return _nvg


# Ports for nvg.gd
func _nvg_port_get_owner() -> Node:
	return self

func _nvg_port_get_main_viewport() -> Viewport:
	return get_viewport()

func _nvg_port_get_camera() -> XRCamera3D:
	return xr_camera

func _nvg_port_get_brightness() -> float:
	return _nvg_brightness

func _nvg_port_get_mono() -> bool:
	return _nvg_mono

func _nvg_port_get_vignette_enabled() -> bool:
	return _vignette_enabled

func _nvg_port_get_vignette_strength() -> float:
	return _vignette_strength

func _nvg_port_get_overlay_shader() -> String:
	return NVG_OVERLAY_SHADER

func _nvg_port_get_vignette_shader() -> String:
	return COMFORT_VIGNETTE_SHADER

func _ensure_decor():
	if not _decor:
		_decor = Decor.new(get_tree(), {
			"get_camera": Callable(self, "_decor_port_get_camera"),
			"get_game_camera": Callable(self, "_decor_port_get_game_camera"),
			"get_left_controller": Callable(self, "_decor_port_get_left_controller"),
			"get_right_controller": Callable(self, "_decor_port_get_right_controller"),
			"get_controller": Callable(self, "_get_controller"),
			"get_dominant_hand": Callable(self, "_decor_port_get_dominant_hand"),
			"get_holster_state": Callable(self, "_decor_port_get_holster_state"),
			"get_holster_unarmed": Callable(self, "_decor_port_get_holster_unarmed"),
			"get_holster_lowered": Callable(self, "_decor_port_get_holster_lowered"),
			"get_interface_open": Callable(self, "_decor_port_get_interface_open"),
			"get_decor_mode": Callable(self, "_decor_port_get_decor_mode"),
			"set_decor_mode": Callable(self, "_decor_port_set_decor_mode"),
			"inject_key": Callable(self, "_inject_key"),
			"get_long_press_sec": Callable(self, "_decor_port_get_long_press_sec"),
			"get_aim_deadzone_sq": Callable(self, "_decor_port_get_aim_deadzone_sq"),
			"get_steer_last_aim": Callable(self, "_decor_port_get_steer_last_aim"),
			"set_steer_last_aim": Callable(self, "_decor_port_set_steer_last_aim"),
			"get_mouse_sens": Callable(self, "_decor_port_get_mouse_sens"),
			"get_viewport": Callable(self, "_decor_port_get_viewport"),
			"log": Callable(self, "_log_str"),
		})
	return _decor


# Ports for decor.gd
func _decor_port_get_camera() -> XRCamera3D:
	return xr_camera

func _decor_port_get_game_camera() -> Camera3D:
	return game_camera

func _decor_port_get_left_controller() -> XRController3D:
	return left_controller

func _decor_port_get_right_controller() -> XRController3D:
	return right_controller

func _decor_port_get_dominant_hand() -> String:
	return _config_dominant_hand

func _decor_port_get_holster_state() -> int:
	return _holster_state

func _decor_port_get_holster_unarmed() -> int:
	return HolsterState.UNARMED

func _decor_port_get_holster_lowered() -> int:
	return HolsterState.LOWERED

func _decor_port_get_interface_open() -> bool:
	return _interface_open

func _decor_port_get_decor_mode() -> bool:
	return _decor_mode

func _decor_port_set_decor_mode(value: bool) -> void:
	_decor_mode = value

func _decor_port_get_long_press_sec() -> float:
	return DECOR_MODE_LONG_PRESS_SEC

func _decor_port_get_aim_deadzone_sq() -> float:
	return _STEER_AIM_DEADZONE_SQ

func _decor_port_get_steer_last_aim() -> Vector3:
	return _steer_decor_last_aim

func _decor_port_set_steer_last_aim(value: Vector3) -> void:
	_steer_decor_last_aim = value

func _decor_port_get_mouse_sens() -> float:
	return _mouse_sens_estimate

func _decor_port_get_viewport() -> Viewport:
	return get_viewport()

func _ensure_grenade():
	# grenade.gd is the proven-out template for the ports pattern: no autoload
	# back-reference, narrow Callable surface. Other subsystems should follow.
	if not _grenade:
		_grenade = Grenade.new(get_tree(), {
			"inject_action": Callable(self, "_inject_action"),
			"inject_mouse": Callable(self, "_inject_mouse_button"),
			"get_weapon_controller": Callable(self, "_grenade_port_get_weapon_controller"),
			"is_drawn_grenade": Callable(self, "_grenade_port_is_drawn"),
			"request_holster": Callable(self, "_holster_weapon"),
			"log": Callable(self, "_log_str"),
		})
	return _grenade


# Ports for grenade.gd (kept thin and side-effect-free). Pattern: each port
# helper resolves whatever cross-system state grenade needs from one place
# instead of grenade reaching through autoload.* itself.
func _grenade_port_get_weapon_controller() -> XRController3D:
	return _get_controller(_get_weapon_hand())


func _grenade_port_is_drawn() -> bool:
	return _holster_state == HolsterState.DRAWN and _weapon_slot == 4

func _ensure_grab():
	if not _grab:
		_grab = Grab.new(get_tree(), {
			"get_camera": Callable(self, "_grab_port_get_camera"),
			"get_controller": Callable(self, "_get_controller"),
			"get_grab_ray": Callable(self, "_grab_port_get_ray"),
			"get_bag_zone_offset": Callable(self, "_grab_port_get_bag_zone_offset"),
			"get_bag_zone_radius": Callable(self, "_grab_port_get_bag_zone_radius"),
			"get_nvg_zone_offset": Callable(self, "_grab_port_get_nvg_zone_offset"),
			"get_nvg_zone_radius": Callable(self, "_grab_port_get_nvg_zone_radius"),
			"get_dominant_hand": Callable(self, "_grab_port_get_dominant_hand"),
			"get_grabbed_object": Callable(self, "_grab_port_get_grabbed_object"),
			"set_grabbed_object": Callable(self, "_grab_port_set_grabbed_object"),
			"get_grab_hand": Callable(self, "_grab_port_get_grab_hand"),
			"set_grab_hand": Callable(self, "_grab_port_set_grab_hand"),
			"log": Callable(self, "_log_str"),
		})
	return _grab


# Ports for grab.gd (state resolvers; no side effects).
func _grab_port_get_camera() -> XRCamera3D:
	return xr_camera


func _grab_port_get_ray(hand: String) -> RayCast3D:
	return _grab_ray_right if hand == "right" else _grab_ray_left


func _grab_port_get_bag_zone_offset() -> Vector3:
	return _bag_zone_offset


func _grab_port_get_bag_zone_radius() -> float:
	return _bag_zone_radius


func _grab_port_get_nvg_zone_offset() -> Vector3:
	return _nvg_zone_offset


func _grab_port_get_nvg_zone_radius() -> float:
	return _nvg_zone_radius


func _grab_port_get_dominant_hand() -> String:
	return _config_dominant_hand


func _grab_port_get_grabbed_object() -> Node3D:
	return _grabbed_object


func _grab_port_set_grabbed_object(obj) -> void:
	_grabbed_object = obj


func _grab_port_get_grab_hand() -> String:
	return _grab_hand


func _grab_port_set_grab_hand(hand: String) -> void:
	_grab_hand = hand

func _ensure_weapon_sync():
	if not _weapon_sync:
		_weapon_sync = WeaponSync.new(get_tree(), {
			# Scene refs / controllers
			"get_game_camera": Callable(self, "_ws_port_get_game_camera"),
			"get_camera": Callable(self, "_ws_port_get_camera"),
			"get_controller": Callable(self, "_get_controller"),
			"get_cached_mgr": Callable(self, "_ws_port_get_cached_mgr"),
			"set_cached_mgr": Callable(self, "_ws_port_set_cached_mgr"),
			"set_cached_weapon_rig": Callable(self, "_ws_port_set_cached_weapon_rig"),
			"get_hand_wrapper": Callable(self, "_hands_port_get_wrapper"),
			# State (read+write)
			"get_holster_state": Callable(self, "_ws_port_get_holster_state"),
			"set_holster_state": Callable(self, "_ws_port_set_holster_state"),
			"get_state_unarmed": Callable(self, "_ws_port_get_state_unarmed"),
			"get_state_drawn": Callable(self, "_ws_port_get_state_drawn"),
			"get_state_sling": Callable(self, "_ws_port_get_state_sling"),
			"get_weapon_hand": Callable(self, "_ws_port_get_weapon_hand"),
			"get_weapon_hand_resolved": Callable(self, "_get_weapon_hand"),
			"set_weapon_hand": Callable(self, "_ws_port_set_weapon_hand"),
			"get_support_hand": Callable(self, "_get_support_hand"),
			"get_dominant_hand": Callable(self, "_ws_port_get_dominant_hand"),
			"get_weapon_slot": Callable(self, "_ws_port_get_weapon_slot"),
			"set_weapon_slot": Callable(self, "_ws_port_set_weapon_slot"),
			"get_weapon_loaded": Callable(self, "_ws_port_get_weapon_loaded"),
			"set_weapon_loaded": Callable(self, "_ws_port_set_weapon_loaded"),
			"set_weapon_is_long": Callable(self, "_ws_port_set_weapon_is_long"),
			"get_weapon_subtype": Callable(self, "_ws_port_get_weapon_subtype"),
			"set_weapon_subtype": Callable(self, "_ws_port_set_weapon_subtype"),
			"set_weapon_uses_r_reload": Callable(self, "_ws_port_set_weapon_uses_r_reload"),
			"get_action_open": Callable(self, "_ws_port_get_action_open"),
			"set_action_open": Callable(self, "_ws_port_set_action_open"),
			"set_pump_gesture_active": Callable(self, "_ws_port_set_pump_gesture_active"),
			"get_pump_gesture_active": Callable(self, "_ws_port_get_pump_gesture_active"),
			"set_pump_gesture_timer": Callable(self, "_ws_port_set_pump_gesture_timer"),
			"get_pump_gesture_timer": Callable(self, "_ws_port_get_pump_gesture_timer"),
			"get_pump_prev_pos": Callable(self, "_ws_port_get_pump_prev_pos"),
			"set_pump_prev_pos": Callable(self, "_ws_port_set_pump_prev_pos"),
			"get_pump_cooldown": Callable(self, "_ws_port_get_pump_cooldown"),
			"set_pump_cooldown": Callable(self, "_ws_port_set_pump_cooldown"),
			"get_current_weapon_name": Callable(self, "_ws_port_get_current_weapon_name"),
			"set_current_weapon_name": Callable(self, "_ws_port_set_current_weapon_name"),
			"get_recoil_rest_xform": Callable(self, "_ws_port_get_recoil_rest_xform"),
			"set_recoil_rest_xform": Callable(self, "_ws_port_set_recoil_rest_xform"),
			"get_recoil_rest_inv": Callable(self, "_ws_port_get_recoil_rest_inv"),
			"set_recoil_rest_inv": Callable(self, "_ws_port_set_recoil_rest_inv"),
			"get_walk_sway_captured": Callable(self, "_ws_port_get_walk_sway_captured"),
			"set_walk_sway_captured": Callable(self, "_ws_port_set_walk_sway_captured"),
			"get_walk_sway_logged": Callable(self, "_ws_port_get_walk_sway_logged"),
			"set_walk_sway_logged": Callable(self, "_ws_port_set_walk_sway_logged"),
			"get_walk_sway_rest": Callable(self, "_ws_port_get_walk_sway_rest"),
			"get_walk_sway_nodes": Callable(self, "_ws_port_get_walk_sway_nodes"),
			"get_walk_sway_capture_delay": Callable(self, "_ws_port_get_walk_sway_capture_delay"),
			"set_walk_sway_capture_delay": Callable(self, "_ws_port_set_walk_sway_capture_delay"),
			"get_walk_sway_capture_delay_load": Callable(self, "_ws_port_get_walk_sway_capture_delay_load"),
			"get_disable_walk_sway": Callable(self, "_ws_port_get_disable_walk_sway"),
			"get_rest_capture_pending": Callable(self, "_ws_port_get_rest_capture_pending"),
			"set_rest_capture_pending": Callable(self, "_ws_port_set_rest_capture_pending"),
			"get_rest_capture_stability_count": Callable(self, "_ws_port_get_rest_capture_stability_count"),
			"set_rest_capture_stability_count": Callable(self, "_ws_port_set_rest_capture_stability_count"),
			"get_rest_capture_hard_deadline": Callable(self, "_ws_port_get_rest_capture_hard_deadline"),
			"set_rest_capture_hard_deadline": Callable(self, "_ws_port_set_rest_capture_hard_deadline"),
			"get_rest_capture_prev_sample": Callable(self, "_ws_port_get_rest_capture_prev_sample"),
			"set_rest_capture_prev_sample": Callable(self, "_ws_port_set_rest_capture_prev_sample"),
			"get_recoil_chain_names": Callable(self, "_ws_port_get_recoil_chain_names"),
			"get_recoil_fire_rise_edge": Callable(self, "_ws_port_get_recoil_fire_rise_edge"),
			"get_fire_haptic_cooldown": Callable(self, "_ws_port_get_fire_haptic_cooldown"),
			"set_fire_haptic_cooldown": Callable(self, "_ws_port_set_fire_haptic_cooldown"),
			"get_prev_recoil_mag": Callable(self, "_ws_port_get_prev_recoil_mag"),
			"set_prev_recoil_mag": Callable(self, "_ws_port_set_prev_recoil_mag"),
			"get_support_grip_held": Callable(self, "_ws_port_get_support_grip_held"),
			"set_support_grip_held": Callable(self, "_ws_port_set_support_grip_held"),
			"get_two_hand_smooth_enabled": Callable(self, "_ws_port_get_two_hand_smooth_enabled"),
			"get_two_hand_smooth_speed": Callable(self, "_ws_port_get_two_hand_smooth_speed"),
			"get_two_hand_min_dist": Callable(self, "_ws_port_get_two_hand_min_dist"),
			"get_interface_open": Callable(self, "_ws_port_get_interface_open"),
			"get_fg_adjust_mode": Callable(self, "_ws_port_get_fg_adjust_mode"),
			"set_fg_adjust_mode": Callable(self, "_ws_port_set_fg_adjust_mode"),
			"get_fg_adjust_frozen_xform": Callable(self, "_ws_port_get_fg_adjust_frozen_xform"),
			"set_adjust_mode": Callable(self, "_ws_port_set_adjust_mode"),
			"get_rail_mode": Callable(self, "_ws_port_get_rail_mode"),
			"get_rail_active": Callable(self, "_ws_port_get_rail_active"),
			"get_rail_x_pending": Callable(self, "_ws_port_get_rail_x_pending"),
			"set_rail_x_pending": Callable(self, "_ws_port_set_rail_x_pending"),
			"get_rail_x_press_time": Callable(self, "_ws_port_get_rail_x_press_time"),
			"get_rail_long_press_sec": Callable(self, "_ws_port_get_rail_long_press_sec"),
			"get_rail_fwd": Callable(self, "_ws_port_get_rail_fwd"),
			"get_rail_grab_origin": Callable(self, "_ws_port_get_rail_grab_origin"),
			"set_rail_grab_origin": Callable(self, "_ws_port_set_rail_grab_origin"),
			"get_rail_scroll_accum": Callable(self, "_ws_port_get_rail_scroll_accum"),
			"set_rail_scroll_accum": Callable(self, "_ws_port_set_rail_scroll_accum"),
			"get_rail_scroll_cooldown": Callable(self, "_ws_port_get_rail_scroll_cooldown"),
			"set_rail_scroll_cooldown": Callable(self, "_ws_port_set_rail_scroll_cooldown"),
			"get_scroll_cooldown": Callable(self, "_ws_port_get_scroll_cooldown"),
			"set_scroll_cooldown": Callable(self, "_ws_port_set_scroll_cooldown"),
			"get_pending_holster_key": Callable(self, "_holster_port_get_pending_key"),
			"set_pending_holster_key": Callable(self, "_holster_port_set_pending_key"),
			"set_weapon_raise_timer": Callable(self, "_holster_port_set_weapon_raise_timer"),
			"get_weapon_raise_timer": Callable(self, "_ws_port_get_weapon_raise_timer"),
			# Per-weapon dictionaries
			"get_weapon_grip_offsets": Callable(self, "_ws_port_get_weapon_grip_offsets"),
			"get_weapon_grip_rotations": Callable(self, "_ws_port_get_weapon_grip_rotations"),
			"get_weapon_fg_p_local": Callable(self, "_ws_port_get_weapon_fg_p_local"),
			"get_weapon_fg_r_local": Callable(self, "_ws_port_get_weapon_fg_r_local"),
			"get_slot_grip_defaults": Callable(self, "_ws_port_get_slot_grip_defaults"),
			"get_slot_rot_defaults": Callable(self, "_ws_port_get_slot_rot_defaults"),
			# Transition state
			"get_transition_slot": Callable(self, "_ws_port_get_transition_slot"),
			"set_transition_slot": Callable(self, "_ws_port_set_transition_slot"),
			"get_transition_hand": Callable(self, "_ws_port_get_transition_hand"),
			"set_transition_hand": Callable(self, "_ws_port_set_transition_hand"),
			"get_resume_slot": Callable(self, "_ws_port_get_resume_slot"),
			"set_resume_slot": Callable(self, "_ws_port_set_resume_slot"),
			"get_resume_hand": Callable(self, "_ws_port_get_resume_hand"),
			"set_resume_hand": Callable(self, "_ws_port_set_resume_hand"),
			# Hand offsets / rotations
			"get_hand_offset_left": Callable(self, "_hands_port_get_offset_left"),
			"get_hand_offset_right": Callable(self, "_hands_port_get_offset_right"),
			"get_hand_rot_left": Callable(self, "_hands_port_get_rot_left"),
			"get_hand_rot_right": Callable(self, "_hands_port_get_rot_right"),
			# Sling
			"get_sling_offset": Callable(self, "_ws_port_get_sling_offset"),
			"get_sling_rot_offset": Callable(self, "_ws_port_get_sling_rot_offset"),
			# Side effects
			"inject_action": Callable(self, "_inject_action"),
			"inject_scroll": Callable(self, "_inject_scroll"),
			"clear_grenade_state": Callable(self, "_clear_grenade_state"),
			"cleanup_scope": Callable(self, "_cleanup_scope"),
			"fix_reticle_parallax": Callable(self, "_fix_reticle_parallax"),
			"setup_scope_pip": Callable(self, "_setup_scope_pip"),
			"update_scope_camera": Callable(self, "_update_scope_camera"),
			"enter_rail_mode": Callable(self, "_ws_port_enter_rail_mode"),
			"exit_rail_mode": Callable(self, "_ws_port_exit_rail_mode"),
			"find_node_by_class": Callable(self, "_find_node_by_class"),
			# Misc
			"get_log_path": Callable(self, "_ws_port_get_log_path"),
			"get_verbose_log": Callable(self, "_ws_port_get_verbose_log"),
			"get_process_delta": Callable(self, "_ws_port_get_process_delta"),
			"log": Callable(self, "_log_str"),
		})
	return _weapon_sync


# Ports for weapon_sync.gd
func _ws_port_get_game_camera() -> Camera3D: return game_camera
func _ws_port_get_camera() -> XRCamera3D: return xr_camera
func _ws_port_get_cached_mgr() -> Node: return _cached_mgr
func _ws_port_set_cached_mgr(n: Node) -> void: _cached_mgr = n
func _ws_port_set_cached_weapon_rig(n: Node3D) -> void: _cached_weapon_rig = n

func _ws_port_get_holster_state() -> int: return _holster_state
func _ws_port_set_holster_state(v: int) -> void: _holster_state = v
func _ws_port_get_state_unarmed() -> int: return HolsterState.UNARMED
func _ws_port_get_state_drawn() -> int: return HolsterState.DRAWN
func _ws_port_get_state_sling() -> int: return HolsterState.SLING
func _ws_port_get_weapon_hand() -> String: return _weapon_hand
func _ws_port_set_weapon_hand(v: String) -> void: _weapon_hand = v
func _ws_port_get_dominant_hand() -> String: return _config_dominant_hand
func _ws_port_get_weapon_slot() -> int: return _weapon_slot
func _ws_port_set_weapon_slot(v: int) -> void: _weapon_slot = v
func _ws_port_get_weapon_loaded() -> bool: return _weapon_loaded
func _ws_port_set_weapon_loaded(v: bool) -> void: _weapon_loaded = v
func _ws_port_set_weapon_is_long(v: bool) -> void: _weapon_is_long = v
func _ws_port_get_weapon_subtype() -> String: return _weapon_subtype
func _ws_port_set_weapon_subtype(v: String) -> void: _weapon_subtype = v
func _ws_port_set_weapon_uses_r_reload(v: bool) -> void: _weapon_uses_r_reload = v
func _ws_port_get_action_open() -> bool: return _action_open
func _ws_port_set_action_open(v: bool) -> void: _action_open = v
func _ws_port_set_pump_gesture_active(v: bool) -> void: _pump_gesture_active = v
func _ws_port_get_pump_gesture_active() -> bool: return _pump_gesture_active
func _ws_port_set_pump_gesture_timer(v: float) -> void: _pump_gesture_timer = v
func _ws_port_get_pump_gesture_timer() -> float: return _pump_gesture_timer
func _ws_port_get_pump_prev_pos() -> Vector3: return _pump_prev_pos
func _ws_port_set_pump_prev_pos(v: Vector3) -> void: _pump_prev_pos = v
func _ws_port_get_pump_cooldown() -> float: return _pump_cooldown
func _ws_port_set_pump_cooldown(v: float) -> void: _pump_cooldown = v
func _ws_port_get_current_weapon_name() -> String: return _current_weapon_name
func _ws_port_set_current_weapon_name(v: String) -> void: _current_weapon_name = v
func _ws_port_get_recoil_rest_xform() -> Transform3D: return _recoil_rest_xform
func _ws_port_set_recoil_rest_xform(v: Transform3D) -> void: _recoil_rest_xform = v
func _ws_port_get_recoil_rest_inv() -> Transform3D: return _recoil_rest_inv
func _ws_port_set_recoil_rest_inv(v: Transform3D) -> void: _recoil_rest_inv = v
func _ws_port_get_walk_sway_captured() -> bool: return _walk_sway_captured
func _ws_port_set_walk_sway_captured(v: bool) -> void: _walk_sway_captured = v
func _ws_port_get_walk_sway_logged() -> bool: return _walk_sway_logged
func _ws_port_set_walk_sway_logged(v: bool) -> void: _walk_sway_logged = v
func _ws_port_get_walk_sway_rest() -> Dictionary: return _walk_sway_rest
func _ws_port_get_walk_sway_nodes() -> Array: return _WALK_SWAY_NODES
func _ws_port_get_walk_sway_capture_delay() -> float: return _walk_sway_capture_delay
func _ws_port_set_walk_sway_capture_delay(v: float) -> void: _walk_sway_capture_delay = v
func _ws_port_get_walk_sway_capture_delay_load() -> float: return _WALK_SWAY_CAPTURE_DELAY_LOAD
func _ws_port_get_disable_walk_sway() -> bool: return _disable_walk_sway
func _ws_port_get_rest_capture_pending() -> bool: return _rest_capture_pending
func _ws_port_set_rest_capture_pending(v: bool) -> void: _rest_capture_pending = v
func _ws_port_get_rest_capture_stability_count() -> int: return _rest_capture_stability_count
func _ws_port_set_rest_capture_stability_count(v: int) -> void: _rest_capture_stability_count = v
func _ws_port_get_rest_capture_hard_deadline() -> float: return _rest_capture_hard_deadline
func _ws_port_set_rest_capture_hard_deadline(v: float) -> void: _rest_capture_hard_deadline = v
func _ws_port_get_rest_capture_prev_sample() -> Transform3D: return _rest_capture_prev_sample
func _ws_port_set_rest_capture_prev_sample(v: Transform3D) -> void: _rest_capture_prev_sample = v
func _ws_port_get_recoil_chain_names() -> Array: return _RECOIL_CHAIN_NAMES
func _ws_port_get_recoil_fire_rise_edge() -> float: return RECOIL_FIRE_RISE_EDGE
func _ws_port_get_fire_haptic_cooldown() -> float: return _fire_haptic_cooldown
func _ws_port_set_fire_haptic_cooldown(v: float) -> void: _fire_haptic_cooldown = v
func _ws_port_get_prev_recoil_mag() -> float: return _prev_recoil_mag
func _ws_port_set_prev_recoil_mag(v: float) -> void: _prev_recoil_mag = v
func _ws_port_get_support_grip_held() -> bool: return _support_grip_held
func _ws_port_set_support_grip_held(v: bool) -> void: _support_grip_held = v
func _ws_port_get_two_hand_smooth_enabled() -> bool: return _two_hand_smooth_enabled
func _ws_port_get_two_hand_smooth_speed() -> float: return _two_hand_smooth_speed
func _ws_port_get_two_hand_min_dist() -> float: return TWO_HAND_MIN_DIST_M
func _ws_port_get_interface_open() -> bool: return _interface_open
func _ws_port_get_fg_adjust_mode() -> bool: return _fg_adjust_mode
func _ws_port_set_fg_adjust_mode(v: bool) -> void: _fg_adjust_mode = v
func _ws_port_get_fg_adjust_frozen_xform() -> Transform3D: return _fg_adjust_frozen_xform
func _ws_port_set_adjust_mode(v: bool) -> void: _adjust_mode = v
func _ws_port_get_rail_mode() -> bool: return _rail_mode
func _ws_port_get_rail_active() -> bool: return _rail_active
func _ws_port_get_rail_x_pending() -> bool: return _rail_x_pending
func _ws_port_set_rail_x_pending(v: bool) -> void: _rail_x_pending = v
func _ws_port_get_rail_x_press_time() -> float: return _rail_x_press_time
func _ws_port_get_rail_long_press_sec() -> float: return RAIL_MODE_LONG_PRESS_SEC
func _ws_port_get_rail_fwd() -> Vector3: return _rail_fwd
func _ws_port_get_rail_grab_origin() -> float: return _rail_grab_origin
func _ws_port_set_rail_grab_origin(v: float) -> void: _rail_grab_origin = v
func _ws_port_get_rail_scroll_accum() -> float: return _rail_scroll_accum
func _ws_port_set_rail_scroll_accum(v: float) -> void: _rail_scroll_accum = v
func _ws_port_get_rail_scroll_cooldown() -> float: return _rail_scroll_cooldown
func _ws_port_set_rail_scroll_cooldown(v: float) -> void: _rail_scroll_cooldown = v
func _ws_port_get_scroll_cooldown() -> float: return _scroll_cooldown
func _ws_port_set_scroll_cooldown(v: float) -> void: _scroll_cooldown = v
func _ws_port_get_weapon_raise_timer() -> float: return _weapon_raise_timer

func _ws_port_get_weapon_grip_offsets() -> Dictionary: return _weapon_grip_offsets
func _ws_port_get_weapon_grip_rotations() -> Dictionary: return _weapon_grip_rotations
func _ws_port_get_weapon_fg_p_local() -> Dictionary: return _weapon_fg_p_local
func _ws_port_get_weapon_fg_r_local() -> Dictionary: return _weapon_fg_r_local
func _ws_port_get_slot_grip_defaults() -> Dictionary: return _slot_grip_defaults
func _ws_port_get_slot_rot_defaults() -> Dictionary: return _slot_rot_defaults

func _ws_port_get_transition_slot() -> int: return _transition_slot
func _ws_port_set_transition_slot(v: int) -> void: _transition_slot = v
func _ws_port_get_transition_hand() -> String: return _transition_hand
func _ws_port_set_transition_hand(v: String) -> void: _transition_hand = v
func _ws_port_get_resume_slot() -> int: return _resume_slot
func _ws_port_set_resume_slot(v: int) -> void: _resume_slot = v
func _ws_port_get_resume_hand() -> String: return _resume_hand
func _ws_port_set_resume_hand(v: String) -> void: _resume_hand = v

func _ws_port_get_sling_offset() -> Vector3: return _sling_offset
func _ws_port_get_sling_rot_offset() -> Vector3: return _sling_rot_offset

func _ws_port_enter_rail_mode() -> void:
	_enter_rail_mode()
func _ws_port_exit_rail_mode() -> void:
	_exit_rail_mode()
func _ws_port_get_log_path() -> String: return _log_path
func _ws_port_get_verbose_log() -> bool: return _verbose_log
func _ws_port_get_process_delta() -> float: return get_process_delta_time()

func _ensure_xr_rig():
	if not _xr_rig:
		_xr_rig = XrRig.new(get_tree(), {
			# Scene refs
			"get_origin": Callable(self, "_xrr_port_get_origin"),
			"get_camera": Callable(self, "_xrr_port_get_camera"),
			"get_game_camera": Callable(self, "_xrr_port_get_game_camera"),
			"set_game_camera": Callable(self, "_xrr_port_set_game_camera"),
			"get_xr_interface": Callable(self, "_xrr_port_get_xr_interface"),
			"get_main_viewport": Callable(self, "_xrr_port_get_main_viewport"),
			"get_owner_node": Callable(self, "_xrr_port_get_owner"),
			"set_left_controller": Callable(self, "_xrr_port_set_left_controller"),
			"set_right_controller": Callable(self, "_xrr_port_set_right_controller"),
			"get_controller": Callable(self, "_get_controller"),
			"set_grab_ray_left": Callable(self, "_xrr_port_set_grab_ray_left"),
			"set_grab_ray_right": Callable(self, "_xrr_port_set_grab_ray_right"),
			"set_laser_mesh": Callable(self, "_xrr_port_set_laser_mesh"),
			"set_hover_label": Callable(self, "_xrr_port_set_hover_label"),
			"get_config_reminder_label": Callable(self, "_xrr_port_get_config_reminder_label"),
			# Lifecycle / state
			"get_frames_waited": Callable(self, "_xrr_port_get_frames_waited"),
			"get_camera_lost_frames": Callable(self, "_xrr_port_get_camera_lost_frames"),
			"set_camera_lost_frames": Callable(self, "_xrr_port_set_camera_lost_frames"),
			"get_in_menu_mode": Callable(self, "_xrr_port_get_in_menu_mode"),
			"set_in_menu_mode": Callable(self, "_xrr_port_set_in_menu_mode"),
			"get_weapons_reparented": Callable(self, "_xrr_port_get_weapons_reparented"),
			"set_weapons_reparented": Callable(self, "_xrr_port_set_weapons_reparented"),
			"get_standing_mode": Callable(self, "_xrr_port_get_standing_mode"),
			"get_standing_mode_resnap": Callable(self, "_xrr_port_get_standing_mode_resnap"),
			"set_standing_mode_resnap": Callable(self, "_xrr_port_set_standing_mode_resnap"),
			"get_standing_height_ref": Callable(self, "_xrr_port_get_standing_height_ref"),
			"set_standing_height_ref": Callable(self, "_xrr_port_set_standing_height_ref"),
			"get_physical_crouch_active": Callable(self, "_xrr_port_get_physical_crouch_active"),
			"set_physical_crouch_active": Callable(self, "_xrr_port_set_physical_crouch_active"),
			"get_physical_crouch_resnap": Callable(self, "_xrr_port_get_physical_crouch_resnap"),
			"set_physical_crouch_resnap": Callable(self, "_xrr_port_set_physical_crouch_resnap"),
			"get_physical_crouch_threshold": Callable(self, "_xrr_port_get_physical_crouch_threshold"),
			"get_auto_recenter_cooldown": Callable(self, "_xrr_port_get_auto_recenter_cooldown"),
			"set_auto_recenter_cooldown": Callable(self, "_xrr_port_set_auto_recenter_cooldown"),
			"get_auto_recenter_enabled": Callable(self, "_xrr_port_get_auto_recenter_enabled"),
			"get_interface_open": Callable(self, "_xrr_port_get_interface_open"),
			"get_config_screen_open": Callable(self, "_xrr_port_get_config_screen_open"),
			"get_decor_mode": Callable(self, "_xrr_port_get_decor_mode"),
			"get_holster_state": Callable(self, "_xrr_port_get_holster_state"),
			"get_state_drawn": Callable(self, "_xrr_port_get_state_drawn"),
			"get_state_lowered": Callable(self, "_xrr_port_get_state_lowered"),
			"get_state_sling": Callable(self, "_xrr_port_get_state_sling"),
			"get_dominant_hand": Callable(self, "_xrr_port_get_dominant_hand"),
			"get_support_hand": Callable(self, "_get_support_hand"),
			"get_weapon_hand": Callable(self, "_xrr_port_get_weapon_hand"),
			"get_support_grip_held": Callable(self, "_xrr_port_get_support_grip_held"),
			"get_weapon_loaded": Callable(self, "_xrr_port_get_weapon_loaded"),
			"get_steer_have_target": Callable(self, "_xrr_port_get_steer_have_target"),
			"set_steer_have_target": Callable(self, "_xrr_port_set_steer_have_target"),
			"get_steer_last_aim": Callable(self, "_xrr_port_get_steer_last_aim"),
			"set_steer_last_aim": Callable(self, "_xrr_port_set_steer_last_aim"),
			"get_steer_last_target_yaw": Callable(self, "_xrr_port_get_steer_last_target_yaw"),
			"set_steer_last_target_yaw": Callable(self, "_xrr_port_set_steer_last_target_yaw"),
			"get_steer_last_target_pitch": Callable(self, "_xrr_port_get_steer_last_target_pitch"),
			"set_steer_last_target_pitch": Callable(self, "_xrr_port_set_steer_last_target_pitch"),
			"set_sens_cal_pending": Callable(self, "_xrr_port_set_sens_cal_pending"),
			"get_last_game_cam_pos": Callable(self, "_xrr_port_get_last_game_cam_pos"),
			"set_last_game_cam_pos": Callable(self, "_xrr_port_set_last_game_cam_pos"),
			"get_world_scale": Callable(self, "_xrr_port_get_world_scale"),
			"get_render_scale": Callable(self, "_xrr_port_get_render_scale"),
			"get_log_path": Callable(self, "_xrr_port_get_log_path"),
			"get_config_path": Callable(self, "_xrr_port_get_config_path"),
			"set_assets_base": Callable(self, "_xrr_port_set_assets_base"),
			"append_hand_load_error": Callable(self, "_xrr_port_append_hand_load_error"),
			"flush_hand_load_errors": Callable(self, "_xrr_port_flush_hand_load_errors"),
			# Constants
			"get_camera_poll_interval": Callable(self, "_xrr_port_get_camera_poll_interval"),
			"get_auto_recenter_dist": Callable(self, "_xrr_port_get_auto_recenter_dist"),
			"get_two_hand_min_dist": Callable(self, "_xrr_port_get_two_hand_min_dist"),
			"get_aim_deadzone_sq": Callable(self, "_xrr_port_get_aim_deadzone_sq"),
			"get_mouse_sens": Callable(self, "_xrr_port_get_mouse_sens"),
			# Side effects
			"on_level_transition": Callable(self, "_on_level_transition"),
			"on_main_menu_entered": Callable(self, "_on_main_menu_entered"),
			"reparent_camera_children": Callable(self, "_xrr_port_reparent_camera_children"),
			"setup_comfort_vignette": Callable(self, "_setup_comfort_vignette"),
			"create_holster_holos": Callable(self, "_create_holster_holos"),
			"steer_decor_camera_to_controller": Callable(self, "_steer_decor_camera_to_controller"),
			"inject_action": Callable(self, "_inject_action"),
			"create_hand_model": Callable(self, "_xrr_port_create_hand_model"),
			"extract_hand_assets_from_vmz": Callable(self, "_xrr_port_extract_hand_assets_from_vmz"),
			"save_full_config": Callable(self, "_save_full_config"),
			"get_on_button_pressed": Callable(self, "_xrr_port_get_on_button_pressed"),
			"get_on_button_released": Callable(self, "_xrr_port_get_on_button_released"),
			"log": Callable(self, "_log_str"),
		})
	return _xr_rig


# Ports for xr_rig.gd
func _xrr_port_get_origin() -> XROrigin3D: return xr_origin
func _xrr_port_get_camera() -> XRCamera3D: return xr_camera
func _xrr_port_get_game_camera() -> Camera3D: return game_camera
func _xrr_port_set_game_camera(c: Camera3D) -> void: game_camera = c
func _xrr_port_get_xr_interface() -> XRInterface: return xr_interface
func _xrr_port_get_main_viewport() -> Viewport: return get_viewport()
func _xrr_port_get_owner() -> Node: return self
func _xrr_port_set_left_controller(c: XRController3D) -> void: left_controller = c
func _xrr_port_set_right_controller(c: XRController3D) -> void: right_controller = c
func _xrr_port_set_grab_ray_left(r: RayCast3D) -> void: _grab_ray_left = r
func _xrr_port_set_grab_ray_right(r: RayCast3D) -> void: _grab_ray_right = r
func _xrr_port_set_laser_mesh(m: MeshInstance3D) -> void: _laser_mesh = m
func _xrr_port_set_hover_label(l: Label3D) -> void: _hover_label = l
func _xrr_port_get_config_reminder_label() -> Label3D: return _config_reminder_label

func _xrr_port_get_frames_waited() -> int: return _frames_waited
func _xrr_port_get_camera_lost_frames() -> int: return _camera_lost_frames
func _xrr_port_set_camera_lost_frames(v: int) -> void: _camera_lost_frames = v
func _xrr_port_get_in_menu_mode() -> bool: return _in_menu_mode
func _xrr_port_set_in_menu_mode(v: bool) -> void: _in_menu_mode = v
func _xrr_port_get_weapons_reparented() -> bool: return _weapons_reparented
func _xrr_port_set_weapons_reparented(v: bool) -> void: _weapons_reparented = v
func _xrr_port_get_standing_mode() -> bool: return _standing_mode
func _xrr_port_get_standing_mode_resnap() -> int: return _standing_mode_resnap
func _xrr_port_set_standing_mode_resnap(v: int) -> void: _standing_mode_resnap = v
func _xrr_port_get_standing_height_ref() -> float: return _standing_height_ref
func _xrr_port_set_standing_height_ref(v: float) -> void: _standing_height_ref = v
func _xrr_port_get_physical_crouch_active() -> bool: return _physical_crouch_active
func _xrr_port_set_physical_crouch_active(v: bool) -> void: _physical_crouch_active = v
func _xrr_port_get_physical_crouch_resnap() -> int: return _physical_crouch_resnap
func _xrr_port_set_physical_crouch_resnap(v: int) -> void: _physical_crouch_resnap = v
func _xrr_port_get_physical_crouch_threshold() -> float: return _physical_crouch_threshold
func _xrr_port_get_auto_recenter_cooldown() -> float: return _auto_recenter_cooldown
func _xrr_port_set_auto_recenter_cooldown(v: float) -> void: _auto_recenter_cooldown = v
func _xrr_port_get_auto_recenter_enabled() -> bool: return _auto_recenter_enabled
func _xrr_port_get_interface_open() -> bool: return _interface_open
func _xrr_port_get_config_screen_open() -> bool: return _config_screen_open
func _xrr_port_get_decor_mode() -> bool: return _decor_mode
func _xrr_port_get_holster_state() -> int: return _holster_state
func _xrr_port_get_state_drawn() -> int: return HolsterState.DRAWN
func _xrr_port_get_state_lowered() -> int: return HolsterState.LOWERED
func _xrr_port_get_state_sling() -> int: return HolsterState.SLING
func _xrr_port_get_dominant_hand() -> String: return _config_dominant_hand
func _xrr_port_get_weapon_hand() -> String: return _get_weapon_hand()
func _xrr_port_get_support_grip_held() -> bool: return _support_grip_held
func _xrr_port_get_weapon_loaded() -> bool: return _weapon_loaded
func _xrr_port_get_steer_have_target() -> bool: return _steer_game_have_target
func _xrr_port_set_steer_have_target(v: bool) -> void: _steer_game_have_target = v
func _xrr_port_get_steer_last_aim() -> Vector3: return _steer_game_last_aim
func _xrr_port_set_steer_last_aim(v: Vector3) -> void: _steer_game_last_aim = v
func _xrr_port_get_steer_last_target_yaw() -> float: return _steer_game_last_target_yaw
func _xrr_port_set_steer_last_target_yaw(v: float) -> void: _steer_game_last_target_yaw = v
func _xrr_port_get_steer_last_target_pitch() -> float: return _steer_game_last_target_pitch
func _xrr_port_set_steer_last_target_pitch(v: float) -> void: _steer_game_last_target_pitch = v
func _xrr_port_set_sens_cal_pending(v: bool) -> void: _sens_cal_pending = v
func _xrr_port_get_last_game_cam_pos() -> Vector3: return _last_game_cam_pos
func _xrr_port_set_last_game_cam_pos(v: Vector3) -> void: _last_game_cam_pos = v
func _xrr_port_get_world_scale() -> float: return world_scale
func _xrr_port_get_render_scale() -> float: return _render_scale
func _xrr_port_get_log_path() -> String: return _log_path
func _xrr_port_get_config_path() -> String: return _config_path
func _xrr_port_set_assets_base(v: String) -> void: _assets_base = v
func _xrr_port_append_hand_load_error(msg: String) -> void: _hand_load_errors.append(msg)
func _xrr_port_flush_hand_load_errors() -> void:
	for msg in _hand_load_errors:
		_log(msg)
	_hand_load_errors.clear()

func _xrr_port_get_camera_poll_interval() -> int: return CAMERA_POLL_INTERVAL
func _xrr_port_get_auto_recenter_dist() -> float: return AUTO_RECENTER_DIST_M
func _xrr_port_get_two_hand_min_dist() -> float: return TWO_HAND_MIN_DIST_M
func _xrr_port_get_aim_deadzone_sq() -> float: return _STEER_AIM_DEADZONE_SQ
func _xrr_port_get_mouse_sens() -> float: return _mouse_sens_estimate

func _xrr_port_reparent_camera_children() -> void:
	_reparent_camera_children()
func _xrr_port_create_hand_model(ctrl: XRController3D, model_name: String) -> void:
	_create_hand_model(ctrl, model_name)
func _xrr_port_extract_hand_assets_from_vmz() -> bool:
	return _extract_hand_assets_from_vmz()
func _xrr_port_get_on_button_pressed() -> Callable:
	return Callable(self, "_on_button_pressed")
func _xrr_port_get_on_button_released() -> Callable:
	return Callable(self, "_on_button_released")

func _ensure_input():
	if not _input:
		_input = InputDispatch.new(get_tree(), {
			"get_left_controller": Callable(self, "_inp_port_get_lc"),
			"get_right_controller": Callable(self, "_inp_port_get_rc"),
			"get_controller": Callable(self, "_get_controller"),
			"get_camera": Callable(self, "_inp_port_get_camera"),
			"get_game_camera": Callable(self, "_inp_port_get_game_camera"),
			"get_dominant_hand": Callable(self, "_inp_port_get_dominant_hand"),
			"get_deadzone": Callable(self, "_inp_port_get_deadzone"),
			"get_use_snap_turn": Callable(self, "_inp_port_get_use_snap_turn"),
			"get_snap_turn_degrees": Callable(self, "_inp_port_get_snap_turn_degrees"),
			"get_smooth_turn_speed": Callable(self, "_inp_port_get_smooth_turn_speed"),
			"get_interface_open": Callable(self, "_inp_port_get_interface_open"),
			"get_decor_mode": Callable(self, "_inp_port_get_decor_mode"),
			"get_adjust_mode": Callable(self, "_inp_port_get_adjust_mode"),
			"get_fg_adjust_mode": Callable(self, "_inp_port_get_fg_adjust_mode"),
			"get_weapon_slot": Callable(self, "_inp_port_get_weapon_slot"),
			"get_rail_mode": Callable(self, "_inp_port_get_rail_mode"),
			"get_config_screen_open": Callable(self, "_inp_port_get_config_screen_open"),
			"get_move_direction_mode": Callable(self, "_inp_port_get_move_direction_mode"),
			"get_move_direction_hand": Callable(self, "_inp_port_get_move_direction_hand"),
			"get_scroll_cooldown": Callable(self, "_ws_port_get_scroll_cooldown"),
			"set_scroll_cooldown": Callable(self, "_ws_port_set_scroll_cooldown"),
			"get_rail_scroll_cooldown": Callable(self, "_ws_port_get_rail_scroll_cooldown"),
			"set_rail_scroll_cooldown": Callable(self, "_ws_port_set_rail_scroll_cooldown"),
			"get_snap_turn_cooldown": Callable(self, "_inp_port_get_snap_turn_cooldown"),
			"set_snap_turn_cooldown": Callable(self, "_inp_port_set_snap_turn_cooldown"),
			"get_adjust_speed": Callable(self, "_inp_port_get_adjust_speed"),
			"get_adjust_rot_speed": Callable(self, "_inp_port_get_adjust_rot_speed"),
			"get_verbose_log": Callable(self, "_inp_port_get_verbose_log"),
			"get_current_weapon_name": Callable(self, "_ws_port_get_current_weapon_name"),
			"get_weapon_grip_offset": Callable(self, "_get_weapon_grip_offset"),
			"set_weapon_grip_offset": Callable(self, "_set_weapon_grip_offset"),
			"get_weapon_grip_rotation": Callable(self, "_get_weapon_grip_rotation"),
			"set_weapon_grip_rotation": Callable(self, "_set_weapon_grip_rotation"),
			"inject_key": Callable(self, "_inject_key"),
			"inject_scroll": Callable(self, "_inject_scroll"),
			"turn_origin": Callable(self, "_turn_origin"),
			"scroll_config_panel": Callable(self, "_scroll_config_panel"),
			"scope_zoom_branch_eligible": Callable(self, "_scope_zoom_branch_eligible"),
			"cycle_scope_zoom": Callable(self, "_cycle_scope_zoom"),
			"ensure_decor": Callable(self, "_ensure_decor"),
			"ensure_nvg": Callable(self, "_ensure_nvg"),
			"log": Callable(self, "_log_str"),
		})
	return _input


# Ports for input.gd
func _inp_port_get_lc() -> XRController3D: return left_controller
func _inp_port_get_rc() -> XRController3D: return right_controller
func _inp_port_get_camera() -> XRCamera3D: return xr_camera
func _inp_port_get_game_camera() -> Camera3D: return game_camera
func _inp_port_get_dominant_hand() -> String: return _config_dominant_hand
func _inp_port_get_deadzone() -> float: return thumbstick_deadzone
func _inp_port_get_use_snap_turn() -> bool: return use_snap_turn
func _inp_port_get_snap_turn_degrees() -> float: return snap_turn_degrees
func _inp_port_get_smooth_turn_speed() -> float: return smooth_turn_speed
func _inp_port_get_interface_open() -> bool: return _interface_open
func _inp_port_get_decor_mode() -> bool: return _decor_mode
func _inp_port_get_adjust_mode() -> bool: return _adjust_mode
func _inp_port_get_fg_adjust_mode() -> bool: return _fg_adjust_mode
func _inp_port_get_weapon_slot() -> int: return _weapon_slot
func _inp_port_get_rail_mode() -> bool: return _rail_mode
func _inp_port_get_config_screen_open() -> bool: return _config_screen_open
func _inp_port_get_move_direction_mode() -> String: return _move_direction_mode
func _inp_port_get_move_direction_hand() -> String: return _move_direction_hand
func _inp_port_get_snap_turn_cooldown() -> bool: return _snap_turn_cooldown
func _inp_port_set_snap_turn_cooldown(v: bool) -> void: _snap_turn_cooldown = v
func _inp_port_get_adjust_speed() -> float: return ADJUST_SPEED
func _inp_port_get_adjust_rot_speed() -> float: return ADJUST_ROT_SPEED
func _inp_port_get_verbose_log() -> bool: return _verbose_log

# Single-arg wrapper around the variadic _log() so subsystems can hand a
# Callable of known arity to anything that wants logging.
func _log_str(msg: String) -> void:
	_log(msg)

# Tunables — class-level const uses = not := per GDScript 4
const RAIL_MODE_LONG_PRESS_SEC = 0.3
const DECOR_MODE_LONG_PRESS_SEC = 0.5
const AUTO_RECENTER_DIST_M = 0.45
const TWO_HAND_MIN_DIST_M = 0.1
const RECOIL_FIRE_RISE_EDGE = 0.003
const HOLSTER_KEY_DELAY_SEC = 0.15
const HOLSTER_KEY_RELEASE_SEC = 0.1
const GRENADE_TAP_SEC = 0.080
const GRENADE_AUTO_HOLSTER_SEC = 0.5
const KEY_TAP_RELEASE_SEC = 0.08
const _STEER_AIM_DEADZONE_SQ = 0.0000004   # ~0.001 rad squared; below this skip mouse injection

# Aim-deadzone caches read by xr_rig.gd / decor.gd. Declared here so the dynamic
# property fallback never hides a typo in the subsystems.
var _steer_game_have_target := false
var _steer_game_last_aim := Vector3.ZERO
var _steer_game_last_target_yaw := 0.0
var _steer_game_last_target_pitch := 0.0
var _steer_decor_last_aim := Vector3.ZERO

# Walk-sway suppression state — original declarations were lost during the
# Phase 4 module split. weapon_sync.gd reads/writes these via autoload.* and
# without explicit vars the dynamic-property fallback would silently misfire
# (null comparisons, no-op .clear() calls).
const _RECOIL_CHAIN_NAMES: Array = ["Handling", "Sway", "Noise", "Tilt", "Impulse", "Recoil"]
const _WALK_SWAY_NODES: Array = ["Handling", "Sway", "Noise", "Tilt"]
const _WALK_SWAY_CAPTURE_DELAY_LOAD = 1.0
const _WALK_SWAY_CAPTURE_DELAY_TOGGLE = 0.1
var _walk_sway_rest: Dictionary = {}
var _walk_sway_captured := false
var _walk_sway_logged := false
var _walk_sway_capture_delay := 0.0
var _rest_capture_pending := false

# Shader sources - referenced by hud_watch.gd, nvg.gd, scope_pip.gd via
# autoload.<NAME>. Lost during the Phase 4 split; restored on the autoload
# so the modules' shader.code = autoload.<NAME> assignments work.
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

var _scroll_cooldown := 0.0  # Prevent rapid-fire scroll
var _support_grip_held := false  # Support hand grip held = two-hand weapon grip
var _grabbed_object: Node3D = null  # Currently grabbed loose item (broadly shared)
var _grab_hand := ""  # Which hand holds the grabbed object ("left" or "right") (broadly shared)
var _grab_ray_left: RayCast3D   # Grab raycast on left controller
var _grab_ray_right: RayCast3D  # Grab raycast on right controller
# _grab_offset, _throw_samples, _grab_in_bag_zone migrated to Grab subsystem
# (see resources/vr_mod/grab.gd). The 2 broadly-shared fields above stay
# here until the input handler/holster state machine is themselves split.
var _weapon_loaded := false  # Track if weapon appeared
var _weapon_is_long := false  # True for rifles/shotguns that support two-hand aim
var _recoil_rest_xform := Transform3D.IDENTITY  # Cached rest pose of recoil chain
var _recoil_rest_inv := Transform3D.IDENTITY    # affine_inverse of _recoil_rest_xform; updated alongside it
var _rest_capture_prev_sample: Transform3D = Transform3D.IDENTITY  # stability-gate previous sample
var _rest_capture_stability_count: int = 0  # consecutive stable frames
var _rest_capture_hard_deadline: float = 0.0  # seconds remaining before force-commit
var _prev_recoil_mag := 0.0         # recoil chain origin magnitude last frame; rising edge = shot
var _fire_haptic_cooldown := 0.0    # seconds until next fire haptic allowed
var _disable_walk_sway := false  # Skip Sway node contribution in chain delta (walk/movement bob); keeps Noise stamina wobble intact
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
var _resume_slot := 0       # last drawn slot persisted to config (survives app restarts)
var _resume_hand := ""      # last drawn hand persisted to config
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
var _holster_zones_mirrored := false
var _holster_holo_nodes: Dictionary = {}  # slot -> Node3D container
var _holster_holos_enabled := true
var _sling_offset := Vector3(0.2, -0.31, -0.06)    # primary weapon sling pos relative to head (yaw only)
var _sling_rot_offset := Vector3(0.0, 60.0, 0.0)   # extra pitch/yaw/roll applied on top of slot rotation (degrees)
var _hand_in_zone := {"left": 0, "right": 0}  # Which holster zone each hand is in (0 = none)

# Bag zone: reach behind the right shoulder to add a held item to inventory
var _bag_zone_offset := Vector3(0.15, -0.10, 0.35)  # Right-back, upper body (yaw-relative)
var _bag_zone_radius := 0.35
# _grab_in_bag_zone migrated to Grab subsystem (see grab.gd).

# NVG zone: reach above head to toggle night vision goggles
var _nvg_zone_offset := Vector3(0.0, 0.30, 0.0)   # Head-relative, above head
var _nvg_zone_radius := 0.25
# _hand_in_nvg_zone migrated to Nvg subsystem (hand_in_zone field).

# NVG overlay system. Scene-graph references and runtime activation flags
# (_nvg_active, _nvg_overlay_mesh, _nvg_overlay_installed, _nvg_mono_viewport,
# _nvg_mono_camera, _cached_nvg_overlay) live on the Nvg subsystem; these
# config knobs stay here because the F8 panel writes them in place.
var _nvg_mono := true                   # config: mono vision (same image both eyes)
var _nvg_brightness := 5.0             # config: brightness multiplier

# Decor mode (shelter furniture placement). _decor_mode itself remains here
# because it is read by ~30 sites across input handling, weapon sync gating,
# hand visibility, xr_rig steering, and diagnostics; treating it as a
# subsystem field would require shims at every read. The decor-internal
# timing state (X long-press, scroll cooldown/mode) lives on the Decor
# subsystem — see resources/vr_mod/decor.gd.
var _decor_mode := false
var _left_grip_held := false
var _right_grip_held := false

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

# Scope PIP and reticle parallax fix state migrated to ScopePip subsystem
# (see resources/vr_mod/scope_pip.gd). The subsystem owns the SubViewport,
# Camera3D, lens mesh refs, variable-zoom arrays, and the per-instance
# patched-reticle dedupe set.

# Rail movement (optic slide along rail)
var _rail_mode := false               # Rail slide mode active (X long-press while DRAWN)
var _rail_x_press_time := 0.0         # Time when X was pressed (for long-press detection)
var _rail_x_pending := false           # X pressed, waiting to determine short vs long press
var _rail_active := false              # Physical rail slide in progress (trigger held)
var _rail_grab_origin := 0.0           # Off-hand projected position at grab start
var _rail_fwd := Vector3.ZERO          # Weapon forward axis frozen at grab start (constant reference axis)
var _rail_scroll_accum := 0.0          # Accumulated movement for physical grab
var _rail_scroll_cooldown := 0.0       # Cooldown for stick-based scrolling

# Support trigger long-press detection (short = reload, long = ammo check)
var _fire_trigger_held := false     # true while weapon-hand trigger is held for fire
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
# _fg_p_sup_local / _fg_r_sup_local / _fg_grip_captured migrated to
# WeaponSync subsystem (fg_p_sup_local, fg_r_sup_local, fg_grip_captured).
var _cached_weapon_rig: Node3D = null  # last weapon_rig ref, used for adjust mode entry/save
var _cached_mgr: Node = null           # cached game_camera/Manager; cleared on level transition

# Used for activating VR Config Menu
var _left_stick_held := false
var _right_stick_held := false
var _readme_bbcode_cache := ""
var _config_reminder_label: Label3D = null

func _get_weapon_hand() -> String:
	if _holster_state != HolsterState.UNARMED and _weapon_hand != "":
		return _weapon_hand
	return _config_dominant_hand


func _get_support_hand() -> String:
	return "left" if _get_weapon_hand() == "right" else "right"


func _get_controller(hand: String) -> XRController3D:
	return right_controller if hand == "right" else left_controller


# Per-frame transform snapshot. Refreshed lazily on first access each frame
# (and eagerly at the top of _process via _refresh_vrframe(delta)). Subsystems
# read pose/state through this snapshot rather than re-querying XR nodes, so
# the script-engine boundary is crossed once per frame instead of once per
# subsystem call.
var _vrframe := {
	"frame": -1,
	"delta": 0.0,
	"phase": 0,
	"xr_ready": false,
	"weapon_loaded": false,
	"interface_open": false,
	"decor_mode": false,
	"config_screen_open": false,
	"holster_state": 0,
	"weapon_slot": 0,
	"weapon_hand": "",
	"support_hand": "",
	"cam_valid": false,
	"cam_pos": Vector3.ZERO,
	"cam_basis": Basis.IDENTITY,
	"yaw_basis": Basis.IDENTITY,
	"left_pos": Vector3.ZERO,
	"left_basis": Basis.IDENTITY,
	"left_active": false,
	"right_pos": Vector3.ZERO,
	"right_basis": Basis.IDENTITY,
	"right_active": false,
}

# Ordered list of subsystem instances exposing process(frame, delta).
# Populated in _install_xr_rig() once XR objects are constructed. Each
# subsystem in this list owns one slice of per-frame work; the autoload
# remains the lifecycle/wiring layer.
var _systems: Array = []

func _refresh_vrframe(delta: float = 0.0) -> Dictionary:
	var f := Engine.get_process_frames()
	if _vrframe["frame"] == f:
		return _vrframe
	_vrframe["frame"] = f
	_vrframe["delta"] = delta
	_vrframe["phase"] = _phase
	_vrframe["xr_ready"] = _xr_ready
	_vrframe["weapon_loaded"] = _weapon_loaded
	_vrframe["interface_open"] = _interface_open
	_vrframe["decor_mode"] = _decor_mode
	_vrframe["config_screen_open"] = _config_screen_open
	_vrframe["holster_state"] = _holster_state
	_vrframe["weapon_slot"] = _weapon_slot
	_vrframe["weapon_hand"] = _get_weapon_hand()
	_vrframe["support_hand"] = _get_support_hand()
	if xr_camera and is_instance_valid(xr_camera):
		_vrframe["cam_valid"] = true
		_vrframe["cam_pos"] = xr_camera.global_position
		_vrframe["cam_basis"] = xr_camera.global_basis
		_vrframe["yaw_basis"] = Basis(Vector3.UP, xr_camera.global_rotation.y)
	else:
		_vrframe["cam_valid"] = false
	if left_controller and is_instance_valid(left_controller):
		_vrframe["left_active"] = left_controller.get_is_active()
		if _vrframe["left_active"]:
			_vrframe["left_pos"] = left_controller.global_position
			_vrframe["left_basis"] = left_controller.global_basis
	else:
		_vrframe["left_active"] = false
	if right_controller and is_instance_valid(right_controller):
		_vrframe["right_active"] = right_controller.get_is_active()
		if _vrframe["right_active"]:
			_vrframe["right_pos"] = right_controller.global_position
			_vrframe["right_basis"] = right_controller.global_basis
	else:
		_vrframe["right_active"] = false
	return _vrframe


var _holster_zone_world_cache := {}     # slot -> Vector3 zone world pos for the current frame
var _holster_zone_cache_frame := -1     # Engine frame number when cache was last computed

func _get_nearby_holster_zone(controller_pos: Vector3) -> int:
	# Holster zone caching is internal to refresh_holster_zone_cache() now;
	# this thin shim is the only zone read needed by _on_button_pressed.
	return _ensure_holster().get_nearby_holster_zone(controller_pos)


func _is_in_bag_zone(world_pos: Vector3) -> bool:
	return _ensure_grab().is_in_bag_zone(world_pos)



func _is_in_nvg_zone(world_pos: Vector3) -> bool:
	return _ensure_grab().is_in_nvg_zone(world_pos)



func _is_decor_placing() -> bool:
	return _ensure_decor().is_decor_placing()



func _toggle_decor_mode() -> void:
	_ensure_decor().toggle_decor_mode()



func _create_holster_holos() -> void:
	# Called once from _install_xr_rig; the holographic helper builders
	# (mk_holo_mat / add_holo_box/cyl/sph) live entirely on the Holster
	# subsystem and are no longer exposed here.
	_ensure_holster().create_holster_holos()



func _draw_weapon(hand: String, slot: int) -> void:
	_ensure_holster().draw_weapon(hand, slot)




func _enter_sling() -> void:
	_ensure_holster().enter_sling()


func _raise_weapon() -> void:
	_ensure_holster().raise_weapon()


func _holster_weapon() -> void:
	_ensure_holster().holster_weapon()


# HUD
var hud_viewport: SubViewport
# _watch_b_vp migrated to HudWatch subsystem (watch_b_vp field).
var hud_mesh: MeshInstance3D
var _hud_installed := false
var _interface_open := false
var _prev_interface_open := false  # For detecting transitions
var _in_menu_mode := false         # True when at the main menu (no game camera); shows HUD panel
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
var _laser_locked_pos := Vector2(-9999.0, -9999.0)  # Dead-zone locked cursor position
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
# _watch_alpha migrated to HudWatch subsystem (watch_alpha field).
var _watch_size := 0.15               # Watch quad side length (metres)
var _watch_glance_enabled := false    # Glance-to-reveal on/off (off = always visible)
var _watch_glance_angle := 40.0       # Max gaze angle (degrees) for reveal
var _watch_fade_speed := 8.0          # Alpha lerp speed (units/sec)
var _watch_spread := 0.15             # Compact spread for watch mode
var _watch_offset := Vector3(-0.06, -0.08, 0.34)  # X/Y/Z offset on hand model
var _watch_rot := Vector3(180.0, 90.0, -90.0)     # Extra rotation offset in degrees (base -90 X is always applied)
# _vitals_node, _medical_node, _watch_crop_*, _watch_alpha migrated to
# HudWatch subsystem (vitals_node, medical_node, watch_crop_* fields).

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
var _move_direction_mode := "camera"  # "camera" = HMD yaw, "controller" = chosen controller yaw
var _move_direction_hand := "left"    # "left" or "right"; used when _move_direction_mode == "controller"
var _config_dominant_hand := "right"
var _standing_mode := false          # false = sitting (fixed height), true = standing (physical height)
var _standing_mode_resnap := 0       # frames remaining before re-snapping origin after mode change
var _standing_height_ref := 0.0      # xr_camera.position.y captured at full upright height (STAGE space)
var _physical_crouch_threshold := 0.4  # metres below standing height to trigger game crouch
var _physical_crouch_active := false
var _physical_crouch_resnap := 0      # frames to freeze Y + wait before re-snapping after release
var _snap_turn_cooldown := false
var _last_game_cam_pos := Vector3.ZERO
var _auto_recenter_enabled := true
var _auto_recenter_cooldown := 0.0

# Two-hand aim stabilization
var _two_hand_smooth_enabled := true
var _two_hand_smooth_speed := 14.0
# _two_hand_smooth_basis / _two_hand_was_active / _arc_raw_aim_basis
# migrated to WeaponSync subsystem (same names without the leading
# underscore — see resources/vr_mod/weapon_sync.gd).

# Comfort vignette. Strength/enabled flag tunable via F8 stay here; the
# scene mesh and runtime hold/radius animation state live on Nvg subsystem.
var _vignette_enabled := false
var _vignette_strength := 0.7

# Mouse steering
var _mouse_sens_estimate := 0.003  # fixed; calibration removed (was drifting toward 0.001)
var _sens_cal_pending := false


# Timing
const CAMERA_POLL_INTERVAL := 30
const XR_SETTLE_FRAMES := 10
const HUD_SETUP_DELAY := 30
const MENU_SETTLE_FRAMES := 90  # ~1.5s; proceed to VR even without game camera


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		get_viewport().use_xr = false
		_log("[VR Mod] Viewport use_xr = FALSE (waiting for gameplay)")


func _ready() -> void:
	# Run AFTER game scripts so our weapon transform override sticks
	process_priority = 1000
	process_physics_priority = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keep running even if game pauses (ESC menu)
	get_tree().node_added.connect(_on_bullet_hole_node_added)
	_log("[VR Mod] === VR Mod initializing (priority=1000) ===")

	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface:
		_log("[VR Mod] Found OpenXR interface")
		if not xr_interface.is_initialized():
			if xr_interface.initialize():
				_log("[VR Mod] OpenXR interface initialized")
			else:
				printerr("[VR Mod] ERROR: Failed to initialize OpenXR interface")
				return
		else:
			_log("[VR Mod] OpenXR interface already initialized")
		XRServer.primary_interface = xr_interface
		_xr_ready = true
		_log("[VR Mod] OpenXR ready (view count: ", xr_interface.get_view_count(), ")")
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
		_log("[VR Mod] Tracking: standing (roomscale)")
	else:
		_log("[VR Mod] Tracking: sitting (local)")
	_log("[VR Mod] Waiting for 3D camera (gameplay start)...")
	# Show reminder about VR options menu at startup; persists (hidden) for main menu reuse
	_config_reminder_label = Label3D.new()
	_config_reminder_label.text = "VR OPTIONS MENU:\nToggle In-Game \nBy Clicking Both Thumbsticks"
	_config_reminder_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_config_reminder_label.modulate = Color(0.2, 0.5, 1.0)
	_config_reminder_label.outline_modulate = Color.BLACK
	_config_reminder_label.pixel_size = 0.002
	_config_reminder_label.font_size = 32
	_config_reminder_label.no_depth_test = true
	_config_reminder_label.shaded = false
	_config_reminder_label.render_priority = 127
	_config_reminder_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_config_reminder_label.layers = 1 << 19
	xr_camera.add_child(_config_reminder_label)
	_config_reminder_label.position = Vector3(0, 0, -0.75)
	_log("[VR Mod] Showing config reminder")
	get_tree().create_timer(3.0).timeout.connect(_anchor_config_reminder)


func _process(delta: float) -> void:
	if not _xr_ready:
		return
	_frames_waited += 1
	match _phase:
		0:
			_process_waiting_for_camera()
		1:
			_process_xr_activation()
		2:
			_refresh_vrframe(delta)
			for sys in _systems:
				if sys and sys.has_method("process"):
					sys.process(_vrframe, delta)


func _process_waiting_for_camera() -> void:
	# Phase 0: poll the scene tree for the gameplay Camera3D. If none appears
	# within MENU_SETTLE_FRAMES, fall through to VR-at-main-menu mode so the
	# F8 config screen and HUD panel still come up.
	if _frames_waited % CAMERA_POLL_INTERVAL != 0:
		return
	game_camera = _find_game_camera(get_tree().root)
	if game_camera:
		_log("[VR Mod] === Game camera detected! ===")
		_log("[VR Mod] Camera: ", game_camera.get_path())
		_phase = 1
		_frames_waited = 0
	elif _frames_waited >= MENU_SETTLE_FRAMES:
		_log("[VR Mod] No gameplay camera after settle — enabling VR at main menu")
		_in_menu_mode = true
		_phase = 1
		_frames_waited = 0


func _process_xr_activation() -> void:
	# Phase 1: wait XR_SETTLE_FRAMES for OpenXR to stabilize, then build the
	# rig + subsystem pipeline and advance to the running phase.
	if _frames_waited >= XR_SETTLE_FRAMES:
		_install_xr_rig()
		_phase = 2
		_frames_waited = 0


func _install_xr_rig() -> void:
	_ensure_xr_rig().install_xr_rig()
	_build_systems_pipeline()


func _build_systems_pipeline() -> void:
	# Order matters and matches the legacy _process() body precisely:
	# 1. holster zone haptics + holos depend on freshly-snapshotted head pose.
	# 2. NVG/vignette overlays update before origin sync so any visibility
	#    flips this frame are reflected in the next steer call.
	# 3. xr_rig syncs origin -> game and steers the game camera; weapon_sync
	#    must run AFTER this so our weapon transform override wins (the game
	#    moves the weapon on every frame inside its own camera child tree).
	# 4. hands and grab need the post-sync controller pose.
	# 5. hud_watch handles interface state + watch glance + smooth follow.
	# 6. config_ui dispatches the laser pointer last so any flag flipped by
	#    earlier systems this frame is honoured.
	# decor + scope_pip + grenade are present so future per-frame work lands
	# in the right module without touching the autoload _process loop.
	# hud_watch first so _interface_open / _watch_crop_delay flips for this
	# frame are visible to xr_rig (steer gating) and config_ui (laser branch).
	_systems = [
		_ensure_hud_watch(),
		_ensure_holster(),
		_ensure_nvg(),
		_ensure_xr_rig(),
		_ensure_weapon_sync(),
		_ensure_hands(),
		_ensure_grab(),
		_ensure_decor(),
		_ensure_scope_pip(),
		_ensure_grenade(),
		_ensure_config_ui(),
		# Input dispatch runs last so all per-frame state flips set by earlier
		# subsystems are honoured by the same frame's button/stick polling.
		_ensure_input(),
	]



func _setup_nvg_overlay() -> void:
	_ensure_nvg().setup_nvg_overlay()






func _setup_comfort_vignette() -> void:
	_ensure_nvg().setup_comfort_vignette()



func _release_physical_crouch() -> void:
	# Still called from _on_level_transition (autoload-internal cleanup).
	_ensure_xr_rig().release_physical_crouch()















func _ray_quad_intersection(ray_origin: Vector3, ray_dir: Vector3, quad: MeshInstance3D) -> Vector3:
	return _ensure_hud_watch().ray_quad_intersection(ray_origin, ray_dir, quad)



func _attach_rig_to_camera() -> void:
	_ensure_xr_rig().attach_rig_to_camera()



func _on_level_transition() -> void:
	# Reset state that depends on game scene nodes (freed during level change).
	_level_transition_count += 1
	_log("[VR Mod] Level transition #", _level_transition_count, " — resetting scene-dependent state")
	# Save weapon slot/hand so we can re-take control after the new scene loads.
	if _holster_state != HolsterState.UNARMED and _weapon_slot > 0:
		_transition_slot = _weapon_slot
		_transition_hand = _weapon_hand if _weapon_hand != "" else _config_dominant_hand
		_log("[VR Mod] Saving pre-transition state: slot=", _transition_slot, " hand=", _transition_hand)
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
	_recoil_rest_inv = Transform3D.IDENTITY
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
	var _nvg_sys = _ensure_nvg()
	_nvg_sys.nvg_active = false
	if _nvg_sys.nvg_overlay_mesh:
		_nvg_sys.nvg_overlay_mesh.visible = false
	_cached_mgr = null
	_nvg_sys.cached_nvg_overlay = null
	_release_physical_crouch()

	# Re-assert XR. Clear game_camera env/attributes on transition so the new
	# level's camera doesn't re-introduce glow/DOF. We do NOT force current=false —
	# game_camera must stay current for decal-pool LOD to work correctly.
	get_viewport().use_xr = true
	if game_camera:
		game_camera.environment = null
		game_camera.attributes = null
	_log("[VR Mod] Level transition: XR re-asserted, game camera env cleared")

	_log("Level transition reset complete, camera at " + str(game_camera.global_position))


func _on_main_menu_entered() -> void:
	_log("[VR Mod] Main menu detected — VR stays active, polling for game camera")
	_holster_state = HolsterState.UNARMED
	_weapon_slot = 0
	_weapons_reparented = false
	_weapon_loaded = false
	_grabbed_object = null
	_grab_hand = ""
	_action_open = false
	_pump_gesture_active = false
	var _nvg_sys2 = _ensure_nvg()
	_nvg_sys2.nvg_active = false
	if _nvg_sys2.nvg_overlay_mesh:
		_nvg_sys2.nvg_overlay_mesh.visible = false
	_cached_mgr = null
	_nvg_sys2.cached_nvg_overlay = null
	_clear_grenade_state()
	_esc_menu_active = false
	_teardown_watch_content()
	_cleanup_scope()
	_camera_lost_frames = 0
	_in_menu_mode = true
	# Menu needs visible cursor so warp_mouse() actually moves the click position.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_log("Main menu mode entered")
	if xr_camera:
		xr_camera.current = true
	_show_config_reminder()

func _show_config_reminder() -> void:
	if not _config_reminder_label or not is_instance_valid(_config_reminder_label) or not xr_camera:
		return
	var cam_pos = xr_camera.global_position
	var cam_forward = -xr_camera.global_basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	var pos = cam_pos + cam_forward * _menu_distance
	pos += xr_camera.global_basis.x * _menu_lr_offset
	pos.y = cam_pos.y + _hud_height_offset + 0.8
	_config_reminder_label.global_position = pos
	_config_reminder_label.look_at(cam_pos, Vector3.UP)
	_config_reminder_label.rotate_y(deg_to_rad(180))
	_config_reminder_label.visible = true

func _anchor_config_reminder() -> void:
	if not _config_reminder_label or not is_instance_valid(_config_reminder_label):
		return
	var parent = _config_reminder_label.get_parent()
	if parent:
		parent.remove_child(_config_reminder_label)
	get_tree().root.add_child(_config_reminder_label)
	_show_config_reminder()
	_config_reminder_label.visible = _in_menu_mode

func _sync_origin_to_game() -> void:
	_ensure_xr_rig().sync_origin_to_game()



func _steer_decor_camera_to_controller() -> void:
	_ensure_decor().steer_decor_camera_to_controller()






func _turn_origin(angle_deg: float) -> void:
	_ensure_xr_rig().turn_origin(angle_deg)



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
					_log("[VR Mod] DECOR: Place (G pressed)")
			"ax_button":
				if hand == "right":
					# A button = surface magnet toggle (left click)
					_inject_mouse_button(MOUSE_BUTTON_LEFT, true)
					_inject_mouse_button(MOUSE_BUTTON_LEFT, false)
					_log("[VR Mod] DECOR: Surface magnet toggled")
				elif hand == "left" and not _is_decor_placing():
					# X button = exit decor mode (blocked while placing)
					_toggle_decor_mode()
			"by_button":
				if hand == "left":
					# Y button = furniture inventory (Tab)
					# Single dispatch only — _inject_key double-sends (parse+push_input)
					# which toggles the furniture inventory open then immediately closed.
					_tab_single_press()
					_log("[VR Mod] DECOR: Furniture inventory (Tab)")
				elif hand == "right":
					# B button = store item to furniture inventory (middle mouse)
					_inject_mouse_button(MOUSE_BUTTON_MIDDLE, true)
					_inject_mouse_button(MOUSE_BUTTON_MIDDLE, false)
					_log("[VR Mod] DECOR: Store to furniture inv (middle click)")
			"grip_click":
				# Both grips = exit decor mode (blocked while placing)
				if _left_grip_held and _right_grip_held and not _is_decor_placing():
					_toggle_decor_mode()
				# Single right grip = toggle distance/rotation mode via Placer.rotateMode
				elif hand == "right":
					var _dec2 = _ensure_decor()
					_dec2.scroll_mode = 1 - _dec2.scroll_mode
					var placer = game_camera.get_node_or_null("Placer") if game_camera else null
					if placer:
						placer.set("rotateMode", _dec2.scroll_mode == 1)
					var mode_name = "ROTATION" if _dec2.scroll_mode == 1 else "DISTANCE"
					_log("[VR Mod] DECOR: Scroll mode -> " + mode_name)
					right_controller.trigger_haptic_pulse("haptic", 0.0, 0.2, 0.1, 0.0)
			"menu_button":
				_toggle_esc_menu()
		return  # Don't fall through to normal input handling

	# In decor mode with furniture inventory open, Y still maps to TAB (not player inventory)
	if _decor_mode and _interface_open and button_name == "by_button" and hand == "left":
		_tab_single_press()
		return

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
					_log("[VR Mod] NVG toggled (trigger above head)")
				elif is_weapon_hand and _holster_state == HolsterState.DRAWN and not (_weapon_uses_r_reload and _action_open):
					if _weapon_slot == 4:
						var _gren = _ensure_grenade()
						if not _gren.pin_pulled:
							# Grenade: tap fire = pull pin (game click 1).
							# Module owns the press, the release timer, the haptic,
							# and the log line.
							_gren.pull_pin()
						else:
							# Second trigger: right click = replace pin (cancel)
							_gren.replace_pin()
							_log("[VR Mod] Grenade pin replaced")
					else:
						# Non-grenade weapons: fire via mouse button only.
						# inject_mouse_button already triggers "fire"/"left_mouse" actions
						# via Godot's InputMap — the extra action_press/inject_action calls
						# send redundant fire signals to the game's _input() handler.
						_fire_trigger_held = true
						_mouse_states.erase(MOUSE_BUTTON_LEFT)
						_inject_mouse_button(MOUSE_BUTTON_LEFT, true)
				elif is_weapon_hand and _holster_state == HolsterState.LOWERED and _weapon_subtype == "Bolt":
					# Bolt-action: trigger while weapon lowered cycles the bolt (R)
					_inject_action("reload", true)
					_inject_action("reload", false)
					_log("[VR Mod] BOLT CYCLED (dominant trigger, LOWERED)")
					var bolt_ctrl = _get_controller(_weapon_hand)
					if bolt_ctrl:
						bolt_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.1, 0.0)
					_raise_weapon()
				elif is_support_hand and _holster_state in [HolsterState.DRAWN, HolsterState.LOWERED]:
					# Support hand trigger = rail slide / reload / laser (drawn or lowered)
					if _rail_mode:
						_start_rail_slide()  # rail mode is always exited on lower/holster, so only reached when DRAWN
					elif _support_grip_held and not _weapon_uses_r_reload:
						_inject_key(KEY_T, true)
						_inject_key(KEY_T, false)
						_log("[VR Mod] LASER toggled (support trigger + grip)")
					else:
						if _weapon_uses_r_reload and _action_open:
							# Action open: support trigger loads one round/shell (LMB)
							_inject_mouse_button(MOUSE_BUTTON_LEFT, true)
							_inject_mouse_button(MOUSE_BUTTON_LEFT, false)
							_log("[VR Mod] LOAD AMMO (support trigger, action open)")
						else:
							# Start long-press timer — short = reload, long = ammo check (KEY_V)
							_support_trigger_pending = true
							_support_trigger_press_time = Time.get_ticks_msec() / 1000.0
		"grip_click":
			if _interface_open:
				if is_support_hand:
					_menu_ctrl_held = true
					_inject_key(KEY_CTRL, true)
					_log("[VR Mod] MENU: Ctrl held (fast transfer mode)")
				else:
					_inject_mouse_button(MOUSE_BUTTON_RIGHT, true)
					_inject_action("context", true)
			elif _decor_mode:
				return
			elif _holster_cooldown > 0.0:
				_log("[VR Mod] Grip blocked - holster cooldown (" + str(snappedf(_holster_cooldown, 0.01)) + "s remaining)")
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
									_log("[VR Mod] Support grip: two-hand aim ON")
								else:
									_log("[VR Mod] Support grip ignored — short weapon, no two-hand aim")
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
					_ensure_weapon_sync().fg_grip_captured = false
					_fg_adjust_mode = false
					_log("[VR Mod] === FG ADJUST MODE OFF (discarded) ===")
				elif _adjust_mode:
					# X again = discard changes and exit
					_set_weapon_grip_offset(_adjust_saved_offset)
					_set_weapon_grip_rotation(_adjust_saved_rotation)
					_adjust_mode = false
					_log("[VR Mod] === ADJUST MODE OFF (discarded) ===")
				elif _holster_state == HolsterState.DRAWN:
					# Start long-press detection — will resolve on release or timeout
					_rail_x_pending = true
					_rail_x_press_time = Time.get_ticks_msec() / 1000.0
				elif _interface_open:
					# X = rotate dragged item (R key); flashlight/decor disabled while menu is open
					_inject_key(KEY_R, true)
					_inject_key(KEY_R, false)
					_log("[VR Mod] INVENTORY: Rotate item (R)")
				else:
					# X button when unarmed/lowered: long-press (0.5s) = decor mode, short-press = flashlight
					var _dec3 = _ensure_decor()
					_dec3.x_pending = true
					_dec3.x_press_time = Time.get_ticks_msec() / 1000.0
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
						_log("[VR Mod] FG ADJUST saved ", _current_weapon_name, ": p=", snapped(fg_p.x, 0.001), ",", snapped(fg_p.y, 0.001), ",", snapped(fg_p.z, 0.001))
					_ensure_weapon_sync().fg_grip_captured = false
					_fg_adjust_mode = false
					_save_grip_config()
					_log("[VR Mod] === FG ADJUST MODE OFF (saved) ===")
				elif _adjust_mode:
					_save_grip_config()
					_adjust_mode = false
					_log("[VR Mod] === ADJUST MODE OFF (saved) ===")
				elif _config_screen_open:
					_inject_config_click(true)
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
						_log("[VR Mod] ACTION ", "OPENED" if _action_open else "CLOSED", " (B, Ctrl)")
					else:
						_inject_key(KEY_F, true)
						_inject_key(KEY_F, false)
						_log("[VR Mod] FIRE MODE toggled (B button)")
				else:
					_inject_action("interact", true)
		"menu_button":
			_toggle_esc_menu()
		"primary_click":
			if hand == "left":
				_left_stick_held = true
				if not _right_stick_held:
					_inject_action("sprint", true)
			else:
				_right_stick_held = true
				if not _physical_crouch_active and not _left_stick_held:
					_inject_action("crouch", true)
			if _left_stick_held and _right_stick_held:
				# Both sticks = toggle config screen; cancel any in-flight actions first
				_inject_action("sprint", false)
				_inject_action("crouch", false)
				_toggle_config_screen()
				return


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
					_fire_trigger_held = false
					_inject_mouse_button(MOUSE_BUTTON_LEFT, false)
				else:
					if _rail_active:
						_end_rail_slide()
					elif _support_trigger_pending:
						# Short press: do reload tap now
						_support_trigger_pending = false
						_inject_action("reload", true)
						_inject_action("reload", false)
						_log("[VR Mod] RELOAD (support trigger short-press)")
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
					_log("[VR Mod] MENU: Ctrl released")
				else:
					_inject_mouse_button(MOUSE_BUTTON_RIGHT, false)
					_inject_action("context", false)
			elif _decor_mode:
				return
			else:
				if hand == _weapon_hand and _holster_state == HolsterState.DRAWN:
					if _weapon_slot == 4 and _ensure_grenade().pin_pulled:
						# Pin pulled: tap fire = throw (game click 2)
						_ensure_grenade().throw_tap()
						_log("[VR Mod] Grenade thrown (grip release)")
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
						_log("[VR Mod] === FG ADJUST MODE OFF (support released) ===")
					_log("[VR Mod] Support grip: two-hand aim OFF")
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
								_ensure_weapon_sync().fg_grip_captured = false
								if _cached_weapon_rig and is_instance_valid(_cached_weapon_rig):
									_fg_adjust_frozen_xform = _cached_weapon_rig.global_transform
								_log("[VR Mod] === FG ADJUST MODE ON (slot ", _weapon_slot, ") ===")
								_log("[VR Mod] Gun frozen. Move support hand to foregrip, then A=Save, X=Discard")
							else:
								# Main hand only — enter grip adjust mode
								_adjust_mode = true
								_adjust_saved_offset = _get_weapon_grip_offset()
								_adjust_saved_rotation = _get_weapon_grip_rotation()
								_log("[VR Mod] === ADJUST MODE ON (slot ", _weapon_slot, ") ===")
								_log("[VR Mod] Left stick=X/Y, Right stick X=Z Y=Rotation")
								_log("[VR Mod] A=Save, X=Discard")
				else:
					var _dec4 = _ensure_decor()
					if _dec4.x_pending:
						_dec4.x_pending = false
						# Short press — toggle flashlight
						_inject_mouse_button(MOUSE_BUTTON_XBUTTON2, true)
						_inject_mouse_button(MOUSE_BUTTON_XBUTTON2, false)
						_log("[VR Mod] FLASHLIGHT toggled (X short-press)")
			elif hand == "right":
				if _config_screen_open:
					_inject_config_click(false)
				else:
					_inject_action("jump", false)
		"by_button":
			if hand == "left":
				if not _decor_mode:
					_inject_action("interface", false)
			else:
				if _holster_state != HolsterState.DRAWN:
					_inject_action("interact", false)
		"menu_button":
			pass  # ESC release handled by _toggle_esc_menu
		"primary_click":
			if hand == "left":
				_left_stick_held = false
				_inject_action("sprint", false)
			else:
				_right_stick_held = false
				if not _physical_crouch_active:
					_inject_action("crouch", false)


var _key_states := {}
var _mouse_states := {}

func _tab_single_press() -> void:
	# Send TAB press+release via push_input only (not parse_input_event).
	# _inject_key sends both; parse_input_event re-fires the toggle handler a second time,
	# opening then immediately closing the furniture inventory.
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.physical_keycode = KEY_TAB
	ev.pressed = true
	get_viewport().push_input(ev, false)
	ev.pressed = false
	get_viewport().push_input(ev, false)

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
			_log("[VR Mod] Action not found: ", action_name)
		return
	var event = InputEventAction.new()
	event.action = action_name
	event.pressed = pressed
	event.strength = strength if pressed else 0.0
	Input.parse_input_event(event)


func _extract_hand_assets_from_vmz() -> bool:
	return _ensure_hands().extract_hand_assets_from_vmz()


func _create_hand_model(controller: XRController3D, model_name: String) -> void:
	_ensure_hands().create_hand_model(controller, model_name)







func _create_watch_mesh() -> void:
	_ensure_hud_watch().create_watch_mesh()



func _destroy_watch_mesh() -> void:
	_ensure_hud_watch().destroy_watch_mesh()



func _setup_watch_content() -> void:
	_ensure_hud_watch().setup_watch_content()









func _teardown_watch_content() -> void:
	_ensure_hud_watch().teardown_watch_content()



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
		get_tree().create_timer(KEY_TAP_RELEASE_SEC).timeout.connect(func(): Input.parse_input_event(ev_release))
		_log("[VR Mod] Menu button: closing open interface screen")
	elif not _esc_menu_active:
		_esc_menu_active = true
		_key_states.erase(KEY_ESCAPE)
		Input.parse_input_event(ev_press)
		# No release — menu stays open until next press.
		_log("[VR Mod] ESC menu opened")
	else:
		_esc_clear_hover()
		_esc_menu_active = false
		_key_states.erase(KEY_ESCAPE)
		Input.parse_input_event(ev_press)
		get_tree().create_timer(KEY_TAP_RELEASE_SEC).timeout.connect(func(): Input.parse_input_event(ev_release))
		_log("[VR Mod] ESC menu closed (menu button)")






func _clear_grenade_state() -> void:
	# Genuine integration boundary: 5 cross-module call sites (holster x4 +
	# weapon_sync x1) go through this wrapper for the side-effect cleanup.
	_ensure_grenade().clear_state()













func _hand_laser_sees_grabbable(hand: String) -> bool:
	return _ensure_grab().hand_laser_sees_grabbable(hand)



func _try_grab(hand: String) -> void:
	_ensure_grab().try_grab(hand)



func _drop_grabbed() -> void:
	_ensure_grab().drop_grabbed()



func _pickup_to_inventory() -> void:
	_ensure_grab().pickup_to_inventory()






func _collect_arms_meshes(node: Node, out: Array) -> void:
	_ensure_weapon_sync().collect_arms_meshes(node, out)



func _ensure_weapon_cache(weapon_rig: Node3D) -> Dictionary:
	return _ensure_weapon_sync().ensure_weapon_cache(weapon_rig)



func _hide_arms_in_subtree(weapon_rig: Node3D) -> void:
	_ensure_weapon_sync().hide_arms_in_subtree(weapon_rig)



func _weapon_key() -> String:
	return _ensure_weapon_sync().weapon_key()



func _get_weapon_grip_offset() -> Vector3:
	return _ensure_weapon_sync().get_weapon_grip_offset()



func _get_weapon_grip_rotation() -> float:
	return _ensure_weapon_sync().get_weapon_grip_rotation()



func _set_weapon_grip_offset(v: Vector3) -> void:
	_ensure_weapon_sync().set_weapon_grip_offset(v)



func _set_weapon_grip_rotation(v: float) -> void:
	_ensure_weapon_sync().set_weapon_grip_rotation(v)



func _has_weapon_fg_p() -> bool:
	return _ensure_weapon_sync().has_weapon_fg_p()



func _get_weapon_fg_p() -> Vector3:
	return _ensure_weapon_sync().get_weapon_fg_p()



func _get_weapon_fg_r() -> Basis:
	return _ensure_weapon_sync().get_weapon_fg_r()



func _set_weapon_fg_p(v: Vector3) -> void:
	_ensure_weapon_sync().set_weapon_fg_p(v)



func _set_weapon_fg_r(v: Basis) -> void:
	_ensure_weapon_sync().set_weapon_fg_r(v)






func _apply_sway_to_hands(weapon_rig: Node3D, dom_ctrl: XRController3D, sup_ctrl: XRController3D, aim_basis: Basis, local_offset: Vector3, recoil_delta: Transform3D, use_two_hand: bool, arc_comp: Vector3) -> void:
	_ensure_weapon_sync().apply_sway_to_hands(weapon_rig, dom_ctrl, sup_ctrl, aim_basis, local_offset, recoil_delta, use_two_hand, arc_comp)



func _sync_weapon_to_sling(weapon_rig: Node3D) -> void:
	_ensure_weapon_sync().sync_weapon_to_sling(weapon_rig)



func _sample_recoil_chain(weapon_rig: Node3D) -> Transform3D:
	return _ensure_weapon_sync().sample_recoil_chain(weapon_rig)



func _walk_chain_node(weapon_rig: Node3D, node_name: String) -> Node3D:
	return _ensure_weapon_sync().walk_chain_node(weapon_rig, node_name)



func _suppress_walk_sway(weapon_rig: Node3D) -> void:
	_ensure_weapon_sync().suppress_walk_sway(weapon_rig)



func _is_transition_node(node: Node) -> bool:
	for g in node.get_groups():
		var gl := g.to_lower()
		if gl in ["leveltransition", "zonetransition", "levelexit", "zoneexit", "exit", "transition"]:
			return true
	if node.get_script() != null:
		var sp: String = node.get_script().resource_path
		if "LevelTransition" in sp or "LevelExit" in sp or "ZoneTransition" in sp or "ZoneExit" in sp:
			return true
	var nl := node.name.to_lower()
	if "leveltransition" in nl or "levelexit" in nl or "zonetransition" in nl or "zoneexit" in nl:
		return true
	return false


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


func _log(arg0 = "", arg1 = null, arg2 = null, arg3 = null, arg4 = null, arg5 = null, arg6 = null, arg7 = null) -> void:
	var msg := str(arg0)
	if arg1 != null: msg += str(arg1)
	if arg2 != null: msg += str(arg2)
	if arg3 != null: msg += str(arg3)
	if arg4 != null: msg += str(arg4)
	if arg5 != null: msg += str(arg5)
	if arg6 != null: msg += str(arg6)
	if arg7 != null: msg += str(arg7)
	var path = _log_path
	var f = FileAccess.open(path, FileAccess.READ_WRITE)
	if not f:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.seek_end(0)
		f.store_line(msg)
		f.close()


# One-shot error logger for production-visible failures (missing nodes, etc).
# Subsequent calls with the same key are silently ignored, so repeated per-frame
# failures don't flood the log. Keys persist for the autoload's lifetime.
var _log_missing_once_seen := {}
func _log_missing_once(key: String, msg: String) -> void:
	if _log_missing_once_seen.has(key):
		return
	_log_missing_once_seen[key] = true
	_log("[missing] ", key, ": ", msg)


func _fix_reticle_parallax(weapon_rig: Node3D) -> void:
	_ensure_scope_pip().fix_reticle_parallax(weapon_rig)



func _patch_reticle_shader(node: Node) -> void:
	_ensure_scope_pip().patch_reticle_shader(node)



func _find_node_by_class(root: Node, class_name_str: String) -> Node:
	if root.get_class() == class_name_str or root.is_class(class_name_str):
		return root
	for child in root.get_children():
		var found = _find_node_by_class(child, class_name_str)
		if found:
			return found
	return null


func _setup_scope_pip(weapon_rig: Node3D) -> void:
	_ensure_scope_pip().setup_scope_pip(weapon_rig)



func _update_scope_camera() -> void:
	_ensure_scope_pip().update_scope_camera()



func _cycle_scope_zoom(direction: int) -> void:
	_ensure_scope_pip().cycle_scope_zoom(direction)


func _scope_zoom_branch_eligible() -> bool:
	# Used by _process_input's right-stick-Y branch to decide between scope
	# zoom cycling and snap/smooth turn. Migrated to a helper so the input
	# handler does not have to reach into ScopePip's fields directly.
	var sp = _ensure_scope_pip()
	return sp.active and sp.is_variable and _holster_state == HolsterState.DRAWN



func _cleanup_scope() -> void:
	_ensure_scope_pip().cleanup_scope()



func _enter_rail_mode() -> void:
	_rail_mode = true
	_adjust_mode = false      # Cancel adjust mode if somehow active
	_fg_adjust_mode = false   # Cancel foregrip adjust mode if somehow active
	var ctrl = _get_controller(_get_support_hand())
	if ctrl:
		ctrl.trigger_haptic_pulse("haptic", 0.0, 0.4, 0.15, 0.0)
	_log("[VR Mod] === RAIL MODE ON ===")

func _exit_rail_mode() -> void:
	if _rail_active:
		_end_rail_slide()
	_rail_mode = false
	_rail_x_pending = false
	_log("[VR Mod] === RAIL MODE OFF ===")

func _start_rail_slide() -> void:
	_rail_active = true
	_rail_scroll_accum = 0.0
	# Record off-hand position projected onto weapon forward axis
	var support_ctrl = _get_controller(_get_support_hand())
	if support_ctrl and game_camera:
		_rail_fwd = -game_camera.global_basis.z
		_rail_grab_origin = support_ctrl.global_position.dot(_rail_fwd)
	_inject_key(KEY_CTRL, true)
	if support_ctrl:
		support_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.3, 0.1, 0.0)
	_log("[VR Mod] Rail slide started (trigger grab)")

func _end_rail_slide() -> void:
	_rail_active = false
	_inject_key(KEY_CTRL, false)
	_rail_scroll_accum = 0.0
	_log("[VR Mod] Rail slide ended")

func _reparent_camera_children() -> void:
	_ensure_xr_rig().reparent_camera_children()



func _find_game_camera(node: Node) -> Camera3D:
	return _ensure_xr_rig().find_game_camera(node)



func _load_config() -> void:
	var data: Variant = _ensure_config_io().read()
	if not (data is Dictionary):
		return
	# Apply each section to autoload state. Anything unknown is left untouched
	# so the file round-trips cleanly through _save_full_config().
	if data.has("xr"):
		world_scale = data["xr"].get("world_scale", 1.0)
		_render_scale = data["xr"].get("render_scale", 1.0)
		_mouse_sens_estimate = data["xr"].get("mouse_sens", 0.003)
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
		_move_direction_mode = data["controls"].get("move_direction_mode", "camera")
		_move_direction_hand = data["controls"].get("move_direction_hand", "left")
		_holster_zones_mirrored = data["controls"].get("holster_zones_mirrored", false)
		_auto_recenter_enabled = data["controls"].get("auto_recenter", true)
	if data.has("holsters"):
		_holster_zone_radius = data["holsters"].get("zone_radius", 0.27)
		_holster_holos_enabled = data["holsters"].get("holos_enabled", true)
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
	if data.has("resume"):
		_resume_slot = data["resume"].get("slot", 0)
		_resume_hand = data["resume"].get("hand", "")
	_log("[VR Mod] Config loaded successfully")


func _save_grip_config() -> void:
	if not _ensure_config_io().mutate(_grip_config_mutator):
		return
	_log("[VR Mod] Grip config saved to: ", _config_path)
	for wname in _weapon_grip_offsets:
		var o = _weapon_grip_offsets[wname]
		_log("[VR Mod]   " + str(wname)
			+ ": grip x=" + str(snapped(o.x, 0.001))
			+ " y=" + str(snapped(o.y, 0.001))
			+ " z=" + str(snapped(o.z, 0.001))
			+ " rot=" + str(snapped(_weapon_grip_rotations.get(wname, 0.0), 0.1))
			+ " deg foregrip_configured=" + str(_weapon_fg_p_local.has(wname)))


func _grip_config_mutator(data: Dictionary) -> void:
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
	_ensure_config_ui().toggle_config_screen()




func _apply_hud_spread() -> void:
	_ensure_config_ui().apply_hud_spread()


func _inject_config_click(pressed: bool) -> void:
	_ensure_config_ui().inject_config_click(pressed)


func _scroll_config_panel(amount: float) -> void:
	_ensure_config_ui().scroll_config_panel(amount)


func _patch_resume_state(slot: int, hand: String) -> void:
	_ensure_config_ui().patch_resume_state(slot, hand)


func _save_full_config() -> void:
	_ensure_config_ui().save_full_config()


func _watch_rot_basis() -> Basis:
	return _ensure_config_ui().watch_rot_basis()




# ── Bullet hole pool trim (Forward Mobile renders max ~8 decals per mesh) ──
# SceneTree.node_added fires synchronously inside Hit.gd's add_child() call,
# so by the time we run the parent already has the new wrapper as a child.

func _on_bullet_hole_node_added(node: Node) -> void:
	if not node.name.begins_with("@"):
		return
	var parent = node.get_parent()
	if parent == null or not (parent is StaticBody3D):
		return
	_trim_body_decals(parent)


func _trim_body_decals(body: StaticBody3D) -> void:
	var visible_holes := []
	for ch in body.get_children():
		if ch.name.begins_with("@") and ch.visible:
			visible_holes.append(ch)
	while visible_holes.size() > 8:
		visible_holes[0].visible = false
		visible_holes.remove_at(0)


# ── Weapon tree debug dump (F10) ──────────────────────────────────────────

# F9-F12 dispatch wrappers — kept because _unhandled_input calls them by
# name. The leaf helpers (snapshot_tree/dump_*_node/etc.) are subsystem-
# internal; they used to have wrappers here but those were dead and have
# been removed.

func _dump_weapon_tree() -> void:
	_ensure_diagnostics().dump_weapon_tree()


func _dump_ray_target() -> void:
	_ensure_diagnostics().dump_ray_target()


func _dump_hud_tree() -> void:
	_ensure_diagnostics().dump_hud_tree()


func _dump_nvg_and_environment() -> void:
	_ensure_diagnostics().dump_nvg_and_environment()
