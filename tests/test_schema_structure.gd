extends GutTest

const CfgSchema = preload("res://skill_core/schema/cfg_schema.gd")
const CfgCodec = preload("res://skill_core/schema/cfg_codec.gd")

func _schema():
	var validator = CfgSchema.new()
	assert_true(validator.configure(), validator.last_error)
	return validator

func _cfg() -> Dictionary:
	var card: Dictionary = {}
	for field in CfgCodec.BRICK_KEYS:
		card[field] = "example"
	card["carrier"] = CfgCodec.CARRIERS[0]
	card["status"] = CfgCodec.STATUSES[0]
	card["default_cfg"] = {}
	card["author_params"] = []
	card["locked_params"] = {}
	card["relic_params"] = {}
	card["presentation"] = []
	card["player_text"] = []
	var presentation: Dictionary = {}
	for field in CfgCodec.PRESENTATION_KEYS:
		presentation[field] = {}
	presentation["sfx"] = {"max_concurrency": 0}
	presentation["trail"] = {"carrier": CfgCodec.CARRIERS[0]}
	return {
		"schema_version": "0.1", "skill_id": "mage_active_demo",
		"meta": {"role": "mage", "category": "active", "short_name": "demo", "name": "demo", "version": "1.0.0", "author": "test"},
		"bricks": [card.duplicate(true), card.duplicate(true), card.duplicate(true)],
		"params": {"carrier": CfgCodec.CARRIERS[0], "lifetime_ticks": 0, "templates": [{
			"template_id": "main", "carrier": CfgCodec.CARRIERS[0],
			"targeting": {"target_group": "enemy"}, "lifetime_ticks": 0,
			"parts": [{"part_index": 0, "type": "physical"}]
		}]},
		"presentation": presentation, "runtime_hints": {}
	}

func _paths(result: Dictionary) -> Array[String]:
	var paths: Array[String] = []
	for diagnostic in result.diagnostics:
		paths.append(diagnostic.path)
	return paths

func _delta(validator, baseline: Dictionary, modified: Dictionary) -> Array[String]:
	var old_paths: Array[String] = _paths(validator.validate(baseline))
	var new_paths: Array[String] = _paths(validator.validate(modified))
	var added: Array[String] = []
	for path in new_paths:
		if not old_paths.has(path):
			added.append(path)
	return added

func test_baseline_and_frozen_top_level_keys() -> void:
	var validator: Variant = _schema()
	var baseline: Dictionary = _cfg()
	assert_true(validator.validate(baseline).ok, "the complete fixture must start clean")
	for field in CfgCodec.TOP_LEVEL_KEYS:
		var broken: Dictionary = baseline.duplicate(true)
		broken.erase(field)
		assert_true(_delta(validator, baseline, broken).has(field), "missing: %s" % field)
	var extra: Dictionary = baseline.duplicate(true)
	extra["eighth_key"] = 1
	assert_true(_delta(validator, baseline, extra).has("eighth_key"))

func test_twelve_card_fields_are_reported_at_third_slot() -> void:
	var validator: Variant = _schema()
	var baseline: Dictionary = _cfg()
	assert_true(validator.validate(baseline).ok)
	for field in CfgCodec.BRICK_KEYS:
		var broken: Dictionary = baseline.duplicate(true)
		broken["bricks"][2].erase(field)
		assert_true(_delta(validator, baseline, broken).has("bricks[2]." + field), "missing: %s" % field)
	var extra: Dictionary = baseline.duplicate(true)
	extra["bricks"][2]["thirteenth_field"] = true
	assert_true(_delta(validator, baseline, extra).has("bricks[2].thirteenth_field"))

func test_seven_presentation_segments_missing_extra_and_nested_extra() -> void:
	var validator: Variant = _schema()
	var baseline: Dictionary = _cfg()
	assert_true(validator.validate(baseline).ok)
	for field in CfgCodec.PRESENTATION_KEYS:
		var broken: Dictionary = baseline.duplicate(true)
		broken["presentation"].erase(field)
		assert_true(_delta(validator, baseline, broken).has("presentation." + field), "missing: %s" % field)
	var extra: Dictionary = baseline.duplicate(true)
	extra["presentation"]["eighth_segment"] = {}
	assert_true(_delta(validator, baseline, extra).has("presentation.eighth_segment"))
	extra = baseline.duplicate(true)
	extra["presentation"]["fx"]["unregistered"] = true
	assert_true(_delta(validator, baseline, extra).has("presentation.fx.unregistered"))

func test_seven_types_have_valid_value_and_invalid_value() -> void:
	var validator: Variant = _schema()
	var baseline: Dictionary = _cfg()
	assert_true(validator.validate(baseline).ok)
	var cases: Array = [
		["integer", "params.lifetime_ticks", 1, 1.5],
		["float", "params.projectile_speed", 1.5, "1.5"],
		["bool", "params.shotgun_allowed", false, 0],
		["enum", "params.on_target_lost", "continue", "not_registered"],
		["string", "meta.name", "label", []],
		["ref", "runtime_hints.budget_tier", "budget_profile", {}],
		["array", "params.shot_ticks", [0, 1], {}]
	]
	for test_case in cases:
		var path: String = test_case[1]
		var good: Dictionary = baseline.duplicate(true)
		var bad: Dictionary = baseline.duplicate(true)
		_set_path(good, path, test_case[2])
		_set_path(bad, path, test_case[3])
		assert_true(validator.validate(good).ok, "valid %s at %s" % [test_case[0], path])
		assert_true(_delta(validator, baseline, bad).has(path), "invalid %s at %s" % [test_case[0], path])

func test_nested_arrays_and_tick_fields_have_indexed_paths() -> void:
	var validator: Variant = _schema()
	var baseline: Dictionary = _cfg()
	assert_true(validator.validate(baseline).ok)
	var broken: Dictionary = baseline.duplicate(true)
	broken["params"]["templates"][0]["lifetime_ticks"] = 0.5
	assert_true(_delta(validator, baseline, broken).has("params.templates[0].lifetime_ticks"))
	broken = baseline.duplicate(true)
	broken["params"]["templates"][0]["parts"][0]["part_index"] = "zero"
	assert_true(_delta(validator, baseline, broken).has("params.templates[0].parts[0].part_index"))
	broken = baseline.duplicate(true)
	broken["params"]["shot_ticks"] = [0, 1.5]
	assert_true(_delta(validator, baseline, broken).has("params.shot_ticks[1]"))

func test_registered_required_fields_and_closed_vs_open_objects() -> void:
	var validator: Variant = _schema()
	var baseline: Dictionary = _cfg()
	assert_true(validator.validate(baseline).ok)
	var broken: Dictionary = baseline.duplicate(true)
	broken["params"]["templates"][0]["targeting"].erase("target_group")
	assert_true(_delta(validator, baseline, broken).has("params.templates[0].targeting.target_group"))
	broken = baseline.duplicate(true)
	broken["meta"].erase("role")
	assert_true(_delta(validator, baseline, broken).has("meta.role"))
	broken = baseline.duplicate(true)
	broken["params"]["templates"][0]["targeting"]["extra"] = true
	assert_true(_delta(validator, baseline, broken).has("params.templates[0].targeting.extra"))
	var open: Dictionary = baseline.duplicate(true)
	open["bricks"][0]["default_cfg"]["author_extension"] = 42
	assert_true(validator.validate(open).ok, "the Schema's open default_cfg object accepts extra keys")

func test_enum_values_follow_injected_metadata_not_code_literals() -> void:
	var validator: Variant = _schema()
	var baseline: Dictionary = _cfg()
	assert_true(validator.validate(baseline).ok)
	var broken: Dictionary = baseline.duplicate(true)
	broken["params"]["templates"][0]["parts"][0]["type"] = "alien"
	assert_true(_delta(validator, baseline, broken).has("params.templates[0].parts[0].type"))
	var schema_data: Dictionary = _json(CfgSchema.SCHEMA_PATH)
	var params_data: Dictionary = _json(CfgSchema.PARAMS_PATH)
	var original: Array = []
	for leaf in params_data.leaves:
		if leaf.path == "templates[i].parts[i].type":
			original = leaf.enum.duplicate()
			leaf["enum"] = ["alien"]
	assert_true(original.size() > 0, "the registered enum must be present")
	assert_true(validator.configure_from_data(schema_data, params_data), validator.last_error)
	assert_true(validator.validate(broken).ok, "a newly registered value becomes valid without code changes")
	assert_true(_paths(validator.validate(baseline)).has("params.templates[0].parts[0].type"), "the former value is rejected")

func test_nullable_and_unregistered_required_are_not_guessed() -> void:
	var validator: Variant = _schema()
	var baseline: Dictionary = _cfg()
	baseline["meta"]["copied_from"] = null
	assert_true(validator.validate(baseline).ok, "nullable metadata is an explicit exception")
	var other: Dictionary = baseline.duplicate(true)
	other["meta"]["name"] = null
	assert_true(_delta(validator, baseline, other).has("meta.name"))
	var no_conditional: Dictionary = baseline.duplicate(true)
	no_conditional["params"]["templates"][0]["carrier"] = CfgCodec.CARRIERS[1]
	assert_true(validator.validate(no_conditional).ok, "no unregistered carrier-dependent required field may be inferred")

func test_validation_does_not_mutate_input() -> void:
	var validator: Variant = _schema()
	var cfg: Dictionary = _cfg()
	cfg["params"]["shot_ticks"] = [1.5]
	var before: Dictionary = cfg.duplicate(true)
	var result: Dictionary = validator.validate(cfg)
	assert_false(result.ok)
	assert_eq(cfg, before)

func test_missing_or_invalid_metadata_fails_explicitly() -> void:
	var validator = CfgSchema.new()
	assert_false(validator.validate(_cfg()).ok)
	assert_true(validator.validate(_cfg()).error.length() > 0)
	assert_false(validator.configure("res://data/missing_schema_t004.json"))
	assert_true(validator.last_error.length() > 0)
	assert_false(validator.validate(_cfg()).ok)
	var schema_data: Dictionary = _json(CfgSchema.SCHEMA_PATH)
	var params_data: Dictionary = _json(CfgSchema.PARAMS_PATH)
	params_data.erase("objects")
	assert_false(validator.configure_from_data(schema_data, params_data))
	assert_true(validator.last_error.contains("objects"))

func _set_path(cfg: Dictionary, path: String, value: Variant) -> void:
	var segments: PackedStringArray = path.split(".")
	var current: Dictionary = cfg
	for index in range(segments.size() - 1):
		current = current[segments[index]]
	current[segments[-1]] = value

func _json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "metadata file must be deployed: %s" % path)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_true(parsed is Dictionary)
	return parsed if parsed is Dictionary else {}
