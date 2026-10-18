class_name BrickCatalog
extends RefCounted

const DEFAULT_PATH := "res://data/bricks/brick_catalog.json"
const VALID_CARRIERS := ["independent", "attached", "none", "self"]

var _cache: Dictionary = {}
var _active_data: Dictionary = {}
var _active_path: String = ""

func load_from(path: String = DEFAULT_PATH) -> Dictionary:
	if _cache.has(path):
		var cached: Dictionary = _cache[path]
		_active_path = path
		_active_data = cached.get("data", {}).duplicate(true)
		return cached.duplicate(true)

	var result := {"ok": false, "data": {}, "diagnostics": []}
	if not FileAccess.file_exists(path):
		result.diagnostics.append("catalog file not found: %s" % path)
		_cache[path] = result.duplicate(true)
		return result

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.diagnostics.append("catalog file cannot be opened: %s" % path)
		_cache[path] = result.duplicate(true)
		return result

	var text := file.get_as_text()
	file.close()
	var parser := JSON.new()
	var parse_error := parser.parse(text)
	if parse_error != OK:
		result.diagnostics.append("invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
		_cache[path] = result.duplicate(true)
		return result

	var entries = parser.data
	if not (entries is Array):
		result.diagnostics.append("catalog root must be an array")
		_cache[path] = result.duplicate(true)
		return result

	var catalog: Dictionary = {}
	for index in range(entries.size()):
		var entry = entries[index]
		if not (entry is Dictionary):
			result.diagnostics.append("entry %d must be an object" % index)
			break
		var brick_id := str(entry.get("brick_id", ""))
		if brick_id.is_empty():
			result.diagnostics.append("entry %d is missing brick_id" % index)
			break
		var carrier := _normalize_carrier(str(entry.get("carrier", "")))
		if not VALID_CARRIERS.has(carrier):
			result.diagnostics.append("invalid carrier for brick_id '%s': %s" % [brick_id, str(entry.get("carrier", ""))])
			break
		var normalized: Dictionary = (entry as Dictionary).duplicate(true)
		normalized["carrier"] = carrier
		if catalog.has(brick_id):
			result.diagnostics.append("duplicate brick_id '%s'" % brick_id)
			break
		catalog[brick_id] = normalized

	if not result.diagnostics.is_empty():
		_cache[path] = result.duplicate(true)
		return result

	result.ok = true
	result.data = catalog
	_cache[path] = result.duplicate(true)
	_active_path = path
	_active_data = catalog.duplicate(true)
	return result.duplicate(true)

func get_brick(brick_id: String) -> Dictionary:
	return _active_data.get(brick_id, {}).duplicate(true)

func list_all() -> Array:
	var all_entries: Array = []
	for entry in _active_data.values():
		all_entries.append(entry.duplicate(true))
	return all_entries

func list_by_carrier(carrier: String) -> Array:
	return _filter_by("carrier", carrier)

func list_by_status(status: String) -> Array:
	return _filter_by("status", status)

func is_exportable(brick_id: String) -> bool:
	return get_brick(brick_id).get("status", "") == "已登记"

func count() -> int:
	return _active_data.size()

func invalidate_cache() -> void:
	_cache.clear()
	_active_data.clear()
	_active_path = ""

func _filter_by(field: String, expected) -> Array:
	var filtered: Array = []
	for entry in _active_data.values():
		if entry.get(field, null) == expected:
			filtered.append(entry.duplicate(true))
	return filtered

func _normalize_carrier(raw_carrier: String) -> String:
	var annotation_start := raw_carrier.find("〔")
	if annotation_start >= 0:
		return raw_carrier.substr(0, annotation_start).strip_edges()
	return raw_carrier
