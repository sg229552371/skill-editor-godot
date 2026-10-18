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


func _setup() -> Dictionary:
	var clock: RefCounted = Clock.new(7)
	var derive: RefCounted = Derive.new(Derive.META_PATH, null, Derive.PARAMS_PATH, Derive.LIMITS_PATH, _limits())
	var params: Dictionary = {"max_generation": 2, "cast_budget": 20, "split_budget": 1,
		"safety": {"max_chain_depth": 3}, "templates": [{"template_id": "root", "carrier": "none", "lifetime_ticks": 0}]}
	assert_true(derive.configure(params, clock, {"root": {}}), derive.last_error)
	var family: RefCounted = Family.new()
	assert_true(family.configure(clock, _bindings()), family.last_error)
	return {"clock": clock, "derive": derive, "family": family, "facts": {}}


func _root(run: Dictionary, id: String, family_id: String, shot_id: String = "shot_a") -> void:
	var body: RefCounted = Body.create("none", {"body_id": id, "lifetime_ticks": 0}, 0)
	assert_true(run["derive"].register_root(body, "root",
		{"origin_skill": "skill_one", "origin_cast_id": "cast_one"}), run["derive"].last_error)
	run["facts"][id] = {"family_id": family_id, "shot_id": shot_id, "independent_root": true}
	assert_true(run["family"].sync_instances(run["derive"].snapshot_state(), run["facts"]), run["family"].last_error)


func _candidate(id: String, target: String = "victim") -> Dictionary:
	return {"body_id": id, "target_id": target, "tick": 0, "alive": true}


# This is the host-side decision seam: an all-evaded candidate records only a
# completed judgment; a successful candidate records both hit and judgment.
func _decide(run: Dictionary, id: String, target: String, evaded: bool) -> Dictionary:
	var candidate: Dictionary = _candidate(id, target)
	var admitted: Dictionary = run["family"].admit(candidate)
	assert_true(admitted["ok"], admitted["error"])
	if not admitted["admitted"]:
		return {"gate": {"ok": true, "allowed": false, "reason": admitted["reason"]}, "records": []}
	var gate: Dictionary = run["family"].may_hit(candidate)
	assert_true(gate["ok"], gate["error"])
	var records: Array = []
	if gate["allowed"]:
		if evaded:
			records.append({"type": "evaded_all", "body_id": id, "target_id": target})
		else:
			assert_true(run["family"].record_hit(candidate), run["family"].last_error)
			records.append({"type": "hit", "body_id": id, "target_id": target})
		assert_true(run["family"].record_judgment(candidate), run["family"].last_error)
	return {"gate": gate, "records": records}


func _count(records: Array, kind: String) -> int:
	var total: int = 0
	for record in records:
		if record.get("type", "") == kind:
			total += 1
	return total


func test_same_shot_all_evaded_has_one_record() -> void:
	var run: Dictionary = _setup()
	_root(run, "first", "family_a")
	_root(run, "second", "family_a")
	var first: Dictionary = _decide(run, "first", "victim", true)
	assert_gt(first["records"].size(), 0, "nonempty first all-evaded baseline")
	var second: Dictionary = _decide(run, "second", "victim", true)
	var records: Array = first["records"] + second["records"]
	assert_eq(_count(records, "evaded_all"), 1)
	assert_eq(_count(records, "hit"), 0)


func test_same_shot_all_hits_still_has_one_hit() -> void:
	var run: Dictionary = _setup()
	_root(run, "first", "family_a")
	_root(run, "second", "family_b")
	var first: Dictionary = _decide(run, "first", "victim", false)
	assert_gt(first["records"].size(), 0, "nonempty first-hit baseline")
	var second: Dictionary = _decide(run, "second", "victim", false)
	var records: Array = first["records"] + second["records"]
	assert_eq(_count(records, "hit"), 1)


func test_first_evade_wins_over_later_hit() -> void:
	var run: Dictionary = _setup()
	_root(run, "first", "family_a")
	_root(run, "second", "family_a")
	var first: Dictionary = _decide(run, "first", "victim", true)
	assert_gt(first["records"].size(), 0, "nonempty evade baseline")
	var second: Dictionary = _decide(run, "second", "victim", false)
	var records: Array = first["records"] + second["records"]
	assert_eq(records.size(), 1)
	assert_eq(records[0]["type"], "evaded_all")


func test_first_hit_wins_over_later_evade() -> void:
	var run: Dictionary = _setup()
	_root(run, "first", "family_a")
	_root(run, "second", "family_b")
	var first: Dictionary = _decide(run, "first", "victim", false)
	assert_gt(first["records"].size(), 0, "nonempty hit baseline")
	var second: Dictionary = _decide(run, "second", "victim", true)
	var records: Array = first["records"] + second["records"]
	assert_eq(records.size(), 1)
	assert_eq(records[0]["type"], "hit")


func test_different_shots_each_hit() -> void:
	var run: Dictionary = _setup()
	_root(run, "first", "family_a", "shot_a")
	_root(run, "second", "family_b", "shot_b")
	var first: Dictionary = _decide(run, "first", "victim", false)
	assert_gt(first["records"].size(), 0, "nonempty first-shot baseline")
	var second: Dictionary = _decide(run, "second", "victim", false)
	var records: Array = first["records"] + second["records"]
	assert_eq(_count(records, "hit"), 2)


func test_different_shots_each_evade() -> void:
	var run: Dictionary = _setup()
	_root(run, "first", "family_a", "shot_a")
	_root(run, "second", "family_b", "shot_b")
	var first: Dictionary = _decide(run, "first", "victim", true)
	assert_gt(first["records"].size(), 0, "nonempty first-shot evade baseline")
	var second: Dictionary = _decide(run, "second", "victim", true)
	var records: Array = first["records"] + second["records"]
	assert_eq(_count(records, "evaded_all"), 2)


func test_same_shot_different_targets_each_get_one_record() -> void:
	var run: Dictionary = _setup()
	_root(run, "first", "family_a")
	_root(run, "second", "family_b")
	var first: Dictionary = _decide(run, "first", "left", true)
	assert_gt(first["records"].size(), 0, "nonempty first-target baseline")
	var second: Dictionary = _decide(run, "second", "right", true)
	var records: Array = first["records"] + second["records"]
	assert_eq(records.size(), 2)
	assert_eq(_count(records, "evaded_all"), 2)


func test_capacity_denial_does_not_preclaim_shot_judgment() -> void:
	var run: Dictionary = _setup()
	_root(run, "first", "family_a")
	# A host capacity gate rejects this first candidate before may_hit; it must
	# therefore not create a family-ledger judgment. The later candidate is free.
	var state_before: Dictionary = run["family"].snapshot_state()
	assert_eq(state_before["shot_judgments"].size(), 0, "capacity denial baseline is unregistered")
	var result: Dictionary = _decide(run, "first", "victim", false)
	assert_gt(result["records"].size(), 0, "later allowed candidate settles")
	assert_eq(run["family"].snapshot_state()["shot_judgments"].size(), 1)


func test_second_body_gets_shotgun_denial_after_first_judgment() -> void:
	var run: Dictionary = _setup()
	_root(run, "first", "family_a")
	_root(run, "second", "family_a")
	assert_true(run["family"].record_judgment(_candidate("first")))
	assert_eq(run["family"].snapshot_state()["shot_judgments"].size(), 1)
	assert_eq(run["family"].snapshot_state()["shot_hits"].size(), 0)
	var candidate: Dictionary = _candidate("second")
	var admitted: Dictionary = run["family"].admit(candidate)
	assert_true(admitted["ok"], admitted["error"])
	assert_true(admitted["admitted"])
	var gate: Dictionary = run["family"].may_hit(candidate)
	assert_true(gate["ok"], gate["error"])
	assert_false(gate["allowed"])
	assert_eq(gate["reason"], "shotgun")


func test_judgment_key_keeps_family_and_target_fields_distinct() -> void:
	var run: Dictionary = _setup()
	_root(run, "first", "family_a")
	_root(run, "second", "family_b")
	var first: Dictionary = _decide(run, "first", "left", true)
	assert_gt(first["records"].size(), 0, "nonempty key baseline")
	var second: Dictionary = _decide(run, "second", "right", true)
	assert_gt(second["records"].size(), 0, "different family and target remain independent")
	assert_eq(run["family"].snapshot_state()["shot_judgments"].size(), 2)
	var keys: Array = run["family"].snapshot_state()["shot_judgments"].keys()
	var encoded: String = JSON.stringify(keys)
	assert_true(encoded.contains("family_a"), "judgment key retains first family")
	assert_true(encoded.contains("family_b"), "judgment key retains second family")
	assert_true(encoded.contains("left") and encoded.contains("right"), "judgment key retains targets")


func test_preflight_second_does_not_preclaim_first_successful_hit() -> void:
	var run: Dictionary = _setup()
	_root(run, "first", "family_a")
	_root(run, "second", "family_b")
	assert_true(run["family"].admit(_candidate("first"))["admitted"])
	assert_true(run["family"].admit(_candidate("second"))["admitted"])
	var before: Dictionary = run["family"].snapshot_state()
	assert_true(run["family"].may_hit(_candidate("second"))["allowed"])
	assert_eq(run["family"].snapshot_state(), before, "preflight writes no ledger state")
	assert_true(run["family"].record_hit(_candidate("first")))
	var committed: Dictionary = run["family"].snapshot_state()
	var gate: Dictionary = run["family"].may_hit(_candidate("second"))
	assert_true(gate["ok"])
	assert_false(gate["allowed"])
	assert_eq(gate["reason"], "shotgun")
	assert_eq(run["family"].snapshot_state(), committed, "denied preflight also writes nothing")
	assert_eq(committed["shot_hits"].size(), 1)
	assert_eq(committed["shot_judgments"].size(), 0, "record_hit does not imply a completed all-parts decision")


func test_record_judgment_is_idempotent_only_for_same_body() -> void:
	var run: Dictionary = _setup()
	_root(run, "first", "family_a")
	_root(run, "second", "family_a")
	assert_true(run["family"].record_judgment(_candidate("first")))
	var before: Dictionary = run["family"].snapshot_state()
	assert_eq(before["shot_judgments"].size(), 1)
	assert_true(run["family"].record_judgment(_candidate("first")))
	assert_eq(run["family"].snapshot_state(), before)
	assert_false(run["family"].record_judgment(_candidate("second")))
	assert_eq(run["family"].snapshot_state(), before, "duplicate cannot replace judgment owner")


func test_invalid_judgment_and_failed_preflight_preserve_state() -> void:
	var run: Dictionary = _setup()
	_root(run, "first", "family_a")
	var before: Dictionary = run["family"].snapshot_state()
	for field in ["body_id", "target_id", "tick", "alive"]:
		var invalid: Dictionary = _candidate("first")
		invalid[field] = null
		assert_false(run["family"].record_judgment(invalid))
		var error_before: String = run["family"].last_error
		assert_false(run["family"].may_hit(invalid)["ok"])
		assert_eq(run["family"].last_error, error_before, "even invalid queries leave last_error alone")
		assert_eq(run["family"].snapshot_state(), before)
	assert_true(run["family"].record_judgment(_candidate("first")))
	assert_true(run["family"].purge("first"))
	assert_eq(run["family"].snapshot_state()["shot_judgments"], {})


func test_completed_judgment_does_not_merge_family_or_target_with_hit_key() -> void:
	var run: Dictionary = _setup()
	_root(run, "first", "family_a")
	_root(run, "second", "family_b")
	assert_true(run["family"].record_judgment(_candidate("first")))
	assert_true(run["family"].admit(_candidate("second"))["admitted"])
	assert_true(run["family"].may_hit(_candidate("second"))["allowed"], "judgment key includes family")
	assert_true(run["family"].admit(_candidate("first", "other"))["admitted"])
	assert_true(run["family"].may_hit(_candidate("first", "other"))["allowed"], "judgment key includes target")
	var before: Dictionary = run["family"].snapshot_state()
	assert_eq(before["shot_judgments"].size(), 1)
	assert_eq(before["shot_hits"].size(), 0)
	var detached: Dictionary = run["family"].snapshot_state()
	detached["shot_judgments"].clear()
	assert_eq(run["family"].snapshot_state(), before, "judgment snapshot is a deep copy")
