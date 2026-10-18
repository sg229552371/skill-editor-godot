extends GutTest

const Runner = preload("res://skill_core/runtime/preview_runner.gd")
const Codec = preload("res://skill_core/schema/cfg_codec.gd")
const Yaml = preload("res://skill_core/schema/yaml_lite.gd")


func _template(id: String) -> Dictionary:
	return {"template_id": id, "carrier": "independent", "lifetime_ticks": 12,
		"targeting": {"target_group": "enemy"},
		"motion": {"mode": "straight", "speed": 1.0},
		"geometry": {"shape": "circle", "radius": 0.01},
		"hit_policy": {"per_target_limit": 1, "max_hits": 1},
		"parts": [{"part_index": 0, "type": "physical", "amount": 10.0}],
		"derivations": []}


func _cfg() -> Dictionary:
	var root: Dictionary = _template("root_recipe")
	root["derivations"] = [{"trigger_id": "split_once", "event": "hit", "reasons": [],
		"child_template": "child_recipe", "count": 5}]
	var child: Dictionary = _template("child_recipe")
	child["lifetime_ticks"] = 4
	return {"schema_version": "0.1", "skill_id": "mage_active_preview",
		"meta": {"role": "mage", "category": "active", "short_name": "preview", "name": "Preview",
			"version": "1", "author": "test"}, "bricks": [],
		"params": {"carrier": "independent", "lifetime_ticks": 12, "templates": [root, child],
			"cast_budget": 3, "max_generation": 2, "split_budget": 1, "chain_remaining": 0,
			"safety": {"max_chain_depth": 3}},
		"presentation": {"fx": {}, "sfx": {"max_concurrency": 0}, "anim": {},
			"trail": {"carrier": "independent"}, "camera": {}, "damage_number": {}, "status_icon": {}},
		"runtime_hints": {}}


func _target(id: String, x: float) -> Dictionary:
	return {"target_id": id, "position": Vector2(x, 0), "alive": true, "hp": 100.0,
		"invulnerable": false, "evade": {}, "immune": {}}


func _damage(part: Dictionary, record: Dictionary, target: Dictionary) -> bool:
	# An actual sandbox HP transaction, not an always-successful settlement stub.
	if not ["physical", "fire"].has(part["type"]):
		return false
	target["hp"] -= record["value"]
	target["alive"] = target["hp"] > 0.0
	return true


func _options() -> Dictionary:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/params_meta.json"))
	var handlers: Dictionary = {}
	for kind in meta["enums"]["part_type"]:
		handlers[kind] = _damage
	return {"seed": 17, "handlers": handlers,
		"roots": [{"template_id": "root_recipe", "shot_id": "shot_a"}],
		"template_families": {"root_recipe": "split_family", "child_recipe": "split_family"},
		"derivation_bindings": {"root_recipe": {"split_once": {"budgets": ["split_budget"], "reject_visited": false}}},
		"motion_inputs": {}, "targets": [_target("first", 5.0), _target("second", 7.0)]}


func _signature(events: Array) -> Array:
	var result: Array = []
	for event in events:
		result.append([event["type"], event["tick"], event["body_id"], event.get("target_id", event.get("reason", ""))])
	return result


func test_complete_flight_settlement_split_and_budget_chain():
	var runner: RefCounted = Runner.new()
	var cfg: Dictionary = _cfg()
	var before: Dictionary = cfg.duplicate(true)
	assert_true(runner.start(cfg, _options())["ok"], runner.last_error)
	assert_true(runner.advance_ticks(4)["ok"], runner.last_error)
	assert_eq(runner.snapshot_state()["events"].size(), 0, "Flight must actually take time")
	assert_eq(runner.snapshot_state()["entities"]["preview:0:root:0"]["position"], Vector2(4, 0))
	assert_true(runner.advance_ticks(14)["ok"], runner.last_error)
	var state: Dictionary = runner.snapshot_state()
	assert_eq(state["entities"].size(), 3, "Root + two admitted children; three requested children clipped")
	assert_eq(state["active_count"], 0)
	assert_eq(_signature(state["events"]), [
		["hit", 5, "preview:0:root:0", "first"],
		["hit", 7, "preview:0:derive:1", "second"],
		["vanish", 10, "preview:0:derive:1", "expired"],
		["vanish", 10, "preview:0:derive:2", "expired"],
		["vanish", 12, "preview:0:root:0", "expired"]])
	assert_eq(state["records"].size(), 2, "One settlement per actual hit; no suppressed-sibling settlement")
	assert_eq(state["targets"][0]["hp"], 90.0)
	assert_eq(state["targets"][1]["hp"], 90.0)
	assert_eq(state["derive"]["cast_remaining"], 0)
	assert_eq(cfg, before, "Runtime identities and results must not leak into CFG")


func test_snapshot_is_deep_and_fingerprint_covers_cfg_not_runtime_results():
	var cfg: Dictionary = _cfg()
	var runner: RefCounted = Runner.new()
	var options: Dictionary = _options()
	assert_true(runner.start(cfg, options)["ok"], runner.last_error)
	var fingerprint: String = runner.snapshot_state()["fingerprint"]
	cfg["params"]["templates"][0]["parts"][0]["amount"] = 999.0
	cfg["params"]["templates"][1]["parts"][0]["amount"] = 777.0
	options["targets"][0]["position"] = Vector2(1000, 0)
	options["template_families"].clear()
	assert_true(runner.advance_ticks(8)["ok"], runner.last_error)
	var state: Dictionary = runner.snapshot_state()
	assert_eq(state["records"].size(), 2)
	if state["records"].size() != 2:
		return
	assert_eq(state["records"][0]["parts"][0]["value"], 10.0)
	assert_eq(state["records"][1]["parts"][0]["value"], 10.0)
	assert_eq(state["fingerprint"], fingerprint)
	state["targets"][0]["hp"] = -1.0
	state["events"].clear()
	assert_eq(runner.snapshot_state()["events"].size(), 2, "Query snapshots cannot mutate the simulation")
	assert_eq(runner.snapshot_state()["targets"][0]["hp"], 90.0)
	var next: RefCounted = Runner.new()
	assert_true(next.start(cfg, _options())["ok"], next.last_error)
	assert_ne(next.snapshot_state()["fingerprint"], fingerprint)


func test_instance_suggestions_never_allocate_or_duplicate_internal_ids():
	var options: Dictionary = _options()
	options["roots"][0]["instance_id"] = "preview:0:derive:1"
	var runner: RefCounted = Runner.new()
	assert_true(runner.start(_cfg(), options)["ok"], runner.last_error)
	assert_true(runner.advance_ticks(6)["ok"], runner.last_error)
	var state: Dictionary = runner.snapshot_state()
	var ids: Dictionary = {}
	var count: int = 0
	for entity in state["entities"].values():
		assert_false(ids.has(entity["body_id"]))
		ids[entity["body_id"]] = true
		count += 1
	assert_eq(count, 3, "A nonempty actual allocation, not an empty uniqueness assertion")
	assert_eq(state["notices"].size(), 1)
	assert_eq(state["notices"][0]["assigned"], "preview:0:root:0")
	assert_eq(state["notices"][0]["suggested"], "preview:0:derive:1")
	assert_eq(state["derive"]["instances"]["preview:0:derive:1"]["seq"], 1)
	assert_eq(state["derive"]["instances"]["preview:0:derive:2"]["seq"], 2)
	var malformed: Dictionary = _options()
	malformed["roots"][0]["instance_id"] = ["not", "an", "id"]
	var other: RefCounted = Runner.new()
	assert_true(other.start(_cfg(), malformed)["ok"], other.last_error)
	assert_false(other.snapshot_state()["notices"][0]["valid_suggestion"])
	assert_eq(other.snapshot_state()["notices"][0]["assigned"], "preview:0:root:0")


func test_split_budget_has_one_aggregate_drop_and_no_phantom_children():
	var runner: RefCounted = Runner.new()
	assert_true(runner.start(_cfg(), _options())["ok"], runner.last_error)
	assert_true(runner.advance_ticks(5)["ok"], runner.last_error)
	var state: Dictionary = runner.snapshot_state()
	var drops: Array = []
	var created: Array = []
	for record in state["derive"]["records"]:
		if record["kind"] == "budget_drop":
			drops.append(record)
		if record["kind"] == "created":
			created.append(record)
	assert_eq(created.size(), 2)
	assert_eq(drops.size(), 1, "T-045 aggregates uncreated siblings in ONE record")
	if drops.size() != 1:
		return
	assert_eq(drops[0]["requested"], 3)
	assert_eq(drops[0]["detail"], "cast_budget")
	assert_eq(drops[0]["type"], "debug_record")
	assert_eq(state["entities"].size(), 3)
	assert_eq(state["events"].size(), 1, "Budget denials are not vanish events")
	assert_eq(state["budget"]["drops"].size(), 0, "Do not fabricate T-048 drops for T-045 clipping")


func test_root_budget_keeps_t048_per_rejection_records_separate_from_events():
	var options: Dictionary = _options()
	for _index in range(4):
		options["roots"].append({"template_id": "root_recipe", "shot_id": "shot_a"})
	var runner: RefCounted = Runner.new()
	assert_true(runner.start(_cfg(), options)["ok"], runner.last_error)
	var state: Dictionary = runner.snapshot_state()
	assert_eq(state["entities"].size(), 3)
	assert_eq(state["budget"]["drops"].size(), 2, "T-048: one drop per rejected new root")
	assert_eq(state["budget"]["debug"].size(), 2)
	assert_eq(state["budget"]["occupied"], 3)
	assert_eq(state["events"].size(), 0)
	assert_eq(state["records"].size(), 0)
	assert_false(state["entities"].has("preview:0:root:3"))
	assert_false(state["entities"].has("preview:0:root:4"))


func _config(rate: int) -> Dictionary:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/project_config.json"))
	config["tick_rate"] = rate
	return config


func test_tick_rate_drives_resolved_lob_flight_seconds_not_a_hardcoded_frequency():
	var cfg: Dictionary = _cfg()
	var root: Dictionary = cfg["params"]["templates"][0]
	root["motion"] = {"mode": "lob"}
	root["lifetime_ticks"] = 120
	root["derivations"] = []
	var ticks: Array = []
	for rate in [60, 30]:
		var options: Dictionary = _options()
		options["project_config"] = _config(rate)
		options["targets"] = [_target("landing", 10.0)]
		options["motion_inputs"] = {"root_recipe": {"flight_seconds": 0.5, "target": Vector2(10, 0)}}
		var runner: RefCounted = Runner.new()
		assert_true(runner.start(cfg, options)["ok"], runner.last_error)
		assert_true(runner.advance_seconds(1.0)["ok"], runner.last_error)
		var state: Dictionary = runner.snapshot_state()
		assert_eq(state["clock"]["tick"], rate)
		assert_eq(state["records"].size(), 1)
		assert_eq(state["events"].size(), 2, "Landing hit precedes landed vanish at the same tick")
		if state["records"].size() != 1 or state["events"].size() != 2:
			return
		ticks.append(state["records"][0]["tick"])
		assert_eq(state["targets"][0]["hp"], 90.0)
		assert_eq(state["events"][0]["type"], "hit")
		assert_eq(state["events"][1]["reason"], "landed")
		assert_eq(state["events"][0]["tick"], state["events"][1]["tick"])
	assert_eq(ticks, [30, 15], "Same CFG + same 0.5s host flight input at two project frequencies")


func test_missing_frequency_and_provisional_limits_fail_without_defaults():
	var options: Dictionary = _options()
	options["project_config"] = _config(30)
	options["project_config"].erase("tick_rate")
	var runner: RefCounted = Runner.new()
	var result: Dictionary = runner.start(_cfg(), options)
	assert_false(result["ok"])
	assert_eq(result["path"], "project_config.tick_rate")
	assert_false(runner.snapshot_state()["running"])
	assert_eq(runner.snapshot_state()["entities"].size(), 0)
	options["project_config"] = _config(30)
	options["project_config"]["project_limits"]["hard_caps"].erase("cast_budget")
	result = runner.start(_cfg(), options)
	assert_false(result["ok"], "U-16 provisional cap must be injected, never inherited from sample data")
	assert_true(result["error"].contains("cast_budget"))
	assert_false(runner.snapshot_state()["running"])


func test_missing_cfg_paths_fail_before_any_entity_or_runtime_state():
	for path in ["params", "presentation"]:
		var cfg: Dictionary = _cfg()
		cfg.erase(path)
		var runner: RefCounted = Runner.new()
		var result: Dictionary = runner.start(cfg, _options())
		assert_false(result["ok"])
		assert_gt(result["diagnostics"].size(), 0)
		var found: bool = false
		for diagnostic in result["diagnostics"]:
			if diagnostic.path == path:
				found = true
		assert_true(found, "Must name the actual missing path: " + path)
		assert_false(runner.snapshot_state()["running"])
		assert_eq(runner.snapshot_state()["entities"].size(), 0)
	var cfg: Dictionary = _cfg()
	cfg["params"]["templates"][0].erase("parts")
	var runner: RefCounted = Runner.new()
	var result: Dictionary = runner.start(cfg, _options())
	assert_false(result["ok"])
	var found: bool = false
	for diagnostic in result["diagnostics"]:
		if diagnostic.path == "params.templates[0].parts":
			found = true
	assert_true(found, "Nested structure uses the shared Schema, not a runner-only schema")
	assert_false(runner.snapshot_state()["running"])


func test_same_seed_replays_and_presentation_rng_does_not_touch_logic():
	var left: RefCounted = Runner.new()
	var right: RefCounted = Runner.new()
	var options: Dictionary = _options()
	options["targets"][0]["evade"]["physical"] = 0.5
	assert_true(left.start(_cfg(), options)["ok"], left.last_error)
	assert_true(right.start(_cfg(), options)["ok"], right.last_error)
	var initial_rng: int = left.snapshot_state()["clock"]["logic_rng"]["state"]
	for _index in range(18):
		for _draw in range(3):
			left.presentation_random()
		assert_true(left.advance_ticks()["ok"], left.last_error)
		assert_true(right.advance_ticks()["ok"], right.last_error)
		assert_eq(left.snapshot_state()["events"], right.snapshot_state()["events"])
		assert_eq(left.snapshot_state()["records"], right.snapshot_state()["records"])
		assert_eq(left.snapshot_state()["targets"], right.snapshot_state()["targets"])
	assert_gt(left.snapshot_state()["events"].size(), 0, "At least actual lifecycle events even if first contact evades")
	assert_ne(left.snapshot_state()["clock"]["logic_rng"]["state"], initial_rng, "This case must actually consume logic randomness")
	assert_eq(left.snapshot_state()["clock"]["logic_rng"], right.snapshot_state()["clock"]["logic_rng"])
	assert_ne(left.snapshot_state()["clock"]["presentation_rng"], right.snapshot_state()["clock"]["presentation_rng"])


func test_codec_yaml_roundtrip_and_arbitrary_ids_use_the_same_cfg_structure():
	var cfg: Dictionary = _cfg()
	cfg["skill_id"] = "other_active_arbitrary"
	cfg["params"]["templates"][0]["template_id"] = "renamed_primary"
	cfg["params"]["templates"][1]["template_id"] = "renamed_secondary"
	cfg["params"]["templates"][0]["derivations"][0]["child_template"] = "renamed_secondary"
	var parsed: Dictionary = Yaml.parse(Yaml.dump(cfg))
	assert_true(parsed["ok"], str(parsed))
	if not parsed["ok"]:
		return
	assert_eq(Codec.validate_structure(parsed["data"]).size(), 0)
	var options: Dictionary = _options()
	options["roots"][0]["template_id"] = "renamed_primary"
	options["template_families"] = {"renamed_primary": "family_x", "renamed_secondary": "family_x"}
	options["derivation_bindings"] = {"renamed_primary": {"split_once": {"budgets": ["split_budget"], "reject_visited": false}}}
	var runner: RefCounted = Runner.new()
	assert_true(runner.start(parsed["data"], options)["ok"], runner.last_error)
	assert_true(runner.advance_ticks(18)["ok"], runner.last_error)
	assert_eq(runner.snapshot_state()["entities"].size(), 3)
	assert_eq(runner.snapshot_state()["events"].size(), 5)
	assert_eq(runner.snapshot_state()["records"].size(), 2)


func test_second_registered_part_type_uses_injected_handler_not_runner_branches():
	var cfg: Dictionary = _cfg()
	cfg["params"]["templates"][0]["parts"][0]["type"] = "fire"
	var runner: RefCounted = Runner.new()
	assert_true(runner.start(cfg, _options())["ok"], runner.last_error)
	assert_true(runner.advance_ticks(5)["ok"], runner.last_error)
	var records: Array = runner.snapshot_state()["records"]
	assert_eq(records.size(), 1)
	if records.size() != 1:
		return
	assert_eq(records[0]["parts"][0]["type"], "fire")
	assert_eq(records[0]["parts"][0]["value"], 10.0)
	assert_eq(runner.snapshot_state()["targets"][0]["hp"], 90.0)


func test_missing_adapter_and_unresolved_routing_are_explicit_failures():
	var options: Dictionary = _options()
	options["handlers"].clear()
	var runner: RefCounted = Runner.new()
	assert_false(runner.start(_cfg(), options)["ok"])
	assert_true(runner.last_error.contains("adapter"))
	assert_false(runner.snapshot_state()["running"])
	options = _options()
	options["derivation_bindings"].clear()
	assert_false(runner.start(_cfg(), options)["ok"])
	assert_true(runner.last_error.contains("binding"))
	assert_false(runner.snapshot_state()["running"])


func test_stop_is_silent_and_restart_allocates_fresh_internal_ids():
	var runner: RefCounted = Runner.new()
	assert_true(runner.start(_cfg(), _options())["ok"], runner.last_error)
	assert_true(runner.advance_ticks(5)["ok"], runner.last_error)
	var events: Array = runner.snapshot_state()["events"]
	assert_eq(events.size(), 1)
	assert_true(runner.stop()["ok"])
	assert_eq(runner.snapshot_state()["events"], events)
	assert_eq(runner.snapshot_state()["active_count"], 0)
	assert_false(runner.snapshot_state()["running"])
	assert_true(runner.start(_cfg(), _options())["ok"], runner.last_error)
	assert_true(runner.snapshot_state()["entities"].has("preview:1:root:1"))
	assert_false(runner.snapshot_state()["entities"].has("preview:0:root:0"))

