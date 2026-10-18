class_name CfgCodec extends RefCounted

const YamlLiteParser = preload("res://skill_core/schema/yaml_lite.gd")
const DiagnosticType = preload("res://skill_core/api/diagnostic.gd")

const TOP_LEVEL_KEYS: Array[String] = ["schema_version", "skill_id", "meta", "bricks", "params", "presentation", "runtime_hints"]
const BRICK_KEYS: Array[String] = ["brick_id", "name", "tagline", "carrier", "summary", "default_cfg", "author_params", "locked_params", "relic_params", "presentation", "player_text", "status"]
const PRESENTATION_KEYS: Array[String] = ["fx", "sfx", "anim", "trail", "camera", "damage_number", "status_icon"]
const CARRIERS: Array[String] = ["none", "self", "independent", "attached"]
const STATUSES: Array[String] = ["已登记", "候选", "预留"]

static func load_cfg(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": null, "error": "无法打开 CFG: %s" % path, "diagnostics": []}
	var parsed: Dictionary = YamlLiteParser.parse(file.get_as_text())
	if not bool(parsed.get("ok", false)):
		return {"ok": false, "data": null, "error": String(parsed.get("error", "YAML 解析失败")), "diagnostics": []}
	var cfg: Variant = parsed.get("data")
	if not (cfg is Dictionary):
		return {"ok": false, "data": cfg, "error": "顶层路径必须是 map", "diagnostics": _diagnostics_for("", cfg, "map")}
	var diagnostics: Array = validate_structure(cfg)
	return {"ok": diagnostics.is_empty(), "data": cfg, "error": _first_error(diagnostics), "diagnostics": diagnostics}

static func save_cfg(path: String, cfg: Dictionary) -> Dictionary:
	var diagnostics: Array = validate_structure(cfg)
	if not diagnostics.is_empty():
		return {"ok": false, "error": _first_error(diagnostics), "diagnostics": diagnostics}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "无法写入 CFG: %s" % path, "diagnostics": []}
	file.store_string(YamlLiteParser.dump(cfg))
	file.close()
	return {"ok": true, "error": "", "diagnostics": []}

static func validate_structure(cfg: Variant) -> Array:
	var diagnostics: Array = []
	if not (cfg is Dictionary):
		return _diagnostics_for("", cfg, "map")
	var root: Dictionary = cfg
	_check_exact_keys(root, TOP_LEVEL_KEYS, "", diagnostics)
	_check_type(root, "schema_version", TYPE_STRING, diagnostics)
	_check_type(root, "skill_id", TYPE_STRING, diagnostics)
	_check_map(root, "meta", diagnostics)
	_check_array(root, "bricks", diagnostics)
	_check_map(root, "params", diagnostics)
	_check_presentation(root, diagnostics)
	_check_map(root, "runtime_hints", diagnostics)
	_check_nulls_in_nested(root, "", diagnostics)
	if root.has("bricks") and root["bricks"] is Array:
		var bricks: Array = root["bricks"]
		for index in range(bricks.size()):
			var path: String = "bricks[%d]" % index
			if not (bricks[index] is Dictionary):
				diagnostics.append(_diagnostic(path, bricks[index], "map"))
				continue
			var brick: Dictionary = bricks[index]
			_check_exact_keys(brick, BRICK_KEYS, path, diagnostics)
			for key in BRICK_KEYS:
				if not brick.has(key):
					continue
				if brick[key] == null:
					continue
			if brick.has("carrier") and (not (brick["carrier"] is String) or not CARRIERS.has(String(brick["carrier"]))):
				diagnostics.append(_diagnostic(path + ".carrier", brick["carrier"], "none/self/independent/attached"))
			if brick.has("status") and (not (brick["status"] is String) or not STATUSES.has(String(brick["status"]))):
				diagnostics.append(_diagnostic(path + ".status", brick["status"], "已登记/候选/预留"))
			if brick.has("player_text"):
				if not (brick["player_text"] is Array):
					diagnostics.append(_diagnostic(path + ".player_text", brick["player_text"], "array (max 3)"))
				elif brick["player_text"].size() > 3:
					diagnostics.append(_diagnostic(path + ".player_text", brick["player_text"].size(), "最多 3 条"))
	_check_nulls_in_nested(root, "", diagnostics)
	return diagnostics

const TYPE_STRING: int = 0
const TYPE_MAP: int = 1
const TYPE_ARRAY: int = 2

static func _check_type(root: Dictionary, key: String, expected_type: int, diagnostics: Array) -> void:
	if not root.has(key):
		return
	var value: Variant = root[key]
	var valid: bool = (expected_type == TYPE_STRING and value is String) or (expected_type == TYPE_MAP and value is Dictionary) or (expected_type == TYPE_ARRAY and value is Array)
	if not valid:
		diagnostics.append(_diagnostic(key, value, _type_name(expected_type)))

static func _check_map(root: Dictionary, key: String, diagnostics: Array) -> void:
	_check_type(root, key, TYPE_MAP, diagnostics)

static func _check_array(root: Dictionary, key: String, diagnostics: Array) -> void:
	_check_type(root, key, TYPE_ARRAY, diagnostics)

static func _check_presentation(root: Dictionary, diagnostics: Array) -> void:
	if not root.has("presentation") or not (root["presentation"] is Dictionary):
		if root.has("presentation"):
			diagnostics.append(_diagnostic("presentation", root["presentation"], "map with seven slots"))
		return
	var presentation: Dictionary = root["presentation"]
	_check_exact_keys(presentation, PRESENTATION_KEYS, "presentation", diagnostics)
	for key in PRESENTATION_KEYS:
		if not presentation.has(key):
			diagnostics.append(_diagnostic("presentation." + key, "<missing>", "registered slot"))
		elif presentation[key] == null:
			diagnostics.append(_diagnostic("presentation." + key, null, "non-null slot (use {} for empty)"))

static func _check_exact_keys(value: Dictionary, allowed: Array[String], path: String, diagnostics: Array) -> void:
	for key_variant in value.keys():
		var key: String = String(key_variant)
		if not allowed.has(key):
			var actual_path: String = key if path.is_empty() else path + "." + key
			diagnostics.append(_diagnostic(actual_path, value[key_variant], "registered field"))
	for key in allowed:
		if not value.has(key):
			var missing_path: String = key if path.is_empty() else path + "." + key
			diagnostics.append(_diagnostic(missing_path, "<missing>", "required field"))

static func _reject_nulls(value: Variant, path: String, diagnostics: Array) -> void:
	if value == null:
		diagnostics.append(_diagnostic(path, null, "non-null value"))
	elif value is Dictionary:
		var map: Dictionary = value
		for key_variant in map.keys():
			var child_path: String = String(key_variant) if path.is_empty() else path + "." + String(key_variant)
			_reject_nulls(map[key_variant], child_path, diagnostics)
	elif value is Array:
		var array: Array = value
		for index in range(array.size()):
			_reject_nulls(array[index], "%s[%d]" % [path, index], diagnostics)

static func _check_nulls_in_nested(value: Variant, path: String, diagnostics: Array) -> void:
	# Kept separate so the top-level pass can report schema shape before null paths.
	if value is Dictionary:
		var map: Dictionary = value
		for key_variant in map.keys():
			var child_path: String = String(key_variant) if path.is_empty() else path + "." + String(key_variant)
			if map[key_variant] == null and not _has_nullable_path(child_path):
				diagnostics.append(_diagnostic(child_path, null, "non-null value"))
			_check_nulls_in_nested(map[key_variant], child_path, diagnostics)
	elif value is Array:
		var array: Array = value
		for index in range(array.size()):
			_check_nulls_in_nested(array[index], "%s[%d]" % [path, index], diagnostics)

static func _has_nullable_path(_path: String) -> bool:
	# No nullable fields are declared for the current codec contract.
	return false

static func _diagnostics_for(path: String, actual: Variant, expected: String) -> Array:
	return [_diagnostic(path, actual, expected)]

static func _diagnostic(path: String, actual: Variant, expected: String) -> Variant:
	var actual_text: String = "null" if actual == null else str(actual)
	return DiagnosticType.make("V-019", "E-0011", path, actual_text, expected)

static func _first_error(diagnostics: Array) -> String:
	if diagnostics.is_empty():
		return ""
	var diagnostic: Variant = diagnostics[0]
	return diagnostic.text_program() if diagnostic != null and diagnostic.has_method("text_program") else str(diagnostic)

static func _type_name(type_id: int) -> String:
	if type_id == TYPE_STRING:
		return "string"
	if type_id == TYPE_ARRAY:
		return "array"
	return "map"
