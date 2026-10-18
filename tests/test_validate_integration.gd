extends GutTest

const Validator = preload("res://skill_core/validate/validator.gd")
const SkillApi = preload("res://skill_core/api/skill_api.gd")
const Diag = preload("res://skill_core/api/diagnostic.gd")
const IdentityRules = preload("res://skill_core/validate/rules/r_identity.gd")
const IdentityMeta = preload("res://skill_core/validate/identity_meta.gd")
const TypesRules = preload("res://skill_core/validate/rules/r_types.gd")
const ModifierRules = preload("res://skill_core/validate/rules/r_modifier.gd")
const PresentationRules = preload("res://skill_core/validate/rules/r_present.gd")

const RANGES: Array[Dictionary] = [
	{"name": "identity", "first": 1, "last": 18},
	{"name": "types", "first": 19, "last": 38},
	{"name": "modifier", "first": 39, "last": 69},
	{"name": "presentation", "first": 70, "last": 84}
]

class DuplicatingCard extends RefCounted:
	var configured: bool = true
	var inner: Variant

	func validate(cfg: Dictionary, context: Dictionary) -> Dictionary:
		var result: Dictionary = inner.validate(cfg, context)
		var diagnostics_value: Variant = result.get("diagnostics", null)
		var diagnostics: Array = diagnostics_value if diagnostics_value is Array else []
		var duplicated: Array = diagnostics.duplicate(true)
		duplicated.append_array(diagnostics.duplicate(true))
		var notices_value: Variant = result.get("notices", null)
		var notices: Array = notices_value if notices_value is Array else []
		return {"ok": result.get("ok", false), "diagnostics": duplicated,
			"notices": notices}

func _json(name: String) -> Dictionary:
	var file: FileAccess = FileAccess.open("res://data/" + name + ".json", FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

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
	return {"brick_id": "test_bolt", "name": "测试卡", "tagline": "测试",
		"carrier": "independent", "summary": "测试用行为",
		"default_cfg": {"params": {"lifetime_ticks": 60}}, "author_params": [],
		"locked_params": {"lifetime_ticks": "固定寿命"}, "relic_params": {},
		"presentation": [], "player_text": ["造成伤害。"], "status": "已登记"}

func _cfg() -> Dictionary:
	return {
		"schema_version": "0.1", "skill_id": "mage_active_bolt",
		"meta": {"role": "mage", "category": "active", "short_name": "bolt", "variant": "", "name": "飞弹", "version": "1.0.0", "author": "test", "pools": ["starter"], "tags": ["ranged"]},
		"bricks": [_card(), _card(), _card()],
		"params": {"projectile_speed": 10.0, "max_generation": 1, "cast_budget": 16, "modifiers": [], "exposed_fields": [], "triggers": [], "derivations": []},
		"presentation": {"fx": {}, "sfx": {}, "anim": {}, "trail": {}, "camera": {"enabled": false}, "damage_number": {}, "status_icon": {}},
		"runtime_hints": {}
	}

func _context(revision: int = 1) -> Dictionary:
	return {
		"draft_revision": revision,
		"submitted_paths": ["schema_version", "skill_id", "meta", "bricks", "params", "presentation", "runtime_hints"],
		"roles": ["mage", "knight"], "pools": ["starter"], "tags": ["ranged"],
		"catalog": {"test_bolt": {"resolved": true, "status": "已登记"}},
		"card_behaviors": {"bricks[0]": ["damage"], "bricks[1]": ["damage"], "bricks[2]": ["damage"]},
		"outputs": {"child": [{"resolved": true}]}, "definitions": [],
		"current_source": "res://data/skills/test.yaml",
		"capabilities": {"params": {"summon": false}}, "item_category": "relic", "exposed": {},
		"live_requests": [], "stack_operations": {}, "set_counts": {}, "reset_writes": [],
		"derivation_analysis": {"truncated_paths": []},
		"budget_estimate": {"total_requested_instances": 1, "capped": false, "guarantee_bindings": []},
		"produced_types": {"spawn_ref": "effect_template"}, "record_fields": _json("record_fields"),
		"condition_registry": {"condition_ref": {"accessible_fields": ["source", "target"], "part_filters": []}},
		"self_chain_evidence": {"depth_bound": true, "source_mark_bound": true, "cooldown_bound": true, "budget_bound": true, "worst_case_note_complete": true},
		"project_limits": {"defaults": {"cast_budget": 16}, "hard_caps": {"max_generation": 4, "cast_budget": 64, "max_chain_depth": 8}},
		"player_attribute_bindings": {}, "resource_resolution": {}, "default_applications": [],
		"baseline_version_state": {"baseline_version": "1", "current_underlying_version": "1", "operation": "save"},
		"migration_state": {"migrating": false, "source_version": "0.1", "target_version": "0.1", "path_complete": true, "lossless": true},
		"probe_credentials": {}, "preview_fingerprint": {"preview_fingerprint": "a", "current_fingerprint": "a", "operation": "save"},
		"cross_card_facts": {}
	}

func _real_cards() -> Dictionary:
	var identity: IdentityRules = IdentityRules.new()
	assert_true(identity.configure(IdentityMeta.load_metadata()), identity.last_error)
	var types: TypesRules = TypesRules.new()
	assert_true(types.configure(_json("params_meta")), types.last_error)
	var modifier: ModifierRules = ModifierRules.new()
	assert_true(modifier.configure(_json("params_meta")), modifier.last_error)
	var present: PresentationRules = PresentationRules.new()
	assert_true(present.configure(_json("presentation_meta")), present.last_error)
	return {"identity": identity, "types": types, "modifier": modifier, "presentation": present}

func _validator(cards: Dictionary) -> Validator:
	var validator: Validator = Validator.new()
	var spec: Dictionary = {"cards": [], "groups": [], "stages": {}}
	for entry in RANGES:
		var name: String = str(entry["name"])
		spec["cards"].append({"name": name, "card": cards[name]})
		spec["groups"].append({"first": int(entry["first"]), "last": int(entry["last"]), "card": name, "stages": []})
	for stage in [SkillApi.STAGE_FILLING, SkillApi.STAGE_CARD, SkillApi.STAGE_ASSEMBLY, SkillApi.STAGE_SAVE, SkillApi.STAGE_LOAD, SkillApi.STAGE_PREVIEW]:
		var refs: Array[int] = []
		for index in range(RANGES.size()):
			refs.append(index)
		spec["stages"][stage] = refs
	assert_true(validator.configure(spec), validator.last_error)
	return validator

func _has_range(result: Dictionary, first: int, last: int) -> bool:
	for item in result.diagnostics:
		var rule_id: String = str(item.rule_id if item is Diag else item.get("rule_id", ""))
		var suffix: String = rule_id.trim_prefix("V-")
		if rule_id.begins_with("V-") and suffix.is_valid_int() and suffix.to_int() >= first and suffix.to_int() <= last:
			return true
	return false

func _ids_in(result: Dictionary, first: int, last: int) -> Array:
	var found: Array = []
	for item in result.diagnostics:
		var rule_id: String = str(item.rule_id) if not (item is Dictionary) else str(item.get("rule_id", ""))
		var suffix: String = rule_id.trim_prefix("V-")
		if rule_id.begins_with("V-") and suffix.is_valid_int() and suffix.to_int() >= first and suffix.to_int() <= last and not found.has(rule_id):
			found.append(rule_id)
	return found

# 相对基线的增量：只有在破坏后才出现的规则号，才算这条用例被真正触发
func _new_in_range(baseline: Dictionary, result: Dictionary, first: int, last: int) -> Array:
	var before: Array = _ids_in(baseline, first, last)
	var added: Array = []
	for rule_id in _ids_in(result, first, last):
		if not before.has(rule_id):
			added.append(rule_id)
	return added

func test_each_real_rule_card_is_configured_and_triggered_through_validator() -> void:
	var cards: Dictionary = _real_cards()
	var validator: Validator = _validator(cards)
	# 基线：合法 CFG 下各区间已有的诊断。断言一律取「破坏后新增」的差集，
	# 避免区间里本就存在的规则号让断言恒真（审核方反向对照发现 modifier 区间基线非空）。
	var baseline: Dictionary = validator.validate(_cfg(), SkillApi.STAGE_SAVE, _context())

	var cfg: Dictionary = _cfg()
	cfg.schema_version = "unsupported"
	var result: Dictionary = validator.validate(cfg, SkillApi.STAGE_SAVE, _context())
	assert_true(_new_in_range(baseline, result, 1, 18).size() > 0, "identity 区间未因 schema_version 非法而新增诊断")

	cfg = _cfg()
	cfg.params.tick_order = 1
	result = validator.validate(cfg, SkillApi.STAGE_SAVE, _context())
	assert_true(_new_in_range(baseline, result, 19, 38).size() > 0, "types 区间未因 tick_order 而新增诊断")

	cfg = _cfg()
	cfg.params.modifiers = [{"modifier_id": "m0", "permission": "unknown", "scope": "own_skill", "inheritable": false, "targets": [], "stack_rule": {"operation_profile": "add_ref"}}]
	result = validator.validate(cfg, SkillApi.STAGE_SAVE, _context())
	assert_true(_new_in_range(baseline, result, 39, 69).size() > 0, "modifier 区间未因 permission=unknown 而新增诊断")

	cfg = _cfg()
	cfg.presentation.erase("fx")
	result = validator.validate(cfg, SkillApi.STAGE_SAVE, _context())
	assert_true(_new_in_range(baseline, result, 70, 84).size() > 0, "presentation 区间未因缺失 fx 段而新增诊断")

func test_all_six_stages_run_all_real_cards_with_contracts() -> void:
	var validator: Validator = _validator(_real_cards())
	for stage in [SkillApi.STAGE_FILLING, SkillApi.STAGE_CARD, SkillApi.STAGE_ASSEMBLY, SkillApi.STAGE_SAVE, SkillApi.STAGE_LOAD, SkillApi.STAGE_PREVIEW]:
		var result: Dictionary = validator.validate(_cfg(), stage, _context())
		assert_true(result.has("diagnostics"))
		assert_true(result.diagnostics is Array)
		assert_eq(result.revision, 1)

func test_real_diagnostics_are_sorted_and_duplicate_evidence_is_returned() -> void:
	var real: IdentityRules = _real_cards()["identity"]
	var duplicate: DuplicatingCard = DuplicatingCard.new()
	duplicate.inner = real
	var validator: Validator = Validator.new()
	var spec: Dictionary = {"cards": [{"name": "identity", "card": duplicate}],
		"groups": [{"first": 1, "last": 18, "card": "identity", "stages": []}],
		"stages": {"filling": [0], "card": [0], "assembly": [0], "save": [0], "load": [0], "preview": [0]}}
	assert_true(validator.configure(spec), validator.last_error)
	var cfg: Dictionary = _cfg()
	cfg.schema_version = "unsupported"
	var result: Dictionary = validator.validate(cfg, SkillApi.STAGE_SAVE, _context())
	assert_true(result.removed > 0, "重复真实诊断必须由排序器去重")
	assert_true(result.diagnostics.size() > 0)
	for index in range(1, result.diagnostics.size()):
		assert_true(result.diagnostics[index - 1].severity <= result.diagnostics[index].severity)

func test_real_card_without_configure_fails_explicitly() -> void:
	var identity: IdentityRules = IdentityRules.new()
	var validator: Validator = Validator.new()
	var spec: Dictionary = {"cards": [{"name": "identity", "card": identity}],
		"groups": [{"first": 1, "last": 18, "card": "identity", "stages": []}],
		"stages": {"filling": [0], "card": [0], "assembly": [0], "save": [0], "load": [0], "preview": [0]}}
	assert_false(validator.configure(spec))
	assert_true(validator.last_error.contains("configure"))

func test_real_cards_do_not_mutate_cfg_or_context() -> void:
	var validator: Validator = _validator(_real_cards())
	var cfg: Dictionary = _cfg()
	var context: Dictionary = _context()
	var before_cfg: Dictionary = cfg.duplicate(true)
	var before_context: Dictionary = context.duplicate(true)
	validator.validate(cfg, SkillApi.STAGE_SAVE, context)
	assert_eq(cfg, before_cfg)
	assert_eq(context, before_context)
