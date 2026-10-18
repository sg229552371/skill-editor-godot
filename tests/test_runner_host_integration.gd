extends GutTest

const Runner = preload("res://skill_core/runtime/preview_runner.gd")
const RunnerCases = preload("res://tests/test_preview_runner.gd")


class ExtraKeyRunner extends Runner:
	func _advance_hosts(_tick: int) -> Dictionary:
		return _consume_emissions({"spawn": [], "attach": [], "events": [], "records": [], "unexpected": []})


# Frozen T-050 start() read before the integration edits. The unchanged runtime
# kernels stay inherited; this reference never calls the new host/root helpers.
class FrozenRunner extends Runner:
	func start(cfg: Variant, options: Dictionary) -> Dictionary:
		if _running:
			return {"ok": false, "path": "start", "error": "Stop the current preview before starting another", "diagnostics": []}
		_clear()
		var diagnostics: Array = Codec.validate_structure(cfg)
		if not diagnostics.is_empty():
			return _failure("cfg", "CFG structure rejected", diagnostics)
		var schema: RefCounted = Schema.new()
		if not schema.configure():
			return _failure("schema", schema.last_error)
		var checked: Dictionary = schema.validate(cfg)
		if not checked["ok"]:
			return _failure("cfg", "CFG schema rejected", checked["diagnostics"])
		_cfg = cfg.duplicate(true)
		_fingerprint = JSON.stringify(_cfg, "", true, true).sha256_text()
		var resolved: Dictionary = Resolver.new().resolve(_cfg)
		if not resolved["ok"]:
			return _failure("params", "Parameter resolution rejected", resolved["diagnostics"])
		var params: Variant = resolved["resolved"].get("params", null)
		if not params is Dictionary:
			return _failure("params", "No resolved params")
		_params = params.duplicate(true)
		var configuration: Variant = options.get("project_config", null)
		if not options.has("project_config"):
			configuration = _read_json(CONFIG_PATH)
		if not configuration is Dictionary:
			return _failure("project_config", "Missing project configuration object")
		_config = configuration.duplicate(true)
		var rate: Variant = _config.get("tick_rate", null)
		if not _integer_number(rate) or rate < 1:
			return _failure("project_config.tick_rate", "A positive integral tick rate is required; no fallback")
		_tick_rate = int(rate)
		var limits: Variant = _config.get("project_limits", null)
		if not limits is Dictionary:
			return _failure("project_config.project_limits", "Missing project limits")
		var overrides: Dictionary = {}
		for section in ["hard_caps", "defaults"]:
			var entries: Variant = limits.get(section, null)
			if not entries is Dictionary or entries.is_empty():
				return _failure("project_config.project_limits." + section, "Missing nonempty limit section")
			var values: Dictionary = {}
			for key in entries:
				if str(key).begins_with("_"):
					continue
				if not _integer_number(entries[key]) or entries[key] < 0:
					return _failure("project_config.project_limits." + section + "." + str(key), "Expected nonnegative integer")
				values[key] = int(entries[key])
			overrides[section] = values
		var seed_value: Variant = options.get("seed", null)
		if not seed_value is int:
			return _failure("seed", "Explicit integer logic seed required")
		_clock = Clock.new(seed_value)
		_derive_meta = _read_json(Derive.META_PATH)
		_settle_meta = _read_json(Settle.META_PATH)
		_shape_meta = _read_json(Shape.META_PATH)
		if _derive_meta.is_empty() or _settle_meta.is_empty() or _shape_meta.is_empty():
			return _failure("metadata", "Missing derivation, shape or settlement metadata")
		for key in ["handlers", "template_families", "motion_inputs", "derivation_bindings"]:
			var value: Variant = options.get(key, null)
			if key == "motion_inputs" and value == null:
				value = {}
			if not value is Dictionary:
				return _failure(key, "Expected resolved runtime table")
		_handlers = options["handlers"].duplicate()
		_families = options["template_families"].duplicate(true)
		var input_table: Variant = options.get("motion_inputs", null)
		_motion_inputs = input_table.duplicate(true) if input_table is Dictionary else {}
		for id in _motion_inputs:
			if not _motion_inputs[id] is Dictionary:
				return _failure("motion_inputs." + str(id), "Expected motion inputs object")
			var inputs: Dictionary = _motion_inputs[id]
			if inputs.has("flight_seconds"):
				if inputs.has("flight_ticks") or not _number(inputs["flight_seconds"]) or inputs["flight_seconds"] <= 0:
					return _failure("motion_inputs." + str(id) + ".flight_seconds", "Require positive seconds and no flight_ticks")
				var flight_ticks: float = ceil(float(inputs["flight_seconds"]) * _tick_rate)
				if not _integer_number(flight_ticks) or flight_ticks < 1:
					return _failure("motion_inputs." + str(id) + ".flight_seconds", "Flight duration overflows tick representation")
				inputs["flight_ticks"] = int(flight_ticks)
				inputs.erase("flight_seconds")
		var templates: Variant = _params.get("templates", null)
		if not templates is Array or templates.is_empty():
			return _failure("params.templates", "A nonempty template registry is required")
		for index in range(templates.size()):
			var template: Dictionary = templates[index]
			var id: String = template["template_id"]
			if id.is_empty() or _templates.has(id):
				return _failure("params.templates[%d].template_id" % index, "Missing or duplicate template identity")
			if not _families.get(id, null) is String or _families[id].is_empty():
				return _failure("template_families." + id, "Explicit resolved family identity required")
			for section in ["cast", "timing", "attached", "summon", "emission"]:
				if template.has(section) and not template[section].is_empty():
					return _failure("params.templates[%d].%s" % [index, section], "Host adapter not implemented in T-050")
			if template["carrier"] != Body.CARRIER_INDEPENDENT or not template.get("motion", null) is Dictionary:
				return _failure("params.templates[%d].motion" % index, "This sandbox requires independent motion")
			if not FINISH_REASONS.has(template["motion"].get("mode", null)):
				return _failure("params.templates[%d].motion.mode" % index, "No sandbox termination adapter for this motion mode")
			_templates[id] = template.duplicate(true)
			var probe: RefCounted = Body.create(template["carrier"], template, 0)
			if probe == null or _build_entity(probe, id, null).is_empty():
				return _failure("params.templates[%d]" % index, "Runtime preflight failed: " + last_error)
		var targets: Variant = options.get("targets", null)
		if not targets is Array:
			return _failure("targets", "Explicit target roster required (empty is allowed)")
		_targets = targets.duplicate(true)
		if not _valid_targets():
			return _failure("targets", last_error)
		var root_inputs: Variant = options.get("roots", null)
		if not root_inputs is Array or root_inputs.is_empty():
			return _failure("roots", "Explicit nonempty root launch list required")
		var roots: Array = root_inputs.duplicate(true)
		for root in roots:
			if not root is Dictionary or not _templates.has(root.get("template_id", null)) or not root.get("shot_id", null) is String or root["shot_id"].is_empty():
				return _failure("roots", "Each launch needs a registered template_id and actual shot_id")
		_derive = Derive.new(Derive.META_PATH, null, Derive.PARAMS_PATH, Derive.LIMITS_PATH, overrides)
		if not _derive.configure(_params, _clock, options["derivation_bindings"]):
			return _failure("params", _derive.last_error)
		var roles: Dictionary = _derive_meta["budget_roles"]
		var capacity: int = int(_params.get(roles["cast"], overrides["defaults"][roles["cast"]]))
		_budget = Budget.new()
		if not _budget.configure(_budget_policy(capacity), overrides):
			return _failure("budget", _budget.last_error)
		_family = Family.new()
		if not _family.configure(_clock, FAMILY_BINDINGS):
			return _failure("family", _family.last_error)
		_cast_id = "preview:%d" % _run_seq
		_run_seq += 1
		for launch in roots:
			var id: String = "%s:root:%d" % [_cast_id, _root_seq]
			_root_seq += 1
			if launch.has("instance_id"):
				_notices.append({"path": "roots.instance_id", "suggested": launch["instance_id"], "assigned": id,
					"valid_suggestion": launch["instance_id"] is String and not launch["instance_id"].is_empty()})
			var admission: Dictionary = _budget.admit_root(id, [])
			if not admission["ok"]:
				return _failure("budget", admission["error"])
			if not admission["admitted"]:
				continue
			var template_id: String = launch["template_id"]
			var body_cfg: Dictionary = _templates[template_id].duplicate(true)
			body_cfg["body_id"] = id
			var body: RefCounted = Body.create(body_cfg["carrier"], body_cfg, 0)
			if not _derive.register_root(body, template_id, {"origin_skill": _cfg["skill_id"], "origin_cast_id": _cast_id}):
				return _failure("roots", _derive.last_error)
			var entity: Dictionary = _build_entity(body, template_id, null)
			if entity.is_empty():
				_derive.purge(id)
				return _failure("roots", "Runtime adapter initialization failed: " + last_error)
			_entities[id] = entity
			_facts[id] = {"family_id": id + ":" + _families[template_id], "shot_id": launch["shot_id"], "independent": true}
		if _entities.is_empty() or not _family.sync_instances(_derive.snapshot_state(), _facts):
			return _failure("family", _family.last_error)
		_running = true
		if not _process_tick(false):
			return _failure("runtime", last_error)
		last_error = ""
		return {"ok": true, "fingerprint": _fingerprint, "tick_rate": _tick_rate, "diagnostics": [], "error": ""}

	func advance_ticks(count: int = 1) -> Dictionary:
		if not _running or count < 0:
			return _failure("advance_ticks", "Requires running preview and nonnegative tick count")
		for _index in range(count):
			_clock.tick()
			if not _process_tick(true):
				return _failure("runtime", last_error)
		return {"ok": true, "tick": _clock.snapshot_state()["tick"], "error": ""}


func _cfg(shots: Array = [2]) -> Dictionary:
	var cases: Node = autofree(RunnerCases.new())
	var cfg: Dictionary = cases._cfg()
	cfg["params"]["templates"][0]["derivations"] = []
	cfg["params"]["templates"][0]["cast"] = {"windup_ticks": shots[0],
		"shot_ticks": shots.duplicate(), "shot_count": shots.size(), "cooldown_seconds": 1.0}
	return cfg


func _options() -> Dictionary:
	var cases: Node = autofree(RunnerCases.new())
	var options: Dictionary = cases._options()
	options["targets"] = []
	return options


func _start(runner: RefCounted, cfg: Dictionary, options: Dictionary) -> bool:
	var result: Dictionary = runner.start(cfg, options)
	assert_true(result["ok"], str(result))
	return result["ok"]


func test_no_cast_matches_frozen_t050_snapshot_json_each_tick():
	var cases: Node = autofree(RunnerCases.new())
	var cfg: Dictionary = cases._cfg()
	var before: Dictionary = cfg.duplicate(true)
	var options: Dictionary = cases._options()
	options["roots"][0]["instance_id"] = "suggested_id"
	var runner: RefCounted = Runner.new()
	var frozen: RefCounted = FrozenRunner.new()
	if not _start(frozen, cfg, options) or not _start(runner, cfg, options):
		return
	assert_eq(frozen.snapshot_state()["entities"].size(), 1)
	assert_eq(JSON.stringify(runner.snapshot_state(), "", true, true),
		JSON.stringify(frozen.snapshot_state(), "", true, true), "Every snapshot field at tick 0")
	for tick in range(1, 19):
		assert_true(frozen.advance_ticks()["ok"], frozen.last_error)
		assert_true(runner.advance_ticks()["ok"], runner.last_error)
		assert_eq(JSON.stringify(runner.snapshot_state(), "", true, true),
			JSON.stringify(frozen.snapshot_state(), "", true, true), "Every snapshot field at tick %d" % tick)
	var state: Dictionary = frozen.snapshot_state()
	assert_eq(state["entities"].size(), 3)
	assert_eq(state["events"].size(), 5)
	assert_eq(state["records"].size(), 2)
	assert_eq(state["targets"][0]["hp"], 90.0)
	assert_eq(state["notices"].size(), 1)
	assert_eq(cfg, before, "CFG cannot acquire runtime fields")


func test_cast_start_accepts_empty_windup_and_syncs_family():
	var runner: RefCounted = Runner.new()
	var options: Dictionary = _options()
	options["targets"] = [{"target_id": "first_contact", "position": Vector2(1, 0),
		"alive": true, "hp": 100.0, "invulnerable": false, "evade": {}, "immune": {}}]
	if not _start(runner, _cfg(), options):
		return
	var state: Dictionary = runner.snapshot_state()
	assert_true(state["running"])
	assert_eq(state["clock"]["tick"], 0)
	assert_eq(state["entities"].size(), 0)
	assert_eq(state["budget"]["occupied"], 0)
	assert_true(runner.advance_ticks(3)["ok"], runner.last_error)
	var after: Dictionary = runner.snapshot_state()
	assert_eq(after["entities"].size(), 1)
	assert_eq(after["records"].size(), 1, "The new root must use real family facts for an actual contact")
	assert_eq(after["targets"][0]["hp"], 90.0)


func test_shot_two_adds_exactly_one_root_against_zero_baseline():
	var runner: RefCounted = Runner.new()
	if not _start(runner, _cfg(), _options()):
		return
	var baseline: int = runner.snapshot_state()["entities"].size()
	assert_eq(baseline, 0)
	assert_true(runner.advance_ticks()["ok"], runner.last_error)
	assert_eq(runner.snapshot_state()["clock"]["tick"], 1)
	assert_eq(runner.snapshot_state()["entities"].size(), baseline)
	assert_true(runner.advance_ticks()["ok"], runner.last_error)
	assert_eq(runner.snapshot_state()["clock"]["tick"], 2)
	assert_eq(runner.snapshot_state()["entities"].size() - baseline, 1)
	assert_true(runner.advance_ticks()["ok"], runner.last_error)
	assert_eq(runner.snapshot_state()["entities"].size() - baseline, 1)


func test_shot_zero_is_consumed_during_start():
	var runner: RefCounted = Runner.new()
	if not _start(runner, _cfg([0]), _options()):
		return
	var state: Dictionary = runner.snapshot_state()
	assert_eq(state["clock"]["tick"], 0)
	assert_eq(state["entities"].keys(), ["preview:0:root:0"])
	assert_eq(state["budget"]["occupied"], 1)
	assert_true(runner.advance_ticks()["ok"], runner.last_error)
	assert_eq(runner.snapshot_state()["entities"].size(), 1)


func test_shots_two_four_have_exact_increment_ticks():
	var runner: RefCounted = Runner.new()
	if not _start(runner, _cfg([2, 4]), _options()):
		return
	var baseline: int = runner.snapshot_state()["entities"].size()
	assert_eq(baseline, 0)
	var previous: int = baseline
	var release_ticks: Array = []
	for tick in range(1, 7):
		assert_true(runner.advance_ticks()["ok"], runner.last_error)
		var state: Dictionary = runner.snapshot_state()
		assert_eq(state["clock"]["tick"], tick)
		var current: int = state["entities"].size()
		if current != previous:
			assert_eq(current - previous, 1)
			release_ticks.append(tick)
		previous = current
	assert_eq(release_ticks, [2, 4])
	assert_eq(previous - baseline, 2)
	assert_eq(runner.snapshot_state()["entities"].keys(), ["preview:0:root:0", "preview:0:root:1"])


func test_windup_interrupt_entry_not_available():
	pending("Runner has stop(), but no cast interrupt/context update entry; do not simulate one")


func test_other_sections_remain_rejected_with_section_names():
	var sections: Dictionary = {"timing": {"start_delay_ticks": 2},
		"attached": {"anchor_source": "caster"}, "summon": {"summon_cap": 1},
		"emission": {"count": 1}}
	var checked: int = 0
	for section in sections:
		var cfg: Dictionary = _cfg()
		cfg["params"]["templates"][0].erase("cast")
		cfg["params"]["templates"][0][section] = sections[section]
		var runner: RefCounted = Runner.new()
		var result: Dictionary = runner.start(cfg, _options())
		assert_false(result["ok"], section)
		assert_eq(result["path"], "params.templates[0]." + section)
		assert_true(result["error"].contains("Host adapter"), str(result))
		assert_true(result["error"].contains(section), str(result))
		assert_eq(runner.snapshot_state()["entities"].size(), 0)
		checked += 1
	assert_eq(checked, 4)


func test_fifth_emissions_key_fails_start_and_names_key():
	var baseline: RefCounted = Runner.new()
	if not _start(baseline, _cfg(), _options()):
		return
	assert_true(baseline.snapshot_state()["running"])
	var runner: RefCounted = ExtraKeyRunner.new()
	var result: Dictionary = runner.start(_cfg(), _options())
	assert_false(result["ok"])
	assert_eq(result["path"], "emissions.unexpected")
	assert_true(result["error"].contains("unexpected"))
	assert_false(runner.snapshot_state()["running"])
	assert_eq(runner.snapshot_state()["entities"].size(), 0)


func test_emissions_append_to_existing_streams_and_copy_payloads():
	var runner: RefCounted = Runner.new()
	if not _start(runner, _cfg(), _options()):
		return
	var before: Dictionary = runner.snapshot_state()
	var emissions: Dictionary = {"spawn": [], "attach": [],
		"events": [{"type": "vanish", "tick": 0, "body_id": "host_test", "reason": "expired"}],
		"records": [{"type": "cast_started", "tick": 0}]}
	var result: Dictionary = runner._consume_emissions(emissions)
	assert_true(result["ok"], str(result))
	var after: Dictionary = runner.snapshot_state()
	assert_eq(after["events"].size() - before["events"].size(), 1)
	assert_eq(after["records"].size() - before["records"].size(), 1)
	assert_eq(after["events"][-1], emissions["events"][0])
	assert_eq(after["records"][-1], emissions["records"][0])
	emissions["events"][0]["reason"] = "changed_after_consume"
	emissions["records"][0]["tick"] = 99
	assert_eq(runner.snapshot_state()["events"][-1]["reason"], "expired")
	assert_eq(runner.snapshot_state()["records"][-1]["tick"], 0)


func test_cast_budget_rejections_preserve_root_allocation_and_drop_stream():
	var cfg: Dictionary = _cfg([0, 2])
	cfg["params"]["cast_budget"] = 1
	var runner: RefCounted = Runner.new()
	if not _start(runner, cfg, _options()):
		return
	assert_eq(runner.snapshot_state()["entities"].size(), 1)
	assert_true(runner.advance_ticks(2)["ok"], runner.last_error)
	var state: Dictionary = runner.snapshot_state()
	assert_eq(state["entities"].keys(), ["preview:0:root:0"])
	assert_eq(state["budget"]["occupied"], 1)
	assert_eq(state["budget"]["drops"].size(), 1)
	assert_eq(state["events"].size(), 0)
	assert_eq(state["records"].size(), 0)
	assert_eq(runner._root_seq, 2, "Rejected root still consumes its allocation sequence")


func test_restart_discards_old_host_schedule():
	var runner: RefCounted = Runner.new()
	if not _start(runner, _cfg([2, 4]), _options()):
		return
	assert_true(runner.stop()["ok"])
	if not _start(runner, _cfg([0]), _options()):
		return
	assert_eq(runner.snapshot_state()["entities"].keys(), ["preview:1:root:0"])
	assert_true(runner.advance_ticks(4)["ok"], runner.last_error)
	assert_eq(runner.snapshot_state()["entities"].size(), 1, "Prior cast must not launch at ticks 2 or 4")


func test_invalid_cast_count_returns_qualified_path_and_original_error():
	var cfg: Dictionary = _cfg()
	cfg["params"]["templates"][0]["cast"]["shot_count"] = 2
	var runner: RefCounted = Runner.new()
	var result: Dictionary = runner.start(cfg, _options())
	assert_false(result["ok"])
	assert_eq(result["path"], "params.templates[0].cast.shot_count")
	assert_eq(result["error"], "shot_count=2 does not match shot_ticks.size=1")
	assert_false(runner.snapshot_state()["running"])
	assert_eq(runner.snapshot_state()["entities"].size(), 0)
