extends RefCounted

# test_runner.gd
#
# Tiny test harness for the headless GDScript suite. Tests are RefCounted
# scripts containing methods named "test_*". The runner instantiates each
# script and calls every matching method.
#
# Each test method receives a TestRunner instance and uses its assertion
# helpers (assert_eq, assert_true, assert_near, etc.). On failure the runner
# records the message and continues — one bad assertion does not abort the
# whole run.
#
# Exit code: 0 if all assertions pass, 1 if any fail. Set on the calling
# script via its return value.

var passes := 0
var failures: Array = []
var current_test := ""


func fail(msg: String) -> void:
	failures.append(current_test + ": " + msg)
	print("    FAIL: " + msg)


func ok(msg: String) -> void:
	passes += 1
	print("    PASS: " + msg)


func assert_true(cond: bool, msg: String) -> void:
	if cond:
		ok(msg)
	else:
		fail(msg)


func assert_eq(actual, expected, msg: String) -> void:
	if actual == expected:
		ok(msg + " (== " + str(expected) + ")")
	else:
		fail(msg + ": expected " + str(expected) + " got " + str(actual))


func assert_near(actual: float, expected: float, eps: float, msg: String) -> void:
	if abs(actual - expected) <= eps:
		ok(msg + " (~= " + str(expected) + ")")
	else:
		fail(msg + ": expected ~= " + str(expected) + " (eps " + str(eps) + ") got " + str(actual))


func assert_vec_near(actual: Vector3, expected: Vector3, eps: float, msg: String) -> void:
	if (actual - expected).length() <= eps:
		ok(msg + " (~= " + str(expected) + ")")
	else:
		fail(msg + ": expected " + str(expected) + " got " + str(actual))


# Run every test_* method on the given RefCounted instance under suite_name.
func run_suite(suite_name: String, suite) -> void:
	print("")
	print("== " + suite_name + " ==")
	var methods: Array = suite.get_method_list()
	for m in methods:
		var name: String = m["name"]
		if not name.begins_with("test_"):
			continue
		current_test = suite_name + "." + name
		print("  -> " + name)
		suite.call(name, self)
	current_test = ""


func summary() -> int:
	print("")
	print("================================================")
	print("GDScript tests: " + str(passes) + " passed, " + str(failures.size()) + " failed")
	if failures.size() > 0:
		print("")
		print("Failures:")
		for f in failures:
			print("  - " + f)
		return 1
	return 0
