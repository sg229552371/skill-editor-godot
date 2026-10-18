class_name PreviewFingerprint extends RefCounted

## Deterministic preview identity. Configuration is injected by the host so the
## runtime does not own project policy or write runtime state into a CFG.

var _configured: bool = false
var _configuration_error: String = ""
var _tick_rate: Variant = null
var _notice: String = ""
var _certified_fingerprint: String = ""


func configure(project_config: Dictionary) -> Dictionary:
	_configured = false
	_configuration_error = ""
	_tick_rate = null
	_notice = ""
	if not project_config.has("tick_rate"):
		return _configure_failure("missing tick_rate")
	var tick_rate: Variant = project_config["tick_rate"]
	if not (tick_rate is int or tick_rate is float) or not is_finite(float(tick_rate)) or float(tick_rate) <= 0.0:
		return _configure_failure("invalid tick_rate")
	_tick_rate = tick_rate
	_notice = _notice_from(project_config)
	_configured = true
	return {"ok": true, "error": ""}


func compute(cfg: Dictionary, seed: Variant, extra: Dictionary = {}) -> Dictionary:
	var ready: Dictionary = _require_ready()
	if not ready.is_empty():
		return {"ok": false, "error": ready["error"], "fingerprint": ""}
	var before: String = JSON.stringify(cfg)
	var payload: Dictionary = {
		"cfg": cfg.duplicate(true),
		"seed": _duplicate_value(seed),
		"tick_rate": _tick_rate,
		"extra": extra.duplicate(true),
	}
	var canonical: String = _canonical(payload)
	var hashing: HashingContext = HashingContext.new()
	var start_error: int = hashing.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		return {"ok": false, "error": "fingerprint hashing unavailable", "fingerprint": ""}
	hashing.update(canonical.to_utf8_buffer())
	var fingerprint: String = hashing.finish().hex_encode()
	if JSON.stringify(cfg) != before:
		return {"ok": false, "error": "compute modified cfg", "fingerprint": ""}
	return {"ok": true, "error": "", "fingerprint": fingerprint}


func certify(fingerprint: String) -> void:
	_certified_fingerprint = fingerprint


func state_for(cfg: Dictionary, seed: Variant, extra: Dictionary = {}) -> Dictionary:
	var result: Dictionary = compute(cfg, seed, extra)
	var current: String = String(result.get("fingerprint", ""))
	var match: bool = bool(result.get("ok", false)) and not _certified_fingerprint.is_empty() and current == _certified_fingerprint
	return {
		"ok": bool(result.get("ok", false)),
		"error": String(result.get("error", "")),
		"fingerprint": current,
		"certified_fingerprint": _certified_fingerprint,
		"match": match,
		"save_verdict": "allow" if match else "allow_with_notice",
		"certify_verdict": "allow" if match else "block",
		"notice": _notice,
	}


func _configure_failure(reason: String) -> Dictionary:
	_configuration_error = reason
	return {"ok": false, "error": reason}


func _require_ready() -> Dictionary:
	if _configured:
		return {}
	return {"error": _configuration_error if not _configuration_error.is_empty() else "not configured"}


func _notice_from(project_config: Dictionary) -> String:
	for key in ["notice", "save_notice", "preview_notice"]:
		var value: Variant = project_config.get(key, null)
		if value is String:
			return String(value)
	var notices: Variant = project_config.get("notices", null)
	if notices is Dictionary:
		for key in ["unpreviewed", "save", "preview"]:
			var nested: Variant = notices.get(key, null)
			if nested is String:
				return String(nested)
	return ""


func _duplicate_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


func _canonical(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Dictionary:
		var map: Dictionary = value
		var keys: Array[String] = []
		for key_variant in map.keys():
			keys.append(String(key_variant))
		keys.sort()
		var parts: PackedStringArray = PackedStringArray()
		for key in keys:
			parts.append(JSON.stringify(key) + ":" + _canonical(map[key]))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var items: PackedStringArray = PackedStringArray()
		for item in value:
			items.append(_canonical(item))
		return "[" + ",".join(items) + "]"
	if value is bool:
		return "bool:" + ("true" if value else "false")
	if value is int:
		return "int:" + str(value)
	if value is float:
		return "float:" + str(value)
	if value is String:
		return "string:" + JSON.stringify(value)
	return str(typeof(value)) + ":" + JSON.stringify(str(value))
