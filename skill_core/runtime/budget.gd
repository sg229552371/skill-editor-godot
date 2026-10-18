class_name RuntimeBudget extends RefCounted

## Runtime admission gate. Call before registering a new root with Derive;
## rejections and drops are observable without publishing events or settlement records.
const LIMITS_PATH: String = "res://data/project_limits.json"
const DERIVE_PATH: String = "res://data/derive_meta.json"
const PARAMS_PATH: String = "res://data/params_meta.json"

static var _cache: Dictionary = {}
var last_error: String = ""
var _load_error: String = ""
var _ready: bool = false
var _roles: Dictionary = {}
var _fields: Dictionary = {}
var _keys: Dictionary = {}
var _priorities: Dictionary = {}
var _formal_types: Array = []
var _event_types: Array = []
var _reason: String = ""
var _debug_type: String = ""
var _debug_enabled: bool = false
var _capacity: int = 0
var _root_cost: int = 0
var _occupied: int = 0
var _roots: Dictionary = {}
var _drops: Array = []
var _debug: Array = []
var _settlements: Array = []


func _init(limits_path: String = LIMITS_PATH, derive_path: String = DERIVE_PATH, params_path: String = PARAMS_PATH):
	var limits: Dictionary = _load_json(limits_path)
	var derive: Dictionary = _load_json(derive_path)
	var params: Dictionary = _load_json(params_path)
	for loaded in [limits, derive, params]:
		if not loaded["error"].is_empty():
			_load_error = loaded["error"]
			break
	if _load_error.is_empty():
		if not limits["data"] is Dictionary or not derive["data"] is Dictionary or not params["data"] is Dictionary:
			_load_error = "Budget metadata must contain objects"
		else:
			_roles = {"limits": limits["data"], "derive": derive["data"], "params": params["data"]}
	last_error = _load_error


static func _load_json(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path].duplicate(true)
	var result: Dictionary = {"data": null, "error": ""}
	if not path.begins_with("res://data/") or not FileAccess.file_exists(path):
		result["error"] = "Budget metadata missing or outside res://data/: " + path
	else:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			result["error"] = "Cannot open budget metadata: " + path
		else:
			var parser: JSON = JSON.new()
			if parser.parse(file.get_as_text()) != OK:
				result["error"] = "Invalid budget JSON: " + path + ": " + parser.get_error_message()
			else:
				result["data"] = parser.data
	_cache[path] = result.duplicate(true)
	return result


static func _name(value: Variant) -> bool:
	return value is String and not value.is_empty()


static func _natural(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0


## Policy is runtime-only: priorities maps every allowed category to a unique
## nonnegative discard rank (lowest is sacrificed first). No CFG switches.
## fields: id, category, cost, type, kind, root, reason, occupied.
## ledger_keys: roots, drops, debug, settlements, occupied, capacity.
func configure(policy: Dictionary, limit_overrides: Dictionary) -> bool:
	if not _load_error.is_empty():
		return _fail(_load_error)
	if _ready:
		return _fail("Budget already configured")
	var priorities: Variant = policy.get("priorities", null)
	if not priorities is Dictionary or priorities.is_empty():
		return _fail("Missing nonempty budget priority table")
	var ranks: Dictionary = {}
	for category in priorities:
		if not _name(category) or str(category).begins_with("_") or not _natural(priorities[category]):
			return _fail("Invalid budget priority/category")
		var rank: int = priorities[category]
		if ranks.has(rank):
			return _fail("Duplicate budget priority")
		ranks[rank] = true
	var fields: Variant = policy.get("fields", null)
	var keys: Variant = policy.get("ledger_keys", null)
	if not fields is Dictionary or not keys is Dictionary:
		return _fail("Missing budget field or ledger bindings")
	var names: Dictionary = {}
	for role in ["id", "category", "cost", "type", "kind", "root", "reason", "occupied"]:
		var field: Variant = fields.get(role, null)
		if not _name(field) or names.has(field):
			return _fail("Missing or duplicate budget field: " + role)
		names[field] = true
	names.clear()
	for role in ["roots", "drops", "debug", "settlements", "occupied", "capacity"]:
		var key: Variant = keys.get(role, null)
		if not _name(key) or names.has(key):
			return _fail("Missing or duplicate budget ledger key: " + role)
		names[key] = true
	var debug_type: Variant = policy.get("debug_type", null)
	var debug_enabled: Variant = policy.get("debug_enabled", null)
	var cost: Variant = policy.get("root_cost", null)
	var capacity: Variant = policy.get("capacity", null)
	if not _name(debug_type) or typeof(debug_enabled) != TYPE_BOOL or not _natural(cost) or cost < 1 or not _natural(capacity) or capacity < 1:
		return _fail("Invalid budget capacity, root cost or debug binding")
	var derive: Dictionary = _roles["derive"]
	var params: Dictionary = _roles["params"]
	var budget_roles: Variant = derive.get("budget_roles", null)
	var record_roles: Variant = derive.get("records", null)
	var enums: Variant = params.get("enums", null)
	if not budget_roles is Dictionary or not record_roles is Dictionary or not enums is Dictionary:
		return _fail("Missing derivation budget/record or parameter enum bindings")
	var cast_key: Variant = budget_roles.get("cast", null)
	var reason: Variant = record_roles.get("budget", null)
	var formal: Variant = enums.get("record", null)
	var events: Variant = enums.get("event", null)
	if not _name(cast_key) or not _name(reason) or not formal is Array or formal.is_empty() or not events is Array or events.is_empty():
		return _fail("Incomplete budget or formal record registry")
	if formal.has(debug_type) or events.has(debug_type):
		return _fail("Debug type must not be a settlement record or event")
	for kind in formal + events:
		if not _name(kind):
			return _fail("Invalid formal record/event registry")
	var resolved: Dictionary = _resolve_limits(_roles["limits"], limit_overrides)
	if not resolved["ok"]:
		return _fail(resolved["error"])
	var caps: Dictionary = resolved["hard_caps"]
	var defaults: Dictionary = resolved["defaults"]
	if not caps.has(cast_key) or not defaults.has(cast_key) or caps[cast_key] < 1 or defaults[cast_key] < 1 or capacity > caps[cast_key]:
		return _fail("Budget capacity exceeds project cast hard cap or cast limit is missing")
	_fields = fields.duplicate(true)
	_keys = keys.duplicate(true)
	_priorities = priorities.duplicate(true)
	_formal_types = formal.duplicate()
	_event_types = events.duplicate()
	_reason = reason
	_debug_type = debug_type
	_debug_enabled = debug_enabled
	_root_cost = cost
	_capacity = capacity
	_ready = true
	last_error = ""
	return true


func _resolve_limits(source: Variant, overrides: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok": false, "error": "", "defaults": {}, "hard_caps": {}}
	if not source is Dictionary:
		result["error"] = "Missing project limits"
		return result
	for section in overrides:
		if not ["defaults", "hard_caps"].has(section):
			result["error"] = "Unknown project limit override section: " + str(section)
			return result
	for section in ["defaults", "hard_caps"]:
		var entries: Variant = source.get(section, null)
		var injected: Variant = overrides.get(section, null)
		if not entries is Dictionary or entries.is_empty() or (injected != null and not injected is Dictionary):
			result["error"] = "Invalid project limit section: " + section
			return result
		if injected == null:
			injected = {}
		for key in injected:
			if not entries.has(key) or str(key).begins_with("_"):
				result["error"] = "Unknown project limit override: " + section + "." + str(key)
				return result
		var values: Dictionary = {}
		for key in entries:
			if str(key).begins_with("_"):
				continue
			var entry: Variant = entries[key]
			if not entry is Dictionary or typeof(entry.get("_provisional", null)) != TYPE_BOOL:
				result["error"] = "Missing provisional marker: " + section + "." + str(key)
				return result
			if entry["_provisional"] and not injected.has(key):
				result["error"] = "Unresolved provisional project limit: " + section + "." + str(key)
				return result
			var value: Variant = injected.get(key, entry.get("value", null))
			if injected.has(key):
				if not _natural(value):
					result["error"] = "Invalid integer project override: " + section + "." + str(key)
					return result
			elif (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)) or value < 0 or float(value) != floor(float(value)):
				result["error"] = "Invalid project limit value: " + section + "." + str(key)
				return result
			values[key] = int(value)
		result[section] = values
	for key in result["defaults"]:
		if result["hard_caps"].has(key) and result["defaults"][key] > result["hard_caps"][key]:
			result["error"] = "Project default exceeds hard cap: " + str(key)
			return result
	result["ok"] = true
	return result


## Items are resolved runtime demands, not author CFG. No existing allocation
## is evicted; only items of THIS request may be discarded, in priority order.
func admit_root(root_id: Variant, items: Array) -> Dictionary:
	var result: Dictionary = {"ok": false, "admitted": false, "rejected": null, "kept": [], "dropped": [], "error": ""}
	if not _ready:
		return _error(result, "Budget is not configured: " + _load_error)
	if not _name(root_id) or _roots.has(root_id):
		return _error(result, "Invalid or duplicate root identity")
	var seen: Dictionary = {}
	var requested: Array = []
	for item in items:
		if not item is Dictionary:
			return _error(result, "Budget item must be an object")
		var id: Variant = item.get(_fields["id"], null)
		var category: Variant = item.get(_fields["category"], null)
		var cost: Variant = item.get(_fields["cost"], null)
		if not _name(id) or seen.has(id) or not _name(category) or not _priorities.has(category) or not _natural(cost) or cost < 1:
			return _error(result, "Invalid, duplicate or unregistered budget item/category")
		seen[id] = true
		requested.append(item.duplicate(true))
	if _occupied + _root_cost > _capacity:
		var rejection: Dictionary = _entry(root_id, root_id, _occupied)
		_drops.append(rejection.duplicate(true))
		_debug_append(rejection)
		result["rejected"] = rejection.duplicate(true)
		result["ok"] = true
		last_error = ""
		return result
	var kept: Array = requested.duplicate(true)
	var needed: int = _occupied + _root_cost
	for item in kept:
		needed += item[_fields["cost"]]
	var order: Array = range(kept.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var left: int = _priorities[kept[a][_fields["category"]]]
		var right: int = _priorities[kept[b][_fields["category"]]]
		return left < right if left != right else a > b)
	var discarded: Dictionary = {}
	for index in order:
		if needed <= _capacity:
			break
		needed -= kept[index][_fields["cost"]]
		discarded[index] = true
		var drop: Dictionary = _entry(root_id, kept[index][_fields["id"]], _occupied)
		_drops.append(drop.duplicate(true))
		_debug_append(drop)
		result["dropped"].append(drop.duplicate(true))
	var accepted: Array = []
	for index in range(kept.size()):
		if not discarded.has(index):
			accepted.append(kept[index].duplicate(true))
	_occupied = needed
	_roots[root_id] = {"cost": _root_cost, "items": accepted.duplicate(true)}
	result["kept"] = accepted
	result["admitted"] = true
	result["ok"] = true
	last_error = ""
	return result


func _entry(root_id: String, id: String, occupied: int) -> Dictionary:
	var entry: Dictionary = {}
	entry[_fields["root"]] = root_id
	entry[_fields["id"]] = id
	entry[_fields["reason"]] = _reason
	entry[_fields["occupied"]] = occupied
	return entry


func _debug_append(entry: Dictionary):
	if not _debug_enabled:
		return
	var record: Dictionary = entry.duplicate(true)
	record[_fields["type"]] = _debug_type
	record[_fields["kind"]] = _reason
	_debug.append(record)


## Debug affects observation only. No event/settlement subscription or callback
## is exposed by this ledger, so the battle path cannot consume debug_record.
func set_debug_enabled(enabled: bool) -> bool:
	if not _ready:
		return _fail("Budget is not configured")
	_debug_enabled = enabled
	last_error = ""
	return true


func record_settlement(record: Dictionary) -> bool:
	if not _ready or not _formal_types.has(record.get(_fields["type"], null)):
		return _fail("Only registered formal settlement records may be stored")
	_settlements.append(record.duplicate(true))
	last_error = ""
	return true


func snapshot_state() -> Dictionary:
	if not _ready:
		return {}
	var state: Dictionary = {}
	state[_keys["roots"]] = _roots.duplicate(true)
	state[_keys["drops"]] = _drops.duplicate(true)
	state[_keys["debug"]] = _debug.duplicate(true)
	state[_keys["settlements"]] = _settlements.duplicate(true)
	state[_keys["occupied"]] = _occupied
	state[_keys["capacity"]] = _capacity
	return state


func _error(result: Dictionary, message: String) -> Dictionary:
	last_error = message
	result["error"] = message
	return result


func _fail(message: String) -> bool:
	last_error = message
	return false
