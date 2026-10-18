extends GutTest

const RunDiff = preload("res://skill_core/runtime/run_diff.gd")
const RunnerScript = preload("res://skill_core/runtime/preview_runner.gd")
const ClockScript = preload("res://skill_core/runtime/sim_clock.gd")

# Contract double for isolated error/bound tests; real-runner tests below are
# mandatory, especially the presentation RNG test (not proved by this double).
class TraceRunner extends RefCounted:
	var clock: RefCounted
	var cfg_copy: Dictionary = {}
	var advance_count: int = 0
	var starts: int = 0
	var stops: int = 0
	var reject_advance: bool = false

	func start(cfg: Variant, options: Dictionary) -> Dictionary:
		cfg_copy = cfg.duplicate(true)
		clock = ClockScript.new(options["seed"])
		advance_count = 0
		starts += 1
		return {"ok": true, "error": ""}

	func advance_ticks(count: int = 1) -> Dictionary:
		if reject_advance:
			return {"ok": false, "error": "injected advance failure"}
		for _index in range(count):
			clock.tick()
		advance_count += count
		return {"ok": true, "error": ""}

	func snapshot_state() -> Dictionary:
		return {"clock": clock.snapshot_state(), "entities": [
			{"position": Vector2(clock.snapshot_state()["tick"], 0), "amount": cfg_copy["amount"]}]}

	func stop() -> Dictionary:
		stops += 1
		return {"ok": true}

	func presentation_random() -> float:
		return clock.rng_presentation().randf()


func _settings() -> Dictionary:
	return {"limits": {"max_trace_ticks": 24}, "runner_options": {"seed": 17}}


func _configured(options: Dictionary) -> RefCounted:
	var diff: RefCounted = RunDiff.new()
	var result: Dictionary = diff.configure(options)
	assert_true(result["ok"], str(result))
	return diff


func _fake_capture(diff: RefCounted, ticks: int) -> Dictionary:
	var runner: RefCounted = TraceRunner.new()
	assert_true(runner.start({"amount": 10}, {"seed": 17})["ok"])
	return diff.capture(runner, ticks)


func _assert_trace_equal(left: Array, right: Array, count: int):
	assert_eq(left.size(), count, "Nonempty, exact-length trace required")
	assert_eq(right.size(), count)
	if left.size() != count or right.size() != count:
		return
	for index in range(count):
		assert_eq(left[index]["tick"], index)
		assert_true(left[index]["tick"] is int)
		assert_eq(JSON.stringify(left[index]), JSON.stringify(right[index]), "tick %d" % index)


func test_same_input_seed_capture_and_equal_contract():
	var diff: RefCounted = _configured(_settings())
	var first: Dictionary = _fake_capture(diff, 10)
	var second: Dictionary = _fake_capture(diff, 10)
	assert_true(first["ok"], str(first))
	assert_true(second["ok"], str(second))
	_assert_trace_equal(first["trace"], second["trace"], 10)
	var result: Dictionary = diff.compare(first["trace"], second["trace"])
	assert_true(result["ok"])
	assert_true(result["equal"])
	assert_eq(result["first_diff_index"], -1)
	assert_eq(result["path"], "")
	assert_eq(first["trace"][7]["entities"][0]["position"]["x"], JSON.stringify(7.0))


func _change_tick_seven(index: int, snapshot: Dictionary, _runner: Variant):
	if index == 7:
		snapshot["entities"][0]["position"]["x"] = "999.0"


func test_first_difference_tick_seven_names_leaf_without_mutating_runner():
	var baseline_diff: RefCounted = _configured(_settings())
	var baseline: Dictionary = _fake_capture(baseline_diff, 10)
	var settings: Dictionary = _settings()
	settings["post_tick_hook"] = _change_tick_seven
	var changed_diff: RefCounted = _configured(settings)
	var runner: RefCounted = TraceRunner.new()
	assert_true(runner.start({"amount": 10}, {"seed": 17})["ok"])
	var changed: Dictionary = changed_diff.capture(runner, 10)
	assert_true(baseline["ok"])
	assert_true(changed["ok"], str(changed))
	assert_eq(baseline["trace"].size(), 10)
	assert_eq(changed["trace"].size(), 10)
	if baseline["trace"].size() != 10 or changed["trace"].size() != 10:
		return
	assert_ne(JSON.stringify(baseline["trace"][7]), JSON.stringify(changed["trace"][7]))
	assert_eq(JSON.stringify(baseline["trace"][6]), JSON.stringify(changed["trace"][6]))
	assert_eq(JSON.stringify(baseline["trace"][8]), JSON.stringify(changed["trace"][8]))
	var result: Dictionary = changed_diff.compare(baseline["trace"], changed["trace"])
	assert_true(result["ok"])
	assert_false(result["equal"])
	assert_eq(result["first_diff_index"], 7)
	assert_eq(result["path"], "trace[7].entities[0].position.x")
	assert_eq(result["left"], JSON.stringify(7.0))
	assert_eq(result["right"], "999.0")
	assert_eq(JSON.stringify(runner.snapshot_state()["entities"][0]["position"]), JSON.stringify(Vector2(9, 0)))


func _change_three_ticks(index: int, snapshot: Dictionary, _runner: Variant):
	if index >= 5 and index <= 7:
		snapshot["entities"][0]["amount"] = "777"


func test_first_of_three_consecutive_differences_is_exactly_five():
	var plain: RefCounted = _configured(_settings())
	var baseline: Dictionary = _fake_capture(plain, 10)
	var settings: Dictionary = _settings()
	settings["post_tick_hook"] = _change_three_ticks
	var changed_diff: RefCounted = _configured(settings)
	var changed: Dictionary = _fake_capture(changed_diff, 10)
	assert_true(baseline["ok"])
	assert_true(changed["ok"])
	assert_eq(baseline["trace"].size(), 10)
	assert_eq(changed["trace"].size(), 10)
	if baseline["trace"].size() != 10 or changed["trace"].size() != 10:
		return
	for index in range(10):
		if index >= 5 and index <= 7:
			assert_ne(JSON.stringify(baseline["trace"][index]), JSON.stringify(changed["trace"][index]))
		else:
			assert_eq(JSON.stringify(baseline["trace"][index]), JSON.stringify(changed["trace"][index]))
	var result: Dictionary = changed_diff.compare(baseline["trace"], changed["trace"])
	assert_true(result["ok"])
	assert_false(result["equal"])
	assert_eq(result["first_diff_index"], 5)
	assert_eq(result["path"], "trace[5].entities[0].amount")


func _real_cfg() -> Dictionary:
	# Small standalone fixture: real flight, hit policy and probabilistic evade.
	# No dependency on T-052's concurrently authored fixture files.
	return {"schema_version": "0.1", "skill_id": "mage_active_determinism",
		"meta": {"role": "mage", "category": "active", "short_name": "determinism",
			"name": "Determinism", "version": "1", "author": "test"}, "bricks": [],
		"params": {"carrier": "independent", "lifetime_ticks": 12,
			"templates": [{"template_id": "root_recipe", "carrier": "independent", "lifetime_ticks": 12,
				"targeting": {"target_group": "enemy"}, "motion": {"mode": "straight", "speed": 1.0},
				"geometry": {"shape": "circle", "radius": 0.01},
				"hit_policy": {"per_target_limit": 1, "max_hits": 1},
				"parts": [{"part_index": 0, "type": "physical", "amount": 10.0, "evadable": true},
					{"part_index": 1, "type": "physical", "amount": 1.0, "evadable": false}], "derivations": []}],
			"cast_budget": 3, "max_generation": 2, "split_budget": 0, "chain_remaining": 0,
			"safety": {"max_chain_depth": 3}},
		"presentation": {"fx": {}, "sfx": {"max_concurrency": 0}, "anim": {},
			"trail": {"carrier": "independent"}, "camera": {}, "damage_number": {}, "status_icon": {}},
		"runtime_hints": {}}


func _damage(part: Dictionary, record: Dictionary, target: Dictionary) -> bool:
	if part["type"] != "physical":
		return false
	target["hp"] -= record["value"]
	target["alive"] = target["hp"] > 0.0
	return true


func _real_options() -> Dictionary:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/params_meta.json"))
	var handlers: Dictionary = {}
	for kind in meta["enums"]["part_type"]:
		if not str(kind).begins_with("_"):
			handlers[kind] = _damage
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/project_config.json"))
	return {"seed": 17, "project_config": config, "handlers": handlers,
		"roots": [{"template_id": "root_recipe", "shot_id": "shot_a"}],
		"template_families": {"root_recipe": "single_family"}, "derivation_bindings": {}, "motion_inputs": {},
		"targets": [{"target_id": "enemy_one", "position": Vector2(5, 0), "alive": true, "hp": 100.0,
			"invulnerable": false, "evade": {"physical": 0.5}, "immune": {}}]}


var _presentation_calls: int = 0


func _consume_presentation(_index: int, _snapshot: Dictionary, runner: Variant):
	for _draw in range(11):
		runner.presentation_random()
		_presentation_calls += 1


func test_real_runner_presentation_rng_does_not_pollute_logic_trace():
	var cfg: Dictionary = _real_cfg()
	var before: Dictionary = cfg.duplicate(true)
	var options: Dictionary = _real_options()
	var first: RefCounted = RunnerScript.new()
	var second: RefCounted = RunnerScript.new()
	var started_first: Dictionary = first.start(cfg, options)
	var started_second: Dictionary = second.start(cfg, options)
	assert_true(started_first["ok"], str(started_first))
	assert_true(started_second["ok"], str(started_second))
	if not started_first["ok"] or not started_second["ok"]:
		first.stop()
		second.stop()
		return
	var plain: RefCounted = _configured(_settings())
	var baseline: Dictionary = plain.capture(first, 10)
	var settings: Dictionary = _settings()
	settings["post_tick_hook"] = _consume_presentation
	var noisy: RefCounted = _configured(settings)
	_presentation_calls = 0
	var changed: Dictionary = noisy.capture(second, 10)
	assert_true(baseline["ok"], str(baseline))
	assert_true(changed["ok"], str(changed))
	assert_eq(_presentation_calls, 110, "Real second runner received extra presentation draws")
	_assert_trace_equal(baseline["trace"], changed["trace"], 10)
	var result: Dictionary = noisy.compare(baseline["trace"], changed["trace"])
	assert_true(result["ok"], str(result))
	assert_true(result["equal"])
	assert_eq(result["first_diff_index"], -1)
	assert_eq(result["path"], "")
	var raw_first: Dictionary = first.snapshot_state()
	var raw_second: Dictionary = second.snapshot_state()
	assert_eq(raw_first["events"].size(), 1, "Nonempty real hit at tick 5")
	assert_eq(raw_first["records"].size(), 1, "Actual settlement, not empty determinism")
	assert_ne(JSON.stringify(raw_first["clock"]["presentation_rng"]), JSON.stringify(raw_second["clock"]["presentation_rng"]))
	if baseline["trace"].size() == 10:
		assert_true(baseline["trace"][0]["clock"].has("logic_rng"))
		assert_false(baseline["trace"][0]["clock"].has("presentation_rng"))
		assert_ne(JSON.stringify(baseline["trace"][0]["clock"]["logic_rng"]),
			JSON.stringify(baseline["trace"][9]["clock"]["logic_rng"]), "Evade must consume actual logic RNG")
	assert_eq(JSON.stringify(cfg), JSON.stringify(before), "capture must not write back into CFG")
	first.stop()
	second.stop()


func _fresh_runner() -> RefCounted:
	return RunnerScript.new()


func test_real_diff_runs_same_seed_fresh_identity_and_cfg_not_written_back():
	var cfg: Dictionary = _real_cfg()
	var before: Dictionary = cfg.duplicate(true)
	var settings: Dictionary = _settings()
	settings["runner_options"] = _real_options()
	settings["runner_factory"] = _fresh_runner
	var diff: RefCounted = _configured(settings)
	var result: Dictionary = diff.diff_runs(RunnerScript.new(), cfg, 10)
	assert_true(result["ok"], str(result))
	assert_eq(JSON.stringify(cfg), JSON.stringify(before))
	if not result["ok"]:
		return
	assert_true(result["equal"])
	assert_eq(result["first_diff_index"], -1)
	assert_eq(result["path"], "")
	_assert_trace_equal(result["trace_a"], result["trace_b"], 10)
	assert_eq(result["trace_a"][9]["events"].size(), 1)
	assert_eq(result["trace_a"][9]["records"].size(), 1)
	assert_false(result["truncated"])


func test_diff_runs_contract_double_restarts_and_preserves_cfg():
	var diff: RefCounted = _configured(_settings())
	var cfg: Dictionary = {"amount": 10}
	var before: Dictionary = cfg.duplicate(true)
	var runner: RefCounted = TraceRunner.new()
	var result: Dictionary = diff.diff_runs(runner, cfg, 8)
	assert_true(result["ok"], str(result))
	assert_eq(JSON.stringify(cfg), JSON.stringify(before))
	assert_eq(runner.starts, 2)
	assert_eq(runner.stops, 4)
	if result["ok"]:
		assert_true(result["equal"])
		_assert_trace_equal(result["trace_a"], result["trace_b"], 8)


func test_unconfigured_methods_fail_explicitly():
	var diff: RefCounted = RunDiff.new()
	for result in [diff.capture(null, 1), diff.compare([{ "tick": 0 }], [{ "tick": 0 }]), diff.diff_runs(null, {}, 1)]:
		assert_false(result["ok"])
		assert_true(result["error"].contains("configure"))


func test_missing_runner_methods_are_named():
	var diff: RefCounted = _configured(_settings())
	for runner in [null, {}]:
		for result in [diff.capture(runner, 1), diff.diff_runs(runner, {"amount": 10}, 1)]:
			assert_false(result["ok"])
			for method in ["start", "advance_ticks", "snapshot_state", "stop"]:
				assert_true(result["error"].contains(method), str(result))


func test_unequal_trace_lengths_report_both_not_shorter_prefix():
	var diff: RefCounted = _configured(_settings())
	for traces in [[[{"tick": 0}], [{"tick": 0}, {"tick": 1}]],
		[[{"tick": 0}, {"tick": 1}], [{"tick": 0}]]]:
		var result: Dictionary = diff.compare(traces[0], traces[1])
		assert_false(result["ok"])
		assert_false(result["equal"])
		assert_true(result["error"].contains("left=%d" % traces[0].size()))
		assert_true(result["error"].contains("right=%d" % traces[1].size()))


func test_ticks_positive_limits_required_and_huge_request_truncated():
	var diff: RefCounted = RunDiff.new()
	for settings in [{}, {"limits": {}}, {"limits": {"max_trace_ticks": 0}},
		{"limits": {"max_trace_ticks": -1}}, {"limits": {"max_trace_ticks": 2.5}},
		{"limits": {"max_trace_ticks": "8"}}, {"limits": {"max_trace_ticks": INF}}]:
		var configured: Dictionary = diff.configure(settings)
		assert_false(configured["ok"])
		assert_true(configured["error"].contains("limits.max_trace_ticks"))
		assert_false(diff.capture(null, 1)["ok"])
	var options: Dictionary = _settings()
	# JSON-injected limits are floats; changing the injected cap changes output.
	for cap in [3, 8]:
		options["limits"] = JSON.parse_string('{"max_trace_ticks":%d}' % cap)
		assert_true(diff.configure(options)["ok"])
		var runner: RefCounted = TraceRunner.new()
		assert_true(runner.start({"amount": 10}, {"seed": 17})["ok"])
		for invalid in [0, -1]:
			var failed: Dictionary = diff.capture(runner, invalid)
			assert_false(failed["ok"])
			assert_true(failed["error"].contains(str(invalid)))
			assert_eq(runner.advance_count, 0)
		var result: Dictionary = diff.capture(runner, 100000)
		assert_true(result["ok"], str(result))
		assert_true(result["truncated"])
		assert_eq(result["trace"].size(), cap)
		assert_eq(result["captured_ticks"], cap)
		assert_eq(result["requested_ticks"], 100000)
		assert_eq(runner.advance_count, cap - 1, "Do not advance 100000 and only truncate afterwards")
		assert_eq(result["trace"][cap - 1]["tick"], cap - 1)
		var replay: Dictionary = diff.diff_runs(TraceRunner.new(), {"amount": 10}, 100000)
		assert_true(replay["ok"], str(replay))
		if replay["ok"]:
			assert_true(replay["equal"])
			assert_true(replay["truncated"])
			assert_eq(replay["captured_ticks"], cap)


func test_changed_logic_seed_is_not_filtered_out():
	var diff: RefCounted = _configured(_settings())
	var first: RefCounted = TraceRunner.new()
	var second: RefCounted = TraceRunner.new()
	assert_true(first.start({"amount": 10}, {"seed": 17})["ok"])
	assert_true(second.start({"amount": 10}, {"seed": 18})["ok"])
	var left: Dictionary = diff.capture(first, 3)
	var right: Dictionary = diff.capture(second, 3)
	assert_true(left["ok"])
	assert_true(right["ok"])
	assert_eq(left["trace"].size(), 3)
	assert_eq(right["trace"].size(), 3)
	var result: Dictionary = diff.compare(left["trace"], right["trace"])
	assert_true(result["ok"])
	assert_false(result["equal"], "Do not achieve determinism by discarding all RNG state")
	assert_eq(result["first_diff_index"], 0)
	assert_eq(result["path"], "trace[0].clock.logic_rng.seed")


func test_leaf_structure_and_dictionary_order_are_deterministic():
	var diff: RefCounted = _configured(_settings())
	var left: Array = [{"tick": 0, "data": {"a": null, "b": [0.1 + 0.2]}}]
	var right: Array = [{"data": {"b": [0.3], "a": null}, "tick": 0}]
	var equivalent: Dictionary = diff.compare(left, right)
	assert_true(equivalent["ok"])
	assert_true(equivalent["equal"], "Use JSON's trajectory number representation, not float ==")
	right[0]["data"]["b"][0] = 0.4
	var leaf: Dictionary = diff.compare(left, right)
	assert_true(leaf["ok"])
	assert_eq(leaf["first_diff_index"], 0)
	assert_eq(leaf["path"], "trace[0].data.b[0]")
	right[0]["data"]["b"].append(1)
	left[0]["data"]["b"][0] = 0.4
	var extra: Dictionary = diff.compare(left, right)
	assert_true(extra["ok"])
	assert_false(extra["equal"])
	assert_eq(extra["path"], "trace[0].data.b[1]")
	assert_false(diff.compare([], [])["ok"], "Empty traces cannot certify acceptance")
	assert_false(diff.compare([{}], [{}])["ok"])


func test_whitelist_missing_fields_and_advance_errors_are_explicit():
	var settings: Dictionary = _settings()
	settings["trace_fields"] = ["entities", "clock.logic_rng"]
	var diff: RefCounted = _configured(settings)
	var capture: Dictionary = _fake_capture(diff, 3)
	assert_true(capture["ok"], str(capture))
	assert_eq(capture["trace"].size(), 3)
	if capture["trace"].size() == 3:
		assert_true(capture["trace"][0].has("entities"))
		assert_true(capture["trace"][0].has("tick"))
		assert_true(capture["trace"][0]["clock"].has("logic_rng"))
		assert_false(capture["trace"][0]["clock"].has("paused"))
	settings["trace_fields"] = ["absent_field"]
	assert_true(diff.configure(settings)["ok"])
	var missing: Dictionary = _fake_capture(diff, 3)
	assert_false(missing["ok"])
	assert_true(missing["error"].contains("absent_field"))
	assert_true(diff.configure(_settings())["ok"])
	var runner: RefCounted = TraceRunner.new()
	assert_true(runner.start({"amount": 10}, {"seed": 17})["ok"])
	runner.reject_advance = true
	var failed: Dictionary = diff.capture(runner, 3)
	assert_false(failed["ok"])
	assert_true(failed["error"].contains("advance_ticks"))
	assert_eq(failed["trace"].size(), 1, "Partial trace must never be certified as successful")
	var replay: Dictionary = diff.diff_runs(runner, {"amount": 10}, 3)
	assert_false(replay["ok"])
	assert_true(replay["error"].contains("injected advance failure"))
	assert_eq(runner.stops, 2, "Failed replay still stops its runner")
