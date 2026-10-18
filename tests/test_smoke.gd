extends GutTest

func test_diagnostic_make_creates_object() -> void:
	var diagnostic := Diagnostic.make("V-001", "E-0002", "skill_id", "bad_id", "role_category_name")
	assert_not_null(diagnostic)
	assert_eq(diagnostic.rule_id, "V-001")
	assert_eq(diagnostic.code, "E-0002")
	assert_eq(diagnostic.path, "skill_id")

func test_diagnostic_severity_constants_are_distinct() -> void:
	assert_ne(Diagnostic.SEV_BLOCK, Diagnostic.SEV_WARN)
	assert_ne(Diagnostic.SEV_WARN, Diagnostic.SEV_HINT)
	assert_ne(Diagnostic.SEV_BLOCK, Diagnostic.SEV_HINT)

func test_skill_api_stubs_return_failure_without_throwing() -> void:
	var api := SkillApi.new()
	var results: Array[Dictionary] = [
		api.load_cfg(""),
		api.save_cfg("", {}),
		api.parse_yaml(""),
		api.dump_yaml({}),
		api.load_catalog(""),
		api.get_brick([], ""),
		api.list_bricks([]),
		api.validate({}, SkillApi.STAGE_SAVE),
		api.resolve({}),
		api.apply_modifiers(0, []),
	]
	assert_eq(results.size(), 10)
	for result in results:
		assert_false(result.ok)
		assert_true(result.has("diagnostics"))
	var invalid_cfg: Dictionary = api.create_sim({}, 0)
	assert_false(invalid_cfg.ok)
	assert_true(invalid_cfg.has("diagnostics"))
	var invalid_sim: Dictionary = api.step_sim({}, 1)
	assert_false(invalid_sim.ok)
	assert_true(invalid_sim.has("diagnostics"))

func test_brick_catalog_is_valid_json_with_28_entries() -> void:
	var file := FileAccess.open("res://data/bricks/brick_catalog.json", FileAccess.READ)
	assert_not_null(file)
	var parsed = JSON.parse_string(file.get_as_text())
	assert_true(parsed is Array)
	assert_eq(parsed.size(), 28)
