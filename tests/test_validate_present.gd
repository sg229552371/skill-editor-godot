extends GutTest

const Rules = preload("res://skill_core/validate/rules/r_present.gd")
const Diag = preload("res://skill_core/api/diagnostic.gd")

func _meta() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/presentation_meta.json"))
	return data if data is Dictionary else {}

func _cfg() -> Dictionary:
	return {"schema_version": "0.1", "meta": {"version": "1", "player_attributes": []}, "presentation": {
		"fx": {}, "sfx": {}, "anim": {}, "trail": {}, "camera": {"enabled": false},
		"damage_number": {}, "status_icon": {}}}

func _context() -> Dictionary:
	return {"player_attribute_bindings": {}, "resource_resolution": {}, "probe_credentials": {},
		"baseline_version_state": {"baseline_version": "1", "current_underlying_version": "1", "operation": "save"},
		"default_applications": [], "migration_state": {"migrating": false, "source_version": "0.1", "target_version": "0.1", "path_complete": true, "lossless": true},
		"preview_fingerprint": {"preview_fingerprint": "a", "current_fingerprint": "a", "operation": "save"}}

func _rules() -> Rules:
	var rules: Rules = Rules.new()
	assert_true(rules.configure(_meta()), rules.last_error)
	return rules

func _has(result: Dictionary, rule_id: String, path: String, severity: int) -> void:
	var found: bool = false
	for diagnostic in result.diagnostics:
		if diagnostic.rule_id == rule_id and diagnostic.path == path:
			found = true
			assert_eq(diagnostic.severity, severity)
			assert_false(diagnostic.hint.is_empty())
	assert_true(found, "%s @ %s; actual=%s" % [rule_id, path, str(result.diagnostics)])

func _no_rule(result: Dictionary, rule_id: String) -> void:
	for diagnostic in result.diagnostics:
		assert_ne(diagnostic.rule_id, rule_id)

func test_setup_failure_is_explicit() -> void:
	var rules: Rules = Rules.new()
	assert_false(rules.configure({}))
	assert_false(rules.validate(_cfg(), _context()).ok)
	assert_true(rules.configure(_meta()))
	assert_eq(rules._groups[0].rules.size(), 15)
	var broken: Dictionary = _meta()
	broken.erase("section_enable")
	assert_false(Rules.new().configure(broken))
	broken = _meta()
	broken["additional_properties"] = true
	assert_false(Rules.new().configure(broken))

func test_v070_seven_sections_unknown_eighth_and_schema_types() -> void:
	var cfg: Dictionary = _cfg()
	for section in _meta().required_sections:
		var copy: Dictionary = cfg.duplicate(true)
		copy.presentation.erase(section)
		_has(_rules().validate(copy, _context()), "V-070", "presentation." + str(section), Diag.SEV_BLOCK)
	cfg.presentation["eighth"] = {}
	_has(_rules().validate(cfg, _context()), "V-070", "presentation.eighth", Diag.SEV_BLOCK)
	cfg = _cfg()
	cfg.presentation.fx["unknown"] = 1
	_has(_rules().validate(cfg, _context()), "V-070", "presentation.fx.unknown", Diag.SEV_BLOCK)
	cfg = _cfg()
	cfg.presentation.camera["shake_amplitude"] = NAN
	_has(_rules().validate(cfg, _context()), "V-070", "presentation.camera.shake_amplitude", Diag.SEV_BLOCK)
	cfg.presentation.camera["shake_amplitude"] = 0
	assert_true(_rules().validate(cfg, _context()).ok)

func test_v071_debug_forbidden_natural_reason_legal() -> void:
	var cfg: Dictionary = _cfg()
	cfg.presentation.damage_number["source"] = "debug_record"
	_has(_rules().validate(cfg, _context()), "V-071", "presentation.damage_number.source", Diag.SEV_BLOCK)
	cfg = _cfg()
	cfg.presentation.fx["vanish_by_reason"] = {"debug": {}}
	_has(_rules().validate(cfg, _context()), "V-071", "presentation.fx.vanish_by_reason.debug", Diag.SEV_BLOCK)
	cfg.presentation.fx["vanish_by_reason"] = {"hit_end": {}}
	_no_rule(_rules().validate(cfg, _context()), "V-071")
	cfg = _cfg()
	cfg.presentation.damage_number["source"] = "hit_settled"
	_no_rule(_rules().validate(cfg, _context()), "V-071")

func test_v072_callback_and_alignment_actual_key() -> void:
	var cfg: Dictionary = _cfg()
	cfg.presentation.anim["callback_mode"] = "logic"
	_has(_rules().validate(cfg, _context()), "V-072", "presentation.anim.callback_mode", Diag.SEV_BLOCK)
	cfg.presentation.anim["callback_mode"] = "presentation_only"
	_no_rule(_rules().validate(cfg, _context()), "V-072")
	cfg.presentation.anim["alignments"] = [{"shot_tick": 1, "drive_shot": true}]
	_has(_rules().validate(cfg, _context()), "V-072", "presentation.anim.alignments[0].drive_shot", Diag.SEV_BLOCK)

func test_v073_disabled_zero_enabled_zero_and_type_boundary() -> void:
	var cfg: Dictionary = _cfg()
	cfg.presentation.sfx["max_concurrency"] = 0
	assert_true(_rules().validate(cfg, _context()).ok)
	cfg.presentation.sfx["spawn"] = [{}]
	_has(_rules().validate(cfg, _context()), "V-073", "presentation.sfx.max_concurrency", Diag.SEV_BLOCK)
	cfg.presentation.sfx["max_concurrency"] = 1
	_no_rule(_rules().validate(cfg, _context()), "V-073")
	cfg.presentation.sfx["max_concurrency"] = "1"
	_has(_rules().validate(cfg, _context()), "V-073", "presentation.sfx.max_concurrency", Diag.SEV_BLOCK)
	cfg.presentation.sfx["max_concurrency"] = -1
	_has(_rules().validate(cfg, _context()), "V-070", "presentation.sfx.max_concurrency", Diag.SEV_BLOCK)

func test_v074_enabled_alignment_requires_both_fields() -> void:
	var cfg: Dictionary = _cfg()
	cfg.presentation.anim["cast_clip"] = {"id": "cast"}
	_has(_rules().validate(cfg, _context()), "V-074", "presentation.anim.logic_release_tick", Diag.SEV_BLOCK)
	_has(_rules().validate(cfg, _context()), "V-074", "presentation.anim.release_frame", Diag.SEV_BLOCK)
	cfg.presentation.anim["logic_release_tick"] = 0
	cfg.presentation.anim["release_frame"] = 0
	_no_rule(_rules().validate(cfg, _context()), "V-074")
	cfg.presentation.anim["release_frame"] = "0"
	_has(_rules().validate(cfg, _context()), "V-074", "presentation.anim.release_frame", Diag.SEV_BLOCK)

func test_v075_all_carrier_combinations_come_from_policy() -> void:
	var policy: Dictionary = _meta().trail_carrier_policy
	for carrier in policy.carrier_enum:
		var cfg: Dictionary = _cfg()
		cfg.presentation.trail["resource_ref"] = {"id": "trail"}
		cfg.presentation.trail["carrier"] = carrier
		var required: Variant = policy.required_end_policy.get(carrier, null)
		if required is String:
			_has(_rules().validate(cfg, _context()), "V-075", required, Diag.SEV_BLOCK)
			var legal_value: String = ""
			for leaf in _meta().leaves:
				if leaf.path == required:
					legal_value = str(leaf.enum[0])
			assert_false(legal_value.is_empty())
			cfg.presentation.trail[required.trim_prefix("presentation.trail.")] = legal_value
			_no_rule(_rules().validate(cfg, _context()), "V-075")
		else:
			_no_rule(_rules().validate(cfg, _context()), "V-075")
		var forbidden: Variant = policy.forbidden_end_policy.get(carrier, null)
		if forbidden is Array and not forbidden.is_empty():
			cfg.presentation.trail[forbidden[0].trim_prefix("presentation.trail.")] = "fade_then_free"
			_has(_rules().validate(cfg, _context()), "V-075", forbidden[0], Diag.SEV_BLOCK)

func test_v076_merge_scope_and_optional_context_notice() -> void:
	var cfg: Dictionary = _cfg()
	cfg.presentation.damage_number["merge_policy"] = "per_cast"
	var result: Dictionary = _rules().validate(cfg, _context())
	assert_true(result.ok)
	assert_true(str(result.notices).contains("V-076"))
	var context: Dictionary = _context()
	context["damage_number_semantics"] = {"cross_target": true, "cross_type": false, "writeback": false}
	_has(_rules().validate(cfg, context), "V-076", "presentation.damage_number.merge_policy", Diag.SEV_BLOCK)
	context.damage_number_semantics["cross_target"] = false
	context.damage_number_semantics["cross_type"] = true
	_has(_rules().validate(cfg, context), "V-076", "presentation.damage_number.merge_policy", Diag.SEV_BLOCK)
	context.damage_number_semantics["cross_type"] = false
	context.damage_number_semantics["writeback"] = true
	_has(_rules().validate(cfg, context), "V-076", "presentation.damage_number.merge_policy", Diag.SEV_BLOCK)
	context.damage_number_semantics["writeback"] = false
	_no_rule(_rules().validate(cfg, context), "V-076")
	cfg.presentation.damage_number["fallback_total"] = false
	_has(_rules().validate(cfg, context), "V-076", "presentation.damage_number.fallback_total", Diag.SEV_BLOCK)

func test_v077_attribute_binding_warning_and_legal() -> void:
	var context: Dictionary = _context()
	context.player_attribute_bindings["power"] = {"resolved_path": "params.power", "resolved_value": 1, "matches": false}
	var result: Dictionary = _rules().validate(_cfg(), context)
	assert_true(result.ok)
	_has(result, "V-077", "meta.player_attributes", Diag.SEV_WARN)
	context.player_attribute_bindings["power"]["matches"] = true
	_no_rule(_rules().validate(_cfg(), context), "V-077")

func test_v078_legal_placeholder_warns_resolved_legal() -> void:
	var context: Dictionary = _context()
	context.resource_resolution["presentation.fx.resource_ref"] = {"resolved": false, "placeholder_legal": true}
	var result: Dictionary = _rules().validate(_cfg(), context)
	assert_true(result.ok)
	_has(result, "V-078", "presentation.fx.resource_ref", Diag.SEV_WARN)
	context.resource_resolution["presentation.fx.resource_ref"]["resolved"] = true
	_no_rule(_rules().validate(_cfg(), context), "V-078")

func test_v079_probe_requires_bound_coverage_and_pass() -> void:
	var context: Dictionary = _context()
	context.probe_credentials["bricks[0].brick_id"] = {"result": "fail", "content_fingerprint": "hash", "runtime_version": "1", "capabilities": [], "coverage": {"hit": true}}
	_has(_rules().validate(_cfg(), context), "V-079", "bricks[0].brick_id", Diag.SEV_BLOCK)
	context.probe_credentials["bricks[0].brick_id"]["result"] = "pass"
	_no_rule(_rules().validate(_cfg(), context), "V-079")
	context.probe_credentials["bricks[0].brick_id"].erase("content_fingerprint")
	assert_false(_rules().validate(_cfg(), context).ok)

func test_v080_nested_illegal_leaf_and_registered_boundary() -> void:
	var cfg: Dictionary = _cfg()
	cfg["runtime_hints"] = {"unknown": {"nested": [0, {"bad": true}]}}
	_has(_rules().validate(cfg, _context()), "V-080", "runtime_hints.unknown.nested[1].bad", Diag.SEV_BLOCK)
	cfg["runtime_hints"] = {"deterministic": false}
	_has(_rules().validate(cfg, _context()), "V-080", "runtime_hints.deterministic", Diag.SEV_BLOCK)
	cfg["runtime_hints"] = {"deterministic": true, "rng_stream": "logic", "contract_notes": ["ok"]}
	assert_true(_rules().validate(cfg, _context()).ok)

func test_v081_changed_baseline_blocks_unchanged_passes() -> void:
	var context: Dictionary = _context()
	context.baseline_version_state["current_underlying_version"] = "2"
	_has(_rules().validate(_cfg(), context), "V-081", "meta.version", Diag.SEV_BLOCK)
	context.baseline_version_state["current_underlying_version"] = "1"
	_no_rule(_rules().validate(_cfg(), context), "V-081")

func test_v082_legal_default_is_hint_author_filled_passes() -> void:
	var context: Dictionary = _context()
	context.default_applications = [{"path": "params.shotgun_allowed", "default_value": false, "legally_applied": true, "author_filled": false}]
	var result: Dictionary = _rules().validate(_cfg(), context)
	assert_true(result.ok)
	_has(result, "V-082", "params.shotgun_allowed", Diag.SEV_HINT)
	context.default_applications[0]["author_filled"] = true
	_no_rule(_rules().validate(_cfg(), context), "V-082")

func test_v083_incomplete_migration_blocks_current_version_passes() -> void:
	var context: Dictionary = _context()
	context.migration_state["migrating"] = true
	context.migration_state["path_complete"] = false
	_has(_rules().validate(_cfg(), context), "V-083", "schema_version", Diag.SEV_BLOCK)
	context.migration_state["path_complete"] = true
	_no_rule(_rules().validate(_cfg(), context), "V-083")

func test_v084_certify_blocks_save_notices_invalid_operation_fails() -> void:
	var context: Dictionary = _context()
	context.preview_fingerprint["current_fingerprint"] = "b"
	context.preview_fingerprint["operation"] = "certify"
	_has(_rules().validate(_cfg(), context), "V-084", "meta.version", Diag.SEV_BLOCK)
	context.preview_fingerprint["operation"] = "save"
	var result: Dictionary = _rules().validate(_cfg(), context)
	assert_true(result.ok)
	_no_rule(result, "V-084")
	assert_true(str(result.notices).contains("未预览/未认证"))
	context.preview_fingerprint.erase("operation")
	result = _rules().validate(_cfg(), context)
	assert_false(result.ok)
	_has(result, "V-084", "meta.version", Diag.SEV_BLOCK)
	assert_false(_rules().validate(_cfg(), {}).ok)

func test_required_context_missing_and_wrong_type_each_fail() -> void:
	var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/validation_context_contract.json"))
	assert_true(contract is Dictionary)
	for key in ["player_attribute_bindings", "resource_resolution", "probe_credentials", "baseline_version_state", "default_applications", "migration_state", "preview_fingerprint"]:
		var rule_id: String = str(contract.context_keys[key].required_by[0])
		var missing: Dictionary = _context()
		missing.erase(key)
		var rules: Rules = _rules()
		var result: Dictionary = rules.validate(_cfg(), missing)
		assert_false(result.ok, "缺少 %s 必须失败" % key)
		assert_true(rules.last_error.contains(key))
		var wrong: Dictionary = _context()
		wrong[key] = [] if contract.context_keys[key].type == "Dictionary" else {}
		result = _rules().validate(_cfg(), wrong)
		assert_false(result.ok, "错型 %s 必须失败" % key)
		var seen: bool = false
		for diagnostic in result.diagnostics:
			if diagnostic.rule_id == rule_id:
				seen = true
		assert_true(seen, "对应规则必须可定位: " + rule_id)
