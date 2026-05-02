extends SceneTree

# run_tests.gd
#
# Headless GDScript test entry. Run via:
#
#     godot --headless --script res://tests/gdscript/run_tests.gd --quit
#
# (The --quit is implicit: this script calls quit() with the suite exit code.)
#
# Test files live in tests/gdscript/test_*.gd and are loaded by absolute path
# below. To add a new suite, drop it in the SUITES list.

const TestRunner = preload("res://tests/gdscript/lib/test_runner.gd")

const SUITES := [
	["zone_math",     "res://tests/gdscript/test_zone_math.gd"],
	["config_io",     "res://tests/gdscript/test_config_io.gd"],
	["weapon_slots",  "res://tests/gdscript/test_weapon_slots.gd"],
	["input_routing", "res://tests/gdscript/test_input_routing.gd"],
	["weapon_cache",  "res://tests/gdscript/test_weapon_cache.gd"],
]


func _init() -> void:
	print("")
	print("================================================")
	print("Road to Vostok VR Mod - GDScript test suite")
	print("Godot " + Engine.get_version_info()["string"])
	print("================================================")

	var runner = TestRunner.new()
	for suite_def in SUITES:
		var suite_name: String = suite_def[0]
		var suite_path: String = suite_def[1]
		var script: Script = load(suite_path)
		if script == null:
			runner.failures.append(suite_name + ": failed to load " + suite_path)
			print("  ERROR: could not load " + suite_path)
			continue
		var instance = script.new()
		runner.run_suite(suite_name, instance)

	var code := runner.summary()
	quit(code)
