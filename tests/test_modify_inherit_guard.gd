extends GutTest

const Guard = preload("res://skill_core/modify/inherit_guard.gd")
const Diag = preload("res://skill_core/api/diagnostic.gd")
const TARGETS_PATH: String = "res://data/protected_targets.json"

func _guard() -> Guard:
	var guard = Guard.new()
	assert_true(guard.configure_from_file(), guard.last_error)
	return guard

func _find(result: Dictionary, rule_id: String, path: String) -> Array:
	var found: Array = []
	for diagnostic in result.diagnostics:
		if diagnostic is Diag and diagnostic.rule_id == rule_id and diagnostic.path == path:
			found.append(diagnostic)
	return found

func test_each_v046_group_reports_actual_leaf_path() -> void:
	var guard: Guard = _guard()
	var cases: Dictionary = {
		"params.origin": "source_chain",
		"params.caster_id": "instance_identity",
		"params.snapshot": "snapshot",
		"params.history": "history",
	}
	for target in cases:
		var result: Dictionary = guard.check([target])
		assert_false(result.ok, target)
		assert_eq(_find(result, "V-046", "targets[0]").size(), 1, cases[target])
		assert_eq(result.diagnostics[0].actual, target)

func test_v047_protects_each_safety_bound() -> void:
	var guard: Guard = _guard()
	for target in ["params.max_generation", "params.max_chain_depth", "params.allow_self_chain"]:
		var result: Dictionary = guard.check([target])
		assert_false(result.ok, target)
		assert_eq(_find(result, "V-047", "targets[0]").size(), 1, target)

func test_segment_matching_does_not_confuse_similar_paths() -> void:
	var guard: Guard = _guard()
	for target in ["params.max_hits", "params.max_range", "params.history_count"]:
		var result: Dictionary = guard.check([target])
		assert_true(result.ok, target)
		assert_eq(result.diagnostics.size(), 0)

func test_one_modifier_reports_each_matching_protected_group() -> void:
	var guard: Guard = _guard()
	var modifier: Dictionary = {"inheritable": true, "targets": ["params.origin.max_generation"]}
	var before: Dictionary = modifier.duplicate(true)
	var result: Dictionary = guard.check(modifier)
	assert_false(result.ok)
	assert_eq(_find(result, "V-046", "targets[0]").size(), 1)
	assert_eq(_find(result, "V-047", "targets[0]").size(), 1)
	assert_eq(result.diagnostics.size(), 2)
	assert_eq(modifier, before, "守卫不得回写修饰器或 CFG")

func test_unprotected_target_is_a_real_happy_path_and_false_inheritable_is_skipped() -> void:
	var guard: Guard = _guard()
	var value: Dictionary = {"params": {"damage": 10}, "inherable_typo": true}
	var before: Dictionary = value.duplicate(true)
	var result: Dictionary = guard.check({"inheritable": true, "targets": ["params.damage"]})
	assert_true(result.ok)
	assert_eq(result.diagnostics.size(), 0)
	assert_eq(value, before)
	result = guard.check({"inheritable": false, "targets": ["params.origin"]})
	assert_true(result.ok)
	assert_eq(result.diagnostics.size(), 0)

func test_cfg_modifiers_are_checked_only_when_inheritable() -> void:
	var guard: Guard = _guard()
	var cfg: Dictionary = {"params": {"modifiers": [
		{"inheritable": false, "targets": ["params.origin"]},
		{"inheritable": true, "targets": ["params.snapshot"]},
	]}}
	var before: Dictionary = cfg.duplicate(true)
	var result: Dictionary = guard.check(cfg)
	assert_false(result.ok)
	assert_eq(_find(result, "V-046", "params.modifiers[1].targets[0]").size(), 1)
	assert_eq(result.diagnostics.size(), 1)
	assert_eq(cfg, before)

func test_invalid_target_paths_fail_explicitly() -> void:
	var guard: Guard = _guard()
	for target in ["", "params..origin", "params.origin[0]", "params.origin]", 1, null]:
		var result: Dictionary = guard.check([target])
		assert_false(result.ok, str(target))
		assert_gt(result.diagnostics.size(), 0)
		assert_eq(result.diagnostics[0].rule_id, "INHERIT_GUARD_SETUP")

func test_missing_or_malformed_protected_metadata_fails_configuration() -> void:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(TARGETS_PATH))
	assert_true(source is Dictionary)
	var cases: Array = []
	var missing: Dictionary = source.duplicate(true)
	missing.erase("groups")
	cases.append(missing)
	var empty: Dictionary = source.duplicate(true)
	empty["groups"] = {}
	cases.append(empty)
	var non_dict: Dictionary = source.duplicate(true)
	non_dict["groups"] = {"source_chain": "bad"}
	cases.append(non_dict)
	var no_mode: Dictionary = source.duplicate(true)
	no_mode.erase("match_mode")
	cases.append(no_mode)
	for metadata in cases:
		var guard = Guard.new()
		assert_false(guard.configure(metadata), "损坏受保护素材必须显式失败")
		assert_false(guard.last_error.is_empty())

func test_rule_severity_is_consumed_from_csv_not_overridden() -> void:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(TARGETS_PATH))
	assert_true(source is Dictionary)
	var metadata: Dictionary = source.duplicate(true)
	metadata.groups["warning_group"] = {"rule_ids": ["V-050"], "segments": ["warning_field"]}
	var guard = Guard.new()
	assert_true(guard.configure(metadata), guard.last_error)
	var result: Dictionary = guard.check(["params.warning_field"])
	assert_true(result.ok, "CSV 的警告不可被错误升级成阻止保存")
	assert_eq(result.diagnostics.size(), 1)
	assert_eq(result.diagnostics[0].severity, Diag.SEV_WARN)
	assert_eq(result.diagnostics[0].code, "E-0027")

func test_unconfigured_guard_fails_instead_of_zero_protection() -> void:
	var guard = Guard.new()
	var result: Dictionary = guard.check(["params.damage"])
	assert_false(result.ok)
	assert_eq(result.diagnostics.size(), 1)
	assert_eq(result.diagnostics[0].rule_id, "INHERIT_GUARD_SETUP")
