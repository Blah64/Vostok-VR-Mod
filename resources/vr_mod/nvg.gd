extends RefCounted

# nvg.gd
# Night vision overlay (3D quad parented to xr_camera, hides the game's 2D
# overlay via modulate.a so the game's NVG.gd toggle still works), the optional
# mono SubViewport+camera, and the comfort vignette ring used during turning.
#
# Subsystem-owned state. All scene-graph references and runtime activation
# bookkeeping live here. The user-tunable knobs (_nvg_brightness, _nvg_mono,
# _vignette_enabled, _vignette_strength) remain on the autoload because the
# F8 config screen writes them directly; this module reads them through ports.
#
# Port contract:
#   tree                       : SceneTree
#   get_owner_node             : Callable() -> Node
#   get_main_viewport          : Callable() -> Viewport
#   get_camera                 : Callable() -> XRCamera3D
#   get_nvg_brightness         : Callable() -> float
#   get_nvg_mono               : Callable() -> bool
#   get_vignette_enabled       : Callable() -> bool
#   get_vignette_strength      : Callable() -> float
#   get_overlay_shader_source  : Callable() -> String
#   get_vignette_shader_source : Callable() -> String
#   log                        : Callable(msg) -> void

# Subsystem-owned state.
var nvg_active: bool = false
var nvg_overlay_installed: bool = false
var nvg_overlay_mesh: MeshInstance3D = null
var nvg_mono_viewport: SubViewport = null
var nvg_mono_camera: Camera3D = null
var cached_nvg_overlay: Node = null  # Map/Core/UI/NVG/Overlay (cleared on level transition)

var vignette_mesh: MeshInstance3D = null
var vignette_radius: float = 1.0  # 1.0 = off-screen edge, smaller = more coverage
var vignette_hold: float = 0.0    # seconds remaining; bumped by turn/move input

# NVG-zone hand latch (haptic edge-detection). Holster's zone-haptic loop
# writes this; nothing else reads it.
var hand_in_zone := {"left": false, "right": false}


# Ports
var _tree: SceneTree
var _get_owner_node: Callable
var _get_main_viewport: Callable
var _get_camera: Callable
var _get_nvg_brightness: Callable
var _get_nvg_mono: Callable
var _get_vignette_enabled: Callable
var _get_vignette_strength: Callable
var _get_overlay_shader_source: Callable
var _get_vignette_shader_source: Callable
var _log_fn: Callable


func _init(tree: SceneTree, ports: Dictionary) -> void:
	_tree = tree
	_get_owner_node = ports["get_owner_node"]
	_get_main_viewport = ports["get_main_viewport"]
	_get_camera = ports["get_camera"]
	_get_nvg_brightness = ports["get_nvg_brightness"]
	_get_nvg_mono = ports["get_nvg_mono"]
	_get_vignette_enabled = ports["get_vignette_enabled"]
	_get_vignette_strength = ports["get_vignette_strength"]
	_get_overlay_shader_source = ports["get_overlay_shader_source"]
	_get_vignette_shader_source = ports["get_vignette_shader_source"]
	_log_fn = ports.get("log", Callable())


func _log(msg: String) -> void:
	if _log_fn.is_valid():
		_log_fn.call(msg)


func hold_vignette(min_seconds: float) -> void:
	# Convenience for input handlers: keep vignette active for at least
	# min_seconds. Callers don't need to know about the underlying field.
	if min_seconds > vignette_hold:
		vignette_hold = min_seconds


func process(_frame: Dictionary, delta: float) -> void:
	update_nvg_overlay(delta)
	update_comfort_vignette(delta)


func update_nvg_overlay(_delta: float) -> void:
	if not nvg_overlay_installed:
		return

	# Poll game's NVG overlay visibility as the true NVG state.
	# We use modulate.a=0 to hide it visually (not visible=false), so the game's
	# NVG.gd script can still toggle overlay.visible freely and we can read it.
	if not cached_nvg_overlay or not is_instance_valid(cached_nvg_overlay):
		cached_nvg_overlay = _tree.root.get_node_or_null("Map/Core/UI/NVG/Overlay")
	var overlay := cached_nvg_overlay
	if not overlay:
		return
	var game_nvg_on: bool = overlay.visible

	# State transition: NVG just turned on
	if game_nvg_on and not nvg_active:
		nvg_active = true
		overlay.modulate.a = 0.0  # hide game's 2D overlay from HUD quad (keep visible=true)
		nvg_overlay_mesh.visible = true
		var mat = nvg_overlay_mesh.material_override as ShaderMaterial
		mat.set_shader_parameter("brightness", _get_nvg_brightness.call())
		var mono: bool = _get_nvg_mono.call()
		if mono:
			create_nvg_mono_viewport()
			nvg_mono_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			var vp_tex = nvg_mono_viewport.get_texture()
			mat.set_shader_parameter("mono_tex", vp_tex)
			mat.set_shader_parameter("use_mono", true)
			(nvg_overlay_mesh.mesh as QuadMesh).size = Vector2(4.0, 4.0)
			nvg_overlay_mesh.position = Vector3(0.0, 0.0, -1.0)
		else:
			mat.set_shader_parameter("use_mono", false)
			# Stereo: close to camera, oversized for SCREEN_UV coverage
			(nvg_overlay_mesh.mesh as QuadMesh).size = Vector2(4.0, 4.0)
			nvg_overlay_mesh.position = Vector3(0.0, 0.0, -0.15)
		_log("[VR Mod] NVG overlay activated (mono=" + str(mono) + ")")

	# State transition: NVG just turned off
	elif not game_nvg_on and nvg_active:
		nvg_active = false
		overlay.modulate.a = 1.0  # restore game overlay opacity for next activation
		nvg_overlay_mesh.visible = false
		if nvg_mono_viewport:
			nvg_mono_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_log("[VR Mod] NVG overlay deactivated")

	# While NVG active: update shader time + sync mono camera
	if nvg_active:
		# Keep game overlay hidden
		if overlay:
			overlay.modulate.a = 0.0
		var mat = nvg_overlay_mesh.material_override as ShaderMaterial
		mat.set_shader_parameter("time_val", Time.get_ticks_msec() / 1000.0)
		var cam = _get_camera.call()
		if _get_nvg_mono.call() and nvg_mono_camera and cam:
			nvg_mono_camera.global_transform = cam.global_transform


func setup_nvg_overlay() -> void:
	nvg_overlay_mesh = MeshInstance3D.new()
	nvg_overlay_mesh.name = "NVGOverlay"
	var quad = QuadMesh.new()
	quad.size = Vector2(4.0, 4.0)
	nvg_overlay_mesh.mesh = quad

	var shader = Shader.new()
	shader.code = _get_overlay_shader_source.call()
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = 127
	mat.set_shader_parameter("tint", Color(0.47, 0.67, 0.51, 1.0))
	mat.set_shader_parameter("brightness", _get_nvg_brightness.call())
	mat.set_shader_parameter("use_mono", _get_nvg_mono.call())
	nvg_overlay_mesh.material_override = mat

	# Put overlay on layer 20 ONLY so the mono camera can exclude it (prevents feedback loop)
	# XR cameras default cull_mask includes all 20 layers, so they still see it
	nvg_overlay_mesh.layers = (1 << 19)  # layer 20 only
	nvg_overlay_mesh.position = Vector3(0.0, 0.0, -0.15)
	nvg_overlay_mesh.visible = false
	var cam = _get_camera.call()
	cam.add_child(nvg_overlay_mesh)
	nvg_overlay_installed = true
	_log("[VR Mod] NVG overlay installed (mono=" + str(_get_nvg_mono.call()) + " brightness=" + str(_get_nvg_brightness.call()) + ")")


func create_nvg_mono_viewport() -> void:
	if nvg_mono_viewport:
		return
	# Use XR per-eye render size for correct aspect ratio, scaled down for perf
	var xr_iface = XRServer.primary_interface
	var vp_size := Vector2i(1024, 1024)
	if xr_iface:
		var eye_size = xr_iface.get_render_target_size()
		var scale_factor := 0.5
		vp_size = Vector2i(maxi(int(eye_size.x * scale_factor), 512), maxi(int(eye_size.y * scale_factor), 512))

	nvg_mono_viewport = SubViewport.new()
	nvg_mono_viewport.name = "NVGMonoVP"
	nvg_mono_viewport.size = vp_size
	nvg_mono_viewport.transparent_bg = false
	nvg_mono_viewport.disable_3d = false
	nvg_mono_viewport.world_3d = _get_main_viewport.call().world_3d
	nvg_mono_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_get_owner_node.call().add_child(nvg_mono_viewport)

	nvg_mono_camera = Camera3D.new()
	nvg_mono_camera.name = "NVGMonoCamera"
	nvg_mono_camera.fov = 90.0
	nvg_mono_camera.near = 0.05
	nvg_mono_camera.far = 4000.0
	# Exclude layer 20 so mono camera doesn't see the NVG overlay quad (prevents feedback loop)
	nvg_mono_camera.cull_mask = 0xFFFFF & ~(1 << 19)  # all 20 layers except layer 20
	nvg_mono_viewport.add_child(nvg_mono_camera)
	_log("[VR Mod] NVG mono viewport created (" + str(vp_size.x) + "x" + str(vp_size.y) + ")")


func build_vignette_ring_mesh(steps: int) -> ArrayMesh:
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


func setup_comfort_vignette() -> void:
	vignette_mesh = MeshInstance3D.new()
	vignette_mesh.name = "ComfortVignette"
	vignette_mesh.mesh = build_vignette_ring_mesh(32)
	var shader = Shader.new()
	shader.code = _get_vignette_shader_source.call()
	var mat = ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = 126
	mat.set_shader_parameter("color", Color(0, 0, 0, 1))
	mat.set_shader_parameter("radius", 1.0)
	mat.set_shader_parameter("fade", 0.15)
	vignette_mesh.material_override = mat
	vignette_mesh.layers = (1 << 19)  # layer 20 only
	vignette_mesh.visible = false
	var cam = _get_camera.call()
	cam.add_child(vignette_mesh)
	vignette_radius = 1.0
	_log("[VR Mod] Comfort vignette installed")


func update_comfort_vignette(delta: float) -> void:
	if not vignette_mesh or not is_instance_valid(vignette_mesh):
		return
	# strength 0.1 -> inner radius 0.85 (subtle), strength 1.0 -> inner radius 0.2 (strong)
	var target_inner = 1.0 - _get_vignette_strength.call() * 0.8
	var target_radius := 1.0
	if _get_vignette_enabled.call() and vignette_hold > 0.0:
		vignette_hold -= delta
		target_radius = target_inner
	# Fast fade in, slow fade out
	var speed := 5.0 if target_radius < vignette_radius else 1.0
	vignette_radius = move_toward(vignette_radius, target_radius, delta * speed)
	var show := vignette_radius < 0.99
	vignette_mesh.visible = show
	if show:
		(vignette_mesh.material_override as ShaderMaterial).set_shader_parameter("radius", vignette_radius)
