extends GutTest

const Registry = preload("res://skill_core/resolve/exposed_fields.gd")
const Diag = preload("res://skill_core/api/diagnostic.gd")

func _entry() -> Dictionary:
	return {"field_path": "params.damage", "permissions": ["mutate_number"], "min": 0, "max": 10, "live": false, "inheritable": false}

func _cfg(entry: Variant) -> Dictionary:
	return {"params": {"exposed_fields": [entry]}}

func _registry():
	var registry = Registry.new()
	assert_true(registry.configure(Registry.TRANSITION_METADATA), registry.last_error)
	return registry

func _expect(result: Dictionary, path: String, rule: String, severity: int = Diag.SEV_BLOCK) -> void:
	var found: Array = []
	for diagnostic in result.diagnostics:
		assert_true(diagnostic is Diag)
		if diagnostic.path == path and diagnostic.rule_id == rule:
			found.append(diagnostic)
	assert_eq(found.size(), 1, "%s at %s" % [rule, path])
	if found.size() == 1:
		assert_eq(found[0].severity, severity)
		assert_false(found[0].hint.is_empty())
	if severity == Diag.SEV_BLOCK:
		assert_false(result.ok)
		assert_eq(result.fields.size(), 0, "阻断时不发布部分能力表")
		assert_eq(result.sources.size(), 0)

func test_register_equal_bounds_and_source_paths_without_mutating_cfg() -> void:
	var registry = _registry()
	var entry: Dictionary = _entry()
	entry.min = 3
	entry.max = 3
	var cfg: Dictionary = _cfg(entry)
	var before: Dictionary = cfg.duplicate(true)
	var result: Dictionary = registry.register_fields(cfg)
	assert_true(result.ok)
	assert_eq(result.diagnostics.size(), 0)
	assert_eq(result.fields.size(), 1)
	assert_eq(result.fields["params.damage"].min, 3)
	assert_eq(result.sources["params.damage"].input_path, "params.exposed_fields[0]")
	assert_eq(result.sources["params.damage"].slots.min, "params.exposed_fields[0].min")
	assert_eq(cfg, before)
	result.fields["params.damage"].permissions.append("add_behavior")
	assert_eq(cfg, before, "登记结果不能与输入共享可变容器")

func test_each_required_slot_missing_is_located_without_defaulting() -> void:
	var registry = _registry()
	for field in ["field_path", "permissions", "min", "max", "live", "inheritable"]:
		var entry: Dictionary = _entry()
		entry.erase(field)
		var rule: String = "V-048" if field in ["min", "max"] else "V-020"
		var result: Dictionary = registry.register_fields(_cfg(entry))
		_expect(result, "params.exposed_fields[0]." + field, rule)
		assert_eq(result.diagnostics[0].actual, "未填写")

func test_field_types_and_permissions_reject_each_counterexample() -> void:
	var registry = _registry()
	var bad_values: Dictionary = {
		"field_path": [null, 5, false, "", "   ", [], {}],
		"permissions": [null, "mutate_number", [], ["unknown"], ["mutate_number", "mutate_number"], [1], [true]],
		"min": [null, "0", true, [], {}, NAN, INF, -INF],
		"max": [null, "10", false, [], {}, NAN, INF, -INF],
		"live": [null, "false", 0, 1, [], {}],
		"inheritable": [null, "true", 0, 1, [], {}],
		"set_conflict_note": [null, 1, false, [], {}],
	}
	var cases: int = 0
	for field in bad_values:
		for value in bad_values[field]:
			var entry: Dictionary = _entry()
			entry[field] = value
			var result: Dictionary = registry.register_fields(_cfg(entry))
			_expect(result, "params.exposed_fields[0]." + field, "V-048" if field in ["min", "max"] else "V-020")
			cases += 1
	assert_eq(cases, 47, "反例矩阵不能退化为空")

func test_inverted_bounds_report_both_slots_and_zero_negative_ranges_are_legal() -> void:
	var registry = _registry()
	var entry: Dictionary = _entry()
	entry.min = 11
	var result: Dictionary = registry.register_fields(_cfg(entry))
	_expect(result, "params.exposed_fields[0].min", "V-048")
	_expect(result, "params.exposed_fields[0].max", "V-048")
	for pair in [[0, 0], [-10, -1], [-2.5, 0.5]]:
		entry.min = pair[0]
		entry.max = pair[1]
		result = registry.register_fields(_cfg(entry))
		assert_true(result.ok)
		assert_eq(result.fields.size(), 1)

func test_optional_note_absence_and_distinct_permissions_are_legal() -> void:
	var registry = _registry()
	var entry: Dictionary = _entry()
	entry.permissions = ["mutate_number", "add_behavior", "mutate_live_instance"]
	entry.live = true
	entry.inheritable = true
	var result: Dictionary = registry.register_fields(_cfg(entry))
	assert_true(result.ok)
	assert_eq(result.fields.size(), 1)
	assert_eq(result.fields["params.damage"].permissions, entry.permissions)
	assert_false(result.fields["params.damage"].has("set_conflict_note"))

func test_permission_tiers_are_not_expanded() -> void:
	var registry = _registry()
	for permission in ["mutate_number", "add_behavior", "mutate_live_instance"]:
		var entry: Dictionary = _entry()
		entry.permissions = [permission]
		var result: Dictionary = registry.register_fields(_cfg(entry))
		assert_true(result.ok)
		assert_eq(result.fields.size(), 1)
		assert_eq(result.fields["params.damage"].permissions, [permission])

func test_multiple_sets_without_note_warn_but_allow_registration() -> void:
	var registry = _registry()
	for note in [null, "", "   "]:
		var entry: Dictionary = _entry()
		if note != null:
			entry.set_conflict_note = note
		var result: Dictionary = registry.register_fields(_cfg(entry), {"set_counts": {"params.damage": 2}})
		_expect(result, "params.exposed_fields[0].set_conflict_note", "V-050", Diag.SEV_WARN)
		assert_true(result.ok, "警告可保存")
		assert_eq(result.fields.size(), 1)
		assert_eq(result.diagnostics.size(), 1)
		assert_eq(result.diagnostics[0].code, "E-0027")
		assert_eq(result.notices.size(), 0, "真实文案模板应完整渲染")
	var entry: Dictionary = _entry()
	entry.set_conflict_note = "最后挂载者覆盖前者；伤害最终使用最后挂载值。"
	var result: Dictionary = registry.register_fields(_cfg(entry), {"set_counts": {"params.damage": 2}})
	assert_true(result.ok)
	assert_eq(result.diagnostics.size(), 0)
	for count in [0, 1]:
		result = registry.register_fields(_cfg(_entry()), {"set_counts": {"params.damage": count}})
		assert_true(result.ok)
		assert_eq(result.diagnostics.size(), 0)

func test_live_requires_both_item_application_and_target_live_permission() -> void:
	var registry = _registry()
	for item in [null, "mutate_number", "add_behavior", "mutate_live_instance"]:
		for target_live in [false, true]:
			for target_permission in ["mutate_number", "add_behavior", "mutate_live_instance"]:
				var entry: Dictionary = _entry()
				entry.live = target_live
				entry.permissions = [target_permission]
				var cfg: Dictionary = _cfg(entry)
				var before: Dictionary = cfg.duplicate(true)
				var result: Dictionary = registry.register_fields(cfg, {"live_requests": [{"field_path": "params.damage", "permission": item}]})
				var allowed: bool = item == "mutate_live_instance" and target_live and target_permission == "mutate_live_instance"
				assert_eq(result.ok, allowed)
				if item != "mutate_live_instance" or target_permission != "mutate_live_instance":
					_expect(result, "params.exposed_fields[0].permissions", "V-045")
				if not target_live:
					_expect(result, "params.exposed_fields[0].live", "V-045")
				if allowed:
					assert_eq(result.fields.size(), 1)
					assert_eq(result.diagnostics.size(), 0)
				assert_eq(cfg, before, "live 检查不能回写定义或历史")

func test_missing_item_application_has_precise_slot_and_real_message() -> void:
	var registry = _registry()
	var entry: Dictionary = _entry()
	entry.live = true
	entry.permissions = ["mutate_live_instance"]
	var result: Dictionary = registry.register_fields(_cfg(entry), {"live_requests": [{"field_path": "params.damage"}]})
	_expect(result, "params.exposed_fields[0].permissions", "V-045")
	assert_eq(result.notices.size(), 0)
	assert_true(result.diagnostics[0].hint.contains("物品申请"))

func test_unknown_aliases_and_duplicate_references_do_not_grant_capability() -> void:
	var registry = _registry()
	var entry: Dictionary = _entry()
	entry.name = "params.damage"
	entry.permission = "mutate_number"
	var result: Dictionary = registry.register_fields(_cfg(entry))
	_expect(result, "params.exposed_fields[0].name", "V-019")
	_expect(result, "params.exposed_fields[0].permission", "V-019")
	assert_eq(result.notices.size(), 0)
	result = registry.register_fields({"params": {"exposed_fields": [_entry(), _entry()]}})
	_expect(result, "params.exposed_fields[1].field_path", "V-043")

func test_non_object_entry_reports_required_slots_not_object_label() -> void:
	var registry = _registry()
	var result: Dictionary = registry.register_fields(_cfg("wrong"))
	assert_eq(result.diagnostics.size(), 6)
	for field in ["field_path", "permissions", "min", "max", "live", "inheritable"]:
		_expect(result, "params.exposed_fields[0]." + field, "V-048" if field in ["min", "max"] else "V-020")

func test_later_array_index_and_missing_null_empty_are_distinguished() -> void:
	var registry = _registry()
	var entry: Dictionary = _entry()
	entry.field_path = "params.speed"
	entry.erase("permissions")
	var result: Dictionary = registry.register_fields({"params": {"exposed_fields": [_entry(), entry]}})
	_expect(result, "params.exposed_fields[1].permissions", "V-020")
	assert_eq(result.diagnostics[0].actual, "未填写")
	entry.permissions = null
	result = registry.register_fields(_cfg(entry))
	assert_eq(result.diagnostics.size(), 1)
	assert_eq(result.diagnostics[0].actual, "null")
	entry.permissions = []
	result = registry.register_fields(_cfg(entry))
	assert_eq(result.diagnostics.size(), 1)
	assert_eq(result.diagnostics[0].actual, "空列表")

func test_missing_metadata_and_messages_fail_explicitly_and_invalidate_previous_setup() -> void:
	var registry = Registry.new()
	var result: Dictionary = registry.register_fields(_cfg(_entry()))
	assert_false(result.ok)
	assert_eq(result.diagnostics.size(), 1)
	assert_false(registry.last_error.is_empty())
	assert_true(registry.configure(Registry.TRANSITION_METADATA))
	assert_false(registry.configure_from_file("res://data/__t032_missing_metadata__.json"))
	assert_false(registry.last_error.is_empty())
	result = registry.register_fields(_cfg(_entry()))
	assert_false(result.ok)
	assert_eq(result.fields.size(), 0)
	assert_eq(result.diagnostics[0].code, "VALIDATION_METADATA_UNAVAILABLE")
	assert_false(registry.configure_from_file("res://S_docs/collab/assets/schema_v0_1.yaml"))
	assert_false(registry.configure(Registry.TRANSITION_METADATA, null, "res://data/__t032_missing_messages__.csv"))
	assert_false(registry.register_fields(_cfg(_entry())).ok)

func test_invalid_metadata_is_not_an_empty_capability_success() -> void:
	var registry = Registry.new()
	var invalid: Array = [{}]
	for key in ["input_path", "fields", "roles", "required", "permissions", "live_permission"]:
		var metadata: Dictionary = Registry.TRANSITION_METADATA.duplicate(true)
		metadata.erase(key)
		invalid.append(metadata)
	for permissions in [[], ["duplicate", "duplicate"], [1]]:
		var metadata: Dictionary = Registry.TRANSITION_METADATA.duplicate(true)
		metadata.permissions = permissions
		invalid.append(metadata)
	for metadata in invalid:
		assert_false(registry.configure(metadata))
		assert_false(registry.last_error.is_empty())
		var result: Dictionary = registry.register_fields(_cfg(_entry()))
		assert_false(result.ok)
		assert_eq(result.diagnostics.size(), 1)
	assert_eq(invalid.size(), 10)

func test_missing_message_code_falls_back_with_notice_and_same_severity() -> void:
	var registry = Registry.new()
	assert_true(registry.configure(Registry.TRANSITION_METADATA, {}))
	var entry: Dictionary = _entry()
	entry.erase("min")
	var result: Dictionary = registry.register_fields(_cfg(entry))
	_expect(result, "params.exposed_fields[0].min", "V-048")
	assert_eq(result.notices.size(), 1)
	assert_true(result.notices[0].contains("E-0026"))
	assert_true(result.diagnostics[0].hint.contains("缺失文案模板"))
	result = registry.register_fields(_cfg(_entry()), {"set_counts": {"params.damage": 2}})
	_expect(result, "params.exposed_fields[0].set_conflict_note", "V-050", Diag.SEV_WARN)
	assert_true(result.ok)
	assert_eq(result.notices.size(), 1)
	assert_true(result.notices[0].contains("E-0027"))

func test_unresolved_message_tokens_are_visible() -> void:
	var registry = Registry.new()
	assert_true(registry.configure(Registry.TRANSITION_METADATA, {"E-0026": "{field}: {detail} {unregistered}"}))
	var entry: Dictionary = _entry()
	entry.erase("max")
	var result: Dictionary = registry.register_fields(_cfg(entry))
	_expect(result, "params.exposed_fields[0].max", "V-048")
	assert_eq(result.notices.size(), 1)
	assert_true(result.diagnostics[0].hint.contains("文案元数据不完整"))

func test_injected_field_names_required_set_and_permissions_drive_registration() -> void:
	var registry = Registry.new()
	var metadata: Dictionary = Registry.TRANSITION_METADATA.duplicate(true)
	metadata.fields["target_ref"] = metadata.fields.field_path
	metadata.fields.erase("field_path")
	metadata.roles.reference = "target_ref"
	metadata.required[metadata.required.find("field_path")] = "target_ref"
	metadata.fields["extra_required"] = {"type": "boolean"}
	metadata.required.append("extra_required")
	metadata.permissions = ["numeric_custom", "live_custom"]
	metadata.live_permission = "live_custom"
	assert_true(registry.configure(metadata))
	var entry: Dictionary = _entry()
	entry.erase("field_path")
	entry.target_ref = "params.damage"
	entry.permissions = ["numeric_custom"]
	var result: Dictionary = registry.register_fields(_cfg(entry))
	_expect(result, "params.exposed_fields[0].extra_required", "V-020")
	entry.extra_required = true
	result = registry.register_fields(_cfg(entry))
	assert_true(result.ok)
	assert_eq(result.fields.size(), 1)
	assert_eq(result.sources["params.damage"].slots.target_ref, "params.exposed_fields[0].target_ref")
	entry.permissions = ["mutate_number"]
	result = registry.register_fields(_cfg(entry))
	_expect(result, "params.exposed_fields[0].permissions", "V-020")
	entry.permissions = ["live_custom"]
	entry.live = true
	# WorkBuddy 复核：上下文请求的目标键须跟随注入的 reference 角色名，不得写死 field_path
	result = registry.register_fields(_cfg(entry), {"live_requests": [{metadata.roles.reference: "params.damage", "permission": "live_custom"}]})
	assert_true(result.ok)
	assert_eq(result.fields.size(), 1)

func test_bad_context_fails_instead_of_silently_skipping_checks() -> void:
	var registry = _registry()
	var contexts: Array = [
		{"unknown_key": true}, {"set_counts": null}, {"live_requests": null},
		{"set_counts": {"params.damage": "2"}}, {"set_counts": {"params.damage": -1}},
		{"set_counts": {"params.damage": 1.5}}, {"set_counts": {"params.damage": NAN}},
		{"set_counts": {"params.unknown": 2}}, {"live_requests": [null]},
		{"live_requests": [{"field_path": "params.unknown"}]},
	]
	for context in contexts:
		var result: Dictionary = registry.register_fields(_cfg(_entry()), context)
		assert_false(result.ok)
		assert_eq(result.fields.size(), 0)
		assert_eq(result.diagnostics.size(), 1)
		assert_false(registry.last_error.is_empty())
	assert_eq(contexts.size(), 10)

func test_snapshot_history_and_behavior_are_never_modified_or_inherited() -> void:
	var registry = _registry()
	var entry: Dictionary = _entry()
	entry.permissions = ["mutate_live_instance"]
	entry.live = true
	entry.inheritable = true
	var cfg: Dictionary = _cfg(entry)
	cfg.snapshot = {"params": {"damage": 5}}
	cfg.history = [{"settled": 5}]
	cfg.params.parts = [{"type": "damage"}]
	var before: Dictionary = cfg.duplicate(true)
	var result: Dictionary = registry.register_fields(cfg, {"live_requests": [{"field_path": "params.damage", "permission": "mutate_live_instance"}]})
	assert_true(result.ok)
	assert_eq(result.fields.size(), 1)
	assert_eq(result.fields["params.damage"].permissions, ["mutate_live_instance"])
	assert_eq(cfg, before)
	assert_false(result.fields["params.damage"].has("snapshot"))

func test_empty_registration_is_legal_but_null_collection_is_not() -> void:
	var registry = _registry()
	for cfg in [{}, {"params": {}}, {"params": {"exposed_fields": []}}]:
		var result: Dictionary = registry.register_fields(cfg)
		assert_true(result.ok)
		assert_eq(result.fields.size(), 0)
		assert_eq(result.diagnostics.size(), 0)
	for value in [null, {}, "", 5]:
		var result: Dictionary = registry.register_fields({"params": {"exposed_fields": value}})
		_expect(result, "params.exposed_fields", "V-020")
	for value in [null, [], "wrong"]:
		var result: Dictionary = registry.register_fields({"params": value})
		_expect(result, "params", "V-020")

# ---- WorkBuddy 复核补测：生产元数据资产必须可用（与过渡表等价） ----

func _production_metadata() -> Dictionary:
	var file: FileAccess = FileAccess.open(Registry.METADATA_PATH, FileAccess.READ)
	assert_not_null(file, "生产元数据必须存在: " + Registry.METADATA_PATH)
	var parser: JSON = JSON.new()
	assert_eq(parser.parse(file.get_as_text()), OK, parser.get_error_message())
	file.close()
	assert_true(parser.data is Dictionary)
	return parser.data as Dictionary


func test_production_metadata_asset_matches_transition_table():
	var meta: Dictionary = _production_metadata()
	# 真源口径：四项必填、三档权限、live 权限名
	assert_eq(meta["required"], ["field_path", "permissions", "live", "inheritable"])
	assert_eq(meta["permissions"], ["mutate_number", "add_behavior", "mutate_live_instance"])
	assert_eq(meta["live_permission"], "mutate_live_instance")
	# 生产素材必须能直接装配，并与过渡表给出同一组字段/角色
	assert_eq(meta["fields"].keys(), Registry.TRANSITION_METADATA["fields"].keys())
	assert_eq(meta["roles"], Registry.TRANSITION_METADATA["roles"])
	assert_eq(meta["input_path"], Registry.TRANSITION_METADATA["input_path"])
	var registry = Registry.new()
	assert_true(registry.configure_from_file(Registry.METADATA_PATH, Registry.MESSAGES_PATH), registry.last_error)
	var result: Dictionary = registry.register_fields(_cfg(_entry()))
	assert_true(result.ok, str(result.diagnostics))
	assert_eq(result.fields.size(), 1)
	# 上下限缺失仍须阻止保存（V-048），用生产素材同样成立
	var no_bounds: Dictionary = _entry()
	no_bounds.erase("min")
	_expect(registry.register_fields(_cfg(no_bounds)), "params.exposed_fields[0].min", "V-048")
