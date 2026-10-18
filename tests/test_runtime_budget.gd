extends GutTest

const Budget = preload("res://skill_core/runtime/budget.gd")


func _limits(cap: int = 6) -> Dictionary:
	return {"defaults": {"cast_budget": cap},
		"hard_caps": {"cast_budget": cap, "max_generation": 5, "max_chain_depth": 6}}


func _policy(capacity: int = 5, priorities: Variant = null, debug: bool = true) -> Dictionary:
	return {"capacity": capacity, "root_cost": 1,
		"priorities": {"presentation": 0, "logic": 1} if priorities == null else priorities,
		"debug_type": "debug_record", "debug_enabled": debug,
		"fields": {"id": "item_id", "category": "category", "cost": "units", "type": "type",
			"kind": "kind", "root": "root_id", "reason": "reason", "occupied": "occupied_at_decision"},
		"ledger_keys": {"roots": "roots", "drops": "drops", "debug": "debug_ledger",
			"settlements": "settlement_records", "occupied": "occupied", "capacity": "capacity"}}


func _item(id: String, kind: String, cost: int = 1) -> Dictionary:
	return {"item_id": id, "category": kind, "units": cost}


func _ledger(capacity: int = 5, priorities: Variant = null, debug: bool = true, hard_cap: int = 6) -> RefCounted:
	var ledger: RefCounted = Budget.new()
	assert_true(ledger.configure(_policy(capacity, priorities, debug), _limits(hard_cap)), ledger.last_error)
	return ledger


func test_exhaustion_discards_presentation_layer_before_logic_and_records_each_drop():
	var ledger: RefCounted = _ledger(3)
	var result: Dictionary = ledger.admit_root("root_a", [
		_item("fx_a", "presentation"), _item("logic_a", "logic"),
		_item("fx_b", "presentation"), _item("logic_b", "logic")])
	assert_true(result["ok"], result["error"])
	assert_true(result["admitted"])
	assert_eq(result["kept"].map(func(item): return item["item_id"]), ["logic_a", "logic_b"])
	assert_eq(result["dropped"].map(func(item): return item["item_id"]), ["fx_b", "fx_a"])
	assert_eq(result["dropped"].map(func(item): return item["reason"]), ["budget_drop", "budget_drop"])
	assert_eq(ledger.snapshot_state()["drops"], result["dropped"])
	assert_eq(ledger.snapshot_state()["occupied"], 3)
	var logic_last: Dictionary = _ledger(1).admit_root("root", [_item("fx", "presentation"), _item("logic", "logic")])
	assert_eq(logic_last["dropped"].map(func(item): return item["item_id"]), ["fx", "logic"])
	assert_true(logic_last["admitted"])


func test_full_budget_rejects_new_root_with_identity_reason_and_occupancy_without_eviction():
	var ledger: RefCounted = _ledger(2)
	assert_true(ledger.admit_root("existing", [_item("existing_logic", "logic")])["admitted"])
	var before: Dictionary = ledger.snapshot_state()
	var rejected: Dictionary = ledger.admit_root("new_root", [])
	assert_true(rejected["ok"])
	assert_false(rejected["admitted"])
	assert_eq(rejected["rejected"]["root_id"], "new_root")
	assert_eq(rejected["rejected"]["reason"], "budget_drop")
	assert_eq(rejected["rejected"]["occupied_at_decision"], 2)
	var after: Dictionary = ledger.snapshot_state()
	assert_eq(after["roots"], before["roots"], "No old root or allocation displaced")
	assert_eq(after["occupied"], before["occupied"])
	assert_eq(after["drops"].size(), 1)
	assert_eq(after["drops"][0], rejected["rejected"])
	assert_eq(after["debug_ledger"].size(), 1)
	assert_false(after.has("events"), "Budget denial emits no compensating event")


func test_different_injected_order_changes_winner_without_category_branches():
	var forward: RefCounted = _ledger(2, {"presentation": 0, "logic": 1})
	var backward: RefCounted = _ledger(2, {"presentation": 1, "logic": 0})
	var items: Array = [_item("fx", "presentation"), _item("hit", "logic")]
	assert_eq(forward.admit_root("r", items)["kept"][0]["item_id"], "hit")
	assert_eq(backward.admit_root("r", items)["kept"][0]["item_id"], "fx")


func test_priority_table_missing_empty_duplicate_and_unknown_category_are_explicit_failures():
	var missing: Dictionary = _policy()
	missing.erase("priorities")
	var absent: RefCounted = Budget.new()
	assert_false(absent.configure(missing, _limits()))
	assert_false(absent.last_error.is_empty())
	var empty: RefCounted = Budget.new()
	assert_false(empty.configure(_policy(5, {}), _limits()))
	assert_false(empty.last_error.is_empty())
	var duplicate: RefCounted = Budget.new()
	assert_false(duplicate.configure(_policy(5, {"fx": 0, "hit": 0}), _limits()))
	assert_string_contains(duplicate.last_error, "Duplicate")
	var ledger: RefCounted = _ledger()
	var unknown: Dictionary = ledger.admit_root("r", [_item("not_registered", "unknown")])
	assert_false(unknown["ok"])
	assert_false(unknown["error"].is_empty())
	assert_eq(ledger.snapshot_state()["occupied"], 0)
	assert_eq(ledger.snapshot_state()["drops"], [])


func test_debug_record_is_only_in_debug_ledger_and_formal_types_are_checked_from_params():
	var ledger: RefCounted = _ledger(1)
	var official: Dictionary = {"type": "hit_settled", "value": 5}
	assert_true(ledger.record_settlement(official))
	assert_false(ledger.record_settlement({"type": "debug_record"}))
	assert_false(ledger.record_settlement({"type": "hit"}))
	assert_true(ledger.admit_root("first", [])["admitted"])
	assert_true(ledger.admit_root("second", [])["ok"])
	var state: Dictionary = ledger.snapshot_state()
	assert_eq(state["settlement_records"], [official])
	assert_eq(state["debug_ledger"].size(), 1)
	assert_eq(state["debug_ledger"][0]["type"], "debug_record")
	assert_eq(state["debug_ledger"][0]["kind"], "budget_drop")
	assert_false(state.has("events"))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Budget.PARAMS_PATH))
	assert_eq(source["enums"]["record"].size(), 4, "Nonempty formal-record registry")
	for kind in source["enums"]["record"]:
		assert_true(ledger.record_settlement({"type": kind}), str(kind))
	assert_eq(ledger.snapshot_state()["settlement_records"].size(), 5)


func test_turning_off_debug_leaves_each_battle_outcome_and_formal_record_unchanged():
	var visible: RefCounted = _ledger(3, null, true)
	var hidden: RefCounted = _ledger(3, null, false)
	assert_true(visible.record_settlement({"type": "cast_started", "seed": 42}))
	assert_true(hidden.record_settlement({"type": "cast_started", "seed": 42}))
	var requests: Array = [
		{"root": "a", "items": [_item("fx", "presentation"), _item("hit", "logic"), _item("trail", "presentation")]},
		{"root": "b", "items": [_item("fx2", "presentation")]},
		{"root": "c", "items": []}]
	var count: int = 0
	for request in requests:
		var with_debug: Dictionary = visible.admit_root(request["root"], request["items"])
		var without_debug: Dictionary = hidden.admit_root(request["root"], request["items"])
		assert_eq(with_debug, without_debug, "Result must match on every request")
		count += 1
	assert_eq(count, 3, "Not a vacuous comparison")
	var a: Dictionary = visible.snapshot_state()
	var b: Dictionary = hidden.snapshot_state()
	for key in ["roots", "drops", "settlement_records", "occupied", "capacity"]:
		assert_eq(a[key], b[key], key)
	assert_gt(a["debug_ledger"].size(), 0)
	assert_eq(b["debug_ledger"], [])
	assert_true(visible.set_debug_enabled(false))
	assert_eq(visible.admit_root("d", []), hidden.admit_root("d", []))
	assert_eq(visible.snapshot_state()["debug_ledger"].size(), a["debug_ledger"].size(), "Disabling only stops new debug entries")


func test_hard_cap_injection_changes_admission_and_each_unresolved_provisional_fails():
	var low: RefCounted = _ledger(2, null, true, 2)
	var high: RefCounted = _ledger(3, null, true, 3)
	for id in ["a", "b"]:
		assert_true(low.admit_root(id, [])["admitted"])
		assert_true(high.admit_root(id, [])["admitted"])
	assert_false(low.admit_root("c", [])["admitted"])
	assert_true(high.admit_root("c", [])["admitted"])
	var exceeds: RefCounted = Budget.new()
	assert_false(exceeds.configure(_policy(3), _limits(2)))
	assert_false(exceeds.last_error.is_empty())
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Budget.LIMITS_PATH))
	var checked: int = 0
	for section in ["defaults", "hard_caps"]:
		for key in source[section]:
			if str(key).begins_with("_") or not source[section][key]["_provisional"]:
				continue
			var overrides: Dictionary = _limits()
			overrides[section].erase(key)
			var runner: RefCounted = Budget.new()
			assert_false(runner.configure(_policy(), overrides))
			assert_string_contains(runner.last_error, section + "." + key)
			checked += 1
	assert_eq(checked, 4, "Every provisional entry was exercised")


func test_repeated_inputs_with_same_seed_produce_identical_records_and_do_not_write_cfg():
	var fixture: Dictionary = {"seed": 31415, "requests": [
		{"root": "a", "items": [_item("a_fx", "presentation"), _item("a_logic", "logic")]},
		{"root": "b", "items": [_item("b_fx", "presentation"), _item("b_logic", "logic")]},
		{"root": "c", "items": []}]}
	var before: Dictionary = fixture.duplicate(true)
	var one: RefCounted = _ledger(4)
	var two: RefCounted = _ledger(4)
	var compared: int = 0
	for request in fixture["requests"]:
		assert_eq(one.admit_root(request["root"], request["items"]), two.admit_root(request["root"], request["items"]))
		compared += 1
	assert_eq(compared, 3)
	assert_eq(one.snapshot_state(), two.snapshot_state())
	assert_eq(fixture, before, "Inputs are not a runtime ledger")
	# 三条痕：b 的表现层与逻辑层各被丢弃一条，随后 c 作为新根被容量拒绝也留一条（拒绝不留痕 = 静默丢弃）
	assert_eq(one.snapshot_state()["drops"].size(), 3)
	assert_eq(one.snapshot_state()["drops"].map(func(entry): return entry["item_id"]), ["b_fx", "b_logic", "c"])


func test_missing_json_and_invalid_item_do_not_silently_admit_or_change_state():
	var missing: RefCounted = Budget.new("res://data/missing_t048_limits.json")
	assert_false(missing.configure(_policy(), _limits()))
	assert_false(missing.last_error.is_empty())
	var ledger: RefCounted = _ledger()
	var bad: Dictionary = ledger.admit_root("root", [_item("item", "logic", -1)])
	assert_false(bad["ok"])
	assert_false(bad["error"].is_empty())
	assert_eq(ledger.snapshot_state()["roots"], {})
	assert_eq(ledger.snapshot_state()["occupied"], 0)
