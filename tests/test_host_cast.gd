extends "res://addons/gut/test.gd"

const CastScript = preload("res://skill_core/runtime/hosts/host_cast.gd")


func _request(windup: int = 2, shots: Array = [2]) -> Dictionary:
	return {"windup_ticks": windup, "shot_ticks": shots.duplicate(),
		"shot_count": shots.size(), "cooldown_seconds": 0.125}


func _project_config() -> Dictionary:
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/project_config.json"))
	assert_true(config is Dictionary, "Real project_config.json must parse")
	if not config is Dictionary:
		return {}
	return config


func _ctx(tick: int = 0) -> Dictionary:
	var config: Dictionary = _project_config()
	var rate: Variant = config.get("tick_rate", null)
	assert_true(rate is int or rate is float, "Project tick_rate must be numeric")
	if rate is int or rate is float:
		assert_true(is_finite(float(rate)) and float(rate) >= 1 and floor(float(rate)) == float(rate))
		# Most timing cases use normalized host input; raw JSON has its own regression below.
		config["tick_rate"] = int(rate)
	return {"tick": tick, "project_config": config, "template_id": "cast_recipe",
		"shot_id": "caller_shot", "origin": {"source_id": "caster"}, "parent_ref": "caller_parent"}


func _begin_state(adapter: RefCounted, request: Dictionary, ctx: Dictionary) -> Dictionary:
	assert_true(adapter.validate(request, ctx).get("ok", false), "Nonempty valid cast baseline")
	assert_gt(request["shot_ticks"].size(), 0, "No empty-schedule false positives")
	var result: Dictionary = adapter.begin(request, ctx)
	assert_true(result.get("ok", false), str(result))
	assert_true(result.get("state", null) is Dictionary, str(result))
	if not result.get("state", null) is Dictionary:
		return {}
	assert_eq(result["state"]["status"], "active")
	assert_eq(result["state"]["shot_ticks"], request["shot_ticks"])
	return result["state"]


func _advance(adapter: RefCounted, state: Dictionary, tick: int, ctx: Dictionary) -> Dictionary:
	var result: Dictionary = adapter.advance(state, tick, ctx)
	assert_true(result.get("ok", false), str(result))
	assert_true(result.get("state", null) is Dictionary, str(result))
	var emissions: Variant = result.get("emissions", null)
	assert_true(emissions is Dictionary, str(result))
	if emissions is Dictionary:
		assert_eq(emissions.size(), 4, "Only the frozen four emission keys are allowed")
		for key in ["spawn", "attach", "events", "records"]:
			assert_true(emissions.get(key, null) is Array, "Array emission required: " + key)
		for key in ["attach", "events", "records"]:
			assert_eq(emissions.get(key, null), [], "Cast only emits spawn")
	return result


func _assert_invalid(request: Dictionary, path: String):
	var adapter: RefCounted = CastScript.new()
	var ctx: Dictionary = _ctx()
	for result in [adapter.validate(request, ctx), adapter.begin(request, ctx)]:
		assert_false(result.get("ok", true), str(result))
		assert_eq(result.get("path", ""), path)
		assert_ne(str(result.get("code", "")), "")
		assert_ne(str(result.get("error", "")), "")


func test_ed17_09_windup_has_zero_spawn_every_tick_then_real_shot():
	var adapter: RefCounted = CastScript.new()
	var ctx: Dictionary = _ctx(11)
	var request: Dictionary = _request(3, [3])
	var state: Dictionary = _begin_state(adapter, request, ctx)
	if state.is_empty():
		return
	assert_eq(state["start_tick"], 11)
	var total: int = 0
	for tick in range(11, 14):
		var result: Dictionary = _advance(adapter, state, tick, ctx)
		assert_eq(result["emissions"]["spawn"].size(), 0, "Windup tick %d" % tick)
		total += result["emissions"]["spawn"].size()
		assert_eq(total, 0)
		assert_eq(result["state"]["status"], "active")
	var shot: Dictionary = _advance(adapter, state, 14, ctx)
	assert_eq(shot["emissions"]["spawn"].size(), 1, "Positive control: this schedule really fires")
	assert_eq(shot["state"]["status"], "done")


func test_ed17_10_single_shot_occurs_only_at_tick_two():
	var adapter: RefCounted = CastScript.new()
	var ctx: Dictionary = _ctx()
	var state: Dictionary = _begin_state(adapter, _request(), ctx)
	if state.is_empty():
		return
	var counts: Array = []
	for tick in range(6):
		var result: Dictionary = _advance(adapter, state, tick, ctx)
		counts.append(result["emissions"]["spawn"].size())
		if tick == 2:
			assert_eq(result["emissions"]["spawn"], [{"template_id": "cast_recipe",
				"shot_id": "caller_shot", "origin": {"source_id": "caster"}, "parent_ref": "caller_parent"}])
	assert_eq(counts, [0, 0, 1, 0, 0, 0])
	assert_eq(state["status"], "done")


func test_ed17_12_two_shots_have_exact_ticks_and_total():
	var adapter: RefCounted = CastScript.new()
	var ctx: Dictionary = _ctx()
	var state: Dictionary = _begin_state(adapter, _request(3, [3, 5]), ctx)
	if state.is_empty():
		return
	var counts: Array = []
	var fired_ticks: Array = []
	var total: int = 0
	for tick in range(8):
		var result: Dictionary = _advance(adapter, state, tick, ctx)
		var count: int = result["emissions"]["spawn"].size()
		counts.append(count)
		total += count
		if count > 0:
			fired_ticks.append(tick)
	assert_eq(counts, [0, 0, 0, 1, 0, 1, 0, 0])
	assert_eq(fired_ticks, [3, 5])
	assert_eq(total, 2)
	assert_eq(state["status"], "done")


func test_windup_interrupt_cancels_and_never_spawns():
	var adapter: RefCounted = CastScript.new()
	var ctx: Dictionary = _ctx()
	var request: Dictionary = _request(3, [3, 5])
	var state: Dictionary = _begin_state(adapter, request, ctx)
	if state.is_empty():
		return
	assert_eq(_advance(adapter, state, 0, ctx)["emissions"]["spawn"], [])
	var interrupted: Dictionary = ctx.duplicate(true)
	interrupted["interrupt"] = true
	var cancelled: Dictionary = _advance(adapter, state, 1, interrupted)
	assert_eq(cancelled["state"]["status"], "cancelled")
	assert_eq(cancelled["emissions"]["spawn"], [])
	for tick in range(2, 9):
		var result: Dictionary = _advance(adapter, state, tick, ctx)
		assert_eq(result["state"]["status"], "cancelled")
		assert_eq(result["emissions"], {"spawn": [], "attach": [], "events": [], "records": []})
	# Positive control with the identical request but no interruption.
	var control: RefCounted = CastScript.new()
	var control_state: Dictionary = _begin_state(control, request, ctx)
	if not control_state.is_empty():
		assert_eq(_advance(control, control_state, 3, ctx)["emissions"]["spawn"].size(), 1)


func test_interrupt_between_shots_suppresses_remaining_shot():
	var adapter: RefCounted = CastScript.new()
	var ctx: Dictionary = _ctx()
	var state: Dictionary = _begin_state(adapter, _request(3, [3, 5]), ctx)
	if state.is_empty():
		return
	assert_eq(_advance(adapter, state, 3, ctx)["emissions"]["spawn"].size(), 1)
	var interrupted: Dictionary = ctx.duplicate(true)
	interrupted["interrupt"] = true
	assert_eq(_advance(adapter, state, 4, interrupted)["state"]["status"], "cancelled")
	assert_eq(_advance(adapter, state, 5, ctx)["emissions"]["spawn"], [])


func test_ed17_19_cooldown_names_remaining_ticks_and_expires_exactly():
	var adapter: RefCounted = CastScript.new()
	var ctx: Dictionary = _ctx(10)
	var request: Dictionary = _request(1, [1, 3])
	var state: Dictionary = _begin_state(adapter, request, ctx)
	if state.is_empty():
		return
	var expected: int = int(ceil(float(request["cooldown_seconds"]) * float(ctx["project_config"]["tick_rate"])))
	assert_gt(expected, 1)
	assert_eq(state["cooldown_ticks"], expected)
	assert_eq(_advance(adapter, state, 11, ctx)["emissions"]["spawn"].size(), 1)
	assert_eq(_advance(adapter, state, 13, ctx)["emissions"]["spawn"].size(), 1)
	assert_eq(state["status"], "done")
	var next_ctx: Dictionary = ctx.duplicate(true)
	next_ctx["template_id"] = "different_recipe"
	next_ctx["shot_id"] = "different_caller_shot"
	next_ctx["tick"] = 14
	var blocked: Dictionary = adapter.begin(request, next_ctx)
	assert_false(blocked.get("ok", true), "Public cooldown must also block a different template")
	assert_eq(blocked.get("path", ""), "cooldown_seconds")
	assert_eq(blocked.get("code", ""), "CAST_COOLDOWN")
	assert_true(str(blocked.get("error", "")).contains("remaining ticks: %d" % (expected - 1)), str(blocked))
	next_ctx["tick"] = 13 + expected - 1
	var last_blocked: Dictionary = adapter.begin(request, next_ctx)
	assert_false(last_blocked.get("ok", true))
	assert_true(str(last_blocked.get("error", "")).contains("remaining ticks: 1"), str(last_blocked))
	next_ctx["tick"] = 13 + expected
	var ready: Dictionary = adapter.begin(request, next_ctx)
	assert_true(ready.get("ok", false), str(ready))
	if ready.get("state", null) is Dictionary:
		assert_eq(ready["state"]["start_tick"], 13 + expected)
		assert_eq(ready["state"]["shot_id"], "different_caller_shot")


func test_cooldown_conversion_uses_injected_nondefault_rate_and_ceiling():
	var adapter: RefCounted = CastScript.new()
	var ctx: Dictionary = _ctx()
	var alternate: int = int(ctx["project_config"]["tick_rate"]) + 7
	ctx["project_config"]["tick_rate"] = alternate
	var request: Dictionary = _request(0, [0])
	request["cooldown_seconds"] = 1.25 / float(alternate)
	var state: Dictionary = _begin_state(adapter, request, ctx)
	if state.is_empty():
		return
	assert_eq(state["cooldown_ticks"], 2, "1.25 ticks must ceil to two, at injected frequency")
	assert_eq(_advance(adapter, state, 0, ctx)["emissions"]["spawn"].size(), 1)
	ctx["tick"] = 1
	assert_false(adapter.begin(request, ctx).get("ok", true))
	ctx["tick"] = 2
	assert_true(adapter.begin(request, ctx).get("ok", false))


func test_real_project_config_json_integral_float_tick_rate_is_accepted():
	var adapter: RefCounted = CastScript.new()
	var config: Dictionary = _project_config()
	assert_true(config.get("tick_rate", null) is float, "Exercise raw JSON, not normalized test injection")
	var ctx: Dictionary = {"tick": 0, "project_config": config,
		"template_id": "cast_recipe", "shot_id": "raw_config_shot"}
	var request: Dictionary = _request()
	var checked: Dictionary = adapter.validate(request, ctx)
	assert_true(checked.get("ok", false), "Integral project JSON rate is valid: " + str(checked))
	var begun: Dictionary = adapter.begin(request, ctx)
	assert_true(begun.get("ok", false), str(begun))
	if begun.get("state", null) is Dictionary:
		assert_eq(begun["state"]["cooldown_ticks"], int(ceil(float(config["tick_rate"]) * float(request["cooldown_seconds"]))))


func test_count_mismatch_reports_both_values():
	var adapter: RefCounted = CastScript.new()
	var request: Dictionary = _request(2, [2, 4])
	request["shot_count"] = 3
	var result: Dictionary = adapter.validate(request, _ctx())
	assert_false(result.get("ok", true))
	assert_eq(result.get("path", ""), "shot_count")
	assert_eq(result.get("code", ""), "CAST_COUNT_MISMATCH")
	assert_true(str(result.get("error", "")).contains("shot_count=3"), str(result))
	assert_true(str(result.get("error", "")).contains("shot_ticks.size=2"), str(result))


func test_noninteger_shot_tick_has_exact_index():
	_assert_invalid(_request(2, [2, 3.5]), "shot_ticks[1]")


func test_negative_shot_tick_has_exact_index():
	_assert_invalid(_request(0, [-1]), "shot_ticks[0]")


func test_duplicate_shot_ticks_are_not_strictly_increasing():
	_assert_invalid(_request(2, [2, 2]), "shot_ticks[1]")


func test_descending_shot_ticks_have_exact_index():
	_assert_invalid(_request(2, [4, 3]), "shot_ticks[1]")


func test_shot_before_windup_has_exact_index():
	_assert_invalid(_request(3, [2]), "shot_ticks[0]")


func test_noninteger_and_negative_windup_are_rejected():
	for value in [1.5, -1, "2", null]:
		var request: Dictionary = _request()
		request["windup_ticks"] = value
		_assert_invalid(request, "windup_ticks")


func test_shot_count_minimum_one_and_integer_type():
	for value in [0, -1, 1.0, "1", null]:
		var request: Dictionary = _request()
		request["shot_count"] = value
		_assert_invalid(request, "shot_count")


func test_empty_or_nonarray_shot_ticks_are_rejected():
	for value in [[], "2", null]:
		var request: Dictionary = _request()
		request["shot_ticks"] = value
		_assert_invalid(request, "shot_ticks")


func test_nonpositive_or_nonnumeric_cooldown_is_rejected():
	for value in [0, -0.25, "1", null, INF, NAN]:
		var request: Dictionary = _request()
		request["cooldown_seconds"] = value
		_assert_invalid(request, "cooldown_seconds")


func test_missing_required_cast_fields_fail_without_defaults():
	for field in ["windup_ticks", "shot_ticks", "shot_count", "cooldown_seconds"]:
		var request: Dictionary = _request()
		request.erase(field)
		_assert_invalid(request, field)


func test_zero_windup_can_fire_at_start_tick():
	var adapter: RefCounted = CastScript.new()
	var ctx: Dictionary = _ctx(9)
	var state: Dictionary = _begin_state(adapter, _request(0, [0]), ctx)
	if state.is_empty():
		return
	assert_eq(_advance(adapter, state, 9, ctx)["emissions"]["spawn"].size(), 1)
	assert_eq(state["status"], "done")
	assert_eq(_advance(adapter, state, 10, ctx)["emissions"]["spawn"], [])


func test_repeated_advance_same_tick_cannot_duplicate_either_shot():
	var adapter: RefCounted = CastScript.new()
	var ctx: Dictionary = _ctx()
	var state: Dictionary = _begin_state(adapter, _request(2, [2, 4]), ctx)
	if state.is_empty():
		return
	for tick in [2, 4]:
		assert_eq(_advance(adapter, state, tick, ctx)["emissions"]["spawn"].size(), 1)
		assert_eq(_advance(adapter, state, tick, ctx)["emissions"]["spawn"], [])
		assert_eq(_advance(adapter, state, tick, ctx)["emissions"]["spawn"], [])
	assert_eq(state["next_index"], 2)
	assert_eq(state["status"], "done")


func test_begin_requires_caller_identity_and_does_not_mutate_request():
	var adapter: RefCounted = CastScript.new()
	var request: Dictionary = _request()
	var before: Dictionary = request.duplicate(true)
	for field in ["template_id", "shot_id"]:
		var missing: Dictionary = _ctx()
		missing.erase(field)
		var failed: Dictionary = adapter.begin(request, missing)
		assert_false(failed.get("ok", true))
		assert_eq(failed.get("path", ""), field)
		assert_eq(failed.get("code", ""), "INVALID_CAST_CONTEXT")
	var ctx: Dictionary = _ctx()
	var state: Dictionary = _begin_state(adapter, request, ctx)
	if state.is_empty():
		return
	assert_eq(_advance(adapter, state, 2, ctx)["emissions"]["spawn"][0]["shot_id"], ctx["shot_id"])
	assert_eq(request, before, "Runtime fields cannot leak into CFG request")


func test_missing_or_invalid_project_tick_rate_is_explicit_failure():
	var adapter: RefCounted = CastScript.new()
	var contexts: Array = [{}, {"project_config": {}}, {"project_config": {"tick_rate": 0}},
		{"project_config": {"tick_rate": -1}}, {"project_config": {"tick_rate": 2.5}}]
	for ctx in contexts:
		var failed: Dictionary = adapter.validate(_request(), ctx)
		assert_false(failed.get("ok", true))
		assert_eq(failed.get("path", ""), "project_config.tick_rate")
		assert_eq(failed.get("code", ""), "INVALID_CAST")
