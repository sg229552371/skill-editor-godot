extends GutTest

const Runner = preload("res://skill_core/runtime/preview_runner.gd")
const FIXTURE: String = "res://data/fixtures/ed17.json"
const PUBLIC_API: Array = ["advance_seconds", "advance_ticks", "presentation_random", "snapshot_state", "start", "stop"]
var _data: Dictionary = {}


func _fixture() -> Dictionary:
	if _data.is_empty():
		var parser: JSON = JSON.new()
		var error: int = parser.parse(FileAccess.get_file_as_string(FIXTURE))
		assert_eq(error, OK, "ED-17-01..ED-17-24 fixture JSON: " + parser.get_error_message())
		assert_true(parser.data is Dictionary, "ED-17-01..ED-17-24 fixture object")
		if parser.data is Dictionary:
			_data = _native(parser.data)
	return _data


# Fixture JSON numbers are floats. This is test input construction, BEFORE the
# CFG immutability baseline, not a relaxation of runtime integer validation.
func _native(value: Variant) -> Variant:
	if value is Dictionary:
		var object: Dictionary = {}
		for key in value:
			object[key] = _native(value[key])
		return object
	if value is Array:
		var items: Array = []
		for item in value:
			items.append(_native(item))
		return items
	if value is float and is_finite(value) and value == floor(value):
		return int(value)
	return value


func _case(number: int) -> Dictionary:
	var id: String = "ED-17-%02d" % number
	var found: Array = []
	for entry in _fixture().get("cases", []):
		if entry is Dictionary and str(entry.get("id", "")) == id:
			found.append(entry)
	assert_eq(found.size(), 1, id + " exactly one fixture")
	return found[0].duplicate(true) if found.size() == 1 else {"id": id, "input": {}}


func _ledger() -> void:
	var expected: Array = []
	for number in range(1, 25):
		expected.append("ED-17-%02d" % number)
	var actual: Array = []
	var entries: Variant = _fixture().get("cases", null)
	assert_true(entries is Array, "ED-17-01..ED-17-24 cases array")
	if not entries is Array:
		return
	assert_eq(entries.size(), 24, "ED-17-01..ED-17-24 cardinality")
	for entry in entries:
		assert_true(entry is Dictionary, "ED-17-01..ED-17-24 case object")
		if not entry is Dictionary:
			continue
		var id: String = str(entry.get("id", ""))
		assert_false(actual.has(id), id + " no duplicate id")
		actual.append(id)
		assert_true(["ok", "blocked"].has(entry.get("status", null)), id + " status enum")
		assert_eq(entry.get("verification", ""), "not_run", id + " author has not run engine")
		if str(entry.get("status", "")) == "blocked":
			for key in ["blocked_reason", "blocked_probe"]:
				var text: Variant = entry.get(key, null)
				assert_true(text is String, id + " " + key + " string")
				if text is String:
					assert_false(text.strip_edges().is_empty(), id + " " + key + " nonempty")
	actual.sort()
	assert_eq(actual, expected, "ED-17-01..ED-17-24 exact id set, generated with range(1,25)")


func _variant(c: Dictionary, patch: Dictionary) -> Dictionary:
	var copy: Dictionary = c.duplicate(true)
	copy["input"].merge(patch, true)
	return copy


func _damage(_part: Dictionary, record: Dictionary, target: Dictionary) -> bool:
	target["hp"] = maxf(0.0, float(target["hp"]) - float(record["value"]))
	target["alive"] = target["hp"] > 0.0
	target["applied"].append(record.duplicate(true))
	return true


func _heal(_part: Dictionary, record: Dictionary, target: Dictionary) -> bool:
	target["hp"] = minf(float(target["max_hp"]), float(target["hp"]) + float(record["value"]))
	target["applied"].append(record.duplicate(true))
	return true


func _effect(part: Dictionary, record: Dictionary, target: Dictionary) -> bool:
	# The host applies an actual status marker; it does NOT implement missing
	# shield lifecycle, cast scheduling, passive logic or derivation in tests.
	target["applied"].append({"part": part.duplicate(true), "result": record.duplicate(true)})
	return true


func _prepare(c: Dictionary) -> Dictionary:
	var source: Dictionary = _fixture()
	var cfg: Dictionary = source["cfg"].duplicate(true)
	var input: Dictionary = c["input"]
	var root: Dictionary = cfg["params"]["templates"][0]
	root.merge(input.get("root", {}), true)
	if input.has("parts"):
		root["parts"] = input["parts"].duplicate(true)
	var families: Dictionary = {"root_recipe": "split_family"}
	var bindings: Dictionary = {"root_recipe": {}}
	if input.has("derive"):
		var child: Dictionary = source["cfg"]["params"]["templates"][0].duplicate(true)
		child["template_id"] = "child_recipe"
		child["lifetime_ticks"] = 6
		cfg["params"]["templates"].append(child)
		var rule: Dictionary = input["derive"].duplicate(true)
		rule["trigger_id"] = "split_once"
		rule["child_template"] = "child_recipe"
		root["derivations"] = [rule]
		families["child_recipe"] = "split_family"
		bindings["root_recipe"]["split_once"] = {"budgets": ["split_budget"], "reject_visited": false}
	var targets: Array = []
	for spec in input.get("targets", [{"id": "victim", "x": 0}]):
		targets.append({"target_id": str(spec["id"]), "position": Vector2(float(spec["x"]), 0),
			"alive": true, "hp": float(spec.get("hp", 100)), "max_hp": 100.0,
			"invulnerable": spec.get("invulnerable", false),
			"evade": spec.get("evade", {}).duplicate(true), "immune": spec.get("immune", {}).duplicate(true), "applied": []})
	var roots: Array = []
	for index in range(int(input.get("root_count", 1))):
		roots.append({"template_id": "root_recipe", "shot_id": "shot_%d" % index if input.get("distinct_shots", false) else "shot_a"})
	var handlers: Dictionary = {}
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/params_meta.json"))
	for kind in meta["enums"]["part_type"]:
		handlers[kind] = _effect
	for kind in ["physical", "fire", "ice", "lightning", "arcane"]:
		handlers[kind] = _damage
	handlers["heal"] = _heal
	var options: Dictionary = {"seed": int(source["seed"]), "project_config": source["project_config"].duplicate(true),
		"roots": roots, "targets": targets, "handlers": handlers, "motion_inputs": {},
		"template_families": families, "derivation_bindings": bindings}
	return {"cfg": cfg, "options": options}


func _run(c: Dictionary, visual_draws: int = 0, batched: bool = false) -> Dictionary:
	var id: String = c["id"]
	var prepared: Dictionary = _prepare(c)
	var cfg: Dictionary = prepared["cfg"]
	var before: String = JSON.stringify(cfg)
	var runner: RefCounted = Runner.new()
	var started: Dictionary = runner.start(cfg, prepared["options"])
	assert_true(started["ok"], id + " baseline start: " + str(started))
	var trace: Array = [runner.snapshot_state()]
	if started["ok"]:
		var ticks: int = int(c["input"].get("ticks", 2))
		if c["input"].get("stop_now", false):
			assert_true(runner.stop()["ok"], id + " silent purge stop")
			trace.append(runner.snapshot_state())
		elif batched:
			for _draw in range(visual_draws):
				runner.presentation_random()
			assert_true(runner.advance_ticks(ticks)["ok"], id + " batched advance: " + runner.last_error)
			trace.append(runner.snapshot_state())
		else:
			for tick in range(ticks):
				for _draw in range(visual_draws):
					runner.presentation_random()
				assert_true(runner.advance_ticks(1)["ok"], id + " tick %d: " % tick + runner.last_error)
				trace.append(runner.snapshot_state())
	var state: Dictionary = runner.snapshot_state()
	assert_true(runner.stop()["ok"], id + " teardown stop")
	assert_eq(JSON.stringify(cfg), before, id + " input CFG unchanged after start/advance/snapshot/stop")
	return {"state": state, "trace": trace}


func _pair(c: Dictionary) -> Dictionary:
	var first: Dictionary = _run(c)
	var second: Dictionary = _run(c)
	assert_eq(first, second, c["id"] + " same input/seed every snapshot including ticks and RNG")
	return first["state"]


func _of(entries: Array, kind: String, field: String = "type") -> Array:
	var result: Array = []
	for entry in entries:
		if str(entry.get(field, "")) == kind:
			result.append(entry)
	return result


func _rejection(c: Dictionary, patch: Dictionary, path: String, error: String) -> Dictionary:
	var id: String = c["id"]
	var prepared: Dictionary = _prepare(c)
	prepared["cfg"]["params"]["templates"][0].merge(patch, true)
	var before: String = JSON.stringify(prepared["cfg"])
	var runner: RefCounted = Runner.new()
	var result: Dictionary = runner.start(prepared["cfg"], prepared["options"])
	assert_false(result["ok"], id + " capability probe must be rejected, not accepted/no-op")
	assert_eq(result.get("path", ""), path, id + " exact missing capability path")
	assert_true(str(result.get("error", "")).contains(error), id + " explicit unsupported error: " + str(result))
	var state: Dictionary = runner.snapshot_state()
	assert_false(state["running"], id + " failed probe not running")
	assert_eq(state["entities"].size(), 0, id + " preflight refusal creates no fake instances")
	runner.stop()
	assert_eq(JSON.stringify(prepared["cfg"]), before, id + " rejected CFG unchanged")
	return {"ok": result["ok"], "path": result.get("path", ""), "error": result.get("error", ""), "state": state}


func _api_probe(c: Dictionary) -> Dictionary:
	var id: String = c["id"]
	var runner: RefCounted = Runner.new()
	var methods: Array = []
	for method in runner.get_script().get_script_method_list():
		var name: String = str(method["name"])
		if not name.begins_with("_"):
			methods.append(name)
	methods.sort()
	assert_eq(methods, PUBLIC_API, id + " complete public script API: missing host integration, not just a guessed name")
	var observed: Dictionary = {}
	for name in c["input"].get("probe_methods", []):
		observed[name] = runner.has_method(name)
		assert_false(observed[name], id + " missing candidate capability " + str(name))
	assert_gt(observed.size(), 0, id + " nonempty actual capability probe")
	return {"public_api": methods, "capabilities": observed}


func _blocked(number: int) -> Dictionary:
	var c: Dictionary = _case(number)
	var id: String = c["id"]
	assert_eq(c["status"], "blocked", id + " explicit BLOCKED, never acceptance PASS")
	# A real nonempty positive control prevents an invalid fixture/schema failure
	# being mistaken for evidence that the requested feature is unsupported.
	var state: Dictionary = _pair(c)
	assert_gt(state["entities"].size(), 0, id + " capability control actually created a body")
	assert_gt(state["events"].size(), 0, id + " capability control actually produced an event")
	var input: Dictionary = c["input"]
	if input.has("reject_patch"):
		var first: Dictionary = _rejection(c, input["reject_patch"], input["reject_path"], input["reject_error"])
		var second: Dictionary = _rejection(c, input["reject_patch"], input["reject_path"], input["reject_error"])
		assert_eq(first, second, id + " unsupported probe snapshots deterministic")
	elif input.has("probe_methods"):
		assert_eq(_api_probe(c), _api_probe(c), id + " API probes deterministic")
	else:
		assert_true(false, id + " blocked case has no executable probe")
	return state


func test_ed17_01_three_parts_one_hit_one_derivation() -> void:
	_ledger()
	var c: Dictionary = _case(1)
	var s: Dictionary = _pair(c)
	var expected: Dictionary = c["expected"]
	assert_eq(_of(s["events"], "hit").size(), int(expected["hit"]), "ED-17-01 exactly one hit")
	assert_eq(s["records"].size(), 1, "ED-17-01 one contact summary")
	assert_eq(_of(s["derive"]["records"], "created", "kind").size(), int(expected["children"]), "ED-17-01 actual derivation execution count")
	if s["records"].size() != 1:
		return
	var parts: Array = s["records"][0]["parts"]
	assert_eq(parts.size(), int(expected["parts"]), "ED-17-01 three part records")
	var evaded: Array = []
	for part in parts:
		evaded.append(part["evaded"])
	assert_eq(evaded, expected["evaded"], "ED-17-01 only middle part evaded")
	assert_eq(s["targets"][0]["hp"], float(expected["hp"]), "ED-17-01 actual damage")
	var control: Dictionary = _pair(_variant(c, {"targets": [{"id": "victim", "x": 0, "evade": {"physical": 1, "fire": 1, "ice": 1}}]}))
	assert_eq(_of(control["events"], "hit").size(), 0, "ED-17-01 all-evaded control no hit")
	assert_eq(_of(control["records"], "evaded_all").size(), 1, "ED-17-01 all-evaded control record exists")
	assert_eq(_of(control["derive"]["records"], "created", "kind").size(), 0, "ED-17-01 no derived child from all evade")


func test_ed17_02_all_evade_overlap_and_max_hits() -> void:
	var c: Dictionary = _case(2)
	var s: Dictionary = _pair(c)
	var hits: Array = _of(s["events"], "hit")
	var evades: Array = _of(s["records"], "evaded_all")
	assert_eq(hits.size(), 1, "ED-17-02 max_hits remains available for later target")
	assert_eq(evades.size(), 1, "ED-17-02 sustained overlap no second evade contact")
	assert_eq(s["records"].size(), 2, "ED-17-02 one evaded contact plus one later settled contact")
	if hits.size() != 1 or evades.size() != 1:
		return
	assert_eq(hits[0]["target_id"], c["expected"]["later_target"], "ED-17-02 later target uses max_hits")
	assert_eq(evades[0]["parts"].size(), 3, "ED-17-02 all three parts attempted")
	assert_eq(s["targets"][0]["hp"], 100.0, "ED-17-02 evader took no damage")
	assert_eq(s["targets"][1]["hp"], float(c["expected"]["hp"]), "ED-17-02 later target damage")
	var control: Dictionary = _pair(_variant(c, {"targets": [{"id": "evader", "x": 0}, {"id": "other", "x": 3}]}))
	assert_eq(control["records"].size(), 1, "ED-17-02 successful first contact spends max_hits")
	assert_eq(control["targets"][1]["hp"], 100.0, "ED-17-02 successful control prevents later hit")


func test_ed17_03_invulnerable_damage_heal_control() -> void:
	var c: Dictionary = _case(3)
	var s: Dictionary = _pair(c)
	assert_eq(_of(s["events"], "hit").size(), 1, "ED-17-03 heal/control preserve hit")
	assert_eq(s["records"].size(), 1, "ED-17-03 one summary")
	if s["records"].size() != 1:
		return
	var parts: Array = s["records"][0]["parts"]
	assert_eq(parts.size(), 3, "ED-17-03 all part kinds present")
	if parts.size() != 3:
		return
	assert_true(parts[0]["evaded"], "ED-17-03 invulnerability evades damage")
	assert_false(parts[1]["evaded"], "ED-17-03 healing not evaded")
	assert_eq(parts[1]["value"], 10.0, "ED-17-03 healing amount")
	assert_false(parts[2]["evaded"], "ED-17-03 control not damage-invulnerability")
	assert_true(parts[2]["immune"], "ED-17-03 matching stun immunity")
	assert_eq(s["targets"][0]["hp"], 60.0, "ED-17-03 heal applied")
	var control: Dictionary = _pair(_variant(c, {"targets": [{"id": "victim", "x": 0, "hp": 50, "invulnerable": true, "immune": {"stun": false}}]}))
	assert_eq(control["targets"][0]["applied"].size(), 2, "ED-17-03 without immunity healing and control both applied")
	assert_eq(s["targets"][0]["applied"].size(), 1, "ED-17-03 immunity removes only control application")


func test_ed17_04_immunity_zero_is_still_hit() -> void:
	var c: Dictionary = _case(4)
	var s: Dictionary = _pair(c)
	assert_eq(_of(s["events"], "hit").size(), 1, "ED-17-04 immune zero hit")
	assert_eq(_of(s["records"], "evaded_all").size(), 0, "ED-17-04 immune is not evade")
	assert_eq(s["records"].size(), 1, "ED-17-04 summary exists")
	if s["records"].size() != 1:
		return
	var part: Dictionary = s["records"][0]["parts"][0]
	assert_eq(part["value"], 0.0, "ED-17-04 immune value zero")
	assert_true(part["immune"], "ED-17-04 immune flag")
	assert_true(part["zero"], "ED-17-04 zero flag")
	assert_false(part["evaded"], "ED-17-04 not evaded")
	var control: Dictionary = _pair(_variant(c, {"targets": [{"id": "victim", "x": 0}]}))
	assert_eq(control["targets"][0]["hp"], 90.0, "ED-17-04 removing immunity changes damage")
	assert_eq(s["targets"][0]["hp"], 100.0, "ED-17-04 zero damage actually applied")


func test_ed17_05_blocked_instant_carrier_adapter() -> void:
	_blocked(5)


func test_ed17_06_death_rechecked_between_instances() -> void:
	var c: Dictionary = _case(6)
	var s: Dictionary = _pair(c)
	assert_eq(s["entities"].size(), 2, "ED-17-06 actually two roots")
	assert_eq(_of(s["events"], "hit").size(), 1, "ED-17-06 only first lethal hit")
	assert_eq(_of(s["records"], "evaded_all").size(), 0, "ED-17-06 dead target not evaded_all")
	assert_eq(s["records"].size(), 1, "ED-17-06 later root no settlement")
	var kills: int = 0
	for record in s["records"]:
		if record["killed"]:
			kills += 1
	assert_eq(kills, 1, "ED-17-06 exactly one killing transaction")
	assert_eq(s["targets"][0]["hp"], 0.0, "ED-17-06 target dead")
	var control: Dictionary = _pair(_variant(c, {"targets": [{"id": "victim", "x": 0, "hp": 100}]}))
	assert_eq(_of(control["events"], "hit").size(), 2, "ED-17-06 surviving-target control proves second root can hit")


func test_ed17_07_blocked_area_pulse_expiry_scheduler() -> void:
	var c: Dictionary = _case(7)
	var state: Dictionary = _pair(c)
	assert_eq(c["status"], "blocked", "ED-17-07 timing scheduler still missing")
	assert_eq(state["entities"].size(), 1, "ED-17-07 valid independent control creates one body")
	assert_eq(_of(state["events"], "hit").size(), 1, "ED-17-07 valid control actually hits")
	var first: Dictionary = _rejection(c, c["input"]["reject_patch"],
		"params.templates[0].timing", "Host adapter not implemented: timing")
	assert_true(first["error"].contains("Host adapter"), "ED-17-07 missing host adapter")
	assert_true(first["error"].contains("timing"), "ED-17-07 missing timing section")
	assert_eq(first, _rejection(c, c["input"]["reject_patch"],
		"params.templates[0].timing", "Host adapter not implemented: timing"),
		"ED-17-07 timing refusal reproducible")


func test_ed17_08_purge_cancels_real_termination_derivation() -> void:
	var c: Dictionary = _case(8)
	var s: Dictionary = _pair(c)
	assert_eq(s["active_count"], 0, "ED-17-08 purge removed live body")
	assert_eq(s["entities"].size(), 1, "ED-17-08 root existed, no child")
	assert_eq(s["events"].size(), 0, "ED-17-08 no vanish or compensating hit")
	assert_eq(s["records"].size(), 0, "ED-17-08 no compensating settlement")
	assert_eq(_of(s["derive"]["records"], "created", "kind").size(), 0, "ED-17-08 no derivation")
	var control: Dictionary = _pair(_variant(c, {"stop_now": false, "ticks": 2}))
	assert_eq(_of(control["events"], "vanish").size(), 1, "ED-17-08 natural expiry control emits vanish")
	assert_eq(_of(control["derive"]["records"], "created", "kind").size(), 1, "ED-17-08 configured end rule really creates child without purge")
	assert_eq(_of(control["events"], "hit").size(), 1, "ED-17-08 unpurged control really hits before expiry")


func test_ed17_09_displacement_gate_buffer_recovery_and_expiry() -> void:
	const InputHostScript = preload("res://skill_core/runtime/hosts/preview_input_host.gd")
	var traces: Array = []
	for window in [3, 1]:
		var prepared: Dictionary = _prepare(_case(9))
		prepared["cfg"]["params"]["templates"][0]["cast"] = {"windup_ticks": 1,
			"shot_ticks": [1], "shot_count": 1, "cooldown_seconds": 1}
		var buffered_template: Dictionary = prepared["cfg"]["params"]["templates"][0].duplicate(true)
		buffered_template["template_id"] = "buffered_recipe"
		prepared["cfg"]["params"]["templates"].append(buffered_template)
		prepared["options"]["template_families"]["buffered_recipe"] = "split_family"
		prepared["options"]["derivation_bindings"]["buffered_recipe"] = {}
		var before: String = JSON.stringify(prepared["cfg"])
		var host: RefCounted = InputHostScript.new()
		assert_true(host.configure({"input_buffer": {"window_ticks": window}})["ok"])
		prepared["options"]["runtime_host"] = host
		var runner: RefCounted = Runner.new()
		assert_true(runner.start(prepared["cfg"], prepared["options"])["ok"])
		assert_true(host.set_locks({"cast_gate": true, "pause_cast": false, "interrupts_cast": false})["ok"])
		var request: Dictionary = host.request_cast({"template_id": "buffered_recipe", "shot_id": "buffered"})
		assert_false(request["ok"], "ED-17-09 gate refuses to start windup")
		assert_true(request.get("buffered", false), "ED-17-09 input host retains the request")
		# Source :8846-8847 expires at the deadline tick; recover strictly before it.
		assert_true(runner.advance_ticks(1)["ok"])
		assert_eq(runner.snapshot_state()["entities"].size(), 1, "ED-17-09 only original scheduled cast exists")
		assert_eq(host.snapshot_state()["pending"].size(), 1 if window == 3 else 0)
		assert_true(host.set_locks({"cast_gate": false, "pause_cast": false, "interrupts_cast": false})["ok"])
		assert_true(runner.advance_ticks(1)["ok"])
		assert_eq(host.snapshot_state()["actions"].size(), 2 if window == 3 else 1,
			"ED-17-09 recovery at tick2 executes only the unexpired request")
		assert_true(runner.advance_ticks(1)["ok"])
		var state: Dictionary = runner.snapshot_state()
		assert_eq(state["clock"]["tick"], 3)
		assert_eq(state["entities"].size(), 2 if window == 3 else 1, "ED-17-09 actual buffered release at tick3 vs discard")
		assert_eq(host.snapshot_state()["discarded"].size(), 0 if window == 3 else 1)
		assert_eq(host.snapshot_state()["pending"].size(), 0)
		assert_eq(JSON.stringify(prepared["cfg"]), before, "ED-17-09 CFG immutable")
		traces.append(state)
		runner.stop()
	assert_eq(traces.size(), 2, "ED-17-09 both concrete window outcomes observed")
	assert_ne(traces[0]["entities"].size(), traces[1]["entities"].size())


func test_ed17_10_control_pause_resume_vs_cancel() -> void:
	const InputHostScript = preload("res://skill_core/runtime/hosts/preview_input_host.gd")
	var outcomes: Array = []
	for interrupt in [false, true]:
		var prepared: Dictionary = _prepare(_case(10))
		prepared["cfg"]["params"]["templates"][0]["cast"] = {"windup_ticks": 3,
			"shot_ticks": [3, 5], "shot_count": 2, "cooldown_seconds": 1}
		var before: String = JSON.stringify(prepared["cfg"])
		var host: RefCounted = InputHostScript.new()
		assert_true(host.configure({"input_buffer": {"window_ticks": 3}})["ok"])
		prepared["options"]["runtime_host"] = host
		var runner: RefCounted = Runner.new()
		assert_true(runner.start(prepared["cfg"], prepared["options"])["ok"])
		assert_true(runner.advance_ticks(1)["ok"])
		assert_true(host.set_locks({"cast_gate": true, "pause_cast": true, "interrupts_cast": interrupt})["ok"])
		for tick in [2, 3]:
			assert_true(runner.advance_ticks(1)["ok"])
			assert_eq(runner.snapshot_state()["clock"]["tick"], tick)
			assert_eq(runner.snapshot_state()["entities"].size(), 0, "ED-17-10 control prevents release at both concrete ticks")
			var action: Dictionary = host.snapshot_state()["actions"][0]
			assert_eq(action["state"]["status"], "cancelled" if interrupt else "active")
			if not interrupt:
				assert_eq(3 - (tick - int(action["state"]["start_tick"])), 2, "ED-17-10 remaining windup frozen")
		assert_true(host.set_locks({"cast_gate": false, "pause_cast": false, "interrupts_cast": false})["ok"])
		var counts: Array = []
		for tick in [4, 5, 6, 7]:
			assert_true(runner.advance_ticks(1)["ok"])
			assert_eq(runner.snapshot_state()["clock"]["tick"], tick)
			counts.append(runner.snapshot_state()["entities"].size())
		assert_eq(counts, [0, 0, 0, 0] if interrupt else [0, 1, 1, 2], "ED-17-10 resumed shots tick5/7 vs cancelled unshot points")
		assert_eq(host.snapshot_state()["X"], 0 if interrupt else 2)
		outcomes.append(counts)
		assert_true(runner.stop()["ok"])
		assert_eq(JSON.stringify(prepared["cfg"]), before, "ED-17-10 runtime controls do not modify CFG")
	assert_eq(outcomes.size(), 2)
	assert_ne(outcomes[0], outcomes[1], "ED-17-10 pause is observably different from interrupt")


func test_ed17_11_blocked_owner_death_interrupt_priority() -> void:
	_blocked(11)


func test_ed17_12_three_actions_six_shots_separate_ledgers() -> void:
	const InputHostScript = preload("res://skill_core/runtime/hosts/preview_input_host.gd")
	var c: Dictionary = _variant(_case(12), {"root_count": 3, "distinct_shots": true,
		"targets": [{"id": "victim", "x": 1, "hp": 7}],
		"parts": [{"part_index": 0, "type": "physical", "amount": 1, "evadable": true},
			{"part_index": 1, "type": "fire", "amount": 1, "evadable": true},
			{"part_index": 2, "type": "ice", "amount": 1, "evadable": true}]})
	var results: Array = []
	for _repeat in range(2):
		var prepared: Dictionary = _prepare(c)
		prepared["cfg"]["params"]["templates"][0]["cast"] = {"windup_ticks": 0,
			"shot_ticks": [0, 2], "shot_count": 2, "cooldown_seconds": 0.01}
		for root in prepared["options"]["roots"]:
			root["instance_count"] = 3
		var before: String = JSON.stringify(prepared["cfg"])
		var host: RefCounted = InputHostScript.new()
		assert_true(host.configure({"input_buffer": {"window_ticks": 3}})["ok"])
		prepared["options"]["runtime_host"] = host
		var runner: RefCounted = Runner.new()
		assert_true(runner.start(prepared["cfg"], prepared["options"])["ok"])
		assert_eq(runner.snapshot_state()["entities"].size(), 3, "ED-17-12 first actual shot creates three instances")
		assert_true(runner.advance_ticks(9)["ok"])
		var ledger: Dictionary = host.snapshot_state()
		var state: Dictionary = runner.snapshot_state()
		assert_eq(ledger["actions"].size(), 3, "ED-17-12 three real FIFO actions")
		assert_eq(ledger["X"], 6, "ED-17-12 X counts actual shot emissions, not instances")
		assert_eq(ledger["shots"].size(), 6)
		var shot_ticks: Array = []
		var shot_ids: Array = []
		for shot in ledger["shots"]:
			shot_ticks.append(shot["tick"])
			assert_false(shot_ids.has(shot["shot_id"]), "ED-17-12 every actual shot has its own identity")
			shot_ids.append(shot["shot_id"])
		assert_eq(shot_ticks, [0, 2, 3, 5, 6, 8])
		for action in ledger["actions"]:
			assert_eq(action["state"]["next_index"], 2, "ED-17-12 two completed shot points per action")
			assert_eq(action["state"]["status"], "done")
		assert_eq(state["entities"].size(), 18, "ED-17-12 six shots each spawn three instances")
		assert_eq(_of(state["events"], "hit").size(), 3, "ED-17-12 finite victim dies on third hit, X remains six")
		assert_eq(state["records"].size(), 3)
		var part_count: int = 0
		for record in state["records"]:
			part_count += record["parts"].size()
		assert_eq(part_count, 9, "ED-17-12 nine settlement parts, not X or instance count")
		assert_eq(state["targets"][0]["hp"], 0.0)
		results.append({"host": ledger, "runner": state})
		assert_true(runner.stop()["ok"])
		assert_eq(JSON.stringify(prepared["cfg"]), before, "ED-17-12 ledgers never write into CFG")
	assert_eq(results.size(), 2)
	assert_eq(results[0], results[1], "ED-17-12 all runtime ledgers deterministic")


func test_ed17_13_blocked_all_evade_shotgun_contact_registration() -> void:
	var c: Dictionary = _case(13)
	assert_eq(c["status"], "blocked", "ED-17-13 known semantic capability gap")
	var s: Dictionary = _pair(c)
	assert_eq(s["entities"].size(), 2, "ED-17-13 real same-shot roots, distinct root families")
	assert_eq(_of(s["events"], "hit").size(), 0, "ED-17-13 all evaded no hit")
	assert_eq(_of(s["records"], "evaded_all").size(), 2, "ED-17-13 BLOCKED probe: first evade fails to suppress second (required count is 1)")
	var plain: Dictionary = _variant(c, {"targets": [{"id": "victim", "x": 0}]})
	var same: Dictionary = _pair(plain)
	assert_eq(_of(same["events"], "hit").size(), 1, "ED-17-13 successful-hit suppression positive control")
	var different: Dictionary = _pair(_variant(plain, {"distinct_shots": true}))
	assert_eq(_of(different["events"], "hit").size(), 2, "ED-17-13 distinct shots not suppressed")
	var evading_different: Dictionary = _pair(_variant(c, {"distinct_shots": true}))
	assert_eq(_of(evading_different["records"], "evaded_all").size(), 2, "ED-17-13 actual missing all-evaded distinction")


func test_ed17_14_legal_split_then_evade_consumes_family_contact() -> void:
	var c: Dictionary = _case(14)
	var s: Dictionary = _pair(c)
	assert_false(str(c["legal_split_entry"]).is_empty(), "ED-17-14 legal source documented")
	var children: Array = _of(s["derive"]["records"], "created", "kind")
	assert_eq(children.size(), 2, "ED-17-14 two REAL hit-derived children")
	var hits: Array = _of(s["events"], "hit")
	assert_eq(hits.size(), 1, "ED-17-14 only legal source hit, not all-evaded derivation")
	var evades: Array = _of(s["records"], "evaded_all")
	assert_eq(evades.size(), 1, "ED-17-14 sibling must not settle or reroll same family target")
	assert_eq(s["entities"].size(), 3, "ED-17-14 root plus real siblings")
	if hits.size() != 1 or evades.size() != 1 or s["entities"].size() != 3:
		return
	assert_eq(hits[0]["target_id"], "split_source", "ED-17-14 split source is a different non-evading target")
	assert_eq(hits[0]["tick"], 1, "ED-17-14 legal hit at tick1")
	assert_eq(evades[0]["target_id"], "evader", "ED-17-14 first child all evaded target")
	assert_eq(evades[0]["tick"], 2, "ED-17-14 first eligible child tick")
	assert_ne(evades[0]["body_id"], hits[0]["body_id"], "ED-17-14 evading member is child, not a fake mother split")
	for entity in s["entities"].values():
		if entity["template_id"] == "child_recipe":
			assert_eq(entity["spawn_tick"], 2, "ED-17-14 actual child next-tick birth")
			assert_eq(entity["parent_ref"], hits[0]["body_id"], "ED-17-14 actual parent linkage")
	assert_eq(s["targets"][1]["hp"], 100.0, "ED-17-14 evade plus sibling suppression no damage")
	var control: Dictionary = _pair(_variant(c, {"targets": [{"id": "split_source", "x": 1}, {"id": "evader", "x": 2}]}))
	assert_eq(_of(control["events"], "hit").size(), 2, "ED-17-14 without evade, child really reaches same target")
	assert_eq(control["targets"][1]["hp"], 90.0, "ED-17-14 child reachability nonvacuous control")


func test_ed17_15_blocked_split_pierce_chain_collision_policy() -> void:
	_blocked(15)


func test_ed17_16_blocked_current_target_state_update() -> void:
	_blocked(16)


func test_ed17_17_blocked_nominal_heal_shield_link() -> void:
	var c: Dictionary = _case(17)
	_blocked(17)
	var patch: Dictionary = {"parts": [{"part_index": 0, "type": "heal", "amount_profile": "nominal_heal", "evadable": false}]}
	var first: Dictionary = _rejection(c, patch, "params.templates[0]", "Unresolved settlement profile adapter: amount_profile")
	assert_eq(first, _rejection(c, patch, "params.templates[0]", "Unresolved settlement profile adapter: amount_profile"), "ED-17-17 profile refusal reproducible")


func test_ed17_18_blocked_shield_seq_and_single_hit_end() -> void:
	var c: Dictionary = _case(18)
	var state: Dictionary = _pair(c)
	assert_eq(c["status"], "blocked", "ED-17-18 attached shield lifecycle still missing")
	assert_eq(state["entities"].size(), 1, "ED-17-18 valid independent control creates one body")
	assert_eq(_of(state["events"], "hit").size(), 1, "ED-17-18 valid control actually hits")
	var first: Dictionary = _rejection(c, c["input"]["reject_patch"],
		"params.templates[0].attached", "Host adapter not implemented: attached")
	assert_true(first["error"].contains("Host adapter"), "ED-17-18 missing host adapter")
	assert_true(first["error"].contains("attached"), "ED-17-18 missing attached section")
	assert_eq(first, _rejection(c, c["input"]["reject_patch"],
		"params.templates[0].attached", "Host adapter not implemented: attached"),
		"ED-17-18 attached refusal reproducible")


func test_ed17_19_partial_skill_cooldown_but_atomic_equipment_absent() -> void:
	var c: Dictionary = _case(19)
	# 原为缺口探针；T-080 转正：装配已由新实例消费，正向验收仍保留历史函数名。
	assert_eq(c["status"], "ok", "ED-17-19 is now a positive acceptance case")
	var cast: Dictionary = {"windup_ticks": 0, "shot_ticks": [1], "shot_count": 1, "cooldown_seconds": 1}
	assert_eq(cast["shot_ticks"], [1], "ED-17-19 nonempty scheduled-shot control")
	var scheduled: Dictionary = _variant(c, {"root": {"cast": cast}, "ticks": 2})
	var first: Dictionary = _run(scheduled)
	assert_eq(first, _run(scheduled), "ED-17-19 every scheduled snapshot reproducible")
	var trace: Array = first["trace"]
	assert_eq(trace.size(), 3, "ED-17-19 tick0 plus two ticks")
	var counts: Array = []
	var increments: Array = []
	var previous: int = 0
	for index in range(trace.size()):
		assert_eq(trace[index]["clock"]["tick"], index, "ED-17-19 exact observed tick")
		var current: int = trace[index]["entities"].size()
		counts.append(current)
		if index > 0:
			increments.append(current - previous)
		previous = current
	assert_eq(counts, [0, 1, 1], "ED-17-19 real root released at tick1")
	assert_eq(increments, [1, 0], "ED-17-19 release adds exactly one root")
	assert_eq(first["state"]["entities"].size(), 1, "ED-17-19 runner positive control creates a body")

	# Source :2667 separates skill and equipment cooldowns. Test the real adapter,
	# not Runner.start's stop-first guard, and never claim equipment cooldown PASS.
	const HostCastScript = preload("res://skill_core/runtime/hosts/host_cast.gd")
	var results: Array = []
	for _repeat in range(2):
		var host: RefCounted = HostCastScript.new()
		var ctx: Dictionary = {"template_id": "root_recipe", "shot_id": "shot_a", "tick": 0, "tick_rate": 60}
		var begun: Dictionary = host.begin(cast, ctx)
		assert_true(begun["ok"], "ED-17-19 real host begin: " + str(begun))
		if not begun["ok"]:
			continue
		var state: Dictionary = begun["state"]
		assert_eq(state["cooldown_ticks"], 60, "ED-17-19 one second at 60Hz")
		var zero: Dictionary = host.advance(state, 0, ctx)
		assert_true(zero["ok"], "ED-17-19 host tick0")
		assert_eq(zero["emissions"]["spawn"].size(), 0, "ED-17-19 no early host spawn")
		var release: Dictionary = host.advance(state, 1, ctx)
		assert_true(release["ok"], "ED-17-19 host tick1")
		assert_eq(release["emissions"]["spawn"], [{"template_id": "root_recipe", "shot_id": "shot_a", "origin": {}, "parent_ref": ""}],
			"ED-17-19 actual one-shot host emission")
		assert_eq(state["status"], "done", "ED-17-19 last release completed")
		var rejected: Array = []
		for tick in [1, 60]:
			ctx["tick"] = tick
			var retry: Dictionary = host.begin(cast, ctx)
			assert_false(retry["ok"], "ED-17-19 skill cooldown rejects begin at tick%d" % tick)
			assert_eq(retry["code"], "CAST_COOLDOWN", "ED-17-19 rejection is cooldown, not lifecycle")
			assert_eq(retry["path"], "cooldown_seconds", "ED-17-19 real skill cooldown path")
			assert_eq(retry["error"], "Cast is cooling down; remaining ticks: %d" % (61 - tick),
				"ED-17-19 exact remaining ticks at tick%d" % tick)
			rejected.append(retry)
		ctx["tick"] = 61
		var reopened: Dictionary = host.begin(cast, ctx)
		assert_true(reopened["ok"], "ED-17-19 skill cooldown expires exactly at tick61")
		if not reopened["ok"]:
			continue
		var next_state: Dictionary = reopened["state"]
		var next_release: Dictionary = host.advance(next_state, 62, ctx)
		assert_true(next_release["ok"], "ED-17-19 second accepted host cast advances")
		assert_eq(next_release["emissions"]["spawn"].size(), 1, "ED-17-19 after cooldown actual second spawn, not only begin.ok")
		results.append({"rejected": rejected, "next_release": next_release})
	assert_eq(results.size(), 2, "ED-17-19 both real cooldown runs completed")
	if results.size() == 2:
		assert_eq(results[0], results[1], "ED-17-19 cooldown results reproducible")

	var runner: RefCounted = Runner.new()
	var native_names: Array = []
	for method in RefCounted.new().get_method_list():
		native_names.append(str(method["name"]))
	var script_names: Array = []
	for method in runner.get_script().get_script_method_list():
		script_names.append(str(method["name"]))
	var methods: Array = []
	for method in runner.get_method_list():
		var name: String = str(method["name"])
		if not name.begins_with("_") and (script_names.has(name) or not native_names.has(name)):
			methods.append(name)
	methods.sort()
	assert_eq(methods, PUBLIC_API, "ED-17-19 complete public sandbox API frozen")
	assert_eq(methods.size(), 6, "ED-17-19 exactly six public entries")
	for index in range(mini(methods.size(), PUBLIC_API.size())):
		assert_eq(methods[index], PUBLIC_API[index], "ED-17-19 public entry %d" % index)
	# Source :6890 原子替换; :2663 装配公共冷却. No invented equipment API name.
	var candidates: Array = ["原子替换", "装配公共冷却"]
	assert_eq(candidates.size(), 2, "ED-17-19 nonempty source-vocabulary probe")
	for name in candidates:
		assert_false(methods.has(name), "ED-17-19 absent source capability " + str(name))
		assert_false(runner.has_method(name), "ED-17-19 no atomic-equipment/global-cooldown entry " + str(name))
	# Runtime capabilities can also enter through start(options.runtime_host).
	const InputHostScript = preload("res://skill_core/runtime/hosts/preview_input_host.gd")
	var input_host: RefCounted = InputHostScript.new()
	var host_methods: Array = []
	for method in input_host.get_script().get_script_method_list():
		var name: String = str(method["name"])
		if not name.begins_with("_"):
			host_methods.append(name)
	host_methods.sort()
	# T-076 第 3 轮按 U-29 增量扩权新增了四个装配窄入口（apply_equipment_boundary /
	# configure_equipment / request_equipment_changes / equipment_snapshot）。
	# 缺口探针的既有裁定：能力落地后探针应当变红，此时改为记录真实清单，
	# 不得反向改 core 恢复旧行为。ED-17-19 整体仍 blocked（见本函数首条断言），
	# 这四个入口是窄骨架，不是原子换装与装配公共冷却的完整交付。
	assert_eq(host_methods, ["apply_equipment_boundary", "configure", "configure_equipment",
			"equipment_snapshot", "request_cast", "request_equipment_changes",
			"set_locks", "snapshot_state"],
		"ED-17-19 input host equipment entries landed narrow by T-076; full chain still blocked")


func test_ed17_20_blocked_live_permission_runner_integration() -> void:
	_blocked(20)


func test_ed17_21_blocked_passive_feedback_subscription() -> void:
	var s: Dictionary = _blocked(21)
	assert_eq(_of(s["records"], "hit_settled").size(), 1, "ED-17-21 actual source record exists, not an empty subscription proof")


func test_ed17_22_blocked_summon_owner_lifecycle_adapter() -> void:
	var c: Dictionary = _case(22)
	var state: Dictionary = _pair(c)
	assert_eq(c["status"], "blocked", "ED-17-22 summon owner lifecycle still missing")
	assert_eq(state["entities"].size(), 1, "ED-17-22 valid independent control creates one body")
	assert_eq(_of(state["events"], "hit").size(), 1, "ED-17-22 valid control actually hits")
	var first: Dictionary = _rejection(c, c["input"]["reject_patch"],
		"params.templates[0].summon", "Host adapter not implemented: summon")
	assert_true(first["error"].contains("Host adapter"), "ED-17-22 missing host adapter")
	assert_true(first["error"].contains("summon"), "ED-17-22 missing summon section")
	assert_eq(first, _rejection(c, c["input"]["reject_patch"],
		"params.templates[0].summon", "Host adapter not implemented: summon"),
		"ED-17-22 summon refusal reproducible")


func test_ed17_23_blocked_presentation_budget_with_real_body_drop() -> void:
	var c: Dictionary = _case(23)
	_blocked(23)
	var results: Array = []
	for _repeat in range(2):
		var prepared: Dictionary = _prepare(_variant(c, {"root_count": 2, "distinct_shots": true}))
		prepared["cfg"]["params"]["cast_budget"] = 1
		var before: String = JSON.stringify(prepared["cfg"])
		var runner: RefCounted = Runner.new()
		assert_true(runner.start(prepared["cfg"], prepared["options"])["ok"], "ED-17-23 tight body budget run: " + runner.last_error)
		var state: Dictionary = runner.snapshot_state()
		assert_eq(state["entities"].size(), 1, "ED-17-23 new root actually denied, existing root retained")
		assert_eq(state["budget"].get("drops", []).size(), 1, "ED-17-23 real body refusal recorded")
		assert_eq(_of(state["events"], "hit").size(), 1, "ED-17-23 only admitted root hit")
		assert_eq(_of(state["events"], "vanish").size(), 0, "ED-17-23 no fake vanish for unborn root")
		runner.stop()
		assert_eq(JSON.stringify(prepared["cfg"]), before, "ED-17-23 body-drop CFG unchanged")
		results.append(state)
	assert_eq(results[0], results[1], "ED-17-23 body-drop probe snapshots deterministic")
	var unlimited: Dictionary = _pair(_variant(c, {"root_count": 2, "distinct_shots": true}))
	assert_eq(_of(unlimited["events"], "hit").size(), 2, "ED-17-23 control shows REAL truncation difference; never claims logic equal")


func _logic(state: Dictionary) -> Dictionary:
	var copy: Dictionary = state.duplicate(true)
	copy["clock"].erase("presentation_rng")
	return copy


func test_ed17_24_blocked_pause_scale_but_replay_and_visual_rng_probed() -> void:
	var c: Dictionary = _case(24)
	_blocked(24)
	var plain: Dictionary = _run(c)
	var noisy: Dictionary = _run(c, 17)
	assert_eq(plain["trace"].size(), 6, "ED-17-24 start plus five actual ticks")
	assert_eq(noisy["trace"].size(), plain["trace"].size(), "ED-17-24 same trace length")
	if noisy["trace"].size() != plain["trace"].size():
		return
	for index in range(plain["trace"].size()):
		assert_eq(_logic(plain["trace"][index]), _logic(noisy["trace"][index]), "ED-17-24 presentation draws cannot perturb logic tick %d" % index)
	var batched: Dictionary = _run(c, 0, true)
	assert_eq(_logic(plain["state"]), _logic(batched["state"]), "ED-17-24 tick batch size/render grouping cannot change final logic")
	assert_ne(plain["state"]["clock"]["presentation_rng"], noisy["state"]["clock"]["presentation_rng"], "ED-17-24 visual RNG really consumed; not an empty comparison")
	assert_ne(plain["trace"][0]["clock"]["logic_rng"], plain["state"]["clock"]["logic_rng"], "ED-17-24 probabilistic contact really consumed logic RNG")
