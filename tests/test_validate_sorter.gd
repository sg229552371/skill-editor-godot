extends GutTest

const Sorter = preload("res://skill_core/validate/diagnostic_sorter.gd")
const Diag = preload("res://skill_core/api/diagnostic.gd")

func _meta() -> Dictionary:
	return Sorter.load_metadata()

func _sorter() -> Sorter:
	var sorter: Sorter = Sorter.new()
	assert_true(sorter.configure(_meta()), sorter.last_error)
	return sorter

func _issue(rule_id: String, path: String, severity: int = 0, actual: String = "bad", code: String = "E-0001", expected: String = "good") -> Dictionary:
	return {"rule_id": rule_id, "code": code, "path": path, "actual": actual,
		"expected": expected, "severity": severity, "hint": "explanation"}

func _ids(result: Dictionary) -> Array:
	var ids: Array = []
	for diagnostic in result["diagnostics"]:
		if diagnostic is Dictionary:
			ids.append(diagnostic["rule_id"])
		else:
			ids.append(diagnostic.rule_id)
	return ids

func test_severity_order_is_injected_and_out_of_order_severity_fails() -> void:
	var sorter: Sorter = _sorter()
	var meta: Dictionary = _meta()
	var order: Array = meta["severity_order"]
	var items: Array = [_issue("hint", "schema_version", int(order[2])),
		_issue("warn", "runtime_hints", int(order[1])), _issue("block", "presentation", int(order[0]))]
	var result: Dictionary = sorter.sort_diagnostics(items)
	assert_true(result["ok"])
	assert_eq(_ids(result), ["block", "warn", "hint"])
	var unknown: Dictionary = sorter.sort_diagnostics([_issue("invalid", "meta", 17)])
	assert_false(unknown["ok"])
	assert_true(unknown["error"].contains("严重度"))
	assert_eq(unknown["diagnostics"], [])
	meta["severity_order"].reverse()
	assert_true(sorter.configure(meta), sorter.last_error)
	assert_eq(_ids(sorter.sort_diagnostics(items)), ["hint", "warn", "block"])

func test_field_order_and_nested_indices_are_injected() -> void:
	var meta: Dictionary = _meta()
	var fields: Array = meta["field_order"]
	assert_eq(fields.size(), 7)
	var sorter: Sorter = _sorter()
	var items: Array = [_issue("deep", "bricks[2].parts[0]"),
		_issue("after", str(fields[6])), _issue("two", "bricks[2]"),
		_issue("first", str(fields[0])), _issue("one", "bricks[1]"),
		_issue("params", str(fields[4]))]
	var result: Dictionary = sorter.sort_diagnostics(items)
	assert_true(result["ok"])
	assert_eq(_ids(result), ["first", "one", "two", "deep", "params", "after"])
	fields.reverse()
	assert_true(sorter.configure(meta), sorter.last_error)
	assert_eq(_ids(sorter.sort_diagnostics([_issue("left", str(fields[6])),
		_issue("right", str(fields[0]))])), ["right", "left"])
	var unknown: Dictionary = sorter.sort_diagnostics([_issue("unknown", "undocumented.leaf")])
	assert_false(unknown["ok"])
	assert_true(unknown["error"].contains("首段"))

func test_rule_id_breaks_all_equal_primary_keys() -> void:
	var sorter: Sorter = _sorter()
	var result: Dictionary = sorter.sort_diagnostics([_issue("V-009", "params.parts[2]"),
		_issue("V-002", "params.parts[2]"), _issue("V-004", "params.parts[2]")])
	assert_true(result["ok"])
	assert_eq(_ids(result), ["V-002", "V-004", "V-009"])

func test_shuffled_arrivals_have_deterministic_order() -> void:
	var sorter: Sorter = _sorter()
	var items: Array = [_issue("V-009", "params.parts[2]"),
		_issue("V-004", "bricks[1]"), _issue("V-002", "params.parts[2]"),
		_issue("V-007", "meta.title", 1), _issue("V-006", "bricks[0]")]
	var expected: Array = ["V-006", "V-004", "V-002", "V-009", "V-007"]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 14014
	for attempt in range(30):
		var arrival: Array = items.duplicate()
		for index in range(arrival.size() - 1, 0, -1):
			var other: int = rng.randi_range(0, index)
			var temporary: Variant = arrival[index]
			arrival[index] = arrival[other]
			arrival[other] = temporary
		var result: Dictionary = sorter.sort_diagnostics(arrival)
		assert_true(result["ok"], "shuffle %d: %s" % [attempt, result["error"]])
		assert_eq(_ids(result), expected, "shuffle %d" % attempt)

func test_dedupe_uses_injected_five_fields_and_keeps_first() -> void:
	var sorter: Sorter = _sorter()
	var first: Dictionary = _issue("V-001", "bricks[0]", 0, "x")
	var duplicate: Dictionary = first.duplicate(true)
	duplicate["hint"] = "later explanation"
	var other_path: Dictionary = _issue("V-001", "bricks[1]", 0, "x")
	var other_actual: Dictionary = _issue("V-001", "bricks[0]", 0, "y")
	var other_code: Dictionary = _issue("V-001", "bricks[0]", 0, "x", "E-0002")
	var other_expected: Dictionary = _issue("V-001", "bricks[0]", 0, "x", "E-0001", "different")
	var other_rule: Dictionary = _issue("V-002", "bricks[0]", 0, "x")
	var result: Dictionary = sorter.sort_diagnostics([first, duplicate, other_path, other_actual, other_code, other_expected, other_rule])
	assert_true(result["ok"])
	assert_eq(result["removed"], 1)
	assert_eq(result["duplicates"].size(), 1)
	assert_same(result["duplicates"][0], duplicate)
	assert_eq(result["diagnostics"].size(), 6)
	assert_same(result["diagnostics"][0], first)
	var changed: Dictionary = _meta()
	changed["dedupe_keys"].reverse()
	assert_true(sorter.configure(changed), sorter.last_error)
	var repeated: Dictionary = sorter.sort_diagnostics([first, duplicate, other_path])
	assert_eq(repeated["removed"], 1)
	assert_eq(repeated["diagnostics"].size(), 2)

func test_invalid_diagnostics_fail_without_runtime_error() -> void:
	var sorter: Sorter = _sorter()
	var bad_entries: Array = [null, {}, _issue("V-001", "meta"),
		_issue("V-001", "meta[NaN]"), _issue("V-001", "bricks[1e309]"),
		_issue("V-001", "bricks[-1]")]
	bad_entries[2]["actual"] = null
	for bad in bad_entries:
		var result: Dictionary = sorter.sort_diagnostics([bad])
		assert_false(result["ok"], "invalid input must be rejected")
		assert_false(result["error"].is_empty())
		assert_eq(result["diagnostics"], [])
	var container: Dictionary = _issue("V-001", "params")
	container["rule_id"] = ["V-001"]
	assert_false(sorter.sort_diagnostics([container])["ok"])
	var unknown_path: Dictionary = sorter.sort_diagnostics([_issue("V-001", "params.parts[18446744073709551616]")])
	assert_false(unknown_path["ok"])
	var bad_severity: Dictionary = _issue("V-001", "meta")
	bad_severity["severity"] = INF
	assert_false(sorter.sort_diagnostics([bad_severity])["ok"])
	bad_severity["severity"] = null
	assert_false(sorter.sort_diagnostics([bad_severity])["ok"])

func test_input_array_is_unchanged_and_result_is_new_shallow_array() -> void:
	var sorter: Sorter = _sorter()
	var one: Dictionary = _issue("V-003", "params")
	var two: Dictionary = _issue("V-002", "meta")
	var input: Array = [one, two]
	var result: Dictionary = sorter.sort_diagnostics(input)
	assert_true(result["ok"])
	assert_same(input[0], one)
	assert_same(input[1], two)
	assert_eq(_ids(result), ["V-002", "V-003"])
	assert_same(result["diagnostics"][0], two)
	result["diagnostics"].clear()
	assert_eq(input.size(), 2)

func test_empty_single_all_same_severity_and_stable_exact_ties() -> void:
	var sorter: Sorter = _sorter()
	var empty: Dictionary = sorter.sort_diagnostics([])
	assert_true(empty["ok"])
	assert_eq(empty["diagnostics"].size(), 0)
	assert_eq(empty["removed"], 0)
	assert_eq(empty["duplicates"].size(), 0)
	var instance: Diag = Diag.new()
	instance.rule_id = "V-001"
	instance.code = "E-0001"
	instance.path = "meta.title"
	instance.actual = "bad"
	instance.expected = "good"
	instance.severity = int(_meta()["severity_order"][0])
	var single: Dictionary = sorter.sort_diagnostics([instance])
	assert_true(single["ok"])
	assert_eq(single["diagnostics"].size(), 1)
	assert_same(single["diagnostics"][0], instance)
	var same: Dictionary = sorter.sort_diagnostics([_issue("V-010", "params.parts[3]"),
		_issue("V-008", "params.parts[1]"), _issue("V-009", "params.parts[2]")])
	assert_eq(_ids(same), ["V-008", "V-009", "V-010"])
	var tie1: Dictionary = _issue("V-001", "params.first")
	var tie2: Dictionary = _issue("V-001", "params.second")
	var tied: Dictionary = sorter.sort_diagnostics([tie2, tie1])
	assert_true(tied["ok"])
	assert_same(tied["diagnostics"][0], tie2)
	assert_same(tied["diagnostics"][1], tie1)

func test_invalid_metadata_fails_even_when_input_is_empty() -> void:
	var sorter: Sorter = Sorter.new()
	assert_false(sorter.configure({}))
	assert_false(sorter.sort_diagnostics([])["ok"])
	var invalid: Dictionary = _meta()
	invalid["severity_order"] = []
	assert_false(sorter.configure(invalid))
	assert_false(sorter.sort_diagnostics([])["ok"])
	invalid = _meta()
	invalid["field_order"] = [null]
	assert_false(sorter.configure(invalid))
	invalid = _meta()
	invalid["dedupe_keys"] = ["rule_id", "rule_id"]
	assert_false(sorter.configure(invalid))
	assert_true(sorter.configure(_meta()), sorter.last_error)
	assert_true(sorter.sort_diagnostics([])["ok"])
