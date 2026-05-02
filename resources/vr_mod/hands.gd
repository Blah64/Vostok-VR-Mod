extends RefCounted

# hands.gd
# Lowpoly hand GLTF loading, finger curl skeleton animation, and hand
# visibility logic (which doubles as the per-frame laser-pointer colour
# selector since both depend on game/mod state). State (skeletons, finger
# bone caches, wrappers) stays on the autoload.

var autoload: Node

func _init(p_autoload: Node) -> void:
	autoload = p_autoload


func process(_frame: Dictionary, delta: float) -> void:
	# Hand visibility (also re-colours the laser based on what it is pointing
	# at) and procedural finger curl driven by trigger/grip analog values.
	update_hand_visibility()
	update_hand_poses(delta)


func extract_hand_assets_from_vmz() -> bool:
	# Metro Mod Loader caches the VMZ as a zip at user://vmz_mount_cache/vr-mod.zip.
	# Godot's res:// VFS does not expose the VMZ contents, so we extract the hand
	# assets to user://vr_mod/hands/ where FileAccess and GLTFDocument can read them.
	var zip_path := "user://vmz_mount_cache/vr-mod.zip"

	var reader := ZIPReader.new()
	var open_err := reader.open(zip_path)
	if open_err != OK:
		autoload._hand_load_errors.append("hand: ZIPReader.open failed for " + zip_path + " err=" + str(open_err))
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
			autoload._hand_load_errors.append("hand: entry not found in VMZ: " + asset)
			reader.close()
			return false
		var bytes := reader.read_file(entry)
		if bytes.is_empty():
			autoload._hand_load_errors.append("hand: read_file empty for " + entry)
			reader.close()
			return false
		var dest_path := "user://vr_mod/hands/" + filename
		var wf := FileAccess.open(dest_path, FileAccess.WRITE)
		if not wf:
			autoload._hand_load_errors.append("hand: cannot write " + dest_path + " err=" + str(FileAccess.get_open_error()))
			reader.close()
			return false
		wf.store_buffer(bytes)
		wf.close()

	reader.close()
	autoload._hand_load_errors.append("hand: extracted assets to user://vr_mod/hands/")
	return true


func create_hand_model(controller: XRController3D, model_name: String) -> void:
	var is_left := "Left" in model_name
	var gltf_name := "Hand_Nails_low_L.gltf" if is_left else "Hand_Nails_low_R.gltf"
	var gltf_path = autoload._assets_base + gltf_name

	# Runtime GLTF import - append_from_file resolves relative texture references
	# (hand_col.png) automatically from the same directory.
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var err := gltf_doc.append_from_file(gltf_path, gltf_state)
	if err != OK:
		autoload._hand_load_errors.append("hand: append_from_file failed err=" + str(err) + " path=" + gltf_path)
		create_fallback_box_hand(controller, model_name)
		return
	var scene: Node = gltf_doc.generate_scene(gltf_state)
	if not scene:
		autoload._hand_load_errors.append("hand: generate_scene returned null for " + gltf_path)
		create_fallback_box_hand(controller, model_name)
		return

	# CRITICAL (Forward Mobile): never add MeshInstance3D directly to XRController3D.
	# The wrapper Node3D is the direct child; the gltf scene (which contains meshes) goes
	# under the wrapper.
	var wrapper := Node3D.new()
	wrapper.name = model_name
	wrapper.position = autoload.HAND_GLTF_OFFSET_LEFT if is_left else autoload.HAND_GLTF_OFFSET_RIGHT
	wrapper.rotation_degrees = autoload.HAND_GLTF_ROTATION_LEFT if is_left else autoload.HAND_GLTF_ROTATION_RIGHT
	wrapper.add_child(scene)
	controller.add_child(wrapper)
	apply_hand_texture(scene)

	# Cache skeleton and finger bone indices for runtime curl animation
	var skel: Skeleton3D = autoload._find_node_by_class(scene, "Skeleton3D")
	if not skel:
		autoload._hand_load_errors.append("hand: Skeleton3D not found inside " + gltf_name)
		return

	var suffix := "_L" if is_left else "_R"
	# Joint order is always proximal -> intermediate -> distal (base to tip).
	# Thumb has no Intermediate joint in anatomical rigs - only Proximal + Distal.
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
				autoload._hand_load_errors.append("hand: bone not found: " + bone_base + suffix)
		fingers[finger_name] = indices

	if is_left:
		autoload._hand_wrapper_left = wrapper
		autoload._hand_skel_left = skel
		autoload._hand_fingers_left = fingers
		autoload._hand_bone_rest_left = rest
	else:
		autoload._hand_wrapper_right = wrapper
		autoload._hand_skel_right = skel
		autoload._hand_fingers_right = fingers
		autoload._hand_bone_rest_right = rest

	autoload._log("hand: loaded " + gltf_name + " bones=" + str(skel.get_bone_count()) + " fingers=" + str(fingers.keys()))


func create_fallback_box_hand(controller: XRController3D, model_name: String) -> void:
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
	autoload._log("[VR Mod] Created fallback box hand model: ", model_name)


func apply_hand_texture(root: Node) -> void:
	# Load the shared skin texture on first call; reuse for both hands after that.
	if not autoload._hand_tex:
		var tex_path = autoload._assets_base + "hand_col.png"
		if FileAccess.file_exists(tex_path):
			var img := Image.load_from_file(tex_path)
			if img:
				autoload._hand_tex = ImageTexture.create_from_image(img)
				autoload._hand_load_errors.append("hand: loaded skin texture " + tex_path)
			else:
				autoload._hand_load_errors.append("hand: Image.load_from_file failed for " + tex_path)
		else:
			autoload._hand_load_errors.append("hand: skin texture not found at " + tex_path)
	# Build a StandardMaterial3D with the skin texture (or plain skin colour as fallback).
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.roughness = 0.85
	mat.metallic = 0.0
	if autoload._hand_tex:
		mat.albedo_texture = autoload._hand_tex
	else:
		mat.albedo_color = Color(0.76, 0.60, 0.46)  # neutral skin fallback
	# Apply material_override on every MeshInstance3D inside the scene.
	hand_apply_mat_recursive(root, mat)


func hand_apply_mat_recursive(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.material_override = mat
	for child in node.get_children():
		hand_apply_mat_recursive(child, mat)


func update_hand_poses(delta: float) -> void:
	# Procedural finger curl
	update_one_hand("left", delta)
	update_one_hand("right", delta)


func update_one_hand(hand: String, delta: float) -> void:
	var skel: Skeleton3D = autoload._hand_skel_left if hand == "left" else autoload._hand_skel_right
	if not skel or not is_instance_valid(skel):
		return
	var ctrl = autoload._get_controller(hand)
	if not ctrl or not ctrl.get_is_active():
		return

	# Read analog inputs (0.0-1.0). Quest/OpenXR action map uses these names.
	var grip_val: float = clampf(ctrl.get_float("grip"), 0.0, 1.0)
	var trig_val: float = clampf(ctrl.get_float("trigger"), 0.0, 1.0)

	# Thumb: extended (uncurled) only when no thumb-resting button is held.
	var thumb_down = ctrl.is_button_pressed("ax_button") or ctrl.is_button_pressed("by_button")
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

	var curl_state: Dictionary = autoload._hand_curl_left if hand == "left" else autoload._hand_curl_right
	var fingers: Dictionary = autoload._hand_fingers_left if hand == "left" else autoload._hand_fingers_right
	var rest: Dictionary = autoload._hand_bone_rest_left if hand == "left" else autoload._hand_bone_rest_right
	var alpha := clampf(delta * autoload.HAND_CURL_SMOOTH_SPEED, 0.0, 1.0)
	# Right hand finger bones are mirrored so their local Z points opposite to the left hand.
	var finger_axis: Vector3 = autoload.HAND_CURL_AXIS_FINGER if hand == "left" else -autoload.HAND_CURL_AXIS_FINGER

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
		var max_curl: float = autoload.HAND_THUMB_MAX_CURL if is_thumb else autoload.HAND_FINGER_MAX_CURL
		var curl_axis: Vector3 = autoload.HAND_CURL_AXIS_THUMB if is_thumb else finger_axis

		for i in bones.size():
			var bi: int = bones[i]
			var weight: float = autoload.HAND_FINGER_JOINT_WEIGHT[min(i, autoload.HAND_FINGER_JOINT_WEIGHT.size() - 1)]
			# Negative angle so the rotation curls toward the palm.
			var angle: float = -cur * max_curl * weight
			var rest_q: Quaternion = rest[bi]
			var curl_q := Quaternion(curl_axis, angle)
			skel.set_bone_pose_rotation(bi, rest_q * curl_q)


func update_hand_visibility() -> void:
	var left_hand = autoload.left_controller.get_node_or_null("LeftHandModel")
	var right_hand = autoload.right_controller.get_node_or_null("RightHandModel")

	# Check if the game actually has a weapon model visible
	var game_has_weapon := false
	if autoload.game_camera and is_instance_valid(autoload.game_camera):
		var mgr = autoload.game_camera.get_node_or_null("Manager")
		if mgr and mgr.get_child_count() > 0:
			game_has_weapon = true

	# Hide weapon hand only when the game actually has a weapon model present.
	# This prevents hands vanishing during the draw-pending window on empty slots.
	# Always show VR hand models - the game's first-person arm mesh is
	# hidden separately via _hide_arms_in_subtree on the weapon rig.
	if left_hand: left_hand.visible = true
	if right_hand: right_hand.visible = true

	# Reset hand wrappers to their canonical GLTF position/rotation when no weapon
	# sway is active (UNARMED / SLING), so a stale sway displacement from the last
	# DRAWN frame does not persist after holstering.
	if autoload._holster_state == autoload.HolsterState.UNARMED or autoload._holster_state == autoload.HolsterState.SLING:
		if autoload._hand_wrapper_left:
			autoload._hand_wrapper_left.position = autoload.HAND_GLTF_OFFSET_LEFT
			autoload._hand_wrapper_left.rotation_degrees = autoload.HAND_GLTF_ROTATION_LEFT
		if autoload._hand_wrapper_right:
			autoload._hand_wrapper_right.position = autoload.HAND_GLTF_OFFSET_RIGHT
			autoload._hand_wrapper_right.rotation_degrees = autoload.HAND_GLTF_ROTATION_RIGHT

	# Laser pointer: grab range when UNARMED, interact range when LOWERED (weapon hand)
	if autoload._laser_mesh and not autoload._menu_open and not autoload._config_screen_open:
		var show_laser := false
		var laser_hand = autoload._config_dominant_hand

		if autoload._decor_mode:
			show_laser = true
			laser_hand = autoload._config_dominant_hand
		elif autoload._holster_state == autoload.HolsterState.UNARMED and autoload._grabbed_object == null:
			show_laser = true
			laser_hand = autoload._config_dominant_hand
		elif autoload._holster_state == autoload.HolsterState.LOWERED or autoload._holster_state == autoload.HolsterState.SLING:
			show_laser = true
			laser_hand = autoload._config_dominant_hand

		if show_laser:
			# Reparent laser to correct controller if needed
			var target_ctrl = autoload._get_controller(laser_hand)
			if target_ctrl and autoload._laser_mesh.get_parent() != target_ctrl:
				autoload._laser_mesh.get_parent().remove_child(autoload._laser_mesh)
				target_ctrl.add_child(autoload._laser_mesh)
				autoload._laser_mesh.rotation.x = deg_to_rad(90)

			# Check what the ray is pointing at
			var grab_ray = autoload._grab_ray_right if laser_hand == "right" else autoload._grab_ray_left
			var pointing_at_grabbable := false
			var pointing_at_interactable := false
			var pointing_at_furniture := false
			var pointing_at_transition := false
			var hover_collider: Node3D = null
			var hover_hit_pos := Vector3.ZERO
			if autoload._decor_mode and autoload.game_camera and is_instance_valid(autoload.game_camera):
				# Use the game's Interactor raycast (driven by game camera we steer)
				var interactor = autoload.game_camera.get_node_or_null("Interactor")
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
				if not pointing_at_grabbable and autoload.game_camera and is_instance_valid(autoload.game_camera):
					var interactor = autoload.game_camera.get_node_or_null("Interactor")
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
				# Level transition: Interactor hit something not in "Interactable" - check by script/group/name
				if not pointing_at_grabbable and not pointing_at_interactable \
						and autoload.game_camera and is_instance_valid(autoload.game_camera):
					var interactor2 = autoload.game_camera.get_node_or_null("Interactor")
					if interactor2 is RayCast3D and interactor2.is_colliding():
						var check = interactor2.get_collider()
						for _i in range(6):
							if not is_instance_valid(check):
								break
							if autoload._is_transition_node(check):
								pointing_at_transition = true
								hover_collider = check as Node3D
								hover_hit_pos = interactor2.get_collision_point()
								break
							check = check.get_parent()
				# Also check GrabRay for Area3D transition triggers (collide_with_areas = true)
				if not pointing_at_transition and not pointing_at_grabbable \
						and grab_ray and grab_ray.is_colliding():
					var ac = grab_ray.get_collider()
					if ac is Area3D:
						var check = ac
						for _i in range(6):
							if not is_instance_valid(check):
								break
							if autoload._is_transition_node(check):
								pointing_at_transition = true
								hover_collider = check as Node3D
								hover_hit_pos = grab_ray.get_collision_point()
								break
							check = check.get_parent()
			var mat := autoload._laser_mesh.material_override as StandardMaterial3D
			if mat:
				if autoload._decor_mode and pointing_at_furniture:
					mat.albedo_color = Color(1.0, 0.65, 0.1, 0.8)  # Orange - furniture targeted
				elif autoload._decor_mode:
					mat.albedo_color = Color(0.2, 0.8, 1.0, 0.7)   # Cyan - decor placement
				elif pointing_at_grabbable:
					mat.albedo_color = Color(0.1, 1.0, 0.2, 0.7)   # Green - grabbable item
				elif pointing_at_interactable:
					mat.albedo_color = Color(1.0, 0.8, 0.1, 0.7)   # Yellow - B-interact
				elif pointing_at_transition:
					mat.albedo_color = Color(0.9, 0.9, 1.0, 0.8)   # White - level transition
				else:
					mat.albedo_color = Color(1.0, 0.2, 0.1, 0.6)   # Red - nothing
			var cyl := autoload._laser_mesh.mesh as CylinderMesh
			if cyl:
				cyl.height = 1.0
				autoload._laser_mesh.position.z = -0.5

			# Update hover label with target name
			if autoload._hover_label:
				if hover_collider != null:
					if pointing_at_interactable or pointing_at_transition:
						autoload._hover_label.text = autoload._find_interactable_display_name(hover_collider)
					else:
						autoload._hover_label.text = autoload._format_node_name(hover_collider.name)
					autoload._hover_label.global_position = hover_hit_pos + Vector3.UP * 0.15
					autoload._hover_label.visible = true
				else:
					autoload._hover_label.visible = false
			var has_target := pointing_at_grabbable or pointing_at_interactable or pointing_at_furniture or pointing_at_transition
			autoload._laser_mesh.visible = autoload._laser_always_on or has_target
		else:
			if autoload._hover_label:
				autoload._hover_label.visible = false
			autoload._laser_mesh.visible = false
