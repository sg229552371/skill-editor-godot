class_name HostRegistry extends RefCounted

const SECTIONS: Array = ["cast", "timing", "attached", "summon", "emission", "carrier"]

var _adapters: Dictionary = {}


func register(section: String, adapter: Variant) -> Dictionary:
	if not SECTIONS.has(section):
		return _failure("section", "Unknown host section: " + section, "UNKNOWN_SECTION")
	if _adapters.has(section):
		return _failure("section", "Host adapter already registered: " + section, "DUPLICATE_ADAPTER")
	if adapter == null:
		return _failure("adapter", "Host adapter is null: " + section, "INVALID_ADAPTER")
	if not adapter is Object:
		return _failure("adapter", "Host adapter must be an object: " + section, "INVALID_ADAPTER")
	for method in ["validate", "begin", "advance"]:
		if not adapter.has_method(method):
			return _failure("adapter." + method, "Host adapter missing " + method + ": " + section, "INVALID_ADAPTER")
	_adapters[section] = adapter
	return {"ok": true, "error": "", "path": "", "code": ""}


func has_adapter(section: String) -> bool:
	return _adapters.has(section)


func sections() -> Array:
	var result: Array = []
	for section in SECTIONS:
		if _adapters.has(section):
			result.append(section)
	return result


func validate(section: String, request: Dictionary, ctx: Dictionary) -> Dictionary:
	if not _adapters.has(section):
		return _failure(section, "Host adapter not implemented: " + section, "HOST_ADAPTER_MISSING")
	return _adapters[section].validate(request, ctx)


func begin(section: String, request: Dictionary, ctx: Dictionary) -> Dictionary:
	if not _adapters.has(section):
		return _failure(section, "Host adapter not implemented: " + section, "HOST_ADAPTER_MISSING")
	return _adapters[section].begin(request, ctx)


func advance(section: String, state: Dictionary, tick: int, ctx: Dictionary) -> Dictionary:
	if not _adapters.has(section):
		return _failure(section, "Host adapter not implemented: " + section, "HOST_ADAPTER_MISSING")
	return _adapters[section].advance(state, tick, ctx)


func _failure(path: String, error: String, code: String) -> Dictionary:
	return {"ok": false, "error": error, "path": path, "code": code}
