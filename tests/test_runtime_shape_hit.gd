extends GutTest

const ShapeScript = preload("res://skill_core/runtime/shape_hit.gd")
const BodyScript = preload("res://skill_core/runtime/effect_body.gd")
const ClockScript = preload("res://skill_core/runtime/sim_clock.gd")


func _body() -> RefCounted:
	return BodyScript.create(BodyScript.CARRIER_INDEPENDENT, {"body_id": "shape_test", "lifetime_ticks": 100}, 0)


func _shape() -> RefCounted:
	# Explicit temporary metadata injection; never a missing-file fallback.
	return ShapeScript.new(ShapeScript.META_PATH, ShapeScript.PROVISIONAL_META)


func _template(geometry: Dictionary, policy: Dictionary) -> Dictionary:
	return {"geometry": geometry, "hit_policy": policy}


func test_circle_closed_boundary():
	var shape: RefCounted = _shape()
	assert_true(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 1}), _body(), ClockScript.new(1)))
	assert_true(shape.contains_point(Vector2.ZERO))
	assert_true(shape.contains_point(Vector2(3, 4)), "Radius exactly equal is inside")
	assert_false(shape.contains_point(Vector2(5.001, 0)))


func test_sector_closed_radial_and_angular_boundaries():
	var shape: RefCounted = _shape()
	assert_true(shape.configure(_template({"shape": "sector", "radius": 5, "sector_angle": 90}, {"per_target_limit": 1}), _body(), ClockScript.new(1)))
	assert_true(shape.contains_point(Vector2.ZERO), "Apex is included")
	assert_true(shape.contains_point(Vector2(5, 0)), "Outer arc is included")
	assert_true(shape.contains_point(Vector2(1, 1)), "Upper angular edge is included")
	assert_true(shape.contains_point(Vector2(1, -1)), "Lower angular edge is included")
	assert_false(shape.contains_point(Vector2(5.001, 0)))
	assert_false(shape.contains_point(Vector2(1, 1.001)))
	assert_false(shape.contains_point(Vector2(1, -1.001)))
	assert_false(shape.contains_point(Vector2(-1, 0)))


func test_sector_uses_registered_default_full_angle():
	var shape: RefCounted = _shape()
	assert_true(shape.configure(_template({"shape": "sector", "radius": 5}, {"per_target_limit": 1}), _body(), ClockScript.new(1)))
	assert_true(shape.contains_point(Vector2.from_angle(deg_to_rad(12.49))))
	assert_false(shape.contains_point(Vector2.from_angle(deg_to_rad(12.51))))


func test_line_flat_end_closed_boundaries():
	var shape: RefCounted = _shape()
	assert_true(shape.configure(_template({"shape": "line", "length": 6, "width": 2}, {"per_target_limit": 1}), _body(), ClockScript.new(1)))
	for point in [Vector2.ZERO, Vector2(3, 0), Vector2(0, -1), Vector2(6, 1)]:
		assert_true(shape.contains_point(point), "Closed forward box: " + str(point))
	for point in [Vector2(-0.001, 0), Vector2(6.001, 0), Vector2(3, 1.001), Vector2(3, -1.001)]:
		assert_false(shape.contains_point(point), "Outside forward box: " + str(point))


func test_rectangle_centered_closed_boundaries_and_transform():
	var shape: RefCounted = _shape()
	assert_true(shape.configure(_template({"shape": "rectangle", "length": 6, "width": 2}, {"per_target_limit": 1}), _body(), ClockScript.new(1)))
	for point in [Vector2.ZERO, Vector2(-3, -1), Vector2(3, 1), Vector2(-3, 1), Vector2(3, -1)]:
		assert_true(shape.contains_point(point), "Closed centered box: " + str(point))
	for point in [Vector2(-3.001, 0), Vector2(3.001, 0), Vector2(0, 1.001), Vector2(0, -1.001)]:
		assert_false(shape.contains_point(point), "Outside centered box: " + str(point))
	assert_true(shape.contains_point(Vector2(11, 23), Vector2(10, 20), Vector2(0, 8)))
	assert_false(shape.contains_point(Vector2(11.001, 23), Vector2(10, 20), Vector2(0, 8)))


func test_geometry_rejects_bad_registered_fields():
	var cases: Array = [
		{"shape": "circle", "radius": 0}, {"shape": "circle", "radius": INF},
		{"shape": "circle", "radius": NAN}, {"shape": "circle", "radius": "5"},
		{"shape": "sector", "radius": 5, "sector_angle": 0},
		{"shape": "sector", "radius": 5, "sector_angle": 100.001},
		{"shape": "line", "length": 0, "width": 2},
		{"shape": "rectangle", "length": 6, "width": -1},
		{"shape": "line", "length": 6}, {"shape": "capsule", "radius": 5},
		{"shape": "circle", "radius": 5, "unknown": 1},
		{"shape": "circle", "radius": 5, "wavefront_start_radius": -1},
		{"shape": "circle", "radius": 5, "wavefront_end_radius": 0},
		{"shape": "circle", "radius": 5, "wavefront_speed": 0},
		{"shape": "circle", "radius": 5, "area_profile": "unresolved"},
	]
	assert_eq(cases.size(), 15)
	for geometry in cases:
		var shape: RefCounted = _shape()
		assert_false(shape.configure(_template(geometry, {"per_target_limit": 1}), _body(), ClockScript.new(1)), str(geometry))
		assert_false(shape.last_error.is_empty())
	var upper: RefCounted = _shape()
	assert_true(upper.configure(_template({"shape": "sector", "radius": 5, "sector_angle": 100}, {"per_target_limit": 1}), _body(), ClockScript.new(1)))


func _target(id: String, point: Vector2 = Vector2.ZERO, alive: bool = true) -> Dictionary:
	return {"target_id": id, "position": point, "alive": alive}


func test_all_evaded_contact_spends_target_quota_not_max_hits():
	var shape: RefCounted = _shape()
	var clock: RefCounted = ClockScript.new(9)
	var calls: Array = []
	var resolver: Callable = func(target: Dictionary, _rng: RandomNumberGenerator) -> bool:
		calls.append(target["target_id"])
		return target["target_id"] != "evader"
	assert_true(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 1, "max_hits": 1}), _body(), clock, resolver))
	var first: Dictionary = shape.step([_target("evader")])
	assert_true(first["ok"])
	assert_eq(first["candidates"].size(), 1)
	assert_eq(first["events"].size(), 0)
	assert_eq(shape.snapshot_state()["candidate_count"], 1)
	assert_eq(shape.snapshot_state()["hit_count"], 0)
	clock.tick()
	var second: Dictionary = shape.step([_target("evader"), _target("other")])
	assert_true(second["ok"])
	assert_eq(second["candidates"].size(), 1)
	assert_eq(second["events"].size(), 1)
	assert_eq(second["events"][0]["target_id"], "other")
	assert_eq(calls, ["evader", "other"])
	assert_eq(shape.snapshot_state()["candidate_count"], 2)
	assert_eq(shape.snapshot_state()["hit_count"], 1)
	clock.tick()
	var capped: Dictionary = shape.step([_target("third")])
	assert_eq(capped["candidates"].size(), 0)
	assert_eq(calls.size(), 2)


func test_interval_waits_after_evade_and_coalesces_due_pulse():
	var shape: RefCounted = _shape()
	var clock: RefCounted = ClockScript.new(9)
	var calls: Array = []
	var evade: Callable = func(_target_value: Dictionary, rng: RandomNumberGenerator) -> bool:
		calls.append(rng.randi())
		return false
	assert_true(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 3, "rehit_interval_ticks": 3}), _body(), clock, evade))
	assert_eq(shape.step([_target("a")])["candidates"].size(), 1)
	var after_contact: int = clock.rng_logic().state
	for tick in [1, 2]:
		assert_eq(clock.tick(), tick)
		var waiting: Dictionary = shape.step([_target("a")], {"pulse": true})
		assert_true(waiting["ok"])
		assert_eq(waiting["candidates"].size(), 0, "Pulse cannot bypass waiting")
		assert_eq(clock.rng_logic().state, after_contact)
	assert_eq(clock.tick(), 3)
	var due: Dictionary = shape.step([_target("a"), _target("a")], {"pulse": true})
	assert_eq(due["candidates"].size(), 1, "Deadline + pulse + duplicate candidate = one roll")
	assert_eq(shape.step([_target("a")], {"pulse": true})["candidates"].size(), 0)
	assert_eq(calls.size(), 2)
	assert_eq(shape.snapshot_state()["candidate_count"], 2)
	assert_eq(shape.snapshot_state()["hit_count"], 0)


func test_target_quotas_and_cooldowns_are_independent():
	var shape: RefCounted = _shape()
	var clock: RefCounted = ClockScript.new(9)
	assert_true(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 2, "rehit_interval_ticks": 2}), _body(), clock))
	assert_eq(shape.step([_target("a")])["events"].size(), 1)
	clock.tick()
	var first_b: Dictionary = shape.step([_target("a"), _target("b")])
	assert_eq(first_b["events"].size(), 1)
	assert_eq(first_b["events"][0]["target_id"], "b")
	clock.tick()
	var second_a: Dictionary = shape.step([_target("a"), _target("b")])
	assert_eq(second_a["events"].size(), 1)
	assert_eq(second_a["events"][0]["target_id"], "a")
	clock.tick()
	var second_b: Dictionary = shape.step([_target("a"), _target("b")])
	assert_eq(second_b["events"].size(), 1)
	assert_eq(second_b["events"][0]["target_id"], "b")
	for _i in range(4):
		clock.tick()
		assert_eq(shape.step([_target("a"), _target("b")], {"pulse": true})["candidates"].size(), 0)
	var state: Dictionary = shape.snapshot_state()
	assert_eq(state["candidate_count"], 4)
	assert_eq(state["hit_count"], 4, "Omitted max_hits does not secretly default to one")
	assert_eq(state["targets"]["a"]["candidate_count"], 2)
	assert_eq(state["targets"]["b"]["candidate_count"], 2)


func test_continuous_overlap_without_interval_does_not_reroll():
	var shape: RefCounted = _shape()
	var clock: RefCounted = ClockScript.new(9)
	var calls: Array = []
	var evade: Callable = func(_t: Dictionary, _rng: RandomNumberGenerator) -> bool:
		calls.append(1)
		return false
	assert_true(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 3}), _body(), clock, evade))
	assert_eq(shape.step([_target("a")])["candidates"].size(), 1)
	for _i in range(3):
		clock.tick()
		assert_eq(shape.step([_target("a")])["candidates"].size(), 0)
	assert_eq(calls.size(), 1)
	clock.tick()
	assert_eq(shape.step([])["candidates"].size(), 0)
	clock.tick()
	assert_eq(shape.step([_target("a")])["candidates"].size(), 1, "A real re-entry is a new contact")
	clock.tick()
	assert_eq(shape.step([_target("a")], {"pulse": true})["candidates"].size(), 1, "An explicit pulse is a new opportunity")
	clock.tick()
	assert_eq(shape.step([_target("a")], {"pulse": true})["candidates"].size(), 0)
	assert_eq(calls.size(), 3)


func test_invalid_policy_never_creates_a_runnable_checker():
	var policies: Array = [
		{}, {"per_target_limit": 0}, {"per_target_limit": 1.0}, {"per_target_limit": null},
		{"per_target_limit": 1, "rehit_interval_ticks": 0},
		{"per_target_limit": 1, "rehit_interval_ticks": -1},
		{"per_target_limit": 1, "rehit_interval_ticks": 1.0},
		{"per_target_limit": 1, "max_hits": 0}, {"per_target_limit": 1, "max_hits": -1},
		{"per_target_limit": 1, "max_hits": null}, {"per_target_limit": 1, "max_hits": "1"},
		{"per_target_limit": 1, "max_hits": true}, {"per_target_limit": 1, "unknown": 1},
	]
	assert_eq(policies.size(), 13)
	for policy in policies:
		var shape: RefCounted = _shape()
		assert_false(shape.configure(_template({"shape": "circle", "radius": 5}, policy), _body(), ClockScript.new(1)), str(policy))
		assert_false(shape.last_error.is_empty())
		assert_false(shape.step([_target("a")])["ok"])
	var lower: RefCounted = _shape()
	assert_true(lower.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 1, "rehit_interval_ticks": 1, "max_hits": 1}), _body(), ClockScript.new(1)))


func _seeded_trace(seed_value: int, presentation_draws: int) -> Dictionary:
	var clock: RefCounted = ClockScript.new(seed_value)
	var shape: RefCounted = _shape()
	var draws: Array = []
	var resolver: Callable = func(_t: Dictionary, rng: RandomNumberGenerator) -> bool:
		var roll: float = rng.randf()
		draws.append(roll)
		return roll >= 0.5
	assert_true(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 12, "rehit_interval_ticks": 1}), _body(), clock, resolver))
	var trace: Array = []
	for _i in range(12):
		for _j in range(presentation_draws):
			clock.rng_presentation().randi()
		var result: Dictionary = shape.step([_target("a")])
		assert_true(result["ok"])
		assert_eq(result["candidates"].size(), 1)
		trace.append(result)
		clock.tick()
	return {"trace": trace, "draws": draws, "ledger": shape.snapshot_state(), "logic_state": clock.rng_logic().state}


func test_hit_rng_is_logic_only_and_reproducible_step_by_step():
	var plain: Dictionary = _seeded_trace(193, 0)
	var noisy: Dictionary = _seeded_trace(193, 7)
	assert_eq(plain["draws"].size(), 12, "Nonempty deterministic trace")
	assert_eq(plain["trace"].size(), 12)
	assert_eq(plain, noisy, "Presentation draws cannot perturb any candidate, hit, ledger or logic RNG state")
	var oracle: RandomNumberGenerator = RandomNumberGenerator.new()
	oracle.seed = 193
	var expected_hits: int = 0
	for i in range(12):
		var roll: float = oracle.randf()
		assert_eq(plain["draws"][i], roll, "Exactly one logical draw per candidate")
		assert_eq(plain["trace"][i]["candidates"][0]["hit"], roll >= 0.5)
		var count: int = 1 if roll >= 0.5 else 0
		assert_eq(plain["trace"][i]["events"].size(), count)
		expected_hits += count
	assert_eq(plain["ledger"]["candidate_count"], 12)
	assert_eq(plain["ledger"]["hit_count"], expected_hits)


func test_fifo_rechecks_death_before_each_candidate():
	var shape: RefCounted = _shape()
	var clock: RefCounted = ClockScript.new(9)
	var later: Dictionary = _target("later")
	var calls: Array = []
	var resolver: Callable = func(target: Dictionary, _rng: RandomNumberGenerator) -> bool:
		calls.append(target["target_id"])
		later["alive"] = false
		return true
	assert_true(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 1}), _body(), clock, resolver))
	var result: Dictionary = shape.step([_target("z_first"), later, _target("a_last"), _target("already_dead", Vector2.ZERO, false)])
	assert_true(result["ok"])
	assert_eq(calls, ["z_first", "a_last"], "Do not sort by target_id or batch all death checks before FIFO resolution")
	assert_eq(result["events"].size(), 2)
	assert_eq(result["events"][0]["target_id"], "z_first")
	assert_eq(result["events"][1]["target_id"], "a_last")
	assert_eq(result["candidates"].size(), 2)
	assert_false(shape.snapshot_state()["targets"].has("later"))


func test_purge_expiry_and_outside_targets_are_silent():
	var clock: RefCounted = ClockScript.new(9)
	var body: RefCounted = _body()
	var shape: RefCounted = _shape()
	var calls: Array = []
	var resolver: Callable = func(_t: Dictionary, rng: RandomNumberGenerator) -> bool:
		calls.append(rng.randi())
		return true
	assert_true(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 10}), body, clock, resolver))
	var initial_rng: int = clock.rng_logic().state
	assert_eq(shape.step([_target("outside", Vector2(6, 0))])["candidates"].size(), 0)
	clock.tick()
	assert_eq(shape.step([_target("inside")])["events"].size(), 1)
	body.purge()
	clock.tick()
	var purged: Dictionary = shape.step([_target("new")], {"pulse": true})
	assert_true(purged["ok"])
	assert_eq(purged["events"].size(), 0)
	assert_eq(purged["candidates"].size(), 0)
	assert_eq(calls.size(), 1)
	assert_ne(clock.rng_logic().state, initial_rng)
	var expired: RefCounted = _shape()
	var short_body: RefCounted = BodyScript.create(BodyScript.CARRIER_INDEPENDENT, {"lifetime_ticks": 2}, 0)
	assert_true(expired.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 1}), short_body, clock, resolver))
	assert_eq(expired.step([_target("a")])["events"].size(), 0, "Expiry gates hits even before lifecycle step")
	assert_eq(calls.size(), 1)


func test_cfg_and_debug_snapshot_are_not_mutated():
	var cfg: Dictionary = _template({"shape": "sector", "radius": 5}, {"per_target_limit": 1})
	var original: Dictionary = cfg.duplicate(true)
	var shape: RefCounted = _shape()
	assert_true(shape.configure(cfg, _body(), ClockScript.new(9)))
	assert_eq(shape.step([_target("a")])["events"].size(), 1)
	assert_eq(cfg, original, "Default angle, ledgers and results never flow back to CFG")
	var view: Dictionary = shape.snapshot_state()
	view["targets"]["a"]["candidate_count"] = 999
	assert_eq(shape.snapshot_state()["targets"]["a"]["candidate_count"], 1)


func test_interval_is_not_reset_by_exit_or_reentry():
	var shape: RefCounted = _shape()
	var clock: RefCounted = ClockScript.new(9)
	assert_true(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 3, "rehit_interval_ticks": 3}), _body(), clock))
	assert_eq(shape.step([_target("a")])["events"].size(), 1)
	clock.tick()
	assert_eq(shape.step([_target("a", Vector2(6, 0))])["candidates"].size(), 0)
	clock.tick()
	assert_eq(shape.step([_target("a")])["candidates"].size(), 0)
	clock.tick()
	assert_eq(shape.step([_target("a")])["events"].size(), 1)


func test_fifo_max_hits_cap_stops_later_candidates_in_same_tick():
	var shape: RefCounted = _shape()
	var calls: Array = []
	var resolver: Callable = func(target: Dictionary, _rng: RandomNumberGenerator) -> bool:
		calls.append(target["target_id"])
		return true
	assert_true(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 1, "max_hits": 1}), _body(), ClockScript.new(9), resolver))
	var result: Dictionary = shape.step([_target("z"), _target("a")])
	assert_eq(result["candidates"].size(), 1)
	assert_eq(result["events"].size(), 1)
	assert_eq(result["events"][0]["type"], "hit")
	assert_eq(result["events"][0]["target_id"], "z")
	assert_eq(calls, ["z"])


func test_invalid_roster_is_rejected_before_any_rng_or_quota_is_spent():
	var shape: RefCounted = _shape()
	var clock: RefCounted = ClockScript.new(9)
	var rng_state: int = clock.rng_logic().state
	assert_true(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 1}), _body(), clock))
	var bad: Dictionary = shape.step([_target("good"), {"target_id": "bad", "position": Vector2.ZERO}])
	assert_false(bad["ok"])
	assert_eq(bad["candidates"].size(), 0)
	assert_eq(shape.snapshot_state()["candidate_count"], 0)
	assert_eq(clock.rng_logic().state, rng_state)
	assert_eq(shape.step([_target("good")])["events"].size(), 1, "Correcting input before a tick commits is safe")


func test_instant_body_hits_only_before_its_lifecycle_termination():
	var clock: RefCounted = ClockScript.new(9)
	var body: RefCounted = BodyScript.create(BodyScript.CARRIER_NONE, {"lifetime_ticks": 0}, 0)
	var shape: RefCounted = _shape()
	assert_true(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 1}), body, clock))
	assert_eq(shape.step([_target("a")])["events"].size(), 1)
	var lifecycle: Array = body.step(0)
	assert_eq(lifecycle.size(), 1)
	assert_eq(lifecycle[0]["type"], "vanish")
	clock.tick()
	assert_eq(shape.step([_target("b")])["events"].size(), 0)


func test_bad_resolver_fails_closed_without_free_retry():
	var shape: RefCounted = _shape()
	var clock: RefCounted = ClockScript.new(9)
	var calls: Array = []
	var invalid: Callable = func(_t: Dictionary, rng: RandomNumberGenerator) -> String:
		calls.append(rng.randi())
		return "not a boolean"
	assert_true(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 3, "rehit_interval_ticks": 1}), _body(), clock, invalid))
	var result: Dictionary = shape.step([_target("a")])
	assert_false(result["ok"])
	assert_eq(result["candidates"].size(), 1)
	assert_eq(result["events"].size(), 0)
	assert_eq(shape.snapshot_state()["candidate_count"], 1)
	assert_false(shape.step([_target("a")])["ok"])
	clock.tick()
	assert_false(shape.step([_target("a")])["ok"])
	assert_eq(calls.size(), 1)


func test_paused_tick_does_not_consume_another_candidate_or_rng():
	var clock: RefCounted = ClockScript.new(9)
	var shape: RefCounted = _shape()
	assert_true(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 3, "rehit_interval_ticks": 1}), _body(), clock))
	assert_eq(shape.step([_target("a")])["events"].size(), 1)
	clock.pause()
	assert_eq(clock.tick(), 0)
	assert_eq(shape.step([_target("a")], {"pulse": true})["candidates"].size(), 0)
	assert_eq(shape.snapshot_state()["candidate_count"], 1)
	clock.resume()
	clock.tick()
	assert_eq(shape.step([_target("a")])["events"].size(), 1)


func test_metadata_missing_is_an_explicit_configuration_failure():
	var shape: RefCounted = ShapeScript.new("res://data/__t043_missing_shape_meta__.json")
	assert_false(shape.last_error.is_empty(), "Missing metadata must not look like an empty supported-shape table")
	assert_false(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 1}), _body(), ClockScript.new(1)))
	assert_string_contains(shape.last_error, "__t043_missing_shape_meta__.json")


func test_malformed_metadata_fails_before_geometry_or_hit_access():
	var broken: Array = []
	var fields: Dictionary = ShapeScript.PROVISIONAL_META.duplicate(true)
	fields["geometry_fields"]["radius"] = null
	broken.append(fields)
	var arguments: Dictionary = ShapeScript.PROVISIONAL_META.duplicate(true)
	arguments["shapes"]["circle"]["arguments"] = ["not_registered"]
	broken.append(arguments)
	var roles: Dictionary = ShapeScript.PROVISIONAL_META.duplicate(true)
	roles["policy_roles"]["interval"] = "not_registered"
	broken.append(roles)
	var kernel: Dictionary = ShapeScript.PROVISIONAL_META.duplicate(true)
	kernel["shapes"]["circle"]["kernel"] = "not_implemented"
	broken.append(kernel)
	assert_eq(broken.size(), 4)
	for metadata in broken:
		var shape: RefCounted = ShapeScript.new(ShapeScript.META_PATH, metadata)
		assert_false(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 1}), _body(), ClockScript.new(1)))
		assert_false(shape.last_error.is_empty())


func test_shape_and_policy_field_bindings_follow_injected_metadata():
	var metadata: Dictionary = ShapeScript.PROVISIONAL_META.duplicate(true)
	metadata["shapes"] = {"round_test": {"kernel": "disk", "arguments": ["extent_test"]}}
	metadata["geometry_fields"] = {"kind_test": {"type": "string", "enum": ["round_test"]}, "extent_test": {"type": "number", "exclusiveMinimum": 0}}
	metadata["geometry_shape_field"] = "kind_test"
	metadata["hit_policy_fields"] = {"quota_test": {"type": "integer", "minimum": 1}, "gap_test": {"type": "integer", "minimum": 1}, "cap_test": {"type": "integer", "minimum": 1}}
	metadata["hit_policy_required"] = ["quota_test"]
	metadata["policy_roles"] = {"target_limit": "quota_test", "interval": "gap_test", "hit_limit": "cap_test"}
	var shape: RefCounted = ShapeScript.new(ShapeScript.META_PATH, metadata)
	assert_true(shape.configure(_template({"kind_test": "round_test", "extent_test": 5}, {"quota_test": 1, "cap_test": 1}), _body(), ClockScript.new(1)))
	assert_true(shape.contains_point(Vector2(3, 4)))
	var result: Dictionary = shape.step([_target("first"), _target("second")])
	assert_true(result["ok"])
	assert_eq(result["candidates"].size(), 1)
	assert_eq(result["events"].size(), 1)
	assert_eq(result["events"][0]["target_id"], "first")


func test_empty_injected_metadata_is_not_a_fallback():
	var shape: RefCounted = ShapeScript.new(ShapeScript.META_PATH, {})
	assert_false(shape.configure(_template({"shape": "circle", "radius": 5}, {"per_target_limit": 1}), _body(), ClockScript.new(1)))
	assert_false(shape.last_error.is_empty())

# ---- WorkBuddy 复核补测：生产元数据资产必须可用（与过渡表等价） ----

func test_production_metadata_asset_drives_all_four_shapes():
	var file: FileAccess = FileAccess.open(ShapeScript.META_PATH, FileAccess.READ)
	assert_not_null(file, "生产元数据必须存在: " + ShapeScript.META_PATH)
	var parser: JSON = JSON.new()
	assert_eq(parser.parse(file.get_as_text()), OK, parser.get_error_message())
	file.close()
	assert_true(parser.data is Dictionary)
	var meta: Dictionary = parser.data as Dictionary
	# 真源口径：四形状、必填 per_target_limit、角色绑定、hit 事件名
	assert_eq(meta["geometry_shape_field"], "shape")
	assert_eq(meta["shapes"].keys(), ["circle", "sector", "line", "rectangle"])
	assert_eq(meta["hit_policy_required"], ["per_target_limit"])
	assert_eq(meta["policy_roles"], {"target_limit": "per_target_limit", "interval": "rehit_interval_ticks", "hit_limit": "max_hits"})
	assert_eq(meta["hit_event"], "hit")
	assert_eq(meta["geometry_fields"]["sector_angle"]["maximum"], 100)
	assert_eq(meta["hit_policy_fields"]["per_target_limit"]["minimum"], 1)
	# 生产素材必须能驱动四形状实际判定，不只是能解析
	var cases: Array = [
		{"shape": "circle", "radius": 5},
		{"shape": "sector", "radius": 5, "sector_angle": 90},
		{"shape": "line", "length": 6, "width": 2},
		{"shape": "rectangle", "length": 6, "width": 4},
	]
	for geometry in cases:
		var shape: RefCounted = ShapeScript.new(ShapeScript.META_PATH, null)
		assert_true(shape.configure(_template(geometry, {"per_target_limit": 1}), _body(), ClockScript.new(1)), shape.last_error)
		assert_true(shape.contains_point(Vector2.ZERO), str(geometry))
