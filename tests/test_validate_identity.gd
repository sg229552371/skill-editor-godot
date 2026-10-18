extends GutTest

const IdentityRules = preload("res://skill_core/validate/rules/r_identity.gd")
const IdentityMeta = preload("res://skill_core/validate/identity_meta.gd")
const Diag = preload("res://skill_core/api/diagnostic.gd")

# 独立验收夹具，不是生产登记表。生产词表由 WorkBuddy 抽取并注入。
func _policy() -> Dictionary:
	return {
		"supported_schema_versions": ["0.1"],
		"id_pattern": "^[a-z][a-z0-9]*(?:_[a-z0-9]+){2,}$",
		"id_format": "<role>_<category>_<short_name>[_<variant>]",
		"version_pattern": "^[0-9]+\\.[0-9]+\\.[0-9]+$",
		"categories": ["active", "passive", "crystal", "relic"],
		"required_card_fields": ["brick_id", "name", "tagline", "carrier", "summary", "default_cfg", "author_params", "locked_params", "relic_params", "presentation", "player_text", "status"],
		"runnable_statuses": ["已登记"],
		"internal_terms": ["hit", "vanish", "range_end", "mutate_number"],
		"verb_behaviors": {"治疗": ["heal"], "伤害": ["damage"]},
		"max_player_sentences": 3,
		"sentence_delimiters": ["。", "！", "？", ".", "!", "?"]
	}

func _card() -> Dictionary:
	return {
		"brick_id": "test_bolt", "name": "测试卡", "tagline": "测试",
		"carrier": "independent", "summary": "测试用行为",
		"default_cfg": {"params": {"lifetime_ticks": 60}},
		"author_params": [], "locked_params": {"lifetime_ticks": "固定寿命"},
		"relic_params": {}, "presentation": [], "player_text": ["造成伤害。"],
		"status": "已登记"
	}

func _cfg() -> Dictionary:
	return {
		"schema_version": "0.1", "skill_id": "mage_active_bolt",
		"meta": {"role": "mage", "category": "active", "short_name": "bolt", "variant": "", "name": "飞弹", "version": "1.0.0", "author": "test", "pools": ["starter"], "tags": ["ranged"]},
		"bricks": [_card(), _card(), _card()],
		"params": {}, "presentation": {}, "runtime_hints": {}
	}

func _context() -> Dictionary:
	return {
		"roles": ["mage", "knight"], "pools": ["starter"], "tags": ["ranged"],
		"catalog": {"test_bolt": {"resolved": true, "status": "已登记"}},
		"card_behaviors": {"bricks[0]": ["damage"], "bricks[1]": ["damage"], "bricks[2]": ["damage"]},
		"outputs": {"child": [{"resolved": true}]},
		"definitions": [], "current_source": "res://data/skills/test.yaml"
	}

func _validator():
	var validator = IdentityRules.new()
	assert_true(validator.configure(_policy()), validator.last_error)
	return validator

func _find(result: Dictionary, rule_id: String, path: String):
	var matches: Array = []
	for diagnostic in result.diagnostics:
		if diagnostic.rule_id == rule_id and diagnostic.path == path:
			matches.append(diagnostic)
	assert_eq(matches.size(), 1, "%s 应且只应定位到 %s" % [rule_id, path])
	if matches.size() != 1:
		return null
	return matches[0]

func _reject(cfg: Dictionary, rule_id: String, path: String, code: String):
	var validator = _validator()
	var result: Dictionary = validator.validate(cfg, _context())
	assert_false(result.ok, "阻止保存不能降级")
	var diagnostic = _find(result, rule_id, path)
	if diagnostic != null:
		assert_true(diagnostic is Diag)
		assert_eq(diagnostic.code, code)
		assert_eq(diagnostic.severity, Diag.SEV_BLOCK)
		assert_false(diagnostic.hint.is_empty())
		assert_false(diagnostic.hint.contains("{"), "所有文案占位必须填完")
	return diagnostic

func _clean(cfg: Dictionary) -> void:
	var validator = _validator()
	var result: Dictionary = validator.validate(cfg, _context())
	assert_true(result.ok, str(result.diagnostics))
	assert_eq(result.diagnostics.size(), 0)

func test_missing_metadata_context_or_csv_fails_explicitly() -> void:
	var validator = IdentityRules.new()
	var result: Dictionary = validator.validate(_cfg(), _context())
	assert_false(result.ok)
	assert_eq(result.diagnostics.size(), 1)
	assert_eq(result.diagnostics[0].code, "VALIDATION_METADATA_UNAVAILABLE")
	assert_false(validator.configure({}))
	assert_false(validator.last_error.is_empty())
	assert_false(validator.configure(_policy(), "res://not_present_identity_rules.csv"))
	assert_false(validator.last_error.is_empty())
	assert_true(validator.configure(_policy()))
	var context: Dictionary = _context()
	context.erase("roles")
	result = validator.validate(_cfg(), context)
	assert_false(result.ok)
	assert_eq(result.diagnostics.size(), 1)
	assert_eq(result.diagnostics[0].severity, Diag.SEV_BLOCK)
	assert_true(validator.last_error.contains("roles"))
	context = _context()
	context.card_behaviors.erase("bricks[2]")
	result = validator.validate(_cfg(), context)
	assert_false(result.ok, "不能用缺失的行为表充当空行为表")

func test_csv_drives_rule_metadata_and_only_identity_range_is_registered() -> void:
	var validator = _validator()
	assert_eq(validator._rules.size(), 84, "从完整 CSV 读取，不能只认十八条")
	assert_eq(validator._groups.size(), 1)
	assert_eq(validator._groups[0].rules.size(), 18)
	var bad: Dictionary = _cfg()
	bad.schema_version = "unsupported"
	var result: Dictionary = validator.validate(bad, _context())
	var diagnostic = _find(result, "V-001", "schema_version")
	if diagnostic != null:
		assert_eq(diagnostic.expected, '["0.1"]')
		assert_true(diagnostic.hint.begins_with("文件结构版本为"))
		assert_true(diagnostic.hint.contains("unsupported"))
		assert_eq(diagnostic.severity, Diag.SEV_BLOCK)
	for item in result.diagnostics:
		assert_true(int(item.rule_id.trim_prefix("V-")) <= 18)

func test_loaded_rule_id_and_field_path_are_not_dispatch_switches() -> void:
	var validator = _validator()
	# 故障注入已载入的规则行：执行器不依赖固定 ID 或固定诊断路径。
	validator._groups[0].rules[0].rule_id = "V-TEST-IDENTITY"
	validator._groups[0].rules[0].paths = ["alternate_version"]
	var cfg: Dictionary = _cfg()
	cfg.alternate_version = "unsupported"
	var result: Dictionary = validator.validate(cfg, _context())
	assert_false(result.ok)
	assert_eq(result.diagnostics.size(), 1)
	_find(result, "V-TEST-IDENTITY", "alternate_version")

func test_rule_range_can_extend_without_overwriting_identity_group() -> void:
	var validator = _validator()
	var row: Dictionary = validator._rules[18]
	assert_eq(row.rule_id, "V-019", "扩展测试必须确实选中区间外的行")
	var handlers: Dictionary = {}
	handlers[row.condition] = func(_cfg_value: Dictionary, _context_value: Dictionary, _rule: Dictionary) -> Array: return []
	assert_true(validator.register_group(19, 19, handlers), validator.last_error)
	assert_eq(validator._groups.size(), 2)
	assert_false(validator.register_group(18, 19, handlers), "重叠注册必须拒绝")
	assert_eq(validator._groups.size(), 2, "失败不能半注册")

func test_unknown_message_code_has_fallback_and_notice_not_silent_drop() -> void:
	var validator = _validator()
	# 白盒故障注入，不修改共享 CSV 或冻结 Diagnostic。
	validator._groups[0].rules[0].error_code = "E-TEST-MISSING"
	var bad: Dictionary = _cfg()
	bad.erase("schema_version")
	var result: Dictionary = validator.validate(bad, _context())
	assert_false(result.ok)
	assert_eq(result.diagnostics.size(), 1)
	assert_eq(result.notices.size(), 1)
	var diagnostic = _find(result, "V-001", "schema_version")
	if diagnostic != null:
		assert_eq(diagnostic.code, "E-TEST-MISSING")
		assert_eq(diagnostic.severity, Diag.SEV_BLOCK)
		assert_true(diagnostic.hint.contains("缺失文案模板"))
		assert_true(diagnostic.hint.contains("schema_version"))

func test_policy_injection_and_validation_never_mutate_cfg_or_context() -> void:
	var metadata: Dictionary = _policy()
	metadata.supported_schema_versions = ["next"]
	metadata.runnable_statuses = ["ready_for_test"]
	metadata.internal_terms.append("private_event")
	var validator = IdentityRules.new()
	assert_true(validator.configure(metadata))
	metadata.supported_schema_versions.clear()
	var cfg: Dictionary = _cfg()
	cfg.schema_version = "next"
	for card in cfg.bricks:
		card.status = "ready_for_test"
	cfg.bricks[2].player_text = ["private_event"]
	var context: Dictionary = _context()
	context.catalog.test_bolt.status = "ready_for_test"
	var before_cfg: Dictionary = cfg.duplicate(true)
	var before_context: Dictionary = context.duplicate(true)
	var result: Dictionary = validator.validate(cfg, context)
	assert_true(result.ok, "数据变化不需要代码枚举分支")
	assert_eq(result.diagnostics.size(), 1)
	_find(result, "V-017", "bricks[2].player_text")
	assert_eq(cfg, before_cfg)
	assert_eq(context, before_context)

func test_v007_dictionary_order_does_not_change_content() -> void:
	var cfg: Dictionary = _cfg()
	var baseline: Dictionary = {}
	var keys: Array = cfg.keys()
	keys.reverse()
	for key in keys:
		baseline[key] = cfg[key]
	var context: Dictionary = _context()
	context.definitions = [{"source": context.current_source, "cfg": baseline}]
	var validator = _validator()
	var result: Dictionary = validator.validate(cfg, context)
	assert_true(result.ok)
	assert_eq(result.diagnostics.size(), 0)

func test_v014_nested_lock_does_not_match_unrelated_suffix() -> void:
	var bad: Dictionary = _cfg()
	bad.bricks[2].locked_params = {"params.motion.speed": "固定速度"}
	bad.params.brick_overrides = [{"brick_index": 2, "values": {"motion": {"speed": 4}}}]
	_reject(bad, "V-014", "params.brick_overrides[0].values.motion.speed", "E-0009")
	bad.params.brick_overrides[0].values = {"other_motion": {"speed": 4}}
	_clean(bad)
	bad.bricks[2].locked_params = {"parts[1].type": "固定份类型"}
	bad.params.brick_overrides[0].values = {"parts": [{"amount": 5}]}
	_reject(bad, "V-014", "params.brick_overrides[0].values.parts", "E-0009")

func test_v018_sentence_limit_and_verbs_require_corresponding_behavior() -> void:
	for text in [["第一句。第二句！第三句？第四句。"], ["一", "二", "三", "四"], ["治疗目标。"]]:
		var cfg: Dictionary = _cfg()
		cfg.bricks[2].player_text = text
		var validator = _validator()
		var result: Dictionary = validator.validate(cfg, _context())
		assert_true(result.ok)
		assert_eq(result.diagnostics.size(), 1)
		var diagnostic = _find(result, "V-018", "bricks[2].player_text")
		if diagnostic != null:
			assert_eq(diagnostic.severity, Diag.SEV_WARN)
			assert_eq(diagnostic.code, "E-0010")
	var valid: Dictionary = _cfg()
	valid.bricks[2].player_text = ["造成伤害。", "第二句！", "第三句？"]
	_clean(valid)
	var context: Dictionary = _context()
	context.card_behaviors["bricks[2]"] = ["damage", "heal"]
	valid.bricks[2].player_text = ["治疗目标。"]
	var validator = _validator()
	var result: Dictionary = validator.validate(valid, context)
	assert_true(result.ok)
	assert_eq(result.diagnostics.size(), 0)

func test_v017_internal_terms_warn_without_blocking_save() -> void:
	for term in ["hit", "vanish", "range_end", "mutate_number"]:
		var cfg: Dictionary = _cfg()
		cfg.bricks[2].player_text = ["触发 " + term + "。"]
		var validator = _validator()
		var result: Dictionary = validator.validate(cfg, _context())
		assert_true(result.ok, "警告可保存但摘要必须可见")
		assert_eq(result.diagnostics.size(), 1)
		var diagnostic = _find(result, "V-017", "bricks[2].player_text")
		if diagnostic != null:
			assert_eq(diagnostic.severity, Diag.SEV_WARN)
			assert_eq(diagnostic.code, "E-0010")
	var valid: Dictionary = _cfg()
	valid.bricks[2].player_text = ["white shield"]
	_clean(valid)

func test_v016_derivation_trigger_and_default_references() -> void:
	for collection in ["derivations", "triggers"]:
		var bad: Dictionary = _cfg()
		bad.params[collection] = [{"produces": "child"}, {"produces": "absent"}]
		_reject(bad, "V-016", "params.%s[1].produces" % collection, "E-0007")
		bad.params[collection][1] = {}
		_reject(bad, "V-016", "params.%s[1].produces" % collection, "E-0007")
		bad.params[collection] = [{"produces": "child"}]
		_clean(bad)
	var default_bad: Dictionary = _cfg()
	default_bad.bricks[2].default_cfg.params.derivations = [{"produces": "absent"}]
	_reject(default_bad, "V-016", "bricks[2].default_cfg.params.derivations[0].produces", "E-0007")
	default_bad = _cfg()
	default_bad.bricks[2].default_cfg.derivations = [{"produces": "absent"}]
	_reject(default_bad, "V-016", "bricks[2].default_cfg.derivations[0].produces", "E-0007")
	var override_bad: Dictionary = _cfg()
	override_bad.params.brick_overrides = [{"brick_index": 2, "values": {"derivations": [{"produces": "absent"}]}}]
	_reject(override_bad, "V-016", "params.brick_overrides[0].values.derivations[0].produces", "E-0007")
	var cfg: Dictionary = _cfg()
	cfg.params.triggers = [{"produces": "child"}]
	var context: Dictionary = _context()
	context.outputs.child = [{"resolved": false}]
	var validator = _validator()
	var result: Dictionary = validator.validate(cfg, context)
	assert_false(result.ok)
	_find(result, "V-016", "params.triggers[0].produces")
	context.outputs.child = [{"resolved": true}, {"resolved": true}]
	result = validator.validate(cfg, context)
	assert_false(result.ok, "重复定义不能随意挑一个")
	_find(result, "V-016", "params.triggers[0].produces")

func test_v015_index_missing_out_of_bounds_duplicate_and_id_mismatch() -> void:
	for index in [-1, 3, 0.5, "2", null]:
		var bad: Dictionary = _cfg()
		bad.params.brick_overrides = [{"brick_index": index, "values": {"projectile_speed": 2}}]
		_reject(bad, "V-015", "params.brick_overrides[0].brick_index", "E-0007")
	var duplicate: Dictionary = _cfg()
	duplicate.params.brick_overrides = [{"brick_index": 2, "values": {"projectile_speed": 2}}, {"brick_index": 2, "values": {"projectile_speed": 3}}]
	_reject(duplicate, "V-015", "params.brick_overrides[1].brick_index", "E-0007")
	var mismatch: Dictionary = _cfg()
	mismatch.params.brick_overrides = [{"brick_index": 2, "brick_id": "other", "values": {}}]
	_reject(mismatch, "V-015", "params.brick_overrides[0].brick_index", "E-0007")
	var valid: Dictionary = _cfg()
	valid.params.brick_overrides = [{"brick_index": 0, "values": {}}, {"brick_index": 2, "values": {}}]
	_clean(valid)

func test_v014_locked_override_reports_actual_leaf_not_parameter_object() -> void:
	var bad: Dictionary = _cfg()
	bad.params.brick_overrides = [{"brick_index": 2, "values": {"lifetime_ticks": 99}}]
	_reject(bad, "V-014", "params.brick_overrides[0].values.lifetime_ticks", "E-0009")
	bad.params.brick_overrides[0].values = {"params": {"lifetime_ticks": 99}}
	_reject(bad, "V-014", "params.brick_overrides[0].values.params.lifetime_ticks", "E-0009")
	bad.params = {"lifetime_ticks": 99}
	_reject(bad, "V-014", "params.lifetime_ticks", "E-0009")
	var valid: Dictionary = _cfg()
	valid.params.brick_overrides = [{"brick_index": 2, "values": {"projectile_speed": 99}}]
	_clean(valid)

func test_v013_all_twelve_missing_slots_are_expanded_at_index_two() -> void:
	var required: Array = ["brick_id", "name", "tagline", "carrier", "summary", "default_cfg", "author_params", "locked_params", "relic_params", "presentation", "player_text", "status"]
	assert_eq(required.size(), 12)
	for field in required:
		var bad: Dictionary = _cfg()
		bad.bricks[2].erase(field)
		var diagnostic = _reject(bad, "V-013", "bricks[2]." + field, "E-0006")
		if diagnostic != null:
			assert_eq(diagnostic.actual, "未填写")
	_clean(_cfg())

func test_v012_candidate_reserved_and_catalog_status_cannot_be_forged() -> void:
	for status in ["候选", "预留"]:
		var bad: Dictionary = _cfg()
		bad.bricks[2].status = status
		_reject(bad, "V-012", "bricks[2].status", "E-0008")
	var context: Dictionary = _context()
	context.catalog.test_bolt.status = "候选"
	var validator = _validator()
	var result: Dictionary = validator.validate(_cfg(), context)
	assert_false(result.ok, "不能只信任 CFG 自报已登记")
	_find(result, "V-012", "bricks[2].status")
	_clean(_cfg())

func test_v011_brick_reference_and_version_resolution() -> void:
	var bad: Dictionary = _cfg()
	bad.bricks[2].brick_id = "unknown_brick"
	_reject(bad, "V-011", "bricks[2].brick_id", "E-0007")
	var context: Dictionary = _context()
	context.catalog.test_bolt.resolved = false
	var validator = _validator()
	var result: Dictionary = validator.validate(_cfg(), context)
	assert_false(result.ok)
	_find(result, "V-011", "bricks[2].brick_id")
	_clean(_cfg())

func test_v010_tag_reference_missing_and_duplicate() -> void:
	var bad: Dictionary = _cfg()
	bad.meta.tags = ["ranged", "absent"]
	_reject(bad, "V-010", "meta.tags[1]", "E-0007")
	bad.meta.tags = ["ranged", "ranged"]
	_reject(bad, "V-010", "meta.tags[1]", "E-0007")
	_clean(_cfg())

func test_v009_pool_reference_missing_and_duplicate() -> void:
	var bad: Dictionary = _cfg()
	bad.meta.pools = ["starter", "absent"]
	var diagnostic = _reject(bad, "V-009", "meta.pools[1]", "E-0007")
	if diagnostic != null:
		assert_eq(diagnostic.actual, "absent")
	bad.meta.pools = ["starter", "starter"]
	_reject(bad, "V-009", "meta.pools[1]", "E-0007")
	_clean(_cfg())

func test_v008_display_name_not_blank() -> void:
	for name_value in ["", " \t\n", null]:
		var bad: Dictionary = _cfg()
		bad.meta.name = name_value
		_reject(bad, "V-008", "meta.name", "E-0006")
	_clean(_cfg())

func test_v007_version_format_and_same_version_content_conflict() -> void:
	var bad: Dictionary = _cfg()
	bad.meta.version = "1.0"
	_reject(bad, "V-007", "meta.version", "E-0005")
	var cfg: Dictionary = _cfg()
	var context: Dictionary = _context()
	context.definitions = [{"source": context.current_source, "cfg": cfg.duplicate(true)}]
	cfg.meta.name = "修改显示名"
	var validator = _validator()
	var result: Dictionary = validator.validate(cfg, context)
	assert_false(result.ok)
	_find(result, "V-007", "meta.version")
	cfg.meta.version = "1.0.1"
	result = validator.validate(cfg, context)
	assert_true(result.ok)
	assert_eq(result.diagnostics.size(), 0)

func test_v006_short_name_and_variant_reconstruct_without_guessing() -> void:
	var bad: Dictionary = _cfg()
	bad.meta.short_name = "wrong"
	_reject(bad, "V-006", "meta.short_name", "E-0004")
	bad = _cfg()
	bad.meta.variant = "ice"
	_reject(bad, "V-006", "meta.variant", "E-0004")
	var valid: Dictionary = _cfg()
	valid.meta.erase("variant")
	_clean(valid)
	valid.meta.short_name = "long_bolt"
	valid.skill_id = "mage_active_long_bolt"
	_clean(valid)

func test_v005_category_registered_and_matches_id() -> void:
	for category in ["other", "passive"]:
		var bad: Dictionary = _cfg()
		bad.meta.category = category
		_reject(bad, "V-005", "meta.category", "E-0004")
	_clean(_cfg())

func test_v004_role_registered_and_matches_id() -> void:
	for role in ["unknown", "knight"]:
		var bad: Dictionary = _cfg()
		bad.meta.role = role
		_reject(bad, "V-004", "meta.role", "E-0004")
	_clean(_cfg())

func test_v003_duplicate_id_excludes_current_source_only() -> void:
	var cfg: Dictionary = _cfg()
	var context: Dictionary = _context()
	context.definitions = [{"source": "res://other.yaml", "cfg": cfg.duplicate(true)}]
	var validator = _validator()
	var rejected: Dictionary = validator.validate(cfg, context)
	assert_false(rejected.ok)
	_find(rejected, "V-003", "skill_id")
	context.definitions[0].source = context.current_source
	var unchanged: Dictionary = validator.validate(cfg, context)
	assert_true(unchanged.ok)
	assert_eq(unchanged.diagnostics.size(), 0)

func test_v002_identity_format() -> void:
	for value in ["Mage_active_bolt", "mage", "mage__bolt", "mage_active_bolt-"]:
		var bad: Dictionary = _cfg()
		bad.skill_id = value
		_reject(bad, "V-002", "skill_id", "E-0002")
	var valid: Dictionary = _cfg()
	valid.meta.short_name = "long_bolt"
	valid.meta.variant = "ice_blue"
	valid.skill_id = "mage_active_long_bolt_ice_blue"
	_clean(valid)

func test_v001_schema_version_missing_type_and_supported_boundary() -> void:
	var missing: Dictionary = _cfg()
	missing.erase("schema_version")
	var diagnostic = _reject(missing, "V-001", "schema_version", "E-0001")
	if diagnostic != null:
		assert_eq(diagnostic.actual, "未填写")
	for value in [null, 0.1, "0.2"]:
		var bad: Dictionary = _cfg()
		bad.schema_version = value
		_reject(bad, "V-001", "schema_version", "E-0001")
	_clean(_cfg())

# ---- WorkBuddy 复核补测（U-10）：产出引用落点由元数据别名补齐，生产元数据资产可装配 ----

func test_production_metadata_asset_configures_validator() -> void:
	var meta: Dictionary = IdentityMeta.load_metadata()
	assert_false(meta.is_empty(), "生产元数据必须可从 res://data/identity_meta.json 载入")
	assert_true(IdentityMeta.is_available())
	var validator = IdentityRules.new()
	assert_true(validator.configure(meta), validator.last_error)
	var result: Dictionary = validator.validate(_cfg(), _context())
	assert_true(result.ok, str(result.diagnostics))
	assert_eq(result.diagnostics.size(), 0)
	assert_eq(result.notices.size(), 0, str(result.notices))
	# 真源口径：四类类别、十二个冻结槽位、只放行已登记、至多三句
	assert_eq(meta.categories, ["active", "passive", "crystal", "relic"])
	assert_eq(meta.required_card_fields.size(), 12)
	assert_eq(meta.runnable_statuses, ["已登记"])
	assert_eq(int(meta.max_player_sentences), 3)
	var schema_bad: Dictionary = _cfg()
	schema_bad.meta.category = "ultimate"
	schema_bad.bricks[1].author_params = ["speed"]
	result = validator.validate(schema_bad, _context())
	assert_false(result.ok)
	_find(result, "V-005", "meta.category")

func test_v016_produce_alias_covers_schema_field_names() -> void:
	var policy: Dictionary = _policy()
	policy.v016_produce_paths = {
		"derivations": [{"field": "child_template", "required": true}],
		"triggers": [{"field": "action_profile", "required": true}, {"field": "produces", "required": false}]
	}
	var validator = IdentityRules.new()
	assert_true(validator.configure(policy), validator.last_error)
	# 第 14 章统称 produces 在派生上落到 Schema 的 child_template（14.1：路径以第 16 章落点为准）
	var legacy: Dictionary = _cfg()
	legacy.params.derivations = [{"produces": "absent"}]
	var result: Dictionary = validator.validate(legacy, _context())
	assert_false(result.ok)
	_find(result, "V-016", "params.derivations[0].child_template")
	var deriv: Dictionary = _cfg()
	deriv.params.derivations = [{"child_template": "absent"}]
	result = validator.validate(deriv, _context())
	assert_false(result.ok)
	_find(result, "V-016", "params.derivations[0].child_template")
	var trig: Dictionary = _cfg()
	trig.params.triggers = [{"action_profile": "absent"}]
	result = validator.validate(trig, _context())
	assert_false(result.ok)
	_find(result, "V-016", "params.triggers[0].action_profile")
	# produces 是可选数组：逐项定位，缺省不报错
	var list_bad: Dictionary = _cfg()
	list_bad.params.triggers = [{"action_profile": "child", "produces": ["child", "absent"]}]
	result = validator.validate(list_bad, _context())
	assert_false(result.ok)
	_find(result, "V-016", "params.triggers[0].produces[1]")
	var ok: Dictionary = _cfg()
	ok.params.derivations = [{"child_template": "child"}]
	ok.params.triggers = [{"action_profile": "child"}, {"action_profile": "child", "produces": []}]
	result = validator.validate(ok, _context())
	assert_true(result.ok, str(result.diagnostics))
	# 非法别名必须显式失败，不能静默忽略
	var broken: Dictionary = _policy()
	broken.v016_produce_paths = {"derivations": []}
	var broken_validator = IdentityRules.new()
	assert_false(broken_validator.configure(broken))
	assert_true(broken_validator.last_error.contains("产出引用"))
