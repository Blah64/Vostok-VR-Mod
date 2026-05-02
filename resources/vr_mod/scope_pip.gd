extends RefCounted

# scope_pip.gd
# Scope picture-in-picture: detects a visible scope attachment with a SubViewport,
# patches its lens material with a SCOPE_PIP_SHADER that samples our own
# stereo-correct viewport, and patches the reticle shader to use a VR-correct
# ray-plane intersection. Also handles variable-zoom cycling.
#
# Subsystem-owned state. The autoload is no longer the storage for any of
# the scope PIP scene graph or the variable-zoom bookkeeping.
#
# Port contract:
#   tree                       : SceneTree
#   get_owner_node             : Callable() -> Node            (parent for our SubViewport — autoload)
#   get_main_viewport          : Callable() -> Viewport        (for shared World3D)
#   get_game_camera            : Callable() -> Camera3D
#   get_weapon_slot            : Callable() -> int
#   get_weapon_hand            : Callable() -> String
#   get_controller             : Callable(hand) -> XRController3D
#   get_weapon_cache           : Callable(weapon_rig) -> Dictionary
#   sample_recoil_chain        : Callable(weapon_rig) -> Transform3D
#   get_pip_shader_source      : Callable() -> String
#   log                        : Callable(msg) -> void

# Subsystem-owned state.
var camera: Camera3D = null              # Our scope render camera
var viewport: SubViewport = null         # Our SubViewport
var attachment: Node3D = null            # The visible scope attachment node
var lens_mesh: MeshInstance3D = null     # MeshInstance3D with the lens surface
var overridden_surfaces: Array = []      # [{surf: int, original: Material}]
var active: bool = false
var weapon_slot: int = 0
var vp_created: bool = false
var is_variable: bool = false
var zoom_fovs: Array = []
var zoom_reticle_scales: Array = []
var zoom_index: int = 0
var fixed_reticle_instances: Dictionary = {}  # MeshInstance3D instance_id -> true


# Ports
var _tree: SceneTree
var _get_owner_node: Callable
var _get_main_viewport: Callable
var _get_game_camera: Callable
var _get_weapon_slot: Callable
var _get_weapon_hand: Callable
var _get_controller: Callable
var _get_weapon_cache: Callable
var _sample_recoil_chain: Callable
var _get_pip_shader_source: Callable
var _log_fn: Callable


func _init(tree: SceneTree, ports: Dictionary) -> void:
	_tree = tree
	_get_owner_node = ports["get_owner_node"]
	_get_main_viewport = ports["get_main_viewport"]
	_get_game_camera = ports["get_game_camera"]
	_get_weapon_slot = ports["get_weapon_slot"]
	_get_weapon_hand = ports["get_weapon_hand"]
	_get_controller = ports["get_controller"]
	_get_weapon_cache = ports["get_weapon_cache"]
	_sample_recoil_chain = ports["sample_recoil_chain"]
	_get_pip_shader_source = ports["get_pip_shader_source"]
	_log_fn = ports.get("log", Callable())


func _log(msg: String) -> void:
	if _log_fn.is_valid():
		_log_fn.call(msg)


func process(_frame: Dictionary, _delta: float) -> void:
	# Scope PIP setup + camera sync are driven from weapon_sync per frame
	# (they run only when a weapon_rig is present and need the chain caches
	# weapon_sync builds). The hook stays here so the system fits the
	# subsystem-loop contract; zoom cycling is event-driven from input.
	pass


func fix_reticle_parallax(weapon_rig: Node3D) -> void:
	# VR parallax fix: the game's Reticle shader uses normalize(reticlePosition)+NORMAL
	# for UV, which is an approximation that breaks in stereo VR. Replace with a proper
	# ray-plane intersection (Addmix collimator method) that uses only rotation matrices
	# (same for both eyes) and the per-eye VIEW direction for correct collimation.
	var attachments = _get_weapon_cache.call(weapon_rig).get("attachments")
	if not attachments or not is_instance_valid(attachments):
		return
	for child in attachments.get_children():
		if not child is Node3D or not child.visible:
			continue
		patch_reticle_shader(child)


func patch_reticle_shader(node: Node) -> void:
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		var inst_id = mi.get_instance_id()
		if fixed_reticle_instances.has(inst_id):
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
			# VR-compatible ray-plane intersection.
			var old_frag = "vec3 reticleOffset = normalize(reticlePosition) + NORMAL;\n\tvec2 reticleUV = (reticleOffset.xy / size) * vec2(1.0, -1.0);"
			var new_frag = "// vr_reticle_fix: ray-plane intersection for VR collimation\n\tmat3 _mvr = mat3(VIEW_MATRIX[0].xyz, VIEW_MATRIX[1].xyz, VIEW_MATRIX[2].xyz) * mat3(MODEL_MATRIX[0].xyz, MODEL_MATRIX[1].xyz, MODEL_MATRIX[2].xyz);\n\tvec3 _sn = _mvr * vec3(0.0, 0.0, -1.0);\n\tvec3 _su = _mvr * vec3(1.0, 0.0, 0.0);\n\tvec3 _sv = _mvr * vec3(0.0, 1.0, 0.0);\n\tvec3 _vp = VIEW / dot(VIEW, _sn);\n\tvec2 reticleUV = vec2(-dot(_vp, _su), dot(_vp, _sv)) / (-size);"
			var patched = code.replace(old_frag, new_frag)
			if patched == code:
				_log("reticle: WARNING - fragment target not found")
				var idx = code.find("reticleOffset")
				if idx >= 0:
					_log("reticle: actual code: " + code.substr(idx, 120))
				continue
			# Patch the shader in-place on the game's own material
			var new_shader = Shader.new()
			new_shader.code = patched
			mat.shader = new_shader
			_log("reticle: patched fragment surf=" + str(s) + " on " + mi.name)
		if found_reticle:
			fixed_reticle_instances[inst_id] = true
	for child in node.get_children():
		patch_reticle_shader(child)


func setup_scope_pip(weapon_rig: Node3D) -> void:
	if active and weapon_slot == _get_weapon_slot.call():
		# Check if current scope attachment is still valid and visible
		if attachment and is_instance_valid(attachment) and attachment.visible:
			return
		# Scope changed - re-detect
	cleanup_scope()
	# Skeleton3D + Attachments resolved once in the weapon cache
	var attachments = _get_weapon_cache.call(weapon_rig).get("attachments")
	if not attachments or not is_instance_valid(attachments):
		return
	for child in attachments.get_children():
		if not child is Node3D or not child.visible:
			continue
		var game_vp = child.get_node_or_null("Viewport")
		if not game_vp or not (game_vp is SubViewport):
			continue
		# Found a visible scope attachment with a SubViewport - it's a zoom scope
		var mesh_node = child.get_node_or_null("Mesh")
		if not mesh_node or not (mesh_node is MeshInstance3D):
			continue
		var mi = mesh_node as MeshInstance3D
		if not mi.mesh:
			continue
		attachment = child
		lens_mesh = mi
		weapon_slot = _get_weapon_slot.call()
		active = true
		# Detect variable zoom capability and build per-level FOV/reticle arrays
		var att_data = child.get("attachmentData")
		is_variable = att_data != null and att_data.get("variable") == true
		if is_variable and att_data:
			var ret_sizes = att_data.get("reticleSize")  # Vector3 with per-level sizes
			if ret_sizes and ret_sizes is Vector3:
				var num_levels := 3
				zoom_fovs.clear()
				zoom_reticle_scales.clear()
				# Base reticle size is level 0 (widest zoom)
				var base_size: float = ret_sizes.x
				for i in range(num_levels):
					var s: float = [ret_sizes.x, ret_sizes.y, ret_sizes.z][i]
					# Reticle scale: how much bigger the reticle appears vs level 0
					zoom_reticle_scales.append(s / base_size if base_size > 0.0 else 1.0)
					# FOV: inversely proportional to magnification (reticle ratio)
					zoom_fovs.append(0.0)
			# Initialize zoom index from game's current zoom level
			var wr_zoom = weapon_rig.get("zoomLevel")
			if wr_zoom != null:
				zoom_index = clampi(int(wr_zoom), 0, zoom_fovs.size() - 1)
			else:
				zoom_index = 0
		# Create our own SubViewport + Camera if not already done
		if not vp_created:
			viewport = SubViewport.new()
			viewport.name = "VRScopeVP"
			viewport.size = Vector2i(512, 512)
			viewport.transparent_bg = false
			viewport.disable_3d = false
			viewport.world_3d = _get_main_viewport.call().world_3d
			_get_owner_node.call().add_child(viewport)
			camera = Camera3D.new()
			camera.name = "ScopeCamera"
			camera.fov = 3.0
			camera.near = 0.05
			camera.far = 4000.0
			viewport.add_child(camera)
			vp_created = true
			_log("scope: created own SubViewport + Camera, world_3d=" + str(viewport.world_3d))
		# Read FOV from the game's scope camera
		var game_cam: Camera3D = null
		for vp_child in game_vp.get_children():
			if vp_child is Camera3D:
				game_cam = vp_child as Camera3D
				break
		var scope_fov := 3.0
		if game_cam:
			scope_fov = game_cam.fov
		if is_variable and zoom_fovs.size() > 0 and zoom_reticle_scales.size() > 0:
			# Derive per-level FOVs from game camera FOV and reticle size ratios
			var base_scale: float = zoom_reticle_scales[zoom_index] if zoom_index < zoom_reticle_scales.size() else 1.0
			for i in range(zoom_fovs.size()):
				# FOV is inversely proportional to magnification ratio
				var ratio: float = zoom_reticle_scales[i] / base_scale if base_scale > 0.0 else 1.0
				zoom_fovs[i] = scope_fov / ratio
			camera.fov = zoom_fovs[zoom_index]
			_log("scope: variable zoom fovs=" + str(zoom_fovs) + " reticle_scales=" + str(zoom_reticle_scales) + " index=" + str(zoom_index))
		else:
			camera.fov = scope_fov
		# Build PIP shader + material
		var shader = Shader.new()
		shader.code = _get_pip_shader_source.call()
		# Find the scope lens surface (has "reticle" uniform AND "scope" = true)
		overridden_surfaces.clear()
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
			# This is the scope lens surface - replace with PIP+reticle combo.
			if patched_count == 0:
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
				(game_vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
			overridden_surfaces.append({"surf": s, "original": mat})
			var pip_mat = ShaderMaterial.new()
			pip_mat.shader = shader
			pip_mat.set_shader_parameter("scope_texture", viewport.get_texture())
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


func update_scope_camera() -> void:
	if not active or not camera or not is_instance_valid(camera):
		active = false
		return
	if not attachment or not is_instance_valid(attachment):
		active = false
		return
	# Position scope camera at the scope, looking along weapon barrel
	var gc = _get_game_camera.call()
	if not gc or not is_instance_valid(gc):
		return
	var mgr = gc.get_node_or_null("Manager")
	if not mgr or mgr.get_child_count() == 0:
		return
	var weapon_rig = mgr.get_child(0)
	if not weapon_rig:
		return
	var scope_pos = attachment.global_position
	# Chain nodes (Handling/Sway/Noise/Tilt/Impulse/Recoil) rotate the barrel
	var chain_xform: Transform3D = _sample_recoil_chain.call(weapon_rig)
	var barrel_basis: Basis = weapon_rig.global_basis * chain_xform.basis
	var barrel_forward: Vector3 = barrel_basis.z
	var barrel_up: Vector3 = barrel_basis.y
	camera.global_position = scope_pos
	camera.look_at(scope_pos + barrel_forward * 100.0, barrel_up)


func cycle_scope_zoom(direction: int) -> void:
	# direction: +1 = zoom in (higher index = narrower FOV), -1 = zoom out
	var new_index = clampi(zoom_index + direction, 0, zoom_fovs.size() - 1)
	if new_index == zoom_index:
		return
	zoom_index = new_index
	camera.fov = zoom_fovs[zoom_index]
	# Update reticle scale on PIP material
	if zoom_reticle_scales.size() > zoom_index:
		var ret_scale: float = zoom_reticle_scales[zoom_index]
		if lens_mesh and is_instance_valid(lens_mesh):
			for entry in overridden_surfaces:
				var mat = lens_mesh.get_surface_override_material(entry["surf"])
				if mat and mat is ShaderMaterial:
					mat.set_shader_parameter("reticle_scale", ret_scale)
	# Sync game's weapon rig zoomLevel so reticle size etc. stays consistent
	var gc = _get_game_camera.call()
	if gc and is_instance_valid(gc):
		var mgr = gc.get_node_or_null("Manager")
		if mgr and mgr.get_child_count() > 0:
			var wr = mgr.get_child(0)
			wr.set("zoomLevel", zoom_index)
	# Haptic feedback on weapon hand
	var ctrl = _get_controller.call(_get_weapon_hand.call())
	if ctrl:
		ctrl.trigger_haptic_pulse("haptic", 0.0, 0.4, 0.1, 0.0)
	_log("scope zoom: level=" + str(zoom_index) + " fov=" + str(zoom_fovs[zoom_index]))


func cleanup_scope() -> void:
	if lens_mesh and is_instance_valid(lens_mesh):
		for entry in overridden_surfaces:
			lens_mesh.set_surface_override_material(entry["surf"], entry["original"])
	overridden_surfaces.clear()
	lens_mesh = null
	# Re-enable game's scope viewport so original material has a live texture on next draw
	if attachment and is_instance_valid(attachment):
		var game_vp = attachment.get_node_or_null("Viewport")
		if game_vp and game_vp is SubViewport:
			(game_vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
	attachment = null
	active = false
	weapon_slot = 0
	is_variable = false
	zoom_index = 0
	zoom_fovs.clear()
	zoom_reticle_scales.clear()
	# Don't destroy viewport/camera - reuse across weapon changes
	if viewport and is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
