extends RefCounted

# config_io.gd
# JSON config read/write primitives. Owns the file path, the bundled-defaults
# seed path, and a single read-modify-write helper that all save paths route
# through. Keeps load/save logic in one place so a new save site cannot
# accidentally drop keys another site owns.
#
# Field-level marshalling (which keys map to which autoload variables) lives
# in vr_mod_init.gd; this module is intentionally schema-agnostic.
#
# Logging is delegated to the autoload via a Callable so we don't need to
# duplicate _log() here.

const DEFAULT_RES_PATH := "res://resources/default_config.json"

var path: String        # absolute user:// config path, e.g. "user://vr_mod/vr_mod_config.json"
var log_fn: Callable    # called with (msg: String) for diagnostics; may be empty Callable

func _init(p_path: String, p_log_fn: Callable = Callable()) -> void:
	path = p_path
	log_fn = p_log_fn


func _log(msg: String) -> void:
	if log_fn.is_valid():
		log_fn.call(msg)


# Read the config dict. If the file is missing, seeds it from the bundled
# defaults at DEFAULT_RES_PATH. Returns null if the file still does not exist
# or cannot be parsed (caller should fall back to compiled-in defaults).
func read() -> Variant:
	if not FileAccess.file_exists(path):
		if FileAccess.file_exists(DEFAULT_RES_PATH):
			var src := FileAccess.open(DEFAULT_RES_PATH, FileAccess.READ)
			if src:
				var content := src.get_as_text()
				src.close()
				DirAccess.make_dir_recursive_absolute(path.get_base_dir())
				var dst := FileAccess.open(path, FileAccess.WRITE)
				if dst:
					dst.store_string(content)
					dst.close()
					_log("[VR Mod] Seeded config from bundled defaults: " + path)
		if not FileAccess.file_exists(path):
			_log("[VR Mod] Config not found at: " + path + ", using defaults")
			return null

	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return null
	var json := JSON.new()
	var ok := json.parse(f.get_as_text())
	f.close()
	if ok != OK or not (json.data is Dictionary):
		return null
	return json.data


# Read-modify-write helper. Reads the existing dict (or starts empty if the
# file is missing or unreadable), runs the mutator on it, writes back. Adds a
# version stamp on every write so future migrations can branch on it.
#
# The mutator MUST take a single Dictionary arg and mutate in place. Returning
# a value is ignored. Example:
#
#     config_io.mutate(func(data):
#         data["resume"] = {"slot": slot, "hand": hand})
#
# Returns true on successful write, false if the file could not be opened.
func mutate(mutator: Callable) -> bool:
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var json := JSON.new()
			if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
				data = json.data
			f.close()
	data["version"] = data.get("version", 1)
	mutator.call(data)
	var out := FileAccess.open(path, FileAccess.WRITE)
	if not out:
		_log("[VR Mod] Config save failed (cannot open for write): " + path)
		return false
	out.store_string(JSON.stringify(data, "\t"))
	out.close()
	return true
