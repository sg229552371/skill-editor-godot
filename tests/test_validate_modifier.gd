extends GutTest

const Rules = preload("res://skill_core/validate/rules/r_modifier.gd")
const Diag = preload("res://skill_core/api/diagnostic.gd")

func _json(name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/" + name + ".json"))

func _cfg() -> Dictionary:
	return {"meta": {"tags": ["fire"]}, "params": {"projectile_speed": 10.0, "max_generation": 1, "cast_budget": 16,
		"modifiers": [], "exposed_fields": [], "triggers": [], "derivations": []}}

func _context() -> Dictionary:
	return {"capabilities": {"params": {"summon": false}}, "item_category": "relic", "exposed": {},
		"live_requests": [], "stack_operations": {}, "set_counts": {}, "reset_writes": [],
		"derivation_analysis": {"truncated_paths": []},
		"budget_estimate": {"total_requested_instances": 1, "capped": false, "guarantee_bindings": []},
		"produced_types": {"spawn_ref": "effect_template"}, "record_fields": _json("record_fields"),
		"condition_registry": {"condition_ref": {"accessible_fields": ["source", "target"], "part_filters": []}},
		"self_chain_evidence": {"depth_bound": true, "source_mark_bound": true, "cooldown_bound": true,
			"budget_bound": true, "worst_case_note_complete": true},
		"project_limits": {"defaults": {"cast_budget": 16}, "hard_caps": {"max_generation": 4, "cast_budget": 64, "max_chain_depth": 8}}}

func _validator() -> Rules:
	var validator: Rules = Rules.new()
	assert_true(validator.configure(_json("params_meta")), validator.last_error)
	return validator

func _find(result: Dictionary, rule_id: String, path: String):
	for diagnostic in result.diagnostics:
		if diagnostic.rule_id == rule_id and diagnostic.path == path:
			return diagnostic
	fail_test("缺少 %s @ %s；实际=%s" % [rule_id, path, str(result.diagnostics)])
	return null

func _expect(cfg: Dictionary, context: Dictionary, rule_id: String, path: String, warning: bool = false) -> void:
	var result: Dictionary = _validator().validate(cfg, context)
	assert_eq(result.ok, warning, "%s 的保存结论" % rule_id)
	var diagnostic = _find(result, rule_id, path)
	if diagnostic != null:
		assert_eq(diagnostic.severity, Diag.SEV_WARN if warning else Diag.SEV_BLOCK)
		assert_false(diagnostic.hint.is_empty())

func _modifier(id: String = "m0") -> Dictionary:
	return {"modifier_id": id, "permission": "mutate_number", "scope": "own_skill", "inheritable": false,
		"targets": ["params.projectile_speed"], "stack_rule": {"operation_profile": "add_ref"}}

func _exposure() -> Dictionary:
	return {"field_path": "params.projectile_speed", "permissions": ["mutate_number", "mutate_live_instance"],
		"min": 0.0, "max": 100.0, "live": true, "inheritable": false, "set_conflict_note": ""}

func _with_modifier(cfg: Dictionary, ctx: Dictionary) -> void:
	cfg.params.modifiers = [_modifier()]
	cfg.params.exposed_fields = [_exposure()]
	ctx.exposed["params.projectile_speed"] = _exposure()
	ctx.stack_operations.m0 = {"category": "add", "operands": [2.0], "base_value": 10.0,
		"hard_range": {"min": 0.0, "max": 100.0}, "mount_order": 0}
	ctx.live_requests = [{"field_path": "params.projectile_speed", "permission": "mutate_live_instance"}]

func test_v040_multiple_unknown_and_null_permissions() -> void:
	for value in [["mutate_number", "add_behavior"], "unknown", null]:
		var cfg: Dictionary = _cfg()
		var ctx: Dictionary = _context()
		_with_modifier(cfg, ctx)
		cfg.params.modifiers.append(_modifier("m1"))
		cfg.params.modifiers[1].permission = value
		_expect(cfg, ctx, "V-040", "params.modifiers[1].permission")

func test_v041_category_policy_and_context_failure() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	_with_modifier(cfg, ctx)
	ctx.item_category = "crystal"
	assert_true(_validator().validate(cfg, ctx).ok)
	cfg.params.modifiers[0].permission = "add_behavior"
	_expect(cfg, ctx, "V-041", "params.modifiers[0].permission")
	for value in ["unregistered", null, 3]:
		ctx.item_category = value
		_expect(cfg, ctx, "V-041", "params.modifiers[0].permission")
	ctx.erase("item_category")
	_expect(cfg, ctx, "V-041", "params.modifiers[0].permission")

func test_v042_scope_and_tag_filter() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	_with_modifier(cfg, ctx)
	cfg.params.modifiers[0].scope = "tagged"
	cfg.params.modifiers[0].tag_filter = ["fire"]
	assert_true(_validator().validate(cfg, ctx).ok)
	cfg.params.modifiers[0].tag_filter = []
	_expect(cfg, ctx, "V-042", "params.modifiers[0].tag_filter")
	cfg.params.modifiers[0].scope = "everywhere"
	_expect(cfg, ctx, "V-042", "params.modifiers[0].scope")

func test_v043_unexposed_third_target_and_required_context() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	_with_modifier(cfg, ctx)
	assert_true(_validator().validate(cfg, ctx).ok)
	cfg.params.modifiers[0].targets = ["params.projectile_speed", "params.projectile_speed", "ambiguous"]
	_expect(cfg, ctx, "V-043", "params.modifiers[0].targets[2]")
	cfg.params.modifiers[0].targets = ["params.projectile_speed"]
	ctx.erase("exposed")
	_expect(cfg, ctx, "V-043", "params.modifiers[0].targets[0]")
	ctx.exposed = []
	_expect(cfg, ctx, "V-043", "params.modifiers[0].targets[0]")

func test_v044_exposed_but_nonexistent_is_not_existing_number() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	_with_modifier(cfg, ctx)
	assert_true(_validator().validate(cfg, ctx).ok)
	cfg.params.erase("projectile_speed")
	_expect(cfg, ctx, "V-044", "params.modifiers[0].targets[0]")
	cfg.params.projectile_speed = 10.0
	ctx.erase("exposed")
	_expect(cfg, ctx, "V-044", "params.modifiers[0].targets[0]")

func test_v045_live_requires_both_sides_and_strict_bool() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	_with_modifier(cfg, ctx)
	cfg.params.modifiers[0].permission = "mutate_live_instance"
	assert_true(_validator().validate(cfg, ctx).ok)
	ctx.live_requests = []
	_expect(cfg, ctx, "V-045", "params.modifiers[0].permission")
	ctx.live_requests = [{"field_path": "params.projectile_speed", "permission": "mutate_live_instance"}]
	ctx.exposed["params.projectile_speed"].live = "true"
	_expect(cfg, ctx, "V-045", "params.exposed_fields[0].live")
	ctx.exposed["params.projectile_speed"].live = true
	ctx.erase("live_requests")
	_expect(cfg, ctx, "V-045", "params.modifiers[0].permission")
	ctx.live_requests = {}
	_expect(cfg, ctx, "V-045", "params.modifiers[0].permission")

func test_v046_protected_segments_not_substrings() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	_with_modifier(cfg, ctx)
	cfg.params.modifiers[0].targets = ["params.projectile_speed", "params.projectile_speed", "params.snapshot.power"]
	_expect(cfg, ctx, "V-046", "params.modifiers[0].targets[2]")
	cfg.params.modifiers[0].targets[2] = "params.snapshot_power"
	var result: Dictionary = _validator().validate(cfg, ctx)
	for diagnostic in result.diagnostics:
		assert_ne(diagnostic.rule_id, "V-046")
	assert_false(result.ok, "未暴露仍由 V-043 拒绝，不是整体验收通过")

func test_v047_safety_bounds_cannot_be_modified() -> void:
	for field in ["max_generation", "max_chain_depth", "allow_self_chain"]:
		var cfg: Dictionary = _cfg()
		var ctx: Dictionary = _context()
		_with_modifier(cfg, ctx)
		cfg.params.modifiers[0].targets = ["params." + field]
		_expect(cfg, ctx, "V-047", "params.modifiers[0].targets[0]")

func test_v048_bounds_types_and_nonfinite_are_slot_local() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	_with_modifier(cfg, ctx)
	for value in [null, "64", INF, NAN, 101.0]:
		cfg.params.exposed_fields[0].min = value
		_expect(cfg, ctx, "V-048", "params.exposed_fields[0].min")
	cfg.params.exposed_fields[0].min = 100.0
	assert_true(_validator().validate(cfg, ctx).ok, "min == max 合法")
	cfg.params.exposed_fields[0].erase("min")
	var missing: Dictionary = _validator().validate(cfg, ctx)
	var missing_diag = _find(missing, "V-048", "params.exposed_fields[0].min")
	if missing_diag != null:
		assert_eq(missing_diag.actual, "未填写")
	cfg.params.exposed_fields[0].min = null
	var null_diag = _find(_validator().validate(cfg, ctx), "V-048", "params.exposed_fields[0].min")
	if null_diag != null:
		assert_eq(null_diag.actual, "null")

func test_v049_category_comes_from_resolved_operation_not_ref_name() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	_with_modifier(cfg, ctx)
	cfg.params.modifiers[0].stack_rule.operation_profile = "not_an_enum_name"
	assert_true(_validator().validate(cfg, ctx).ok)
	ctx.stack_operations.m0.category = "divide"
	_expect(cfg, ctx, "V-049", "params.modifiers[0].stack_rule")
	ctx.erase("stack_operations")
	_expect(cfg, ctx, "V-049", "params.modifiers[0].stack_rule")
	ctx.stack_operations = []
	_expect(cfg, ctx, "V-049", "params.modifiers[0].stack_rule")

func test_v050_multiple_set_warns_and_last_mount_wins() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	_with_modifier(cfg, ctx)
	cfg.params.modifiers.append(_modifier("m1"))
	ctx.stack_operations.m0.category = "set"
	ctx.stack_operations.m1 = {"category": "set", "operands": [4.0], "base_value": 10.0,
		"hard_range": {"min": 0.0, "max": 100.0}, "mount_order": 1}
	_expect(cfg, ctx, "V-050", "params.exposed_fields[0].set_conflict_note", true)
	cfg.params.exposed_fields[0].set_conflict_note = "最后挂载者覆盖"
	assert_true(_validator().validate(cfg, ctx).ok)
	ctx.stack_operations = "bad"
	var result: Dictionary = _validator().validate(cfg, ctx)
	assert_false(result.ok)
	assert_ne(_find(result, "V-050", "params.modifiers[0].stack_rule"), null)

func test_v051_merge_type_hard_range_and_legal_clamp() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	_with_modifier(cfg, ctx)
	ctx.stack_operations.m0.operands = [95.0]
	_expect(cfg, ctx, "V-051", "params.modifiers[0].targets[0]")
	cfg.params.modifiers.append(_modifier("clamp0"))
	ctx.stack_operations.clamp0 = {"category": "clamp", "operands": [0.0, 100.0], "base_value": 10.0,
		"hard_range": {"min": 0.0, "max": 100.0}, "mount_order": 1}
	assert_true(_validator().validate(cfg, ctx).ok, "最终夹取合法")
	ctx.stack_operations.m0.operands = [INF]
	_expect(cfg, ctx, "V-051", "params.modifiers[0].targets[0]")
	ctx.stack_operations.m0.operands = [95.0]
	ctx.erase("stack_operations")
	_expect(cfg, ctx, "V-051", "params.modifiers[0].targets[0]")

func test_v052_inheritable_requires_bool() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	_with_modifier(cfg, ctx)
	for value in ["all", 1, null]:
		cfg.params.modifiers[0].inheritable = value
		_expect(cfg, ctx, "V-052", "params.modifiers[0].inheritable")
	cfg.params.modifiers[0].erase("inheritable")
	assert_true(_validator().validate(cfg, ctx).ok, "缺省来自 Schema false，不隐式全继承")

func test_v053_generation_type_and_project_cap_changes_conclusion() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	cfg.params.max_generation = 3
	assert_true(_validator().validate(cfg, ctx).ok)
	ctx.project_limits.hard_caps.max_generation = 2
	_expect(cfg, ctx, "V-053", "params.max_generation")
	ctx.project_limits.hard_caps.erase("max_generation")
	_expect(cfg, ctx, "V-053", "params.max_generation")
	ctx.project_limits.hard_caps.max_generation = "4"
	_expect(cfg, ctx, "V-053", "params.max_generation")
	for value in [-1, 1.5, "3", null, INF]:
		cfg.params.max_generation = value
		_expect(cfg, _context(), "V-053", "params.max_generation")

func _derivation() -> Dictionary:
	return {"trigger_id": "derive0", "event": "hit", "child_template": "child0", "count": 1}

func test_v054_theoretical_truncation_is_warning_at_schema_child_slot() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	cfg.params.derivations = [_derivation()]
	ctx.derivation_analysis.truncated_paths = [{"path": "params.derivations[0].produces", "blocked_by": "params.max_generation", "generation": 2}]
	_expect(cfg, ctx, "V-054", "params.derivations[0].child_template", true)
	ctx.derivation_analysis.truncated_paths = []
	assert_true(_validator().validate(cfg, ctx).ok)
	ctx.erase("derivation_analysis")
	var result: Dictionary = _validator().validate(cfg, ctx)
	assert_false(result.ok)
	assert_ne(_find(result, "V-054", "params.derivations[0].child_template"), null)
	ctx.derivation_analysis = {"truncated_paths": "wrong"}
	assert_false(_validator().validate(cfg, ctx).ok)

func test_v055_budget_missing_default_and_strict_integer() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	for value in [0, -1, 1.5, "64", null]:
		cfg.params.cast_budget = value
		_expect(cfg, ctx, "V-055", "params.cast_budget")
	cfg.params.erase("cast_budget")
	assert_true(_validator().validate(cfg, ctx).ok)
	ctx.project_limits.defaults.erase("cast_budget")
	_expect(cfg, ctx, "V-055", "params.cast_budget")
	ctx.project_limits.defaults.cast_budget = "64"
	_expect(cfg, ctx, "V-055", "params.cast_budget")

func test_v056_requested_not_capped_instances_warn() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	ctx.budget_estimate.total_requested_instances = 17
	ctx.budget_estimate.capped = true
	_expect(cfg, ctx, "V-056", "params.cast_budget", true)
	ctx.budget_estimate.total_requested_instances = 16
	assert_true(_validator().validate(cfg, ctx).ok)
	ctx.erase("budget_estimate")
	var result: Dictionary = _validator().validate(cfg, ctx)
	assert_false(result.ok)
	assert_ne(_find(result, "V-056", "params.cast_budget"), null)
	ctx.budget_estimate = {"total_requested_instances": "17", "capped": false, "guarantee_bindings": []}
	assert_false(_validator().validate(cfg, ctx).ok)

func test_v057_reset_split_budget_from_cfg_and_analysis() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	cfg.params.derivations = [_derivation()]
	cfg.params.derivations[0].split_budget = 5
	_expect(cfg, ctx, "V-057", "params.derivations[0].split_budget")
	cfg.params.derivations[0].erase("split_budget")
	ctx.reset_writes = [{"path": "params.derivations[0].child_template", "kind": "split_budget", "source": "child0"}]
	_expect(cfg, ctx, "V-057", "params.derivations[0].child_template")
	ctx.reset_writes = []
	assert_true(_validator().validate(cfg, ctx).ok)
	ctx.reset_writes = "bad"
	_expect(cfg, ctx, "V-057", "params.split_budget")
	ctx.erase("reset_writes")
	var result: Dictionary = _validator().validate(cfg, ctx)
	assert_true(result.ok)
	assert_true(result.notices.size() > 0, "可选缺省必须声明未执行，不能当成分析通过")

func test_v058_reset_chain_or_visited_is_rejected() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	cfg.params.derivations = [_derivation()]
	for field in ["chain_remaining", "visited"]:
		cfg.params.derivations[0][field] = 4
		_expect(cfg, ctx, "V-058", "params.derivations[0]." + field)
		cfg.params.derivations[0].erase(field)
	ctx.reset_writes = [{"path": "params.derivations[0].child_template", "kind": "visited", "source": "child0"}]
	_expect(cfg, ctx, "V-058", "params.derivations[0].child_template")
	ctx.reset_writes = []
	assert_true(_validator().validate(cfg, ctx).ok)
	ctx.reset_writes = null
	_expect(cfg, ctx, "V-058", "params.chain_remaining")

func _trigger(id: String = "trigger0") -> Dictionary:
	return {"trigger_id": id, "record": "hit_settled", "condition": "condition_ref", "chance": 1.0,
		"internal_cooldown_ticks": 1, "max_chain_depth": 4, "allow_self_chain": false, "action_profile": "spawn_ref"}

func test_v059_trigger_ids_unique_across_trigger_and_derivation() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.triggers = [_trigger(), _trigger()]
	_expect(cfg, _context(), "V-059", "params.triggers[1].trigger_id")
	cfg.params.triggers = [_trigger("derive0")]
	cfg.params.derivations = [_derivation()]
	_expect(cfg, _context(), "V-059", "params.derivations[0].trigger_id")
	cfg.params.triggers[0].trigger_id = "\n"
	_expect(cfg, _context(), "V-059", "params.triggers[0].trigger_id")

func test_v060_record_not_on_and_no_silent_migration() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.triggers = [_trigger(), _trigger("trigger1")]
	for value in ["hit", "vanish", "debug_record", null]:
		cfg.params.triggers[1].record = value
		_expect(cfg, _context(), "V-060", "params.triggers[1].record")
	cfg.params.triggers[1].erase("record")
	cfg.params.triggers[1].on = "hit_settled"
	_expect(cfg, _context(), "V-060", "params.triggers[1].record")
	assert_false(cfg.params.triggers[1].has("record"))

func test_v061_produced_ref_type_not_merely_existence() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	cfg.params.triggers = [_trigger()]
	assert_true(_validator().validate(cfg, ctx).ok)
	ctx.produced_types.spawn_ref = "illegal"
	_expect(cfg, ctx, "V-061", "params.triggers[0].action_profile")
	ctx.produced_types.spawn_ref = "effect_template"
	cfg.params.triggers[0].produces = ["spawn_ref", "wrong_ref"]
	ctx.produced_types.wrong_ref = "illegal"
	_expect(cfg, ctx, "V-061", "params.triggers[0].produces[1]")
	ctx.erase("produced_types")
	_expect(cfg, ctx, "V-061", "params.triggers[0].action_profile")
	ctx.produced_types = []
	_expect(cfg, ctx, "V-061", "params.triggers[0].action_profile")

func test_v062_conditions_read_only_registered_record_fields() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	cfg.params.triggers = [_trigger()]
	assert_true(_validator().validate(cfg, ctx).ok)
	ctx.condition_registry.condition_ref.accessible_fields = ["actual_amount"]
	_expect(cfg, ctx, "V-062", "params.triggers[0].condition")
	ctx.condition_registry.condition_ref.accessible_fields = ["part_type", "target"]
	_expect(cfg, ctx, "V-062", "params.triggers[0].condition")
	ctx.condition_registry.condition_ref.part_filters = ["heal"]
	assert_true(_validator().validate(cfg, ctx).ok)
	cfg.params.triggers[0].condition = "target.hp > 0; arbitrary_call()"
	_expect(cfg, ctx, "V-062", "params.triggers[0].condition")
	cfg.params.triggers[0].condition = "condition_ref"
	ctx.erase("condition_registry")
	_expect(cfg, ctx, "V-062", "params.triggers[0].condition")
	ctx = _context()
	ctx.erase("record_fields")
	_expect(cfg, ctx, "V-062", "params.triggers[0].condition")

func test_v063_probability_finite_number_boundary() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.triggers = [_trigger()]
	for value in [-0.01, 1.01, "1", null, INF, NAN, true]:
		cfg.params.triggers[0].chance = value
		_expect(cfg, _context(), "V-063", "params.triggers[0].chance")
	for value in [0, 1, 0.25]:
		cfg.params.triggers[0].chance = value
		assert_true(_validator().validate(cfg, _context()).ok)

func test_v064_internal_cooldown_required_strict_tick() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.triggers = [_trigger()]
	for value in [-1, 0.5, "0", null, true]:
		cfg.params.triggers[0].internal_cooldown_ticks = value
		_expect(cfg, _context(), "V-064", "params.triggers[0].internal_cooldown_ticks")
	cfg.params.triggers[0].erase("internal_cooldown_ticks")
	_expect(cfg, _context(), "V-064", "params.triggers[0].internal_cooldown_ticks")

func test_v065_zero_cooldown_note_and_chain_bound_budget() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	cfg.params.triggers = [_trigger()]
	cfg.params.triggers[0].internal_cooldown_ticks = 0
	_expect(cfg, ctx, "V-065", "params.triggers[0].zero_cooldown_note")
	cfg.params.triggers[0].zero_cooldown_note = "由该链共享预算限制"
	_expect(cfg, ctx, "V-065", "params.triggers[0].zero_cooldown_note")
	ctx.budget_estimate.guarantee_bindings = [{"trigger_path": "params.triggers[0]", "budget_path": "params.cast_budget"}]
	assert_true(_validator().validate(cfg, ctx).ok)
	cfg.params.triggers[0].erase("zero_cooldown_note")
	_expect(cfg, ctx, "V-065", "params.triggers[0].zero_cooldown_note")
	cfg.params.triggers[0].zero_cooldown_note = "安全说明"
	ctx.budget_estimate.guarantee_bindings[0].trigger_path = "params.triggers[1]"
	_expect(cfg, ctx, "V-065", "params.triggers[0].zero_cooldown_note")
	ctx.erase("budget_estimate")
	_expect(cfg, ctx, "V-065", "params.triggers[0].zero_cooldown_note")
	ctx.budget_estimate = null
	_expect(cfg, ctx, "V-065", "params.triggers[0].zero_cooldown_note")

func test_v066_depth_required_and_project_cap() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	cfg.params.triggers = [_trigger()]
	assert_true(_validator().validate(cfg, ctx).ok)
	ctx.project_limits.hard_caps.max_chain_depth = 3
	_expect(cfg, ctx, "V-066", "params.triggers[0].max_chain_depth")
	ctx.project_limits.hard_caps.erase("max_chain_depth")
	_expect(cfg, ctx, "V-066", "params.triggers[0].max_chain_depth")
	cfg.params.triggers[0].erase("max_chain_depth")
	_expect(cfg, _context(), "V-066", "params.triggers[0].max_chain_depth")

func test_v067_nonempty_note_does_not_prove_self_chain_safety() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	cfg.params.triggers = [_trigger()]
	cfg.params.triggers[0].allow_self_chain = true
	cfg.params.triggers[0].self_chain_note = "任意语言的说明；不搜索中文关键词"
	assert_true(_validator().validate(cfg, ctx).ok)
	for key in ctx.self_chain_evidence.keys():
		ctx.self_chain_evidence[key] = false
		_expect(cfg, ctx, "V-067", "params.triggers[0].self_chain_note")
		ctx.self_chain_evidence[key] = true
	ctx.erase("self_chain_evidence")
	_expect(cfg, ctx, "V-067", "params.triggers[0].self_chain_note")
	ctx.self_chain_evidence = {"depth_bound": "true"}
	_expect(cfg, ctx, "V-067", "params.triggers[0].self_chain_note")

func test_v068_summon_cap_from_resolved_capability() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	ctx.capabilities.params.summon = true
	_expect(cfg, ctx, "V-068", "params.summon_cap")
	cfg.params.summon_cap = 1
	assert_true(_validator().validate(cfg, ctx).ok)
	for value in [0, -1, "1", 1.5, null]:
		cfg.params.summon_cap = value
		_expect(cfg, ctx, "V-068", "params.summon_cap")
	ctx.erase("capabilities")
	_expect(cfg, ctx, "V-068", "params.summon_cap")
	ctx.template_capabilities = {"params": {"summon": true}}
	cfg.params.summon_cap = 1
	assert_true(_validator().validate(cfg, ctx).ok)
	ctx.template_capabilities.params.summon = "false"
	_expect(cfg, ctx, "V-068", "params.summon_cap")

func test_summon_template_uses_registered_parameter_cap_slot() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	cfg.params.templates = [{"template_id": "summon_template"}]
	ctx.capabilities["params.templates[0]"] = {"summon": true}
	_expect(cfg, ctx, "V-068", "params.summon_cap")
	cfg.params.summon_cap = 2
	assert_true(_validator().validate(cfg, ctx).ok)

func test_v069_bool_fields_not_truthy_values() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.triggers = [_trigger()]
	for field in ["attach_to_caster", "bind_owner", "shotgun_allowed"]:
		cfg.params[field] = "false"
		_expect(cfg, _context(), "V-069", "params." + field)
		cfg.params[field] = false
	cfg.params.triggers[0].allow_self_chain = 1
	_expect(cfg, _context(), "V-069", "params.triggers[0].allow_self_chain")
	cfg.params.triggers[0].allow_self_chain = false
	assert_true(_validator().validate(cfg, _context()).ok)

class CorruptTableRules extends Rules:
	var corruption: String = ""
	func _read_csv(path: String, required: Array) -> Array[Dictionary]:
		var rows: Array[Dictionary] = super._read_csv(path, required)
		if path != RULES_PATH:
			return rows
		for index in range(rows.size()):
			if rows[index].rule_id != "V-040":
				continue
			match corruption:
				"condition": rows[index].condition = "unbound condition"
				"missing": rows.remove_at(index)
				"severity": rows[index].severity = "未登记严重度"
				"warning": rows[index].severity = "警告"
			break
		return rows

func test_configuration_requires_complete_bound_interval_and_csv_severity() -> void:
	var validator: Rules = Rules.new()
	assert_false(validator.validate(_cfg(), _context()).ok)
	assert_false(validator.configure({}))
	assert_true(validator.configure(_json("params_meta")), validator.last_error)
	assert_eq(validator._groups.size(), 1)
	assert_eq(validator._groups[0].rules.size(), 31)
	var warning_ids: Array = []
	for rule in validator._groups[0].rules:
		if rule.severity == "警告":
			warning_ids.append(rule.rule_id)
	assert_eq(warning_ids, ["V-050", "V-054", "V-056"])
	for corruption in ["condition", "missing", "severity"]:
		var broken: CorruptTableRules = CorruptTableRules.new()
		broken.corruption = corruption
		assert_false(broken.configure(_json("params_meta")))
		assert_false(broken.last_error.is_empty())
		assert_false(broken.validate(_cfg(), _context()).ok)
	var changed: CorruptTableRules = CorruptTableRules.new()
	changed.corruption = "warning"
	assert_true(changed.configure(_json("params_meta")))
	var cfg: Dictionary = _cfg()
	cfg.params.modifiers = [{"modifier_id": "m0", "permission": "unknown", "targets": []}]
	var diagnostic = _find(changed.validate(cfg, _context()), "V-040", "params.modifiers[0].permission")
	if diagnostic != null:
		assert_eq(diagnostic.severity, Diag.SEV_WARN, "不是按规则 ID 写死严重度")

func test_optional_facts_absent_are_not_silent_success_evidence() -> void:
	var ctx: Dictionary = _context()
	ctx.erase("set_counts")
	ctx.erase("reset_writes")
	var result: Dictionary = _validator().validate(_cfg(), ctx)
	assert_true(result.ok)
	assert_true(result.notices.size() >= 3)
	assert_true(str(result.notices).contains("set_counts"))
	assert_true(str(result.notices).contains("reset_writes"))

func test_every_consumed_context_has_missing_or_wrong_type_failure() -> void:
	var scenarios: Array = [
		["V-041", "item_category", "params.modifiers[0].permission"],
		["V-043", "exposed", "params.modifiers[0].targets[0]"],
		["V-044", "exposed", "params.modifiers[0].targets[0]"],
		["V-045", "exposed", "params.modifiers[0].permission"],
		["V-045", "live_requests", "params.modifiers[0].permission"],
		["V-049", "stack_operations", "params.modifiers[0].stack_rule"],
		["V-050", "stack_operations", "params.modifiers[0].stack_rule"],
		["V-050", "set_counts", "params.exposed_fields"],
		["V-051", "stack_operations", "params.modifiers[0].targets[0]"],
		["V-051", "exposed", "params.modifiers[0].targets[0]"],
		["V-054", "derivation_analysis", "params.derivations[0].child_template"],
		["V-056", "budget_estimate", "params.cast_budget"],
		["V-057", "reset_writes", "params.split_budget"],
		["V-058", "reset_writes", "params.chain_remaining"],
		["V-061", "produced_types", "params.triggers[0].action_profile"],
		["V-062", "condition_registry", "params.triggers[0].condition"],
		["V-062", "record_fields", "params.triggers[0].condition"],
		["V-065", "budget_estimate", "params.triggers[0].zero_cooldown_note"],
		["V-067", "self_chain_evidence", "params.triggers[0].self_chain_note"],
		["V-068", "capabilities", "params.summon_cap"]]
	assert_eq(scenarios.size(), 20)
	for scenario in scenarios:
		var cfg: Dictionary = _cfg()
		var ctx: Dictionary = _context()
		_with_modifier(cfg, ctx)
		cfg.params.derivations = [_derivation()]
		cfg.params.triggers = [_trigger()]
		cfg.params.triggers[0].internal_cooldown_ticks = 0
		cfg.params.triggers[0].zero_cooldown_note = "受当前施放预算限制"
		cfg.params.triggers[0].allow_self_chain = true
		cfg.params.triggers[0].self_chain_note = "完整说明"
		ctx.budget_estimate.guarantee_bindings = [{"trigger_path": "params.triggers[0]", "budget_path": "params.cast_budget"}]
		if scenario[0] == "V-045":
			cfg.params.modifiers[0].permission = "mutate_live_instance"
		assert_true(_validator().validate(cfg, ctx).ok, "正确事实：%s" % str(scenario))
		ctx[scenario[1]] = null
		var validator: Rules = _validator()
		var result: Dictionary = validator.validate(cfg, ctx)
		assert_false(result.ok, str(scenario))
		assert_false(validator.last_error.is_empty())
		assert_ne(_find(result, scenario[0], scenario[2]), null)

func test_passive_default_card_and_override_paths_are_preserved() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	cfg.params.passive = {"triggers": [_trigger()]}
	cfg.params.passive.triggers[0].chance = "1"
	_expect(cfg, ctx, "V-063", "params.passive.triggers[0].chance")
	cfg.params.erase("passive")
	cfg.bricks = [{"default_cfg": {"params": {"bind_owner": "true"}}}]
	ctx.capabilities["bricks[0].default_cfg.params"] = {"summon": false}
	_expect(cfg, ctx, "V-069", "bricks[0].default_cfg.params.bind_owner")
	cfg.params.brick_overrides = [{"values": {"shotgun_allowed": 1}}]
	ctx.capabilities["params.brick_overrides[0].values"] = {"summon": false}
	_expect(cfg, ctx, "V-069", "params.brick_overrides[0].values.shotgun_allowed")

func test_exposed_permission_and_merged_bounds_are_not_ignored() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	_with_modifier(cfg, ctx)
	ctx.exposed["params.projectile_speed"].permissions = ["add_behavior"]
	_expect(cfg, ctx, "V-043", "params.modifiers[0].targets[0]")
	ctx.exposed["params.projectile_speed"].permissions = ["mutate_number"]
	ctx.exposed["params.projectile_speed"].max = 11.0
	_expect(cfg, ctx, "V-051", "params.modifiers[0].targets[0]")
	ctx.exposed["params.projectile_speed"].max = "11"
	_expect(cfg, ctx, "V-051", "params.modifiers[0].targets[0]")

func test_merged_integer_cannot_be_fractional_and_order_is_fixed() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	_with_modifier(cfg, ctx)
	cfg.params.summon_cap = 10
	cfg.params.modifiers[0].targets = ["params.summon_cap"]
	cfg.params.exposed_fields[0].field_path = "params.summon_cap"
	ctx.exposed["params.summon_cap"] = _exposure()
	ctx.stack_operations.m0.category = "mul"
	ctx.stack_operations.m0.operands = [1.05]
	_expect(cfg, ctx, "V-051", "params.modifiers[0].targets[0]")
	_with_modifier(cfg, ctx)
	cfg.params.projectile_speed = 10.0
	cfg.params.modifiers.append(_modifier("m1"))
	ctx.stack_operations.m0.category = "add"
	ctx.stack_operations.m0.operands = [10.0]
	ctx.stack_operations.m0.mount_order = 9
	ctx.stack_operations.m0.hard_range.max = 35.0
	ctx.stack_operations.m1 = {"category": "mul", "operands": [2.0], "base_value": 10.0,
		"hard_range": {"min": 0.0, "max": 35.0}, "mount_order": 0}
	_expect(cfg, ctx, "V-051", "params.modifiers[1].targets[0]", false)
	# set/add/mul/clamp, not mount order across categories: (10+10)*2=40, not 10*2+10=30.

func test_registered_initial_motion_budgets_are_not_child_resets() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.templates = [{"motion": {"split_budget": 2, "chain_remaining": 3}}]
	var result: Dictionary = _validator().validate(cfg, _context())
	assert_true(result.ok, "Schema 登记的初始预算不等于子体重置")
	assert_eq(result.diagnostics.size(), 0)

func test_safety_and_passive_wrapper_fields_use_same_safety_rules() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	cfg.params.safety = {"max_chain_depth": 9, "cast_budget": 16}
	_expect(cfg, ctx, "V-066", "params.safety.max_chain_depth")
	cfg.params.safety.max_chain_depth = 8
	cfg.params.safety.cast_budget = "16"
	_expect(cfg, ctx, "V-055", "params.safety.cast_budget")
	cfg.params.safety.cast_budget = 16
	cfg.params.passive = {"allow_self_chain": true, "triggers": [_trigger()]}
	cfg.params.passive.triggers[0].erase("allow_self_chain")
	_expect(cfg, ctx, "V-067", "params.passive.triggers[0].self_chain_note")
	cfg.params.passive.triggers[0].self_chain_note = "共享开关的完整说明"
	assert_true(_validator().validate(cfg, ctx).ok)

func test_validation_is_read_only_and_repeated_merge_uses_base() -> void:
	var cfg: Dictionary = _cfg()
	var ctx: Dictionary = _context()
	_with_modifier(cfg, ctx)
	var cfg_before: Dictionary = cfg.duplicate(true)
	var ctx_before: Dictionary = ctx.duplicate(true)
	var validator: Rules = _validator()
	assert_true(validator.validate(cfg, ctx).ok)
	assert_true(validator.validate(cfg, ctx).ok)
	assert_eq(cfg, cfg_before)
	assert_eq(ctx, ctx_before)

func test_v039_missing_or_duplicate_id_is_local() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.modifiers = [{"modifier_id": "same"}, {"modifier_id": "same"}]
	_expect(cfg, _context(), "V-039", "params.modifiers[1].modifier_id")
	cfg.params.modifiers[1].erase("modifier_id")
	_expect(cfg, _context(), "V-039", "params.modifiers[1].modifier_id")
