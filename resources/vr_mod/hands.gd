extends RefCounted

# hands.gd
# Lowpoly hand GLTF loading, finger curl skeleton animation, and hand
# visibility logic (which doubles as the per-frame laser-pointer colour
# selector since both depend on game/mod state).
#
# Subsystem-owned state. Skeleton/finger-bone caches and wrapper refs stay on
# the autoload because legacy diagnostics and the F8 panel still read them by
# name; this module reads/writes them through Callable ports.
#
# Port contract:
#   tree                       : SceneTree
#   get_assets_base            : Callable() -> String   (res://resources/hands/)
#   get_left_controller        : Callable() -> XRController3D
#   get_right_controller       : Callable() -> XRController3D
#   get_controller             : Callable(hand) -> XRController3D
#   get_game_camera            : Callable() -> Camera3D
#   get_holster_state          : Callable() -> int
#   get_state_unarmed          : Callable() -> int
#   get_state_sling            : Callable() -> int
#   get_state_lowered          : Callable() -> int
#   get_decor_mode             : Callable() -> bool
#   get_grabbed_object         : Callable() -> Node3D
#   get_dominant_hand          : Callable() -> String
#   get_menu_open              : Callable() -> bool
#   get_config_screen_open     : Callable() -> bool
#   get_laser_mesh             : Callable() -> MeshInstance3D
#   get_laser_always_on        : Callable() -> bool
#   get_hover_label            : Callable() -> Label3D
#   get_grab_ray               : Callable(hand) -> RayCast3D
#   is_transition_node         : Callable(node) -> bool
#   find_interactable_name     : Callable(collider) -> String
#   format_node_name           : Callable(name) -> String
#   find_node_by_class         : Callable(root, class_name_str) -> Node
#   get_hand_offset_left       : Callable() -> Vector3
#   get_hand_offset_right      : Callable() -> Vector3
#   get_hand_rot_left          : Callable() -> Vector3
#   get_hand_rot_right         : Callable() -> Vector3
#   get_curl_axis_thumb        : Callable() -> Vector3
#   get_curl_axis_finger       : Callable() -> Vector3
#   get_finger_max_curl        : Callable() -> float
#   get_thumb_max_curl         : Callable() -> float
#   get_curl_smooth_speed      : Callable() -> float
#   get_finger_joint_weight    : Callable() -> Array
#   get_hand_skel              : Callable(hand) -> Skeleton3D
#   get_hand_curl              : Callable(hand) -> Dictionary
#   get_hand_fingers           : Callable(hand) -> Dictionary
#   get_hand_bone_rest         : Callable(hand) -> Dictionary
#   get_hand_wrapper           : Callable(hand) -> Node3D
#   set_hand_wrapper           : Callable(hand, node) -> void
#   set_hand_skel              : Callable(hand, skel) -> void
#   set_hand_fingers           : Callable(hand, dict) -> void
#   set_hand_bone_rest         : Callable(hand, dict) -> void
#   get_hand_tex               : Callable() -> ImageTexture
#   set_hand_tex               : Callable(tex) -> void
#   append_load_error          : Callable(msg) -> void
#   log                        : Callable(msg) -> void

# Ports
var _tree: SceneTree
var _get_assets_base: Callable
var _get_left_controller: Callable
var _get_right_controller: Callable
var _get_controller: Callable
var _get_game_camera: Callable
var _get_holster_state: Callable
var _get_state_unarmed: Callable
var _get_state_sling: Callable
var _get_state_lowered: Callable
var _get_decor_mode: Callable
var _get_grabbed_object: Callable
var _get_dominant_hand: Callable
var _get_menu_open: Callable
var _get_config_screen_open: Callable
var _get_laser_mesh: Callable
var _get_laser_always_on: Callable
var _get_hover_label: Callable
var _get_grab_ray: Callable
var _is_transition_node_fn: Callable
var _find_interactable_name: Callable
var _format_node_name_fn: Callable
var _find_node_by_class: Callable
var _get_hand_offset_left: Callable
var _get_hand_offset_right: Callable
var _get_hand_rot_left: Callable
var _get_hand_rot_right: Callable
var _get_curl_axis_thumb: Callable
var _get_curl_axis_finger: Callable
var _get_finger_max_curl: Callable
var _get_thumb_max_curl: Callable
var _get_curl_smooth_speed: Callable
var _get_finger_joint_weight: Callable
var _get_hand_skel: Callable
var _get_hand_curl: Callable
var _get_hand_fingers: Callable
var _get_hand_bone_rest: Callable
var _get_hand_wrapper: Callable
var _set_hand_wrapper: Callable
var _set_hand_skel: Callable
var _set_hand_fingers: Callable
var _set_hand_bone_rest: Callable
var _get_hand_tex: Callable
var _set_hand_tex: Callable
var _append_load_error: Callable
var _log_fn: Callable


func _init(tree: SceneTree, ports: Dictionary) -> void:
	_tree = tree
	_get_assets_base = ports["get_assets_base"]
	_get_left_controller = ports["get_left_controller"]
	_get_right_controller = ports["get_right_controller"]
	_get_controller = ports["get_controller"]
	_get_game_camera = ports["get_game_camera"]
	_get_holster_state = ports["get_holster_state"]
	_get_state_unarmed = ports["get_state_unarmed"]
	_get_state_sling = ports["get_state_sling"]
	_get_state_lowered = ports["get_state_lowered"]
	_get_decor_mode = ports["get_decor_mode"]
	_get_grabbed_object = ports["get_grabbed_object"]
	_get_dominant_hand = ports["get_dominant_hand"]
	_get_menu_open = ports["get_menu_open"]
	_get_config_screen_open = ports["get_config_screen_open"]
	_get_laser_mesh = ports["get_laser_mesh"]
	_get_laser_always_on = ports["get_laser_always_on"]
	_get_hover_label = ports["get_hover_label"]
	_get_grab_ray = ports["get_grab_ray"]
	_is_transition_node_fn = ports["is_transition_node"]
	_find_interactable_name = ports["find_interactable_name"]
	_format_node_name_fn = ports["format_node_name"]
	_find_node_by_class = ports["find_node_by_class"]
	_get_hand_offset_left = ports["get_hand_offset_left"]
	_get_hand_offset_right = ports["get_hand_offset_right"]
	_get_hand_rot_left = ports["get_hand_rot_left"]
	_get_hand_rot_right = ports["get_hand_rot_right"]
	_get_curl_axis_thumb = ports["get_curl_axis_thumb"]
	_get_curl_axis_finger = ports["get_curl_axis_finger"]
	_get_finger_max_curl = ports["get_finger_max_curl"]
	_get_thumb_max_curl = ports["get_thumb_max_curl"]
	_get_curl_smooth_speed = ports["get_curl_smooth_speed"]
	_get_finger_joint_weight = ports["get_finger_joint_weight"]
	_get_hand_skel = ports["get_hand_skel"]
	_get_hand_curl = ports["get_hand_curl"]
	_get_hand_fingers = ports["get_hand_fingers"]
	_get_hand_bone_rest = ports["get_hand_bone_rest"]
	_get_hand_wrapper = ports["get_hand_wrapper"]
	_set_hand_wrapper = ports["set_hand_wrapper"]
	_set_hand_skel = ports["set_hand_skel"]
	_set_hand_fingers = ports["set_hand_fingers"]
	_set_hand_bone_rest = ports["set_hand_bone_rest"]
	_get_hand_tex = ports["get_hand_tex"]
	_set_hand_tex = ports["set_hand_tex"]
	_append_load_error = ports["append_load_error"]
	_log_fn = ports.get("log", Callable())


func _log(msg: String) -> void:
	if _log_fn.is_valid():
		_log_fn.call(msg)


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
		_append_load_error.call("hand: ZIPReader.open failed for " + zip_path + " err=" + str(open_err))
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
			_append_load_error.call("hand: entry not found in VMZ: " + asset)
			reader.close()
			return false
		var bytes := reader.read_file(entry)
		if bytes.is_empty():
			_append_load_error.call("hand: read_file empty for " + entry)
			reader.close()
			return false
		var dest_path := "user://vr_mod/hands/" + filename
		var wf := FileAccess.open(dest_path, FileAccess.WRITE)
		if not wf:
			_append_load_error.call("hand: cannot write " + dest_path + " err=" + str(FileAccess.get_open_error()))
			reader.close()
			return false
		wf.store_buffer(bytes)
		wf.close()

	reader.close()
	_append_load_error.call("hand: extracted assets to user://vr_mod/hands/")
	return true


func create_hand_model(controller: XRController3D, model_name: String) -> void:
	var is_left := "Left" in model_name
	var gltf_name := "Hand_Nails_low_L.gltf" if is_left else "Hand_Nails_low_R.gltf"
	var gltf_path: String = _get_assets_base.call() + gltf_name

	# Runtime GLTF import - append_from_file resolves relative texture references
	# (hand_col.png) automatically from the same directory.
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var err := gltf_doc.append_from_file(gltf_path, gltf_state)
	if err != OK:
		_append_load_error.call("hand: append_from_file failed err=" + str(err) + " path=" + gltf_path)
		create_fallback_box_hand(controller, model_name)
		return
	var scene: Node = gltf_doc.generate_scene(gltf_state)
	if not scene:
		_append_load_error.call("hand: generate_scene returned null for " + gltf_path)
		create_fallback_box_hand(controller, model_name)
		return

	# CRITICAL (Forward Mobile): never add MeshInstance3D directly to XRController3D.
	# The wrapper Node3D is the direct child; the gltf scene (which contains meshes) goes
	# under the wrapper.
	var wrapper := Node3D.new()
	wrapper.name = model_name
	wrapper.position = _get_hand_offset_left.call() if is_left else _get_hand_offset_right.call()
	wrapper.rotation_degrees = _get_hand_rot_left.call() if is_left else _get_hand_rot_right.call()
	wrapper.add_child(scene)
	controller.add_child(wrapper)
	apply_hand_texture(scene)

	# Cache skeleton and finger bone indices for runtime curl animation
	var skel: Skeleton3D = _find_node_by_class.call(scene, "Skeleton3D")
	if not skel:
		_append_load_error.call("hand: Skeleton3D not found inside " + gltf_name)
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
				_append_load_error.call("hand: bone not found: " + bone_base + suffix)
		fingers[finger_name] = indices

	var hand: String = "left" if is_left else "right"
	_set_hand_wrapper.call(hand, wrapper)
	_set_hand_skel.call(hand, skel)
	_set_hand_fingers.call(hand, fingers)
	_set_hand_bone_rest.call(hand, rest)

	_log("hand: loaded " + gltf_name + " bones=" + str(skel.get_bone_count()) + " fingers=" + str(fingers.keys()))


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
	_log("[VR Mod] Created fallback box hand model: " + model_name)


func apply_hand_texture(root: Node) -> void:
	# Load the shared skin texture on first call; reuse for both hands after that.
	var tex: ImageTexture = _get_hand_tex.call()
	if not tex:
		var tex_path: String = _get_assets_base.call() + "hand_col.png"
		if FileAccess.file_exists(tex_path):
			var img := Image.load_from_file(tex_path)
			if img:
				tex = ImageTexture.create_from_image(img)
				_set_hand_tex.call(tex)
				_append_load_error.call("hand: loaded skin texture " + tex_path)
			else:
				_append_load_error.call("hand: Image.load_from_file failed for " + tex_path)
		else:
			_append_load_error.call("hand: skin texture not found at " + tex_path)
	# Build a StandardMaterial3D with the skin texture (or plain skin colour as fallback).
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.roughness = 0.85
	mat.metallic = 0.0
	if tex:
		mat.albedo_texture = tex
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
	var skel: Skeleton3D = _get_hand_skel.call(hand)
	if not skel or not is_instance_valid(skel):
		return
	var ctrl = _get_controller.call(hand)
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

	var curl_state: Dictionary = _get_hand_curl.call(hand)
	var fingers: Dictionary = _get_hand_fingers.call(hand)
	var rest: Dictionary = _get_hand_bone_rest.call(hand)
	var alpha := clampf(delta * _get_curl_smooth_speed.call(), 0.0, 1.0)
	# Right hand finger bones are mirrored so their local Z points opposite to the left hand.
	var finger_axis_base: Vector3 = _get_curl_axis_finger.call()
	var finger_axis: Vector3 = finger_axis_base if hand == "left" else -finger_axis_base
	var thumb_axis: Vector3 = _get_curl_axis_thumb.call()
	var max_finger_curl: float = _get_finger_max_curl.call()
	var max_thumb_curl: float = _get_thumb_max_curl.call()
	var joint_weights: Array = _get_finger_joint_weight.call()
	var jw_size: int = joint_weights.size()

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
		var max_curl: float = max_thumb_curl if is_thumb else max_finger_curl
		var curl_axis: Vector3 = thumb_axis if is_thumb else finger_axis

		for i in bones.size():
			var bi: int = bones[i]
			var weight: float = joint_weights[min(i, jw_size - 1)]
			# Negative angle so the rotation curls toward the palm.
			var angle: float = -cur * max_curl * weight
			var rest_q: Quaternion = rest[bi]
			var curl_q := Quaternion(curl_axis, angle)
			skel.set_bone_pose_rotation(bi, rest_q * curl_q)


func update_hand_visibility() -> void:
	var lc: XRController3D = _get_left_controller.call()
	var rc: XRController3D = _get_right_controller.call()
	var left_hand = lc.get_node_or_null("LeftHandModel") if lc else null
	var right_hand = rc.get_node_or_null("RightHandModel") if rc else null

	# Always show VR hand models - the game's first-person arm mesh is
	# hidden separately via _hide_arms_in_subtree on the weapon rig.
	if left_hand: left_hand.visible = true
	if right_hand: right_hand.visible = true

	# Reset hand wrappers to their canonical GLTF position/rotation when no weapon
	# sway is active (UNARMED / SLING), so a stale sway displacement from the last
	# DRAWN frame does not persist after holstering.
	var hs: int = _get_holster_state.call()
	var unarmed: int = _get_state_unarmed.call()
	var sling: int = _get_state_sling.call()
	var lowered: int = _get_state_lowered.call()
	if hs == unarmed or hs == sling:
		var wrap_l: Node3D = _get_hand_wrapper.call("left")
		if wrap_l:
			wrap_l.position = _get_hand_offset_left.call()
			wrap_l.rotation_degrees = _get_hand_rot_left.call()
		var wrap_r: Node3D = _get_hand_wrapper.call("right")
		if wrap_r:
			wrap_r.position = _get_hand_offset_right.call()
			wrap_r.rotation_degrees = _get_hand_rot_right.call()

	# Laser pointer: grab range when UNARMED, interact range when LOWERED (weapon hand)
	var laser: MeshInstance3D = _get_laser_mesh.call()
	var menu_open: bool = _get_menu_open.call()
	var config_open: bool = _get_config_screen_open.call()
	if laser and not menu_open and not config_open:
		var show_laser := false
		var laser_hand: String = _get_dominant_hand.call()
		var decor_mode: bool = _get_decor_mode.call()
		var grabbed = _get_grabbed_object.call()
		var gc = _get_game_camera.call()

		if decor_mode:
			show_laser = true
		elif hs == unarmed and grabbed == null:
			show_laser = true
		elif hs == lowered or hs == sling:
			show_laser = true

		if show_laser:
			# Reparent laser to correct controller if needed
			var target_ctrl = _get_controller.call(laser_hand)
			if target_ctrl and laser.get_parent() != target_ctrl:
				laser.get_parent().remove_child(laser)
				target_ctrl.add_child(laser)
				laser.rotation.x = deg_to_rad(90)

			# Check what the ray is pointing at
			var grab_ray = _get_grab_ray.call(laser_hand)
			var pointing_at_grabbable := false
			var pointing_at_interactable := false
			var pointing_at_furniture := false
			var pointing_at_transition := false
			var hover_collider: Node3D = null
			var hover_hit_pos := Vector3.ZERO
			if decor_mode and gc and is_instance_valid(gc):
				# Use the game's Interactor raycast (driven by game camera we steer)
				var interactor = gc.get_node_or_null("Interactor")
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
				if not pointing_at_grabbable and gc and is_instance_valid(gc):
					var interactor = gc.get_node_or_null("Interactor")
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
						and gc and is_instance_valid(gc):
					var interactor2 = gc.get_node_or_null("Interactor")
					if interactor2 is RayCast3D and interactor2.is_colliding():
						var check = interactor2.get_collider()
						for _i in range(6):
							if not is_instance_valid(check):
								break
							if _is_transition_node_fn.call(check):
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
							if _is_transition_node_fn.call(check):
								pointing_at_transition = true
								hover_collider = check as Node3D
								hover_hit_pos = grab_ray.get_collision_point()
								break
							check = check.get_parent()
			var mat := laser.material_override as StandardMaterial3D
			if mat:
				if decor_mode and pointing_at_furniture:
					mat.albedo_color = Color(1.0, 0.65, 0.1, 0.8)  # Orange - furniture targeted
				elif decor_mode:
					mat.albedo_color = Color(0.2, 0.8, 1.0, 0.7)   # Cyan - decor placement
				elif pointing_at_grabbable:
					mat.albedo_color = Color(0.1, 1.0, 0.2, 0.7)   # Green - grabbable item
				elif pointing_at_interactable:
					mat.albedo_color = Color(1.0, 0.8, 0.1, 0.7)   # Yellow - B-interact
				elif pointing_at_transition:
					mat.albedo_color = Color(0.9, 0.9, 1.0, 0.8)   # White - level transition
				else:
					mat.albedo_color = Color(1.0, 0.2, 0.1, 0.6)   # Red - nothing
			var cyl := laser.mesh as CylinderMesh
			if cyl:
				cyl.height = 1.0
				laser.position.z = -0.5

			# Update hover label with target name
			var hover_label: Label3D = _get_hover_label.call()
			if hover_label:
				if hover_collider != null:
					if pointing_at_interactable or pointing_at_transition:
						hover_label.text = _find_interactable_name.call(hover_collider)
					else:
						hover_label.text = _format_node_name_fn.call(hover_collider.name)
					hover_label.global_position = hover_hit_pos + Vector3.UP * 0.15
					hover_label.visible = true
				else:
					hover_label.visible = false
			var has_target := pointing_at_grabbable or pointing_at_interactable or pointing_at_furniture or pointing_at_transition
			laser.visible = _get_laser_always_on.call() or has_target
		else:
			var hover_label: Label3D = _get_hover_label.call()
			if hover_label:
				hover_label.visible = false
			laser.visible = false
