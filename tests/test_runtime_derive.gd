extends GutTest

const DeriveScript = preload("res://skill_core/runtime/derive.gd")
const BodyScript = preload("res://skill_core/runtime/effect_body.gd")
const ClockScript = preload("res://skill_core/runtime/sim_clock.gd")
const ShapeScript = preload("res://skill_core/runtime/shape_hit.gd")
const SettleScript = preload("res://skill_core/runtime/settle.gd")


# These are explicit TEST project choices, not production defaults (U-16).
func _limits() -> Dictionary:
	return {"defaults": {"cast_budget": 20},
		"hard_caps": {"max_generation": 5, "cast_budget": 20, "max_chain_depth": 6}}


func _rule(event: String = "hit", reasons: Array = [], trigger: String = "first", child: String = "child") -> Dictionary:
	return {"trigger_id": trigger, "event": event, "reasons": reasons,
		"child_template": child, "count": 1}


func _template(id: String, rules: Array = []) -> Dictionary:
	return {"template_id": id, "carrier": "none", "lifetime_ticks": 0,
		"geometry": {"shape": "circle", "radius": 5},
		"hit_policy": {"per_target_limit": 1},
		"parts": [{"part_index": 0, "type": "physical", "amount": 10.0, "evadable": true}],
		"derivations": rules}


func _params(rules: Array) -> Dictionary:
	return {"max_generation": 4, "cast_budget": 20, "split_budget": 0, "chain_remaining": 0,
		"safety": {"max_chain_depth": 5},
		"templates": [_template("root", rules), _template("child")]}


func _bindings(params: Dictionary, budgets: Array = []) -> Dictionary:
	var bindings: Dictionary = {}
	for template in params["templates"]:
		var entries: Dictionary = {}
		for rule in template["derivations"]:
			entries[rule["trigger_id"]] = {"budgets": budgets.duplicate(), "reject_visited": false}
		bindings[template["template_id"]] = entries
	return bindings


func _new_runner(overrides: Variant = null) -> RefCounted:
	var supplied: Dictionary = _limits() if overrides == null else overrides
	return DeriveScript.new(DeriveScript.META_PATH, DeriveScript.PROVISIONAL_META,
		DeriveScript.PARAMS_PATH, DeriveScript.LIMITS_PATH, supplied)


func _configured(params: Dictionary, clock: RefCounted, bindings: Variant = null) -> RefCounted:
	var runner: RefCounted = _new_runner()
	var resolved: Dictionary = _bindings(params) if bindings == null else bindings
	assert_true(runner.configure(params, clock, resolved), runner.last_error)
	return runner


func _root(runner: RefCounted, id: String = "root_body", template: String = "root") -> RefCounted:
	var body: RefCounted = BodyScript.create("none", {"body_id": id, "lifetime_ticks": 0}, 0)
	assert_true(runner.register_root(body, template, {"origin_skill": "test_skill", "origin_cast_id": "cast_1"}), runner.last_error)
	return body


func _hit(body: RefCounted, tick: int = 0, target: String = "target_a") -> Dictionary:
	return {"type": "hit", "tick": tick, "body_id": body.body_id, "target_id": target}


func test_hit_event_creates_one_child_next_tick_without_writing_cfg():
	var params: Dictionary = _params([_rule()])
	var before: Dictionary = params.duplicate(true)
	var runner: RefCounted = _configured(params, ClockScript.new(12))
	var root: RefCounted = _root(runner)
	assert_true(runner.enqueue_event(_hit(root)))
	var result: Dictionary = runner.drain()
	assert_true(result["ok"], runner.last_error)
	assert_eq(result["events"].size(), 1)
	assert_eq(result["children"].size(), 1)
	if result["children"].size() != 1:
		return
	var child: RefCounted = result["children"][0]
	assert_eq(child.spawn_tick, 1, "ED-17-05: zero lifetime must not erase the next-tick hit window")
	assert_eq(child.lifetime_ticks, 0)
	assert_eq(child.generation, 1)
	assert_eq(child.parent_ref, root.body_id)
	assert_eq(child.origin["chain_depth"], 1)
	assert_eq(runner.snapshot_state()["cast_remaining"], 18, "Root and child each cost one")
	assert_eq(params, before)
	var state: Dictionary = runner.snapshot_state()
	state["instances"][child.body_id]["origin"]["proc_mask"].clear()
	assert_eq(runner.snapshot_state()["instances"][child.body_id]["origin"]["proc_mask"], ["first"])


func test_both_events_reject_wrong_shapes_records_and_candidate_contacts():
	var invalid_rules: Array = [
		_rule("hit", ["expired"]), _rule("vanish", []),
		_rule("hit_settled"), _rule("debug_record"), _rule("purge"),
		_rule("vanish", ["purge"]), _rule("vanish", ["dispelled"])]
	for rule in invalid_rules:
		var params: Dictionary = _params([rule])
		var runner: RefCounted = _new_runner()
		assert_false(runner.configure(params, ClockScript.new(1), _bindings(params)))
		assert_false(runner.last_error.is_empty())
	var runner: RefCounted = _configured(_params([_rule()]), ClockScript.new(1))
	var root: RefCounted = _root(runner)
	for event in [
		{"tick": 0, "body_id": root.body_id, "target_id": "a", "hit": false},
		{"type": "hit_settled", "tick": 0, "body_id": root.body_id},
		{"type": "vanish", "tick": 0, "body_id": root.body_id, "reason": "purge"},
		{"type": "hit", "tick": 0, "body_id": root.body_id},
		{"type": "hit", "tick": 0, "body_id": root.body_id, "target_id": "a", "reason": "expired"}]:
		assert_false(runner.enqueue_event(event))
		assert_false(runner.last_error.is_empty())
	assert_eq(runner.snapshot_state()["queued"], 0)
	assert_eq(runner.drain()["children"].size(), 0)


func test_seven_metadata_reasons_are_consumed_and_filtered_individually():
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DeriveScript.PARAMS_PATH))
	var reasons: Array = meta["enums"]["vanish_reason"]
	assert_eq(reasons.size(), 7, "Frozen contract cardinality, not an empty all-true loop")
	assert_eq(meta["enums"]["event"], ["hit", "vanish"])
	assert_false(reasons.has("purge"))
	var exercised: int = 0
	for reason in reasons:
		var rule: Dictionary = _rule("vanish", [reason])
		rule["allow_restricted_reason"] = true
		var runner: RefCounted = _configured(_params([rule]), ClockScript.new(2))
		var root: RefCounted = _root(runner)
		assert_true(runner.enqueue_event({"type": "vanish", "tick": 0, "body_id": root.body_id, "reason": reason}))
		var result: Dictionary = runner.drain()
		assert_true(result["ok"])
		assert_eq(result["events"].size(), 1)
		assert_eq(result["events"][0]["reason"], reason)
		assert_eq(result["children"].size(), 1, str(reason))
		exercised += 1
		var different: String = reasons[(reasons.find(reason) + 1) % reasons.size()]
		var other: RefCounted = _configured(_params([rule]), ClockScript.new(2))
		var other_root: RefCounted = _root(other)
		assert_true(other.enqueue_event({"type": "vanish", "tick": 0, "body_id": other_root.body_id, "reason": different}))
		var unmatched: Dictionary = other.drain()
		assert_eq(unmatched["events"].size(), 1, "Valid event still consumed")
		assert_eq(unmatched["children"].size(), 0, "Valid reason is not an implicit subscription")
	assert_eq(exercised, 7)


func test_restricted_reasons_require_boolean_true_not_integer_one():
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DeriveScript.PARAMS_PATH))
	assert_eq(meta["restricted_reasons"], ["range_end", "interrupted"])
	for reason in meta["restricted_reasons"]:
		for permission in [null, false, 1, 0, "true", [], {}, true]:
			var rule: Dictionary = _rule("vanish", [reason])
			if permission != null:
				rule["allow_restricted_reason"] = permission
			var params: Dictionary = _params([rule])
			var runner: RefCounted = _new_runner()
			var allowed: bool = typeof(permission) == TYPE_BOOL and permission
			assert_eq(runner.configure(params, ClockScript.new(3), _bindings(params)), allowed, str(permission))
			if not allowed:
				assert_false(runner.last_error.is_empty())


func test_purge_is_silent_no_vanish_no_child_no_compensating_hit():
	var params: Dictionary = _params([_rule(), _rule("vanish", ["instant_end"], "finish")])
	var runner: RefCounted = _configured(params, ClockScript.new(4))
	var root: RefCounted = _root(runner)
	assert_true(runner.enqueue_event(_hit(root)), "Exercise cancellation of actual queued work")
	assert_eq(runner.snapshot_state()["queued"], 1)
	assert_true(runner.purge(root.body_id))
	assert_eq(root.step(0).size(), 0, "No vanish from lifecycle")
	var result: Dictionary = runner.drain()
	assert_true(result["ok"])
	assert_eq(result["events"].size(), 0, "No vanish or compensating hit")
	assert_eq(result["children"].size(), 0, "No derivation")
	assert_eq(runner.snapshot_state()["events"].size(), 0, "No hidden hit in persistent ledger")
	assert_eq(runner.snapshot_state()["instances"].size(), 1)
	assert_eq(runner.snapshot_state()["cast_remaining"], 19)
	assert_gt(result["records"].size(), 0, "Debug cancellation is observable but is not a subscribed event")
	assert_false(runner.enqueue_event(_hit(root, 0, "later")))


func test_missing_metadata_and_each_provisional_override_fail_explicitly():
	var params: Dictionary = _params([_rule()])
	var missing: RefCounted = DeriveScript.new("res://data/not_present_t045.json", null,
		DeriveScript.PARAMS_PATH, DeriveScript.LIMITS_PATH, _limits())
	assert_false(missing.configure(params, ClockScript.new(1), _bindings(params)))
	assert_string_contains(missing.last_error, "metadata")
	var bad_params: RefCounted = DeriveScript.new(DeriveScript.META_PATH, DeriveScript.PROVISIONAL_META,
		"res://data/not_present_t045_params.json", DeriveScript.LIMITS_PATH, _limits())
	assert_false(bad_params.configure(params, ClockScript.new(1), _bindings(params)))
	assert_false(bad_params.last_error.is_empty())
	var no_limits: RefCounted = DeriveScript.new(DeriveScript.META_PATH, DeriveScript.PROVISIONAL_META,
		DeriveScript.PARAMS_PATH, "res://data/not_present_t045_limits.json", _limits())
	assert_false(no_limits.configure(params, ClockScript.new(1), _bindings(params)))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DeriveScript.LIMITS_PATH))
	var checked: int = 0
	for section in ["defaults", "hard_caps"]:
		for key in source[section]:
			if not source[section][key]["_provisional"]:
				continue
			var overrides: Dictionary = _limits()
			overrides[section].erase(key)
			var runner: RefCounted = _new_runner(overrides)
			assert_false(runner.configure(params, ClockScript.new(1), _bindings(params)))
			assert_string_contains(runner.last_error, section + "." + key)
			checked += 1
	assert_eq(checked, 4, "All four unresolved placeholder entries require injection")


func test_missing_runtime_binding_is_not_guessed_from_template_or_trigger_name():
	var params: Dictionary = _params([_rule()])
	var runner: RefCounted = _new_runner()
	assert_false(runner.configure(params, ClockScript.new(1), {}))
	assert_string_contains(runner.last_error, "binding")


func _chain_params() -> Dictionary:
	var params: Dictionary = _params([])
	params["chain_remaining"] = 3
	params["templates"] = [
		_template("root", [_rule("hit", [], "one", "second")]),
		_template("second", [_rule("hit", [], "two", "third")]),
		_template("third", [_rule("hit", [], "three", "fourth")]),
		_template("fourth", [_rule("hit", [], "four", "root")])]
	return params


func test_chain_across_three_generations_decrements_and_preserves_history():
	var params: Dictionary = _chain_params()
	var before: Dictionary = params.duplicate(true)
	var clock: RefCounted = ClockScript.new(9)
	var runner: RefCounted = _configured(params, clock, _bindings(params, ["chain_remaining"]))
	var parent: RefCounted = _root(runner)
	var ids: Array = [parent.body_id]
	var targets: Array = []
	var triggers: Array = []
	for generation in range(1, 4):
		var target: String = "target_%d" % generation
		targets.append(target)
		triggers.append(["one", "two", "three"][generation - 1])
		assert_true(runner.enqueue_event(_hit(parent, generation - 1, target)))
		var result: Dictionary = runner.drain()
		assert_true(result["ok"])
		assert_eq(result["children"].size(), 1, "A real three-generation chain, not an empty loop")
		if result["children"].size() != 1:
			return
		parent = result["children"][0]
		ids.append(parent.body_id)
		var state: Dictionary = runner.snapshot_state()["instances"][parent.body_id]
		assert_eq(state["generation"], generation)
		assert_eq(state["origin"]["chain_depth"], generation)
		assert_eq(state["generation_remaining"], 4 - generation)
		assert_eq(state["depth_remaining"], 5 - generation)
		assert_eq(state["budgets"]["chain_remaining"], 3 - generation)
		assert_eq(state["visited"], targets)
		assert_eq(state["source_chain"], ids)
		assert_eq(state["origin"]["proc_mask"], triggers)
		assert_eq(state["origin"]["origin_cast_id"], "cast_1")
		assert_eq(state["origin"]["origin_skill"], "test_skill")
		assert_eq(runner.snapshot_state()["cast_remaining"], 19 - generation)
		clock.tick()
	assert_true(runner.enqueue_event(_hit(parent, 3, "target_4")))
	var exhausted: Dictionary = runner.drain()
	assert_true(exhausted["ok"], "Ordinary budget truncation is a record, not a crash")
	assert_eq(exhausted["children"].size(), 0)
	assert_eq(exhausted["records"].size(), 1)
	assert_eq(exhausted["records"][0]["kind"], "budget_drop")
	assert_eq(exhausted["records"][0]["detail"], "chain_remaining")
	assert_eq(runner.snapshot_state()["instances"].size(), 4)
	assert_eq(params, before)


func test_split_siblings_share_cast_budget_and_cannot_refill_from_child_cfg():
	var split: Dictionary = _rule("hit", [], "split_once")
	split["count"] = 2
	var params: Dictionary = _params([split])
	params["split_budget"] = 1
	params["templates"][1] = _template("child", [_rule("hit", [], "child_split", "root")])
	# An independently spawned root may initialize from its own motion defaults;
	# a derived template MUST NOT reload these values over inherited runtime state.
	params["templates"][1]["carrier"] = "independent"
	params["templates"][1]["lifetime_ticks"] = 10
	params["templates"][1]["motion"] = {"mode": "straight", "speed": 1, "split_budget": 99, "chain_remaining": 99}
	var before: Dictionary = params.duplicate(true)
	var clock: RefCounted = ClockScript.new(11)
	var runner: RefCounted = _configured(params, clock, _bindings(params, ["split_budget"]))
	var root: RefCounted = _root(runner)
	assert_true(runner.enqueue_event(_hit(root)))
	var result: Dictionary = runner.drain()
	assert_eq(result["children"].size(), 2)
	assert_eq(runner.snapshot_state()["cast_remaining"], 17)
	if result["children"].size() != 2:
		return
	clock.tick()
	for child in result["children"]:
		var state: Dictionary = runner.snapshot_state()["instances"][child.body_id]
		assert_eq(state["budgets"]["split_budget"], 0)
		assert_eq(state["budgets"]["chain_remaining"], 0)
		assert_eq(state["visited"], ["target_a"])
		assert_false(runner.register_root(child, "child", {"origin_skill": "test_skill", "origin_cast_id": "cast_2"}))
		assert_true(runner.enqueue_event(_hit(child, 1, "other")))
	var blocked: Dictionary = runner.drain()
	assert_eq(blocked["children"].size(), 0)
	assert_eq(blocked["records"].size(), 2)
	assert_eq(blocked["records"][0]["detail"], "split_budget")
	assert_eq(blocked["records"][1]["detail"], "split_budget")
	assert_eq(params, before)


func test_cast_exhaustion_is_aggregate_record_without_synthetic_events():
	var rule: Dictionary = _rule()
	rule["count"] = 1000000
	var params: Dictionary = _params([rule])
	params["cast_budget"] = 3
	var runner: RefCounted = _configured(params, ClockScript.new(3))
	var root: RefCounted = _root(runner)
	assert_true(runner.enqueue_event(_hit(root)))
	var result: Dictionary = runner.drain()
	assert_true(result["ok"])
	assert_eq(result["children"].size(), 2)
	assert_eq(result["events"].size(), 1, "Only original hit, no budget-refusal vanish/hit")
	assert_eq(runner.snapshot_state()["cast_remaining"], 0)
	assert_eq(result["records"].size(), 3)
	assert_eq(result["records"][2]["kind"], "budget_drop")
	assert_eq(result["records"][2]["requested"], 999998)
	assert_eq(result["records"][2]["detail"], "cast_budget")


func test_generation_and_causal_depth_stop_independently_with_records():
	for limit in ["max_generation", "max_chain_depth"]:
		var params: Dictionary = _params([_rule()])
		if limit == "max_generation":
			params[limit] = 0
		else:
			params["safety"][limit] = 0
		var runner: RefCounted = _configured(params, ClockScript.new(3))
		var root: RefCounted = _root(runner)
		assert_true(runner.enqueue_event(_hit(root)))
		var result: Dictionary = runner.drain()
		assert_true(result["ok"])
		assert_eq(result["children"].size(), 0)
		assert_eq(result["records"].size(), 1)
		assert_eq(result["records"][0]["kind"], "gen_limit" if limit == "max_generation" else "chain_depth_limit")
		assert_eq(runner.snapshot_state()["cast_remaining"], 19)


func test_each_hard_cap_and_malformed_limit_rejects_configuration():
	for role in ["max_generation", "cast_budget", "max_chain_depth"]:
		var params: Dictionary = _params([_rule()])
		var caps: Dictionary = _limits()["hard_caps"]
		if role == "max_chain_depth":
			params["safety"][role] = caps[role] + 1
		else:
			params[role] = caps[role] + 1
		var runner: RefCounted = _new_runner()
		assert_false(runner.configure(params, ClockScript.new(1), _bindings(params)))
		assert_string_contains(runner.last_error, role)
	for value in [true, 1.0, -1, "3", [], null]:
		var limits: Dictionary = _limits()
		limits["hard_caps"]["max_generation"] = value
		var runner: RefCounted = _new_runner(limits)
		assert_false(runner.last_error.is_empty())


func test_injected_project_caps_change_same_chain_without_code_or_cfg_changes():
	var params: Dictionary = _chain_params()
	params.erase("max_generation")
	params.erase("cast_budget")
	var original: Dictionary = params.duplicate(true)
	var created_counts: Array = []
	for cap in [1, 3]:
		var overrides: Dictionary = _limits()
		overrides["defaults"]["max_generation"] = cap
		overrides["hard_caps"]["max_generation"] = cap
		var clock: RefCounted = ClockScript.new(7)
		var runner: RefCounted = _new_runner(overrides)
		assert_true(runner.configure(params, clock, _bindings(params, ["chain_remaining"])), runner.last_error)
		var parent: RefCounted = _root(runner)
		var total: int = 0
		for tick in range(4):
			assert_true(runner.enqueue_event(_hit(parent, tick, "victim_%d" % tick)))
			var result: Dictionary = runner.drain()
			if result["children"].is_empty():
				assert_eq(result["records"].size(), 1)
				assert_eq(result["records"][0]["kind"], "gen_limit")
				break
			assert_eq(result["children"].size(), 1)
			total += 1
			parent = result["children"][0]
			clock.tick()
		created_counts.append(total)
	assert_eq(created_counts, [1, 3])
	assert_eq(params, original)


func _apply_damage(_part: Dictionary, record: Dictionary, target: Dictionary) -> bool:
	target["hp"] = maxf(0.0, target["hp"] - float(record["value"]))
	target["alive"] = target["hp"] > 0.0
	return true


func _target(evade: float = 0.0) -> Dictionary:
	return {"target_id": "victim", "alive": true, "position": Vector2.ZERO,
		"hp": 10.0, "invulnerable": false, "evade": {"physical": evade}, "immune": {}}


func _settler(body: RefCounted, clock: RefCounted, derive: RefCounted, template: Dictionary) -> RefCounted:
	var handlers: Dictionary = {}
	var params_meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DeriveScript.PARAMS_PATH))
	for kind in params_meta["enums"]["part_type"]:
		handlers[kind] = _apply_damage
	var runner: RefCounted = SettleScript.new(SettleScript.META_PATH, SettleScript.PROVISIONAL_META)
	assert_true(runner.configure(template, body, clock, handlers, Callable(derive, "enqueue_event"),
		ShapeScript.new(ShapeScript.META_PATH, ShapeScript.PROVISIONAL_META)), runner.last_error)
	return runner


func test_real_all_evaded_contact_does_not_dispatch_or_spend_derivation_budget():
	var params: Dictionary = _params([_rule()])
	var clock: RefCounted = ClockScript.new(13)
	var derive: RefCounted = _configured(params, clock)
	var root: RefCounted = _root(derive)
	var settle: RefCounted = _settler(root, clock, derive, params["templates"][0])
	var result: Dictionary = settle.step([_target(1.0)])
	assert_true(result["ok"])
	assert_eq(result["candidates"].size(), 1)
	assert_eq(settle.snapshot_state()["candidate_count"], 1)
	assert_eq(settle.snapshot_state()["hit_count"], 0)
	assert_eq(result["events"].size(), 0)
	assert_eq(derive.snapshot_state()["queued"], 0)
	assert_eq(derive.drain()["children"].size(), 0)
	assert_eq(derive.snapshot_state()["cast_remaining"], 19)


func test_real_lethal_hit_derives_but_later_dead_target_has_no_hit():
	var params: Dictionary = _params([_rule()])
	var clock: RefCounted = ClockScript.new(14)
	var derive: RefCounted = _configured(params, clock)
	var first_body: RefCounted = _root(derive, "z_created_first")
	var second_body: RefCounted = _root(derive, "a_created_second")
	var first: RefCounted = _settler(first_body, clock, derive, params["templates"][0])
	var second: RefCounted = _settler(second_body, clock, derive, params["templates"][0])
	var target: Dictionary = _target()
	assert_eq(first.step([target])["events"].size(), 1)
	assert_false(target["alive"])
	assert_eq(second.step([target])["events"].size(), 0)
	assert_eq(second.snapshot_state()["candidate_count"], 0)
	assert_eq(derive.snapshot_state()["queued"], 1)
	var result: Dictionary = derive.drain()
	assert_eq(result["children"].size(), 1, "The killing hit was valid before target death")
	assert_eq(result["events"].size(), 1)
	assert_eq(result["events"][0]["body_id"], first_body.body_id)


func test_ed17_05_real_derived_instant_has_next_tick_hit_window_then_vanish():
	var params: Dictionary = _params([_rule()])
	var clock: RefCounted = ClockScript.new(15)
	var derive: RefCounted = _configured(params, clock)
	var root: RefCounted = _root(derive)
	var settle: RefCounted = _settler(root, clock, derive, params["templates"][0])
	assert_eq(settle.step([_target()])["events"].size(), 1)
	var root_end: Array = root.step(0)
	assert_eq(root_end.size(), 1)
	assert_true(derive.enqueue_event(root_end[0]))
	var result: Dictionary = derive.drain()
	assert_eq(result["events"].size(), 2)
	assert_eq(result["children"].size(), 1)
	if result["children"].size() != 1:
		return
	var child: RefCounted = result["children"][0]
	var child_settle: RefCounted = _settler(child, clock, derive, params["templates"][1])
	assert_eq(child_settle.step([_target()])["events"].size(), 0)
	assert_eq(child.step(0).size(), 0)
	assert_true(child.is_alive())
	clock.tick()
	assert_eq(child_settle.step([_target()])["events"].size(), 1)
	var ended: Array = child.step(1)
	assert_eq(ended.size(), 1)
	assert_eq(ended[0]["type"], "vanish")
	assert_true(derive.enqueue_event(ended[0]))
	var consumed: Dictionary = derive.drain()
	assert_eq(consumed["events"].size(), 2)
	assert_eq(consumed["children"].size(), 0, "No implicit child subscription")


func test_same_tick_fifo_is_not_sorted_by_body_id_or_template_name():
	var params: Dictionary = _params([_rule()])
	var derive: RefCounted = _configured(params, ClockScript.new(16))
	var first: RefCounted = _root(derive, "z_first")
	var second: RefCounted = _root(derive, "a_second")
	assert_true(derive.enqueue_event(_hit(first, 0, "z_target")))
	assert_true(derive.enqueue_event(_hit(second, 0, "a_target")))
	var result: Dictionary = derive.drain()
	assert_eq(result["events"].size(), 2)
	assert_eq(result["children"].size(), 2)
	if result["children"].size() != 2:
		return
	var left: RefCounted = result["children"][0]
	var right: RefCounted = result["children"][1]
	assert_eq(left.parent_ref, first.body_id)
	assert_eq(right.parent_ref, second.body_id)
	var instances: Dictionary = derive.snapshot_state()["instances"]
	assert_lt(instances[left.body_id]["seq"], instances[right.body_id]["seq"])
	assert_eq(derive.snapshot_state()["cast_remaining"], 16, "One shared cast budget for both root families")


func test_source_mask_and_visited_survive_child_body_mutation():
	for gate in ["mask", "visited"]:
		var params: Dictionary = _params([_rule()])
		params["templates"][1]["derivations"] = [_rule("hit", [], "first" if gate == "mask" else "new_trigger", "root")]
		var bindings: Dictionary = _bindings(params)
		for template in bindings:
			for trigger in bindings[template]:
				bindings[template][trigger]["reject_visited"] = true
		var clock: RefCounted = ClockScript.new(17)
		var derive: RefCounted = _configured(params, clock, bindings)
		var root: RefCounted = _root(derive)
		assert_true(derive.enqueue_event(_hit(root)))
		var first: Dictionary = derive.drain()
		assert_eq(first["children"].size(), 1)
		if first["children"].size() != 1:
			return
		var child: RefCounted = first["children"][0]
		child.origin["proc_mask"].clear()
		child.origin["chain_depth"] = 0
		child.generation = 0
		clock.tick()
		assert_true(derive.enqueue_event(_hit(child, 1)))
		var result: Dictionary = derive.drain()
		assert_eq(result["children"].size(), 0)
		assert_eq(result["records"].size(), 1)
		assert_eq(result["records"][0]["kind"], "proc_mask" if gate == "mask" else "visited")
		var state: Dictionary = derive.snapshot_state()["instances"][child.body_id]
		assert_eq(state["generation"], 1)
		assert_eq(state["origin"]["chain_depth"], 1)
		assert_eq(state["origin"]["proc_mask"], ["first"])


func _random_trace(seed_value: int, visual_draws: int) -> Dictionary:
	var params: Dictionary = _params([_rule()])
	var clock: RefCounted = ClockScript.new(seed_value)
	var derive: RefCounted = _configured(params, clock)
	var root: RefCounted = _root(derive)
	var settle: RefCounted = _settler(root, clock, derive, params["templates"][0])
	for _draw in range(visual_draws):
		clock.rng_presentation().randf()
	var targets: Array = []
	for index in range(12):
		var target: Dictionary = _target(0.0 if index < 2 else 0.5)
		target["target_id"] = "target_%d" % index
		targets.append(target)
	var input_rng_state: int = clock.rng_logic().state
	var result: Dictionary = settle.step(targets)
	assert_true(result["ok"])
	assert_eq(result["candidates"].size(), 12)
	assert_gt(result["events"].size(), 1, "Two guaranteed hits keep replay evidence nonempty")
	assert_ne(clock.rng_logic().state, input_rng_state, "Real settlement consumed the injected logic stream")
	var consumed: Dictionary = derive.drain()
	assert_true(consumed["ok"])
	assert_eq(consumed["events"].size(), result["events"].size())
	assert_eq(consumed["children"].size(), result["events"].size())
	return {"runtime": derive.snapshot_state(), "settled": result, "logic_state": clock.rng_logic().state}


func test_logic_rng_repeatable_and_independent_of_presentation_stream():
	var first: Dictionary = _random_trace(222, 0)
	assert_eq(_random_trace(222, 0), first)
	assert_eq(_random_trace(222, 1000), first)
	assert_ne(_random_trace(223, 0)["logic_state"], first["logic_state"])


func test_invalid_variant_fields_fail_without_cross_type_comparisons():
	for field in ["event", "child_template", "trigger_id", "reasons", "count", "allow_restricted_reason"]:
		for value in [[], {}, null, 1]:
			if field == "reasons" and value is Array:
				continue
			if field == "count" and typeof(value) == TYPE_INT:
				continue
			var rule: Dictionary = _rule()
			rule[field] = value
			var params: Dictionary = _params([rule])
			var runner: RefCounted = _new_runner()
			assert_false(runner.configure(params, ClockScript.new(1), {"root": {"first": {"budgets": [], "reject_visited": false}}}))
			assert_false(runner.last_error.is_empty())


func test_lowering_only_hard_cap_rejects_identical_overdeep_chain():
	var params: Dictionary = _chain_params()
	var config_copy: Dictionary = params.duplicate(true)
	var limits: Dictionary = _limits()
	limits["hard_caps"]["max_generation"] = 1
	var small: RefCounted = _new_runner(limits)
	assert_false(small.configure(params, ClockScript.new(20), _bindings(params, ["chain_remaining"])))
	assert_string_contains(small.last_error, "max_generation")
	assert_eq(small.snapshot_state()["instances"].size(), 0)
	limits["hard_caps"]["max_generation"] = 5
	var large: RefCounted = _new_runner(limits)
	assert_true(large.configure(params, ClockScript.new(20), _bindings(params, ["chain_remaining"])), large.last_error)
	var root: RefCounted = _root(large)
	assert_true(large.enqueue_event(_hit(root)))
	assert_eq(large.drain()["children"].size(), 1)
	assert_eq(params, config_copy)


func test_duplicate_or_late_events_cannot_create_extra_children():
	var params: Dictionary = _params([_rule(), _rule("vanish", ["instant_end"], "finish")])
	var clock: RefCounted = ClockScript.new(21)
	var runner: RefCounted = _configured(params, clock)
	var root: RefCounted = _root(runner)
	assert_true(runner.enqueue_event(_hit(root)))
	assert_false(runner.enqueue_event(_hit(root)))
	assert_eq(runner.drain()["children"].size(), 1)
	var end: Dictionary = root.step(0)[0]
	assert_true(runner.enqueue_event(end))
	assert_false(runner.enqueue_event(end))
	assert_false(runner.enqueue_event(_hit(root, 0, "new_victim")))
	assert_eq(runner.drain()["children"].size(), 1)
	clock.tick()
	end["tick"] = 1
	assert_false(runner.enqueue_event(end))
	assert_eq(runner.snapshot_state()["instances"].size(), 3)


func test_delayed_drain_fails_instead_of_losing_instant_hit_window():
	var clock: RefCounted = ClockScript.new(22)
	var runner: RefCounted = _configured(_params([_rule()]), clock)
	var root: RefCounted = _root(runner)
	assert_true(runner.enqueue_event(_hit(root)))
	clock.tick()
	clock.tick()
	var result: Dictionary = runner.drain()
	assert_false(result["ok"])
	assert_false(result["error"].is_empty())
	assert_eq(result["children"].size(), 0)
	assert_eq(runner.snapshot_state()["queued"], 1, "Failed drain cannot erase pending work silently")


func test_cfg_and_binding_copies_are_detached_after_configuration():
	var params: Dictionary = _params([_rule()])
	var bindings: Dictionary = _bindings(params)
	var runner: RefCounted = _configured(params, ClockScript.new(23), bindings)
	params["templates"][0]["derivations"][0]["count"] = 999
	bindings["root"]["first"]["budgets"].append("split_budget")
	var root: RefCounted = _root(runner)
	assert_true(runner.enqueue_event(_hit(root)))
	var result: Dictionary = runner.drain()
	assert_eq(result["children"].size(), 1)
	assert_eq(runner.snapshot_state()["cast_remaining"], 18)


func test_optional_trigger_id_uses_stable_runtime_identity_not_cfg_backfill():
	var rule: Dictionary = _rule()
	rule.erase("trigger_id")
	var params: Dictionary = _params([rule])
	var before: Dictionary = params.duplicate(true)
	var bindings: Dictionary = {"root": {"root:derivations[0]": {"budgets": [], "reject_visited": false}}, "child": {}}
	var runner: RefCounted = _configured(params, ClockScript.new(24), bindings)
	var root: RefCounted = _root(runner)
	assert_true(runner.enqueue_event(_hit(root)))
	var result: Dictionary = runner.drain()
	assert_eq(result["children"].size(), 1)
	if result["children"].size() == 1:
		assert_eq(result["children"][0].origin["proc_mask"], ["root:derivations[0]"])
	assert_eq(params, before)


func test_root_cannot_import_a_descendant_origin_or_new_cast_identity():
	var runner: RefCounted = _configured(_params([_rule()]), ClockScript.new(25))
	var body: RefCounted = BodyScript.create("none", {"body_id": "new_root", "lifetime_ticks": 0}, 0)
	for extra in [{"chain_depth": 1}, {"chain_depth": []}, {"proc_mask": ["existing"]}, {"proc_mask": 1}]:
		var origin: Dictionary = {"origin_skill": "test_skill", "origin_cast_id": "cast_1"}
		origin.merge(extra)
		assert_false(runner.register_root(body, "root", origin))
		assert_eq(runner.snapshot_state()["instances"].size(), 0)
	_root(runner)
	assert_false(runner.register_root(body, "root", {"origin_skill": "test_skill", "origin_cast_id": "other_cast"}))
	assert_eq(runner.snapshot_state()["cast_remaining"], 19)


func test_conflicting_budget_routes_and_unknown_rule_keys_fail_explicitly():
	var params: Dictionary = _params([_rule()])
	params["safety"]["cast_budget"] = 2
	var runner: RefCounted = _new_runner()
	assert_false(runner.configure(params, ClockScript.new(26), _bindings(params)))
	assert_string_contains(runner.last_error, "conflicting")
	params["safety"].erase("cast_budget")
	params["templates"][0]["derivations"][0]["generation"] = 0
	assert_false(runner.configure(params, ClockScript.new(26), _bindings(params)))
	assert_string_contains(runner.last_error, "Unknown derivation field")


func _assert_string_keys(value: Variant):
	if value is Dictionary:
		for key in value:
			assert_true(key is String, "Runtime dictionary keys must remain String, not StringName")
			_assert_string_keys(value[key])
	elif value is Array:
		for item in value:
			_assert_string_keys(item)


func test_runtime_ledger_new_keys_are_strings_and_snapshot_is_detached():
	var runner: RefCounted = _configured(_params([_rule()]), ClockScript.new(27))
	var root: RefCounted = _root(runner)
	assert_true(runner.enqueue_event(_hit(root)))
	assert_eq(runner.drain()["children"].size(), 1)
	var state: Dictionary = runner.snapshot_state()
	assert_eq(state["instances"].size(), 2)
	_assert_string_keys(state)
	state["records"].clear()
	state["events"].clear()
	state["instances"][root.body_id]["budgets"]["chain_remaining"] = 999
	assert_gt(runner.snapshot_state()["records"].size(), 0)
	assert_eq(runner.snapshot_state()["events"].size(), 1)
	assert_eq(runner.snapshot_state()["instances"][root.body_id]["budgets"]["chain_remaining"], 0)
