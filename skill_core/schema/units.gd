class_name SkillUnits extends RefCounted

const META_PATH = "res://data/params_meta.json"
const MAX_TICK_EXCLUSIVE = 9223372036854775808.0

static var _cached_meta: Variant = null

var last_error: String = ""
var _rate: Variant = null
var _tick_fields: Dictionary = {}
var _ready: bool = false


func configure(project_meta: Dictionary, metadata_override: Variant = null, metadata_path: String = META_PATH) -> Dictionary:
	_ready = false
	_rate = null
	_tick_fields = {}
	last_error = ""
	if not project_meta.has("tick_rate"):
		return _fail("Missing project tick_rate")
	var proposed_rate: Variant = project_meta["tick_rate"]
	if not _finite_number(proposed_rate) or float(proposed_rate) <= 0.0:
		return _fail("tick_rate must be a positive finite number")
	var metadata: Variant = metadata_override
	if metadata == null:
		metadata = _load_metadata(metadata_path)
	if not metadata is Dictionary:
		return _fail("Tick metadata is missing or invalid: %s" % metadata_path)
	var source: Dictionary = metadata
	var entries: Variant = source.get("tick_fields", null)
	if not entries is Array:
		return _fail("Tick metadata has no tick_fields array")
	var fields: Dictionary = {}
	for entry in entries:
		if entry is String and entry.begins_with("_"):
			continue
		if not entry is String or entry.is_empty():
			return _fail("Tick metadata contains an invalid field")
		if fields.has(entry):
			return _fail("Tick metadata contains a duplicate field: %s" % entry)
		fields[entry] = true
	if fields.is_empty():
		return _fail("Tick metadata contains no registered fields")
	_rate = proposed_rate
	_tick_fields = fields
	_ready = true
	return {"ok": true, "rate": _rate, "error": ""}


func seconds_to_ticks(field: String, seconds: Variant) -> Dictionary:
	var error: Dictionary = _check_field(field)
	if not error.is_empty():
		return error
	if not _finite_number(seconds):
		return _fail("Seconds must be a finite number: %s" % field)
	if float(seconds) < 0.0:
		return _fail("Seconds cannot be negative: %s" % field)
	var product: float = float(seconds) * float(_rate)
	if not is_finite(product) or product >= MAX_TICK_EXCLUSIVE:
		return _fail("Converted ticks exceed integer range: %s" % field)
	return {"ok": true, "field": field, "seconds": seconds, "ticks": int(ceil(product)), "rate": _rate, "error": ""}


func accept_ticks(field: String, ticks: Variant) -> Dictionary:
	var error: Dictionary = _check_field(field)
	if not error.is_empty():
		return error
	if not ticks is int:
		return _fail("Ticks must be an integer: %s" % field)
	return {"ok": true, "field": field, "seconds": null, "ticks": ticks, "rate": _rate, "error": ""}


func ticks_to_seconds(field: String, ticks: Variant) -> Dictionary:
	var result: Dictionary = accept_ticks(field, ticks)
	if not result["ok"]:
		return result
	result["seconds"] = float(ticks) / float(_rate)
	result["display_only"] = true
	return result


func convert_field(cfg: Dictionary, field: String, from_seconds: bool) -> Dictionary:
	var error: Dictionary = _check_field(field)
	if not error.is_empty():
		return error
	if not cfg.has(field):
		return {"ok": true, "present": false, "field": field, "rate": _rate, "error": ""}
	var value: Variant = cfg[field]
	var result: Dictionary = seconds_to_ticks(field, value) if from_seconds else accept_ticks(field, value)
	if result["ok"]:
		result["present"] = true
	return result


func _check_field(field: String) -> Dictionary:
	if not _ready:
		return _fail("Tick units are not configured: %s" % last_error)
	var regex := RegEx.new()
	if regex.compile("\\[[0-9]+\\]") != OK:
		return _fail("Cannot normalize indexed tick field")
	var registered: String = regex.sub(field, "[i]", true)
	if not _tick_fields.has(registered):
		return _fail("Field is not registered as tick: %s" % field)
	return {}


func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _load_metadata(path: String) -> Variant:
	if path == META_PATH and _cached_meta != null:
		return _cached_meta
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if path == META_PATH and parsed is Dictionary:
		_cached_meta = parsed
	return parsed


func _fail(message: String) -> Dictionary:
	last_error = message
	return {"ok": false, "error": message}
