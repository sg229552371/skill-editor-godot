extends GutTest

const Guard = preload("res://skill_core/resolve/lock_guard.gd")

func _cfg(locked: Variant, overrides: Array) -> Dictionary:
	return {"bricks": [{"locked_params": locked}], "params": {"brick_overrides": overrides}}

func _override(values: Variant) -> Dictionary:
	return {"brick_index": 0, "values": values}

func _guard():
	var guard = Guard.new()
	assert_true(guard.configure_from_file(), guard.last_error)
	return guard

func _expect_lock(result: Dictionary, path: String) -> void:
	var matches: Array = []
	for diagnostic in result.diagnostics:
		if diagnostic.get("path") == path and diagnostic.get("rule_id") == "V-014":
			matches.append(diagnostic)
	assert_eq(matches.size(), 1, path)
	if matches.size() == 1:
		assert_eq(matches[0].code, "E-0009")
		assert_eq(matches[0].severity, 0, "CSV 阻止保存")
		assert_true(matches[0].message.contains(path))
	assert_false(result.ok)

func test_registered_lock_blocks_at_actual_nested_leaf() -> void:
	var result: Dictionary = _guard().check(_cfg({"hit_policy.max_hits": "命中限制"}, [_override({"hit_policy": {"max_hits": 3}})]))
	_expect_lock(result, "params.brick_overrides[0].values.hit_policy.max_hits")
	assert_eq(result.diagnostics.size(), 1)

func test_complete_path_and_segment_boundary_prevent_substring_matches() -> void:
	var guard = _guard()
	var cfg: Dictionary = _cfg({"params.max_generation": "预算保护"}, [_override({"max_hits": 4, "max_generation": 2})])
	var result: Dictionary = guard.check(cfg)
	_expect_lock(result, "params.brick_overrides[0].values.max_generation")
	assert_eq(result.diagnostics.size(), 1, "max_hits 不得因相似字段被锁")
	result = guard.check(_cfg({"hit_policy.max_hits": "整段命中"}, [_override({"other_hit_policy": {"max_hits": 1}, "hit_policy": {"max_hits": 1}})]))
	_expect_lock(result, "params.brick_overrides[0].values.hit_policy.max_hits")
	assert_eq(result.diagnostics.size(), 1, "多段锁不得仅匹配最后一个字段")

func test_explicit_params_wrapper_preserves_actual_input_leaf() -> void:
	var result: Dictionary = _guard().check(_cfg({"params.speed": "冻结速度"}, [_override({"params": {"speed": 2}})]))
	_expect_lock(result, "params.brick_overrides[0].values.params.speed")
	assert_eq(result.diagnostics.size(), 1)

func test_empty_lock_is_explicitly_valid_but_missing_and_malformed_fail_closed() -> void:
	var guard = _guard()
	var cfg: Dictionary = _cfg({}, [_override({"lifetime_ticks": 1})])
	var result: Dictionary = guard.check(cfg)
	assert_true(result.ok)
	assert_eq(result.diagnostics.size(), 0)
	cfg.bricks[0].erase("locked_params")
	result = guard.check(cfg)
	assert_false(result.ok)
	assert_eq(result.diagnostics.size(), 1)
	assert_eq(result.diagnostics[0].path, "bricks[0].locked_params")
	for invalid in [null, [], "locked", 1, {"speed": " "}, {"speed": 2}, {"speed": NAN}, {"speed": []}, {"speed": null}, {"speed": {}}, {"": "reason"}, {"a..b": "reason"}]:
		result = guard.check(_cfg(invalid, [_override({"speed": 1})]))
		assert_false(result.ok, str(invalid))
		assert_gt(result.diagnostics.size(), 0)
		assert_eq(result.diagnostics[0].code, "LOCK_GUARD_INVALID")

func test_multiple_bricks_and_overrides_keep_distinct_indices_and_paths() -> void:
	var cfg: Dictionary = {"bricks": [{"locked_params": {"speed": "A"}}, {"locked_params": {"speed": "B", "hit_policy.max_hits": "B"}}], "params": {"brick_overrides": [
		{"brick_index": 1, "values": {"speed": 3, "hit_policy": {"max_hits": 2}}},
		{"brick_index": 0, "values": {"speed": 4}},
	]}}
	var result: Dictionary = _guard().check(cfg)
	assert_eq(result.diagnostics.size(), 3)
	_expect_lock(result, "params.brick_overrides[0].values.speed")
	_expect_lock(result, "params.brick_overrides[0].values.hit_policy.max_hits")
	_expect_lock(result, "params.brick_overrides[1].values.speed")

func test_arrays_are_single_leaves_and_container_lock_covers_descendants() -> void:
	var result: Dictionary = _guard().check(_cfg({"shot_ticks": "冻结整个数组", "hit_policy": "冻结整个对象"}, [_override({"shot_ticks": [1, 2], "hit_policy": {"max_hits": 2}})]))
	_expect_lock(result, "params.brick_overrides[0].values.shot_ticks")
	_expect_lock(result, "params.brick_overrides[0].values.hit_policy.max_hits")
	assert_eq(result.diagnostics.size(), 2)

func test_invalid_values_and_key_types_do_not_raise_or_grant_permission() -> void:
	var guard = _guard()
	for value in [null, "4", NAN, INF, -INF, 4, 4.0, [], {}]:
		var result: Dictionary = guard.check(_cfg({"lifetime_ticks": "锁定"}, [_override({"lifetime_ticks": value})]))
		_expect_lock(result, "params.brick_overrides[0].values.lifetime_ticks")
	for key in [null, 1, 1.0, [], {}]:
		var values: Dictionary = {}
		values[key] = 4
		var result: Dictionary = guard.check(_cfg({"lifetime_ticks": "锁定"}, [_override(values)]))
		assert_false(result.ok)
		assert_gt(result.diagnostics.size(), 0)
		assert_eq(result.diagnostics[0].code, "LOCK_GUARD_INVALID")

func test_check_never_mutates_cfg_or_shares_mutable_diagnostics() -> void:
	var guard = _guard()
	var cfg: Dictionary = _cfg({"hit_policy.max_hits": "契约约束"}, [_override({"hit_policy": {"max_hits": [1, 2]}})])
	var before: Dictionary = cfg.duplicate(true)
	var result: Dictionary = guard.check(cfg)
	_expect_lock(result, "params.brick_overrides[0].values.hit_policy.max_hits")
	assert_eq(cfg, before)
	result.diagnostics[0]["path"] = "modified"
	assert_eq(cfg, before)

func test_lock_list_is_supplied_by_cards_not_hardcoded() -> void:
	var guard = _guard()
	var result: Dictionary = guard.check(_cfg({"custom.future_value": "动态登记"}, [_override({"custom": {"future_value": 1}})]))
	_expect_lock(result, "params.brick_overrides[0].values.custom.future_value")
	result = guard.check(_cfg({"other": "另一项"}, [_override({"custom": {"future_value": 1}})]))
	assert_true(result.ok)
	assert_eq(result.diagnostics.size(), 0)

func test_unconfigured_or_missing_production_assets_fail_explicitly() -> void:
	var guard = Guard.new()
	var result: Dictionary = guard.check(_cfg({}, [_override({"speed": 1})]))
	assert_false(result.ok)
	assert_eq(result.diagnostics.size(), 1)
	assert_false(guard.last_error.is_empty())
	assert_false(guard.configure_from_file("res://data/__missing_lock_meta__.json"))
	assert_false(guard.check(_cfg({}, [_override({"speed": 1})])).ok)
	assert_false(guard.configure_from_file("res://S_docs/collab/assets/schema_v0_1.yaml"))
