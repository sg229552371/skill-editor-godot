extends GutTest

const Family = preload("res://skill_core/runtime/family_ledger.gd")
const Derive = preload("res://skill_core/runtime/derive.gd")
const Body = preload("res://skill_core/runtime/effect_body.gd")
const Clock = preload("res://skill_core/runtime/sim_clock.gd")


func _limits() -> Dictionary:
	return {"defaults": {"cast_budget": 20}, "hard_caps": {"max_generation": 5, "cast_budget": 20, "max_chain_depth": 6}}


func _bindings() -> Dictionary:
	return {"family": {"id": "family_id"},
		"shotgun": {"shot": "shot_id", "independent": "independent_root", "allow": "shotgun_allowed"}}


func _setup(seed_value: int = 7) -> Dictionary:
	var clock: RefCounted = Clock.new(seed_value)
	var derive: RefCounted = Derive.new(Derive.META_PATH, null, Derive.PARAMS_PATH, Derive.LIMITS_PATH, _limits())
	var root: Dictionary = {"template_id": "root", "carrier": "none", "lifetime_ticks": 0,
		"derivations": [{"trigger_id": "make_children", "event": "hit", "reasons": [], "child_template": "child", "count": 2}]}
	var child: Dictionary = {"template_id": "child", "carrier": "none", "lifetime_ticks": 0}
	var params: Dictionary = {"max_generation": 2, "cast_budget": 20, "split_budget": 1,
		"safety": {"max_chain_depth": 3}, "templates": [root, child]}
	assert_true(derive.configure(params, clock,
		{"root": {"make_children": {"budgets": ["split_budget"], "reject_visited": false}}, "child": {}}), derive.last_error)
	var family: RefCounted = Family.new()
	assert_true(family.configure(clock, _bindings()), family.last_error)
	return {"clock": clock, "derive": derive, "family": family, "facts": {}}


func _root(run: Dictionary, id: String, family_id: String, shot_id: String = "shot_0", allowed: Variant = null):
	var body: RefCounted = Body.create("none", {"body_id": id, "lifetime_ticks": 0}, 0)
	assert_true(run["derive"].register_root(body, "root",
		{"origin_skill": "skill_one", "origin_cast_id": "cast_one"}), run["derive"].last_error)
	var facts: Dictionary = {"family_id": family_id, "shot_id": shot_id, "independent_root": true}
	if allowed != null:
		facts["shotgun_allowed"] = allowed
	run["facts"][id] = facts
	assert_true(run["family"].sync_instances(run["derive"].snapshot_state(), run["facts"]), run["family"].last_error)


func _children(run: Dictionary, new_family: String = "") -> Array:
	assert_true(run["derive"].enqueue_event({"type": "hit", "tick": 0, "body_id": "root_z", "target_id": "trigger"}))
	var result: Dictionary = run["derive"].drain()
	assert_true(result["ok"], result["error"])
	assert_eq(result["children"].size(), 2)
	for child in result["children"]:
		run["facts"][child.body_id] = {"family_id": new_family if not new_family.is_empty() else "split_family",
			"independent_root": false}
	assert_true(run["family"].sync_instances(run["derive"].snapshot_state(), run["facts"]), run["family"].last_error)
	run["clock"].tick()
	return result["children"]


func _candidate(id: Variant, target: Variant = "target", tick: Variant = 0, alive: Variant = true) -> Dictionary:
	return {"body_id": id, "target_id": target, "tick": tick, "alive": alive}


func test_split_siblings_stable_first_candidate_and_silent_second():
	var run: Dictionary = _setup()
	_root(run, "root_z", "split_family")
	var children: Array = _children(run)
	var first: String = children[0].body_id
	var second: String = children[1].body_id
	var batch: Dictionary = run["family"].admit_batch([_candidate(second, "fresh", 1), _candidate(first, "fresh", 1)])
	assert_true(batch["ok"], batch["error"])
	assert_eq(batch["admitted"].size(), 1)
	assert_eq(batch["suppressed"].size(), 1)
	assert_eq(batch["admitted"][0]["body_id"], first)
	assert_eq(batch["suppressed"][0]["reason"], "family")
	var state: Dictionary = run["family"].snapshot_state()
	var family_key: String = JSON.stringify(["cast_one", "split_family"])
	assert_eq(state["families"][family_key].size(), 1, "No second contact record")
	assert_eq(state["families"][family_key]["fresh"], first)
	assert_eq(state["shot_hits"].size(), 0, "Suppressed sibling spent no hit allowance")
	assert_eq(run["derive"].snapshot_state()["events"].size(), 1, "No second hit or evaded_all event")


func test_all_evaded_contact_still_blocks_split_sibling_without_hit_or_evasion_record():
	var run: Dictionary = _setup()
	_root(run, "root_z", "split_family")
	var children: Array = _children(run)
	var first: String = children[0].body_id
	var second: String = children[1].body_id
	assert_true(run["family"].admit(_candidate(first, "evaded", 1))["admitted"])
	# No record_hit: all parts evaded; family admission nevertheless persists.
	var denied: Dictionary = run["family"].admit(_candidate(second, "evaded", 1))
	assert_true(denied["ok"])
	assert_false(denied["admitted"])
	assert_eq(denied["reason"], "family")
	assert_eq(run["family"].snapshot_state()["families"][JSON.stringify(["cast_one", "split_family"])].size(), 1)
	assert_eq(run["family"].snapshot_state()["shot_hits"], {})
	assert_eq(run["derive"].snapshot_state()["events"].size(), 1)
	assert_eq(run["derive"].snapshot_state()["instances"][second]["visited"].has("evaded"), false)


func test_shotgun_default_blocks_only_second_successful_root_hit():
	var run: Dictionary = _setup()
	_root(run, "first", "family_a")
	_root(run, "second", "family_b")
	assert_true(run["family"].admit(_candidate("first"))["admitted"])
	assert_true(run["family"].admit(_candidate("second"))["admitted"], "Shotgun never suppresses candidate registration")
	assert_true(run["family"].may_hit(_candidate("second"))["allowed"], "An all-evaded first root must not block another hit")
	assert_true(run["family"].record_hit(_candidate("first")))
	var gate: Dictionary = run["family"].may_hit(_candidate("second"))
	assert_true(gate["ok"])
	assert_false(gate["allowed"])
	assert_eq(gate["reason"], "shotgun")
	assert_eq(run["family"].snapshot_state()["shot_hits"].size(), 1)
	assert_eq(run["family"].snapshot_state()["families"].size(), 2, "Both family candidates remain registered")


func test_explicit_shotgun_true_stacks_hits_without_disabling_family_registration():
	var run: Dictionary = _setup()
	_root(run, "root_z", "split_family", "shot_0", true)
	_root(run, "other_root", "different_family", "shot_0", true)
	assert_true(run["family"].admit(_candidate("root_z", "stack"))["admitted"])
	assert_true(run["family"].record_hit(_candidate("root_z", "stack")))
	assert_true(run["family"].admit(_candidate("other_root", "stack"))["admitted"])
	assert_true(run["family"].may_hit(_candidate("other_root", "stack"))["allowed"])
	assert_true(run["family"].record_hit(_candidate("other_root", "stack")))
	assert_eq(run["family"].snapshot_state()["families"].size(), 2)
	var children: Array = _children(run)
	var first: String = children[0].body_id
	var second: String = children[1].body_id
	assert_true(run["family"].admit(_candidate(first, "fresh", 1))["admitted"])
	assert_eq(run["family"].admit(_candidate(second, "fresh", 1))["reason"], "family",
		"Parent's shotgun permission cannot override sibling family admission")


func test_new_explosion_family_preserves_origin_and_complete_source_chain():
	var run: Dictionary = _setup()
	_root(run, "root_z", "split_family")
	var original: Dictionary = run["derive"].snapshot_state()["instances"]["root_z"]["origin"].duplicate(true)
	assert_true(run["family"].admit(_candidate("root_z", "shared"))["admitted"])
	var children: Array = _children(run, "explosion_family")
	var id: String = children[0].body_id
	var member: Dictionary = run["family"].snapshot_state()["members"][id]
	assert_eq(member["family"], "explosion_family")
	assert_eq(member["origin"]["origin_cast_id"], original["origin_cast_id"])
	assert_eq(member["origin"]["origin_skill"], original["origin_skill"])
	assert_eq(member["chain"], ["root_z", id])
	assert_true(run["family"].admit(_candidate(id, "shared", 1))["admitted"])
	assert_eq(run["family"].snapshot_state()["families"].size(), 2)


func test_permuted_batch_has_identical_nonempty_contact_order():
	var expected: Dictionary = {}
	for attempt in range(2):
		var run: Dictionary = _setup(90)
		_root(run, "root_z", "split_family")
		var children: Array = _children(run)
		var first: String = children[0].body_id
		var second: String = children[1].body_id
		if attempt == 1:
			for unused in range(20):
				run["clock"].rng_presentation().randf()
		var a: Dictionary = _candidate(second, "z", 1)
		var b: Dictionary = _candidate(first, "a", 1)
		var c: Dictionary = _candidate(first, "z", 1)
		var inputs: Array = [a, b, c] if attempt == 0 else [c, a, b]
		var result: Dictionary = run["family"].admit_batch(inputs)
		assert_true(result["ok"], result["error"])
		assert_eq(result["admitted"].size(), 2)
		assert_eq(result["suppressed"].size(), 1)
		if attempt == 0:
			expected = {"admitted": result["admitted"], "suppressed": result["suppressed"],
				"families": run["family"].snapshot_state()["families"]}
		else:
			assert_eq(result["admitted"], expected["admitted"])
			assert_eq(result["suppressed"], expected["suppressed"])
			assert_eq(run["family"].snapshot_state()["families"], expected["families"])
	assert_gt(expected["families"].size(), 0)


func test_two_actual_shots_at_same_tick_do_not_share_shotgun_group():
	var run: Dictionary = _setup()
	_root(run, "first", "family_a", "actual_shot_0")
	_root(run, "second", "family_b", "actual_shot_1")
	assert_true(run["family"].admit(_candidate("first"))["admitted"])
	assert_true(run["family"].record_hit(_candidate("first")))
	assert_true(run["family"].admit(_candidate("second"))["admitted"])
	assert_true(run["family"].may_hit(_candidate("second"))["allowed"])
	assert_true(run["family"].record_hit(_candidate("second")))
	assert_eq(run["family"].snapshot_state()["shot_hits"].size(), 2)


func test_dead_target_and_purge_are_silent_and_do_not_create_hit():
	var run: Dictionary = _setup()
	_root(run, "root_z", "family_a")
	var dead: Dictionary = run["family"].admit(_candidate("root_z", "dead", 0, false))
	assert_true(dead["ok"])
	assert_false(dead["admitted"])
	assert_eq(dead["reason"], "dead")
	assert_eq(run["family"].snapshot_state()["families"], {})
	assert_true(run["family"].purge("root_z"))
	assert_eq(run["family"].snapshot_state()["families"], {})
	assert_eq(run["family"].snapshot_state()["members"], {})
	assert_eq(run["family"].snapshot_state()["shot_hits"], {})
	assert_eq(run["derive"].snapshot_state()["events"], [])
	assert_eq(run["derive"].snapshot_state()["instances"].size(), 1, "Purge did not derive another body")
	assert_false(run["family"].admit(_candidate("root_z"))["ok"])


func test_invalid_routing_or_material_fails_without_cfg_writeback():
	var run: Dictionary = _setup()
	_root(run, "root_z", "family_a")
	var before: Dictionary = run["derive"].snapshot_state()
	var corrupt: Dictionary = before.duplicate(true)
	corrupt["instances"]["root_z"]["origin"]["origin_cast_id"] = []
	assert_false(run["family"].sync_instances(corrupt, run["facts"]))
	assert_eq(run["family"].snapshot_state()["members"]["root_z"]["origin"]["origin_cast_id"], "cast_one")
	for bad in [[], {}, null, 5]:
		assert_false(run["family"].admit(_candidate(bad))["ok"])
		assert_false(run["family"].admit(_candidate("root_z", bad))["ok"])
		assert_false(run["family"].admit(_candidate("root_z", "target", bad))["ok"])
	assert_eq(run["derive"].snapshot_state(), before, "Only the runtime ledger changes; CFG/Derive snapshots are not mutated")
	var detached: Dictionary = run["family"].snapshot_state()
	detached["members"]["root_z"]["chain"].clear()
	assert_eq(run["family"].snapshot_state()["members"]["root_z"]["chain"], ["root_z"])
	var clock: RefCounted = Clock.new(1)
	var missing: RefCounted = Family.new("res://data/nonexistent_t046.json")
	assert_false(missing.configure(clock, _bindings()))
	assert_false(missing.last_error.is_empty())
	var unbound: RefCounted = Family.new()
	assert_false(unbound.configure(clock, {}), "Unresolved split and shot policy cannot silently default")
