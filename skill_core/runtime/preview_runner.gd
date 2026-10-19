class_name PreviewRunner extends RefCounted

## One deterministic, headless sandbox. CFG stays author data; options contains
## resolved host inputs/strategies, never additional author-facing CFG fields.
const Clock = preload("res://skill_core/runtime/sim_clock.gd")
const Body = preload("res://skill_core/runtime/effect_body.gd")
const Motion = preload("res://skill_core/runtime/motion.gd")
const Shape = preload("res://skill_core/runtime/shape_hit.gd")
const Settle = preload("res://skill_core/runtime/settle.gd")
const Derive = preload("res://skill_core/runtime/derive.gd")
const Family = preload("res://skill_core/runtime/family_ledger.gd")
const Summon = preload("res://skill_core/runtime/summon.gd")
const Budget = preload("res://skill_core/runtime/budget.gd")
const Resolver = preload("res://skill_core/resolve/param_resolver.gd")
const Codec = preload("res://skill_core/schema/cfg_codec.gd")
const Schema = preload("res://skill_core/schema/cfg_schema.gd")
const HostRegistry = preload("res://skill_core/runtime/hosts/host_registry.gd")
const HostCast = preload("res://skill_core/runtime/hosts/host_cast.gd")
const InputHost = preload("res://skill_core/runtime/hosts/preview_input_host.gd")
const CONFIG_PATH: String = "res://data/project_config.json"

# Implementation dispatch, not a skill/brick whitelist. Other motion kernels
# require host adapters not included in this increment; fail closed at start.
const FINISH_REASONS: Dictionary = {"straight": Body.REASON_RANGE_END, "lob": Body.REASON_LANDED}
const FAMILY_BINDINGS: Dictionary = {"family": {"id": "family_id"},
	"shotgun": {"shot": "shot_id", "independent": "independent", "allow": "shotgun_allowed"}}

var last_error: String = ""
var _running: bool = false
var _run_seq: int = 0
var _root_seq: int = 0
var _cast_id: String = ""
var _cfg: Dictionary = {}
var _params: Dictionary = {}
var _config: Dictionary = {}
var _fingerprint: String = ""
var _tick_rate: int = 0
var _clock: RefCounted
var _derive: RefCounted
var _budget: RefCounted
var _family: RefCounted
var _templates: Dictionary = {}
var _entities: Dictionary = {}
var _facts: Dictionary = {}
var _families: Dictionary = {}
var _motion_inputs: Dictionary = {}
var _handlers: Dictionary = {}
var _targets: Array = []
var _events: Array = []
var _records: Array = []
var _notices: Array = []
var _derive_meta: Dictionary = {}
var _settle_meta: Dictionary = {}
var _shape_meta: Dictionary = {}
var _hosts: RefCounted
var _host_states: Dictionary = {}
var _host_requests: Dictionary = {}
var _host_contexts: Dictionary = {}
var _runtime_host: RefCounted


## Required options: seed:int, roots:[{template_id, shot_id, instance_id?}],
## targets:[runtime target], handlers: Settle host adapter table,
## template_families:{template_id:resolved family key}, derivation_bindings:
## Derive.configure's resolved routing table. Optional: project_config (REPLACE,
## not merge with file), motion_inputs:{template_id: Motion.configure inputs}.
## motion_inputs.flight_seconds is a host flight-duration input converted once
## to flight_ticks; supplying both is an error, never a second authority.
func start(cfg: Variant, options: Dictionary) -> Dictionary:
	if _running:
		return {"ok": false, "path": "start", "error": "Stop the current preview before starting another", "diagnostics": []}
	_clear()
	var diagnostics: Array = Codec.validate_structure(cfg)
	if not diagnostics.is_empty():
		return _failure("cfg", "CFG structure rejected", diagnostics)
	var schema: RefCounted = Schema.new()
	if not schema.configure():
		return _failure("schema", schema.last_error)
	var checked: Dictionary = schema.validate(cfg)
	if not checked["ok"]:
		return _failure("cfg", "CFG schema rejected", checked["diagnostics"])
	_cfg = cfg.duplicate(true)
	_fingerprint = JSON.stringify(_cfg, "", true, true).sha256_text()
	var resolved: Dictionary = Resolver.new().resolve(_cfg)
	if not resolved["ok"]:
		return _failure("params", "Parameter resolution rejected", resolved["diagnostics"])
	var params: Variant = resolved["resolved"].get("params", null)
	if not params is Dictionary:
		return _failure("params", "No resolved params")
	_params = params.duplicate(true)
	var configuration: Variant = options.get("project_config", null)
	if not options.has("project_config"):
		configuration = _read_json(CONFIG_PATH)
	if not configuration is Dictionary:
		return _failure("project_config", "Missing project configuration object")
	_config = configuration.duplicate(true)
	var rate: Variant = _config.get("tick_rate", null)
	if not _integer_number(rate) or rate < 1:
		return _failure("project_config.tick_rate", "A positive integral tick rate is required; no fallback")
	_tick_rate = int(rate)
	var limits: Variant = _config.get("project_limits", null)
	if not limits is Dictionary:
		return _failure("project_config.project_limits", "Missing project limits")
	var overrides: Dictionary = {}
	for section in ["hard_caps", "defaults"]:
		var entries: Variant = limits.get(section, null)
		if not entries is Dictionary or entries.is_empty():
			return _failure("project_config.project_limits." + section, "Missing nonempty limit section")
		var values: Dictionary = {}
		for key in entries:
			if str(key).begins_with("_"):
				continue
			if not _integer_number(entries[key]) or entries[key] < 0:
				return _failure("project_config.project_limits." + section + "." + str(key), "Expected nonnegative integer")
			# JSON numbers are floats; runtime modules require injected integers.
			values[key] = int(entries[key])
		overrides[section] = values
	var seed_value: Variant = options.get("seed", null)
	if not seed_value is int:
		return _failure("seed", "Explicit integer logic seed required")
	_clock = Clock.new(seed_value)
	var runtime_host: Variant = options.get("runtime_host", null)
	_runtime_host = runtime_host
	if runtime_host != null:
		if not runtime_host is InputHost:
			return _failure("runtime_host", "Expected preview input host")
	_derive_meta = _read_json(Derive.META_PATH)
	_settle_meta = _read_json(Settle.META_PATH)
	_shape_meta = _read_json(Shape.META_PATH)
	if _derive_meta.is_empty() or _settle_meta.is_empty() or _shape_meta.is_empty():
		return _failure("metadata", "Missing derivation, shape or settlement metadata")
	_hosts = HostRegistry.new()
	_host_states.clear()
	_host_requests.clear()
	_host_contexts.clear()
	var registered: Dictionary = _hosts.register("cast", HostCast.new())
	if not registered["ok"]:
		return _failure("hosts.cast", registered["error"])
	for key in ["handlers", "template_families", "motion_inputs", "derivation_bindings"]:
		var value: Variant = options.get(key, null)
		if key == "motion_inputs" and value == null:
			value = {}
		if not value is Dictionary:
			return _failure(key, "Expected resolved runtime table")
	_handlers = options["handlers"].duplicate()
	_families = options["template_families"].duplicate(true)
	var input_table: Variant = options.get("motion_inputs", null)
	_motion_inputs = input_table.duplicate(true) if input_table is Dictionary else {}
	for id in _motion_inputs:
		if not _motion_inputs[id] is Dictionary:
			return _failure("motion_inputs." + str(id), "Expected motion inputs object")
		var inputs: Dictionary = _motion_inputs[id]
		if inputs.has("flight_seconds"):
			if inputs.has("flight_ticks") or not _number(inputs["flight_seconds"]) or inputs["flight_seconds"] <= 0:
				return _failure("motion_inputs." + str(id) + ".flight_seconds", "Require positive seconds and no flight_ticks")
			var flight_ticks: float = ceil(float(inputs["flight_seconds"]) * _tick_rate)
			if not _integer_number(flight_ticks) or flight_ticks < 1:
				return _failure("motion_inputs." + str(id) + ".flight_seconds", "Flight duration overflows tick representation")
			inputs["flight_ticks"] = int(flight_ticks)
			inputs.erase("flight_seconds")
	var templates: Variant = _params.get("templates", null)
	if not templates is Array or templates.is_empty():
		return _failure("params.templates", "A nonempty template registry is required")
	for index in range(templates.size()):
		var template: Dictionary = templates[index]
		var id: String = template["template_id"]
		if id.is_empty() or _templates.has(id):
			return _failure("params.templates[%d].template_id" % index, "Missing or duplicate template identity")
		if not _families.get(id, null) is String or _families[id].is_empty():
			return _failure("template_families." + id, "Explicit resolved family identity required")
		# Only registered hosts may schedule roots; unused templates are preflighted.
		for section in ["cast", "timing", "attached", "summon", "emission"]:
			if template.has(section) and not template[section].is_empty():
				var host_path: String = "params.templates[%d].%s" % [index, section]
				if not _hosts.has_adapter(section):
					return _failure(host_path, "Host adapter not implemented: " + section)
				var request: Dictionary = template[section].duplicate(true)
				var ctx: Dictionary = {"template_id": id, "tick": 0, "tick_rate": _tick_rate}
				var validated: Dictionary = _hosts.validate(section, request, ctx)
				if not validated["ok"]:
					stop()
					last_error = validated["error"]
					validated["path"] = host_path + "." + validated["path"]
					return validated
				var launches: Variant = options.get("roots", null)
				if not launches is Array or launches.is_empty():
					return _failure("roots", "Explicit nonempty root launch list required")
				for launch_index in range(launches.size()):
					var host_launch: Variant = launches[launch_index]
					if not host_launch is Dictionary:
						return _failure("roots", "Each launch needs a registered template_id and actual shot_id")
					var launch_template: Variant = host_launch.get("template_id", null)
					if launch_template is String and launch_template == id:
						if _runtime_host != null:
							continue
						var host_key: String = "%s:%d" % [id, launch_index]
						var launch_ctx: Dictionary = ctx.duplicate(true)
						launch_ctx["shot_id"] = host_launch.get("shot_id", null)
						var begun: Dictionary = _hosts.begin(section, request, launch_ctx)
						if not begun["ok"]:
							stop()
							last_error = begun["error"]
							begun["path"] = host_path + "." + begun["path"]
							return begun
						_host_states[host_key] = begun["state"]
						_host_requests[host_key] = request.duplicate(true)
						_host_contexts[host_key] = launch_ctx
		if template["carrier"] != Body.CARRIER_INDEPENDENT or not template.get("motion", null) is Dictionary:
			return _failure("params.templates[%d].motion" % index, "This sandbox requires independent motion")
		if not FINISH_REASONS.has(template["motion"].get("mode", null)):
			return _failure("params.templates[%d].motion.mode" % index, "No sandbox termination adapter for this motion mode")
		_templates[id] = template.duplicate(true)
		var probe: RefCounted = Body.create(template["carrier"], template, 0)
		if probe == null or _build_entity(probe, id, null).is_empty():
			return _failure("params.templates[%d]" % index, "Runtime preflight failed: " + last_error)
	var targets: Variant = options.get("targets", null)
	if not targets is Array:
		return _failure("targets", "Explicit target roster required (empty is allowed)")
	_targets = targets.duplicate(true)
	if not _valid_targets():
		return _failure("targets", last_error)
	var root_inputs: Variant = options.get("roots", null)
	if not root_inputs is Array or root_inputs.is_empty():
		return _failure("roots", "Explicit nonempty root launch list required")
	var roots: Array = root_inputs.duplicate(true)
	for root in roots:
		if not root is Dictionary or not _templates.has(root.get("template_id", null)) or not root.get("shot_id", null) is String or root["shot_id"].is_empty():
			return _failure("roots", "Each launch needs a registered template_id and actual shot_id")
	_derive = Derive.new(Derive.META_PATH, null, Derive.PARAMS_PATH, Derive.LIMITS_PATH, overrides)
	if not _derive.configure(_params, _clock, options["derivation_bindings"]):
		return _failure("params", _derive.last_error)
	var roles: Dictionary = _derive_meta["budget_roles"]
	var capacity: int = int(_params.get(roles["cast"], overrides["defaults"][roles["cast"]]))
	_budget = Budget.new()
	if not _budget.configure(_budget_policy(capacity), overrides):
		return _failure("budget", _budget.last_error)
	_family = Family.new()
	if not _family.configure(_clock, FAMILY_BINDINGS):
		return _failure("family", _family.last_error)
	_cast_id = "preview:%d" % _run_seq
	_run_seq += 1
	if _runtime_host != null:
		var bound: Dictionary = _runtime_host._bind(_templates, roots, _tick_rate, _cfg["params"])
		if not bound["ok"]:
			return _failure(bound["path"], bound["error"])
	for launch in roots:
		var template: Dictionary = _templates[launch["template_id"]]
		if template.has("cast") and not template["cast"].is_empty():
			continue
		var launched: Dictionary = _launch_root(launch)
		if not launched["ok"]:
			return _failure(launched["path"], launched["error"])
		if not launched["admitted"]:
			continue
	var family_synced: bool = _family.sync_instances(_derive.snapshot_state(), _facts)
	if _entities.is_empty() and _host_states.is_empty() and _runtime_host == null:
		return _failure("family", _family.last_error)
	# The ledger rejects an empty source; pending hosts have no members yet.
	if not family_synced and not _entities.is_empty():
		return _failure("family", _family.last_error)
	_running = true
	if not _process_tick(false):
		return _failure("runtime", last_error)
	var advanced_hosts: Dictionary = _advance_hosts(0)
	if not advanced_hosts["ok"]:
		return advanced_hosts
	last_error = ""
	return {"ok": true, "fingerprint": _fingerprint, "tick_rate": _tick_rate, "diagnostics": [], "error": ""}


func _launch_root(launch: Dictionary) -> Dictionary:
	var id: String = "%s:root:%d" % [_cast_id, _root_seq]
	_root_seq += 1
	if launch.has("instance_id"):
		_notices.append({"path": "roots.instance_id", "suggested": launch["instance_id"], "assigned": id,
			"valid_suggestion": launch["instance_id"] is String and not launch["instance_id"].is_empty()})
	var admission: Dictionary = _budget.admit_root(id, [])
	if not admission["ok"]:
		return {"ok": false, "admitted": false, "id": id, "error": admission["error"], "path": "budget"}
	if not admission["admitted"]:
		return {"ok": true, "admitted": false, "id": id, "error": "", "path": ""}
	var template_id: String = launch["template_id"]
	var body_cfg: Dictionary = _templates[template_id].duplicate(true)
	body_cfg["body_id"] = id
	var equipment_value: Variant = launch.get("equipment_snapshot", null)
	var equipment_snapshot: Dictionary = equipment_value.duplicate(true) if equipment_value is Dictionary else {}
	var body: RefCounted = Body.create(body_cfg["carrier"], body_cfg, 0)
	if not _derive.register_root(body, template_id, {"origin_skill": _cfg["skill_id"], "origin_cast_id": _cast_id}):
		return {"ok": false, "admitted": false, "id": id, "error": _derive.last_error, "path": "roots"}
	var entity: Dictionary = _build_entity(body, template_id, null, equipment_snapshot)
	if entity.is_empty():
		_derive.purge(id)
		return {"ok": false, "admitted": false, "id": id,
			"error": "Runtime adapter initialization failed: " + last_error, "path": "roots"}
	_entities[id] = entity
	_facts[id] = {"family_id": id + ":" + _families[template_id], "shot_id": launch["shot_id"], "independent": true}
	return {"ok": true, "admitted": true, "id": id, "error": "", "path": ""}


func _build_entity(body: RefCounted, template_id: String, parent: Variant, equipment_snapshot: Variant = null) -> Dictionary:
	var template: Dictionary = _templates[template_id]
	var value: Variant = _motion_inputs.get(template_id, null)
	var inputs: Dictionary = value.duplicate(true) if value is Dictionary else {}
	var equipment: Dictionary = {}
	if parent is Dictionary:
		var inherited: Variant = parent.get("equipment_snapshot", null)
		if inherited is Dictionary:
			equipment = inherited.duplicate(true)
		inputs["position"] = parent["motion"].position
		inputs["direction"] = parent["motion"].direction
	if equipment_snapshot is Dictionary:
		equipment = equipment_snapshot.duplicate(true)
	var motion: RefCounted = Motion.new()
	if not motion.configure(template, body, _clock, inputs):
		last_error = motion.last_error
		return {}
	var shape: RefCounted = Shape.new()
	var settle: RefCounted = Settle.new()
	if not settle.configure(template, body, _clock, _handlers, Callable(), shape):
		last_error = settle.last_error
		return {}
	return {"body": body, "template_id": template_id, "motion": motion, "shape": shape, "settle": settle, "inputs": inputs,
		"equipment_snapshot": equipment}


func _valid_targets() -> bool:
	var seen: Dictionary = {}
	var roles: Dictionary = _settle_meta["target_roles"]
	for target in _targets:
		if not target is Dictionary or not target.get("target_id", null) is String or target["target_id"].is_empty():
			last_error = "Target requires target_id"
			return false
		if seen.has(target["target_id"]) or not target.get("position", null) is Vector2 or not target["position"].is_finite() or not target.get("alive", null) is bool:
			last_error = "Duplicate target or invalid position/alive"
			return false
		seen[target["target_id"]] = true
		if not target.get(roles["invulnerable"], null) is bool:
			last_error = "Target requires " + roles["invulnerable"]
			return false
		for role in ["evade", "immune"]:
			var table: Variant = target.get(roles[role], null)
			if not table is Dictionary:
				last_error = "Target requires " + roles[role]
				return false
			for key in table:
				if not key is String or (role == "immune" and not table[key] is bool) or (role == "evade" and (not _number(table[key]) or table[key] < 0 or table[key] > 1)):
					last_error = "Invalid target gate: " + roles[role]
					return false
	return true


## Both ledgers enforce the same project-injected upper bound, not additive
## charges: Budget admits new roots, Derive owns cumulative descendant charges.
## No post-creation child rejection/purge masquerades as budget admission.
func _budget_policy(capacity: int) -> Dictionary:
	return {"priorities": {"runtime_body": 0}, "root_cost": 1, "capacity": capacity,
		"debug_type": "debug_record", "debug_enabled": true,
		"fields": {"id": "id", "category": "category", "cost": "cost", "type": "type", "kind": "kind",
			"root": "root_id", "reason": "reason", "occupied": "occupied"},
		"ledger_keys": {"roots": "roots", "drops": "drops", "debug": "debug", "settlements": "settlements",
			"occupied": "occupied", "capacity": "capacity"}}


func _consume_emissions(emissions: Dictionary) -> Dictionary:
	for key in emissions:
		if not ["spawn", "attach", "events", "records"].has(key):
			return _failure("emissions." + str(key), "Unknown host emissions key: " + str(key))
	for key in ["spawn", "attach", "events", "records"]:
		if not emissions.get(key, null) is Array:
			return _failure("emissions." + key, "Expected host emissions array: " + key)
	if not emissions["attach"].is_empty():
		return _failure("emissions.attach", "Host adapter not implemented: attach")
	for launch in emissions["spawn"]:
		if not launch is Dictionary or not _templates.has(launch.get("template_id", null)) or not launch.get("shot_id", null) is String or launch["shot_id"].is_empty():
			return _failure("emissions.spawn", "Each launch needs a registered template_id and actual shot_id")
	for launch in emissions["spawn"]:
		var launched: Dictionary = _launch_root(launch)
		if not launched["ok"]:
			return _failure(launched["path"], launched["error"])
		if not launched["admitted"]:
			continue
	if not _entities.is_empty() and not _family.sync_instances(_derive.snapshot_state(), _facts):
		return _failure("family", _family.last_error)
	_events.append_array(emissions["events"].duplicate(true))
	_records.append_array(emissions["records"].duplicate(true))
	return {"ok": true, "error": ""}


func _advance_hosts(tick: int) -> Dictionary:
	if _runtime_host != null:
		var equipment_boundary: Dictionary = _runtime_host.apply_equipment_boundary(tick)
		if not equipment_boundary["ok"]:
			return _failure("runtime_host.equipment", equipment_boundary["error"])
		var result: Dictionary = _runtime_host._advance(tick)
		if not result["ok"]:
			return _failure("runtime_host", result["error"])
		return _consume_emissions(result["emissions"])
	for host_key in _host_states:
		var state: Dictionary = _host_states[host_key]
		var ctx: Dictionary = _host_contexts[host_key]
		var advanced: Dictionary = _hosts.advance("cast", state, tick, ctx)
		if not advanced["ok"]:
			stop()
			last_error = advanced["error"]
			return advanced
		_host_states[host_key] = advanced["state"]
		var consumed: Dictionary = _consume_emissions(advanced["emissions"])
		if not consumed["ok"]:
			return consumed
	return {"ok": true, "error": ""}


func advance_ticks(count: int = 1) -> Dictionary:
	if not _running or count < 0:
		return _failure("advance_ticks", "Requires running preview and nonnegative tick count")
	for _index in range(count):
		_clock.tick()
		if not _process_tick(true):
			return _failure("runtime", last_error)
		var advanced_hosts: Dictionary = _advance_hosts(_clock.snapshot_state()["tick"])
		if not advanced_hosts["ok"]:
			return advanced_hosts
	return {"ok": true, "tick": _clock.snapshot_state()["tick"], "error": ""}


## Explicit duration input, not rendering delta. Each call rounds upward just
## like SkillUnits; use advance_ticks for replay without repeated rounding.
func advance_seconds(seconds: float) -> Dictionary:
	if not _running or not is_finite(seconds) or seconds < 0:
		return _failure("advance_seconds", "Requires running preview and finite nonnegative seconds")
	var ticks: float = ceil(seconds * _tick_rate)
	if not _integer_number(ticks):
		return _failure("advance_seconds", "Duration overflows tick representation")
	return advance_ticks(int(ticks))


func _process_tick(move: bool) -> bool:
	var tick: int = _clock.snapshot_state()["tick"]
	# Registry insertion order is root FIFO, then Derive's monotonic seq FIFO.
	# Snapshot keys so new children never run on their parent's event tick.
	var ids: Array = _entities.keys()
	for id in ids:
		var entity: Dictionary = _entities[id]
		var body: RefCounted = entity["body"]
		var motion: RefCounted = entity["motion"]
		if not body.is_alive() or tick < body.spawn_tick:
			continue
		if tick < body.spawn_tick + body.lifetime_ticks:
			if move and not motion.step(entity["inputs"]):
				last_error = motion.last_error
				return false
			var roster: Array = []
			var contacts: Dictionary = {}
			for target in _targets:
				if not _contact_eligible(entity, target):
					continue
				var candidate: Dictionary = {"body_id": id, "target_id": target["target_id"], "tick": tick, "alive": true}
				var admitted: Dictionary = _family.admit(candidate)
				if not admitted["ok"]:
					last_error = admitted["error"]
					return false
				if not admitted["admitted"]:
					continue
				var gate: Dictionary = _family.may_hit(candidate)
				if not gate["ok"]:
					last_error = gate["error"]
					return false
				if gate["allowed"]:
					roster.append(target)
					contacts[target["target_id"]] = candidate
			var result: Dictionary = entity["settle"].step(roster, {"position": motion.position, "direction": motion.direction})
			if not result["ok"]:
				last_error = result["error"]
				return false
			for record in result["records"]:
				_records.append(record.duplicate(true))
				if not _budget.record_settlement(record):
					last_error = _budget.last_error
					return false
			for event in result["events"]:
				if not _family.record_hit(contacts[event["target_id"]]) or not _derive.enqueue_event(event):
					last_error = _family.last_error + _derive.last_error
					return false
		# Lifecycle expiration wins over range/landing when both occur this tick.
		var terminations: Array = body.step(tick)
		if terminations.is_empty() and body.is_alive() and motion.finished:
			body.state = Body.VANISHED
			var mode: String = _templates[entity["template_id"]]["motion"]["mode"]
			terminations.append({"type": _derive_meta["event_roles"]["termination"], "tick": tick,
				"body_id": id, "reason": FINISH_REASONS[mode]})
		for event in terminations:
			if not _derive.enqueue_event(event):
				last_error = _derive.last_error
				return false
	var drained: Dictionary = _derive.drain()
	if not drained["ok"]:
		last_error = drained["error"]
		return false
	_events.append_array(drained["events"].duplicate(true))
	var instance_states: Dictionary = _derive.snapshot_state()["instances"]
	for child in drained["children"]:
		var state: Dictionary = instance_states[child.body_id]
		var parent: Dictionary = _entities[child.parent_ref]
		var entity: Dictionary = _build_entity(child, state["template_id"], parent)
		if entity.is_empty():
			return false
		_entities[child.body_id] = entity
		_facts[child.body_id] = {"family_id": state["source_chain"][0] + ":" + _families[state["template_id"]], "independent": false}
	if not drained["children"].is_empty() and not _family.sync_instances(_derive.snapshot_state(), _facts):
		last_error = _family.last_error
		return false
	return true


## Do not reserve a family contact for a body that has already exhausted its
## own hit/target quota. Such a reservation would wrongly suppress a sibling.
func _contact_eligible(entity: Dictionary, target: Dictionary) -> bool:
	var motion: RefCounted = entity["motion"]
	if not target["alive"] or not entity["shape"].contains_point(target["position"], motion.position, motion.direction):
		return false
	var policy: Dictionary = _templates[entity["template_id"]]["hit_policy"]
	var roles: Dictionary = _shape_meta["policy_roles"]
	var state: Dictionary = entity["shape"].snapshot_state()
	var cap: Variant = policy.get(roles["hit_limit"], null)
	if cap != null and state["hit_count"] >= cap:
		return false
	var ledger: Variant = state["targets"].get(target["target_id"], null)
	return ledger == null or ledger["candidate_count"] < policy[roles["target_limit"]]


func stop() -> Dictionary:
	if _runtime_host != null:
		_runtime_host._unbind()
	if _derive != null:
		for id in _entities:
			if _entities[id]["body"].is_alive():
				_derive.purge(id)
	_running = false
	return {"ok": true}


## Presentation clients get their own stream, never the logic RNG handle.
func presentation_random() -> float:
	return _clock.rng_presentation().randf() if _clock != null else 0.0


func snapshot_state() -> Dictionary:
	var entities: Dictionary = {}
	var active: int = 0
	for id in _entities:
		var entity: Dictionary = _entities[id]
		var body: RefCounted = entity["body"]
		var entry: Dictionary = body.to_debug_record()
		entry["position"] = entity["motion"].position
		entry["template_id"] = entity["template_id"]
		var equipment_value: Variant = entity.get("equipment_snapshot", null)
		entry["equipment_snapshot"] = equipment_value.duplicate(true) if equipment_value is Dictionary else {}
		entities[id] = entry
		if body.is_alive():
			active += 1
	return {"running": _running, "tick_rate": _tick_rate, "fingerprint": _fingerprint,
		"config_fingerprint": JSON.stringify(_config, "", true, true).sha256_text(),
		"clock": _clock.snapshot_state() if _clock != null else {}, "entities": entities,
		"active_count": active, "events": _events.duplicate(true), "records": _records.duplicate(true),
		"targets": _targets.duplicate(true), "notices": _notices.duplicate(true),
		"derive": _derive.snapshot_state() if _derive != null else {},
		"budget": _budget.snapshot_state() if _budget != null else {}}


func _clear():
	_runtime_host = null
	_cfg = {}
	_params = {}
	_config = {}
	_fingerprint = ""
	_tick_rate = 0
	_clock = null
	_derive = null
	_budget = null
	_family = null
	_templates = {}
	_entities = {}
	_facts = {}
	_families = {}
	_motion_inputs = {}
	_handlers = {}
	_targets = []
	_events = []
	_records = []
	_notices = []
	last_error = ""


func _failure(path: String, message: String, diagnostics: Array = []) -> Dictionary:
	stop()
	last_error = path + ": " + message
	return {"ok": false, "path": path, "error": last_error, "diagnostics": diagnostics}


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _integer_number(value: Variant) -> bool:
	return _number(value) and float(value) == floor(float(value)) and absf(float(value)) < 9223372036854775807.0
