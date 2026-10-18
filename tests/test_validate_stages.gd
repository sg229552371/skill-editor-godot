extends GutTest

const Validator = preload("res://skill_core/validate/validator.gd")
const SkillApi = preload("res://skill_core/api/skill_api.gd")
const Diag = preload("res://skill_core/api/diagnostic.gd")

class FakeCard extends RefCounted:
	var configured: bool = true
	var output: Array = []

	func validate(_cfg: Dictionary, _context: Dictionary) -> Dictionary:
		return {"ok": true, "diagnostics": output.duplicate(true), "notices": []}

func _diag(rule_id: String, path: String, severity: int = Diag.SEV_BLOCK) -> Dictionary:
	return {"rule_id": rule_id, "code": "E-0001", "severity": severity, "path": path,
		"actual": "bad", "expected": "good", "hint": "test"}

func _stages() -> Dictionary:
	return {"filling": [0], "card": [0], "assembly": [0], "save": [0], "load": [0], "preview": [0]}

func _validator(card: FakeCard) -> Validator:
	var validator: Validator = Validator.new()
	var spec: Dictionary = {"cards": [{"name": "fake", "card": card}],
		"groups": [{"first": 1, "last": 1, "card": "fake", "stages": []}],
		"stages": _stages()}
	assert_true(validator.configure(spec), validator.last_error)
	return validator

func _context(revision: int = 1) -> Dictionary:
	return {"draft_revision": revision, "submitted_paths": ["meta.title"],
		"cross_card_facts": {}, "baseline_version_state": {}, "migration_state": {},
		"probe_credentials": {}, "preview_fingerprint": {}}

func test_all_six_stage_entries_select_registered_groups() -> void:
	var card: FakeCard = FakeCard.new()
	card.output = [_diag("V-001", "meta.title")]
	var validator: Validator = _validator(card)
	for stage in [SkillApi.STAGE_FILLING, SkillApi.STAGE_CARD, SkillApi.STAGE_ASSEMBLY,
		SkillApi.STAGE_SAVE, SkillApi.STAGE_LOAD, SkillApi.STAGE_PREVIEW]:
		var result: Dictionary = validator.validate({}, stage, _context())
		assert_eq(result.revision, 1)
		assert_eq(result.diagnostics.size(), 1)

func test_each_stage_missing_contract_context_fails_explicitly() -> void:
	var validator: Validator = _validator(FakeCard.new())
	var required: Dictionary = {
		"filling": "submitted_paths", "card": "__none__", "assembly": "cross_card_facts",
		"save": "__none__", "load": "baseline_version_state", "preview": "probe_credentials"}
	for stage in [SkillApi.STAGE_FILLING, SkillApi.STAGE_CARD, SkillApi.STAGE_ASSEMBLY,
		SkillApi.STAGE_SAVE, SkillApi.STAGE_LOAD, SkillApi.STAGE_PREVIEW]:
		var context: Dictionary = _context()
		context.erase("draft_revision")
		var result: Dictionary = validator.validate({}, stage, context)
		assert_false(result.ok, "缺 draft_revision 必须失败")
		assert_true(result.error.contains("draft_revision"))
		context = _context()
		var key: String = str(required[String(stage)])
		if key != "__none__":
			context.erase(key)
			result = validator.validate({}, stage, context)
			assert_false(result.ok, "缺 %s 必须失败" % key)
			assert_true(result.error.contains(key))

func test_filling_only_reports_submitted_paths_and_second_submission_expands() -> void:
	var card: FakeCard = FakeCard.new()
	card.output = [_diag("V-001", "meta.title"), _diag("V-002", "params.speed")]
	var validator: Validator = _validator(card)
	var context: Dictionary = _context()
	var result: Dictionary = validator.validate({}, SkillApi.STAGE_FILLING, context)
	assert_eq(result.diagnostics.size(), 1)
	assert_eq(result.diagnostics[0].path, "meta.title")
	context.submitted_paths.append("params.speed")
	result = validator.validate({}, SkillApi.STAGE_FILLING, context)
	assert_eq(result.diagnostics.size(), 2)

func test_save_is_full_definition_not_filling_subset() -> void:
	var card: FakeCard = FakeCard.new()
	card.output = [_diag("V-001", "meta.title"), _diag("V-002", "params.speed")]
	var validator: Validator = _validator(card)
	var filling: Dictionary = validator.validate({}, SkillApi.STAGE_FILLING, _context())
	var saving: Dictionary = validator.validate({}, SkillApi.STAGE_SAVE, _context())
	assert_lt(filling.diagnostics.size(), saving.diagnostics.size())

func test_severity_is_aggregated_without_downgrade() -> void:
	var card: FakeCard = FakeCard.new()
	card.output = [_diag("V-001", "meta.title", Diag.SEV_HINT), _diag("V-002", "bricks[0]", Diag.SEV_WARN),
		_diag("V-003", "params.speed", Diag.SEV_BLOCK)]
	var result: Dictionary = _validator(card).validate({}, SkillApi.STAGE_SAVE, _context())
	assert_false(result.ok)
	assert_eq(result.diagnostics.size(), 3)
	assert_eq(result.diagnostics[0].severity, Diag.SEV_BLOCK)
	assert_eq(result.diagnostics[1].severity, Diag.SEV_WARN)
	assert_eq(result.diagnostics[2].severity, Diag.SEV_HINT)

func test_sorting_and_deduplication_are_applied_after_card_aggregation() -> void:
	var first: FakeCard = FakeCard.new()
	first.output = [_diag("V-002", "params.speed"), _diag("V-001", "meta.title")]
	var second: FakeCard = FakeCard.new()
	second.output = [_diag("V-001", "meta.title")]
	var validator: Validator = Validator.new()
	var spec: Dictionary = {"cards": [{"name": "first", "card": first}, {"name": "second", "card": second}],
		"groups": [{"first": 1, "last": 1, "card": "first", "stages": []},
			{"first": 2, "last": 2, "card": "second", "stages": []}],
		"stages": {"filling": [0, 1], "card": [0, 1], "assembly": [0, 1], "save": [0, 1],
			"load": [0, 1], "preview": [0, 1]}}
	assert_true(validator.configure(spec), validator.last_error)
	var result: Dictionary = validator.validate({}, SkillApi.STAGE_SAVE, _context())
	assert_eq(result.removed, 1)
	assert_eq(result.diagnostics.size(), 2)
	assert_eq(result.diagnostics[0].rule_id, "V-001")

func test_revision_older_result_is_stale_and_not_accepted() -> void:
	var validator: Validator = _validator(FakeCard.new())
	var three: Dictionary = validator.validate({}, SkillApi.STAGE_SAVE, _context(3))
	var five: Dictionary = validator.validate({}, SkillApi.STAGE_SAVE, _context(5))
	var late_three: Dictionary = validator.validate({}, SkillApi.STAGE_SAVE, _context(3))
	assert_false(three.stale)
	assert_false(five.stale)
	assert_true(late_three.stale)
	assert_false(late_three.accepted)
	assert_true(validator.is_stale(late_three))

func test_illegal_stage_and_unconfigured_card_fail_explicitly() -> void:
	var card: FakeCard = FakeCard.new()
	card.configured = false
	var validator: Validator = Validator.new()
	assert_false(validator.configure({"cards": [{"name": "fake", "card": card}]}))
	var configured: Validator = _validator(FakeCard.new())
	var result: Dictionary = configured.validate({}, StringName("unknown"), _context())
	assert_false(result.ok)
	assert_true(result.error.contains("阶段"))

func test_empty_diagnostics_is_valid_but_no_rule_registry_is_not() -> void:
	var empty_card: FakeCard = FakeCard.new()
	var valid: Dictionary = _validator(empty_card).validate({}, SkillApi.STAGE_SAVE, _context())
	assert_true(valid.ok)
	assert_eq(valid.diagnostics.size(), 0)
	var validator: Validator = Validator.new()
	assert_false(validator.configure({"cards": [{"name": "fake", "card": empty_card}], "groups": [], "stages": _stages()}))
	assert_true(validator.last_error.contains("规则区间"))

func test_cfg_and_diagnostic_inputs_are_not_shared() -> void:
	var card: FakeCard = FakeCard.new()
	card.output = [_diag("V-001", "meta.title")]
	var validator: Validator = _validator(card)
	var cfg: Dictionary = {"meta": {"title": "x"}}
	var before: Dictionary = cfg.duplicate(true)
	var result: Dictionary = validator.validate(cfg, SkillApi.STAGE_SAVE, _context())
	assert_eq(cfg, before)
	result.diagnostics[0].actual = "changed"
	assert_eq(card.output[0].actual, "bad")
