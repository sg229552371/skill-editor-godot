extends GutTest

const Summon = preload("res://skill_core/runtime/summon.gd")


func _policy(limit_value: Variant = 2) -> Dictionary:
	return {
		"limit": limit_value,
		"strategy": "purge_oldest",
		"strategy_values": {"oldest": "purge_oldest"},
		"fields": {"id": "summon_id", "owner": "owner_id", "seq": "seq", "spawn_tick": "spawn_tick", "state": "state"},
		"ledger_keys": {"instances": "instances", "summons": "summons", "records": "records", "notices": "notices"},
		"record_fields": {"type": "kind", "id": "summon_id", "reason": "reason", "seq": "seq", "spawn_tick": "spawn_tick"},
		"states": {"active": "ACTIVE", "purged": "PURGED"},
		"reasons": {"limit": "limit", "owner_death": "owner_death", "ignored_seq": "ignored_seq"},
	}


func _item(id: String, owner: Variant, tick: int) -> Dictionary:
	return {"summon_id": id, "owner_id": owner, "spawn_tick": tick}


func _ledger(limit_value: Variant = 2) -> RefCounted:
	var ledger: RefCounted = Summon.new()
	assert_true(ledger.configure(_policy(limit_value)), ledger.last_error)
	assert_true(ledger.sync_instances({"instances": {"hero": {}}, "summons": {}}), ledger.last_error)
	return ledger


func test_limit_purges_first_spawn_by_internal_sequence_not_tick():
	var ledger: RefCounted = _ledger(2)
	var first: Dictionary = ledger.spawn(_item("first", null, 99))
	var second: Dictionary = ledger.spawn(_item("second", null, 1))
	assert_true(first["ok"], first["error"])
	assert_true(second["ok"], second["error"])
	assert_eq(first["summon"]["seq"], 0)
	assert_eq(second["summon"]["seq"], 1)
	var result: Dictionary = ledger.spawn(_item("third", null, 2))
	assert_true(result["ok"], result["error"])
	assert_eq(result["purged"].size(), 1)
	assert_eq(result["purged"][0]["summon_id"], "first")
	assert_eq(result["purged"][0]["seq"], 0)
	assert_eq(result["purged"][0]["spawn_tick"], 99)
	assert_eq(ledger.active_summons().map(func(item): return item["summon_id"]), ["second", "third"])
	assert_eq(result["summon"]["seq"], 2)


func test_same_tick_spawns_are_ordered_by_internal_sequence():
	var ledger: RefCounted = _ledger(2)
	var earlier: Dictionary = ledger.spawn(_item("z", null, 7))
	var later: Dictionary = ledger.spawn(_item("a", null, 7))
	assert_true(earlier["ok"])
	assert_true(later["ok"])
	assert_lt(earlier["summon"]["seq"], later["summon"]["seq"])
	var result: Dictionary = ledger.spawn(_item("m", null, 7))
	assert_true(result["ok"])
	assert_eq(result["purged"].size(), 1)
	assert_eq(result["purged"][0]["summon_id"], "z")
	assert_eq(ledger.active_summons().map(func(item): return item["summon_id"]), ["a", "m"])


func test_caller_sequence_is_ignored_with_explicit_notice():
	var ledger: RefCounted = _ledger(2)
	var input: Dictionary = _item("caller", null, 3)
	input["seq"] = 500
	var before: Dictionary = input.duplicate(true)
	var result: Dictionary = ledger.spawn(input)
	assert_true(result["ok"], result["error"])
	assert_eq(result["summon"]["seq"], 0)
	assert_eq(result["notices"].size(), 1)
	assert_eq(result["notices"][0]["reason"], "ignored_seq")
	assert_eq(ledger.snapshot_state()["notices"], result["notices"])
	assert_eq(input, before)
	var next: Dictionary = ledger.spawn(_item("next", null, 4))
	assert_true(next["ok"])
	assert_eq(next["summon"]["seq"], 1)
	assert_eq(next["notices"].size(), 0)


func test_owner_death_purges_all_owned_and_leaves_independent_alive():
	var ledger: RefCounted = _ledger(5)
	assert_true(ledger.spawn(_item("bound_a", "hero", 1))["ok"])
	assert_true(ledger.spawn(_item("independent", null, 1))["ok"])
	assert_true(ledger.spawn(_item("bound_b", "hero", 2))["ok"])
	var result: Dictionary = ledger.on_owner_death("hero")
	assert_true(result["ok"], result["error"])
	assert_eq(result["purged"].size(), 2)
	assert_eq(result["purged"].map(func(item): return item["summon_id"]), ["bound_a", "bound_b"])
	assert_eq(result["purged"].map(func(item): return item["seq"]), [0, 2])
	assert_eq(ledger.active_summons().map(func(item): return item["summon_id"]), ["independent"])
	assert_eq(ledger.active_summons()[0]["state"], "ACTIVE")
	assert_eq(ledger.snapshot_state()["records"], result["purged"])
	assert_eq(ledger.snapshot_state()["records"].size(), 2)
	assert_eq(ledger.snapshot_state()["notices"], [])


func test_limit_is_injected_and_released_ids_and_sequences_are_never_reused():
	var one: RefCounted = _ledger(1)
	var two: RefCounted = _ledger(2)
	assert_true(one.spawn(_item("first", null, 0))["ok"])
	assert_true(two.spawn(_item("first", null, 0))["ok"])
	var one_result: Dictionary = one.spawn(_item("second", null, 1))
	var two_result: Dictionary = two.spawn(_item("second", null, 1))
	assert_true(one_result["ok"])
	assert_true(two_result["ok"])
	assert_eq(one_result["purged"].size(), 1)
	assert_eq(two_result["purged"].size(), 0)
	assert_eq(one.active_summons().size(), 1)
	assert_eq(two.active_summons().size(), 2)
	var rejected: Dictionary = one.spawn(_item("first", null, 2))
	assert_false(rejected["ok"])
	assert_false(rejected["error"].is_empty())
	var third: Dictionary = one.spawn(_item("third", null, 2))
	assert_true(third["ok"])
	assert_eq(third["summon"]["seq"], 2)
	assert_eq(third["purged"][0]["summon_id"], "second")


func test_invalid_limits_and_strategy_are_explicit_failures():
	var missing: Dictionary = _policy()
	missing.erase("limit")
	var missing_ledger: RefCounted = Summon.new()
	assert_false(missing_ledger.configure(missing))
	assert_false(missing_ledger.last_error.is_empty())
	for bad in [null, 0, -1, 1.0, "2"]:
		var ledger: RefCounted = Summon.new()
		assert_false(ledger.configure(_policy(bad)), "Limit must reject: " + str(bad))
		assert_false(ledger.last_error.is_empty())
	var wrong: Dictionary = _policy()
	wrong["strategy"] = "reject_new"
	var strategy_ledger: RefCounted = Summon.new()
	assert_false(strategy_ledger.configure(wrong))
	assert_false(strategy_ledger.last_error.is_empty())


func test_invalid_ownership_structure_is_not_skipped():
	var ledger: RefCounted = _ledger(3)
	var missing_owner: Dictionary = {"summon_id": "bad", "spawn_tick": 0}
	var missing_result: Dictionary = ledger.spawn(missing_owner)
	assert_false(missing_result["ok"])
	assert_false(missing_result["error"].is_empty())
	var dangling: Dictionary = ledger.spawn(_item("missing_owner", "no_such_instance", 0))
	assert_false(dangling["ok"])
	assert_false(dangling["error"].is_empty())
	var snapshot: Dictionary = {"instances": {"hero": {}}, "summons": {"bad": "not_object"}}
	assert_false(ledger.sync_instances(snapshot))
	assert_false(ledger.last_error.is_empty())
	assert_eq(ledger.active_summons().size(), 0)


func test_purge_is_silent_and_input_and_snapshot_are_copied():
	var ledger: RefCounted = _ledger(2)
	var input: Dictionary = _item("bound", "hero", 0)
	var before: Dictionary = input.duplicate(true)
	assert_true(ledger.spawn(input)["ok"])
	assert_eq(input, before)
	var snapshot: Dictionary = ledger.snapshot_state()
	snapshot["summons"]["bound"]["state"] = "CORRUPTED"
	assert_eq(ledger.active_summons()[0]["state"], "ACTIVE")
	var result: Dictionary = ledger.on_owner_death("hero")
	assert_true(result["ok"])
	assert_eq(result["purged"].size(), 1)
	assert_eq(result["purged"][0]["kind"], "owner_death")
	assert_eq(ledger.snapshot_state()["records"].size(), 1)
	assert_false(ledger.snapshot_state().has("events"))
	assert_false(result.has("events"))


func test_sync_resumes_after_highest_sequence_without_reusing_it():
	var ledger: RefCounted = Summon.new()
	assert_true(ledger.configure(_policy(3)))
	var restored: Dictionary = _item("old", null, 3)
	restored["seq"] = 7
	restored["state"] = "ACTIVE"
	assert_true(ledger.sync_instances({"instances": {"hero": {}}, "summons": {"old": restored}}), ledger.last_error)
	var result: Dictionary = ledger.spawn(_item("new", null, 1))
	assert_true(result["ok"])
	assert_eq(result["summon"]["seq"], 8)
	assert_eq(ledger.active_summons().map(func(item): return item["summon_id"]), ["old", "new"])


func test_same_input_order_produces_same_purge_records():
	var a: RefCounted = _ledger(2)
	var b: RefCounted = _ledger(2)
	var inputs: Array = [_item("z", null, 8), _item("a", null, 9), _item("m", null, 1)]
	for input in inputs:
		var first: Dictionary = a.spawn(input)
		var second: Dictionary = b.spawn(input)
		assert_true(first["ok"])
		assert_true(second["ok"])
		assert_eq(first, second)
	assert_eq(a.snapshot_state(), b.snapshot_state())
	assert_eq(a.snapshot_state()["records"].size(), 1)
	assert_eq(a.snapshot_state()["records"][0]["summon_id"], "z")
	assert_eq(a.active_summons(), b.active_summons())
