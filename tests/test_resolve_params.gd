extends GutTest

const ParamResolverScript = preload("res://skill_core/resolve/param_resolver.gd")

func test_resolve_merges_default_generic_then_specific_and_records_source() -> void:
	var resolver = ParamResolverScript.new()
	var cfg: Dictionary = {
		"bricks": [{
			"default_cfg": {"params": {"motion": {"speed": 4, "range": 10}}},
			"author_params": ["params.motion.speed", "params.motion.range"],
			"locked_params": {},
			"relic_params": {"params.motion.speed": "可改", "params.motion.range": "可改"},
		}],
		"params": {
			"motion": {"speed": 8},
			"brick_overrides": [{"brick_index": 0, "values": {"motion": {"range": 20}}}],
		},
	}

	var result: Dictionary = resolver.resolve(cfg)
	assert_true(result.ok)
	assert_eq(result.resolved["params"]["motion"]["speed"], 8)
	assert_eq(result.resolved["params"]["motion"]["range"], 20)
	assert_eq(result.sources["params.motion.speed"]["source"], "params")
	assert_eq(result.sources["params.motion.range"]["source"], "brick_override")
	assert_eq(result.sources["params.motion.range"]["input_path"], "params.brick_overrides[0].values.motion.range")

func test_resolve_rejects_locked_and_forbidden_relic_overrides_without_mutating_cfg() -> void:
	var resolver = ParamResolverScript.new()
	var cfg: Dictionary = {
		"bricks": [{
			"default_cfg": {"params": {"cast": {"cooldown": 10}, "motion": {"speed": 4}}},
			"author_params": ["params.cast.cooldown", "params.motion.speed"],
			"locked_params": {"params.cast.cooldown": "registry"},
			"relic_params": {"params.cast.cooldown": "可改", "params.motion.speed": "禁止"},
		}],
		"params": {
			"brick_overrides": [{"brick_index": 0, "values": {"cast": {"cooldown": 1}, "motion": {"speed": 9}}}],
		},
	}
	var before: Dictionary = cfg.duplicate(true)

	var result: Dictionary = resolver.resolve(cfg)
	assert_false(result.ok)
	assert_eq(result.resolved["params"]["cast"]["cooldown"], 10)
	assert_eq(result.resolved["params"]["motion"]["speed"], 4)
	assert_eq(cfg, before)
	assert_eq(result.diagnostics.size(), 2)
	assert_eq(result.diagnostics[0]["rule_id"], "V-014")
	assert_eq(result.diagnostics[1]["path"], "params.brick_overrides[0].values.motion.speed")

func test_resolve_replaces_lists_as_one_leaf_and_does_not_share_mutable_values() -> void:
	var resolver = ParamResolverScript.new()
	var defaults: Array = [{"template_id": "one"}, {"template_id": "two"}]
	var cfg: Dictionary = {
		"bricks": [{"default_cfg": {"params": {"templates": defaults}}, "author_params": ["params.templates"], "locked_params": {}, "relic_params": {"params.templates": "可改"}}],
		"params": {"templates": [{"template_id": "replacement"}]},
	}

	var result: Dictionary = resolver.resolve(cfg)
	assert_true(result.ok)
	assert_eq(result.resolved["params"]["templates"].size(), 1)
	result.resolved["params"]["templates"].append({"template_id": "runtime_only"})
	assert_eq(defaults.size(), 2)
	assert_eq(cfg["bricks"][0]["default_cfg"]["params"]["templates"].size(), 2)
