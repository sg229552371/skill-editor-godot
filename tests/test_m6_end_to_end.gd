extends GutTest

const ApiScript = preload("res://skill_core/api/skill_api.gd")
const BodyScript = preload("res://skill_core/runtime/effect_body.gd")
const CodecScript = preload("res://skill_core/schema/cfg_codec.gd")
const RunnerScript = preload("res://skill_core/runtime/preview_runner.gd")
const RunDiffScript = preload("res://skill_core/runtime/run_diff.gd")


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _cfg() -> Dictionary:
	var catalog: Array = _json("res://data/bricks/brick_catalog.json")
	var entry: Dictionary = {}
	for candidate in catalog:
		if candidate["carrier"] == BodyScript.CARRIER_INDEPENDENT:
			entry = candidate
			break
	var metadata: Dictionary = _json("res://data/params_meta.json")
	var part_type: String = metadata["enums"]["part_type"][0]
	var template: Dictionary = {"template_id": "t078_root", "carrier": entry["carrier"],
		"lifetime_ticks": 4, "targeting": {"target_group": "enemy"},
		"motion": {"mode": "straight", "speed": 1.25},
		"geometry": {"shape": "circle", "radius": 0.125},
		"hit_policy": {"per_target_limit": 1, "max_hits": 1},
		"parts": [{"part_index": 0, "type": part_type, "amount": 2.5}],
		"derivations": []}
	var brick: Dictionary = {"brick_id": entry["brick_id"], "name": entry["name"],
		"tagline": "T078", "carrier": entry["carrier"], "summary": "M6 host input card",
		"default_cfg": {"template_id": "t078_root", "shot_id": "t078_shot"},
		"author_params": [], "locked_params": {}, "relic_params": {},
		"presentation": [], "player_text": ["M6 host input card"], "status": entry["status"]}
	return {"schema_version": "0.1", "skill_id": "mage_active_t078",
		"meta": {"role": "mage", "category": "active", "short_name": "t078",
			"name": "T078", "version": "1", "author": "test"},
		"bricks": [brick, brick.duplicate(true)],
		"params": {"carrier": entry["carrier"], "lifetime_ticks": 4, "templates": [template],
			"max_generation": 1, "cast_budget": 1, "safety": {"max_chain_depth": 3}},
		"presentation": {"fx": {}, "sfx": {"max_concurrency": 0}, "anim": {},
			"trail": {"carrier": entry["carrier"]}, "camera": {}, "damage_number": {}, "status_icon": {}},
		"runtime_hints": {}}


func _unsupported_part(_part: Dictionary, _record: Dictionary, _target: Dictionary) -> bool:
	return false


func _settle_part(_part: Dictionary, record: Dictionary, target: Dictionary) -> bool:
	var value: float = float(record.get("value", 0.0))
	target["hp"] = float(target["hp"]) - value
	target["alive"] = target["hp"] > 0.0
	return true


func _hosts(cfg: Dictionary) -> Dictionary:
	var metadata: Dictionary = _json("res://data/params_meta.json")
	var handlers: Dictionary = {}
	var used_type: String = cfg["params"]["templates"][0]["parts"][0]["type"]
	for kind in metadata["enums"]["part_type"]:
		handlers[kind] = _settle_part if kind == used_type else _unsupported_part
	return {"targets": [{"target_id": "enemy_one", "position": Vector2(1.25, 0),
		"alive": true, "hp": 100.0, "invulnerable": false,
		"evade": {used_type: 0.0}, "immune": {}}], "handlers": handlers}


func _options(cfg: Dictionary, hosts: Dictionary, seed: int) -> Dictionary:
	var roots: Array = []
	var template_id: String = cfg["params"]["templates"][0]["template_id"]
	for index in range(cfg["bricks"].size()):
		var brick: Dictionary = cfg["bricks"][index]
		var registration: Dictionary = brick["default_cfg"]
		roots.append({"template_id": registration["template_id"], "shot_id": registration["shot_id"],
			"instance_id": "api:root:%d" % index})
	return {"seed": seed,
		"roots": roots, "handlers": hosts["handlers"],
		"template_families": {template_id: template_id},
		"derivation_bindings": {}, "targets": hosts["targets"]}


func _created(api: RefCounted, cfg: Dictionary, seed: int, hosts: Dictionary) -> Dictionary:
	var result: Dictionary = api.create_sim_with_hosts(cfg, seed, hosts)
	print("T078 create_sim_with_hosts: ", result)
	assert_true(result["ok"], str(result))
	return result


func test_host_input_channel_requires_full_part_type_handler_table() -> void:
	var cfg: Dictionary = _cfg()
	cfg["bricks"] = [cfg["bricks"][0]]
	var incomplete: Dictionary = {"targets": _hosts(cfg)["targets"], "handlers": {}}
	var result: Dictionary = ApiScript.new().create_sim_with_hosts(cfg, 17, incomplete)
	assert_false(result["ok"], str(result))
	assert_eq(result["path"], "hosts.handlers." + str(_json("res://data/params_meta.json")["enums"]["part_type"][0]))
	assert_true(result["diagnostics"] is Array)


func test_real_card_host_channel_produces_nonempty_three_stream_snapshot() -> void:
	var cfg: Dictionary = _cfg()
	var hosts: Dictionary = _hosts(cfg)
	var before: Dictionary = cfg.duplicate(true)
	var created: Dictionary = _created(ApiScript.new(), cfg, 17, hosts)
	if not created["ok"]:
		return
	var step: Dictionary = ApiScript.new().step_sim(created["sim"], 1)
	# The runner begins at tick zero; the first explicit step reaches the target.
	assert_true(step["ok"], str(step))
	if not step["ok"]:
		return
	var snapshot: Dictionary = step["snapshot"]
	print("T078 three streams: events=", snapshot["events"], " records=", snapshot["records"],
		" debug=", snapshot["budget"]["debug"])
	assert_gt(snapshot["events"].size(), 0)
	assert_gt(snapshot["records"].size(), 0)
	assert_true(snapshot["budget"]["debug"] is Array)
	assert_gt(snapshot["budget"]["debug"].size(), 0)
	assert_eq(cfg, before, "Host inputs and runtime state must not write to CFG")


func test_save_reload_and_formal_preview_are_same_trace_with_nonempty_difference_probe() -> void:
	var cfg: Dictionary = _cfg()
	var hosts: Dictionary = _hosts(cfg)
	var directory_error: int = DirAccess.make_dir_recursive_absolute("user://t078/")
	assert_eq(directory_error, OK)
	if directory_error != OK:
		return
	var path: String = "user://t078/t078_case.skillcfg"
	var saved: Dictionary = CodecScript.save_cfg(path, cfg)
	assert_true(saved["ok"], str(saved))
	if not saved["ok"]:
		return
	var loaded: Dictionary = CodecScript.load_cfg(path)
	assert_true(loaded["ok"], str(loaded))
	if not loaded["ok"]:
		return
	assert_eq(loaded["data"], cfg)
	assert_eq(loaded["data"]["meta"]["version"], "1")

	var api: RefCounted = ApiScript.new()
	var formal: Dictionary = _created(api, loaded["data"], 17, hosts)
	if not formal["ok"]:
		return
	var preview: RefCounted = RunnerScript.new()
	var started: Dictionary = preview.start(cfg, _options(cfg, hosts, 17))
	print("T078 direct PreviewRunner.start: ", started)
	assert_true(started["ok"], str(started))
	if not started["ok"]:
		return
	var diff: RefCounted = RunDiffScript.new()
	var configured: Dictionary = diff.configure({"limits": {"max_trace_ticks": 3}})
	assert_true(configured["ok"], str(configured))
	if not configured["ok"]:
		return
	var formal_trace: Dictionary = diff.capture(formal["sim"]["runner"], 3)
	var preview_trace: Dictionary = diff.capture(preview, 3)
	assert_true(formal_trace["ok"], str(formal_trace))
	assert_true(preview_trace["ok"], str(preview_trace))
	if not formal_trace["ok"] or not preview_trace["ok"]:
		return
	var compared: Dictionary = diff.compare(formal_trace["trace"], preview_trace["trace"])
	print("T078 formal/preview first difference: ", compared)
	assert_true(compared["ok"], str(compared))
	assert_true(compared["equal"], str(compared))
	assert_eq(compared["first_diff_index"], -1)
	assert_eq(compared["path"], "")

	var changed: Dictionary = cfg.duplicate(true)
	changed["params"]["templates"][0]["parts"][0]["amount"] = 7.5
	var changed_runner: RefCounted = RunnerScript.new()
	var changed_start: Dictionary = changed_runner.start(changed, _options(changed, hosts, 17))
	assert_true(changed_start["ok"], str(changed_start))
	if not changed_start["ok"]:
		return
	var changed_trace: Dictionary = diff.capture(changed_runner, 3)
	assert_true(changed_trace["ok"], str(changed_trace))
	if not changed_trace["ok"]:
		return
	var broken: Dictionary = diff.compare(preview_trace["trace"], changed_trace["trace"])
	print("T078 changed-card first difference: ", broken)
	assert_true(broken["ok"], str(broken))
	assert_false(broken["equal"], str(broken))
	assert_ne(broken["first_diff_index"], -1)
	assert_eq(cfg["meta"]["version"], "1")


func _cfg_v2() -> Dictionary:
	var cfg: Dictionary = _cfg()
	cfg["meta"]["version"] = "1.0.0"
	return cfg


func _validation_context(cfg: Dictionary) -> Dictionary:
	var catalog_entries: Array = _json("res://data/bricks/brick_catalog.json")
	var catalog: Dictionary = {}
	for entry in catalog_entries:
		if entry is Dictionary and entry.get("brick_id", "") == cfg["bricks"][0]["brick_id"]:
			catalog[entry["brick_id"]] = {"resolved": true, "status": entry.get("status", "")}
	var behaviors: Dictionary = {}
	for index in range(cfg["bricks"].size()):
		behaviors["bricks[%d]" % index] = ["damage"]
	return {
		"draft_revision": 2,
		"submitted_paths": ["schema_version", "skill_id", "meta", "bricks", "params", "presentation", "runtime_hints"],
		"roles": ["mage"], "pools": ["starter"], "tags": ["ranged"],
		"catalog": catalog, "card_behaviors": behaviors,
		"outputs": {}, "definitions": [], "current_source": "",
		"capabilities": {"params": {"summon": false}}, "item_category": "relic", "exposed": {},
		"live_requests": [], "stack_operations": {}, "set_counts": {}, "reset_writes": [],
		"derivation_analysis": {"truncated_paths": []},
		"budget_estimate": {"total_requested_instances": 1, "capped": false, "guarantee_bindings": []},
		"produced_types": {"spawn_ref": "effect_template"}, "record_fields": _json("res://data/record_fields.json"),
		"condition_registry": {"condition_ref": {"accessible_fields": ["source", "target"], "part_filters": []}},
		"self_chain_evidence": {"depth_bound": true, "source_mark_bound": true, "cooldown_bound": true, "budget_bound": true, "worst_case_note_complete": true},
		"project_limits": {"defaults": {"cast_budget": 16}, "hard_caps": {"max_generation": 4, "cast_budget": 64, "max_chain_depth": 8}},
		"player_attribute_bindings": {}, "resource_resolution": {}, "default_applications": [],
		"baseline_version_state": {"baseline_version": "1.0.0", "current_underlying_version": "1.0.0", "operation": "save"},
		"migration_state": {"migrating": false, "source_version": "0.1", "target_version": "0.1", "path_complete": true, "lossless": true},
		"probe_credentials": {}, "preview_fingerprint": {"preview_fingerprint": "v2", "current_fingerprint": "v2", "operation": "save"},
		"cross_card_facts": {}
	}


func _block_diagnostics(result: Dictionary) -> Array:
	var blocks: Array = []
	for diagnostic in result.get("diagnostics", []):
		var severity: int = int(diagnostic.severity) if diagnostic is RefCounted else int(diagnostic.get("severity", -1))
		if severity == 0:
			blocks.append(diagnostic)
	return blocks


func test_v2_validate_with_context_returns_all_six_stages_without_blocks() -> void:
	var cfg: Dictionary = _cfg_v2()
	var context: Dictionary = _validation_context(cfg)
	var api: RefCounted = ApiScript.new()
	var stages: Array[StringName] = [ApiScript.STAGE_FILLING, ApiScript.STAGE_CARD,
		ApiScript.STAGE_ASSEMBLY, ApiScript.STAGE_SAVE, ApiScript.STAGE_LOAD, ApiScript.STAGE_PREVIEW]
	var revisions: Array[int] = []
	for stage in stages:
		var result: Dictionary = api.validate_with_context(cfg, stage, context)
		print("T078 v2 validation ", String(stage), ": ", result)
		assert_true(result.has("ok"), str(result))
		assert_eq(_block_diagnostics(result).size(), 0, "%s must have zero block diagnostics" % String(stage))
		revisions.append(int(result.get("revision", -1)))
	assert_eq(revisions.size(), 6)
	for revision in revisions:
		assert_eq(revision, 2)


func test_v2_validate_with_context_rejects_invalid_skill_id_with_nonempty_block_probe() -> void:
	var cfg: Dictionary = _cfg_v2()
	cfg["skill_id"] = "INVALID"
	var result: Dictionary = ApiScript.new().validate_with_context(cfg, ApiScript.STAGE_SAVE, _validation_context(cfg))
	print("T078 v2 invalid identity probe: ", result)
	assert_false(result["ok"], str(result))
	var matching: Array = []
	for diagnostic in result.get("diagnostics", []):
		var rule_id: String = str(diagnostic.rule_id) if diagnostic is RefCounted else str(diagnostic.get("rule_id", ""))
		var path: String = str(diagnostic.path) if diagnostic is RefCounted else str(diagnostic.get("path", ""))
		var severity: int = int(diagnostic.severity) if diagnostic is RefCounted else int(diagnostic.get("severity", -1))
		if rule_id == "V-002" and path == "skill_id" and severity == 0:
			matching.append(diagnostic)
	assert_eq(matching.size(), 1, "invalid skill_id must produce one concrete V-002 block")


func test_validate_with_context_does_not_fabricate_missing_context() -> void:
	var cfg: Dictionary = _cfg_v2()
	var context: Dictionary = _validation_context(cfg)
	context.erase("draft_revision")
	var result: Dictionary = ApiScript.new().validate_with_context(cfg, ApiScript.STAGE_SAVE, context)
	assert_false(result["ok"], str(result))
	assert_eq(result.get("path", ""), "context.draft_revision")
