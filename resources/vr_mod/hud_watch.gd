extends RefCounted

# hud_watch.gd
# VR HUD setup (SubViewport+QuadMesh sharing the game's World2D), wrist-watch
# crop logic, glance-to-reveal fade, ammo check panel, world-fixed menu/inventory
# panel handoff, smooth-follow yaw, and the laser pointer that drives all of it.
# State (hud_viewport, _watch_*, _hud_yaw, etc.) stays on the autoload.

var autoload: Node

# Subsystem-owned state. Watch-specific scene refs and crop-state machine
# live here. The hud_mesh / hud_viewport themselves and the broadly-tunable
# _hud_yaw / _hud_spread_active stay on the autoload because the F8 panel
# layout helpers and other systems read them.
var watch_b_vp: SubViewport = null     # Second viewport for Medical element
var watch_alpha: float = 0.0           # Fade alpha (0=hidden, 1=visible)
var watch_crop_computed: bool = false
var watch_crop_delay: int = 0          # Countdown frames before reading node rects
var watch_crop_retries: int = 0
var vitals_node: Control = null        # game HUD node ref (not reparented)
var medical_node: Control = null       # game HUD node ref (not reparented)


func _init(p_autoload: Node) -> void:
	autoload = p_autoload


func process(frame: Dictionary, delta: float) -> void:
	# HUD/watch per-frame work:
	#  * one-shot HUD setup (delayed HUD_SETUP_DELAY frames after rig install)
	#  * support-trigger long-press -> ammo check (KEY_V) + ammo panel timers
	#  * interface open/close detection, smooth follow, watch glance fade,
	#    delayed crop computation set up by setup_watch_content().
	_setup_vr_hud_when_ready()
	_tick_support_trigger_long_press()
	_tick_ammo_panel(delta)
	update_interface_state()
	update_smooth_hud(delta)
	if not frame.get("interface_open", false):
		update_watch_glance(delta)
	if watch_crop_delay > 0:
		watch_crop_delay -= 1
		if watch_crop_delay == 0:
			compute_watch_crop()


func _setup_vr_hud_when_ready() -> void:
	if autoload._hud_installed or autoload._frames_waited < autoload.HUD_SETUP_DELAY:
		return
	setup_vr_hud()
	if autoload._in_menu_mode:
		# Force on_interface_opened() to re-fire now that hud_mesh exists.
		autoload._prev_interface_open = false


func _tick_support_trigger_long_press() -> void:
	# Support trigger held >= 0.5 s = ammo check (KEY_V tap + haptic blip).
	if not autoload._support_trigger_pending:
		return
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - autoload._support_trigger_press_time
	if elapsed < 0.5:
		return
	autoload._support_trigger_pending = false
	autoload._inject_key(KEY_V, true)
	autoload._inject_key(KEY_V, false)
	var support_ctrl = autoload._get_controller(autoload._get_support_hand())
	if support_ctrl:
		support_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.2, 0.1, 0.0)
	autoload._ammo_read_delay = 3
	autoload._log("[VR Mod] AMMO CHECK (support trigger long-press)")


func _tick_ammo_panel(delta: float) -> void:
	# Two-stage countdown: read_delay frames first (waits for the game to refresh
	# its ammo labels after KEY_V), then ammo_check_timer keeps the panel
	# visible and tracking the weapon hand.
	if autoload._ammo_read_delay > 0:
		autoload._ammo_read_delay -= 1
		if autoload._ammo_read_delay == 0:
			show_ammo_check_panel()
	if autoload._ammo_check_timer > 0.0:
		autoload._ammo_check_timer -= delta
		if autoload._ammo_check_timer <= 0.0:
			hide_ammo_check_panel()
		elif autoload._ammo_panel_mesh and is_instance_valid(autoload._ammo_panel_mesh) and autoload.xr_camera:
			update_ammo_panel_position()


func setup_vr_hud() -> void:
	autoload._log("[VR Mod] Setting up VR HUD (World2D sharing)...")

	var main_vp = autoload.get_viewport()
	var vp_size = main_vp.get_visible_rect().size
	var win_size_for_log = DisplayServer.window_get_size()
	var win := autoload.get_window()
	var cs_size = win.content_scale_size if win else Vector2i.ZERO
	autoload._log("HUD sizes: visible_rect=" + str(vp_size) + " win=" + str(win_size_for_log) + " content_scale=" + str(cs_size) + " canvas_xform=" + str(main_vp.canvas_transform) + " global_canvas_xform=" + str(main_vp.global_canvas_transform))
	var ui_node = autoload.get_tree().root.get_node_or_null("Map/Core/UI")
	if ui_node:
		autoload._log("[VR Mod] UI node: ", ui_node.get_path(), " vis=", ui_node.visible)

	autoload.hud_viewport = SubViewport.new()
	autoload.hud_viewport.name = "VRHudViewport"
	autoload.hud_viewport.size = Vector2i(int(vp_size.x), int(vp_size.y))
	autoload.hud_viewport.transparent_bg = true
	autoload.hud_viewport.disable_3d = true
	autoload.hud_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	autoload.hud_viewport.world_2d = main_vp.world_2d
	autoload.hud_viewport.gui_disable_input = true
	# Exclude canvas visibility layer 16 - Effects (Sharpen etc.) are moved there
	# so their screen-space shaders don't sample our empty SubViewport and go black.
	autoload.hud_viewport.canvas_cull_mask = 0xFFFFFFFF ^ (1 << 16)
	autoload.add_child(autoload.hud_viewport)

	# Second viewport for Medical element - same setup, separate canvas_transform
	watch_b_vp = SubViewport.new()
	watch_b_vp.name = "VRWatchMedVP"
	watch_b_vp.size = Vector2i(int(vp_size.x), int(vp_size.y))
	watch_b_vp.transparent_bg = true
	watch_b_vp.disable_3d = true
	watch_b_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	watch_b_vp.world_2d = main_vp.world_2d
	watch_b_vp.gui_disable_input = true
	watch_b_vp.canvas_cull_mask = 0xFFFFFFFF ^ (1 << 16)
	autoload.add_child(watch_b_vp)

	autoload.hud_mesh = MeshInstance3D.new()
	autoload.hud_mesh.name = "VRHudPanel"

	var quad = QuadMesh.new()
	var aspect = float(autoload.hud_viewport.size.y) / float(autoload.hud_viewport.size.x)
	quad.size = Vector2(autoload._hud_width, autoload._hud_width * aspect)
	autoload.hud_mesh.mesh = quad

	var mat = StandardMaterial3D.new()
	mat.albedo_texture = autoload.hud_viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 10
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	autoload.hud_mesh.material_override = mat

	# Put HUD on layer 20 only so NVG mono camera doesn't render it
	autoload.hud_mesh.layers = (1 << 19)

	# Park hud_mesh invisibly under self - watch takes over during gameplay
	autoload.hud_mesh.visible = false
	autoload.add_child(autoload.hud_mesh)

	autoload._hud_installed = true

	# Set compact spread, set up dedicated watch content VP, then create watch mesh
	autoload._hud_spread_active = autoload._watch_spread
	autoload._apply_hud_spread()
	setup_watch_content()
	autoload._log("HUD viewport ready, creating watch mesh...")
	create_watch_mesh()
	if autoload._watch_mesh:
		autoload._log("Watch mesh created OK, visible=" + str(autoload._watch_mesh.visible) + " layers=" + str(autoload._watch_mesh.layers))
	else:
		autoload._log("WARNING: watch mesh is null after _create_watch_mesh!")

	autoload._log("[VR Mod] VR HUD installed (wrist watch mode)")

	autoload._setup_nvg_overlay()

	autoload._log("[VR Mod] === VR fully active ===")


func create_watch_mesh() -> void:
	# Determine non-dominant hand
	var non_dom = "left" if autoload._config_dominant_hand == "right" else "right"
	var controller = autoload._get_controller(non_dom)
	if not controller:
		autoload._log("WARNING: non-dominant controller not found for watch")
		return

	# Use a dedicated mount Node3D with no rotation - avoids hand model rotation complexity
	# CRITICAL: Never add MeshInstance3D directly to XRController3D; always wrap in Node3D
	var mount = Node3D.new()
	mount.name = "WatchMount"
	controller.add_child(mount)

	autoload._watch_mesh = MeshInstance3D.new()
	autoload._watch_mesh.name = "WristWatch"

	var quad = QuadMesh.new()
	quad.size = Vector2(autoload._watch_size, autoload._watch_size)
	autoload._watch_mesh.mesh = quad

	# ShaderMaterial with UV crop + alpha fade
	var shader = Shader.new()
	shader.code = autoload.WATCH_CROP_SHADER
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("hud_texture", autoload.hud_viewport.get_texture())
	if watch_b_vp:
		mat.set_shader_parameter("medical_tex", watch_b_vp.get_texture())
	mat.set_shader_parameter("alpha", 0.0)
	mat.render_priority = 10
	autoload._watch_mesh.material_override = mat

	# Use layer 1 so it's definitely in the XR camera cull_mask
	autoload._watch_mesh.layers = 1

	autoload._watch_mesh.position = autoload._watch_offset
	autoload._watch_mesh.basis = autoload._watch_rot_basis()

	mount.add_child(autoload._watch_mesh)
	autoload._watch_mesh.visible = false
	autoload._log("Wrist watch installed on " + non_dom + " hand, mount at " + str(mount.get_path()))


func destroy_watch_mesh() -> void:
	if autoload._watch_mesh and is_instance_valid(autoload._watch_mesh):
		# Free the WatchMount parent too
		var mount = autoload._watch_mesh.get_parent()
		if mount and is_instance_valid(mount) and mount.name == "WatchMount":
			mount.queue_free()
		else:
			autoload._watch_mesh.queue_free()
	autoload._watch_mesh = null
	watch_alpha = 0.0
	teardown_watch_content()


func setup_watch_content() -> void:
	# Find Vitals and Medical in the game HUD
	var stats = autoload.get_tree().root.get_node_or_null("Map/Core/UI/HUD/Stats")
	if not stats:
		autoload._log("WARNING: HUD/Stats not found - watch will show full HUD texture")
		return

	vitals_node = stats.get_node_or_null("Vitals") as Control
	medical_node = stats.get_node_or_null("Medical") as Control

	if not vitals_node and not medical_node:
		autoload._log("WARNING: Neither Vitals nor Medical found - watch will show full HUD texture")
		return

	watch_crop_computed = false
	watch_crop_delay = 30
	watch_crop_retries = 0
	autoload._log("Watch: found Vitals=" + str(vitals_node != null) + " Medical=" + str(medical_node != null) + " - crop will be computed in 30 frames")


func compute_watch_crop() -> void:
	if not autoload.hud_viewport:
		return

	var vp_w = float(autoload.hud_viewport.size.x)
	var vp_h = float(autoload.hud_viewport.size.y)

	autoload._hud_spread_active = 1.0
	autoload._apply_hud_spread()

	var elem_w  = vp_w * 0.208
	var elem_h  = vp_h * 0.25
	var elem_top = vp_h - elem_h
	var vitals_cx  = vp_w * 0.25
	var medical_cx = vp_w * 0.75

	var vitals_rect  = Rect2(vitals_cx  - elem_w * 0.5, elem_top, elem_w, elem_h)
	var medical_rect = Rect2(medical_cx - elem_w * 0.5, elem_top, elem_w, elem_h)

	autoload._log("Watch crop: vitals=" + str(vitals_rect) + " medical=" + str(medical_rect))

	var sx = vp_w / elem_w
	var sy = vp_h / elem_h

	var tv = Transform2D()
	tv[0] = Vector2(sx, 0.0)
	tv[1] = Vector2(0.0, sy)
	tv[2] = Vector2(-vitals_rect.position.x * sx, -vitals_rect.position.y * sy)
	autoload.hud_viewport.canvas_transform = tv

	if watch_b_vp:
		var tm = Transform2D()
		tm[0] = Vector2(sx, 0.0)
		tm[1] = Vector2(0.0, sy)
		tm[2] = Vector2(-medical_rect.position.x * sx, -medical_rect.position.y * sy)
		watch_b_vp.canvas_transform = tm

	watch_crop_computed = true
	autoload._log("Watch crop scale=(" + str(snapped(sx, 0.01)) + "," + str(snapped(sy, 0.01)) + ")")

	# Move all Effects canvas items to visibility layer 16 so watch SubViewports
	# (which exclude layer 16 via canvas_cull_mask) don't render screen-space
	# effects that would sample the empty SubViewport and output black.
	var effects_node = autoload.get_node_or_null("/root/Map/Core/UI/Effects")
	if effects_node:
		set_canvas_visibility_recursive(effects_node, 1 << 16)

	if autoload._watch_mesh and is_instance_valid(autoload._watch_mesh):
		var stacked_aspect = elem_w / (elem_h * 2.0)
		var quad_w = clamp(autoload._watch_size * stacked_aspect, 0.02, 1.0)
		var quad_h = autoload._watch_size
		(autoload._watch_mesh.mesh as QuadMesh).size = Vector2(quad_w, quad_h)
		autoload._log("Watch quad: " + str(snapped(quad_w, 0.001)) + "m x " + str(snapped(quad_h, 0.001)) + "m (aspect " + str(snapped(stacked_aspect, 0.01)) + ")")


func set_canvas_visibility_recursive(node: Node, layer: int) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visibility_layer = layer
	for child in node.get_children():
		set_canvas_visibility_recursive(child, layer)


func teardown_watch_content() -> void:
	# Reset canvas_transforms so the floating menu HUD renders correctly
	if autoload.hud_viewport:
		autoload.hud_viewport.canvas_transform = Transform2D.IDENTITY
	if watch_b_vp:
		watch_b_vp.canvas_transform = Transform2D.IDENTITY
	vitals_node = null
	medical_node = null
	watch_crop_computed = false
	watch_crop_delay = 0
	watch_crop_retries = 0


func update_interface_state() -> void:
	# Check if any UI panel that's normally hidden is now visible
	autoload._interface_open = false
	var _detected_by := ""
	var ui_node = autoload.get_tree().root.get_node_or_null("Map/Core/UI")
	if ui_node:
		for child in ui_node.get_children():
			# Skip always-visible HUD elements
			if child.name in ["HUD", "Effects", "NVG"]:
				continue
			if child is CanvasItem and child.visible:
				autoload._interface_open = true
				_detected_by = "Map/Core/UI/" + child.name + " (" + child.get_class() + ")"
				break

	# Also check siblings of UI under Map/Core - ESC menu may live there
	if not autoload._interface_open:
		var core_node = autoload.get_tree().root.get_node_or_null("Map/Core")
		if core_node:
			for child in core_node.get_children():
				if child.name in ["Camera", "UI", "LOS", "Interactor"]:
					continue
				if child is CanvasItem and child.visible:
					autoload._interface_open = true
					_detected_by = "Map/Core/" + child.name + " (" + child.get_class() + ")"
					break

	if autoload._interface_open and not autoload._prev_interface_open:
		autoload._log("Interface opened: detected by " + _detected_by)

	# ESC menu always pauses the tree; inventory/loot pools do not.
	if autoload._esc_menu_active and not autoload.get_tree().paused:
		autoload._esc_menu_active = false
		autoload._esc_clear_hover()
	if autoload._esc_menu_active:
		autoload._interface_open = true

	# Main menu mode: no game scene, but show the HUD panel for the main menu UI
	if autoload._in_menu_mode:
		autoload._interface_open = true

	# Detect transitions
	if autoload._interface_open and not autoload._prev_interface_open:
		on_interface_opened()
	elif not autoload._interface_open and autoload._prev_interface_open:
		on_interface_closed()
	autoload._prev_interface_open = autoload._interface_open


func on_interface_opened() -> void:
	autoload._log("[VR Mod] Interface OPENED - switching to world-fixed mode")
	autoload._ammo_check_timer = 0.0
	cleanup_ammo_panel()
	autoload._laser_diag_logged = false
	autoload._laser_locked_pos = Vector2(-9999.0, -9999.0)
	if not autoload.hud_mesh:
		return

	# Hide watch during menus
	if autoload._watch_mesh:
		autoload._watch_mesh.visible = false
		watch_alpha = 0.0
		var wmat = autoload._watch_mesh.material_override as ShaderMaterial
		if wmat:
			wmat.set_shader_parameter("alpha", 0.0)

	# Restore normal spread and full canvas for floating menu
	autoload._hud_spread_active = autoload._hud_spread
	autoload._apply_hud_spread()
	if autoload.hud_viewport:
		autoload.hud_viewport.canvas_transform = Transform2D.IDENTITY
	if watch_b_vp:
		watch_b_vp.canvas_transform = Transform2D.IDENTITY

	# Detach hud_mesh from parked location and place in world space
	if autoload.hud_mesh.get_parent():
		autoload.hud_mesh.get_parent().remove_child(autoload.hud_mesh)

	# Place in front of camera at current look direction
	var cam_pos = autoload.xr_camera.global_position
	var cam_forward = -autoload.xr_camera.global_basis.z
	cam_forward.y = 0
	cam_forward = cam_forward.normalized()

	var menu_pos = cam_pos + cam_forward * autoload._menu_distance
	var cam_right = autoload.xr_camera.global_basis.x
	menu_pos += cam_right * autoload._menu_lr_offset
	menu_pos.y = cam_pos.y + autoload._hud_height_offset

	# Add to scene root so it's world-fixed
	autoload.get_tree().root.add_child(autoload.hud_mesh)
	autoload.hud_mesh.visible = true
	autoload.hud_mesh.global_position = menu_pos
	autoload.hud_mesh.look_at(cam_pos, Vector3.UP)
	autoload.hud_mesh.rotate_y(deg_to_rad(180))

	# Scale up for menu
	var aspect = float(autoload.hud_viewport.size.y) / float(autoload.hud_viewport.size.x)
	(autoload.hud_mesh.mesh as QuadMesh).size = Vector2(autoload._menu_width, autoload._menu_width * aspect)

	# Show laser pointer (restore to UI blue/full-length mode)
	autoload._menu_open = true
	if autoload._laser_mesh:
		var mat := autoload._laser_mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.2, 0.5, 1.0, 0.5)
		var cyl := autoload._laser_mesh.mesh as CylinderMesh
		if cyl:
			cyl.height = 5.0
			autoload._laser_mesh.position.z = -cyl.height / 2.0
		autoload._laser_mesh.visible = true

	autoload._log("[VR Mod] Menu placed at ", menu_pos)


func on_interface_closed() -> void:
	autoload._log("[VR Mod] Interface CLOSED - switching to wrist watch mode")
	if not autoload.hud_mesh:
		return

	# Restore spread=1.0 for watch (elements at known positions for crop)
	autoload._hud_spread_active = 1.0
	autoload._apply_hud_spread()
	if watch_crop_computed and autoload.hud_viewport:
		watch_crop_delay = 1
		watch_crop_retries = 0

	# Park hud_mesh invisibly - watch takes over during gameplay
	if autoload.hud_mesh.get_parent():
		autoload.hud_mesh.get_parent().remove_child(autoload.hud_mesh)
	autoload.hud_mesh.visible = false
	autoload.add_child(autoload.hud_mesh)

	# Release Ctrl modifier if held (support grip fast transfer)
	if autoload._menu_ctrl_held:
		autoload._menu_ctrl_held = false
		autoload._inject_key(KEY_CTRL, false)

	# Hide laser pointer and return to grab-range mode
	autoload._menu_open = false
	if autoload._laser_mesh and not autoload._config_screen_open:
		autoload._laser_mesh.visible = false


func show_ammo_check_panel() -> void:
	if not autoload.xr_camera:
		return

	# Read counts directly from game HUD labels
	var hud_node = autoload.get_tree().root.get_node_or_null("Map/Core/UI/HUD")
	var mag_text := "?"
	var chb_text := "?"
	if hud_node:
		var mag_lbl = hud_node.get_node_or_null("Magazine/Panel/Count")
		var chb_lbl = hud_node.get_node_or_null("Chamber/Panel/Count")
		if mag_lbl:
			mag_text = mag_lbl.text
		if chb_lbl:
			chb_text = chb_lbl.text

	cleanup_ammo_panel()

	autoload._ammo_panel_vp = SubViewport.new()
	autoload._ammo_panel_vp.size = Vector2i(256, 128)
	autoload._ammo_panel_vp.transparent_bg = true
	autoload._ammo_panel_vp.disable_3d = true
	autoload._ammo_panel_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	autoload.add_child(autoload._ammo_panel_vp)

	var bg = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	autoload._ammo_panel_vp.add_child(bg)

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
	autoload._ammo_panel_vp.add_child(mag_label)

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
	autoload._ammo_panel_vp.add_child(chb_label)

	# QuadMesh using the SubViewport texture
	var quad = QuadMesh.new()
	quad.size = Vector2(0.22, 0.11)
	autoload._ammo_panel_mesh = MeshInstance3D.new()
	autoload._ammo_panel_mesh.mesh = quad
	autoload._ammo_panel_mesh.layers = 1

	var mat = StandardMaterial3D.new()
	mat.albedo_texture = autoload._ammo_panel_vp.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	autoload._ammo_panel_mesh.material_override = mat

	autoload.get_tree().root.add_child(autoload._ammo_panel_mesh)
	update_ammo_panel_position()
	autoload._ammo_check_timer = 3.0
	autoload._log("[VR Mod] Ammo check: MAG=", mag_text, " CHB=", chb_text)


func hide_ammo_check_panel() -> void:
	cleanup_ammo_panel()


func cleanup_ammo_panel() -> void:
	if autoload._ammo_panel_mesh and is_instance_valid(autoload._ammo_panel_mesh):
		autoload._ammo_panel_mesh.queue_free()
		autoload._ammo_panel_mesh = null
	if autoload._ammo_panel_vp and is_instance_valid(autoload._ammo_panel_vp):
		autoload._ammo_panel_vp.queue_free()
		autoload._ammo_panel_vp = null


func update_ammo_panel_position() -> void:
	if not autoload._ammo_panel_mesh or not is_instance_valid(autoload._ammo_panel_mesh):
		return
	var weapon_ctrl = autoload._get_controller(autoload._weapon_hand if autoload._weapon_hand != "" else autoload._config_dominant_hand)
	if not weapon_ctrl or not weapon_ctrl.get_is_active():
		return
	# Float just above and slightly forward of the weapon hand, facing the player
	var hand_pos = weapon_ctrl.global_position
	var up = autoload.xr_camera.global_basis.y.normalized()
	var to_cam = (autoload.xr_camera.global_position - hand_pos).normalized()
	autoload._ammo_panel_mesh.global_position = hand_pos + up * 0.12 + to_cam * 0.05
	autoload._ammo_panel_mesh.look_at(autoload.xr_camera.global_position, Vector3.UP)
	autoload._ammo_panel_mesh.rotate_y(deg_to_rad(180))


func update_smooth_hud(delta: float) -> void:
	if not autoload._hud_smooth_follow:
		return
	if not autoload.hud_mesh:
		return
	if not autoload.hud_mesh.visible:
		return
	if autoload._interface_open:
		return
	if autoload.hud_mesh.get_parent() == autoload.xr_camera:
		return

	var cam_yaw = autoload.xr_camera.global_rotation.y

	# Shortest-path yaw lerp
	var diff = fmod(cam_yaw - autoload._hud_yaw + PI, TAU) - PI
	autoload._hud_yaw += diff * clampf(autoload._hud_smooth_speed * delta, 0.0, 1.0)

	# Position: instantly at exact offset from camera, rotated by lagged yaw
	var lagged_basis = Basis(Vector3.UP, autoload._hud_yaw)
	autoload.hud_mesh.global_position = autoload.xr_camera.global_position + lagged_basis * Vector3(autoload._hud_lr_offset, autoload._hud_height_offset, -autoload._hud_distance)
	autoload.hud_mesh.global_rotation = Vector3(0.0, autoload._hud_yaw, 0.0)


func update_watch_glance(delta: float) -> void:
	if not autoload._watch_mesh or not autoload.xr_camera:
		return

	if not autoload._watch_glance_enabled:
		# Glance disabled - always visible
		watch_alpha = 1.0
		var mat = autoload._watch_mesh.material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("alpha", 1.0)
		autoload._watch_mesh.visible = true
		return

	# Gaze direction (camera forward, world space)
	var gaze_dir = -autoload.xr_camera.global_basis.z

	# Vector from eye to watch (world space)
	var eye_to_watch = autoload._watch_mesh.global_position - autoload.xr_camera.global_position
	var dist = eye_to_watch.length()
	if dist < 0.01:
		return
	eye_to_watch = eye_to_watch / dist

	# One condition: gaze direction points toward watch
	var gaze_dot = gaze_dir.dot(eye_to_watch)

	var threshold = cos(deg_to_rad(autoload._watch_glance_angle))
	var looking = gaze_dot > threshold

	# Smooth fade
	var target_alpha = 1.0 if looking else 0.0
	watch_alpha = move_toward(watch_alpha, target_alpha, autoload._watch_fade_speed * delta)

	# Apply alpha to shader
	var mat = autoload._watch_mesh.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("alpha", watch_alpha)

	# Toggle visibility for render cost savings
	autoload._watch_mesh.visible = watch_alpha > 0.001


func update_laser_pointer() -> void:
	if not autoload.hud_mesh or not autoload._laser_mesh:
		return

	# Get the pointer controller (config dominant hand for UI)
	var controller = autoload._get_controller(autoload._config_dominant_hand)
	if not controller or not controller.get_is_active():
		return

	# Raycast from controller forward direction
	var ray_origin = controller.global_position
	var ray_dir = -controller.global_basis.z  # Controller forward = -Z

	# Intersect with the HUD quad plane
	var hit_pos = ray_quad_intersection(ray_origin, ray_dir, autoload.hud_mesh)

	# Fail-path diagnostic (fires once per interface open)
	if not autoload._laser_diag_logged and hit_pos == Vector3.INF:
		var qn = autoload.hud_mesh.global_basis.z.normalized()
		var denom = qn.dot(ray_dir)
		var t_val = qn.dot(autoload.hud_mesh.global_position - ray_origin) / denom if abs(denom) > 0.0001 else INF
		autoload._log("Laser MISS: origin=" + str(ray_origin) + " dir=" + str(ray_dir) + " quad_pos=" + str(autoload.hud_mesh.global_position) + " quad_norm=" + str(qn) + " denom=" + str(denom) + " t=" + str(t_val))
		autoload._laser_diag_logged = true

	if hit_pos != Vector3.INF:
		# Convert 3D hit point to 2D viewport coordinates
		var local_pos = autoload.hud_mesh.global_transform.affine_inverse() * hit_pos
		var quad_size = (autoload.hud_mesh.mesh as QuadMesh).size

		# QuadMesh goes from -size/2 to +size/2
		var uv_x = (local_pos.x + quad_size.x / 2.0) / quad_size.x
		var uv_y = (-local_pos.y + quad_size.y / 2.0) / quad_size.y

		# Range check on raw UV (did the ray actually hit the quad?)
		if not autoload._laser_diag_logged and (uv_x < 0 or uv_x > 1 or uv_y < 0 or uv_y > 1):
			autoload._log("Laser UV MISS: uv=(" + str(uv_x) + "," + str(uv_y) + ") local=" + str(local_pos) + " quad_size=" + str(quad_size))
			autoload._laser_diag_logged = true
		if uv_x >= 0 and uv_x <= 1 and uv_y >= 0 and uv_y <= 1:
			var vp_pos = Vector2(
				(uv_x + autoload._menu_laser_uv_x) * autoload.hud_viewport.size.x,
				(uv_y + autoload._menu_laser_uv_y) * autoload.hud_viewport.size.y
			)
			# Dead zone: only warp when controller has moved far enough
			if vp_pos.distance_to(autoload._laser_locked_pos) > autoload.hud_viewport.size.y * 0.014:
				autoload._laser_locked_pos = vp_pos
				autoload.get_viewport().warp_mouse(autoload._laser_locked_pos)
			autoload._laser_screen_pos = autoload._laser_locked_pos

			if not autoload._laser_diag_logged:
				autoload._laser_diag_logged = true
				var main_vp: Viewport = autoload.get_viewport()
				autoload._log("Laser diag: uv=" + str(Vector2(uv_x, uv_y)) + " vp_pos=" + str(vp_pos) + " hud_vp_size=" + str(autoload.hud_viewport.size) + " visible_rect=" + str(main_vp.get_visible_rect().size) + " win=" + str(DisplayServer.window_get_size()))

			# Laser tip flush with quad surface. no_depth_test=true prevents clipping.
			var dist = ray_origin.distance_to(hit_pos) - 0.01
			if dist > 0.1:
				(autoload._laser_mesh.mesh as CylinderMesh).height = dist
				autoload._laser_mesh.position.z = -dist / 2.0
				autoload._laser_mesh.visible = true
			else:
				autoload._laser_mesh.visible = false  # Too close, hide entirely
			# ESC menu hover: update each frame while laser hits the quad
			if autoload._esc_menu_active:
				autoload._update_esc_hover()
		else:
			autoload._laser_screen_pos = Vector2(-1, -1)
			autoload._laser_locked_pos = Vector2(-9999.0, -9999.0)
			if autoload._esc_menu_active:
				autoload._esc_clear_hover()


func ray_quad_intersection(ray_origin: Vector3, ray_dir: Vector3, quad: MeshInstance3D) -> Vector3:
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
