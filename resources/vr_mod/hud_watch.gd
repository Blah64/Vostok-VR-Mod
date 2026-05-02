extends RefCounted

# hud_watch.gd
# VR HUD setup (SubViewport+QuadMesh sharing the game's World2D), wrist-watch
# crop logic, glance-to-reveal fade, ammo check panel, world-fixed menu/inventory
# panel handoff, smooth-follow yaw, and the laser pointer that drives all of it.
#
# Subsystem-owned state. Watch-specific scene refs and crop-state machine
# live here. The hud_mesh / hud_viewport themselves and many tunables stay on
# the autoload because the F8 panel and other systems read/write them by name;
# this module reaches them through Callable ports rather than back-reference.
#
# Port surface is large because this subsystem genuinely touches a lot of
# cross-system state. Ports are split into:
#   * Scene refs (camera/owner/laser/hud_mesh/hud_viewport getters and setters)
#   * Per-frame state (interface_open, menu_open, frame counter, etc.)
#   * Tunables (sizes, distances, spreads — F8 writes these)
#   * Side effects (inject_key, apply_hud_spread, setup_nvg_overlay, esc_*)
#   * Constants (HUD_SETUP_DELAY, WATCH_CROP_SHADER, etc.)


# Subsystem-owned state.
var watch_b_vp: SubViewport = null     # Second viewport for Medical element
var watch_alpha: float = 0.0           # Fade alpha (0=hidden, 1=visible)
var watch_crop_computed: bool = false
var watch_crop_delay: int = 0          # Countdown frames before reading node rects
var watch_crop_retries: int = 0
var vitals_node: Control = null        # game HUD node ref (not reparented)
var medical_node: Control = null       # game HUD node ref (not reparented)


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


# Convenience accessors — keep the call sites readable without inflating the
# constructor by pulling each Callable into its own field. _ports.get() returns
# Variant so we coerce as needed.
func _p(name: String) -> Callable:
	return _ports[name]


func process(frame: Dictionary, delta: float) -> void:
	# HUD/watch per-frame work.
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
	if _p("get_hud_installed").call() or _p("get_frames_waited").call() < _p("get_hud_setup_delay").call():
		return
	setup_vr_hud()
	if _p("get_in_menu_mode").call():
		_p("set_prev_interface_open").call(false)


func _tick_support_trigger_long_press() -> void:
	if not _p("get_support_trigger_pending").call():
		return
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - _p("get_support_trigger_press_time").call()
	if elapsed < 0.5:
		return
	_p("set_support_trigger_pending").call(false)
	_p("inject_key").call(KEY_V, true)
	_p("inject_key").call(KEY_V, false)
	var support_ctrl = _p("get_controller").call(_p("get_support_hand").call())
	if support_ctrl:
		support_ctrl.trigger_haptic_pulse("haptic", 0.0, 0.2, 0.1, 0.0)
	_p("set_ammo_read_delay").call(3)
	_log("[VR Mod] AMMO CHECK (support trigger long-press)")


func _tick_ammo_panel(delta: float) -> void:
	var rd: int = _p("get_ammo_read_delay").call()
	if rd > 0:
		rd -= 1
		_p("set_ammo_read_delay").call(rd)
		if rd == 0:
			show_ammo_check_panel()
	var t: float = _p("get_ammo_check_timer").call()
	if t > 0.0:
		t -= delta
		_p("set_ammo_check_timer").call(t)
		if t <= 0.0:
			hide_ammo_check_panel()
		else:
			var ammo_mesh = _p("get_ammo_panel_mesh").call()
			if ammo_mesh and is_instance_valid(ammo_mesh) and _p("get_camera").call():
				update_ammo_panel_position()


func setup_vr_hud() -> void:
	_log("[VR Mod] Setting up VR HUD (World2D sharing)...")

	var owner_node: Node = _p("get_owner_node").call()
	var main_vp: Viewport = _p("get_main_viewport").call()
	var vp_size = main_vp.get_visible_rect().size
	var win_size_for_log = DisplayServer.window_get_size()
	var win = _p("get_window").call()
	var cs_size = win.content_scale_size if win else Vector2i.ZERO
	_log("HUD sizes: visible_rect=" + str(vp_size) + " win=" + str(win_size_for_log) + " content_scale=" + str(cs_size) + " canvas_xform=" + str(main_vp.canvas_transform) + " global_canvas_xform=" + str(main_vp.global_canvas_transform))
	var ui_node = _tree.root.get_node_or_null("Map/Core/UI")
	if ui_node:
		_log("[VR Mod] UI node: " + str(ui_node.get_path()) + " vis=" + str(ui_node.visible))

	var hud_vp = SubViewport.new()
	hud_vp.name = "VRHudViewport"
	hud_vp.size = Vector2i(int(vp_size.x), int(vp_size.y))
	hud_vp.transparent_bg = true
	hud_vp.disable_3d = true
	hud_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	hud_vp.world_2d = main_vp.world_2d
	hud_vp.gui_disable_input = true
	# Exclude canvas visibility layer 16 - Effects (Sharpen etc.) are moved there
	# so their screen-space shaders don't sample our empty SubViewport and go black.
	hud_vp.canvas_cull_mask = 0xFFFFFFFF ^ (1 << 16)
	owner_node.add_child(hud_vp)
	_p("set_hud_viewport").call(hud_vp)

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
	owner_node.add_child(watch_b_vp)

	var hud_mesh := MeshInstance3D.new()
	hud_mesh.name = "VRHudPanel"

	var quad = QuadMesh.new()
	var aspect = float(hud_vp.size.y) / float(hud_vp.size.x)
	quad.size = Vector2(_p("get_hud_width").call(), _p("get_hud_width").call() * aspect)
	hud_mesh.mesh = quad

	var mat = StandardMaterial3D.new()
	mat.albedo_texture = hud_vp.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 10
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hud_mesh.material_override = mat

	# Put HUD on layer 20 only so NVG mono camera doesn't render it
	hud_mesh.layers = (1 << 19)

	# Park hud_mesh invisibly under owner - watch takes over during gameplay
	hud_mesh.visible = false
	owner_node.add_child(hud_mesh)
	_p("set_hud_mesh").call(hud_mesh)

	_p("set_hud_installed").call(true)

	# Set compact spread, set up dedicated watch content VP, then create watch mesh
	_p("set_hud_spread_active").call(_p("get_watch_spread").call())
	_p("apply_hud_spread").call()
	setup_watch_content()
	_log("HUD viewport ready, creating watch mesh...")
	create_watch_mesh()
	var wm = _p("get_watch_mesh").call()
	if wm:
		_log("Watch mesh created OK, visible=" + str(wm.visible) + " layers=" + str(wm.layers))
	else:
		_log("WARNING: watch mesh is null after _create_watch_mesh!")

	_log("[VR Mod] VR HUD installed (wrist watch mode)")

	_p("setup_nvg_overlay").call()

	_log("[VR Mod] === VR fully active ===")


func create_watch_mesh() -> void:
	# Determine non-dominant hand
	var dom: String = _p("get_dominant_hand").call()
	var non_dom = "left" if dom == "right" else "right"
	var controller = _p("get_controller").call(non_dom)
	if not controller:
		_log("WARNING: non-dominant controller not found for watch")
		return

	# Use a dedicated mount Node3D with no rotation - avoids hand model rotation complexity
	# CRITICAL: Never add MeshInstance3D directly to XRController3D; always wrap in Node3D
	var mount = Node3D.new()
	mount.name = "WatchMount"
	controller.add_child(mount)

	var watch_mesh := MeshInstance3D.new()
	watch_mesh.name = "WristWatch"

	var quad = QuadMesh.new()
	var watch_size: float = _p("get_watch_size").call()
	quad.size = Vector2(watch_size, watch_size)
	watch_mesh.mesh = quad

	# ShaderMaterial with UV crop + alpha fade
	var shader = Shader.new()
	shader.code = _p("get_watch_crop_shader").call()
	var mat = ShaderMaterial.new()
	mat.shader = shader
	var hud_vp = _p("get_hud_viewport").call()
	mat.set_shader_parameter("hud_texture", hud_vp.get_texture())
	if watch_b_vp:
		mat.set_shader_parameter("medical_tex", watch_b_vp.get_texture())
	mat.set_shader_parameter("alpha", 0.0)
	mat.render_priority = 10
	watch_mesh.material_override = mat

	# Use layer 1 so it's definitely in the XR camera cull_mask
	watch_mesh.layers = 1

	watch_mesh.position = _p("get_watch_offset").call()
	watch_mesh.basis = _p("watch_rot_basis").call()

	mount.add_child(watch_mesh)
	watch_mesh.visible = false
	_p("set_watch_mesh").call(watch_mesh)
	_log("Wrist watch installed on " + non_dom + " hand, mount at " + str(mount.get_path()))


func destroy_watch_mesh() -> void:
	var watch_mesh = _p("get_watch_mesh").call()
	if watch_mesh and is_instance_valid(watch_mesh):
		# Free the WatchMount parent too
		var mount = watch_mesh.get_parent()
		if mount and is_instance_valid(mount) and mount.name == "WatchMount":
			mount.queue_free()
		else:
			watch_mesh.queue_free()
	_p("set_watch_mesh").call(null)
	watch_alpha = 0.0
	teardown_watch_content()


func setup_watch_content() -> void:
	# Find Vitals and Medical in the game HUD
	var stats = _tree.root.get_node_or_null("Map/Core/UI/HUD/Stats")
	if not stats:
		_log("WARNING: HUD/Stats not found - watch will show full HUD texture")
		return

	vitals_node = stats.get_node_or_null("Vitals") as Control
	medical_node = stats.get_node_or_null("Medical") as Control

	if not vitals_node and not medical_node:
		_log("WARNING: Neither Vitals nor Medical found - watch will show full HUD texture")
		return

	watch_crop_computed = false
	watch_crop_delay = 30
	watch_crop_retries = 0
	_log("Watch: found Vitals=" + str(vitals_node != null) + " Medical=" + str(medical_node != null) + " - crop will be computed in 30 frames")


func compute_watch_crop() -> void:
	var hud_vp = _p("get_hud_viewport").call()
	if not hud_vp:
		return

	var vp_w = float(hud_vp.size.x)
	var vp_h = float(hud_vp.size.y)

	_p("set_hud_spread_active").call(1.0)
	_p("apply_hud_spread").call()

	var elem_w  = vp_w * 0.208
	var elem_h  = vp_h * 0.25
	var elem_top = vp_h - elem_h
	var vitals_cx  = vp_w * 0.25
	var medical_cx = vp_w * 0.75

	var vitals_rect  = Rect2(vitals_cx  - elem_w * 0.5, elem_top, elem_w, elem_h)
	var medical_rect = Rect2(medical_cx - elem_w * 0.5, elem_top, elem_w, elem_h)

	_log("Watch crop: vitals=" + str(vitals_rect) + " medical=" + str(medical_rect))

	var sx = vp_w / elem_w
	var sy = vp_h / elem_h

	var tv = Transform2D()
	tv[0] = Vector2(sx, 0.0)
	tv[1] = Vector2(0.0, sy)
	tv[2] = Vector2(-vitals_rect.position.x * sx, -vitals_rect.position.y * sy)
	hud_vp.canvas_transform = tv

	if watch_b_vp:
		var tm = Transform2D()
		tm[0] = Vector2(sx, 0.0)
		tm[1] = Vector2(0.0, sy)
		tm[2] = Vector2(-medical_rect.position.x * sx, -medical_rect.position.y * sy)
		watch_b_vp.canvas_transform = tm

	watch_crop_computed = true
	_log("Watch crop scale=(" + str(snapped(sx, 0.01)) + "," + str(snapped(sy, 0.01)) + ")")

	# Move all Effects canvas items to visibility layer 16 so watch SubViewports
	# (which exclude layer 16 via canvas_cull_mask) don't render screen-space
	# effects that would sample the empty SubViewport and output black.
	var effects_node = _tree.root.get_node_or_null("Map/Core/UI/Effects")
	if effects_node:
		set_canvas_visibility_recursive(effects_node, 1 << 16)

	var watch_mesh = _p("get_watch_mesh").call()
	if watch_mesh and is_instance_valid(watch_mesh):
		var stacked_aspect = elem_w / (elem_h * 2.0)
		var watch_size: float = _p("get_watch_size").call()
		var quad_w = clamp(watch_size * stacked_aspect, 0.02, 1.0)
		var quad_h = watch_size
		(watch_mesh.mesh as QuadMesh).size = Vector2(quad_w, quad_h)
		_log("Watch quad: " + str(snapped(quad_w, 0.001)) + "m x " + str(snapped(quad_h, 0.001)) + "m (aspect " + str(snapped(stacked_aspect, 0.01)) + ")")


func set_canvas_visibility_recursive(node: Node, layer: int) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visibility_layer = layer
	for child in node.get_children():
		set_canvas_visibility_recursive(child, layer)


func teardown_watch_content() -> void:
	# Reset canvas_transforms so the floating menu HUD renders correctly
	var hud_vp = _p("get_hud_viewport").call()
	if hud_vp:
		hud_vp.canvas_transform = Transform2D.IDENTITY
	if watch_b_vp:
		watch_b_vp.canvas_transform = Transform2D.IDENTITY
	vitals_node = null
	medical_node = null
	watch_crop_computed = false
	watch_crop_delay = 0
	watch_crop_retries = 0


func update_interface_state() -> void:
	# Check if any UI panel that's normally hidden is now visible
	_p("set_interface_open").call(false)
	var _detected_by := ""
	var ui_node = _tree.root.get_node_or_null("Map/Core/UI")
	if ui_node:
		for child in ui_node.get_children():
			# Skip always-visible HUD elements
			if child.name in ["HUD", "Effects", "NVG"]:
				continue
			if child is CanvasItem and child.visible:
				_p("set_interface_open").call(true)
				_detected_by = "Map/Core/UI/" + child.name + " (" + child.get_class() + ")"
				break

	# Also check siblings of UI under Map/Core - ESC menu may live there
	if not _p("get_interface_open").call():
		var core_node = _tree.root.get_node_or_null("Map/Core")
		if core_node:
			for child in core_node.get_children():
				if child.name in ["Camera", "UI", "LOS", "Interactor"]:
					continue
				if child is CanvasItem and child.visible:
					_p("set_interface_open").call(true)
					_detected_by = "Map/Core/" + child.name + " (" + child.get_class() + ")"
					break

	if _p("get_interface_open").call() and not _p("get_prev_interface_open").call():
		_log("Interface opened: detected by " + _detected_by)

	# ESC menu always pauses the tree; inventory/loot pools do not.
	if _p("get_esc_menu_active").call() and not _tree.paused:
		_p("set_esc_menu_active").call(false)
		_p("esc_clear_hover").call()
	if _p("get_esc_menu_active").call():
		_p("set_interface_open").call(true)

	# Main menu mode: no game scene, but show the HUD panel for the main menu UI
	if _p("get_in_menu_mode").call():
		_p("set_interface_open").call(true)

	# Detect transitions
	var io: bool = _p("get_interface_open").call()
	var prev: bool = _p("get_prev_interface_open").call()
	if io and not prev:
		on_interface_opened()
	elif not io and prev:
		on_interface_closed()
	_p("set_prev_interface_open").call(io)


func on_interface_opened() -> void:
	_log("[VR Mod] Interface OPENED - switching to world-fixed mode")
	_p("set_ammo_check_timer").call(0.0)
	cleanup_ammo_panel()
	_p("set_laser_diag_logged").call(false)
	_p("set_laser_locked_pos").call(Vector2(-9999.0, -9999.0))
	var hud_mesh = _p("get_hud_mesh").call()
	if not hud_mesh:
		return

	# Hide watch during menus
	var watch_mesh = _p("get_watch_mesh").call()
	if watch_mesh:
		watch_mesh.visible = false
		watch_alpha = 0.0
		var wmat = watch_mesh.material_override as ShaderMaterial
		if wmat:
			wmat.set_shader_parameter("alpha", 0.0)

	# Restore normal spread and full canvas for floating menu
	_p("set_hud_spread_active").call(_p("get_hud_spread").call())
	_p("apply_hud_spread").call()
	var hud_vp = _p("get_hud_viewport").call()
	if hud_vp:
		hud_vp.canvas_transform = Transform2D.IDENTITY
	if watch_b_vp:
		watch_b_vp.canvas_transform = Transform2D.IDENTITY

	# Detach hud_mesh from parked location and place in world space
	if hud_mesh.get_parent():
		hud_mesh.get_parent().remove_child(hud_mesh)

	# Place in front of camera at current look direction
	var cam = _p("get_camera").call()
	var cam_pos = cam.global_position
	var cam_forward = -cam.global_basis.z
	cam_forward.y = 0
	cam_forward = cam_forward.normalized()

	var menu_dist: float = _p("get_menu_distance").call()
	var menu_lr: float = _p("get_menu_lr_offset").call()
	var hud_h: float = _p("get_hud_height_offset").call()
	var menu_pos = cam_pos + cam_forward * menu_dist
	var cam_right = cam.global_basis.x
	menu_pos += cam_right * menu_lr
	menu_pos.y = cam_pos.y + hud_h

	# Add to scene root so it's world-fixed
	_tree.root.add_child(hud_mesh)
	hud_mesh.visible = true
	hud_mesh.global_position = menu_pos
	hud_mesh.look_at(cam_pos, Vector3.UP)
	hud_mesh.rotate_y(deg_to_rad(180))

	# Scale up for menu
	var aspect = float(hud_vp.size.y) / float(hud_vp.size.x)
	var menu_w: float = _p("get_menu_width").call()
	(hud_mesh.mesh as QuadMesh).size = Vector2(menu_w, menu_w * aspect)

	# Show laser pointer (restore to UI blue/full-length mode)
	_p("set_menu_open").call(true)
	var laser = _p("get_laser_mesh").call()
	if laser:
		var mat := laser.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.2, 0.5, 1.0, 0.5)
		var cyl := laser.mesh as CylinderMesh
		if cyl:
			cyl.height = 5.0
			laser.position.z = -cyl.height / 2.0
		laser.visible = true

	_log("[VR Mod] Menu placed at " + str(menu_pos))


func on_interface_closed() -> void:
	_log("[VR Mod] Interface CLOSED - switching to wrist watch mode")
	var hud_mesh = _p("get_hud_mesh").call()
	if not hud_mesh:
		return

	# Restore spread=1.0 for watch (elements at known positions for crop)
	_p("set_hud_spread_active").call(1.0)
	_p("apply_hud_spread").call()
	var hud_vp = _p("get_hud_viewport").call()
	if watch_crop_computed and hud_vp:
		watch_crop_delay = 1
		watch_crop_retries = 0

	# Park hud_mesh invisibly - watch takes over during gameplay
	if hud_mesh.get_parent():
		hud_mesh.get_parent().remove_child(hud_mesh)
	hud_mesh.visible = false
	_p("get_owner_node").call().add_child(hud_mesh)

	# Release Ctrl modifier if held (support grip fast transfer)
	if _p("get_menu_ctrl_held").call():
		_p("set_menu_ctrl_held").call(false)
		_p("inject_key").call(KEY_CTRL, false)

	# Hide laser pointer and return to grab-range mode
	_p("set_menu_open").call(false)
	var laser = _p("get_laser_mesh").call()
	if laser and not _p("get_config_screen_open").call():
		laser.visible = false


func show_ammo_check_panel() -> void:
	var cam = _p("get_camera").call()
	if not cam:
		return

	# Read counts directly from game HUD labels
	var hud_node = _tree.root.get_node_or_null("Map/Core/UI/HUD")
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

	var ammo_vp := SubViewport.new()
	ammo_vp.size = Vector2i(256, 128)
	ammo_vp.transparent_bg = true
	ammo_vp.disable_3d = true
	ammo_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_p("get_owner_node").call().add_child(ammo_vp)
	_p("set_ammo_panel_vp").call(ammo_vp)

	var bg = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.75)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ammo_vp.add_child(bg)

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
	ammo_vp.add_child(mag_label)

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
	ammo_vp.add_child(chb_label)

	# QuadMesh using the SubViewport texture
	var quad = QuadMesh.new()
	quad.size = Vector2(0.22, 0.11)
	var ammo_mesh := MeshInstance3D.new()
	ammo_mesh.mesh = quad
	ammo_mesh.layers = 1

	var mat = StandardMaterial3D.new()
	mat.albedo_texture = ammo_vp.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ammo_mesh.material_override = mat
	_p("set_ammo_panel_mesh").call(ammo_mesh)

	_tree.root.add_child(ammo_mesh)
	update_ammo_panel_position()
	_p("set_ammo_check_timer").call(3.0)
	_log("[VR Mod] Ammo check: MAG=" + mag_text + " CHB=" + chb_text)


func hide_ammo_check_panel() -> void:
	cleanup_ammo_panel()


func cleanup_ammo_panel() -> void:
	var ammo_mesh = _p("get_ammo_panel_mesh").call()
	if ammo_mesh and is_instance_valid(ammo_mesh):
		ammo_mesh.queue_free()
		_p("set_ammo_panel_mesh").call(null)
	var ammo_vp = _p("get_ammo_panel_vp").call()
	if ammo_vp and is_instance_valid(ammo_vp):
		ammo_vp.queue_free()
		_p("set_ammo_panel_vp").call(null)


func update_ammo_panel_position() -> void:
	var ammo_mesh = _p("get_ammo_panel_mesh").call()
	if not ammo_mesh or not is_instance_valid(ammo_mesh):
		return
	var weapon_hand: String = _p("get_weapon_hand").call()
	var hand_for_ctrl: String = weapon_hand if weapon_hand != "" else _p("get_dominant_hand").call()
	var weapon_ctrl = _p("get_controller").call(hand_for_ctrl)
	if not weapon_ctrl or not weapon_ctrl.get_is_active():
		return
	var cam = _p("get_camera").call()
	# Float just above and slightly forward of the weapon hand, facing the player
	var hand_pos = weapon_ctrl.global_position
	var up = cam.global_basis.y.normalized()
	var to_cam = (cam.global_position - hand_pos).normalized()
	ammo_mesh.global_position = hand_pos + up * 0.12 + to_cam * 0.05
	ammo_mesh.look_at(cam.global_position, Vector3.UP)
	ammo_mesh.rotate_y(deg_to_rad(180))


func update_smooth_hud(delta: float) -> void:
	if not _p("get_hud_smooth_follow").call():
		return
	var hud_mesh = _p("get_hud_mesh").call()
	if not hud_mesh:
		return
	if not hud_mesh.visible:
		return
	if _p("get_interface_open").call():
		return
	var cam = _p("get_camera").call()
	if hud_mesh.get_parent() == cam:
		return

	var cam_yaw = cam.global_rotation.y

	# Shortest-path yaw lerp
	var yaw: float = _p("get_hud_yaw").call()
	var diff = fmod(cam_yaw - yaw + PI, TAU) - PI
	yaw += diff * clampf(_p("get_hud_smooth_speed").call() * delta, 0.0, 1.0)
	_p("set_hud_yaw").call(yaw)

	# Position: instantly at exact offset from camera, rotated by lagged yaw
	var lagged_basis = Basis(Vector3.UP, yaw)
	var lr: float = _p("get_hud_lr_offset").call()
	var h: float = _p("get_hud_height_offset").call()
	var d: float = _p("get_hud_distance").call()
	hud_mesh.global_position = cam.global_position + lagged_basis * Vector3(lr, h, -d)
	hud_mesh.global_rotation = Vector3(0.0, yaw, 0.0)


func update_watch_glance(delta: float) -> void:
	var watch_mesh = _p("get_watch_mesh").call()
	var cam = _p("get_camera").call()
	if not watch_mesh or not cam:
		return

	if not _p("get_watch_glance_enabled").call():
		# Glance disabled - always visible
		watch_alpha = 1.0
		var mat = watch_mesh.material_override as ShaderMaterial
		if mat:
			mat.set_shader_parameter("alpha", 1.0)
		watch_mesh.visible = true
		return

	# Gaze direction (camera forward, world space)
	var gaze_dir = -cam.global_basis.z

	# Vector from eye to watch (world space)
	var eye_to_watch = watch_mesh.global_position - cam.global_position
	var dist = eye_to_watch.length()
	if dist < 0.01:
		return
	eye_to_watch = eye_to_watch / dist

	# One condition: gaze direction points toward watch
	var gaze_dot = gaze_dir.dot(eye_to_watch)

	var threshold = cos(deg_to_rad(_p("get_watch_glance_angle").call()))
	var looking = gaze_dot > threshold

	# Smooth fade
	var target_alpha = 1.0 if looking else 0.0
	watch_alpha = move_toward(watch_alpha, target_alpha, _p("get_watch_fade_speed").call() * delta)

	# Apply alpha to shader
	var mat = watch_mesh.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("alpha", watch_alpha)

	# Toggle visibility for render cost savings
	watch_mesh.visible = watch_alpha > 0.001


func update_laser_pointer() -> void:
	var hud_mesh = _p("get_hud_mesh").call()
	var laser = _p("get_laser_mesh").call()
	if not hud_mesh or not laser:
		return

	# Get the pointer controller (config dominant hand for UI)
	var controller = _p("get_controller").call(_p("get_dominant_hand").call())
	if not controller or not controller.get_is_active():
		return

	# Raycast from controller forward direction
	var ray_origin = controller.global_position
	var ray_dir = -controller.global_basis.z  # Controller forward = -Z

	# Intersect with the HUD quad plane
	var hit_pos = ray_quad_intersection(ray_origin, ray_dir, hud_mesh)

	# Fail-path diagnostic (fires once per interface open)
	if not _p("get_laser_diag_logged").call() and hit_pos == Vector3.INF:
		var qn = hud_mesh.global_basis.z.normalized()
		var denom = qn.dot(ray_dir)
		var t_val = qn.dot(hud_mesh.global_position - ray_origin) / denom if abs(denom) > 0.0001 else INF
		_log("Laser MISS: origin=" + str(ray_origin) + " dir=" + str(ray_dir) + " quad_pos=" + str(hud_mesh.global_position) + " quad_norm=" + str(qn) + " denom=" + str(denom) + " t=" + str(t_val))
		_p("set_laser_diag_logged").call(true)

	if hit_pos != Vector3.INF:
		var hud_vp = _p("get_hud_viewport").call()
		# Convert 3D hit point to 2D viewport coordinates
		var local_pos = hud_mesh.global_transform.affine_inverse() * hit_pos
		var quad_size = (hud_mesh.mesh as QuadMesh).size

		# QuadMesh goes from -size/2 to +size/2
		var uv_x = (local_pos.x + quad_size.x / 2.0) / quad_size.x
		var uv_y = (-local_pos.y + quad_size.y / 2.0) / quad_size.y

		# Range check on raw UV (did the ray actually hit the quad?)
		if not _p("get_laser_diag_logged").call() and (uv_x < 0 or uv_x > 1 or uv_y < 0 or uv_y > 1):
			_log("Laser UV MISS: uv=(" + str(uv_x) + "," + str(uv_y) + ") local=" + str(local_pos) + " quad_size=" + str(quad_size))
			_p("set_laser_diag_logged").call(true)
		if uv_x >= 0 and uv_x <= 1 and uv_y >= 0 and uv_y <= 1:
			var vp_pos = Vector2(
				(uv_x + _p("get_menu_laser_uv_x").call()) * hud_vp.size.x,
				(uv_y + _p("get_menu_laser_uv_y").call()) * hud_vp.size.y
			)
			# Dead zone: only warp when controller has moved far enough
			var locked: Vector2 = _p("get_laser_locked_pos").call()
			if vp_pos.distance_to(locked) > hud_vp.size.y * 0.014:
				locked = vp_pos
				_p("set_laser_locked_pos").call(locked)
				_p("get_main_viewport").call().warp_mouse(locked)
			_p("set_laser_screen_pos").call(locked)

			if not _p("get_laser_diag_logged").call():
				_p("set_laser_diag_logged").call(true)
				var main_vp: Viewport = _p("get_main_viewport").call()
				_log("Laser diag: uv=" + str(Vector2(uv_x, uv_y)) + " vp_pos=" + str(vp_pos) + " hud_vp_size=" + str(hud_vp.size) + " visible_rect=" + str(main_vp.get_visible_rect().size) + " win=" + str(DisplayServer.window_get_size()))

			# Laser tip flush with quad surface. no_depth_test=true prevents clipping.
			var dist = ray_origin.distance_to(hit_pos) - 0.01
			if dist > 0.1:
				(laser.mesh as CylinderMesh).height = dist
				laser.position.z = -dist / 2.0
				laser.visible = true
			else:
				laser.visible = false  # Too close, hide entirely
			# ESC menu hover: update each frame while laser hits the quad
			if _p("get_esc_menu_active").call():
				_p("update_esc_hover").call()
		else:
			_p("set_laser_screen_pos").call(Vector2(-1, -1))
			_p("set_laser_locked_pos").call(Vector2(-9999.0, -9999.0))
			if _p("get_esc_menu_active").call():
				_p("esc_clear_hover").call()


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
