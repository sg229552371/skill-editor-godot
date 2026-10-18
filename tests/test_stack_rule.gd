extends GutTest

const StackRule = preload("res://skill_core/modify/stack_rule.gd")
const Diag = preload("res://skill_core/api/diagnostic.gd")

var rule: StackRule

func before_each() -> void:
	rule = StackRule.new()
	assert_true(rule.configure(StackRule.TRANSITION_METADATA, _profiles()))

func _profiles() -> Dictionary:
	return {
		"set_low": {"category": "set", "operands": [10], "mount_order": 0},
		"set_high": {"category": "set", "operands": [20], "mount_order": 1},
		"add": {"category": "add", "operands": [5], "mount_order": 0},
		"add_negative": {"category": "add", "operands": [-7], "mount_order": 0},
		"mul": {"category": "mul", "operands": [2], "mount_order": 0},
		"mul_zero": {"category": "mul", "operands": [0], "mount_order": 0},
		"clamp": {"category": "clamp", "operands": [0, 100], "mount_order": 0},
	}

func _field(minimum: float = 0.0, maximum: float = 100.0) -> Dictionary:
	return {"min": minimum, "max": maximum, "set_conflict_note": "最后挂载者覆盖"}

func _value(base: float, operations: Array, field: Dictionary = {}) -> Dictionary:
	var target_field: Dictionary = field
	if target_field.is_empty():
		target_field = _field()
	return rule.evaluate(base, operations, target_field, "params.damage")

func _diagnostic(result: Dictionary, id: String) -> Variant:
	for diagnostic in result.diagnostics:
		if diagnostic.rule_id == id:
			return diagnostic
	return null

func test_set_overwrites_base_and_add() -> void:
	var result: Dictionary = _value(30.0, [{"category": "add", "operands": [5]}, {"category": "set", "operands": [10]}])
	assert_true(result.ok)
	assert_eq(result.value, 15.0)

func test_add_supports_negative_and_zero_boundary() -> void:
	var result: Dictionary = _value(10.0, [{"category": "add", "operands": [-7]}])
	assert_true(result.ok)
	assert_eq(result.value, 3.0)
	result = _value(10.0, [{"category": "add", "operands": [0]}])
	assert_true(result.ok)
	assert_eq(result.value, 10.0)

func test_mul_supports_zero_and_fractional_reverse_direction() -> void:
	var result: Dictionary = _value(10.0, [{"category": "mul", "operands": [0]}])
	assert_true(result.ok)
	assert_eq(result.value, 0.0)
	result = _value(-4.0, [{"category": "mul", "operands": [-2]}], _field(-10.0, 10.0))
	assert_true(result.ok)
	assert_eq(result.value, 8.0)

func test_clamp_includes_exact_lower_and_upper_bounds() -> void:
	var result: Dictionary = _value(-10.0, [{"category": "clamp", "operands": [0, 100]}])
	assert_true(result.ok)
	assert_eq(result.value, 0.0)
	result = _value(100.0, [{"category": "clamp", "operands": [0, 100]}])
	assert_true(result.ok)
	assert_eq(result.value, 100.0)

func test_fixed_order_is_add_then_mul_even_when_input_is_reversed() -> void:
	var result: Dictionary = _value(10.0, [{"category": "mul", "operands": [2]}, {"category": "add", "operands": [5]}])
	assert_true(result.ok)
	assert_eq(result.value, 30.0)

func test_recalculation_starts_from_base_and_does_not_accumulate() -> void:
	var operations: Array = [{"category": "add", "operands": [5]}, {"category": "mul", "operands": [2]}]
	var first: Dictionary = _value(10.0, operations)
	var second: Dictionary = _value(10.0, operations)
	assert_eq(first.value, 30.0)
	assert_eq(second.value, 30.0)
	var removed: Dictionary = _value(10.0, [{"category": "add", "operands": [5]}])
	assert_eq(removed.value, 15.0)

func test_unknown_category_and_expression_are_blocking_failures() -> void:
	var result: Dictionary = _value(10.0, [{"category": "eval(10+1)", "operands": []}])
	assert_false(result.ok)
	assert_eq(_diagnostic(result, "V-049").severity, Diag.SEV_BLOCK)
	result = _value(10.0, [{"category": "not_registered", "operands": [1]}])
	assert_false(result.ok)
	assert_eq(_diagnostic(result, "V-049").rule_id, "V-049")

func test_multiple_set_without_note_warns_but_last_mount_wins() -> void:
	var field: Dictionary = _field()
	field.erase("set_conflict_note")
	var result: Dictionary = _value(0.0, [{"category": "set", "operands": [10], "mount_order": 1}, {"category": "set", "operands": [20], "mount_order": 2}], field)
	assert_true(result.ok)
	assert_eq(result.value, 20.0)
	var warning: Variant = _diagnostic(result, "V-050")
	assert_not_null(warning)
	assert_eq(warning.severity, Diag.SEV_WARN)

func test_clamp_cannot_escape_exposed_bounds() -> void:
	var result: Dictionary = _value(50.0, [{"category": "clamp", "operands": [0, 200]}])
	assert_false(result.ok)
	assert_eq(_diagnostic(result, "V-051").severity, Diag.SEV_BLOCK)

func test_invalid_merged_value_is_blocking_and_cfg_is_unchanged() -> void:
	var cfg: Dictionary = {"params": {"damage": 10.0}}
	var before: Dictionary = cfg.duplicate(true)
	var result: Dictionary = _value(10.0, [{"category": "add", "operands": [200]}])
	assert_false(result.ok)
	assert_eq(_diagnostic(result, "V-051").rule_id, "V-051")
	assert_eq(cfg, before)

func test_resolve_produces_stack_operations_and_values_without_cfg_writeback() -> void:
	var modifiers: Array = [
		{"modifier_id": "m_add", "targets": ["params.damage"], "stack_rule": {"operation_profile": "add"}},
		{"modifier_id": "m_mul", "targets": ["params.damage"], "stack_rule": {"operation_profile": "mul"}},
	]
	var exposed: Dictionary = {"params.damage": {"min": 0.0, "max": 100.0, "base_value": 10.0, "set_conflict_note": ""}}
	var result: Dictionary = rule.resolve(modifiers, exposed, {}, {"base_values": {"params.damage": 10.0}})
	assert_true(result.ok)
	assert_eq(result.values["params.damage"], 30.0)
	assert_true(result.stack_operations.has("m_add"))
	assert_true(result.stack_operations.has("m_mul"))
	assert_eq(modifiers[0].stack_rule.operation_profile, "add")
