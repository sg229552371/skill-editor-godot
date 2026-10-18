@tool
class_name SaveFlow
extends RefCounted

## Persistence coordinator for the editor UI.
## All policy is supplied by the validator/codec/limits injections; this class
## only owns revision, baseline and persistence state.

const SkillApi = preload("res://skill_core/api/skill_api.gd")

var _validator: Variant = null
var _codec: Variant = null
var _limits: Dictionary = {}
var _configured: bool = false
var _configuration_error: String = "未配置保存流程"
var _revision: int = 1
var _fingerprint: String = ""
var _read_only: bool = false
var _baseline_token: String = ""

func configure(validator: Variant, codec: Variant, limits: Dictionary) -> Dictionary:
	_validator = null
	_codec = null
	_limits = {}
	_configured = false
	_configuration_error = ""
	_revision = 1
	_fingerprint = ""
	_read_only = false
	_baseline_token = ""
	if validator == null or not validator is Object or not validator.has_method("validate"):
		return _configure_fail("缺少可调用的 validator.validate")
	if codec == null or not codec is Object or not _has_codec_method(codec, ["parse_text", "decode", "parse", "load_text"]):
		return _configure_fail("缺少可调用的 codec 文本解析方法")
	if not _has_codec_method(codec, ["serialize", "encode", "dump", "dump_text", "to_text"]):
		return _configure_fail("缺少可调用的 codec 文本序列化方法")
	var version: String = _current_version(limits)
	if version.is_empty():
		return _configure_fail("limits 缺少当前 schema_version")
	_validator = validator
	_codec = codec
	_limits = limits.duplicate(true)
	_configured = true
	return {"ok": true, "error": ""}

func load(text: String, context: Dictionary) -> Dictionary:
	var unavailable: Dictionary = _require_ready()
	if not unavailable.is_empty():
		return unavailable
	var context_error: String = _context_error(context, false)
	if not context_error.is_empty():
		return _load_failure(context_error)
	var decoded: Dictionary = _decode(text)
	if not bool(decoded.get("ok", false)):
		return _load_failure(String(decoded.get("reason", "CFG 解析失败")), decoded.get("diagnostics", []))
	var cfg_value: Variant = decoded.get("cfg", null)
	if not cfg_value is Dictionary:
		return _load_failure("CFG 顶层必须是 Dictionary")
	var cfg: Dictionary = cfg_value
	var version_value: Variant = cfg.get("schema_version", null)
	if not version_value is String or String(version_value).is_empty():
		return _load_failure("CFG 缺少 schema_version")
	var version: String = String(version_value)
	var unknown: bool = _is_newer_version(version, _current_version(_limits))
	var validation: Dictionary = _validate(cfg, context, "load")
	var diagnostics: Array = validation.get("diagnostics", []) if validation is Dictionary else []
	if validation.has("ok") and validation.get("ok", false) != true:
		return {"ok": false, "cfg": cfg.duplicate(true), "revision": _revision,
			"read_only": unknown, "reason": String(validation.get("reason", validation.get("error", "校验失败"))),
			"diagnostics": diagnostics}
	_revision = _revision_from_context(context)
	_fingerprint = fingerprint(cfg)
	_read_only = unknown
	_baseline_token = _state_token(context.get("baseline_version_state", null))
	var reason: String = "unknown_schema_version" if unknown else ""
	return {"ok": true, "cfg": cfg.duplicate(true), "revision": _revision,
		"read_only": _read_only, "reason": reason, "diagnostics": diagnostics}

func save(cfg: Dictionary, context: Dictionary) -> Dictionary:
	var unavailable: Dictionary = _require_ready()
	if not unavailable.is_empty():
		return _save_failure(String(unavailable.get("reason", "未配置保存流程")))
	var context_error: String = _context_error(context, true)
	if not context_error.is_empty():
		return _save_failure(context_error)
	var before: Dictionary = cfg.duplicate(true)
	var incoming_version: Variant = cfg.get("schema_version", null)
	if not incoming_version is String or String(incoming_version).is_empty():
		return _save_failure("CFG 缺少 schema_version")
	var incoming_unknown: bool = _is_newer_version(String(incoming_version), _current_version(_limits))
	if _read_only or incoming_unknown or context.get("read_only", false) == true:
		return _save_failure("unknown_schema_version", fingerprint(cfg), true)
	var current_baseline: String = _state_token(context.get("baseline_version_state", null))
	if not _baseline_token.is_empty() and current_baseline != _baseline_token:
		return {"ok": false, "changed": false, "revision": _revision,
			"reason": "baseline_advanced", "fingerprint": fingerprint(cfg),
			"actions": ["save_as", "reload_baseline"]}
	var validation: Dictionary = _validate(cfg, context, "save")
	if validation.get("ok", false) != true:
		return {"ok": false, "changed": false, "revision": _revision,
			"reason": String(validation.get("reason", validation.get("error", "校验失败"))),
			"fingerprint": fingerprint(cfg), "diagnostics": validation.get("diagnostics", [])}
	var value_fingerprint: String = fingerprint(cfg)
	if value_fingerprint == _fingerprint:
		return {"ok": true, "changed": false, "revision": _revision,
			"reason": "unchanged", "fingerprint": value_fingerprint}
	var write_result: Dictionary = _write(cfg, context)
	if write_result.get("ok", false) != true:
		return {"ok": false, "changed": false, "revision": _revision,
			"reason": String(write_result.get("reason", "写盘失败")), "fingerprint": value_fingerprint}
	_revision += 1
	_fingerprint = value_fingerprint
	_baseline_token = current_baseline
	# Keep the caller's tree untouched even when a codec/validator retained it.
	if JSON.stringify(cfg) != JSON.stringify(before):
		return _save_failure("保存过程修改了入参 CFG", value_fingerprint)
	return {"ok": true, "changed": true, "revision": _revision,
		"reason": "", "fingerprint": value_fingerprint}

func fingerprint(cfg: Dictionary) -> String:
	var canonical: String = _canonical(cfg)
	var hashing: HashingContext = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(canonical.to_utf8_buffer())
	return hashing.finish().hex_encode()

func _has_codec_method(codec: Variant, names: Array) -> bool:
	for name in names:
		if codec.has_method(String(name)):
			return true
	return false

func _decode(text: String) -> Dictionary:
	for name in ["parse_text", "decode", "parse", "load_text"]:
		if _codec.has_method(name):
			var value: Variant = _codec.call(name, text)
			if value is Dictionary:
				var result: Dictionary = value
				if result.has("ok"):
					var data: Variant = result.get("cfg", result.get("data", null))
					if data is Dictionary:
						result["cfg"] = data
					return result
				if result is Dictionary:
					return {"ok": true, "cfg": result, "diagnostics": []}
		return {"ok": false, "reason": "codec 解析结果无效", "diagnostics": []}
	return {"ok": false, "reason": "codec 不支持文本解析", "diagnostics": []}

func _write(cfg: Dictionary, context: Dictionary) -> Dictionary:
	var text: String = ""
	for name in ["serialize", "encode", "dump", "dump_text", "to_text"]:
		if _codec.has_method(name):
			var value: Variant = _codec.call(name, cfg.duplicate(true))
			if value is String:
				text = value
				break
	if text.is_empty():
		return {"ok": false, "reason": "codec 序列化失败"}
	var writer: Variant = context.get("write", context.get("write_text", null))
	if writer is Callable:
		var written: Variant = writer.call(text)
		if written is Dictionary:
			return written
		return {"ok": bool(written) if written is bool else true}
	var path_value: Variant = context.get("path", null)
	if path_value is String and not String(path_value).is_empty():
		var file: FileAccess = FileAccess.open(String(path_value), FileAccess.WRITE)
		if file == null:
			return {"ok": false, "reason": "无法写入 CFG"}
		file.store_string(text)
		file.close()
		return {"ok": true}
	return {"ok": false, "reason": "缺少写盘回调或 path"}

func _validate(cfg: Dictionary, context: Dictionary, stage_name: String) -> Dictionary:
	var stage: StringName = SkillApi.STAGE_SAVE if stage_name == "save" else SkillApi.STAGE_LOAD
	var result: Variant = _validator.validate(cfg.duplicate(true), stage, context.duplicate(true))
	if result is Dictionary:
		return result
	return {"ok": false, "reason": "validator 返回结果无效", "diagnostics": []}

func _context_error(context: Dictionary, saving: bool) -> String:
	if not context.has("schema_version_state") or not context.get("schema_version_state", null) is Dictionary:
		return "缺少 context.schema_version_state"
	if not context.has("baseline_version_state") or not context.get("baseline_version_state", null) is Dictionary:
		return "缺少 context.baseline_version_state"
	if not context.has("migration_state") or not context.get("migration_state", null) is Dictionary:
		return "缺少 context.migration_state"
	if saving and not context.has("draft_revision"):
		return "缺少 context.draft_revision"
	return ""

func _current_version(limits: Dictionary) -> String:
	for key in ["current_schema_version", "schema_version", "supported_schema_version"]:
		var value: Variant = limits.get(key, null)
		if value is String and not String(value).is_empty():
			return String(value)
	var versions: Variant = limits.get("supported_schema_versions", null)
	if versions is Array and not versions.is_empty():
		return String(versions[versions.size() - 1])
	return ""

func _is_newer_version(value: String, current: String) -> bool:
	var left: PackedStringArray = value.split(".")
	var right: PackedStringArray = current.split(".")
	var count: int = maxi(left.size(), right.size())
	for index in range(count):
		var a: int = int(left[index]) if index < left.size() and left[index].is_valid_int() else 0
		var b: int = int(right[index]) if index < right.size() and right[index].is_valid_int() else 0
		if a != b:
			return a > b
	return false

func _revision_from_context(context: Dictionary) -> int:
	var value: Variant = context.get("revision", 1)
	return int(value) if value is int and int(value) > 0 else 1

func _state_token(value: Variant) -> String:
	return _canonical(value) if value is Dictionary else ""

func _canonical(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Dictionary:
		var keys: Array[String] = []
		for key in value.keys():
			keys.append(String(key))
		keys.sort()
		var parts: PackedStringArray = PackedStringArray()
		for key in keys:
			parts.append(JSON.stringify(key) + ":" + _canonical(value[key]))
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

func _require_ready() -> Dictionary:
	if _configured:
		return {}
	return {"ok": false, "reason": _configuration_error if not _configuration_error.is_empty() else "未配置保存流程", "diagnostics": []}

func _configure_fail(reason: String) -> Dictionary:
	_configuration_error = reason
	return {"ok": false, "error": reason}

func _load_failure(reason: String, diagnostics: Array = []) -> Dictionary:
	return {"ok": false, "cfg": {}, "revision": _revision, "read_only": false, "reason": reason, "diagnostics": diagnostics}

func _save_failure(reason: String, value_fingerprint: String = "", read_only: bool = false) -> Dictionary:
	return {"ok": false, "changed": false, "revision": _revision, "reason": reason,
		"fingerprint": value_fingerprint, "read_only": read_only}
