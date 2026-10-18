extends GutTest

const EngineScript = preload("res://skill_core/modify/modifier_engine.gd")
const Diag = preload("res://skill_core/api/diagnostic.gd")
const EXPOSURE_PATH: String = "res://data/exposed_fields_meta.json"

# 规格驱动的显式注入夹具，不是生产默认表；正式策略由 WorkBuddy 抽取部署。
func _policy() -> Dictionary:
	return {
		"input_path": "params.modifiers",
		"tags_path": "meta.tags",
		"fields": {"id": "modifier_id", "permission": "permission", "scope": "scope", "inheritable": "inheritable", "targets": "targets", "stack": "stack_rule", "tags": "tag_filter", "profile": "operation_profile", "operands": "operands", "note": "note"},
		"permission_roles": {"number": "mutate_number", "behavior": "add_behavior", "live": "mutate_live_instance"},
		"scope_roles": {"own": "own_skill", "tagged": "tagged"},
		"source_permissions": {"crystal": ["mutate_number"], "item": ["mutate_number", "add_behavior", "mutate_live_instance"]},
		"protected_segments": {
			"V-046": ["source_chain", "origin", "instance_id", "snapshot", "history", "settlement_results"],
			"V-047": ["max_generation", "max_chain_depth", "allow_self_chain"],
		},
		"operations": {
			"number_set": {"kind": "number", "is_set": true},
			"number_add": {"kind": "number", "is_set": false},
			"attach_terminal": {"kind": "behavior", "is_set": false},
		},
	}

func _exposure() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(EXPOSURE_PATH))
	assert_true(data is Dictionary, "必须读取已部署暴露元数据，不使用过渡表")
	return data if data is Dictionary else {}

func _engine(messages: Variant = null):
	var engine = EngineScript.new()
	assert_true(engine.configure(_policy(), _exposure(), messages), engine.last_error)
	return engine

func _cfg(permission: String = "mutate_number", target: String = "params.damage") -> Dictionary:
	return {
		"meta": {"tags": ["fire"]},
		"params": {
			"damage": 10,
			"exposed_fields": [{"field_path": target, "permissions": [permission], "min": 0, "max": 100, "live": true, "inheritable": false}],
			"modifiers": [{"modifier_id": "test_modifier", "permission": permission, "scope": "own_skill", "inheritable": false, "targets": [target], "stack_rule": {"operation_profile": "number_set", "operands": [20]}}],
		},
	}

func _context() -> Dictionary:
	return {"source_kind": "item", "registered_tags": ["fire", "ice"]}

func _expect(result: Dictionary, rule: String, path: String, severity: int = Diag.SEV_BLOCK) -> void:
	var found: Array = []
	assert_gt(result.diagnostics.size(), 0, "反例必须真的产生诊断")
	for diagnostic in result.diagnostics:
		assert_true(diagnostic is Diag)
		if diagnostic.rule_id == rule and diagnostic.path == path:
			found.append(diagnostic)
	assert_eq(found.size(), 1, "%s at %s" % [rule, path])
	if found.size() == 1:
		assert_eq(found[0].severity, severity)
		assert_false(found[0].hint.is_empty())
	if severity == Diag.SEV_BLOCK:
		assert_false(result.ok)
		assert_eq(result.approved.size(), 0, "阻断时不能发布部分授权")

func test_three_permissions_are_independent_without_implicit_lower_tiers() -> void:
	var engine = _engine()
	var cases: int = 0
	for requested in ["mutate_number", "add_behavior", "mutate_live_instance"]:
		for opened in ["mutate_number", "add_behavior", "mutate_live_instance"]:
			var cfg: Dictionary = _cfg(requested)
			cfg.params.exposed_fields[0].permissions = [opened]
			if requested == "add_behavior":
				cfg.params.damage = null
				cfg.params.modifiers[0].stack_rule.operation_profile = "attach_terminal"
			var result: Dictionary = engine.authorize(cfg, cfg, _context())
			assert_eq(result.ok, requested == opened, requested + " vs " + opened)
			if requested == opened:
				assert_eq(result.approved.size(), 1)
			else:
				_expect(result, "V-045" if requested == "mutate_live_instance" else "V-043", "params.exposed_fields[0].permissions" if requested == "mutate_live_instance" else "params.modifiers[0].targets[0]")
			cases += 1
	assert_eq(cases, 9)

func test_crystal_only_requests_number_and_reports_actual_modifier_index() -> void:
	var engine = _engine()
	for permission in ["mutate_number", "add_behavior", "mutate_live_instance"]:
		var cfg: Dictionary = _cfg(permission)
		if permission == "add_behavior":
			cfg.params.damage = null
			cfg.params.modifiers[0].stack_rule.operation_profile = "attach_terminal"
		var second: Dictionary = cfg.params.modifiers[0].duplicate(true)
		second.modifier_id = "second_modifier"
		cfg.params.modifiers.append(second)
		var result: Dictionary = engine.authorize(cfg, cfg, {"source_kind": "crystal"})
		if permission == "mutate_number":
			assert_true(result.ok)
			assert_eq(result.approved.size(), 2)
		else:
			_expect(result, "V-041", "params.modifiers[0].permission")
			_expect(result, "V-041", "params.modifiers[1].permission")

func test_live_missing_item_application_and_target_exposure_have_distinct_slots() -> void:
	var engine = _engine()
	var cfg: Dictionary = _cfg("mutate_live_instance")
	cfg.params.modifiers[0].permission = "mutate_number"
	var context: Dictionary = _context()
	context.live = true
	var result: Dictionary = engine.authorize(cfg, cfg, context)
	_expect(result, "V-045", "params.modifiers[0].permission")
	assert_eq(result.diagnostics.size(), 1, "只缺物品申请，不能归咎于目标")
	cfg.params.modifiers[0].permission = "mutate_live_instance"
	cfg.params.exposed_fields[0].live = false
	result = engine.authorize(cfg, cfg, context)
	_expect(result, "V-045", "params.exposed_fields[0].live")
	assert_eq(result.diagnostics.size(), 1)
	cfg.params.modifiers[0].erase("permission")
	result = engine.authorize(cfg, cfg, context)
	_expect(result, "V-045", "params.modifiers[0].permission")
	_expect(result, "V-045", "params.exposed_fields[0].live")

func test_each_protected_category_rejects_every_permission_even_when_exposed() -> void:
	var engine = _engine()
	# 来源链、身份、快照、历史逐条独立；不是仅测试未知/未暴露目标。
	var protected: Dictionary = {"source_chain": "V-046", "origin": "V-046", "instance_id": "V-046", "snapshot": "V-046", "history": "V-046", "settlement_results": "V-046", "max_generation": "V-047", "max_chain_depth": "V-047", "allow_self_chain": "V-047"}
	var cases: int = 0
	for field in protected:
		for permission in ["mutate_number", "add_behavior", "mutate_live_instance"]:
			for target in [field, "params." + field, "bricks[1].params." + field + ".value"]:
				var cfg: Dictionary = _cfg(permission, target)
				var result: Dictionary = engine.authorize(cfg, cfg, _context())
				_expect(result, protected[field], "params.modifiers[0].targets[0]")
				cases += 1
	assert_eq(cases, 81)

func test_live_changes_current_value_but_preserves_every_snapshot_and_history_leaf() -> void:
	var engine = _engine()
	var cfg: Dictionary = _cfg("mutate_live_instance")
	var cfg_before: Dictionary = cfg.duplicate(true)
	var instance: Dictionary = {"params": {"damage": 10, "speed": 5}, "instance_id": 73, "origin": {"root": 2}, "snapshot": {"params": {"damage": 10, "speed": 5}, "parts": [{"amount": 10}]}, "history": [{"tick": 1, "damage": 10}], "settlement_results": [10]}
	var before: Dictionary = instance.duplicate(true)
	var result: Dictionary = engine.apply_live(cfg, instance, {"params.damage": 25}, _context())
	assert_true(result.ok)
	assert_eq(result.values.params.damage, 25, "必须真的修改当前值，否则快照相等会恒真")
	assert_eq(result.applied.size(), 1)
	assert_eq(result.values.snapshot.params.damage, 10)
	assert_eq(result.values.snapshot.params.speed, 5)
	assert_eq(result.values.snapshot.parts[0].amount, 10)
	assert_eq(result.values.snapshot, before.snapshot, "完整结构逐字段相等")
	assert_eq(result.values.history, before.history)
	assert_eq(result.values.settlement_results, before.settlement_results)
	assert_eq(result.values.origin, before.origin)
	assert_eq(result.values.instance_id, 73)
	assert_eq(instance, before, "输入实例也不就地写入")
	assert_eq(cfg, cfg_before, "不回写 CFG")
	result.values.snapshot.parts[0].amount = 999
	result.values.history[0].damage = 999
	assert_eq(instance, before, "返回数据不与输入共享可变容器")

func test_live_cannot_add_behavior_and_behavior_cannot_replace_live_permission() -> void:
	var engine = _engine()
	var cfg: Dictionary = _cfg("mutate_live_instance", "params.terminal_zone_behavior")
	cfg.params.modifiers[0].stack_rule.operation_profile = "attach_terminal"
	var result: Dictionary = engine.apply_live(cfg, {"params": {"damage": 10}}, {"params.terminal_zone_behavior": {"radius": 3}}, _context())
	_expect(result, "V-045", "params.modifiers[0].targets[0]")
	assert_eq(result.applied.size(), 0)
	assert_eq(result.values, {})
	cfg = _cfg("add_behavior", "params.terminal_zone_behavior")
	cfg.params.modifiers[0].stack_rule.operation_profile = "attach_terminal"
	result = engine.apply_live(cfg, {"params": {"damage": 10}}, {"params.terminal_zone_behavior": {"radius": 3}}, _context())
	_expect(result, "V-045", "params.modifiers[0].permission")
	assert_eq(result.applied.size(), 0)
	# 同一新增行为在装配态可授权，但不会执行或改变结算顺序。
	result = engine.authorize(cfg, cfg, _context())
	assert_true(result.ok)
	assert_eq(result.approved.size(), 1)
	assert_false(cfg.params.has("terminal_zone_behavior"))

func test_number_never_creates_missing_behavior_and_behavior_never_reorders_existing_content() -> void:
	var engine = _engine()
	var cfg: Dictionary = _cfg("mutate_number", "params.terminal_zone_behavior")
	var result: Dictionary = engine.authorize(cfg, cfg, _context())
	_expect(result, "V-044", "params.modifiers[0].targets[0]")
	cfg = _cfg("add_behavior", "params.parts")
	cfg.params.parts = [{"amount": 3}, {"amount": 5}]
	cfg.params.modifiers[0].stack_rule.operation_profile = "attach_terminal"
	var before: Dictionary = cfg.duplicate(true)
	result = engine.authorize(cfg, cfg, _context())
	_expect(result, "V-043", "params.modifiers[0].targets[0]")
	assert_eq(cfg, before)
	cfg = _cfg("mutate_number")
	cfg.params.modifiers[0].stack_rule.operation_profile = "attach_terminal"
	result = engine.authorize(cfg, cfg, _context())
	_expect(result, "V-044", "params.modifiers[0].targets[0]")

func test_set_conflict_is_a_registry_warning_not_silent_or_blocking() -> void:
	var engine = _engine()
	var cfg: Dictionary = _cfg()
	var second: Dictionary = cfg.params.modifiers[0].duplicate(true)
	second.modifier_id = "second_modifier"
	cfg.params.modifiers.append(second)
	var before: Dictionary = cfg.duplicate(true)
	var result: Dictionary = engine.authorize(cfg, cfg, _context())
	_expect(result, "V-050", "params.exposed_fields[0].set_conflict_note", Diag.SEV_WARN)
	assert_true(result.ok)
	assert_eq(result.approved.size(), 2)
	assert_eq(result.diagnostics.size(), 1)
	assert_eq(result.diagnostics[0].code, "E-0027")
	assert_eq(result.notices.size(), 0)
	assert_eq(cfg, before)
	cfg.params.exposed_fields[0].set_conflict_note = "最后挂载者覆盖"
	result = engine.authorize(cfg, cfg, _context())
	assert_true(result.ok)
	assert_eq(result.diagnostics.size(), 0)
	cfg.params.exposed_fields[0].erase("set_conflict_note")
	cfg.params.modifiers[1].stack_rule.operation_profile = "number_add"
	result = engine.authorize(cfg, cfg, _context())
	assert_true(result.ok)
	assert_eq(result.diagnostics.size(), 0, "不是两个 set 就不触发 V-050")

func test_inheritable_requires_boolean_and_never_implicitly_copies_everything() -> void:
	var engine = _engine()
	var cases: int = 0
	for value in [null, 0, 1, "true", "all", [], {}]:
		var cfg: Dictionary = _cfg()
		cfg.params.modifiers[0].inheritable = value
		_expect(engine.authorize(cfg, cfg, _context()), "V-052", "params.modifiers[0].inheritable")
		cases += 1
	assert_eq(cases, 7)
	var cfg: Dictionary = _cfg()
	cfg.params.modifiers[0].erase("inheritable")
	_expect(engine.authorize(cfg, cfg, _context()), "V-052", "params.modifiers[0].inheritable")
	for flag in [false, true]:
		cfg.params.modifiers[0].inheritable = flag
		var result: Dictionary = engine.authorize(cfg, cfg, _context())
		assert_true(result.ok)
		assert_eq(result.approved.size(), 1)
		assert_eq(result.approved[0].inheritable, flag, "仅保留显式声明，不实现自动继承")
	var context: Dictionary = _context()
	context.inherit_all = true
	_expect(engine.authorize(cfg, cfg, context), "V-052", "params.modifiers[0].inheritable")

func test_tagged_requires_legal_matching_tags_and_real_tag_slot() -> void:
	var engine = _engine()
	var cfg: Dictionary = _cfg()
	cfg.params.modifiers[0].scope = "tagged"
	for tags in [null, [], ["unknown"], ["ice"], ["fire", "fire"], ["fire", "unknown"]]:
		cfg.params.modifiers[0].tag_filter = tags
		_expect(engine.authorize(cfg, cfg, _context()), "V-042", "params.modifiers[0].scope")
	cfg.params.modifiers[0].tag_filter = ["fire"]
	var result: Dictionary = engine.authorize(cfg, cfg, _context())
	assert_true(result.ok)
	assert_eq(result.approved.size(), 1)
	cfg.meta.tags.append("unknown")
	_expect(engine.authorize(cfg, cfg, _context()), "V-042", "meta.tags[1]")
	cfg.meta.tags = ["fire"]
	_expect(engine.authorize(cfg, cfg, {"source_kind": "item"}), "V-042", "params.modifiers[0].scope")
	cfg.params.modifiers[0].scope = "everything"
	_expect(engine.authorize(cfg, cfg, _context()), "V-042", "params.modifiers[0].scope")

func test_unexposed_ambiguous_and_duplicate_targets_are_rejected() -> void:
	var engine = _engine()
	for target in ["params.speed", "damage", "params..damage", "params.damage]", "params.damage[01]", "params.damage[-1]", "params.damage; run()", "", null, 1]:
		var cfg: Dictionary = _cfg()
		cfg.params.modifiers[0].targets = [target]
		_expect(engine.authorize(cfg, cfg, _context()), "V-043", "params.modifiers[0].targets[0]")
	var cfg: Dictionary = _cfg()
	cfg.params.modifiers[0].targets.append("params.damage")
	_expect(engine.authorize(cfg, cfg, _context()), "V-043", "params.modifiers[0].targets[1]")

func test_unknown_or_multiple_permissions_never_default_to_number() -> void:
	var engine = _engine()
	for permission in [null, "unknown", ["mutate_number", "add_behavior"], [], 1]:
		var cfg: Dictionary = _cfg()
		cfg.params.modifiers[0].permission = permission
		_expect(engine.authorize(cfg, cfg, _context()), "V-040", "params.modifiers[0].permission")

func test_relic_overrides_never_grant_live_permission() -> void:
	var engine = _engine()
	var cfg: Dictionary = _cfg("mutate_number")
	cfg.bricks = [{"relic_params": {"params.damage": "可改", "mutate_live_instance": "可改"}}]
	var result: Dictionary = engine.apply_live(cfg, {"params": {"damage": 10}}, {"params.damage": 12}, _context())
	_expect(result, "V-045", "params.modifiers[0].permission")
	_expect(result, "V-045", "params.exposed_fields[0].permissions")
	assert_eq(result.applied.size(), 0)

func test_live_candidates_are_numeric_bounded_and_atomic() -> void:
	var engine = _engine()
	var cfg: Dictionary = _cfg("mutate_live_instance")
	var instance: Dictionary = {"params": {"damage": 10}, "snapshot": {"damage": 10}}
	var before: Dictionary = instance.duplicate(true)
	for value in [null, true, "15", {"behavior": true}, [], INF, NAN, 2.5, -1, 101]:
		var result: Dictionary = engine.apply_live(cfg, instance, {"params.damage": value}, _context())
		_expect(result, "V-051", "params.modifiers[0].targets[0]")
		assert_eq(result.values, {})
		assert_eq(result.applied.size(), 0)
		assert_eq(instance, before)
	for value in [0, 100]:
		var result: Dictionary = engine.apply_live(cfg, instance, {"params.damage": value}, _context())
		assert_true(result.ok)
		assert_eq(result.values.params.damage, value)
		assert_eq(result.applied.size(), 1)
	var result: Dictionary = engine.apply_live(cfg, instance, {"params.damage": 20, "snapshot.damage": 50}, _context())
	_expect(result, "V-046", "live_changes[\"snapshot.damage\"]")
	assert_eq(result.values, {})
	assert_eq(result.applied.size(), 0)
	assert_eq(instance, before, "一个候选非法就不发布任何写入")
	result = engine.apply_live(cfg, instance, {}, _context())
	_expect(result, "V-043", "params.modifiers")
	result = engine.apply_live(cfg, instance, {"params.speed": 20}, _context())
	_expect(result, "V-043", "live_changes[\"params.speed\"]")

func test_live_integer_conversion_cannot_overflow_even_with_wide_exposure() -> void:
	var engine = _engine()
	var cfg: Dictionary = _cfg("mutate_live_instance")
	cfg.params.exposed_fields[0].min = -1.0e20
	cfg.params.exposed_fields[0].max = 1.0e20
	for value in [1.0e19, -1.0e19]:
		var result: Dictionary = engine.apply_live(cfg, {"params": {"damage": 10}}, {"params.damage": value}, _context())
		_expect(result, "V-051", "params.modifiers[0].targets[0]")
		assert_eq(result.values, {})

func test_indexed_existing_paths_are_changed_without_touching_neighbor_or_snapshot() -> void:
	var engine = _engine()
	var cfg: Dictionary = _cfg("mutate_live_instance", "params.parts[1].damage")
	var instance: Dictionary = {"params": {"parts": [{"damage": 3}, {"damage": 7}]}, "snapshot": {"parts": [{"damage": 3}, {"damage": 7}]}}
	var result: Dictionary = engine.apply_live(cfg, instance, {"params.parts[1].damage": 9}, _context())
	assert_true(result.ok)
	assert_eq(result.values.params.parts[0].damage, 3)
	assert_eq(result.values.params.parts[1].damage, 9)
	assert_eq(result.values.snapshot.parts[1].damage, 7)
	assert_eq(instance.params.parts[1].damage, 7)

func test_registry_failure_is_propagated_and_does_not_publish_partial_authority() -> void:
	var engine = _engine()
	var cfg: Dictionary = _cfg()
	cfg.params.exposed_fields[0].erase("min")
	_expect(engine.authorize(cfg, cfg, _context()), "V-048", "params.exposed_fields[0].min")
	cfg = _cfg()
	var second: Dictionary = cfg.params.modifiers[0].duplicate(true)
	second.modifier_id = "second_modifier"
	second.targets = ["params.not_exposed"]
	cfg.params.modifiers.append(second)
	_expect(engine.authorize(cfg, cfg, _context()), "V-043", "params.modifiers[1].targets[0]")

func test_operation_profiles_are_registered_objects_not_executable_expressions() -> void:
	var engine = _engine()
	for stack in ["set", null, "damage *= 5"]:
		var cfg: Dictionary = _cfg()
		cfg.params.modifiers[0].stack_rule = stack
		_expect(engine.authorize(cfg, cfg, _context()), "V-049", "params.modifiers[0].stack_rule")
	var cfg: Dictionary = _cfg()
	cfg.params.modifiers[0].stack_rule.operation_profile = "eval(anything)"
	_expect(engine.authorize(cfg, cfg, _context()), "V-049", "params.modifiers[0].stack_rule.operation_profile")
	cfg = _cfg()
	cfg.params.modifiers[0].operation_profile = "attach_terminal"
	_expect(engine.authorize(cfg, cfg, _context()), "V-049", "params.modifiers[0].operation_profile")

func test_messages_use_csv_templates_and_explicit_fallback_notices() -> void:
	var engine = _engine()
	var cfg: Dictionary = _cfg("mutate_live_instance")
	cfg.params.exposed_fields[0].live = false
	var result: Dictionary = engine.authorize(cfg, cfg, _context())
	_expect(result, "V-045", "params.exposed_fields[0].live")
	assert_eq(result.diagnostics[0].code, "E-0025")
	assert_true(result.diagnostics[0].hint.contains("双向许可"))
	assert_eq(result.notices.size(), 0)
	engine = _engine({})
	result = engine.authorize(cfg, cfg, _context())
	_expect(result, "V-045", "params.exposed_fields[0].live")
	assert_eq(result.notices.size(), 1)
	assert_true(result.notices[0].contains("E-0025"))
	assert_true(result.diagnostics[0].hint.contains("缺失文案模板"))

func test_metadata_absence_and_broken_reconfiguration_fail_explicitly() -> void:
	var engine = EngineScript.new()
	var cfg: Dictionary = _cfg()
	var result: Dictionary = engine.authorize(cfg, cfg, _context())
	_expect(result, "MODIFIER_SETUP", "validation_context")
	assert_false(engine.last_error.is_empty())
	assert_false(engine.configure_from_file("res://data/__t033_missing_metadata__.json"))
	assert_true(engine.last_error.contains("无法读取"))
	assert_false(engine.configure_from_file("res://S_docs/collab/assets/exposed_fields_meta.json"))
	assert_true(engine.last_error.contains("res://data/"))
	for key in ["fields", "permission_roles", "scope_roles", "source_permissions", "protected_segments", "operations"]:
		var policy: Dictionary = _policy()
		policy.erase(key)
		assert_false(engine.configure(policy, _exposure()))
		assert_false(engine.last_error.is_empty())
		_expect(engine.authorize(cfg, cfg, _context()), "MODIFIER_SETUP", "validation_context")
	assert_true(engine.configure(_policy(), _exposure()))
	assert_true(engine.authorize(cfg, cfg, _context()).ok)
	var broken: Dictionary = _policy()
	broken.protected_segments["V-046"] = []
	assert_false(engine.configure(broken, _exposure()))
	_expect(engine.authorize(cfg, cfg, _context()), "MODIFIER_SETUP", "validation_context")

func test_metadata_unknown_roles_cannot_fall_through_to_number_or_own_scope() -> void:
	var engine = EngineScript.new()
	var policy: Dictionary = _policy()
	policy.scope_roles.everything = "all_skills"
	assert_false(engine.configure(policy, _exposure()))
	policy = _policy()
	var exposure: Dictionary = _exposure()
	exposure.permissions.append("admin_permission")
	assert_false(engine.configure(policy, exposure))
	policy = _policy()
	policy.permission_roles.number = policy.permission_roles.live
	assert_false(engine.configure(policy, _exposure()), "三个角色不得指向相同权限")

func test_metadata_renames_permissions_fields_scopes_sources_and_profiles() -> void:
	var policy: Dictionary = _policy()
	var exposure: Dictionary = _exposure()
	exposure.permissions = ["numeric_grant", "behavior_grant", "live_grant"]
	exposure.live_permission = "live_grant"
	policy.permission_roles = {"number": "numeric_grant", "behavior": "behavior_grant", "live": "live_grant"}
	policy.source_permissions = {"artifact": exposure.permissions.duplicate(), "stone": ["numeric_grant"]}
	policy.scope_roles = {"own": "local_only", "tagged": "filtered"}
	policy.input_path = "loadout.mods"
	policy.fields.permission = "grant"
	policy.fields.targets = "references"
	policy.operations = {"injected_profile": {"kind": "number", "is_set": true}}
	exposure.input_path = "loadout.exposed"
	exposure.fields["address"] = exposure.fields["field_path"]
	exposure.fields.erase("field_path")
	exposure.roles.reference = "address"
	exposure.required[exposure.required.find("field_path")] = "address"
	var cfg: Dictionary = _cfg("mutate_live_instance")
	var modifier: Dictionary = cfg.params.modifiers[0]
	# 坑 6：Dictionary 用点语法写「新键」会产生 StringName 键，不是 String，
	# 与引擎/素材里的 String 键不等，.has("x") 也取不到。新键一律用下标语法。
	modifier["grant"] = "live_grant"
	modifier.erase("permission")
	modifier["references"] = modifier["targets"]
	modifier.erase("targets")
	modifier.scope = "local_only"
	modifier.stack_rule.operation_profile = "injected_profile"
	var entry: Dictionary = cfg.params.exposed_fields[0]
	entry.permissions = ["live_grant"]
	entry["address"] = entry["field_path"]
	entry.erase("field_path")
	cfg["loadout"] = {"mods": [modifier], "exposed": [entry]}
	cfg.params.erase("modifiers")
	cfg.params.erase("exposed_fields")
	var engine = EngineScript.new()
	assert_true(engine.configure(policy, exposure), engine.last_error)
	var result: Dictionary = engine.apply_live(cfg, {"params": {"damage": 10}}, {"params.damage": 40}, {"source_kind": "artifact"})
	assert_true(result.ok)
	assert_eq(result.approved.size(), 1)
	assert_eq(result.values.params.damage, 40)
	assert_eq(result.approved[0].permission, "live_grant")
	result = engine.authorize(cfg, cfg, {"source_kind": "stone"})
	_expect(result, "V-041", "loadout.mods[0].grant")

func test_protected_list_is_injected_and_uses_whole_segments() -> void:
	var policy: Dictionary = _policy()
	policy.protected_segments["V-046"].append("secret_identity")
	var engine = EngineScript.new()
	assert_true(engine.configure(policy, _exposure()))
	var cfg: Dictionary = _cfg("mutate_number", "params.secret_identity")
	cfg.params.secret_identity = 10
	_expect(engine.authorize(cfg, cfg, _context()), "V-046", "params.modifiers[0].targets[0]")
	cfg = _cfg("mutate_number", "params.history_count")
	cfg.params.history_count = 10
	var result: Dictionary = engine.authorize(cfg, cfg, _context())
	assert_true(result.ok, "history_count 不是 history，不能做子串匹配")
	assert_eq(result.approved.size(), 1)

func test_unregistered_source_context_fails_instead_of_guessing_item() -> void:
	var engine = _engine()
	var cfg: Dictionary = _cfg()
	for context in [{}, {"source_kind": "unknown"}, {"source_kind": "item", "inherit_all": "true"}, {"source_kind": "item", "secret_grant": true}]:
		_expect(engine.authorize(cfg, cfg, context), "MODIFIER_SETUP", "validation_context")
