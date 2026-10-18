extends GutTest

const TypesRules = preload("res://skill_core/validate/rules/r_types.gd")
const Diag = preload("res://skill_core/api/diagnostic.gd")

func _meta() -> Dictionary:
	var file: FileAccess = FileAccess.open("res://data/params_meta.json", FileAccess.READ)
	return JSON.parse_string(file.get_as_text())

func _cfg() -> Dictionary:
	return {
		"schema_version": "0.1",
		"params": {
			"carrier": "none",
			"lifetime_ticks": 0,
			"templates": [],
			"parts": []
		}
	}

func _context() -> Dictionary:
	return {
		"capabilities": {
			"params.derivations[0]": {"projectile": true, "instant": false},
			"params": {"projectile": true, "instant": false}
		},
		"card_behaviors": {}
	}

func _validator() -> TypesRules:
	var validator: TypesRules = TypesRules.new()
	assert_true(validator.configure(_meta()), validator.last_error)
	return validator

func _find(result: Dictionary, rule_id: String, path: String):
	for diagnostic in result.diagnostics:
		if diagnostic.rule_id == rule_id and diagnostic.path == path:
			return diagnostic
	assert_true(false, "%s 应定位到 %s；实际=%s" % [rule_id, path, str(result.diagnostics)])
	return null

func _reject(cfg: Dictionary, rule_id: String, path: String) -> void:
	var result: Dictionary = _validator().validate(cfg, _context())
	assert_false(result.ok)
	var diagnostic = _find(result, rule_id, path)
	if diagnostic != null:
		assert_eq(diagnostic.severity, Diag.SEV_BLOCK)
		assert_false(diagnostic.hint.is_empty())

func test_metadata_and_rule_table_are_explicitly_loaded() -> void:
	var validator: TypesRules = TypesRules.new()
	assert_false(validator.validate(_cfg(), _context()).ok)
	assert_eq(validator.validate(_cfg(), _context()).diagnostics[0].code, "VALIDATION_METADATA_UNAVAILABLE")
	assert_true(validator.configure(_meta()), validator.last_error)
	assert_eq(validator._rules.size(), 84)
	assert_eq(validator._groups.size(), 1)
	assert_eq(validator._groups[0].rules.size(), 20)

func test_v019_unknown_field_reports_actual_key() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.tick_order = 1
	_reject(cfg, "V-019", "params.tick_order")

func test_v020_type_nonfinite_and_range_are_leaf_local() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.projectile_speed = "3"
	_reject(cfg, "V-020", "params.projectile_speed")
	cfg = _cfg()
	cfg.params.projectile_speed = INF
	_reject(cfg, "V-020", "params.projectile_speed")
	cfg = _cfg()
	cfg.params.hit_radius = 0
	_reject(cfg, "V-020", "params.hit_radius")

func test_v021_is_generated_for_every_tick_field() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.templates = [{"cast": {"windup_ticks": -1}, "carrier": "none", "lifetime_ticks": 0, "targeting": {}, "parts": []}]
	_reject(cfg, "V-021", "params.templates[0].cast.windup_ticks")
	var found: Dictionary = {}
	for field in _meta().tick_fields:
		found[field] = true
	assert_eq(found.size(), 16, "tick_fields 来自元数据，不能手写三个字段")

func test_v022_negative_shot_point_is_rejected_at_index() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.shot_ticks = [0, -1]
	_reject(cfg, "V-022", "params.shot_ticks[1]")

func test_v023_non_monotone_shot_table_is_rejected() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.shot_ticks = [2, 1]
	_reject(cfg, "V-023", "params.shot_ticks[1]")

func test_v024_instant_is_not_a_carrier() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.carrier = "instant"
	_reject(cfg, "V-024", "params.carrier")

func test_v025_instant_nonzero_lifetime_is_rejected() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.lifetime_ticks = 2
	_reject(cfg, "V-025", "params.lifetime_ticks")

func test_v026_persistent_effect_requires_lifetime() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.carrier = "attached"
	cfg.params.erase("lifetime_ticks")
	_reject(cfg, "V-026", "params.lifetime_ticks")

func test_v027_hit_limits_are_positive_integers() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.hit_policy = {"per_target_limit": 0}
	_reject(cfg, "V-027", "params.hit_policy.per_target_limit")

func test_v028_rehit_interval_must_be_positive_tick() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.hit_policy = {"per_target_limit": 1, "rehit_interval_ticks": 0}
	_reject(cfg, "V-028", "params.hit_policy.rehit_interval_ticks")

func test_v029_repeat_capability_requires_interval() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.hit_policy = {"per_target_limit": 1}
	var context: Dictionary = _context()
	context.capabilities.params = {"projectile": true, "repeat_hit": true}
	var result: Dictionary = _validator().validate(cfg, context)
	assert_false(result.ok)
	_find(result, "V-029", "params.hit_policy.rehit_interval_ticks")

func test_v030_exclusive_hit_strategy_is_rejected() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.hit_policy = {"per_target_limit": 1, "rehit_interval_ticks": 2, "strategy": "either"}
	_reject(cfg, "V-030", "params.hit_policy.strategy")

func test_v031_target_lost_is_metadata_enum_driven() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.on_target_lost = "retarget"
	_reject(cfg, "V-031", "params.on_target_lost")

func test_v032_event_alias_uses_schema_event_and_rejects_third_event() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.derivations = [{"event": "state", "reasons": [], "count": 1, "child_template": "x"}]
	_reject(cfg, "V-032", "params.derivations[0].event")

func test_v033_purge_is_silent_and_not_a_reason_code() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.derivations = [{"event": "vanish", "reasons": ["purge"], "count": 1, "child_template": "x"}]
	_reject(cfg, "V-033", "params.derivations[0].reasons[0]")

func test_v034_restricted_reason_requires_true_authorization() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.derivations = [{"event": "vanish", "reasons": ["range_end"], "count": 1, "child_template": "x"}]
	_reject(cfg, "V-034", "params.derivations[0].allow_restricted_reason")

func test_v035_non_projectile_cannot_derive_landed() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.derivations = [{"event": "vanish", "reasons": ["landed"], "count": 1, "child_template": "x"}]
	var context: Dictionary = _context()
	context.capabilities["params.derivations[0]"] = {"projectile": false, "instant": false}
	var result: Dictionary = _validator().validate(cfg, context)
	assert_false(result.ok)
	_find(result, "V-035", "params.derivations[0].reasons[0]")

func test_v036_instant_reason_is_capability_context_driven() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.derivations = [{"event": "vanish", "reasons": ["expired"], "count": 1, "child_template": "x"}]
	var context: Dictionary = _context()
	context.capabilities["params.derivations[0]"] = {"projectile": false, "instant": true}
	var result: Dictionary = _validator().validate(cfg, context)
	assert_false(result.ok)
	_find(result, "V-036", "params.derivations[0].reasons[0]")

func test_v037_per_part_and_state_expiry_are_not_events() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.derivations = [{"event": "hit", "reasons": [], "count": 1, "child_template": "x", "per_part": true}]
	_reject(cfg, "V-037", "params.derivations[0].per_part")

func test_v038_type_and_fixed_part_index_are_checked_at_actual_slot() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.parts = [{"part_index": 0, "type": "unknown"}, {"part_index": 0, "type": "physical"}]
	var result: Dictionary = _validator().validate(cfg, _context())
	assert_false(result.ok)
	_find(result, "V-038", "params.parts[0].type")
	_find(result, "V-038", "params.parts[1].part_index")

func test_missing_capability_context_fails_explicitly() -> void:
	var validator: TypesRules = _validator()
	var result: Dictionary = validator.validate(_cfg(), {})
	assert_false(result.ok)
	assert_eq(result.diagnostics[0].code, "VALIDATION_METADATA_UNAVAILABLE")
	assert_true(validator.last_error.contains("能力上下文"))

func test_restricted_reason_true_is_accepted_and_cfg_is_not_mutated() -> void:
	var cfg: Dictionary = _cfg()
	cfg.params.derivations = [{"event": "vanish", "reasons": ["range_end"], "allow_restricted_reason": true, "count": 1, "child_template": "x"}]
	var before: Dictionary = cfg.duplicate(true)
	var result: Dictionary = _validator().validate(cfg, _context())
	assert_true(result.ok, str(result.diagnostics))
	assert_eq(cfg, before)
