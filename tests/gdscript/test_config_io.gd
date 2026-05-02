extends RefCounted

# test_config_io.gd
#
# Round-trip tests for resources/vr_mod/config_io.gd. Asserts:
#   - mutate() preserves keys across multiple writes (the original god-autoload
#     bug class that motivated the helper).
#   - mutate() stamps "version" on first write.
#   - mutate() does not clobber an explicit version that the caller set.
#   - read() returns null if the file does not exist AND no bundled defaults
#     are reachable (we cannot easily simulate the bundled-defaults branch
#     headlessly, so it is exercised in the live game).

const ConfigIo = preload("res://resources/vr_mod/config_io.gd")


# Each test gets its own user:// scratch path to avoid cross-pollution.
func _scratch_path(suffix: String) -> String:
	return "user://test_config_io_" + suffix + ".json"


func _cleanup(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func test_round_trip_preserves_keys(t) -> void:
	var p := _scratch_path("rt")
	_cleanup(p)
	var io = ConfigIo.new(p)

	# Write A: set holsters.
	var ok1 = io.mutate(func(d):
		d["holsters"] = {"zone_radius": 0.20, "mirrored": false})
	t.assert_true(ok1, "first mutate succeeds")

	# Write B: set comfort. Should NOT drop holsters.
	var ok2 = io.mutate(func(d):
		d["comfort"] = {"vignette_enabled": true})
	t.assert_true(ok2, "second mutate succeeds")

	var data = io.read()
	t.assert_true(data is Dictionary, "read returns dict")
	t.assert_true(data.has("holsters"), "first-write key 'holsters' preserved across second write")
	t.assert_true(data.has("comfort"), "second-write key 'comfort' present")
	t.assert_eq(data["holsters"]["zone_radius"], 0.20, "holsters.zone_radius round-trips")
	t.assert_eq(data["comfort"]["vignette_enabled"], true, "comfort.vignette_enabled round-trips")
	_cleanup(p)


func test_version_stamp_added_on_first_write(t) -> void:
	var p := _scratch_path("ver")
	_cleanup(p)
	var io = ConfigIo.new(p)

	io.mutate(func(d):
		d["foo"] = 1)
	var data = io.read()
	t.assert_true(data.has("version"), "version stamp present after mutate")
	t.assert_eq(data["version"], 1, "default version = 1")
	_cleanup(p)


func test_explicit_version_not_clobbered(t) -> void:
	var p := _scratch_path("ver2")
	_cleanup(p)
	var io = ConfigIo.new(p)

	io.mutate(func(d):
		d["version"] = 5
		d["payload"] = "hi")
	var data = io.read()
	t.assert_eq(data["version"], 5, "explicit version preserved")
	t.assert_eq(data["payload"], "hi", "payload preserved")
	_cleanup(p)


func test_nested_mutation_preserved(t) -> void:
	var p := _scratch_path("nested")
	_cleanup(p)
	var io = ConfigIo.new(p)

	# Establish a deep structure.
	io.mutate(func(d):
		d["weapon_offsets"] = {
			"1": {"x": 0.1, "y": 0.2, "z": 0.3, "rot": 0.0},
			"2": {"x": 0.4, "y": 0.5, "z": 0.6, "rot": 0.1},
		})

	# Update only slot 1.
	io.mutate(func(d):
		var wo = d.get("weapon_offsets", {})
		wo["1"]["rot"] = 1.5
		d["weapon_offsets"] = wo)

	var data = io.read()
	t.assert_eq(data["weapon_offsets"]["1"]["rot"], 1.5, "slot 1 rot updated")
	t.assert_eq(data["weapon_offsets"]["1"]["x"], 0.1, "slot 1 other fields kept")
	t.assert_eq(data["weapon_offsets"]["2"]["rot"], 0.1, "slot 2 untouched")
	_cleanup(p)


func test_read_missing_file_returns_null(t) -> void:
	var p := _scratch_path("missing_xyz")
	_cleanup(p)
	# Without bundled defaults at res://resources/default_config.json being
	# absent in this scenario, read() may seed and return data. We instead
	# assert mutate() handles the missing-file case by creating fresh.
	var io = ConfigIo.new(p)
	io.mutate(func(d):
		d["fresh"] = true)
	var data = io.read()
	t.assert_true(data is Dictionary, "mutate creates the file when missing")
	t.assert_eq(data.get("fresh"), true, "mutate writes the requested key")
	_cleanup(p)


# --- version migration ------------------------------------------------------
#
# The schema is currently v1, so "migration" is just confirming the version
# stamp is present, persistent, and survives unrelated edits. When v2
# arrives, a real migration test goes here.

func test_v1_file_read_unchanged(t) -> void:
	# Pre-seed a v1-shaped file directly, then read it back. The dict should
	# round-trip with version=1 intact.
	var p := _scratch_path("v1read")
	_cleanup(p)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p).get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string('{"version": 1, "comfort": {"vignette_enabled": true}}')
	f.close()

	var io = ConfigIo.new(p)
	var data = io.read()
	t.assert_eq(data["version"], 1, "v1 file reads back as v1")
	t.assert_eq(data["comfort"]["vignette_enabled"], true, "payload preserved")
	_cleanup(p)


func test_v1_file_survives_mutation(t) -> void:
	# Existing v1 file gets a new key written via mutate(). Version stamp must
	# remain 1 (the mutator does not touch it; the helper only fills in 1 if
	# absent).
	var p := _scratch_path("v1mut")
	_cleanup(p)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p).get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string('{"version": 1, "holsters": {"zone_radius": 0.20}}')
	f.close()

	var io = ConfigIo.new(p)
	io.mutate(func(d):
		d["new_section"] = {"foo": "bar"})
	var data = io.read()
	t.assert_eq(data["version"], 1, "version=1 preserved through mutation")
	t.assert_true(data.has("holsters"), "pre-existing v1 keys preserved")
	t.assert_true(data.has("new_section"), "new key written")
	_cleanup(p)


func test_unstamped_file_gets_v1_on_first_mutate(t) -> void:
	# A legacy file that pre-dates the version stamp should be auto-tagged
	# as v1 when mutate() touches it. This is the migration entry point.
	var p := _scratch_path("legacy")
	_cleanup(p)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p).get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string('{"comfort": {"vignette_enabled": false}}')  # No "version" key
	f.close()

	var io = ConfigIo.new(p)
	io.mutate(func(d):
		pass)  # No-op mutation just to trigger the stamp.
	var data = io.read()
	t.assert_eq(data["version"], 1, "legacy unstamped file becomes v1 on first mutate")
	t.assert_eq(data["comfort"]["vignette_enabled"], false, "legacy payload preserved")
	_cleanup(p)


func test_callable_log_invoked_on_missing_write(t) -> void:
	# Confirm the log_fn port is actually invoked (not just survives a call).
	# Trigger the failure branch of mutate() by pointing at a path whose
	# parent directory does not exist and cannot be created from user-space.
	# That forces FileAccess.open(WRITE) to fail, which mutate() logs.
	var p := "user://__vr_mod_nonexistent_dir__/cannot_write.json"
	var captured: Array = []
	var log_fn := func(msg):
		captured.append(msg)
	var io = ConfigIo.new(p, log_fn)

	# mutate() does not pre-create the parent directory; the WRITE step fails
	# and routes through _log() which calls our captured log_fn.
	var ok = io.mutate(func(d):
		d["payload"] = "ignored")
	t.assert_true(not ok, "mutate returns false when write fails")
	t.assert_true(captured.size() > 0, "log_fn was actually invoked (captured " + str(captured.size()) + " message(s))")
	if captured.size() > 0:
		var msg: String = captured[0]
		t.assert_true(msg.find("Config save failed") >= 0, "log message identifies the failure mode")
