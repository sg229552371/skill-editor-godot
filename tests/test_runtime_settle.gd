extends GutTest

const SettleScript = preload("res://skill_core/runtime/settle.gd")
const ShapeScript = preload("res://skill_core/runtime/shape_hit.gd")
const BodyScript = preload("res://skill_core/runtime/effect_body.gd")
const ClockScript = preload("res://skill_core/runtime/sim_clock.gd")


func _part(index: int, kind: String, amount: float = 10.0) -> Dictionary:
	return {"part_index": index, "type": kind, "amount": amount, "evadable": true}


func _target() -> Dictionary:
	return {"target_id": "victim", "position": Vector2.ZERO, "alive": true,
		"hp": 100.0, "invulnerable": false, "evade": {}, "immune": {}, "applied": []}


# Explicit host integration: damage/healing are host stats, not new CFG fields.
func _damage(_part_cfg: Dictionary, record: Dictionary, target: Dictionary) -> bool:
	target["hp"] = maxf(0.0, float(target["hp"]) - float(record["value"]))
	if target["hp"] == 0.0:
		target["alive"] = false
	target["applied"].append(record.duplicate(true))
	return true


func _heal(_part_cfg: Dictionary, record: Dictionary, target: Dictionary) -> bool:
	target["hp"] += record["value"]
	target["applied"].append(record.duplicate(true))
	return true


func _effect(part_cfg: Dictionary, record: Dictionary, target: Dictionary) -> bool:
	target["applied"].append({"part": part_cfg.duplicate(true), "result": record.duplicate(true)})
	return true


func _handlers() -> Dictionary:
	return {"physical": _damage, "fire": _damage, "ice": _damage,
		"lightning": _damage, "arcane": _damage, "heal": _heal,
		"shield": _effect, "buff": _effect, "debuff": _effect,
		"knockback": _effect, "control": _effect}


func _runner(parts: Array, clock: RefCounted, notifications: Array, policy: Variant = null, body: Variant = null, on_hit: Callable = Callable()) -> RefCounted:
	var runner: RefCounted = SettleScript.new(SettleScript.META_PATH, SettleScript.PROVISIONAL_META)
	var effect_body: RefCounted = body
	if effect_body == null:
		effect_body = BodyScript.create("independent", {"body_id": "settle", "lifetime_ticks": 100}, 0)
	var quota: Dictionary = {"per_target_limit": 1, "max_hits": 1}
	if policy != null:
		quota = policy
	var notify: Callable = func(event: Dictionary):
		notifications.append(event)
		if on_hit.is_valid():
			on_hit.call(event)
	var template: Dictionary = {"parts": parts, "geometry": {"shape": "circle", "radius": 5}, "hit_policy": quota}
	assert_true(runner.configure(template, effect_body, clock, _handlers(), notify,
		ShapeScript.new(ShapeScript.META_PATH, ShapeScript.PROVISIONAL_META)), runner.last_error)
	return runner


func test_ed_17_01_three_parts_one_evade_one_hit_one_derivation():
	var calls: Array = []
	var runner: RefCounted = _runner([_part(7, "physical"), _part(2, "fire"), _part(9, "ice")], ClockScript.new(1), calls)
	var target: Dictionary = _target()
	target["evade"]["fire"] = 1.0
	var result: Dictionary = runner.step([target])
	assert_true(result["ok"])
	assert_eq(result["events"].size(), 1)
	assert_eq(result["records"].size(), 1)
	var parts: Array = result["records"][0]["parts"]
	assert_eq(parts.size(), 3)
	assert_eq([parts[0]["part_index"], parts[1]["part_index"], parts[2]["part_index"]], [7, 2, 9])
	assert_eq([parts[0]["evaded"], parts[1]["evaded"], parts[2]["evaded"]], [false, true, false])
	assert_eq(target["hp"], 80.0)
	assert_eq(calls.size(), 1, "One derivation dispatch, not one per part")
	assert_eq(calls[0]["type"], "hit")
	assert_eq(runner.snapshot_state()["hit_count"], 1)


func test_ed_17_02_all_evaded_spends_contact_not_hit_and_no_overlap_reroll():
	var clock: RefCounted = ClockScript.new(2)
	var calls: Array = []
	var runner: RefCounted = _runner([_part(0, "fire"), _part(1, "ice"), _part(2, "physical")], clock, calls)
	var target: Dictionary = _target()
	target["evade"] = {"fire": 1.0, "ice": 1.0, "physical": 1.0}
	var first: Dictionary = runner.step([target])
	assert_true(first["ok"])
	assert_eq(first["events"].size(), 0)
	assert_eq(first["records"].size(), 1)
	assert_eq(first["records"][0]["type"], "evaded_all")
	assert_eq(first["records"][0]["parts"].size(), 3)
	assert_eq(runner.snapshot_state()["candidate_count"], 1)
	assert_eq(runner.snapshot_state()["hit_count"], 0)
	assert_eq(calls.size(), 0)
	clock.tick()
	var overlap: Dictionary = runner.step([target])
	assert_true(overlap["ok"])
	assert_eq(overlap["candidates"].size(), 0)
	assert_eq(overlap["records"].size(), 0)
	clock.tick()
	var other: Dictionary = _target()
	other["target_id"] = "other"
	var next: Dictionary = runner.step([target, other])
	assert_eq(next["events"].size(), 1, "Evaded contact did not spend max_hits")
	assert_eq(next["events"][0]["target_id"], "other")
	assert_eq(calls.size(), 1)
	assert_eq(runner.snapshot_state()["candidate_count"], 2)


func test_ed_17_03_invulnerable_damage_heal_control_are_distinct():
	var control: Dictionary = _part(2, "control")
	control["control_type"] = "stun"
	for immune in [false, true]:
		var calls: Array = []
		var runner: RefCounted = _runner([_part(0, "physical"), _part(1, "heal"), control], ClockScript.new(3), calls)
		var target: Dictionary = _target()
		target["invulnerable"] = true
		target["immune"]["stun"] = immune
		var result: Dictionary = runner.step([target])
		assert_true(result["ok"])
		assert_eq(result["events"].size(), 1)
		assert_eq(result["records"].size(), 1)
		var parts: Array = result["records"][0]["parts"]
		assert_eq(parts.size(), 3)
		assert_true(parts[0]["evaded"])
		assert_false(parts[0]["immune"])
		assert_false(parts[1]["evaded"])
		assert_eq(parts[1]["value"], 10.0)
		assert_eq(target["hp"], 110.0)
		assert_false(parts[2]["evaded"], "Control does not inherit damage invulnerability")
		assert_eq(parts[2]["immune"], immune)
		assert_eq(parts[2]["zero"], immune)
		assert_eq(target["applied"].size(), 1 if immune else 2)
		assert_eq(calls.size(), 1)


func test_ed_17_04_immune_zero_still_hit_not_evaded_all():
	var calls: Array = []
	var runner: RefCounted = _runner([_part(0, "ice")], ClockScript.new(4), calls)
	var target: Dictionary = _target()
	target["immune"]["ice"] = true
	var result: Dictionary = runner.step([target])
	assert_true(result["ok"])
	assert_eq(result["events"].size(), 1)
	assert_eq(result["records"].size(), 1)
	assert_eq(result["records"][0]["type"], "hit_settled")
	var part: Dictionary = result["records"][0]["parts"][0]
	assert_false(part["evaded"])
	assert_true(part["immune"])
	assert_true(part["zero"])
	assert_eq(part["value"], 0.0)
	assert_eq(target["hp"], 100.0)
	assert_eq(target["applied"].size(), 0)
	assert_eq(calls.size(), 1)
	assert_eq(runner.snapshot_state()["candidate_count"], 1)
	assert_eq(runner.snapshot_state()["hit_count"], 1)


func test_ed_17_05_shot_and_hit_derived_instant_hit_before_end():
	var clock: RefCounted = ClockScript.new(5)
	var order: Array = []
	var derived: Array = []
	var child_calls: Array = []
	var root_calls: Array = []
	var spawn_child: Callable = func(event: Dictionary):
		order.append("root_hit")
		var child_body: RefCounted = BodyScript.create("none", {"body_id": "child", "lifetime_ticks": 0}, int(event["tick"]) + 1)
		var child: RefCounted = _runner([_part(0, "physical")], clock, child_calls, null, child_body)
		derived.append({"body": child_body, "settle": child})
	var root_body: RefCounted = BodyScript.create("none", {"body_id": "shot", "lifetime_ticks": 0}, 0)
	var root: RefCounted = _runner([_part(0, "physical")], clock, root_calls, null, root_body, spawn_child)
	var target: Dictionary = _target()
	var first: Dictionary = root.step([target])
	assert_eq(first["events"].size(), 1)
	assert_eq(first["events"][0]["tick"], 0)
	assert_eq(derived.size(), 1)
	assert_eq(root_body.step(0).size(), 1)
	order.append("root_end")
	var child: RefCounted = derived[0]["settle"]
	var child_body: RefCounted = derived[0]["body"]
	assert_eq(child.step([target])["events"].size(), 0, "No recursive same-tick hit")
	assert_eq(child_body.step(0).size(), 0)
	assert_eq(child_calls.size(), 0)
	clock.tick()
	var next: Dictionary = child.step([target])
	assert_eq(next["events"].size(), 1)
	assert_eq(next["events"][0]["tick"], 1)
	assert_eq(child_calls.size(), 1)
	order.append("child_hit")
	var ended: Array = child_body.step(1)
	assert_eq(ended.size(), 1)
	assert_eq(ended[0]["reason"], "instant_end")
	order.append("child_end")
	assert_eq(order, ["root_hit", "root_end", "child_hit", "child_end"])
	assert_eq(target["hp"], 80.0)


func test_ed_17_06_fifo_death_suppresses_later_instance():
	var clock: RefCounted = ClockScript.new(6)
	var calls: Array = []
	var first: RefCounted = _runner([_part(0, "physical", 100.0)], clock, calls)
	var second: RefCounted = _runner([_part(0, "physical", 100.0)], clock, calls)
	var target: Dictionary = _target()
	var killed: Dictionary = first.step([target])
	var later: Dictionary = second.step([target])
	assert_true(killed["ok"])
	assert_true(later["ok"])
	assert_eq(killed["events"].size(), 1)
	assert_eq(killed["records"].size(), 1)
	assert_true(killed["records"][0]["killed"])
	assert_false(target["alive"])
	assert_eq(later["events"].size(), 0)
	assert_eq(later["records"].size(), 0, "Dead target is not evaded_all")
	assert_eq(later["candidates"].size(), 0)
	assert_eq(target["applied"].size(), 1)
	assert_eq(calls.size(), 1)
	assert_eq(second.snapshot_state()["candidate_count"], 0)
	assert_eq(second.snapshot_state()["hit_count"], 0)


func test_all_eleven_registered_types_settle_through_explicit_host_adapters():
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SettleScript.PARAMS_PATH))
	assert_true(parsed is Dictionary)
	var types: Array = parsed["enums"]["part_type"]
	assert_eq(types, ["physical", "fire", "ice", "lightning", "arcane", "heal", "shield", "buff", "debuff", "knockback", "control"])
	assert_eq(types.size(), 11, "Nonempty coverage guard")
	var visited: Array = []
	for kind in types:
		var calls: Array = []
		var target: Dictionary = _target()
		var runner: RefCounted = _runner([_part(0, kind)], ClockScript.new(7), calls)
		var result: Dictionary = runner.step([target])
		assert_true(result["ok"], str(kind))
		assert_eq(result["events"].size(), 1, str(kind))
		assert_eq(result["records"].size(), 1, str(kind))
		assert_eq(result["records"][0]["parts"].size(), 1)
		assert_eq(result["records"][0]["parts"][0]["type"], kind)
		assert_eq(result["records"][0]["parts"][0]["value"], 10.0)
		assert_eq(target["applied"].size(), 1, "The registered host handler actually ran")
		assert_eq(calls.size(), 1)
		visited.append(kind)
	assert_eq(visited, types)


func test_cfg_and_snapshot_isolation_and_idempotent_same_tick():
	var calls: Array = []
	var clock: RefCounted = ClockScript.new(8)
	var parts: Array = [_part(9, "physical"), _part(1, "heal")]
	var original: Array = parts.duplicate(true)
	var runner: RefCounted = _runner(parts, clock, calls)
	var target: Dictionary = _target()
	var result: Dictionary = runner.step([target])
	assert_true(result["ok"])
	assert_eq(parts, original, "No CFG writes from settlement")
	assert_eq(result["records"][0]["parts"][0]["part_index"], 9)
	assert_eq(result["records"][0]["parts"][1]["part_index"], 1)
	result["records"][0]["parts"][0]["value"] = -999
	var state: Dictionary = runner.snapshot_state()
	assert_eq(state["records"][0]["parts"][0]["value"], 10.0)
	state["records"].clear()
	assert_eq(runner.snapshot_state()["records"].size(), 1)
	assert_eq(runner.step([target])["records"].size(), 0)
	assert_eq(calls.size(), 1)
	assert_eq(target["hp"], 100.0)


func test_configure_copies_parts_before_caller_edits():
	var parts: Array = [_part(0, "physical")]
	var runner: RefCounted = _runner(parts, ClockScript.new(8), [])
	parts[0]["amount"] = 1000.0
	var target: Dictionary = _target()
	assert_true(runner.step([target])["ok"])
	assert_eq(target["hp"], 90.0)
	assert_true(target["alive"])


func _replay(presentation_draws: int) -> Dictionary:
	var clock: RefCounted = ClockScript.new(9182)
	var runner: RefCounted = _runner([_part(0, "fire"), _part(1, "ice"), _part(2, "heal")], clock, [],
		{"per_target_limit": 20, "rehit_interval_ticks": 1})
	var target: Dictionary = _target()
	target["hp"] = 10000.0
	target["evade"] = {"fire": 0.37, "ice": 0.53, "heal": 0.29}
	var log: Array = []
	for tick in range(20):
		for _i in range(presentation_draws):
			clock.rng_presentation().randf()
		var result: Dictionary = runner.step([target])
		assert_true(result["ok"])
		assert_eq(result["records"].size(), 1)
		log.append(result)
		if tick < 19:
			clock.tick()
	return {"log": log, "state": runner.snapshot_state(), "target": target, "logic_state": clock.rng_logic().state}


func test_logic_rng_repeatable_and_independent_of_presentation_rng():
	var first: Dictionary = _replay(0)
	assert_eq(first["log"].size(), 20)
	assert_eq(first["state"]["candidate_count"], 20)
	assert_eq(first, _replay(0))
	assert_eq(first, _replay(17))


func test_purge_is_silent_and_does_not_consume_rng_or_quota():
	var clock: RefCounted = ClockScript.new(10)
	var calls: Array = []
	var body: RefCounted = BodyScript.create("independent", {"body_id": "purged", "lifetime_ticks": 10}, 0)
	var runner: RefCounted = _runner([_part(0, "physical")], clock, calls, null, body)
	var rng_state: int = clock.rng_logic().state
	body.purge()
	var result: Dictionary = runner.step([_target()])
	assert_true(result["ok"])
	assert_eq(result["candidates"].size(), 0)
	assert_eq(result["events"].size(), 0)
	assert_eq(result["records"].size(), 0)
	assert_eq(body.step(0).size(), 0)
	assert_eq(calls.size(), 0)
	assert_eq(clock.rng_logic().state, rng_state)


func _configure(runner: RefCounted, parts: Array, handlers: Variant = null) -> bool:
	var adapters: Dictionary = _handlers() if handlers == null else handlers
	return runner.configure({"parts": parts, "geometry": {"shape": "circle", "radius": 5},
		"hit_policy": {"per_target_limit": 1}},
		BodyScript.create("independent", {"lifetime_ticks": 100}, 0), ClockScript.new(1), adapters,
		Callable(), ShapeScript.new(ShapeScript.META_PATH, ShapeScript.PROVISIONAL_META))


func test_missing_or_wrong_metadata_fails_explicitly_without_fallback():
	var cases: Array = [
		SettleScript.new("res://data/__missing_t044_meta__.json"),
		SettleScript.new(SettleScript.PARAMS_PATH),
		SettleScript.new(SettleScript.META_PATH, {}),
		SettleScript.new(SettleScript.META_PATH, SettleScript.PROVISIONAL_META, "res://data/__missing_t044_params__.json"),
		SettleScript.new("res://S_docs/collab/assets/params_meta.json"),
	]
	assert_eq(cases.size(), 5)
	for runner in cases:
		assert_false(runner.last_error.is_empty())
		assert_false(_configure(runner, [_part(0, "physical")]))
		assert_false(runner.step([_target()])["ok"])


func test_unknown_empty_duplicate_invalid_parts_and_unresolved_profiles_fail():
	var invalid: Array = [[], [_part(0, "unknown")], [_part(0, "fire"), _part(0, "ice")],
		[{"type": "physical"}], [{"part_index": 0, "type": "fire", "amount": NAN}],
		[{"part_index": 0, "type": "fire", "amount": -1}],
		[{"part_index": 0, "type": "fire", "amount": "10"}],
		[{"part_index": 0, "type": "fire", "made_up": true}],
		[{"part_index": 0, "type": "fire", "amount_profile": "not_resolved"}],
		[{"part_index": 0, "type": "fire", "duration_ticks": 0}]]
	assert_eq(invalid.size(), 10)
	for parts in invalid:
		for part in parts:
			part["evadable"] = true
		var runner: RefCounted = SettleScript.new(SettleScript.META_PATH, SettleScript.PROVISIONAL_META)
		assert_false(_configure(runner, parts), str(parts))
		assert_false(runner.last_error.is_empty())


func test_missing_type_adapter_fails_instead_of_silent_noop():
	var handlers: Dictionary = _handlers()
	handlers.erase("control")
	var runner: RefCounted = SettleScript.new(SettleScript.META_PATH, SettleScript.PROVISIONAL_META)
	assert_false(_configure(runner, [_part(0, "fire")], handlers))
	assert_true(runner.last_error.contains("control"))


func test_bad_target_gate_preflight_does_not_spend_contact():
	var runner: RefCounted = _runner([_part(0, "fire")], ClockScript.new(10), [])
	var target: Dictionary = _target()
	target["evade"]["fire"] = 1.01
	assert_false(runner.step([target])["ok"])
	assert_eq(runner.snapshot_state()["candidate_count"], 0)
	target["evade"]["fire"] = 0.0
	assert_eq(runner.step([target])["events"].size(), 1)


func test_adapter_failure_is_fault_not_evaded_all_and_discards_staged_writes():
	var handlers: Dictionary = _handlers()
	handlers["fire"] = func(_part_cfg: Dictionary, _record: Dictionary, staged: Dictionary) -> bool:
		staged["hp"] = -1000
		return false
	var runner: RefCounted = SettleScript.new(SettleScript.META_PATH, SettleScript.PROVISIONAL_META)
	assert_true(_configure(runner, [_part(0, "physical"), _part(1, "fire")], handlers))
	var target: Dictionary = _target()
	var before: Dictionary = target.duplicate(true)
	var result: Dictionary = runner.step([target])
	assert_false(result["ok"])
	assert_eq(result["records"].size(), 0)
	assert_eq(result["events"].size(), 0)
	assert_eq(target, before)
	assert_eq(runner.snapshot_state()["candidate_count"], 1)
	assert_eq(runner.snapshot_state()["hit_count"], 0)
	assert_false(runner.step([target])["ok"], "Fault cannot be retried for a free reroll")


func test_immune_flags_and_profile_keys_are_injected_runtime_gates():
	for extra in [{"immune_flags": ["magic"]}, {"immunity_profile": "magic"}]:
		var part: Dictionary = _part(0, "arcane")
		part.merge(extra)
		var target: Dictionary = _target()
		target["immune"]["magic"] = true
		var runner: RefCounted = _runner([part], ClockScript.new(11), [])
		var result: Dictionary = runner.step([target])
		assert_eq(result["events"].size(), 1)
		assert_true(result["records"][0]["parts"][0]["immune"])
		assert_eq(target["hp"], 100.0)


func test_non_evadable_and_natural_zero_are_not_immunity():
	var part: Dictionary = _part(0, "fire", 0.0)
	part["evadable"] = false
	var target: Dictionary = _target()
	target["evade"]["fire"] = 1.0
	var runner: RefCounted = _runner([part], ClockScript.new(12), [])
	var result: Dictionary = runner.step([target])
	assert_eq(result["events"].size(), 1)
	var record: Dictionary = result["records"][0]["parts"][0]
	assert_false(record["evaded"])
	assert_false(record["immune"])
	assert_true(record["zero"])
	assert_eq(target["applied"].size(), 1)


func test_target_gate_names_are_metadata_driven():
	var meta: Dictionary = SettleScript.PROVISIONAL_META.duplicate(true)
	meta["target_roles"] = {"invulnerable": "god_mode", "evade": "dodge_table", "immune": "resist_table"}
	var runner: RefCounted = SettleScript.new(SettleScript.META_PATH, meta)
	assert_true(_configure(runner, [_part(0, "physical"), _part(1, "heal")]))
	var target: Dictionary = _target()
	target.erase("invulnerable")
	target.erase("evade")
	target.erase("immune")
	target["god_mode"] = true
	target["dodge_table"] = {}
	target["resist_table"] = {}
	var result: Dictionary = runner.step([target])
	assert_true(result["ok"])
	assert_eq(result["events"].size(), 1)
	assert_true(result["records"][0]["parts"][0]["evaded"])
	assert_eq(result["records"][0]["parts"][1]["value"], 10.0)
	assert_eq(target["hp"], 110.0)


func test_host_adapter_receives_real_status_and_displacement_fields():
	var handlers: Dictionary = _handlers()
	handlers["shield"] = func(_cfg: Dictionary, record: Dictionary, target: Dictionary) -> bool:
		target["shield"] = record["value"]
		return true
	handlers["control"] = func(cfg: Dictionary, _record: Dictionary, target: Dictionary) -> bool:
		target["control"] = {"kind": cfg["control_type"], "ticks": cfg["duration_ticks"]}
		return true
	handlers["knockback"] = func(cfg: Dictionary, _record: Dictionary, target: Dictionary) -> bool:
		target["position"] += Vector2.RIGHT * float(cfg["distance"])
		return true
	var control: Dictionary = _part(1, "control")
	control.merge({"control_type": "stun", "duration_ticks": 4})
	var knockback: Dictionary = _part(2, "knockback")
	knockback["distance"] = 2.0
	var runner: RefCounted = SettleScript.new(SettleScript.META_PATH, SettleScript.PROVISIONAL_META)
	assert_true(_configure(runner, [_part(0, "shield"), control, knockback], handlers))
	var target: Dictionary = _target()
	var result: Dictionary = runner.step([target])
	assert_true(result["ok"])
	assert_eq(result["events"].size(), 1)
	assert_eq(result["records"][0]["parts"].size(), 3)
	assert_eq(target["shield"], 10.0)
	assert_eq(target["control"], {"kind": "stun", "ticks": 4})
	assert_eq(target["position"], Vector2(2, 0))


func test_absent_evadable_requires_explicit_metadata_default():
	var part: Dictionary = _part(0, "fire")
	part.erase("evadable")
	var unresolved: RefCounted = SettleScript.new(SettleScript.META_PATH, SettleScript.PROVISIONAL_META)
	assert_false(_configure(unresolved, [part]))
	assert_true(unresolved.last_error.contains("evadable default"))
	var meta: Dictionary = SettleScript.PROVISIONAL_META.duplicate(true)
	meta["evadable_default"] = true
	var resolved: RefCounted = SettleScript.new(SettleScript.META_PATH, meta)
	assert_true(_configure(resolved, [part]))
	var target: Dictionary = _target()
	target["evade"]["fire"] = 1.0
	var result: Dictionary = resolved.step([target])
	assert_true(result["ok"])
	assert_eq(result["events"].size(), 0)
	assert_eq(result["records"].size(), 1)
	assert_eq(result["records"][0]["type"], "evaded_all")

# ---- WorkBuddy 复核补测：生产元数据资产必须可用（与过渡表等价） ----

func test_production_metadata_asset_drives_settlement() -> void:
	var file: FileAccess = FileAccess.open(SettleScript.META_PATH, FileAccess.READ)
	assert_not_null(file, "生产元数据必须存在: " + SettleScript.META_PATH)
	var parser: JSON = JSON.new()
	assert_eq(parser.parse(file.get_as_text()), OK, parser.get_error_message())
	file.close()
	assert_true(parser.data is Dictionary)
	var meta: Dictionary = parser.data as Dictionary
	var provisional: Dictionary = SettleScript.PROVISIONAL_META
	for key in ["roles", "target_roles", "invulnerable_evades", "immunity_selectors",
			"immunity_flags", "unresolved_fields", "hit_record", "evade_record"]:
		assert_eq(meta[key], provisional[key], "生产素材与过渡表必须一致: " + key)
	# 真源口径：无敌只让五种伤害份视为闪避（1261/1547/1574），不波及 debuff/knockback/control
	assert_eq(meta["invulnerable_evades"], ["physical", "fire", "ice", "lightning", "arcane"])
	# 真源 2110：evadable 按有益有害补默认 —— 有害可闪避、有益不可闪避
	var by_kind: Variant = meta.get("evadable_default_by_kind", null)
	assert_true(by_kind is Dictionary, "必须登记按种类的补默认规则")
	for kind in ["physical", "fire", "ice", "lightning", "arcane", "debuff", "knockback", "control"]:
		assert_true(by_kind.has(kind), "有害份缺补默认: " + kind)
		assert_eq(by_kind[kind], true, "有害份必须判闪避: " + kind)
	for kind in ["heal", "shield", "buff"]:
		assert_true(by_kind.has(kind), "有益份缺补默认: " + kind)
		assert_eq(by_kind[kind], false, "有益份不判闪避: " + kind)
	# 生产素材（非注入）必须能真正驱动结算
	var runner: RefCounted = SettleScript.new(SettleScript.META_PATH, null)
	assert_eq(runner.last_error, "", runner.last_error)
	var notify_hits: Array = []
	var template: Dictionary = {"parts": [_part(0, "physical", 10.0)],
		"geometry": {"shape": "circle", "radius": 5}, "hit_policy": {"per_target_limit": 1, "max_hits": 1}}
	assert_true(runner.configure(template,
		BodyScript.create("independent", {"body_id": "prod", "lifetime_ticks": 100}, 0),
		ClockScript.new(11), _handlers(),
		func(event: Dictionary): notify_hits.append(event),
		ShapeScript.new(ShapeScript.META_PATH, null)), runner.last_error)
	var target: Dictionary = _target()
	var result: Dictionary = runner.step([target])
	assert_true(result["ok"], str(result["error"]))
	assert_eq(result["events"].size(), 1)
	assert_eq(target["hp"], 90.0)

func test_absent_evadable_falls_back_to_harmful_or_beneficial_rule() -> void:
	# 真源 2110：缺省 evadable 按有益有害补默认，不要求作者逐份显式写
	var runner: RefCounted = SettleScript.new(SettleScript.META_PATH, null)
	assert_eq(runner.last_error, "", runner.last_error)
	var harmful: Dictionary = {"part_index": 0, "type": "fire", "amount": 10.0}
	var beneficial: Dictionary = {"part_index": 1, "type": "heal", "amount": 5.0}
	var unregistered: Dictionary = {"part_index": 2, "type": "not_a_type", "amount": 1.0}
	assert_true(_configure_with(runner, [harmful, beneficial]))
	var target: Dictionary = _target()
	target["hp"] = 50.0
	target["evade"]["fire"] = 1.0  # 有害份走闪避判定 → 被闪避；有益份不判闪避 → 正常治疗
	var result: Dictionary = runner.step([target])
	assert_true(result["ok"], str(result["error"]))
	var parts: Array = result["records"][0]["parts"]
	assert_eq(parts[0]["evaded"], true, "有害份缺省可闪避")
	assert_eq(parts[1]["evaded"], false, "有益份缺省不判闪避")
	assert_eq(target["hp"], 55.0)
	# 未登记种类补不出默认 → 显式失败，不猜
	var strict: RefCounted = SettleScript.new(SettleScript.META_PATH, null)
	assert_false(_configure_with(strict, [unregistered]))
	assert_true(strict.last_error.contains("Unknown part field") or strict.last_error.contains("part"), strict.last_error)

func _configure_with(runner: RefCounted, parts: Array) -> bool:
	var template: Dictionary = {"parts": parts,
		"geometry": {"shape": "circle", "radius": 5}, "hit_policy": {"per_target_limit": 1, "max_hits": 1}}
	return runner.configure(template,
		BodyScript.create("independent", {"body_id": "fallback", "lifetime_ticks": 100}, 0),
		ClockScript.new(12), _handlers(), func(_event: Dictionary): pass,
		ShapeScript.new(ShapeScript.META_PATH, null))
