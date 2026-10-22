class_name TestCase
extends RefCounted
## Base for tests in tests/unit/. Every method named test_* runs. Use the expect_* helpers;
## a failing expectation is recorded and the test keeps going.

var failures: Array[String] = []
var _current := ""


func run_test(method: String) -> void:
	_current = method
	call(method)


func expect(condition: bool, message: String = "") -> void:
	if not condition:
		failures.append("%s: expected true. %s" % [_current, message])


func expect_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: expected %s, got %s. %s" % [_current, var_to_str(expected), var_to_str(actual), message])
