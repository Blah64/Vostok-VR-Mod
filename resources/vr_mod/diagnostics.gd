extends RefCounted

# diagnostics.gd
# F8/F9/F10/F11/F12 dump handlers and the helper recursors they depend on.
# Pure mechanical lift from vr_mod_init.gd. Holds no own state; reads
# autoload state via the back-reference.

var autoload: Node

func _init(p_autoload: Node) -> void:
	autoload = p_autoload


func force_debug_dump(label: String) -> void:
	if not autoload.game_camera or not is_instance_valid(autoload.game_camera):
		return
	var dump_path = autoload._log_path
	var f = FileAccess.open(dump_path, FileAccess.READ_WRITE)
	if not f:
		f = FileAccess.open(dump_path, FileAccess.WRITE)
	if f:
		f.seek_end(0)
		f.store_line("")
		f.store_line("=== " + label + " ===")
		f.store_line("Time: " + str(Time.get_ticks_msec()) + "ms")
		f.store_line("game_camera.current: " + str(autoload.game_camera.current))
		f.store_line("")
		var log_lines = []
		var snapshot = []
		snapshot_tree(autoload.game_camera, 0, 20, snapshot, log_lines)
		for line in log_lines:
			f.store_line(line)
		f.store_line("")
		# Scan for meshes starting from camera (not root) to reach deep weapon meshes
		f.store_line("=== All MeshInstance3D under Camera ===")
		var cam_meshes = []
		find_all_typed_under(autoload.game_camera, "MeshInstance3D", 0, 20, cam_meshes)
		for entry in cam_meshes:
			f.store_line(entry)
		if cam_meshes.is_empty():
			f.store_line("(none)")
		f.close()
	autoload._log("[VR Mod] Debug dump: ", label)


func snapshot_tree(node: Node, depth: int, max_depth: int, snapshot: Array, log_lines: Array) -> void:
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
			snapshot_tree(child, depth + 1, max_depth, snapshot, log_lines)


func find_all_typed_under(node: Node, type_name: String, depth: int, max_depth: int, result: Array) -> void:
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
			find_all_typed_under(child, type_name, depth + 1, max_depth, result)


func find_meshes_near_to_list(node: Node, pos: Vector3, radius: float, depth: int, max_depth: int, result: Array) -> void:
	if node == autoload.xr_origin:
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
			find_meshes_near_to_list(child, pos, radius, depth + 1, max_depth, result)


func dump_visible_canvas_nodes() -> void:
	# Scan the entire scene tree for visible CanvasItem nodes not in our known HUD paths.
	# Fired 0.3 s after ESC menu opens to identify where the ESC menu node lives.
	autoload._log("=== ESC MENU NODE SCAN ===")
	var known_paths := ["VRHudViewport", "VRWatchMedVP", "VRModOrigin", "VRHudPanel",
		"Map/Core/UI/HUD", "Map/Core/UI/Effects", "Map/Core/UI/NVG"]
	scan_for_visible_canvas(autoload.get_tree().root, "", known_paths, 0)
	autoload._log("=== END ESC MENU NODE SCAN ===")


func scan_for_visible_canvas(node: Node, path: String, skip_prefixes: Array, depth: int) -> void:
	if depth > 20:
		return
	var full_path = path + "/" + node.name if path != "" else node.name
	if node == autoload or node == autoload.xr_origin:
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
			autoload._log("  CTRL: " + full_path + " [" + node.get_class() + "] rect=" + str(r) + " mf=" + mf_str)
	for child in node.get_children():
		scan_for_visible_canvas(child, full_path, skip_prefixes, depth + 1)


func dump_weapon_tree() -> void:
	var log_path = autoload._log_path
	var f = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if not f:
		f = FileAccess.open(log_path, FileAccess.WRITE)
	if not f:
		autoload._log("[VR Mod] Cannot open debug log for weapon dump")
		return
	f.seek_end(0)
	f.store_line("")
	f.store_line("=== WEAPON TREE DUMP (" + str(Time.get_datetime_string_from_system()) + ") ===")

	if not autoload.game_camera or not is_instance_valid(autoload.game_camera):
		f.store_line("  No game camera!")
		f.close()
		return

	var mgr = autoload.game_camera.get_node_or_null("Manager")
	if not mgr or mgr.get_child_count() == 0:
		f.store_line("  No weapon rig (Manager empty)")
		f.close()
		return

	var weapon_rig = mgr.get_child(0)
	f.store_line("Weapon rig: " + weapon_rig.name)
	dump_weapon_node(f, weapon_rig, 0, 30)
	f.store_line("")
	f.close()
	autoload._log("[VR Mod] Weapon tree dumped to vr_mod_debug.log")


func dump_weapon_node(f: FileAccess, node: Node, depth: int, max_depth: int) -> void:
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
		dump_weapon_node(f, child, depth + 1, max_depth)


# Ray target debug dump (F12)
func dump_ray_target() -> void:
	var log_path = autoload._log_path
	var f = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if not f:
		return
	f.seek_end(0)
	f.store_line("")
	f.store_line("=== RAY TARGET DUMP (F12) " + Time.get_datetime_string_from_system() + " ===")
	# In decor mode, also dump the game's Interactor raycast
	if autoload._decor_mode and autoload.game_camera and is_instance_valid(autoload.game_camera):
		var interactor = autoload.game_camera.get_node_or_null("Interactor")
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
					if p.name == "Map" or p == autoload.get_tree().root:
						break
					p = p.get_parent()
					depth += 1
		else:
			f.store_line("    (not colliding)")
	for ray_info in [["Right GrabRay", autoload._grab_ray_right], ["Left GrabRay", autoload._grab_ray_left]]:
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
			f.store_line("    collision_layer: " + str(c.collision_layer) + " (bin: " + bits_str(c.collision_layer) + ")")
			f.store_line("    collision_mask: " + str(c.collision_mask) + " (bin: " + bits_str(c.collision_mask) + ")")
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
			if p.name == "Map" or p == autoload.get_tree().root:
				break
			p = p.get_parent()
			depth += 1
		f.store_line("    Parent chain:")
		f.store_line(parent_chain)
	f.close()
	autoload._log("[VR Mod] Ray target dumped to log (F12)")


func bits_str(val: int) -> String:
	var s := ""
	for i in range(20):
		if val & (1 << i):
			s += str(i + 1) + ","
	return s.trim_suffix(",") if s != "" else "none"


# HUD tree debug dump (F9)
func dump_hud_tree() -> void:
	var log_path = autoload._log_path
	var f = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if not f:
		f = FileAccess.open(log_path, FileAccess.WRITE)
	if not f:
		autoload._log("[VR Mod] Cannot open debug log for HUD dump")
		return
	f.seek_end(0)
	f.store_line("")
	f.store_line("=== HUD TREE DUMP (" + str(Time.get_datetime_string_from_system()) + ") ===")
	f.store_line("interface_open=" + str(autoload._interface_open) + " esc_active=" + str(autoload._esc_menu_active) + " paused=" + str(autoload.get_tree().paused))

	# Dump ALL Map/Core/UI children with class and visibility for loot pool diagnosis
	var ui_node = autoload.get_tree().root.get_node_or_null("Map/Core/UI")
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
	var core_node = autoload.get_tree().root.get_node_or_null("Map/Core")
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
	dump_node_recursive(f, hud_node, 0)
	f.store_line("=== END HUD TREE DUMP ===")
	f.close()
	autoload._log("[VR Mod] HUD tree dumped to vr_mod_debug.log")


func dump_node_recursive(f: FileAccess, node: Node, depth: int) -> void:
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
		dump_node_recursive(f, child, depth + 1)


# NVG & Environment debug dump (F11)
func dump_nvg_and_environment() -> void:
	var log_path = autoload._log_path
	var f = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if not f:
		f = FileAccess.open(log_path, FileAccess.WRITE)
	if not f:
		autoload._log("[VR Mod] Cannot open debug log for NVG dump")
		return
	f.seek_end(0)
	f.store_line("")
	f.store_line("=== NVG & ENVIRONMENT DUMP (" + str(Time.get_datetime_string_from_system()) + ") ===")

	# -1. Character/player node search
	f.store_line("")
	f.store_line("-- Core subtree: all scripted nodes + CharacterBody3D --")
	var core_node = autoload.get_tree().root.get_node_or_null("Map/Core")
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

	# 0. Decor mode state
	f.store_line("")
	f.store_line("-- Decor Mode --")
	f.store_line("  _decor_mode=" + str(autoload._decor_mode))
	f.store_line("  decor.scroll_mode=" + str(autoload._ensure_decor().scroll_mode) + " (0=distance, 1=rotation)")
	f.store_line("  _left_grip_held=" + str(autoload._left_grip_held) + " _right_grip_held=" + str(autoload._right_grip_held))
	if autoload._decor_mode and autoload.game_camera and is_instance_valid(autoload.game_camera):
		# Dump direct children of game_camera that might be decor-related
		f.store_line("  game_camera children:")
		for c in autoload.game_camera.get_children():
			var vis_str = ""
			if c is Node3D:
				vis_str = " vis=" + str(c.visible)
			elif c is CanvasItem:
				vis_str = " vis=" + str(c.visible)
			f.store_line("    " + c.name + " (" + c.get_class() + ")" + vis_str)
		# Check for Placer node
		var placer = autoload.game_camera.get_node_or_null("Placer")
		if placer:
			f.store_line("  Placer node found! Children:")
			for c in placer.get_children():
				var vis_str2 = ""
				if c is Node3D:
					vis_str2 = " vis=" + str(c.visible)
				f.store_line("    " + c.name + " (" + c.get_class() + ")" + vis_str2)
				if c.get_script():
					f.store_line("      script=" + str(c.get_script().resource_path))

	# 0b. Placer script properties + Map/Hint ghost node
	if autoload._decor_mode:
		var placer = autoload.game_camera.get_node_or_null("Placer") if autoload.game_camera else null
		if placer and placer.get_script():
			f.store_line("  Placer script: " + str(placer.get_script().resource_path))
			f.store_line("  Placer PROPS:")
			var prop_list = placer.get_property_list()
			for prop in prop_list:
				# 4096 = PROPERTY_USAGE_SCRIPT_VARIABLE
				if prop["usage"] & 4096:
					var val = placer.get(prop["name"])
					f.store_line("    " + prop["name"] + " = " + str(val))
		var map_node = autoload.get_tree().root.get_node_or_null("Map")
		if map_node:
			f.store_line("  /root/Map/ direct children:")
			for c in map_node.get_children():
				var info = "    " + c.name + " (" + c.get_class() + ")"
				if c is Node3D:
					info += " vis=" + str(c.visible)
				if c.get_script():
					info += " script=" + str(c.get_script().resource_path)
				f.store_line(info)

	# 1. Dump the NVG node under Map/Core/UI
	var ui_node = autoload.get_tree().root.get_node_or_null("Map/Core/UI")
	if ui_node:
		var nvg_node = ui_node.get_node_or_null("NVG")
		if nvg_node:
			f.store_line("")
			f.store_line("-- NVG Node (" + nvg_node.get_class() + ") vis=" + str(nvg_node.visible) + " --")
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
			dump_nvg_node(f, nvg_node, 0, 15)
		else:
			f.store_line("  NVG node not found under Map/Core/UI")
			f.store_line("  Children of UI:")
			for c in ui_node.get_children():
				f.store_line("    " + c.name + " (" + c.get_class() + ") vis=" + str(c.visible if c is CanvasItem else "n/a"))

		# Also dump Effects node since it might contain NVG-related overlays
		var effects_node = ui_node.get_node_or_null("Effects")
		if effects_node:
			f.store_line("")
			f.store_line("-- Effects Node (" + effects_node.get_class() + ") vis=" + str(effects_node.visible) + " --")
			dump_nvg_node(f, effects_node, 0, 10)
	else:
		f.store_line("  Map/Core/UI not found!")

	# 2. Scan for all WorldEnvironment nodes in the scene
	f.store_line("")
	f.store_line("-- WorldEnvironment Nodes --")
	var we_nodes = find_nodes_of_class(autoload.get_tree().root, "WorldEnvironment", 6)
	if we_nodes.size() == 0:
		f.store_line("  (none found in scene, depth 6)")
	for we in we_nodes:
		f.store_line("  " + str(we.get_path()) + " vis=" + str(we.visible if we is Node3D else "n/a"))
		var env = we.get("environment")
		if env and env is Environment:
			dump_environment(f, env, "    ")

	# 3. Check camera's own environment
	f.store_line("")
	f.store_line("-- Camera Environments --")
	if autoload.game_camera and is_instance_valid(autoload.game_camera):
		var cam_env = autoload.game_camera.get("environment")
		if cam_env and cam_env is Environment:
			f.store_line("  game_camera (" + str(autoload.game_camera.get_path()) + ") has environment:")
			dump_environment(f, cam_env, "    ")
		else:
			f.store_line("  game_camera has no environment override")
	if autoload.xr_camera and is_instance_valid(autoload.xr_camera):
		var xr_env = autoload.xr_camera.get("environment")
		if xr_env and xr_env is Environment:
			f.store_line("  xr_camera has environment:")
			dump_environment(f, xr_env, "    ")
		else:
			f.store_line("  xr_camera has no environment override")

	# 4. Check for CanvasLayer nodes at the root level (post-processing overlays)
	f.store_line("")
	f.store_line("-- Root-level CanvasLayers --")
	for child in autoload.get_tree().root.get_children():
		if child is CanvasLayer:
			f.store_line("  " + child.name + " layer=" + str((child as CanvasLayer).layer) + " vis=" + str(child.visible))
	var map_node = autoload.get_tree().root.get_node_or_null("Map")
	if map_node:
		for child in map_node.get_children():
			if child is CanvasLayer:
				f.store_line("  Map/" + child.name + " layer=" + str((child as CanvasLayer).layer) + " vis=" + str(child.visible))

	f.store_line("")
	f.store_line("=== END NVG & ENVIRONMENT DUMP ===")
	f.close()
	autoload._log("[VR Mod] NVG & environment dump written to vr_mod_debug.log (F11)")


func dump_nvg_node(f: FileAccess, node: Node, depth: int, max_depth: int) -> void:
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
		dump_nvg_node(f, child, depth + 1, max_depth)


func dump_environment(f: FileAccess, env: Environment, indent: String) -> void:
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


func find_nodes_of_class(root: Node, class_name_str: String, max_depth: int, _depth: int = 0) -> Array:
	var result := []
	if root.get_class() == class_name_str or root.is_class(class_name_str):
		result.append(root)
	if _depth < max_depth:
		for child in root.get_children():
			result.append_array(find_nodes_of_class(child, class_name_str, max_depth, _depth + 1))
	return result
