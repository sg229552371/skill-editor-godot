class_name RuntimeSettle extends RefCounted

## One settlement coordinator per body. ShapeHit owns contact/hit quotas.
## Host adapters own stats/status/displacement; no host or CFG reference is cached
## in a result. Adapters receive a staged runtime target, never the caller's CFG.
const ShapeScript = preload("res://skill_core/runtime/shape_hit.gd")
const META_PATH: String = "res://data/settle_meta.json"
const PARAMS_PATH: String = "res://data/params_meta.json"

## 待素材替换：仅显式注入；默认路径缺失不回退。类型枚举/份字段仍来自 params_meta。
## TODO(U-T044-meta): WorkBuddy must extract/review these bindings and the
## absent-evadable default before deploying settle_meta.json.
## These bindings are runtime adapter vocabulary, NOT additional CFG keys.
const PROVISIONAL_META: Dictionary = {
	"roles": {"index": "part_index", "type": "type", "amount": "amount", "evadable": "evadable"},
	"target_roles": {"invulnerable": "invulnerable", "evade": "evade", "immune": "immune"},
	"invulnerable_evades": ["physical", "fire", "ice", "lightning", "arcane"],
	"immunity_selectors": ["immunity_profile", "control_type"],
	"immunity_flags": "immune_flags",
	"unresolved_fields": ["amount_profile", "crit_profile", "block_profile", "settlement"],
	"evadable_default": null,
	"hit_record": "hit_settled", "evade_record": "evaded_all",
}

static var _cache: Dictionary = {}
var last_error: String = ""
var _load_error: String = ""
var _meta: Dictionary = {}
var _fields: Dictionary = {}
var _types: Array = []
var _required: Array = []
var _parts: Array = []
var _handlers: Dictionary = {}
var _shape: RefCounted
var _body: RefCounted
var _clock: RefCounted
var _notify: Callable
var _ready: bool = false
var _busy: bool = false
var _fault: String = ""
var _records: Array = []
var _current_records: Array = []


func _init(metadata_path: String = META_PATH, metadata_override: Variant = null, params_path: String = PARAMS_PATH):
	var loaded: Dictionary = _load_json(params_path)
	if not loaded["error"].is_empty():
		_load_error = loaded["error"]
	else:
		_load_error = _read_params(loaded["data"])
	var candidate: Variant = metadata_override
	if _load_error.is_empty() and candidate == null:
		loaded = _load_json(metadata_path)
		_load_error = loaded["error"]
		candidate = loaded["data"]
	if _load_error.is_empty():
		_load_error = _check_meta(candidate)
	if _load_error.is_empty():
		_meta = candidate.duplicate(true)
	last_error = _load_error


static func _load_json(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var result: Dictionary = {"data": null, "error": ""}
	if not path.begins_with("res://data/") or not FileAccess.file_exists(path):
		result["error"] = "Settlement metadata missing or outside res://data/: " + path
	else:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			result["error"] = "Cannot open settlement metadata: " + path
		else:
			var parser: JSON = JSON.new()
			if parser.parse(file.get_as_text()) != OK:
				result["error"] = "Invalid settlement JSON: " + path + ": " + parser.get_error_message()
			else:
				result["data"] = parser.data
	_cache[path] = result
	return result


func _read_params(data: Variant) -> String:
	if not data is Dictionary or not data.get("enums", null) is Dictionary:
		return "Missing params metadata enums"
	var types: Variant = data["enums"].get("part_type", null)
	if not types is Array or types.is_empty():
		return "Missing nonempty part_type enum"
	for kind in types:
		if not kind is String or kind.is_empty() or _types.has(kind):
			return "Invalid/duplicate part_type enum entry"
		_types.append(kind)
	for section in ["leaves", "arrays", "objects"]:
		var entries: Variant = data.get(section, null)
		if not entries is Array:
			return "Missing params metadata section: " + section
		for entry in entries:
			if not entry is Dictionary or not entry.get("path", null) is String:
				return "Invalid params metadata entry"
			var path: String = entry["path"]
			if path == "parts[i]":
				var required: Variant = entry.get("required", null)
				if not required is Array or required.is_empty():
					return "Missing required part fields"
				_required = required.duplicate()
			if path.begins_with("parts[i]."):
				var key: String = path.trim_prefix("parts[i].")
				if key.contains(".") or key.contains("["):
					continue
				var definition: Dictionary = entry.duplicate(true)
				if section == "arrays":
					definition["type"] = "array"
				if section == "objects":
					definition["type"] = "object"
				_fields[key] = definition
	if _required.is_empty() or _fields.is_empty():
		return "Empty parts metadata"
	for key in _required:
		if not _fields.has(key):
			return "Unknown required part field: " + str(key)
	return ""


func _check_meta(meta: Variant) -> String:
	if not meta is Dictionary:
		return "Settlement metadata must be an object"
	for section in ["roles", "target_roles"]:
		if not meta.get(section, null) is Dictionary:
			return "Missing settlement metadata: " + section
	var field_types: Dictionary = {"index": "integer", "type": "string", "amount": "number", "evadable": "boolean"}
	for role in field_types:
		var key: Variant = meta["roles"].get(role, null)
		if not key is String or not _fields.has(key) or _fields[key].get("type", null) != field_types[role]:
			return "Invalid part role: " + str(role)
	for role in ["invulnerable", "evade", "immune"]:
		var key: Variant = meta["target_roles"].get(role, null)
		if not key is String or key.is_empty():
			return "Invalid target role: " + role
	for section in ["invulnerable_evades", "immunity_selectors", "unresolved_fields"]:
		if not meta.get(section, null) is Array or meta[section].is_empty():
			return "Missing nonempty settlement binding: " + section
		for key in meta[section]:
			if not key is String:
				return "Invalid settlement binding entry: " + section
			if section == "invulnerable_evades" and not _types.has(key):
				return "Unregistered invulnerability binding: " + key
			if section != "invulnerable_evades" and not _fields.has(key):
				return "Unregistered part field binding: " + key
	if not meta.get("immunity_flags", null) is String or not _fields.has(meta["immunity_flags"]):
		return "Missing immunity flags field"
	if not meta.has("evadable_default") or (meta["evadable_default"] != null and typeof(meta["evadable_default"]) != TYPE_BOOL):
		return "Missing explicit evadable default policy (null requires an explicit part value)"
	var by_kind: Variant = meta.get("evadable_default_by_kind", null)
	if by_kind != null:
		if not by_kind is Dictionary:
			return "Invalid evadable default by kind policy"
		for kind in by_kind:
			if not kind is String or not _types.has(kind):
				return "Unregistered part type in evadable default policy: " + str(kind)
			if typeof((by_kind as Dictionary)[kind]) != TYPE_BOOL:
				return "Invalid evadable default for part type: " + str(kind)
	for key in ["hit_record", "evade_record"]:
		if not meta.get(key, null) is String or meta[key].is_empty():
			return "Missing settlement record binding: " + key
	return ""


## handlers[type](part_cfg_copy, record_copy, staged_target) -> bool.
## Every registered type needs an explicit host adapter; no silent no-op fallback.
## notify(hit_event_copy) is the single derivation dispatch point, NOT per part.
## Caller schedules hit-derived bodies at tick+1; lifecycle step runs AFTER this.
func configure(template: Dictionary, body: RefCounted, clock: RefCounted, handlers: Dictionary, notify: Callable = Callable(), shape: RefCounted = null) -> bool:
	if not _load_error.is_empty():
		return _fail(_load_error)
	if _ready:
		return _fail("Settlement already configured")
	for kind in _types:
		var handler: Variant = handlers.get(kind, null)
		if not handler is Callable or not handler.is_valid():
			return _fail("Missing settlement host adapter: " + str(kind))
	var parts: Variant = template.get("parts", null)
	if not parts is Array or parts.is_empty():
		return _fail("Settlement requires nonempty parts")
	var seen: Dictionary = {}
	var normalized: Array = []
	for part in parts:
		if not _validate_part(part):
			return false
		var index: int = part[_meta["roles"]["index"]]
		if seen.has(index):
			return _fail("Duplicate part_index: " + str(index))
		seen[index] = true
		normalized.append(part.duplicate(true))
	var checker: RefCounted = shape
	if checker == null:
		checker = ShapeScript.new()
	if not checker.configure(template, body, clock, _resolve):
		return _fail(checker.last_error)
	_parts = normalized
	_handlers = handlers.duplicate()
	_shape = checker
	_body = body
	_clock = clock
	_notify = notify
	_ready = true
	last_error = ""
	return true


# 真源 2110：evadable「按有益有害规则补默认」。
# 缺省时先查按份种类的补默认表（evadable_default_by_kind），再退回全局 evadable_default；
# 两者都补不出就显式失败，绝不替作者猜一个 true/false。
func _evadable_default_for(part: Variant) -> Variant:
	if not part is Dictionary:
		return null
	var body: Dictionary = part as Dictionary
	var roles: Dictionary = _meta["roles"]
	var evadable_key: String = roles["evadable"]
	if body.has(evadable_key):
		return body[evadable_key]
	var by_kind: Variant = _meta.get("evadable_default_by_kind", null)
	if by_kind is Dictionary:
		var kind: Variant = body.get(roles["type"], null)
		if kind is String and (by_kind as Dictionary).has(kind):
			return (by_kind as Dictionary)[kind]
	return _meta.get("evadable_default", null)


func _validate_part(part: Variant) -> bool:
	if not part is Dictionary:
		return _fail("Part must be an object")
	for key in _required:
		if not part.has(key):
			return _fail("Missing required part field: " + str(key))
	if _evadable_default_for(part) == null:
		return _fail("Unresolved evadable default; provide an explicit part value or approved metadata")
	for key in part:
		if not _fields.has(key):
			return _fail("Unknown part field: " + str(key))
		if _meta["unresolved_fields"].has(key):
			return _fail("Unresolved settlement profile adapter: " + str(key))
		var definition: Dictionary = _fields[key]
		var value: Variant = part[key]
		var valid: bool = false
		match str(definition.get("type", "")):
			"integer": valid = typeof(value) == TYPE_INT
			"number": valid = _number(value)
			"boolean": valid = typeof(value) == TYPE_BOOL
			"string": valid = value is String
			"array": valid = value is Array
		if not valid:
			return _fail("Invalid part field type: " + str(key))
		if definition.has("enum") and not definition["enum"].has(value):
			return _fail("Unregistered part field value: " + str(key))
		for bound in ["minimum", "exclusiveMinimum", "maximum"]:
			if definition.has(bound):
				if not _number(value):
					return _fail("Non-numeric part bound: " + str(key))
				if (bound == "minimum" and value < definition[bound]) or (bound == "exclusiveMinimum" and value <= definition[bound]) or (bound == "maximum" and value > definition[bound]):
					return _fail("Part value out of bounds: " + str(key))
		if definition.has("minLength") and value.length() < int(definition["minLength"]):
			return _fail("Empty part string: " + str(key))
		if value is Array:
			for flag in value:
				if not flag is String or flag.is_empty():
					return _fail("Invalid immunity flag")
	if not _types.has(part[_meta["roles"]["type"]]):
		return _fail("Unregistered part type")
	return true


func step(targets: Array, inputs: Dictionary = {}) -> Dictionary:
	var failed: Dictionary = {"ok": false, "events": [], "candidates": [], "records": [], "error": ""}
	if not _ready or _busy or not _fault.is_empty():
		failed["error"] = "Settlement unavailable: " + _load_error + _fault
		last_error = failed["error"]
		return failed
	for target in targets:
		if not _validate_target(target):
			failed["error"] = last_error
			return failed
	_busy = true
	_current_records = []
	var result: Dictionary = _shape.step(targets, inputs)
	result["records"] = _current_records.duplicate(true)
	if not result["ok"]:
		last_error = _shape.last_error
		if not _fault.is_empty():
			last_error = _fault
		result["error"] = last_error
	else:
		last_error = ""
	# Even a later adapter fault must not lose earlier committed hit dispatches.
	for event in result["events"]:
		if _notify.is_valid():
			_notify.call(event.duplicate(true))
	_busy = false
	return result


func _validate_target(target: Variant) -> bool:
	if not target is Dictionary:
		return _fail("Target must be a runtime object")
	var roles: Dictionary = _meta["target_roles"]
	if typeof(target.get(roles["invulnerable"], null)) != TYPE_BOOL:
		return _fail("Target requires explicit invulnerability state")
	for role in ["evade", "immune"]:
		var table: Variant = target.get(roles[role], null)
		if not table is Dictionary:
			return _fail("Target requires runtime table: " + role)
		for key in table:
			var value: Variant = table[key]
			if not key is String:
				return _fail("Target gate keys must be strings")
			if role == "immune" and typeof(value) != TYPE_BOOL:
				return _fail("Immunity values must be bool")
			if role == "evade" and (not _number(value) or value < 0.0 or value > 1.0):
				return _fail("Evasion probability must be finite in [0,1]")
	return true


## ShapeHit calls only for live, eligible contacts, with the logic RNG.
## Null on adapter failure intentionally faults ShapeHit rather than pretending
## that a failed settlement was an all-evaded contact.
func _resolve(target: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var staged: Dictionary = target.duplicate(true)
	var parts: Array = []
	var accepted: int = 0
	var roles: Dictionary = _meta["roles"]
	var target_roles: Dictionary = _meta["target_roles"]
	for part in _parts:
		var kind: String = part[roles["type"]]
		var evadable: bool = part.get(roles["evadable"], _evadable_default_for(part))
		var invulnerable: bool = staged[target_roles["invulnerable"]] and _meta["invulnerable_evades"].has(kind)
		var probability: float = float(staged[target_roles["evade"]].get(kind, 0.0))
		var evaded: bool = invulnerable
		if not evaded and evadable and probability > 0.0:
			evaded = probability >= 1.0 or rng.randf() < probability
		var amount_key: String = roles["amount"]
		var amount: float = float(part.get(amount_key, _fields[amount_key].get("default", 0.0)))
		var record: Dictionary = {"part_index": part[roles["index"]], "type": kind,
			"evaded": evaded, "immune": false, "zero": false, "value": 0.0}
		if not evaded:
			accepted += 1
			var immune: bool = _is_immune(part, kind, staged[target_roles["immune"]])
			record["immune"] = immune
			record["value"] = 0.0 if immune else amount
			record["zero"] = record["value"] == 0.0
			if not immune:
				var handler: Callable = _handlers[kind]
				var alive_before: bool = staged["alive"]
				var applied: Variant = handler.call(part.duplicate(true), record.duplicate(true), staged)
				if typeof(applied) != TYPE_BOOL or not applied:
					_fault = "Settlement host adapter failed: " + kind + "; contact/RNG spent, target transaction discarded"
					return null
				if not _validate_target(staged) or typeof(staged.get("alive", null)) != TYPE_BOOL or staged.get("target_id", null) != target["target_id"] or not _position(staged.get("position", null)):
					_fault = "Settlement adapter corrupted target state/identity; transaction discarded"
					return null
				if not alive_before and staged["alive"]:
					_fault = "Settlement adapter attempted to revive a dead target; transaction discarded"
					return null
		parts.append(record)
	var hit: bool = accepted > 0
	var summary: Dictionary = {"type": _meta["hit_record"] if hit else _meta["evade_record"],
		"tick": int(_clock.snapshot_state()["tick"]), "body_id": _body.body_id,
		"target_id": target["target_id"], "parts": parts, "killed": target["alive"] and not staged["alive"]}
	# Preserve identity for FIFO readers: publish staged runtime state in place.
	target.clear()
	target.merge(staged, true)
	_current_records.append(summary)
	_records.append(summary.duplicate(true))
	return hit


func _is_immune(part: Dictionary, kind: String, immunity: Dictionary) -> bool:
	if immunity.get(kind, false):
		return true
	for selector in _meta["immunity_selectors"]:
		if part.has(selector) and immunity.get(part[selector], false):
			return true
	var flags: Variant = part.get(_meta["immunity_flags"], null)
	if flags is Array:
		for flag in flags:
			if immunity.get(flag, false):
				return true
	return false


func snapshot_state() -> Dictionary:
	var state: Dictionary = {"candidate_count": 0, "hit_count": 0}
	if _shape != null:
		state = _shape.snapshot_state()
	state["records"] = _records.duplicate(true)
	return state


static func _position(value: Variant) -> bool:
	return typeof(value) == TYPE_VECTOR2 and value.is_finite()


static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


func _fail(message: String) -> bool:
	last_error = message
	return false
