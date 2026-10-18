extends GutTest

const RunnerScript = preload("res://skill_core/runtime/preview_runner.gd")
const InputHostScript = preload("res://skill_core/runtime/hosts/preview_input_host.gd")


func _native(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[key] = _native(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_native(item))
		return result
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value


func _damage(_part: Dictionary, record: Dictionary, target: Dictionary) -> bool:
	target["hp"] = maxf(0.0, float(target["hp"]) - float(record["value"]))
	target["alive"] = target["hp"] > 0.0
	return true


func _unsupported_part(_part: Dictionary, _record: Dictionary, _target: Dictionary) -> bool:
	# Explicit fail-closed adapters for registered types this fixture never uses.
	return false


func _inputs(shots: Array, window: int = 3) -> Dictionary:
	var source: Dictionary = _native(JSON.parse_string(FileAccess.get_file_as_string("res://data/fixtures/ed17.json")))
	var cfg: Dictionary = source["cfg"].duplicate(true)
	cfg["params"]["templates"][0]["cast"] = {"windup_ticks": shots[0],
		"shot_ticks": shots.duplicate(), "shot_count": shots.size(), "cooldown_seconds": 0.01}
	var host: RefCounted = InputHostScript.new()
	assert_true(host.configure({"input_buffer": {"window_ticks": window}})["ok"])
	# Settle preflights every registered type, even with no targets. Match its
	# metadata-driven adapter contract without implementing other capabilities.
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/params_meta.json"))
	var handlers: Dictionary = {}
	for kind in meta["enums"]["part_type"]:
		handlers[kind] = _unsupported_part
	handlers["physical"] = _damage
	var options: Dictionary = {"seed": source["seed"], "project_config": source["project_config"],
		"roots": [{"template_id": "root_recipe", "shot_id": "first"}], "targets": [],
		"handlers": handlers, "motion_inputs": {},
		"template_families": {"root_recipe": "split_family"},
		"derivation_bindings": {"root_recipe": {}}, "runtime_host": host}
	return {"cfg": cfg, "options": options, "host": host, "runner": RunnerScript.new()}


func test_09_gate_deadline_and_actual_window_recovery() -> void:
	var counts: Array = []
	for window in [3, 1]:
		var input: Dictionary = _inputs([1], window)
		var host: RefCounted = input["host"]
		var runner: RefCounted = input["runner"]
		# Gate the initial request too: no unrelated action or skill cooldown.
		assert_true(host.set_locks({"cast_gate": true, "pause_cast": false, "interrupts_cast": false})["ok"])
		assert_true(runner.start(input["cfg"], input["options"])["ok"])
		assert_eq(host.snapshot_state()["pending"].size(), 1)
		assert_eq(host.snapshot_state()["actions"].size(), 0)
		assert_true(runner.advance_ticks(1)["ok"])
		assert_eq(host.snapshot_state()["discarded"].size(), 0 if window == 3 else 1,
			"Source :8847: discard at the deadline, not after it")
		assert_true(host.set_locks({"cast_gate": false, "pause_cast": false, "interrupts_cast": false})["ok"])
		assert_true(runner.advance_ticks(2)["ok"])
		counts.append(runner.snapshot_state()["entities"].size())
		assert_eq(host.snapshot_state()["X"], 1 if window == 3 else 0)
		assert_true(runner.stop()["ok"])
	assert_eq(counts, [1, 0], "Actual released body versus expired input")


func test_10_pause_resumes_but_interrupt_preserves_only_existing_body() -> void:
	var results: Array = []
	for interrupt in [false, true]:
		var input: Dictionary = _inputs([1, 3])
		var host: RefCounted = input["host"]
		var runner: RefCounted = input["runner"]
		var started: Dictionary = runner.start(input["cfg"], input["options"])
		assert_true(started["ok"], "ED-17-10 runner preflight: " + str(started))
		if not started["ok"]:
			return
		assert_true(runner.advance_ticks(1)["ok"])
		assert_eq(runner.snapshot_state()["active_count"], 1, "Actual first shot before control")
		assert_true(host.set_locks({"cast_gate": true, "pause_cast": true, "interrupts_cast": interrupt})["ok"])
		for tick in [2, 3]:
			assert_true(runner.advance_ticks(1)["ok"])
			var state: Dictionary = runner.snapshot_state()
			assert_eq(state["clock"]["tick"], tick)
			assert_eq(state["active_count"], 1, "Neither pause nor cancel purges an existing body")
			assert_eq(state["entities"]["preview:0:root:0"]["position"], Vector2(tick - 1, 0), "Existing body continues moving")
		assert_true(host.set_locks({"cast_gate": false, "pause_cast": false, "interrupts_cast": false})["ok"])
		assert_true(runner.advance_ticks(1)["ok"])
		assert_eq(runner.snapshot_state()["entities"].size(), 1, "No premature resumed release at tick4")
		assert_true(runner.advance_ticks(1)["ok"])
		results.append(runner.snapshot_state()["entities"].size())
		assert_eq(host.snapshot_state()["X"], 1 if interrupt else 2)
		assert_true(runner.stop()["ok"])
	assert_eq(results, [2, 1], "Paused second shot resumes at tick5; cancelled one never returns")


func test_12_three_actions_six_shots_and_multi_instance_count() -> void:
	var input: Dictionary = _inputs([0, 2])
	input["options"]["roots"] = []
	for index in range(3):
		input["options"]["roots"].append({"template_id": "root_recipe", "shot_id": "input:%d" % index, "instance_count": 2})
	var host: RefCounted = input["host"]
	var runner: RefCounted = input["runner"]
	var started: Dictionary = runner.start(input["cfg"], input["options"])
	assert_true(started["ok"], "ED-17-12 runner preflight: " + str(started))
	if not started["ok"]:
		return
	assert_eq(runner.snapshot_state()["entities"].size(), 2)
	assert_true(runner.advance_ticks(8)["ok"])
	var ledger: Dictionary = host.snapshot_state()
	assert_eq(ledger["actions"].size(), 3)
	assert_eq(ledger["shots"].size(), 6)
	assert_eq(ledger["X"], 6)
	assert_eq(runner.snapshot_state()["entities"].size(), 12, "X is independent of per-shot multiplicity")
	var ticks: Array = []
	for shot in ledger["shots"]:
		ticks.append(shot["tick"])
	assert_eq(ticks, [0, 2, 3, 5, 6, 8])
	assert_true(runner.stop()["ok"])
	# Restart without an input adapter must not retain the previous host.
	input["options"].erase("runtime_host")
	input["options"]["roots"] = [{"template_id": "root_recipe", "shot_id": "restart"}]
	assert_true(runner.start(input["cfg"], input["options"])["ok"])
	assert_eq(runner.snapshot_state()["entities"].size(), 1)
	assert_eq(host.snapshot_state()["X"], 6, "Detached adapter does not consume a subsequent preview")
	assert_true(runner.stop()["ok"])


