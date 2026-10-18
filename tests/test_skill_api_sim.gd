extends GutTest

const ApiScript = preload("res://skill_core/api/skill_api.gd")
const RunnerScript = preload("res://skill_core/runtime/preview_runner.gd")
const BodyScript = preload("res://skill_core/runtime/effect_body.gd")
const CodecScript = preload("res://skill_core/schema/cfg_codec.gd")
const DiffScript = preload("res://skill_core/runtime/run_diff.gd")


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _cfg() -> Dictionary:
	var catalog: Array = _json("res://data/bricks/brick_catalog.json")
	var entry: Dictionary = {}
	for candidate in catalog:
		if candidate["carrier"] == BodyScript.CARRIER_INDEPENDENT:
			entry = candidate
			break
	var meta: Dictionary = _json("res://data/params_meta.json")
	var template: Dictionary = {"template_id": "t077_root", "carrier": entry["carrier"],
		"lifetime_ticks": 4, "targeting": {"target_group": "enemy"},
		"motion": {"mode": "straight", "speed": 1.25},
		"geometry": {"shape": "circle", "radius": 0.125},
		"hit_policy": {"per_target_limit": 1, "max_hits": 1},
		"parts": [{"part_index": 0, "type": meta["enums"]["part_type"][0], "amount": 2.5}],
		"derivations": []}
	return {"schema_version": "0.1", "skill_id": "mage_active_t077",
		"meta": {"role": "mage", "category": "active", "short_name": "t077",
			"name": "T077", "version": "1", "author": "test"},
		"bricks": [{"brick_id": entry["brick_id"], "name": entry["name"], "tagline": "T077",
			"carrier": entry["carrier"], "summary": "Lifecycle fixture",
			"default_cfg": {"template_id": "t077_root", "shot_id": "t077_shot"},
			"author_params": [], "locked_params": {}, "relic_params": {},
			"presentation": [], "player_text": ["Lifecycle fixture"], "status": entry["status"]}],
		"params": {"carrier": entry["carrier"], "lifetime_ticks": 4, "templates": [template],
			"max_generation": 1, "cast_budget": 4, "safety": {"max_chain_depth": 3}},
		"presentation": {"fx": {}, "sfx": {"max_concurrency": 0}, "anim": {},
			"trail": {"carrier": entry["carrier"]}, "camera": {}, "damage_number": {}, "status_icon": {}},
		"runtime_hints": {}}


func _created(api: RefCounted, cfg: Dictionary, seed: int) -> Dictionary:
	var result: Dictionary = api.create_sim(cfg, seed)
	print("T077 create_sim: ", result)
	assert_true(result["ok"], str(result))
	return result


func test_create_sim_same_seed_real_entity_and_no_cfg_writeback() -> void:
	var api: RefCounted = ApiScript.new()
	var cfg: Dictionary = _cfg()
	var before: Dictionary = cfg.duplicate(true)
	var left: Dictionary = _created(api, cfg, 17)
	if not left["ok"]:
		return
	var right: Dictionary = _created(api, cfg, 17)
	if not right["ok"]:
		return
	assert_false(left["fingerprint"].is_empty())
	assert_eq(left["fingerprint"], right["fingerprint"])
	assert_eq(left["diagnostics"], [])
	assert_ne(left["sim"]["runner"], right["sim"]["runner"])
	var snapshot: Dictionary = left["sim"]["runner"].snapshot_state()
	assert_eq(snapshot["entities"].size(), 1)
	assert_eq(snapshot["clock"]["tick"], 0)
	assert_eq(snapshot["notices"].size(), 1, "API allocated suggestion is observable, never saved")
	assert_eq(cfg, before)


func test_step_sim_chunked_matches_bulk_with_real_expiration() -> void:
	var api: RefCounted = ApiScript.new()
	var chunked: Dictionary = _created(api, _cfg(), 17)
	if not chunked["ok"]:
		return
	var bulk: Dictionary = _created(api, _cfg(), 17)
	if not bulk["ok"]:
		return
	var step: Dictionary = api.step_sim(chunked["sim"], 2)
	assert_true(step["ok"], str(step))
	if not step["ok"]:
		return
	assert_eq(step["snapshot"]["clock"]["tick"], 2)
	step = api.step_sim(chunked["sim"], 3)
	var whole: Dictionary = api.step_sim(bulk["sim"], 5)
	assert_true(step["ok"], str(step))
	assert_true(whole["ok"], str(whole))
	if not step["ok"] or not whole["ok"]:
		return
	assert_eq(step["diagnostics"], [])
	assert_eq(step["snapshot"], whole["snapshot"])
	assert_eq(whole["snapshot"]["clock"]["tick"], 5)
	assert_eq(whole["snapshot"]["entities"].size(), 1)
	assert_eq(whole["snapshot"]["events"].size(), 1, "Actual lifecycle event, not empty-trace equality")
	assert_eq(whole["snapshot"]["active_count"], 0)


func test_different_seeds_have_same_logic_without_random_consumption() -> void:
	# No targets or probabilistic derivations: this CFG has no logic RNG draws.
	var api: RefCounted = ApiScript.new()
	var left: Dictionary = _created(api, _cfg(), 17)
	if not left["ok"]:
		return
	var right: Dictionary = _created(api, _cfg(), 29)
	if not right["ok"]:
		return
	var initial_left: Dictionary = left["sim"]["runner"].snapshot_state()["clock"]["logic_rng"].duplicate(true)
	var initial_right: Dictionary = right["sim"]["runner"].snapshot_state()["clock"]["logic_rng"].duplicate(true)
	assert_ne(initial_left, initial_right, "Seed is forwarded, not replaced internally")
	var a: Dictionary = api.step_sim(left["sim"], 5)
	var b: Dictionary = api.step_sim(right["sim"], 5)
	assert_true(a["ok"], str(a))
	assert_true(b["ok"], str(b))
	if not a["ok"] or not b["ok"]:
		return
	assert_eq(a["snapshot"]["clock"]["logic_rng"], initial_left)
	assert_eq(b["snapshot"]["clock"]["logic_rng"], initial_right)
	assert_eq(a["snapshot"]["entities"].size(), 1)
	assert_eq(a["snapshot"]["events"].size(), 1)
	assert_eq(a["snapshot"]["events"], b["snapshot"]["events"])
	assert_eq(a["snapshot"]["entities"], b["snapshot"]["entities"])
	assert_eq(a["snapshot"]["fingerprint"], b["snapshot"]["fingerprint"])


func _unsupported_part(_part: Dictionary, _record: Dictionary, _target: Dictionary) -> bool:
	return false


func _preview_options(cfg: Dictionary, seed: int) -> Dictionary:
	# Independent fixture construction: do not read options out of the API handle.
	var types: Dictionary = _json("res://data/params_meta.json")
	var handlers: Dictionary = {}
	for kind in types["enums"]["part_type"]:
		handlers[kind] = _unsupported_part
	var registration: Dictionary = cfg["bricks"][0]["default_cfg"]
	var id: String = registration["template_id"]
	return {"seed": seed, "roots": [{"template_id": id, "shot_id": registration["shot_id"],
		"instance_id": "api:root:0"}], "handlers": handlers, "template_families": {id: id},
		"derivation_bindings": {}, "targets": []}


func test_persisted_formal_and_memory_preview_full_trace_first_difference() -> void:
	var cfg: Dictionary = _cfg()
	var before: Dictionary = cfg.duplicate(true)
	var directory_error: int = DirAccess.make_dir_recursive_absolute("user://t077/")
	assert_eq(directory_error, OK)
	if directory_error != OK:
		return
	var path: String = "user://t077/t077_case.skillcfg"
	var saved: Dictionary = CodecScript.save_cfg(path, cfg)
	assert_true(saved["ok"], str(saved))
	if not saved["ok"]:
		return
	var loaded: Dictionary = CodecScript.load_cfg(path)
	assert_true(loaded["ok"], str(loaded))
	if not loaded["ok"]:
		return
	# U-27 is a codec-layer ruling: params retains unknown nested keys on roundtrip.
	# The schema layer rejects them (V-019 unregistered key), so create_sim below
	# must run on the schema-clean cfg, never on the retention probe.
	var persist_cfg: Dictionary = cfg.duplicate(true)
	persist_cfg["params"]["unknown_nested"] = {"marker": "retained", "values": [3, 5]}
	var saved_probe: Dictionary = CodecScript.save_cfg(path, persist_cfg)
	assert_true(saved_probe["ok"], str(saved_probe))
	if not saved_probe["ok"]:
		return
	var loaded_probe: Dictionary = CodecScript.load_cfg(path)
	assert_true(loaded_probe["ok"], str(loaded_probe))
	if not loaded_probe["ok"]:
		return
	assert_eq(loaded_probe["data"].size(), 7)
	assert_eq(loaded_probe["data"], persist_cfg)
	assert_eq(loaded_probe["data"]["params"]["unknown_nested"], persist_cfg["params"]["unknown_nested"])
	var api: RefCounted = ApiScript.new()
	var formal: Dictionary = _created(api, loaded["data"], 17)
	if not formal["ok"]:
		return
	var memory: Dictionary = _created(api, cfg, 17)
	if not memory["ok"]:
		return
	assert_eq(formal["fingerprint"], memory["fingerprint"])
	var preview: RefCounted = RunnerScript.new()
	var options: Dictionary = _preview_options(cfg, 17)
	assert_false(options.has("project_config"))
	var started: Dictionary = preview.start(cfg, options)
	print("T077 direct PreviewRunner.start: ", started)
	assert_true(started["ok"], str(started))
	if not started["ok"]:
		return
	var diff: RefCounted = DiffScript.new()
	var configured: Dictionary = diff.configure({"limits": {"max_trace_ticks": 6}})
	assert_true(configured["ok"], str(configured))
	if not configured["ok"]:
		return
	var a: Dictionary = diff.capture(formal["sim"]["runner"], 6)
	var b: Dictionary = diff.capture(preview, 6)
	assert_true(a["ok"], str(a))
	assert_true(b["ok"], str(b))
	if not a["ok"] or not b["ok"]:
		return
	assert_eq(a["trace"].size(), 6)
	assert_eq(b["trace"].size(), 6)
	assert_false(a["truncated"])
	assert_false(b["truncated"])
	assert_eq(a["trace"][0]["entities"].size(), 1)
	assert_eq(a["trace"][5]["events"].size(), 1)
	assert_eq(b["trace"][5]["events"].size(), 1)
	var compared: Dictionary = diff.compare(a["trace"], b["trace"])
	print("T077 first difference result: ", compared)
	assert_true(compared["ok"], str(compared))
	assert_true(compared["equal"], "First difference: " + str(compared))
	assert_eq(compared["first_diff_index"], -1, str(compared))
	assert_eq(compared["path"], "", str(compared))
	assert_eq(cfg, before, "Neither entry may write runtime state to author CFG")


func _assert_rejected(result: Dictionary, path: String = "") -> void:
	assert_false(result["ok"], str(result))
	assert_true(result.has("diagnostics"), str(result))
	assert_true(result["diagnostics"] is Array, str(result))
	if not path.is_empty():
		assert_eq(result["path"], path, str(result))


func test_invalid_cfg_and_missing_root_registration_are_diagnostic_failures() -> void:
	var api: RefCounted = ApiScript.new()
	_assert_rejected(api.create_sim({}, 0), "cfg")
	var malformed: Dictionary = _cfg()
	malformed["params"]["templates"] = "not_an_array"
	_assert_rejected(api.create_sim(malformed, 0), "cfg")
	var missing: Dictionary = _cfg()
	missing["bricks"][0]["default_cfg"].erase("shot_id")
	var result: Dictionary = api.create_sim(missing, 0)
	_assert_rejected(result, "bricks[0].default_cfg")
	assert_gt(result["diagnostics"].size(), 0)
	var no_roots: Dictionary = _cfg()
	no_roots["bricks"] = []
	_assert_rejected(api.create_sim(no_roots, 0), "bricks")


func test_invalid_handles_ticks_and_stopped_runner_do_not_throw() -> void:
	var api: RefCounted = ApiScript.new()
	for handle in [null, {}, [], 1, "bad", {"runner": null}, {"runner": {}}, {"runner": RefCounted.new()}]:
		_assert_rejected(api.step_sim(handle, 1))
	var created: Dictionary = _created(api, _cfg(), 17)
	if not created["ok"]:
		return
	for ticks in [0, -1]:
		_assert_rejected(api.step_sim(created["sim"], ticks), "ticks")
	assert_eq(created["sim"]["runner"].snapshot_state()["clock"]["tick"], 0)
	var stopped: Dictionary = created["sim"]["runner"].stop()
	assert_true(stopped["ok"])
	_assert_rejected(api.step_sim(created["sim"], 1), "advance_ticks")


func test_catalog_classification_and_instance_allocation_are_not_brick_id_branches() -> void:
	var api: RefCounted = ApiScript.new()
	var catalog: Array = _json("res://data/bricks/brick_catalog.json")
	var cfg: Dictionary = _cfg()
	var replacements: Array = []
	for entry in catalog:
		if entry["carrier"] == BodyScript.CARRIER_INDEPENDENT:
			replacements.append(entry)
	assert_gt(replacements.size(), 1)
	if replacements.size() < 2:
		return
	cfg["bricks"][0]["brick_id"] = replacements[1]["brick_id"]
	var second: Dictionary = cfg["bricks"][0].duplicate(true)
	cfg["bricks"].append(second)
	var created: Dictionary = _created(api, cfg, 17)
	if not created["ok"]:
		return
	var state: Dictionary = created["sim"]["runner"].snapshot_state()
	assert_eq(state["entities"].size(), 2)
	assert_eq(state["notices"].size(), 2)
	assert_ne(state["notices"][0]["assigned"], state["notices"][1]["assigned"])
	assert_ne(state["notices"][0]["suggested"], state["notices"][1]["suggested"])
	cfg["bricks"][0]["brick_id"] = "not_a_catalog_brick"
	_assert_rejected(api.create_sim(cfg, 17), "bricks[0].brick_id")


func test_runner_start_failure_is_returned_without_losing_details() -> void:
	var cfg: Dictionary = _cfg()
	cfg["params"]["templates"][0]["motion"] = {"mode": "orbit"}
	var runner: RefCounted = RunnerScript.new()
	var expected: Dictionary = runner.start(cfg, _preview_options(cfg, 17))
	print("T077 expected direct start failure: ", expected)
	assert_false(expected["ok"], str(expected))
	assert_eq(expected["path"], "params.templates[0].motion.mode", str(expected))
	if expected["path"] != "params.templates[0].motion.mode":
		return
	var actual: Dictionary = ApiScript.new().create_sim(cfg, 17)
	_assert_rejected(actual)
	assert_eq(actual["path"], expected["path"])
	assert_eq(actual["error"], expected["error"])
	assert_eq(actual["diagnostics"], expected["diagnostics"])
