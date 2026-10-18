class_name RuntimeDerive extends RefCounted

## One coordinator per origin_cast_id. Only settled events enter the FIFO;
## candidates/part records are NOT events. CFG is copied at configure time.
const BodyScript = preload("res://skill_core/runtime/effect_body.gd")
const META_PATH: String = "res://data/derive_meta.json"
const PARAMS_PATH: String = "res://data/params_meta.json"
const LIMITS_PATH: String = "res://data/project_limits.json"

## 待素材替换：仅显式注入，默认路径缺失绝不回退。数值从 project_limits 解析。
## TODO(U-T045-meta): WorkBuddy extracts/reviews runtime bindings, not CFG keys.
const PROVISIONAL_META: Dictionary = {
	"event_roles": {"contact": "hit", "termination": "vanish"},
	"budget_roles": {"generation": "max_generation", "cast": "cast_budget", "depth": "max_chain_depth"},
	"inherited_budgets": ["split_budget", "chain_remaining"],
	"relation": "chain_depth_ge_generation",
	"records": {"generation": "gen_limit", "budget": "budget_drop", "depth": "chain_depth_limit",
		"repeat": "proc_mask", "visited": "visited", "purge": "purge", "created": "created", "error": "derive_error"},
}

static var _cache: Dictionary = {}
var last_error: String = ""
var _load_error: String = ""
var _meta: Dictionary = {}
var _params_meta: Dictionary = {}
var _rule_fields: Dictionary = {}
var _required_rule_fields: Array = []
var _limits: Dictionary = {}
var _templates: Dictionary = {}
var _bindings: Dictionary = {}
var _rules: Dictionary = {}
var _bounds: Dictionary = {}
var _initial_budgets: Dictionary = {}
var _clock: RefCounted
var _ready: bool = false
var _busy: bool = false
var _instances: Dictionary = {}
var _bodies: Dictionary = {}
var _queue: Array = []
var _records: Array = []
var _events: Array = []
var _seen: Dictionary = {}
var _origin: Dictionary = {}
var _cast_remaining: int = 0
var _next_seq: int = 0
var _last_event_tick: int = -1


func _init(metadata_path: String = META_PATH, metadata_override: Variant = null,
		params_path: String = PARAMS_PATH, limits_path: String = LIMITS_PATH, limit_overrides: Dictionary = {}):
	var loaded: Dictionary = _load_json(params_path)
	_load_error = loaded["error"]
	if _load_error.is_empty():
		_load_error = _check_params(loaded["data"])
		if _load_error.is_empty():
			_params_meta = loaded["data"].duplicate(true)
	var candidate: Variant = metadata_override
	if _load_error.is_empty() and candidate == null:
		loaded = _load_json(metadata_path)
		_load_error = loaded["error"]
		candidate = loaded["data"]
	if _load_error.is_empty():
		_load_error = _check_meta(candidate)
		if _load_error.is_empty():
			_meta = candidate.duplicate(true)
	if _load_error.is_empty():
		loaded = _load_json(limits_path)
		_load_error = loaded["error"]
		if _load_error.is_empty():
			_load_error = _resolve_limits(loaded["data"], limit_overrides)
	last_error = _load_error


static func _load_json(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var result: Dictionary = {"data": null, "error": ""}
	if not path.begins_with("res://data/") or not FileAccess.file_exists(path):
		result["error"] = "Derivation metadata missing or outside res://data/: " + path
	else:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			result["error"] = "Cannot open derivation metadata: " + path
		else:
			var parser: JSON = JSON.new()
			if parser.parse(file.get_as_text()) != OK:
				result["error"] = "Invalid derivation JSON: " + path + ": " + parser.get_error_message()
			else:
				result["data"] = parser.data
	_cache[path] = result
	return result


static func _strings(value: Variant, nonempty: bool = false) -> bool:
	if not value is Array or (nonempty and value.is_empty()):
		return false
	var seen: Dictionary = {}
	for item in value:
		if not item is String or item.is_empty() or seen.has(item):
			return false
		seen[item] = true
	return true


static func _text(value: Variant) -> String:
	return value if value is String else ""


static func _natural(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0


func _check_params(data: Variant) -> String:
	if not data is Dictionary or not data.get("enums", null) is Dictionary:
		return "Missing params metadata enums"
	for key in ["event", "vanish_reason", "derivation_reason"]:
		if not _strings(data["enums"].get(key, null), true):
			return "Invalid params enum: " + key
	if data["enums"]["vanish_reason"] != data["enums"]["derivation_reason"]:
		return "Vanish and derivation reason enums disagree"
	if not _strings(data.get("restricted_reasons", null), true):
		return "Missing restricted reason metadata"
	for reason in data["restricted_reasons"]:
		if not data["enums"]["vanish_reason"].has(reason):
			return "Unregistered restricted reason"
	for section in ["leaves", "arrays", "objects"]:
		if not data.get(section, null) is Array or data[section].is_empty():
			return "Missing params metadata section: " + section
		for entry in data[section]:
			if not entry is Dictionary:
				return "Invalid params metadata entry"
			var path: String = _text(entry.get("path", null))
			if path == "derivations[i]":
				if not _strings(entry.get("required", null), true):
					return "Missing derivation required fields"
				_required_rule_fields = entry["required"].duplicate()
			if path.begins_with("derivations[i]."):
				var field: String = path.trim_prefix("derivations[i].")
				if field.contains(".") or field.contains("["):
					continue
				_rule_fields[field] = entry.duplicate(true)
	if _required_rule_fields.is_empty() or _rule_fields.is_empty():
		return "Empty derivation field metadata"
	for field in _required_rule_fields:
		if not _rule_fields.has(field):
			return "Missing derivation field definition: " + str(field)
	return ""


func _check_meta(data: Variant) -> String:
	if not data is Dictionary:
		return "Derivation metadata must be an object"
	var sections: Dictionary = {"event_roles": ["contact", "termination"],
		"budget_roles": ["generation", "cast", "depth"],
		"records": ["generation", "budget", "depth", "repeat", "visited", "purge", "created", "error"]}
	for section in sections:
		if not data.get(section, null) is Dictionary:
			return "Missing derivation metadata: " + section
		for role in sections[section]:
			if _text(data[section].get(role, null)).is_empty():
				return "Missing derivation role: " + section + "." + role
	var roles: Dictionary = data["event_roles"]
	if roles["contact"] == roles["termination"] or roles.size() != _params_meta["enums"]["event"].size():
		return "Event role bindings disagree with enum"
	for event in roles.values():
		if not _params_meta["enums"]["event"].has(event):
			return "Unregistered event role"
	if not _strings(data.get("inherited_budgets", null), true) or _text(data.get("relation", null)).is_empty():
		return "Missing inherited budget or depth relation binding"
	return ""


func _resolve_limits(data: Variant, overrides: Dictionary) -> String:
	if not data is Dictionary:
		return "Project limits must be an object"
	for key in overrides:
		if not ["defaults", "hard_caps"].has(key):
			return "Unknown project limit override section: " + str(key)
	var resolved: Dictionary = {}
	for section in ["defaults", "hard_caps"]:
		var entries: Variant = data.get(section, null)
		var injected: Variant = overrides.get(section, null)
		if not entries is Dictionary or entries.is_empty() or (injected != null and not injected is Dictionary):
			return "Invalid project limit section: " + section
		if injected == null:
			injected = {}
		for key in injected:
			if not entries.has(key):
				return "Unknown project limit override: " + section + "." + str(key)
		var values: Dictionary = {}
		for key in entries:
			var entry: Variant = entries[key]
			if not entry is Dictionary or typeof(entry.get("_provisional", null)) != TYPE_BOOL:
				return "Missing provisional marker: " + section + "." + str(key)
			if entry["_provisional"] and not injected.has(key):
				return "Unresolved provisional project limit: " + section + "." + str(key)
			var value: Variant = injected.get(key, entry.get("value", null))
			# JSON integers decode as floats; injected config still requires int.
			if injected.has(key):
				if not _natural(value):
					return "Invalid integer project override: " + section + "." + str(key)
			elif (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)) or value < 0 or float(value) != floor(float(value)):
				return "Invalid project limit value: " + section + "." + str(key)
			values[key] = int(value)
		resolved[section] = values
	var budget_roles: Dictionary = _meta["budget_roles"]
	for role in budget_roles:
		if not resolved["hard_caps"].has(budget_roles[role]):
			return "Missing project hard cap: " + str(budget_roles[role])
	for key in [budget_roles["generation"], budget_roles["cast"]] + _meta["inherited_budgets"]:
		if not resolved["defaults"].has(key):
			return "Missing project default: " + str(key)
	for key in resolved["defaults"]:
		if resolved["hard_caps"].has(key) and resolved["defaults"][key] > resolved["hard_caps"][key]:
			return "Project default exceeds hard cap: " + str(key)
	if resolved["defaults"][budget_roles["cast"]] < 1 or resolved["hard_caps"][budget_roles["cast"]] < 1:
		return "Cast budget must be positive"
	var relations: Variant = data.get("relations", null)
	if not relations is Dictionary or typeof(relations.get(_meta["relation"], null)) != TYPE_BOOL or not relations[_meta["relation"]]:
		return "Missing enforced chain depth relation"
	_limits = resolved
	return ""


## bindings[template_id][trigger_key] = {budgets: [budget_field...],
## reject_visited: bool}. A missing trigger_id uses template_id:derivations[i].
## This is resolved runtime routing, NOT an added author-facing CFG field.
func configure(params: Dictionary, clock: RefCounted, bindings: Dictionary) -> bool:
	if not _load_error.is_empty():
		return _fail(_load_error)
	if _ready or clock == null or not clock.has_method("rng_logic") or not clock.has_method("snapshot_state"):
		return _fail("Derivation already configured or missing logic clock")
	var roles: Dictionary = _meta["budget_roles"]
	var bounds: Dictionary = {}
	for role in ["generation", "cast"]:
		var key: String = roles[role]
		var value: Variant = params.get(key, _limits["defaults"][key])
		if not _natural(value) or value > _limits["hard_caps"][key] or (role == "cast" and value < 1):
			return _fail("Invalid or above hard cap: " + key)
		bounds[key] = value
	var safety: Variant = params.get("safety", null)
	if not safety is Dictionary:
		return _fail("Missing safety limits")
	if safety.has(roles["cast"]):
		var safety_budget: Variant = safety[roles["cast"]]
		if not _natural(safety_budget) or safety_budget != bounds[roles["cast"]]:
			return _fail("Resolve conflicting safety/params cast budgets before runtime")
	var depth: Variant = safety.get(roles["depth"], null)
	if not _natural(depth) or depth > _limits["hard_caps"][roles["depth"]]:
		return _fail("Missing, invalid or above hard cap: " + roles["depth"])
	bounds[roles["depth"]] = depth
	var budgets: Dictionary = {}
	for key in _meta["inherited_budgets"]:
		var value: Variant = params.get(key, _limits["defaults"][key])
		if not _natural(value):
			return _fail("Invalid inherited budget: " + str(key))
		budgets[key] = value
	var templates: Variant = params.get("templates", null)
	if not templates is Array or templates.is_empty():
		return _fail("Missing nonempty templates")
	if params.has("derivations") and (not params["derivations"] is Array or not params["derivations"].is_empty()):
		return _fail("Resolve top-level derivations to template routing before runtime")
	var registry: Dictionary = {}
	var rules: Dictionary = {}
	for template in templates:
		if not template is Dictionary:
			return _fail("Template must be an object")
		var id: String = _text(template.get("template_id", null))
		if id.is_empty() or registry.has(id):
			return _fail("Missing or duplicate template_id")
		if BodyScript.create(_text(template.get("carrier", null)), template, 0) == null:
			return _fail("Invalid effect body template: " + id)
		var entries: Variant = template.get("derivations", null)
		if entries == null:
			entries = []
		if not entries is Array:
			return _fail("Derivations must be an array: " + id)
		registry[id] = template.duplicate(true)
		rules[id] = entries.duplicate(true)
	for id in rules:
		var seen: Dictionary = {}
		for index in range(rules[id].size()):
			if not _validate_rule(rules[id][index], id, index, registry, bindings):
				return false
			var key: String = _trigger_key(rules[id][index], id, index)
			if seen.has(key):
				return _fail("Duplicate trigger identity in template: " + id + ":" + key)
			seen[key] = true
	_templates = registry
	_rules = rules
	_bindings = bindings.duplicate(true)
	_bounds = bounds
	_initial_budgets = budgets
	_clock = clock
	_cast_remaining = bounds[roles["cast"]]
	_ready = true
	last_error = ""
	return true


func _trigger_key(rule: Dictionary, template_id: String, index: int) -> String:
	return _text(rule.get("trigger_id", null)) if rule.has("trigger_id") else "%s:derivations[%d]" % [template_id, index]


func _validate_rule(value: Variant, template_id: String, index: int, registry: Dictionary, bindings: Dictionary) -> bool:
	if not value is Dictionary:
		return _fail("Derivation rule must be an object")
	var rule: Dictionary = value
	for field in _required_rule_fields:
		if not rule.has(field):
			return _fail("Missing required derivation field: " + str(field))
	for field in rule:
		if not field is String or not _rule_fields.has(field):
			return _fail("Unknown derivation field: " + str(field))
	var event: String = _text(rule.get("event", null))
	if not _params_meta["enums"]["event"].has(event):
		return _fail("Unregistered derivation event")
	var reasons: Variant = rule.get("reasons", null)
	if not _strings(reasons):
		return _fail("Reasons must be a unique string array")
	var termination: bool = event == _meta["event_roles"]["termination"]
	if termination == reasons.is_empty():
		return _fail("Termination needs reasons; contact must have no reasons")
	for reason in reasons:
		if not _params_meta["enums"]["derivation_reason"].has(reason):
			return _fail("Unregistered derivation reason: " + str(reason))
		if _params_meta["restricted_reasons"].has(reason) and not (typeof(rule.get("allow_restricted_reason", null)) == TYPE_BOOL and rule["allow_restricted_reason"]):
			return _fail("Restricted reason requires explicit boolean true: " + str(reason))
	if rule.has("allow_restricted_reason") and typeof(rule["allow_restricted_reason"]) != TYPE_BOOL:
		return _fail("allow_restricted_reason must be bool, not truthy")
	if not _natural(rule.get("count", null)) or rule["count"] < 1:
		return _fail("Derivation count must be positive integer")
	if not registry.has(_text(rule.get("child_template", null))):
		return _fail("Unresolved child_template")
	var key: String = _trigger_key(rule, template_id, index)
	var by_template: Variant = bindings.get(template_id, null)
	if key.is_empty() or not by_template is Dictionary or not by_template.get(key, null) is Dictionary:
		return _fail("Missing resolved derivation binding: " + template_id + ":" + key)
	var binding: Dictionary = by_template[key]
	if not _strings(binding.get("budgets", null)) or typeof(binding.get("reject_visited", null)) != TYPE_BOOL:
		return _fail("Invalid resolved derivation binding: " + key)
	for budget in binding["budgets"]:
		if not _meta["inherited_budgets"].has(budget):
			return _fail("Unregistered derivation budget field: " + str(budget))
	return true


## Only genuinely new roots enter here. Children are registered internally;
## neither the child template nor the returned body can replace its ledger.
func register_root(body: RefCounted, template_id: String, origin: Dictionary) -> bool:
	if not _ready or _busy:
		return _fail("Derivation unavailable: " + _load_error)
	if body == null or not body.is_alive() or body.body_id.is_empty() or not _natural(body.spawn_tick) or _instances.has(body.body_id) or not _templates.has(template_id):
		return _fail("Invalid or duplicate root body/template")
	if body.generation != 0 or body.parent_ref != null:
		return _fail("A child cannot register as a root")
	var template: Dictionary = _templates[template_id]
	if body.carrier != _text(template.get("carrier", null)) or body.lifetime_ticks != template["lifetime_ticks"]:
		return _fail("Root body does not match its template")
	if origin.has("chain_depth") and (not _natural(origin["chain_depth"]) or origin["chain_depth"] != 0):
		return _fail("Causal descendants cannot reset depth through root registration")
	if origin.has("proc_mask") and (not origin["proc_mask"] is Array or not origin["proc_mask"].is_empty()):
		return _fail("Causal descendants cannot reset source mask through root registration")
	var budgets: Dictionary = _initial_budgets.duplicate(true)
	var motion: Variant = template.get("motion", null)
	if motion != null:
		if not motion is Dictionary:
			return _fail("Root motion must be an object")
		for field in _meta["inherited_budgets"]:
			if motion.has(field):
				if not _natural(motion[field]):
					return _fail("Invalid root motion budget: " + str(field))
				budgets[field] = motion[field]
	for key in ["origin_skill", "origin_cast_id"]:
		if _text(origin.get(key, null)).is_empty():
			return _fail("Missing root origin: " + key)
	if not _origin.is_empty() and (_origin["origin_skill"] != origin["origin_skill"] or _origin["origin_cast_id"] != origin["origin_cast_id"]):
		return _fail("Different cast requires a separate derivation coordinator")
	if _cast_remaining <= 0:
		_record("budget", {"body_id": body.body_id, "detail": _meta["budget_roles"]["cast"], "requested": 1})
		return _fail("Root rejected: cast budget exhausted; no compensation event")
	var root_origin: Dictionary = {"origin_skill": origin["origin_skill"], "origin_cast_id": origin["origin_cast_id"], "chain_depth": 0, "proc_mask": []}
	var state: Dictionary = {"body_id": body.body_id, "template_id": template_id, "generation": 0, "spawn_tick": body.spawn_tick,
		"origin": root_origin, "parent_ref": null, "source_chain": [body.body_id],
		"visited": [], "budgets": budgets, "seq": _next_seq, "purged": false, "terminated": false}
	_origin = root_origin.duplicate(true)
	_next_seq += 1
	_cast_remaining -= 1
	_instances[body.body_id] = state
	_bodies[body.body_id] = body
	body.origin = root_origin.duplicate(true)
	last_error = ""
	return true


## Host calls this from RuntimeSettle.notify or with EffectBody.step events.
## Already committed lethal hits remain valid; do not recheck target.alive here.
func enqueue_event(event: Dictionary) -> bool:
	if not _ready or _busy:
		return _fail("Derivation unavailable: " + _load_error)
	var type: String = _text(event.get("type", null))
	var id: String = _text(event.get("body_id", null))
	if not _params_meta["enums"]["event"].has(type) or not _instances.has(id):
		return _fail("Only registered-body hit/vanish events may enter derivation")
	var tick: Variant = event.get("tick", null)
	var body: RefCounted = _bodies[id]
	if not _natural(tick) or tick < _instances[id]["spawn_tick"] or tick < _last_event_tick or tick != _clock.snapshot_state()["tick"]:
		return _fail("Invalid, reversed or noncurrent event tick")
	if not _queue.is_empty() and _queue[0]["tick"] != tick:
		return _fail("Drain the previous tick before accepting more events")
	if _instances[id]["purged"] or body.state == BodyScript.PURGED:
		return _fail("Purged body cannot emit an event")
	if _instances[id]["terminated"]:
		return _fail("Terminated body cannot dispatch another event")
	var target: String = ""
	if type == _meta["event_roles"]["contact"]:
		target = _text(event.get("target_id", null))
		if target.is_empty() or event.has("reason"):
			return _fail("Contact requires target_id and cannot carry a vanish reason")
	else:
		var reason: String = _text(event.get("reason", null))
		if not _params_meta["enums"]["vanish_reason"].has(reason):
			return _fail("Unregistered vanish reason")
	var identity: String = JSON.stringify([id, type, tick, target])
	if _seen.has(identity):
		return _fail("Duplicate event dispatch")
	_seen[identity] = true
	if type == _meta["event_roles"]["termination"]:
		_instances[id]["terminated"] = true
	_last_event_tick = tick
	_queue.append(event.duplicate(true))
	last_error = ""
	return true


func drain() -> Dictionary:
	var result: Dictionary = {"ok": false, "events": [], "children": [], "records": [], "error": ""}
	if not _ready or _busy:
		result["error"] = "Derivation unavailable: " + _load_error
		last_error = result["error"]
		return result
	if not _queue.is_empty() and _queue[0]["tick"] != _clock.snapshot_state()["tick"]:
		result["error"] = "Drain must run in the event tick; delayed instant spawning is not allowed"
		last_error = result["error"]
		return result
	_busy = true
	var start: int = _records.size()
	while not _queue.is_empty():
		var event: Dictionary = _queue.pop_front()
		var id: String = event["body_id"]
		var state: Dictionary = _instances[id]
		var body: RefCounted = _bodies[id]
		if state["purged"] or body.state == BodyScript.PURGED:
			_record("purge", {"body_id": id, "tick": event["tick"], "detail": "queued event cancelled"})
			continue
		_events.append(event.duplicate(true))
		result["events"].append(event.duplicate(true))
		var rules: Array = _rules[state["template_id"]]
		for index in range(rules.size()):
			var rule: Dictionary = rules[index]
			if rule["event"] != event["type"]:
				continue
			if event["type"] == _meta["event_roles"]["termination"] and not rule["reasons"].has(event["reason"]):
				continue
			_spawn(state, rule, index, event, result["children"])
		# Registration records settled contacts, even if budget prevented children.
		# The family candidate-contact ledger remains T-046's separate concern.
		var target: String = _text(event.get("target_id", null))
		if not target.is_empty() and not state["visited"].has(target):
			state["visited"].append(target)
	for index in range(start, _records.size()):
		result["records"].append(_records[index].duplicate(true))
	result["ok"] = true
	_busy = false
	last_error = ""
	return result


func _spawn(parent: Dictionary, rule: Dictionary, index: int, event: Dictionary, children: Array):
	var key: String = _trigger_key(rule, parent["template_id"], index)
	var detail: Dictionary = {"body_id": parent["body_id"], "trigger_id": key, "tick": event["tick"], "requested": rule["count"]}
	var generation: int = parent["generation"] + 1
	var depth: int = parent["origin"]["chain_depth"] + 1
	if generation > _bounds[_meta["budget_roles"]["generation"]]:
		_record("generation", detail)
		return
	if depth > _bounds[_meta["budget_roles"]["depth"]]:
		_record("depth", detail)
		return
	if parent["origin"]["proc_mask"].has(key):
		_record("repeat", detail)
		return
	var binding: Dictionary = _bindings[parent["template_id"]][key]
	var target: String = _text(event.get("target_id", null))
	if binding["reject_visited"] and not target.is_empty() and parent["visited"].has(target):
		_record("visited", detail)
		return
	for budget in binding["budgets"]:
		if parent["budgets"][budget] <= 0:
			detail["detail"] = budget
			_record("budget", detail)
			return
	var count: int = mini(rule["count"], _cast_remaining)
	# One split/continuation operation consumes one unit; every sibling receives
	# the remainder. Cast budget is instead consumed for EACH created instance.
	if count > 0:
		for budget in binding["budgets"]:
			parent["budgets"][budget] -= 1
	for _item in range(count):
		var id: String = "%s:derive:%d" % [_origin["origin_cast_id"], _next_seq]
		while _instances.has(id):
			_next_seq += 1
			id = "%s:derive:%d" % [_origin["origin_cast_id"], _next_seq]
		var template: Dictionary = _templates[rule["child_template"]].duplicate(true)
		var origin: Dictionary = parent["origin"].duplicate(true)
		origin["chain_depth"] = depth
		origin["proc_mask"].append(key)
		template["body_id"] = id
		template["generation"] = generation
		template["parent_ref"] = parent["body_id"]
		template["origin"] = origin.duplicate(true)
		var child: RefCounted = BodyScript.create(template["carrier"], template, int(event["tick"]) + 1)
		var state: Dictionary = {"body_id": id, "template_id": rule["child_template"], "generation": generation, "spawn_tick": child.spawn_tick,
			"origin": origin, "parent_ref": parent["body_id"], "source_chain": parent["source_chain"].duplicate(),
			"visited": parent["visited"].duplicate(), "budgets": parent["budgets"].duplicate(true),
			"seq": _next_seq, "purged": false, "terminated": false}
		state["source_chain"].append(id)
		if not target.is_empty() and not state["visited"].has(target):
			state["visited"].append(target)
		_instances[id] = state
		_bodies[id] = child
		_next_seq += 1
		_cast_remaining -= 1
		children.append(child)
		_record("created", {"body_id": id, "parent_ref": parent["body_id"], "tick": event["tick"], "generation": generation})
	if count < rule["count"]:
		detail["detail"] = _meta["budget_roles"]["cast"]
		detail["requested"] = rule["count"] - count
		_record("budget", detail)


func purge(body_id: String) -> bool:
	if not _ready or _busy or not _instances.has(body_id):
		return _fail("Unknown body or unavailable derivation coordinator")
	var body: RefCounted = _bodies[body_id]
	body.purge()
	_instances[body_id]["purged"] = true
	_record("purge", {"body_id": body_id})
	last_error = ""
	return true


func snapshot_state() -> Dictionary:
	var instances: Dictionary = _instances.duplicate(true)
	for state in instances.values():
		state["generation_remaining"] = _bounds[_meta["budget_roles"]["generation"]] - state["generation"]
		state["depth_remaining"] = _bounds[_meta["budget_roles"]["depth"]] - state["origin"]["chain_depth"]
	return {"instances": instances, "cast_remaining": _cast_remaining,
		"records": _records.duplicate(true), "events": _events.duplicate(true), "queued": _queue.size()}


func _record(role: String, detail: Dictionary):
	var record: Dictionary = detail.duplicate(true)
	record["type"] = "debug_record"
	record["kind"] = _meta["records"][role]
	_records.append(record)


func _fail(message: String) -> bool:
	last_error = message
	return false
