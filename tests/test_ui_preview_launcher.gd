extends GutTest

const PreviewLauncher = preload("res://addons/skill_editor/ui/preview_launcher.gd")
const PreviewRunner = preload("res://skill_core/runtime/preview_runner.gd")


class StubRunner extends RefCounted:
	var calls: Array = []
	var starts: Array = []
	var next_start: Dictionary = {"ok": true, "fingerprint": "stub", "tick_rate": 60,
		"diagnostics": [], "error": ""}
	var stop_result: Dictionary = {"ok": true, "error": ""}

	func start(cfg: Variant, options: Dictionary) -> Dictionary:
		calls.append("start")
		var cfg_copy: Variant = cfg.duplicate(true) if cfg is Dictionary else cfg
		if cfg_copy is Dictionary:
			cfg_copy["mutated_by_runner"] = true
		starts.append({"cfg": cfg_copy, "options": options.duplicate(true)})
		return next_start.duplicate(true)

	func stop() -> Dictionary:
		calls.append("stop")
		return stop_result.duplicate(true)


func _options() -> Dictionary:
	return {"seed": 17,
		"roots": [{"template_id": "root_recipe", "shot_id": "shot_a"}],
		"targets": [], "handlers": {},
		"template_families": {"root_recipe": "root_family"},
		"derivation_bindings": {}, "motion_inputs": {}}


func _launcher(stub: StubRunner = null) -> Array:
	var runner: StubRunner = stub if stub != null else StubRunner.new()
	var launcher: PreviewLauncher = PreviewLauncher.new()
	assert_true(launcher.configure(runner)["ok"])
	return [launcher, runner]


func test_missing_seed_is_explicit_and_has_no_fallback() -> void:
	var stub: StubRunner = StubRunner.new()
	var pair: Array = _launcher(stub)
	var launcher: PreviewLauncher = pair[0]
	var options: Dictionary = _options()
	options.erase("seed")
	var result: Dictionary = launcher.launch({"schema_version": "0.1"}, options)
	assert_false(result["ok"])
	assert_string_contains(result["path"], "seed")
	assert_string_contains(result["error"], "seed")
	assert_eq(stub.calls, [])


func test_same_arguments_are_deeply_forwarded_without_time_or_random_fields() -> void:
	var stub: StubRunner = StubRunner.new()
	var pair: Array = _launcher(stub)
	var launcher: PreviewLauncher = pair[0]
	var cfg: Dictionary = {"schema_version": "0.1", "skill_id": "stable"}
	var options: Dictionary = _options()
	assert_true(launcher.launch(cfg, options)["ok"])
	assert_true(launcher.stop()["ok"])
	assert_true(launcher.launch(cfg, options)["ok"])
	assert_eq(stub.starts.size(), 2)
	assert_eq(stub.starts[0]["options"], stub.starts[1]["options"])
	assert_false(stub.starts[0]["options"].has("timestamp"))
	assert_false(stub.starts[0]["options"].has("random"))
	assert_eq(stub.starts[0]["options"], options)


func test_switch_version_stops_before_start_and_forwards_new_cfg() -> void:
	var stub: StubRunner = StubRunner.new()
	var pair: Array = _launcher(stub)
	var launcher: PreviewLauncher = pair[0]
	var options: Dictionary = _options()
	var first_cfg: Dictionary = {"schema_version": "0.1", "version": "one"}
	var second_cfg: Dictionary = {"schema_version": "0.1", "version": "two"}
	assert_true(launcher.launch(first_cfg, options)["ok"])
	stub.calls.clear()
	var result: Dictionary = launcher.switch_version(second_cfg, options)
	assert_true(result["ok"])
	assert_eq(stub.calls, ["stop", "start"])
	assert_eq(stub.starts[1]["cfg"]["version"], second_cfg["version"])
	assert_false(second_cfg.has("mutated_by_runner"))


func test_unregistered_hot_reload_option_fails_instead_of_being_ignored() -> void:
	var pair: Array = _launcher()
	var launcher: PreviewLauncher = pair[0]
	var options: Dictionary = _options()
	options["hot_reload"] = true
	var result: Dictionary = launcher.launch({}, options)
	assert_false(result["ok"])
	assert_string_contains(result["path"], "hot_reload")
	assert_string_contains(result["error"], "hot_reload")


func test_launch_never_writes_back_to_cfg() -> void:
	var stub: StubRunner = StubRunner.new()
	var pair: Array = _launcher(stub)
	var launcher: PreviewLauncher = pair[0]
	var cfg: Dictionary = {"schema_version": "0.1", "params": {"damage": 10,
		"nested": [{"value": true}]}}
	var before: String = JSON.stringify(cfg)
	assert_true(launcher.launch(cfg, _options())["ok"])
	assert_eq(JSON.stringify(cfg), before)
	assert_true(stub.starts[0]["cfg"].has("mutated_by_runner"))


func test_missing_runner_and_runner_failure_are_explicit_and_transparent() -> void:
	var launcher: PreviewLauncher = PreviewLauncher.new()
	var missing: Dictionary = launcher.launch({}, _options())
	assert_false(missing["ok"])
	assert_string_contains(missing["error"], "runner")

	var stub: StubRunner = StubRunner.new()
	stub.next_start = {"ok": false, "path": "cfg", "error": "invalid definition", "diagnostics": []}
	assert_true(launcher.configure(stub)["ok"])
	var rejected: Dictionary = launcher.launch({}, _options())
	assert_false(rejected["ok"])
	assert_eq(rejected["path"], "cfg")
	assert_string_contains(rejected["error"], "cfg")
	assert_string_contains(rejected["error"], "invalid definition")


func _true_cfg() -> Dictionary:
	var template: Dictionary = {"template_id": "root_recipe", "carrier": "independent",
		"lifetime_ticks": 12, "targeting": {"target_group": "enemy"},
		"motion": {"mode": "straight", "speed": 1.0},
		"geometry": {"shape": "circle", "radius": 0.01},
		"hit_policy": {"per_target_limit": 1, "max_hits": 1},
		"parts": [{"part_index": 0, "type": "physical", "amount": 10.0}],
		"derivations": []}
	return {"schema_version": "0.1", "skill_id": "launcher_smoke",
		"meta": {"role": "mage", "category": "active", "short_name": "smoke",
			"name": "Launcher smoke", "version": "1", "author": "test"},
		"bricks": [], "params": {"carrier": "independent", "lifetime_ticks": 12,
			"templates": [template], "cast_budget": 1, "max_generation": 0,
			"split_budget": 0, "chain_remaining": 0, "safety": {"max_chain_depth": 1}},
		"presentation": {"fx": {}, "sfx": {"max_concurrency": 0}, "anim": {},
			"trail": {"carrier": "independent"}, "camera": {}, "damage_number": {},
			"status_icon": {}}, "runtime_hints": {}}


func _damage(_part: Dictionary, _record: Dictionary, _target: Dictionary) -> bool:
	return true


func test_injected_real_runner_can_start_and_stop_once() -> void:
	var runner: PreviewRunner = PreviewRunner.new()
	var launcher: PreviewLauncher = PreviewLauncher.new()
	assert_true(launcher.configure(runner)["ok"])
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/params_meta.json"))
	var handlers: Dictionary = {}
	for kind_value in metadata["enums"]["part_type"]:
		handlers[str(kind_value)] = Callable(self, "_damage")
	var options: Dictionary = {"seed": 17,
		"roots": [{"template_id": "root_recipe", "shot_id": "shot_a"}],
		"targets": [], "handlers": handlers,
		"template_families": {"root_recipe": "root_family"},
		"derivation_bindings": {}, "motion_inputs": {}}
	var started: Dictionary = launcher.launch(_true_cfg(), options)
	assert_true(started["ok"], str(started))
	var stopped: Dictionary = launcher.stop()
	assert_true(stopped["ok"], str(stopped))
	assert_false(launcher.is_running())
