extends RefCounted

# config_ui.gd
# F8 SubViewport-based config panel: building, populating, laser pointer,
# stepper/toggle widgets, all _on_cfg_* callbacks, and the full-config save
# helpers. State (window-open flag, panel/quad refs, settings vars themselves)
# stays on the autoload; this module owns the build + apply logic only.
#
# The autoload retains thin wrappers for any of these methods that other
# autoload code paths or system callbacks reference by name.

const CONFIG_LASER_INTERVAL_MSEC = 33  # ~30 Hz; eye-rate (90 Hz) is overkill for a UI cursor

var autoload: Node
var _config_laser_next_msec := 0

func _init(p_autoload: Node) -> void:
	autoload = p_autoload


func process(frame: Dictionary, _delta: float) -> void:
	# Laser pointer dispatch: F8 panel takes priority, then 2D HUD/menu laser,
	# otherwise the laser is hidden (or driven by hand state via hud_watch).
	# Both branches read the snapshot's interface_open / config_screen_open so
	# the autoload _process body stays free of UI-state coupling.
	if frame.get("config_screen_open", false):
		update_config_laser()
	elif frame.get("interface_open", false):
		autoload._ensure_hud_watch().update_laser_pointer()


func toggle_config_screen() -> void:
	if autoload._config_screen_open:
		close_config_screen()
	else:
		open_config_screen()


func open_config_screen() -> void:
	if autoload._config_screen_open:
		return
	autoload._config_screen_open = true
	build_config_panel()
	populate_config_ui()
	# Show laser in blue/UI mode
	if autoload._laser_mesh:
		var mat := autoload._laser_mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.2, 0.5, 1.0, 0.5)
		var cyl := autoload._laser_mesh.mesh as CylinderMesh
		if cyl:
			cyl.height = 5.0
			autoload._laser_mesh.position.z = -cyl.height / 2.0
		autoload._laser_mesh.visible = true
	autoload._log("[VR Mod] Config screen opened")


func close_config_screen() -> void:
	if not autoload._config_screen_open:
		return
	autoload._config_screen_open = false
	if autoload._config_panel_quad and is_instance_valid(autoload._config_panel_quad):
		autoload._config_panel_quad.queue_free()
		autoload._config_panel_quad = null
	if autoload._config_panel_vp and is_instance_valid(autoload._config_panel_vp):
		autoload._config_panel_vp.queue_free()
		autoload._config_panel_vp = null
	if autoload._laser_mesh and not autoload._interface_open:
		autoload._laser_mesh.visible = false
	autoload._log("[VR Mod] Config screen closed")


func build_config_panel() -> void:
	# SubViewport for config UI
	autoload._config_panel_vp = SubViewport.new()
	autoload._config_panel_vp.name = "ConfigPanelVP"
	autoload._config_panel_vp.size = Vector2i(800, 900)
	autoload._config_panel_vp.transparent_bg = true
	autoload._config_panel_vp.disable_3d = true
	autoload._config_panel_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	autoload._config_panel_vp.gui_disable_input = false
	autoload.add_child(autoload._config_panel_vp)

	# Place quad in world space in front of camera
	autoload._config_panel_quad = MeshInstance3D.new()
	autoload._config_panel_quad.name = "ConfigPanelQuad"
	var quad = QuadMesh.new()
	var aspect = 900.0 / 800.0
	quad.size = Vector2(1.6, 1.6 * aspect)
	autoload._config_panel_quad.mesh = quad

	var mat = StandardMaterial3D.new()
	mat.albedo_texture = autoload._config_panel_vp.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 20
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	autoload._config_panel_quad.material_override = mat

	var cam_pos = autoload.xr_camera.global_position
	var cam_fwd = -autoload.xr_camera.global_basis.z
	cam_fwd.y = 0
	cam_fwd = cam_fwd.normalized()
	var panel_pos = cam_pos + cam_fwd * 1.3
	panel_pos.y = cam_pos.y

	autoload.get_tree().root.add_child(autoload._config_panel_quad)
	autoload._config_panel_quad.global_position = panel_pos
	autoload._config_panel_quad.look_at(cam_pos, Vector3.UP)
	autoload._config_panel_quad.rotate_y(deg_to_rad(180))


func populate_config_ui() -> void:
	if not autoload._config_panel_vp:
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

	mk_sep(outer)

	# Recenter button (pinned above tabs)
	var recenter_row = HBoxContainer.new()
	recenter_row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(recenter_row)
	var recenter_btn = mk_btn("Recenter to Character", Color(0.2, 0.45, 0.7))
	recenter_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recenter_btn.pressed.connect(Callable(self, "_on_cfg_recenter"))
	recenter_row.add_child(recenter_btn)

	mk_sep(outer)

	# Tab container
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

	# Tab 0: General
	var scroll_gen = ScrollContainer.new()
	scroll_gen.name = "General"
	scroll_gen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_gen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll_gen)
	var vbox_gen = VBoxContainer.new()
	vbox_gen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_gen.add_child(vbox_gen)

	mk_header(vbox_gen, "Comfort")
	var grid_comfort = mk_grid(vbox_gen)
	add_toggle_row(grid_comfort, "Turn Mode", ["Snap", "Smooth"], 0 if autoload.use_snap_turn else 1, "_on_cfg_turn")
	add_stepper_row(grid_comfort, "Snap Degrees", autoload.snap_turn_degrees, 15.0, 90.0, 5.0, "_on_cfg_snap_deg")
	add_stepper_row(grid_comfort, "Smooth Speed", autoload.smooth_turn_speed, 30.0, 300.0, 10.0, "_on_cfg_smooth_spd")
	add_toggle_row(grid_comfort, "Vignette", ["On", "Off"], 0 if autoload._vignette_enabled else 1, "_on_cfg_vignette")
	add_stepper_row(grid_comfort, "Vig. Strength", autoload._vignette_strength, 0.1, 1.0, 0.1, "_on_cfg_vignette_str")
	add_stepper_row(grid_comfort, "Render Scale", autoload._render_scale, 0.5, 1.0, 0.05, "_on_cfg_render_scale")
	add_toggle_row(grid_comfort, "2H Stabilize", ["On", "Off"], 0 if autoload._two_hand_smooth_enabled else 1, "_on_cfg_2h_smooth")
	add_stepper_row(grid_comfort, "2H Smooth", autoload._two_hand_smooth_speed, 2.0, 30.0, 1.0, "_on_cfg_2h_smooth_spd")
	add_toggle_row(grid_comfort, "Weapon Sway", ["On", "Off"], 1 if autoload._disable_walk_sway else 0, "_on_cfg_walk_sway")

	mk_sep(vbox_gen)

	mk_header(vbox_gen, "Controls")
	var grid_ctrl = mk_grid(vbox_gen)
	add_toggle_row(grid_ctrl, "Dominant Hand", ["Right", "Left"], 0 if autoload._config_dominant_hand == "right" else 1, "_on_cfg_hand")
	add_toggle_row(grid_ctrl, "Mirror Zones", ["Off", "On"], 1 if autoload._holster_zones_mirrored else 0, "_on_cfg_holster_mirror")
	add_toggle_row(grid_ctrl, "Auto-Recenter", ["On", "Off"], 0 if autoload._auto_recenter_enabled else 1, "_on_cfg_auto_recenter")
	add_toggle_row(grid_ctrl, "Tracking Mode", ["Sitting", "Standing"], 1 if autoload._standing_mode else 0, "_on_cfg_standing_mode")
	add_toggle_row(grid_ctrl, "Gun Config", ["Off", "On"], 1 if autoload._gun_config_enabled else 0, "_on_cfg_gun_config")
	add_toggle_row(grid_ctrl, "Laser Always On", ["On", "Off"], 0 if autoload._laser_always_on else 1, "_on_cfg_laser_always_on")
	add_toggle_row(grid_ctrl, "Move Direction", ["Camera", "Controller"], 0 if autoload._move_direction_mode == "camera" else 1, "_on_cfg_move_direction")
	add_toggle_row(grid_ctrl, "Move Controller", ["Left", "Right"], 0 if autoload._move_direction_hand == "left" else 1, "_on_cfg_move_direction_hand")

	mk_sep(vbox_gen)

	mk_header(vbox_gen, "Menu / Inventory")
	var grid_menu = mk_grid(vbox_gen)
	add_stepper_row(grid_menu, "Distance", autoload._menu_distance, 0.5, 3.0, 0.1, "_on_cfg_menu_dist")
	add_stepper_row(grid_menu, "Size", autoload._menu_width, 0.5, 5.0, 0.1, "_on_cfg_menu_wid")
	add_stepper_row(grid_menu, "Left/Right", autoload._menu_lr_offset, -1.0, 1.0, 0.05, "_on_cfg_menu_lr")
	add_stepper_row(grid_menu, "Height", autoload._hud_height_offset, -1.0, 1.0, 0.05, "_on_cfg_hud_hgt")
	add_stepper_row(grid_menu, "HUD Spread", autoload._hud_spread, 0.1, 2.0, 0.1, "_on_cfg_hud_spread")
	add_stepper_row(grid_menu, "Laser X", autoload._menu_laser_uv_x, -5.0, 5.0, 0.01, "_on_cfg_laser_x")
	add_stepper_row(grid_menu, "Laser Y", autoload._menu_laser_uv_y, -5.0, 5.0, 0.01, "_on_cfg_laser_y")

	# Tab 1: Zones
	var scroll_zone = ScrollContainer.new()
	scroll_zone.name = "Zones"
	scroll_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll_zone)
	var vbox_zone = VBoxContainer.new()
	vbox_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_zone.add_child(vbox_zone)

	mk_header(vbox_zone, "Holster Zones")
	var grid_holsters = mk_grid(vbox_zone)
	add_toggle_row(grid_holsters, "Zone Icons", ["On", "Off"], 0 if autoload._holster_holos_enabled else 1, "_on_cfg_holster_holos")
	add_stepper_row(grid_holsters, "Zone Radius", autoload._holster_zone_radius, 0.05, 0.5, 0.01, "_on_cfg_hz_radius")
	var zone_names := ["1: R.Shoulder", "2: R.Hip", "3: L.Hip", "4: Chest"]
	for zi in range(4):
		var slot = zi + 1
		var o: Vector3 = autoload._holster_offsets[slot]
		mk_header(vbox_zone, zone_names[zi])
		var grid_z = mk_grid(vbox_zone)
		add_stepper_row(grid_z, "X (L/R)", o.x, -0.6, 0.6, 0.01, "_on_cfg_hz_x_" + str(slot))
		add_stepper_row(grid_z, "Y (U/D)", o.y, -1.0, 0.2, 0.01, "_on_cfg_hz_y_" + str(slot))
		add_stepper_row(grid_z, "Z (F/B)", o.z, -0.5, 0.5, 0.01, "_on_cfg_hz_z_" + str(slot))

	mk_sep(vbox_zone)

	mk_header(vbox_zone, "Bag Zone (Inventory)")
	var grid_bag = mk_grid(vbox_zone)
	add_stepper_row(grid_bag, "Radius", autoload._bag_zone_radius, 0.05, 0.8, 0.01, "_on_cfg_bag_radius")
	add_stepper_row(grid_bag, "X (L/R)", autoload._bag_zone_offset.x, -0.5, 0.5, 0.01, "_on_cfg_bag_x")
	add_stepper_row(grid_bag, "Y (U/D)", autoload._bag_zone_offset.y, -0.5, 0.5, 0.01, "_on_cfg_bag_y")
	add_stepper_row(grid_bag, "Z (F/B)", autoload._bag_zone_offset.z, 0.0, 0.8, 0.01, "_on_cfg_bag_z")

	mk_sep(vbox_zone)

	mk_header(vbox_zone, "NVG Zone (Above Head)")
	var grid_nvg = mk_grid(vbox_zone)
	add_stepper_row(grid_nvg, "Radius", autoload._nvg_zone_radius, 0.05, 0.5, 0.01, "_on_cfg_nvg_radius")
	add_stepper_row(grid_nvg, "Y (Height)", autoload._nvg_zone_offset.y, 0.0, 0.6, 0.01, "_on_cfg_nvg_y")
	add_stepper_row(grid_nvg, "Brightness", autoload._nvg_brightness, 1.0, 5.0, 0.25, "_on_cfg_nvg_brightness")
	add_toggle_row(grid_nvg, "Mono Vision", ["Off", "On"], 1 if autoload._nvg_mono else 0, "_on_cfg_nvg_mono")

	# Tab 2: Calibrate
	var scroll_cal = ScrollContainer.new()
	scroll_cal.name = "Calibrate"
	scroll_cal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_cal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll_cal)
	var vbox_cal = VBoxContainer.new()
	vbox_cal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_cal.add_child(vbox_cal)

	mk_header(vbox_cal, "Wrist Watch")
	var grid_watch = mk_grid(vbox_cal)
	add_toggle_row(grid_watch, "Glance Reveal", ["Off", "On"], 1 if autoload._watch_glance_enabled else 0, "_on_cfg_watch_glance")
	add_stepper_row(grid_watch, "Glance Angle", autoload._watch_glance_angle, 20.0, 70.0, 5.0, "_on_cfg_watch_angle")
	add_stepper_row(grid_watch, "Glance Fade", autoload._watch_fade_speed, 2.0, 20.0, 1.0, "_on_cfg_watch_fade")
	add_stepper_row(grid_watch, "Size", autoload._watch_size, 0.04, 0.50, 0.01, "_on_cfg_watch_size")
	add_stepper_row(grid_watch, "X (L/R)", autoload._watch_offset.x, -0.5, 0.5, 0.01, "_on_cfg_watch_x")
	add_stepper_row(grid_watch, "Y (U/D)", autoload._watch_offset.y, -0.5, 0.5, 0.01, "_on_cfg_watch_y")
	add_stepper_row(grid_watch, "Z (F/B)", autoload._watch_offset.z, -0.5, 0.5, 0.01, "_on_cfg_watch_z")
	add_stepper_row(grid_watch, "Rot X", autoload._watch_rot.x, -180.0, 180.0, 5.0, "_on_cfg_watch_rot_x")
	add_stepper_row(grid_watch, "Rot Y", autoload._watch_rot.y, -180.0, 180.0, 5.0, "_on_cfg_watch_rot_y")
	add_stepper_row(grid_watch, "Rot Z", autoload._watch_rot.z, -180.0, 180.0, 5.0, "_on_cfg_watch_rot_z")

	mk_sep(vbox_cal)

	mk_header(vbox_cal, "Hand Models")
	mk_header(vbox_cal, "Left Hand")
	var grid_hand_l = mk_grid(vbox_cal)
	add_stepper_row(grid_hand_l, "X (L/R)", autoload.HAND_GLTF_OFFSET_LEFT.x, -0.2, 0.2, 0.005, "_on_cfg_hand_l_x")
	add_stepper_row(grid_hand_l, "Y (U/D)", autoload.HAND_GLTF_OFFSET_LEFT.y, -0.2, 0.2, 0.005, "_on_cfg_hand_l_y")
	add_stepper_row(grid_hand_l, "Z (F/B)", autoload.HAND_GLTF_OFFSET_LEFT.z, -0.2, 0.2, 0.005, "_on_cfg_hand_l_z")
	add_stepper_row(grid_hand_l, "Rot X", autoload.HAND_GLTF_ROTATION_LEFT.x, -180.0, 180.0, 5.0, "_on_cfg_hand_l_rx")
	add_stepper_row(grid_hand_l, "Rot Y", autoload.HAND_GLTF_ROTATION_LEFT.y, -180.0, 180.0, 5.0, "_on_cfg_hand_l_ry")
	add_stepper_row(grid_hand_l, "Rot Z", autoload.HAND_GLTF_ROTATION_LEFT.z, -180.0, 180.0, 5.0, "_on_cfg_hand_l_rz")
	mk_header(vbox_cal, "Right Hand")
	var grid_hand_r = mk_grid(vbox_cal)
	add_stepper_row(grid_hand_r, "X (L/R)", autoload.HAND_GLTF_OFFSET_RIGHT.x, -0.2, 0.2, 0.005, "_on_cfg_hand_r_x")
	add_stepper_row(grid_hand_r, "Y (U/D)", autoload.HAND_GLTF_OFFSET_RIGHT.y, -0.2, 0.2, 0.005, "_on_cfg_hand_r_y")
	add_stepper_row(grid_hand_r, "Z (F/B)", autoload.HAND_GLTF_OFFSET_RIGHT.z, -0.2, 0.2, 0.005, "_on_cfg_hand_r_z")
	add_stepper_row(grid_hand_r, "Rot X", autoload.HAND_GLTF_ROTATION_RIGHT.x, -180.0, 180.0, 5.0, "_on_cfg_hand_r_rx")
	add_stepper_row(grid_hand_r, "Rot Y", autoload.HAND_GLTF_ROTATION_RIGHT.y, -180.0, 180.0, 5.0, "_on_cfg_hand_r_ry")
	add_stepper_row(grid_hand_r, "Rot Z", autoload.HAND_GLTF_ROTATION_RIGHT.z, -180.0, 180.0, 5.0, "_on_cfg_hand_r_rz")

	mk_sep(vbox_cal)

	mk_header(vbox_cal, "Primary Weapon Sling")
	var grid_sling = mk_grid(vbox_cal)
	add_stepper_row(grid_sling, "X (L/R)", autoload._sling_offset.x, -0.6, 0.6, 0.01, "_on_cfg_sling_x")
	add_stepper_row(grid_sling, "Y (U/D)", autoload._sling_offset.y, -0.8, 0.2, 0.01, "_on_cfg_sling_y")
	add_stepper_row(grid_sling, "Z (F/B)", autoload._sling_offset.z, -0.6, 0.2, 0.01, "_on_cfg_sling_z")
	add_stepper_row(grid_sling, "Rot X", autoload._sling_rot_offset.x, -180.0, 180.0, 5.0, "_on_cfg_sling_rx")
	add_stepper_row(grid_sling, "Rot Y", autoload._sling_rot_offset.y, -180.0, 180.0, 5.0, "_on_cfg_sling_ry")
	add_stepper_row(grid_sling, "Rot Z", autoload._sling_rot_offset.z, -180.0, 180.0, 5.0, "_on_cfg_sling_rz")

	# Tab 3: Info/Controls
	var scroll_info = ScrollContainer.new()
	scroll_info.name = "Controls"
	scroll_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll_info)

	var info_text = RichTextLabel.new()
	info_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_text.size_flags_vertical = Control.SIZE_FILL
	info_text.fit_content = true
	info_text.bbcode_enabled = true
	info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_text.add_theme_font_size_override("normal_font_size", 18)
	info_text.add_theme_font_size_override("bold_font_size", 20)

	if autoload._readme_bbcode_cache.is_empty():
		var controls_path = "res://resources/controls.md"
		if FileAccess.file_exists(controls_path):
			var file = FileAccess.open(controls_path, FileAccess.READ)
			var raw_md = file.get_as_text()
			file.close()
			autoload._readme_bbcode_cache = parse_vostok_readme(raw_md)
		else:
			autoload._readme_bbcode_cache = "[color=gray]controls.md not found in VMZ[/color]"
	info_text.append_text(autoload._readme_bbcode_cache)

	scroll_info.add_child(info_text)

	# Save & Close (pinned below tabs - always visible)
	var btn_sep = HSeparator.new()
	btn_sep.add_theme_constant_override("separation", 10)
	outer.add_child(btn_sep)

	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.custom_minimum_size = Vector2(0, 52)
	outer.add_child(btn_row)

	var save_btn = mk_btn("Save & Close", Color(0.2, 0.7, 0.3))
	save_btn.pressed.connect(Callable(self, "_on_cfg_save_close"))
	btn_row.add_child(save_btn)

	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(20, 0)
	btn_row.add_child(spacer)

	var cancel_btn = mk_btn("Cancel", Color(0.7, 0.3, 0.3))
	cancel_btn.pressed.connect(Callable(self, "close_config_screen"))
	btn_row.add_child(cancel_btn)

	autoload._config_panel_vp.add_child(root)


# UI builder helpers

func mk_sep(parent: Control) -> void:
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 12)
	parent.add_child(sep)


func mk_header(parent: Control, text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	parent.add_child(lbl)


func mk_grid(parent: Control) -> GridContainer:
	var g = GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 8)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(g)
	return g


func mk_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	return lbl


func mk_btn(text: String, color: Color) -> Button:
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


func mk_style(color: Color) -> StyleBoxFlat:
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


# README Parser for UI
func parse_vostok_readme(md: String) -> String:
	var bb = md
	var regex = RegEx.new()

	# 1. Table Parser (Manual loop is safer than regex for complex MD tables)
	var lines = bb.split("\n")
	var in_table = false
	var new_lines = []
	var table_rows = []
	var max_cols = 0

	for line in lines:
		var stripped = line.strip_edges()
		if stripped.begins_with("|") and stripped.ends_with("|"):
			if "---" in line: continue
			in_table = true
			var cells = line.split("|", false)
			max_cols = max(max_cols, cells.size())
			table_rows.append(cells)
		else:
			if in_table:
				var table_bb = "\n[table=" + str(max_cols) + "]"
				for row in table_rows:
					for cell in row:
						table_bb += "[cell][color=#e0e0e0] " + cell.strip_edges() + " [/color][/cell]"
				table_bb += "[/table]\n"
				new_lines.append(table_bb)
				table_rows = []
				max_cols = 0
				in_table = false
			new_lines.append(line)
	# Flush any table that ends at EOF
	if in_table and table_rows.size() > 0:
		var table_bb = "\n[table=" + str(max_cols) + "]"
		for row in table_rows:
			for cell in row:
				table_bb += "[cell][color=#e0e0e0] " + cell.strip_edges() + " [/color][/cell]"
		table_bb += "[/table]\n"
		new_lines.append(table_bb)
	bb = "\n".join(new_lines)

	# 2. Markdown Parsing using RegEx.sub(subject, replacement, all=true)

	# Headers (H1-H3)
	regex.compile(r"(?m)^# (.*)")
	bb = regex.sub(bb, "[font_size=32][b][color=#e6da99]$1[/color][/b][/font_size]", true)

	regex.compile(r"(?m)^## (.*)")
	bb = regex.sub(bb, "\n[font_size=24][b][color=#b3ccff]$1[/color][/b][/font_size]", true)

	regex.compile(r"(?m)^### (.*)")
	bb = regex.sub(bb, "\n[font_size=20][b][color=#8eb4ff]$1[/color][/b][/font_size]", true)

	# Bold Text
	regex.compile(r"\*\*(.*?)\*\*")
	bb = regex.sub(bb, "[b]$1[/b]", true)

	# Blockquotes
	regex.compile(r"(?m)^> (.*)")
	bb = regex.sub(bb, "[color=#99ffcc][i]$1[/i][/color]", true)

	# Code Blocks (Monospace feel)
	regex.compile(r"(?s)```(.*?)```")
	bb = regex.sub(bb, "[indent][color=#aaaaaa][font_size=16]$1[/font_size][/color][/indent]", true)

	# Inline code
	regex.compile(r"`([^`]+)`")
	bb = regex.sub(bb, "[color=#aaaaaa][font_size=16]$1[/font_size][/color]", true)

	return bb


# Row builders

func add_toggle_row(grid: GridContainer, label: String, options: Array, active: int, callback_name: String) -> void:
	grid.add_child(mk_label(label))
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
	highlight_toggle(buttons, active)
	for i in range(buttons.size()):
		var idx = i
		var b_arr = buttons
		var cb = callback_name
		buttons[i].pressed.connect(Callable(self, "_on_toggle_pressed").bind(b_arr, idx, cb))
	grid.add_child(hbox)


func _on_toggle_pressed(buttons: Array, idx: int, callback_name: String) -> void:
	highlight_toggle(buttons, idx)
	call(callback_name, idx)


func highlight_toggle(buttons: Array, active: int) -> void:
	for i in range(buttons.size()):
		var btn = buttons[i] as Button
		if i == active:
			btn.add_theme_stylebox_override("normal", mk_style(Color(0.2, 0.5, 0.8)))
			btn.add_theme_stylebox_override("hover", mk_style(Color(0.3, 0.6, 0.9)))
		else:
			btn.add_theme_stylebox_override("normal", mk_style(Color(0.25, 0.25, 0.3)))
			btn.add_theme_stylebox_override("hover", mk_style(Color(0.35, 0.35, 0.4)))


func add_stepper_row(grid: GridContainer, label: String, value: float, min_val: float, max_val: float, step: float, callback_name: String) -> void:
	grid.add_child(mk_label(label))
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)

	var dec_btn = mk_btn("-", Color(0.35, 0.35, 0.4))
	dec_btn.custom_minimum_size = Vector2(40, 36)
	hbox.add_child(dec_btn)

	var val_lbl = Label.new()
	val_lbl.text = fmt_val(value)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.custom_minimum_size = Vector2(70, 0)
	val_lbl.add_theme_font_size_override("font_size", 18)
	val_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	hbox.add_child(val_lbl)

	var inc_btn = mk_btn("+", Color(0.35, 0.35, 0.4))
	inc_btn.custom_minimum_size = Vector2(40, 36)
	hbox.add_child(inc_btn)

	dec_btn.pressed.connect(Callable(self, "_on_stepper_dec").bind(val_lbl, value, min_val, max_val, step, callback_name))
	inc_btn.pressed.connect(Callable(self, "_on_stepper_inc").bind(val_lbl, value, min_val, max_val, step, callback_name))

	grid.add_child(hbox)


func _on_stepper_dec(val_lbl: Label, current: float, min_val: float, max_val: float, step: float, callback_name: String) -> void:
	var new_val = clampf(snapped(current - step, step), min_val, max_val)
	val_lbl.text = fmt_val(new_val)
	# Update the bound args for next press by reconnecting
	reconnect_stepper(val_lbl, new_val, min_val, max_val, step, callback_name)
	call(callback_name, new_val)


func _on_stepper_inc(val_lbl: Label, current: float, min_val: float, max_val: float, step: float, callback_name: String) -> void:
	var new_val = clampf(snapped(current + step, step), min_val, max_val)
	val_lbl.text = fmt_val(new_val)
	reconnect_stepper(val_lbl, new_val, min_val, max_val, step, callback_name)
	call(callback_name, new_val)


func reconnect_stepper(val_lbl: Label, new_val: float, min_val: float, max_val: float, step: float, callback_name: String) -> void:
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


func fmt_val(v: float) -> String:
	if absf(v - roundf(v)) < 0.001:
		return str(int(v))
	return str(snapped(v, 0.01))


# Config callbacks

func _on_cfg_turn(idx: int) -> void:
	autoload.use_snap_turn = (idx == 0)


func _on_cfg_snap_deg(val: float) -> void:
	autoload.snap_turn_degrees = val


func _on_cfg_smooth_spd(val: float) -> void:
	autoload.smooth_turn_speed = val


func _on_cfg_vignette(idx: int) -> void:
	autoload._vignette_enabled = (idx == 0)


func _on_cfg_vignette_str(val: float) -> void:
	autoload._vignette_strength = val


func _on_cfg_render_scale(val: float) -> void:
	autoload._render_scale = val
	if autoload.xr_interface and is_instance_valid(autoload.xr_interface):
		autoload.xr_interface.render_target_size_multiplier = autoload._render_scale


func _on_cfg_2h_smooth(idx: int) -> void:
	autoload._two_hand_smooth_enabled = (idx == 0)


func _on_cfg_2h_smooth_spd(val: float) -> void:
	autoload._two_hand_smooth_speed = val


func restore_walk_sway_processing(weapon_rig: Node3D) -> void:
	if not weapon_rig or not is_instance_valid(weapon_rig):
		return
	for node_name in autoload._WALK_SWAY_NODES:
		var n = autoload._walk_chain_node(weapon_rig, node_name)
		if n:
			n.set_process(true)
			n.set_physics_process(true)


func _on_cfg_walk_sway(idx: int) -> void:
	var was_disabled = autoload._disable_walk_sway
	autoload._disable_walk_sway = (idx == 1)
	if was_disabled and not autoload._disable_walk_sway and autoload._cached_weapon_rig and is_instance_valid(autoload._cached_weapon_rig):
		restore_walk_sway_processing(autoload._cached_weapon_rig)


func _on_cfg_hud_dist(val: float) -> void:
	autoload._hud_distance = val
	apply_hud_settings()


func _on_cfg_hud_wid(val: float) -> void:
	autoload._hud_width = val
	apply_hud_settings()


func _on_cfg_hud_hgt(val: float) -> void:
	autoload._hud_height_offset = val
	apply_hud_settings()


func _on_cfg_hud_lr(val: float) -> void:
	autoload._hud_lr_offset = val
	apply_hud_settings()


func _on_cfg_hud_follow(idx: int) -> void:
	autoload._hud_smooth_follow = (idx == 1)
	apply_hud_follow_mode()


func _on_cfg_hud_smooth_spd(val: float) -> void:
	autoload._hud_smooth_speed = val


func _on_cfg_hud_spread(val: float) -> void:
	autoload._hud_spread = val
	apply_hud_spread()


func _on_cfg_menu_dist(val: float) -> void:
	autoload._menu_distance = val


func _on_cfg_menu_wid(val: float) -> void:
	autoload._menu_width = val


func _on_cfg_menu_lr(val: float) -> void:
	autoload._menu_lr_offset = val


func _on_cfg_laser_x(val: float) -> void:
	autoload._menu_laser_uv_x = val


func _on_cfg_laser_y(val: float) -> void:
	autoload._menu_laser_uv_y = val


func _on_cfg_hand(idx: int) -> void:
	if idx == 0:
		autoload._config_dominant_hand = "right"
	else:
		autoload._config_dominant_hand = "left"
	# Recreate watch on the other wrist
	autoload._destroy_watch_mesh()
	autoload._create_watch_mesh()


func _on_cfg_holster_mirror(idx: int) -> void:
	autoload._holster_zones_mirrored = (idx == 1)


func _on_cfg_auto_recenter(idx: int) -> void:
	autoload._auto_recenter_enabled = (idx == 0)


func _on_cfg_gun_config(idx: int) -> void:
	autoload._gun_config_enabled = (idx == 1)
	if not autoload._gun_config_enabled:
		autoload._adjust_mode = false
		autoload._fg_adjust_mode = false
	autoload._log("[VR Mod] Gun config: ", "on" if autoload._gun_config_enabled else "off")


func _on_cfg_laser_always_on(idx: int) -> void:
	autoload._laser_always_on = (idx == 0)
	autoload._log("[VR Mod] Laser always on: ", autoload._laser_always_on)


func _on_cfg_move_direction(idx: int) -> void:
	autoload._move_direction_mode = "camera" if idx == 0 else "controller"
	autoload._log("[VR Mod] Move direction: ", autoload._move_direction_mode)


func _on_cfg_move_direction_hand(idx: int) -> void:
	autoload._move_direction_hand = "left" if idx == 0 else "right"
	autoload._log("[VR Mod] Move direction hand: ", autoload._move_direction_hand)


func _on_cfg_standing_mode(idx: int) -> void:
	autoload._standing_mode = (idx == 1)
	if autoload.xr_interface and is_instance_valid(autoload.xr_interface):
		if autoload._standing_mode:
			autoload.xr_interface.play_area_mode = XRInterface.XR_PLAY_AREA_ROOMSCALE
		else:
			autoload.xr_interface.play_area_mode = XRInterface.XR_PLAY_AREA_SITTING
	if not autoload._standing_mode:
		if autoload._physical_crouch_active:
			autoload._inject_action("crouch", true)
			autoload._inject_action("crouch", false)
		autoload._physical_crouch_active = false
		autoload._physical_crouch_resnap = 0
		autoload._standing_height_ref = 0.0
	# Re-snap origin after a few frames so the new reference space has settled
	autoload._standing_mode_resnap = 3
	autoload._log("[VR Mod] Tracking mode: ", "standing" if autoload._standing_mode else "sitting")


func _on_cfg_holster_holos(idx: int) -> void:
	autoload._holster_holos_enabled = (idx == 0)


func _on_cfg_hz_radius(val: float) -> void:
	autoload._holster_zone_radius = val


func _on_cfg_hz_x_1(val: float) -> void:
	autoload._holster_offsets[1].x = val
func _on_cfg_hz_y_1(val: float) -> void:
	autoload._holster_offsets[1].y = val
func _on_cfg_hz_z_1(val: float) -> void:
	autoload._holster_offsets[1].z = val

func _on_cfg_hz_x_2(val: float) -> void:
	autoload._holster_offsets[2].x = val
func _on_cfg_hz_y_2(val: float) -> void:
	autoload._holster_offsets[2].y = val
func _on_cfg_hz_z_2(val: float) -> void:
	autoload._holster_offsets[2].z = val

func _on_cfg_hz_x_3(val: float) -> void:
	autoload._holster_offsets[3].x = val
func _on_cfg_hz_y_3(val: float) -> void:
	autoload._holster_offsets[3].y = val
func _on_cfg_hz_z_3(val: float) -> void:
	autoload._holster_offsets[3].z = val

func _on_cfg_hz_x_4(val: float) -> void:
	autoload._holster_offsets[4].x = val
func _on_cfg_hz_y_4(val: float) -> void:
	autoload._holster_offsets[4].y = val
func _on_cfg_hz_z_4(val: float) -> void:
	autoload._holster_offsets[4].z = val

func _on_cfg_bag_radius(val: float) -> void:
	autoload._bag_zone_radius = val
func _on_cfg_bag_x(val: float) -> void:
	autoload._bag_zone_offset.x = val
func _on_cfg_bag_y(val: float) -> void:
	autoload._bag_zone_offset.y = val
func _on_cfg_bag_z(val: float) -> void:
	autoload._bag_zone_offset.z = val

func _on_cfg_nvg_radius(val: float) -> void:
	autoload._nvg_zone_radius = val
func _on_cfg_nvg_y(val: float) -> void:
	autoload._nvg_zone_offset.y = val
func _on_cfg_nvg_brightness(val: float) -> void:
	autoload._nvg_brightness = val
	var nvg_sys = autoload._ensure_nvg()
	if nvg_sys.nvg_overlay_installed and nvg_sys.nvg_overlay_mesh and nvg_sys.nvg_overlay_mesh.material_override:
		(nvg_sys.nvg_overlay_mesh.material_override as ShaderMaterial).set_shader_parameter("brightness", val)
func _on_cfg_nvg_mono(idx: int) -> void:
	autoload._nvg_mono = (idx == 1)
	var nvg_sys = autoload._ensure_nvg()
	if nvg_sys.nvg_active and nvg_sys.nvg_overlay_mesh and nvg_sys.nvg_overlay_mesh.material_override:
		var mat = nvg_sys.nvg_overlay_mesh.material_override as ShaderMaterial
		if autoload._nvg_mono:
			nvg_sys.create_nvg_mono_viewport()
			nvg_sys.nvg_mono_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			mat.set_shader_parameter("mono_tex", nvg_sys.nvg_mono_viewport.get_texture())
		else:
			if nvg_sys.nvg_mono_viewport:
				nvg_sys.nvg_mono_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		mat.set_shader_parameter("use_mono", autoload._nvg_mono)


func watch_rot_basis() -> Basis:
	# Base orientation: -90 X makes the quad face upward (palm-up wrist position).
	# _watch_rot is a user offset applied first (in the un-tilted local space),
	# giving three distinct independent adjustment axes.
	var base = Basis(Vector3(1.0, 0.0, 0.0), deg_to_rad(-90.0))
	var offset = Basis.from_euler(Vector3(deg_to_rad(autoload._watch_rot.x), deg_to_rad(autoload._watch_rot.y), deg_to_rad(autoload._watch_rot.z)))
	return base * offset


func _on_cfg_watch_glance(idx: int) -> void:
	autoload._watch_glance_enabled = (idx == 1)

func _on_cfg_watch_angle(val: float) -> void:
	autoload._watch_glance_angle = val

func _on_cfg_watch_fade(val: float) -> void:
	autoload._watch_fade_speed = val

func _on_cfg_watch_size(val: float) -> void:
	autoload._watch_size = val
	if autoload._watch_mesh:
		(autoload._watch_mesh.mesh as QuadMesh).size = Vector2(autoload._watch_size, autoload._watch_size)

func _on_cfg_watch_spread(val: float) -> void:
	autoload._watch_spread = val
	if not autoload._interface_open:
		autoload._hud_spread_active = autoload._watch_spread
		apply_hud_spread()

func _on_cfg_watch_x(val: float) -> void:
	autoload._watch_offset.x = val
	if autoload._watch_mesh:
		autoload._watch_mesh.position = autoload._watch_offset

func _on_cfg_watch_y(val: float) -> void:
	autoload._watch_offset.y = val
	if autoload._watch_mesh:
		autoload._watch_mesh.position = autoload._watch_offset

func _on_cfg_watch_z(val: float) -> void:
	autoload._watch_offset.z = val
	if autoload._watch_mesh:
		autoload._watch_mesh.position = autoload._watch_offset

func _on_cfg_watch_rot_x(val: float) -> void:
	autoload._watch_rot.x = val
	if autoload._watch_mesh:
		autoload._watch_mesh.basis = watch_rot_basis()

func _on_cfg_watch_rot_y(val: float) -> void:
	autoload._watch_rot.y = val
	if autoload._watch_mesh:
		autoload._watch_mesh.basis = watch_rot_basis()

func _on_cfg_watch_rot_z(val: float) -> void:
	autoload._watch_rot.z = val
	if autoload._watch_mesh:
		autoload._watch_mesh.basis = watch_rot_basis()

func _on_cfg_hand_l_x(val: float) -> void:
	autoload.HAND_GLTF_OFFSET_LEFT.x = val
	if autoload._hand_wrapper_left:
		autoload._hand_wrapper_left.position = autoload.HAND_GLTF_OFFSET_LEFT

func _on_cfg_hand_l_y(val: float) -> void:
	autoload.HAND_GLTF_OFFSET_LEFT.y = val
	if autoload._hand_wrapper_left:
		autoload._hand_wrapper_left.position = autoload.HAND_GLTF_OFFSET_LEFT

func _on_cfg_hand_l_z(val: float) -> void:
	autoload.HAND_GLTF_OFFSET_LEFT.z = val
	if autoload._hand_wrapper_left:
		autoload._hand_wrapper_left.position = autoload.HAND_GLTF_OFFSET_LEFT

func _on_cfg_hand_l_rx(val: float) -> void:
	autoload.HAND_GLTF_ROTATION_LEFT.x = val
	if autoload._hand_wrapper_left:
		autoload._hand_wrapper_left.rotation_degrees = autoload.HAND_GLTF_ROTATION_LEFT

func _on_cfg_hand_l_ry(val: float) -> void:
	autoload.HAND_GLTF_ROTATION_LEFT.y = val
	if autoload._hand_wrapper_left:
		autoload._hand_wrapper_left.rotation_degrees = autoload.HAND_GLTF_ROTATION_LEFT

func _on_cfg_hand_l_rz(val: float) -> void:
	autoload.HAND_GLTF_ROTATION_LEFT.z = val
	if autoload._hand_wrapper_left:
		autoload._hand_wrapper_left.rotation_degrees = autoload.HAND_GLTF_ROTATION_LEFT

func _on_cfg_hand_r_x(val: float) -> void:
	autoload.HAND_GLTF_OFFSET_RIGHT.x = val
	if autoload._hand_wrapper_right:
		autoload._hand_wrapper_right.position = autoload.HAND_GLTF_OFFSET_RIGHT

func _on_cfg_hand_r_y(val: float) -> void:
	autoload.HAND_GLTF_OFFSET_RIGHT.y = val
	if autoload._hand_wrapper_right:
		autoload._hand_wrapper_right.position = autoload.HAND_GLTF_OFFSET_RIGHT

func _on_cfg_hand_r_z(val: float) -> void:
	autoload.HAND_GLTF_OFFSET_RIGHT.z = val
	if autoload._hand_wrapper_right:
		autoload._hand_wrapper_right.position = autoload.HAND_GLTF_OFFSET_RIGHT

func _on_cfg_hand_r_rx(val: float) -> void:
	autoload.HAND_GLTF_ROTATION_RIGHT.x = val
	if autoload._hand_wrapper_right:
		autoload._hand_wrapper_right.rotation_degrees = autoload.HAND_GLTF_ROTATION_RIGHT

func _on_cfg_hand_r_ry(val: float) -> void:
	autoload.HAND_GLTF_ROTATION_RIGHT.y = val
	if autoload._hand_wrapper_right:
		autoload._hand_wrapper_right.rotation_degrees = autoload.HAND_GLTF_ROTATION_RIGHT

func _on_cfg_hand_r_rz(val: float) -> void:
	autoload.HAND_GLTF_ROTATION_RIGHT.z = val
	if autoload._hand_wrapper_right:
		autoload._hand_wrapper_right.rotation_degrees = autoload.HAND_GLTF_ROTATION_RIGHT

func _on_cfg_sling_x(val: float) -> void:
	autoload._sling_offset.x = val

func _on_cfg_sling_y(val: float) -> void:
	autoload._sling_offset.y = val

func _on_cfg_sling_z(val: float) -> void:
	autoload._sling_offset.z = val

func _on_cfg_sling_rx(val: float) -> void:
	autoload._sling_rot_offset.x = val

func _on_cfg_sling_ry(val: float) -> void:
	autoload._sling_rot_offset.y = val

func _on_cfg_sling_rz(val: float) -> void:
	autoload._sling_rot_offset.z = val

func _on_cfg_save_close() -> void:
	save_full_config()
	close_config_screen()


func _on_cfg_recenter() -> void:
	autoload._attach_rig_to_camera()


# Apply helpers

func apply_hud_settings() -> void:
	if not autoload.hud_mesh:
		return
	var aspect = float(autoload.hud_viewport.size.y) / float(autoload.hud_viewport.size.x)
	(autoload.hud_mesh.mesh as QuadMesh).size = Vector2(autoload._hud_width, autoload._hud_width * aspect)
	if autoload.hud_mesh.get_parent() == autoload.xr_camera:
		autoload.hud_mesh.position = Vector3(autoload._hud_lr_offset, autoload._hud_height_offset, -autoload._hud_distance)


func apply_hud_follow_mode() -> void:
	if not autoload.hud_mesh:
		return
	if autoload._hud_smooth_follow:
		# Seed yaw from current camera so there's no snap on first frame
		if autoload.xr_camera:
			autoload._hud_yaw = autoload.xr_camera.global_rotation.y
		# Switch to world-space
		if autoload.hud_mesh.get_parent() == autoload.xr_camera:
			autoload.xr_camera.remove_child(autoload.hud_mesh)
			autoload.get_tree().root.add_child(autoload.hud_mesh)
			# Place immediately at correct position using seeded yaw
			var lagged_basis = Basis(Vector3.UP, autoload._hud_yaw)
			autoload.hud_mesh.global_position = autoload.xr_camera.global_position + lagged_basis * Vector3(autoload._hud_lr_offset, autoload._hud_height_offset, -autoload._hud_distance)
			autoload.hud_mesh.global_rotation = Vector3(0.0, autoload._hud_yaw, 0.0)
	else:
		# Switch to head-locked
		if autoload.hud_mesh.get_parent() != autoload.xr_camera:
			if autoload.hud_mesh.get_parent():
				autoload.hud_mesh.get_parent().remove_child(autoload.hud_mesh)
			autoload.xr_camera.add_child(autoload.hud_mesh)
			autoload.hud_mesh.position = Vector3(autoload._hud_lr_offset, autoload._hud_height_offset, -autoload._hud_distance)
			autoload.hud_mesh.rotation = Vector3.ZERO


func apply_hud_spread() -> void:
	var hud_node = autoload.get_tree().root.get_node_or_null("Map/Core/UI/HUD")
	if not hud_node:
		return
	# Bottom stats: Vitals (left) and Medical (right)
	var stats = hud_node.get_node_or_null("Stats")
	if stats:
		var vitals = stats.get_node_or_null("Vitals")
		if vitals and vitals is Control:
			vitals.position.x = -960.0 * autoload._hud_spread_active
		var medical = stats.get_node_or_null("Medical")
		if medical and medical is Control:
			medical.position.x = 960.0 * autoload._hud_spread_active
	# Top-left info (Map/FPS) - anchored top-left, default pos=(32, 32)
	var info = hud_node.get_node_or_null("Info")
	if info and info is Control:
		# Move inward from left edge
		var half_w = 1920.0  # half of 3840 HUD width
		var default_x = 32.0
		info.position.x = half_w - (half_w - default_x) * autoload._hud_spread_active


# Config laser & click

func update_config_laser() -> void:
	if not autoload._config_panel_quad or not autoload._config_panel_vp or not autoload._laser_mesh:
		return
	var now_msec := Time.get_ticks_msec()
	if now_msec < _config_laser_next_msec:
		return
	_config_laser_next_msec = now_msec + CONFIG_LASER_INTERVAL_MSEC
	var controller = autoload._get_controller(autoload._config_dominant_hand)
	if not controller or not controller.get_is_active():
		return
	var ray_origin = controller.global_position
	var ray_dir = -controller.global_basis.z
	var hit_pos = autoload._ray_quad_intersection(ray_origin, ray_dir, autoload._config_panel_quad)
	if hit_pos == Vector3.INF:
		return
	var local_pos = autoload._config_panel_quad.global_transform.affine_inverse() * hit_pos
	var quad_size = (autoload._config_panel_quad.mesh as QuadMesh).size
	var uv_x = (local_pos.x + quad_size.x / 2.0) / quad_size.x
	var uv_y = (-local_pos.y + quad_size.y / 2.0) / quad_size.y
	if uv_x >= 0 and uv_x <= 1 and uv_y >= 0 and uv_y <= 1:
		autoload._config_laser_pos = Vector2(uv_x * autoload._config_panel_vp.size.x, uv_y * autoload._config_panel_vp.size.y)
		# Send mouse motion to config viewport
		var motion = InputEventMouseMotion.new()
		motion.position = autoload._config_laser_pos
		motion.global_position = autoload._config_laser_pos
		autoload._config_panel_vp.push_input(motion)
		# Update laser visual
		var dist = ray_origin.distance_to(hit_pos) - 0.01
		if dist > 0.1:
			(autoload._laser_mesh.mesh as CylinderMesh).height = dist
			autoload._laser_mesh.position.z = -dist / 2.0
			autoload._laser_mesh.visible = true


func inject_config_click(pressed: bool) -> void:
	if not autoload._config_panel_vp:
		return
	var ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = autoload._config_laser_pos
	ev.global_position = autoload._config_laser_pos
	autoload._config_panel_vp.push_input(ev)


func scroll_config_panel(amount: float) -> void:
	if not autoload._config_panel_vp:
		return
	var tabs = autoload._config_panel_vp.get_node_or_null("CfgRoot/CfgOuter/CfgTabs")
	if not tabs or not (tabs is TabContainer):
		return
	var active_tab = (tabs as TabContainer).get_current_tab_control()
	if active_tab and active_tab is ScrollContainer:
		(active_tab as ScrollContainer).scroll_vertical += int(amount)


# Save full config

func patch_resume_state(slot: int, hand: String) -> void:
	autoload._resume_slot = slot
	autoload._resume_hand = hand
	autoload._ensure_config_io().mutate(Callable(self, "apply_resume_state").bind(slot, hand))


func apply_resume_state(data: Dictionary, slot: int, hand: String) -> void:
	data["resume"] = {"slot": slot, "hand": hand}


func save_full_config() -> void:
	if autoload._ensure_config_io().mutate(Callable(self, "full_config_mutator")):
		autoload._log("[VR Mod] Full config saved to: ", autoload._config_path)


func full_config_mutator(data: Dictionary) -> void:
	# XR
	data["xr"] = {"world_scale": autoload.world_scale, "render_scale": autoload._render_scale, "mouse_sens": autoload._mouse_sens_estimate}

	# Comfort
	var turn_type = "snap"
	if not autoload.use_snap_turn:
		turn_type = "smooth"
	data["comfort"] = {
		"turn_type": turn_type,
		"snap_turn_degrees": autoload.snap_turn_degrees,
		"smooth_turn_speed": autoload.smooth_turn_speed,
		"vignette_enabled": autoload._vignette_enabled,
		"vignette_strength": autoload._vignette_strength,
		"two_hand_smooth_enabled": autoload._two_hand_smooth_enabled,
		"two_hand_smooth_speed": autoload._two_hand_smooth_speed,
		"walk_sway_enabled": not autoload._disable_walk_sway
	}

	# Controls
	data["controls"] = {
		"thumbstick_deadzone": autoload.thumbstick_deadzone,
		"dominant_hand": autoload._config_dominant_hand,
		"standing_mode": autoload._standing_mode,
		"gun_config_enabled": autoload._gun_config_enabled,
		"laser_always_on": autoload._laser_always_on,
		"move_direction_mode": autoload._move_direction_mode,
		"move_direction_hand": autoload._move_direction_hand,
		"holster_zones_mirrored": autoload._holster_zones_mirrored,
		"auto_recenter": autoload._auto_recenter_enabled
	}

	# HUD
	data["hud"] = {
		"width": autoload._hud_width,
		"distance": autoload._hud_distance,
		"height_offset": autoload._hud_height_offset,
		"lr_offset": autoload._hud_lr_offset,
		"smooth_follow": autoload._hud_smooth_follow,
		"smooth_speed": autoload._hud_smooth_speed,
		"spread": autoload._hud_spread
	}

	# Menu
	data["menu"] = {
		"width": autoload._menu_width,
		"distance": autoload._menu_distance,
		"lr_offset": autoload._menu_lr_offset,
		"laser_uv_x": autoload._menu_laser_uv_x,
		"laser_uv_y": autoload._menu_laser_uv_y
	}

	# Holsters (zone offsets + bag zone)
	var holster_offsets_data := {}
	for slot in [1, 2, 3, 4]:
		var o: Vector3 = autoload._holster_offsets[slot]
		holster_offsets_data[str(slot)] = {"x": snapped(o.x, 0.001), "y": snapped(o.y, 0.001), "z": snapped(o.z, 0.001)}
	data["holsters"] = {
		"zone_radius": autoload._holster_zone_radius,
		"holos_enabled": autoload._holster_holos_enabled,
		"offsets": holster_offsets_data,
		"bag": {
			"x": snapped(autoload._bag_zone_offset.x, 0.001),
			"y": snapped(autoload._bag_zone_offset.y, 0.001),
			"z": snapped(autoload._bag_zone_offset.z, 0.001),
			"radius": autoload._bag_zone_radius
		}
	}

	# NVG zone
	data["nvg_zone"] = {
		"y": snapped(autoload._nvg_zone_offset.y, 0.001),
		"radius": autoload._nvg_zone_radius,
		"brightness": autoload._nvg_brightness,
		"mono": autoload._nvg_mono
	}

	# Wrist watch
	data["watch"] = {
		"size": autoload._watch_size,
		"glance_enabled": autoload._watch_glance_enabled,
		"glance_angle": autoload._watch_glance_angle,
		"fade_speed": autoload._watch_fade_speed,
		"spread": autoload._watch_spread,
		"offset": {
			"x": snapped(autoload._watch_offset.x, 0.001),
			"y": snapped(autoload._watch_offset.y, 0.001),
			"z": snapped(autoload._watch_offset.z, 0.001)
		},
		"rot": {
			"x": snapped(autoload._watch_rot.x, 0.1),
			"y": snapped(autoload._watch_rot.y, 0.1),
			"z": snapped(autoload._watch_rot.z, 0.1)
		}
	}

	# Preserve weapon_offsets and foregrip local data so Save & Close never drops them
	var wo2 := {}
	for wname in autoload._weapon_grip_offsets:
		var o2 := autoload._weapon_grip_offsets[wname] as Vector3
		wo2[wname] = {
			"x": snapped(o2.x, 0.001),
			"y": snapped(o2.y, 0.001),
			"z": snapped(o2.z, 0.001),
			"rot": snapped(autoload._weapon_grip_rotations.get(wname, 0.0), 0.1)
		}
	data["weapon_offsets"] = wo2
	var fgp2 := {}
	for wname in autoload._weapon_fg_p_local:
		var p2: Vector3 = autoload._weapon_fg_p_local[wname]
		fgp2[wname] = {"x": snapped(p2.x, 0.0001), "y": snapped(p2.y, 0.0001), "z": snapped(p2.z, 0.0001)}
	data["foregrip_p_local"] = fgp2
	var fgr2 := {}
	for wname in autoload._weapon_fg_r_local:
		var b2: Basis = autoload._weapon_fg_r_local[wname]
		var q2 := b2.get_rotation_quaternion()
		fgr2[wname] = {"x": snapped(q2.x, 0.0001), "y": snapped(q2.y, 0.0001), "z": snapped(q2.z, 0.0001), "w": snapped(q2.w, 0.0001)}
	data["foregrip_r_local"] = fgr2

	# Hand models
	data["hand_models"] = {
		"left": {
			"x": snapped(autoload.HAND_GLTF_OFFSET_LEFT.x, 0.001),
			"y": snapped(autoload.HAND_GLTF_OFFSET_LEFT.y, 0.001),
			"z": snapped(autoload.HAND_GLTF_OFFSET_LEFT.z, 0.001),
			"rot": {
				"x": snapped(autoload.HAND_GLTF_ROTATION_LEFT.x, 0.1),
				"y": snapped(autoload.HAND_GLTF_ROTATION_LEFT.y, 0.1),
				"z": snapped(autoload.HAND_GLTF_ROTATION_LEFT.z, 0.1)
			}
		},
		"right": {
			"x": snapped(autoload.HAND_GLTF_OFFSET_RIGHT.x, 0.001),
			"y": snapped(autoload.HAND_GLTF_OFFSET_RIGHT.y, 0.001),
			"z": snapped(autoload.HAND_GLTF_OFFSET_RIGHT.z, 0.001),
			"rot": {
				"x": snapped(autoload.HAND_GLTF_ROTATION_RIGHT.x, 0.1),
				"y": snapped(autoload.HAND_GLTF_ROTATION_RIGHT.y, 0.1),
				"z": snapped(autoload.HAND_GLTF_ROTATION_RIGHT.z, 0.1)
			}
		}
	}

	# Resume state (persisted so weapon-drawn-on-exit restores VR control on next launch)
	data["resume"] = {"slot": autoload._resume_slot, "hand": autoload._resume_hand}

	# Primary weapon sling
	data["sling"] = {
		"x": snapped(autoload._sling_offset.x, 0.001),
		"y": snapped(autoload._sling_offset.y, 0.001),
		"z": snapped(autoload._sling_offset.z, 0.001),
		"rot": {
			"x": snapped(autoload._sling_rot_offset.x, 0.1),
			"y": snapped(autoload._sling_rot_offset.y, 0.1),
			"z": snapped(autoload._sling_rot_offset.z, 0.1)
		}
	}
