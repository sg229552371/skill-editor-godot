class_name LockGuard
extends RefCounted

const META_PATH: String = "res://data/params_meta.json"
const RULES_PATH: String = "res://data/validation_rules.csv"
const MESSAGES_PATH: String = "res://data/error_messages.csv"
const LOCK_RULE: String = "V-014"
static var _cache: Dictionary = {}

var last_error: String = ""
var _ready: bool = false
var _array_paths: Dictionary = {}
var _rule: Dictionary = {}
var _template: String = ""

func configure_from_file(meta_path: String = META_PATH, rules_path: String = RULES_PATH, messages_path: String = MESSAGES_PATH) -> bool:
	_ready = false
	last_error = ""
	for path in [meta_path, rules_path, messages_path]:
		if not path.begins_with("res://data/"):
			return _fail("机器素材必须从 res://data/ 读取: %s" % path)
	var cache_key: String = "%s|%s|%s" % [meta_path, rules_path, messages_path]
	if _cache.has(cache_key):
		var saved: Dictionary = _cache[cache_key]
		return configure(saved.meta, saved.rule, saved.template)
	var file: FileAccess = FileAccess.open(meta_path, FileAccess.READ)
	if file == null:
		return _fail("无法读取参数元数据: %s" % meta_path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return _fail("参数元数据必须是 JSON 对象: %s" % meta_path)
	var rule: Dictionary = _csv_row(rules_path, "rule_id", LOCK_RULE)
	if rule.is_empty():
		return _fail("缺少 V-014 规则素材: %s" % rules_path)
	var message: Dictionary = _csv_row(messages_path, "code", str(rule.get("error_code", "")))
	if message.is_empty():
		return _fail("缺少 V-014 的文案素材: %s" % messages_path)
	var template: Variant = message.get("template", null)
	if not template is String or template.is_empty():
		return _fail("E 文案模板无效: %s" % messages_path)
	if not configure(parsed, rule, template):
		return false
	_cache[cache_key] = {"meta": parsed.duplicate(true), "rule": rule.duplicate(true), "template": template}
	return true

func configure(meta: Dictionary, rule: Dictionary, template: String) -> bool:
	_ready = false
	last_error = ""
	_array_paths.clear()
	_rule.clear()
	_template = ""
	var leaves: Variant = meta.get("leaves", null)
	var arrays: Variant = meta.get("arrays", null)
	var objects: Variant = meta.get("objects", null)
	if not leaves is Array or not arrays is Array or not objects is Array:
		return _fail("参数元数据缺少叶、数组或对象登记")
	for entry in arrays:
		if not entry is Dictionary or not _valid_meta_path(entry.get("path", null)):
			return _fail("数组元数据包含非法路径")
		_array_paths[entry["path"]] = true
	var rule_id: Variant = rule.get("rule_id", null)
	var severity: Variant = rule.get("severity", null)
	if not rule_id is String or not severity is String or rule_id != LOCK_RULE or severity != "阻止保存":
		return _fail("V-014 规则未登记为阻止保存")
	var code: Variant = rule.get("error_code", null)
	if not code is String or code.is_empty() or template.is_empty():
		return _fail("V-014 文案编号或模板无效")
	_rule = rule.duplicate(true)
	_template = template
	_ready = true
	return true

# 只检查锁定覆盖，不执行解析/写入；调用方须在发布 T-030 resolved 前合并 diagnostics。
func check(cfg: Dictionary) -> Dictionary:
	if not _ready:
		last_error = last_error if not last_error.is_empty() else "尚未配置锁定检查素材"
		return {"ok": false, "diagnostics": [_invalid("lock_guard", last_error)]}
	last_error = ""
	var result: Dictionary = {"ok": true, "diagnostics": []}
	if not cfg.has("params"):
		return result
	var params_value: Variant = cfg["params"]
	if not params_value is Dictionary:
		_append_invalid(result, "params", "参数对象类型无效")
		return result
	if not params_value.has("brick_overrides"):
		return result
	var overrides: Variant = params_value["brick_overrides"]
	var bricks: Variant = cfg.get("bricks", null)
	if not overrides is Array or not bricks is Array:
		_append_invalid(result, "params.brick_overrides", "覆盖表或积木表必须是数组")
		return result
	for index in range(overrides.size()):
		var base: String = "params.brick_overrides[%d]" % index
		var override: Variant = overrides[index]
		if not override is Dictionary:
			_append_invalid(result, base, "覆盖项必须是对象")
			continue
		var brick_index: Variant = override.get("brick_index", null)
		if not brick_index is int or brick_index < 0 or brick_index >= bricks.size():
			_append_invalid(result, base + ".brick_index", "积木索引必须为已登记整数下标")
			continue
		var card: Variant = bricks[brick_index]
		if not card is Dictionary or not card.has("locked_params"):
			_append_invalid(result, "bricks[%d].locked_params" % brick_index, "积木缺少锁定登记")
			continue
		var locked: Variant = card["locked_params"]
		if not locked is Dictionary:
			_append_invalid(result, "bricks[%d].locked_params" % brick_index, "锁定登记必须是对象")
			continue
		var locks: Array[String] = []
		var valid: bool = true
		for key in locked:
			if not _valid_path(key) or not locked[key] is String or locked[key].strip_edges().is_empty():
				_append_invalid(result, "bricks[%d].locked_params[%s]" % [brick_index, str(key)], "锁定路径和理由必须是非空字符串")
				valid = false
				continue
			locks.append(key)
		if not valid:
			continue
		var values: Variant = override.get("values", null)
		if not values is Dictionary:
			_append_invalid(result, base + ".values", "覆盖值必须是对象")
			continue
		var leaves_out: Array[Dictionary] = []
		_collect(values, "params", "", leaves_out, result, base + ".values")
		for leaf in leaves_out:
			var path: String = leaf["path"]
			for locked_path in locks:
				if _matches(locked_path, path):
					var location: String = base + ".values." + leaf["relative"]
					var reason: String = locked[locked_path]
					var message: String = _template.replace("{field}", location).replace("{source}", "作者覆盖").replace("{contract}", reason)
					result.diagnostics.append({"rule_id": _rule["rule_id"], "code": _rule["error_code"], "severity": 0, "path": location, "actual": str(leaf["value"]), "expected": reason, "message": message})
					result.ok = false
					break
	return result

func _collect(value: Variant, path: String, relative: String, output: Array[Dictionary], result: Dictionary, input_path: String) -> void:
	var schema_path: String = path.trim_prefix("params.")
	if value is Dictionary and not _array_paths.has(schema_path):
		if value.is_empty() and not relative.is_empty():
			output.append({"path": path, "relative": relative, "value": value})
		for key in value:
			if not key is String or not _valid_path(key) or key.contains("."):
				_append_invalid(result, input_path + "[" + str(key) + "]", "覆盖键必须是单个合法路径段")
				continue
			var next_path: String = path if path == "params" and relative.is_empty() and key == "params" else path + "." + key
			var next_relative: String = key if relative.is_empty() else relative + "." + key
			_collect(value[key], next_path, next_relative, output, result, input_path + "." + key)
		return
	if not relative.is_empty():
		output.append({"path": path, "relative": relative, "value": value})

func _matches(locked_path: String, leaf_path: String) -> bool:
	var path: String = leaf_path
	while not path.is_empty():
		if path == locked_path or path.ends_with("." + locked_path):
			return true
		var last_dot: int = path.rfind(".")
		if last_dot < 0:
			break
		path = path.substr(0, last_dot)
	return false

# 素材登记路径：允许 `[i]` 下标段（`templates[i].parts`），因为素材描述的是 Schema 形状
func _valid_meta_path(value: Variant) -> bool:
	if not value is String or value.is_empty():
		return false
	for segment in value.replace("[i]", "").split("."):
		if segment.is_empty() or segment.strip_edges() != segment:
			return false
	return true

# 作者输入的键：必须是单个合法路径段，严禁 `[` `]`（下标由解析器生成，不接受作者手填）
func _valid_path(value: Variant) -> bool:
	if not value is String or value.is_empty():
		return false
	for segment in value.split("."):
		if segment.is_empty() or segment.strip_edges() != segment or segment.contains("[") or segment.contains("]"):
			return false
	return true

func _csv_row(path: String, id_column: String, identifier: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var header: PackedStringArray = file.get_csv_line()
	if not header.is_empty():
		header[0] = header[0].trim_prefix("﻿")
	if not header.has(id_column):
		file.close()
		return {}
	while not file.eof_reached():
		var fields: PackedStringArray = file.get_csv_line()
		if fields.size() != header.size() or fields[header.find(id_column)] != identifier:
			continue
		var row: Dictionary = {}
		for index in range(header.size()):
			row[header[index]] = fields[index]
		file.close()
		return row
	file.close()
	return {}

func _append_invalid(result: Dictionary, path: String, message: String) -> void:
	result.ok = false
	result.diagnostics.append(_invalid(path, message))

func _invalid(path: String, message: String) -> Dictionary:
	last_error = message
	return {"rule_id": "LOCK_GUARD_SETUP", "code": "LOCK_GUARD_INVALID", "severity": 0, "path": path, "message": message}

func _fail(message: String) -> bool:
	last_error = message
	return false
