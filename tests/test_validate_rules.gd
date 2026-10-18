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
		"default_cfg": {"params": {"lifetime_ticks": 60}}, "author_params": [], "locked_params": {"lifetime_ticks": "固定寿命"}, "relic_params": {},
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
		"produced_types": {"spawn_ref": "effect_template"},
		"record_fields": _json("record_fields"),
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

func _tokens(path: String) -> Array:
	var result: Array = []
	for part in path.split("."):
		var rest: String = part
		var open: int = rest.find("[")
		if open < 0:
			result.append(rest)
			continue

		result.append(rest.substr(0, open))
		while open >= 0:
			var close: int = rest.find("]", open)
			assert_true(close > open, "夹具路径下标无效: " + path)
			result.append(rest.substr(open + 1, close - open - 1).to_int())
			open = rest.find("[", close)
	return result

func _decode(value: Variant) -> Variant:
	if value is Array:
		var array_value: Array = []
		for item in value:
			array_value.append(_decode(item))
		return array_value
	if value is Dictionary:
		if value.has("$int"):
			return int(value["$int"])
		if value.has("$float"):
			return float(value["$float"])
		var dict_value: Dictionary = {}
		for key in value:
			dict_value[key] = _decode(value[key])
		return dict_value
	return value

func _patch(root: Dictionary, path: String, value: Variant, erase: bool) -> void:
	var parts: Array = _tokens(path)
	assert_true(not parts.is_empty(), "夹具路径不能为空")
	var current: Variant = root
	for index in range(parts.size() - 1):
		var token: Variant = parts[index]
		var next_token: Variant = parts[index + 1]
		if current is Dictionary:
			var child: Variant = current.get(token, null)
			if child == null:
				child = [] if next_token is int else {}
				current[token] = child
			current = child
		elif current is Array and token is int:
			assert_true(token >= 0 and token < current.size(), "夹具数组下标越界: " + path)
			current = current[token]
		else:
			assert_true(false, "夹具路径无法继续: " + path)
			return
	var final_token: Variant = parts[parts.size() - 1]
	if current is Dictionary:
		if erase:
			current.erase(final_token)
		else:
			current[final_token] = value
	elif current is Array and final_token is int:
		assert_true(final_token >= 0 and final_token < current.size(), "夹具数组末段越界: " + path)
		if not erase:
			current[final_token] = value
	else:
		assert_true(false, "夹具路径末段无效: " + path)

func _apply_patches(cfg: Dictionary, context: Dictionary, patches: Array) -> void:
	for patch_value in patches:
		var patch: Dictionary = patch_value
		var scope: String = str(patch.get("scope", ""))
		var path: String = str(patch.get("path", ""))
		var erase: bool = str(patch.get("op", "set")) == "erase"
		var value: Variant = _decode(patch.get("value", null))
		if scope == "cfg":
			_patch(cfg, path, value, erase)
		elif scope == "context":
			_patch(context, path, value, erase)
		else:
			assert_true(false, "夹具 scope 无效: " + scope)

func _severity_from_csv() -> Dictionary:
	var result: Dictionary = {}
	var file: FileAccess = FileAccess.open("res://data/validation_rules.csv", FileAccess.READ)
	assert_true(file != null, "validation_rules.csv 必须存在")
	while not file.eof_reached():
		var line: String = file.get_line()
		if line.is_empty() or line.begins_with("rule_id,"):
			continue
		var columns: PackedStringArray = line.split(",")
		assert_true(columns.size() >= 3, "CSV 规则行缺列: " + line)
		result[columns[0]] = columns[2]
	return result

func _expected_severity(rule_id: String, severities: Dictionary) -> int:
	assert_true(severities.has(rule_id), "CSV 缺少严重度: " + rule_id)
	var text: String = str(severities[rule_id])
	if text == "阻止保存":
		return Diag.SEV_BLOCK
	if text == "警告":
		return Diag.SEV_WARN
	if text == "提示":
		return Diag.SEV_HINT
	assert_true(false, "CSV 严重度未登记: " + text)
	return Diag.SEV_BLOCK

func _find_rule(result: Dictionary, rule_id: String) -> Array:
	var found: Array = []
	for item in result.diagnostics:
		var actual_id: String = str(item.rule_id) if item is Diag else str(item.get("rule_id", ""))
		if actual_id == rule_id:
			found.append(item)
	return found

func _has_block(result: Dictionary) -> bool:
	for item in result.diagnostics:
		var severity: Variant = item.severity if item is Diag else item.get("severity", null)
		if severity == Diag.SEV_BLOCK:
			return true
	return false

func test_every_rule_fixture_triggers_and_adjacent_boundary_is_clean() -> void:
	var fixture: Dictionary = _json("validate_fixtures")
	var cases_value: Variant = fixture.get("cases", null)
	assert_true(cases_value is Array and not cases_value.is_empty(), "反例夹具不能为空")
	var cases: Array = cases_value
	var severities: Dictionary = _severity_from_csv()
	assert_eq(cases.size(), severities.size(), "夹具条数必须与 CSV 规则条数一致")
	var seen: Dictionary = {}
	var validator: Validator = _validator(_real_cards())
	for case_value in cases:
		var entry: Dictionary = case_value
		var rule_id: String = str(entry.get("rule_id", ""))
		assert_false(rule_id.is_empty(), "夹具缺少 rule_id")
		assert_false(seen.has(rule_id), "夹具重复 rule_id: " + rule_id)
		seen[rule_id] = true
		var cfg: Dictionary = _cfg()
		var context: Dictionary = _context()
		_apply_patches(cfg, context, entry.get("negative", []))
		var result: Dictionary = validator.validate(cfg, SkillApi.STAGE_SAVE, context)
		var matches: Array = _find_rule(result, rule_id)
		assert_true(not matches.is_empty(), "%s 反例未触发；实际=%s" % [rule_id, str(result.diagnostics)])
		var expected: int = _expected_severity(rule_id, severities)
		for diagnostic in matches:
			var actual_severity: int = diagnostic.severity if diagnostic is Diag else int(diagnostic.get("severity", -1))
			assert_eq(actual_severity, expected, "%s 严重度必须取 CSV" % rule_id)
		var boundary_cfg: Dictionary = _cfg()
		var boundary_context: Dictionary = _context()
		_apply_patches(boundary_cfg, boundary_context, entry.get("boundary", []))
		var boundary: Dictionary = validator.validate(boundary_cfg, SkillApi.STAGE_SAVE, boundary_context)
		assert_true(_find_rule(boundary, rule_id).is_empty(), "%s 相邻合法边界仍命中；实际=%s" % [rule_id, str(boundary.diagnostics)])
		assert_false(_has_block(boundary), "%s 相邻合法边界出现 BLOCK；实际=%s" % [rule_id, str(boundary.diagnostics)])
	print("已覆盖 V 条数 = %d / %d" % [seen.size(), severities.size()])
	assert_eq(seen.size(), severities.size(), "已覆盖 V 条数必须等于 CSV 条数")

func test_fixture_validation_is_read_only_and_uses_all_six_stage_contracts() -> void:
	var validator: Validator = _validator(_real_cards())
	var cfg: Dictionary = _cfg()
	var context: Dictionary = _context()
	var before_cfg: Dictionary = cfg.duplicate(true)
	var before_context: Dictionary = context.duplicate(true)
	for stage in [SkillApi.STAGE_FILLING, SkillApi.STAGE_CARD, SkillApi.STAGE_ASSEMBLY, SkillApi.STAGE_SAVE, SkillApi.STAGE_LOAD, SkillApi.STAGE_PREVIEW]:
		var result: Dictionary = validator.validate(cfg, stage, context)
		assert_true(result.has("diagnostics"))
		assert_true(result.diagnostics is Array)
	assert_eq(cfg, before_cfg)
	assert_eq(context, before_context)
