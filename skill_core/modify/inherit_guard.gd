class_name InheritGuard
extends RefCounted

const Diag = preload("res://skill_core/api/diagnostic.gd")
const TARGETS_PATH: String = "res://data/protected_targets.json"
const RULES_PATH: String = "res://data/validation_rules.csv"
const MESSAGES_PATH: String = "res://data/error_messages.csv"
static var _json_cache: Dictionary = {}

var last_error: String = ""
var _ready: bool = false
var _match_mode: String = ""
var _groups: Dictionary = {}
var _rules: Dictionary = {}
var _messages: Dictionary = {}

func configure_from_file(targets_path: String = TARGETS_PATH, rules_path: String = RULES_PATH, messages_path: String = MESSAGES_PATH) -> bool:
	_ready = false
	last_error = ""
	for path in [targets_path, rules_path, messages_path]:
		if not path.begins_with("res://data/"):
			return _fail("机器素材必须从 res://data/ 读取: %s" % path)
	var target_data: Variant = _load_json(targets_path)
	if not target_data is Dictionary:
		return false
	var rules: Dictionary = _load_rules(rules_path)
	if rules.is_empty():
		return _fail("无法读取验证规则素材: %s" % rules_path)
	var messages: Dictionary = _load_messages(messages_path)
	if messages.is_empty():
		return _fail("无法读取错误文案素材: %s" % messages_path)
	return configure(target_data, rules, messages)

# rules/messages 可注入，便于 headless 测试；未注入时只接受显式空表，不猜测严重度。
func configure(targets: Dictionary, rules: Variant = null, messages: Variant = null) -> bool:
	_ready = false
	last_error = ""
	_match_mode = ""
	_groups.clear()
	_rules.clear()
	_messages.clear()
	if rules == null:
		rules = _load_rules(RULES_PATH)
	if messages == null:
		messages = _load_messages(MESSAGES_PATH)
	if not rules is Dictionary or rules.is_empty():
		return _fail("严重度规则必须是非空 Dictionary")
	if not messages is Dictionary or messages.is_empty():
		return _fail("错误文案必须是非空 Dictionary")
	if not _validate_targets(targets):
		return false
	if not _configure_rules(rules):
		return false
	for code in messages:
		if not code is String or not messages[code] is String:
			return _fail("错误文案必须是 code -> template 字符串表")
	_messages = messages.duplicate(true)
	_ready = true
	return true

# value 可以是：目标路径数组、单个修饰器对象、修饰器对象数组，或含 params.modifiers 的 CFG。
# 修饰器显式 inheritable=false 时不参与继承边界检查；缺省不替作者发明开关，按已传入目标检查。
func check(value: Variant, inherited: bool = true) -> Dictionary:
	if not _ready:
		return _unavailable()
	last_error = ""
	var result: Dictionary = {"ok": true, "diagnostics": [], "notices": []}
	if not inherited:
		return result
	_check_value(value, result, "")
	return result

func check_inheritance(value: Variant) -> Dictionary:
	return check(value, true)

func validate(value: Variant) -> Dictionary:
	return check(value, true)

func _check_value(value: Variant, result: Dictionary, default_path: String) -> void:
	if value is String:
		_check_target(value, default_path if not default_path.is_empty() else value, result)
		return
	if value is Array:
		if value.is_empty():
			_append_invalid(result, default_path if not default_path.is_empty() else "targets", "继承目标不能是空数组")
			return
		for index in range(value.size()):
			var entry: Variant = value[index]
			var entry_path: String = "%s[%d]" % [default_path, index] if not default_path.is_empty() else "targets[%d]" % index
			_check_value(entry, result, entry_path)
		return
	if not value is Dictionary:
		_append_invalid(result, default_path if not default_path.is_empty() else "targets", "继承目标必须是路径、对象或数组")
		return
	if value.has("params") and value["params"] is Dictionary:
		var modifiers: Variant = value["params"].get("modifiers", null)
		if modifiers == null and not value["params"].has("modifiers"):
			_append_invalid(result, "params.modifiers", "CFG 缺少修饰器数组")
			return
		_check_value(modifiers, result, "params.modifiers")
		return
	if value.has("targets"):
		var inheritable: Variant = value.get("inheritable", null)
		if inheritable is bool and not inheritable:
			return
		var targets: Variant = value.get("targets", null)
		if not targets is Array or targets.is_empty():
			_append_invalid(result, default_path + ".targets" if not default_path.is_empty() else "targets", "继承目标必须是非空数组")
			return
		for index in range(targets.size()):
			var target: Variant = targets[index]
			var target_path: String = "%s.targets[%d]" % [default_path, index] if not default_path.is_empty() else "targets[%d]" % index
			if not target is String:
				_append_invalid(result, target_path, "修饰器目标路径必须是字符串")
			else:
				_check_target(target, target_path, result)
		return
	# A dictionary is also accepted as a path map, but only keys are inspected.
	if value.is_empty():
		_append_invalid(result, default_path if not default_path.is_empty() else "targets", "继承目标对象为空")
		return
	for key in value:
		var key_path: String = "%s.%s" % [default_path, str(key)] if not default_path.is_empty() else str(key)
		if not key is String:
			_append_invalid(result, key_path, "修饰器目标路径必须是字符串")
		else:
			_check_target(key, key_path, result)

func _check_target(target: String, diagnostic_path: String, result: Dictionary) -> void:
	if not _valid_target_path(target):
		_append_invalid(result, diagnostic_path, "修饰器目标路径必须为非空字符串且不得含数组下标")
		return
	var segments: PackedStringArray = target.split(".")
	for group_name in _groups:
		var group: Dictionary = _groups[group_name]
		var protected: Array = group["segments"]
		var matched: bool = false
		for segment in segments:
			if protected.has(segment):
				matched = true
				break
		if not matched:
			continue
		for rule_id in group["rule_ids"]:
			_emit(result, str(rule_id), diagnostic_path, target, "受保护目标不得由继承修饰器修改")

func _validate_targets(targets: Dictionary) -> bool:
	var mode: Variant = targets.get("match_mode", null)
	if not mode is String or mode.is_empty():
		return _fail("受保护目标未登记 match_mode")
	_match_mode = mode
	if _match_mode != "segment":
		return _fail("未支持的受保护目标 match_mode: %s" % _match_mode)
	var groups: Variant = targets.get("groups", null)
	if not groups is Dictionary or groups.is_empty():
		return _fail("受保护目标 groups 缺失或为空")
	for group_name in groups:
		if str(group_name).begins_with("_"):
			continue
		var raw: Variant = groups[group_name]
		if not raw is Dictionary:
			return _fail("受保护组必须是 Dictionary: %s" % str(group_name))
		var rule_ids: Variant = raw.get("rule_ids", null)
		var segments: Variant = raw.get("segments", null)
		if not rule_ids is Array or rule_ids.is_empty() or not segments is Array or segments.is_empty():
			return _fail("受保护组缺少 rule_ids / segments: %s" % str(group_name))
		var clean_rules: Array[String] = []
		for rule_id in rule_ids:
			if not rule_id is String or rule_id.is_empty() or clean_rules.has(rule_id):
				return _fail("受保护组含非法 rule_id: %s" % str(group_name))
			clean_rules.append(rule_id)
		var clean_segments: Array[String] = []
		for segment in segments:
			if not segment is String or not _valid_segment(segment) or clean_segments.has(segment):
				return _fail("受保护组含非法路径段: %s" % str(group_name))
			clean_segments.append(segment)
		_groups[str(group_name)] = {"rule_ids": clean_rules, "segments": clean_segments}
	if _groups.is_empty():
		return _fail("受保护组缺失")
	return true

func _configure_rules(rules: Dictionary) -> bool:
	for group_name in _groups:
		var group: Dictionary = _groups[group_name]
		for rule_id in group["rule_ids"]:
			var raw: Variant = rules.get(rule_id, null)
			if not raw is Dictionary:
				return _fail("缺少严重度规则素材: %s" % str(rule_id))
			var severity: Variant = raw.get("severity", null)
			var code: Variant = raw.get("error_code", raw.get("code", null))
			var severity_value: int = _severity_value(severity)
			if severity_value < 0 or not code is String or code.is_empty():
				return _fail("规则严重度或错误码无效: %s" % str(rule_id))
			_rules[rule_id] = {"severity": severity_value, "code": code}
	return true

func _severity_value(value: Variant) -> int:
	if value is int:
		return int(value) if int(value) in [Diag.SEV_BLOCK, Diag.SEV_WARN, Diag.SEV_HINT] else -1
	if not value is String:
		return -1
	match value:
		"阻止保存": return Diag.SEV_BLOCK
		"警告": return Diag.SEV_WARN
		"提示": return Diag.SEV_HINT
	return -1

func _emit(result: Dictionary, rule_id: String, path: String, actual: String, expected: String) -> void:
	if not _rules.has(rule_id):
		_append_invalid(result, path, "未登记受保护规则: %s" % rule_id)
		return
	var rule: Dictionary = _rules[rule_id]
	var diagnostic = Diag.new()
	diagnostic.rule_id = rule_id
	diagnostic.code = rule["code"]
	diagnostic.severity = rule["severity"]
	diagnostic.path = path
	diagnostic.actual = actual
	diagnostic.expected = expected
	var template: String = str(_messages.get(rule["code"], ""))
	if template.is_empty():
		diagnostic.hint = "缺失文案模板 %s（规则 %s）：%s" % [rule["code"], rule_id, path]
		result["notices"].append("缺失文案模板 %s" % rule["code"])
	else:
		diagnostic.hint = template.replace("{field}", path).replace("{path}", path).replace("{actual}", actual).replace("{source}", "继承修饰器").replace("{contract}", expected).replace("{expected}", expected)
	result["diagnostics"].append(diagnostic)
	if diagnostic.severity == Diag.SEV_BLOCK:
		result["ok"] = false

func _append_invalid(result: Dictionary, path: String, message: String) -> void:
	result["ok"] = false
	result["diagnostics"].append(_invalid(path, message))

func _invalid(path: String, message: String) -> Diagnostic:
	last_error = message
	var diagnostic = Diag.new()
	diagnostic.rule_id = "INHERIT_GUARD_SETUP"
	diagnostic.code = "INHERIT_GUARD_INVALID"
	diagnostic.severity = Diag.SEV_BLOCK
	diagnostic.path = path
	diagnostic.actual = message
	diagnostic.expected = "合法继承目标"
	diagnostic.hint = message
	return diagnostic

func _unavailable() -> Dictionary:
	var message: String = last_error if not last_error.is_empty() else "尚未配置继承边界素材"
	return {"ok": false, "diagnostics": [_invalid("validation_context", message)], "notices": [message]}

func _valid_target_path(path: String) -> bool:
	if path.is_empty() or path.contains("[") or path.contains("]"):
		return false
	for segment in path.split("."):
		if not _valid_segment(segment):
			return false
	return true

func _valid_segment(segment: String) -> bool:
	return not segment.is_empty() and segment.strip_edges() == segment and segment.is_valid_identifier()

func _load_json(path: String) -> Variant:
	var cached: Variant = _json_cache.get(path, null)
	if cached != null:
		return cached.duplicate(true)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail_value("无法读取受保护目标素材: %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return _fail_value("受保护目标 JSON 无效: %s" % path)
	_json_cache[path] = parsed.duplicate(true)
	return parsed

func _load_rules(path: String) -> Dictionary:
	var rows: Dictionary = {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("无法读取验证规则素材: %s" % path)
		return rows
	var header: PackedStringArray = file.get_csv_line()
	if not header.is_empty():
		header[0] = header[0].trim_prefix("﻿")
	while not file.eof_reached():
		var fields: PackedStringArray = file.get_csv_line()
		if fields.size() != header.size() or fields.is_empty():
			continue
		var row: Dictionary = {}
		for index in range(header.size()):
			row[header[index]] = fields[index]
		if row.has("rule_id"):
			rows[row["rule_id"]] = row
	file.close()
	return rows

func _load_messages(path: String) -> Dictionary:
	var rows: Dictionary = {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("无法读取错误文案素材: %s" % path)
		return rows
	var header: PackedStringArray = file.get_csv_line()
	if not header.is_empty():
		header[0] = header[0].trim_prefix("﻿")
	while not file.eof_reached():
		var fields: PackedStringArray = file.get_csv_line()
		if fields.size() != header.size() or fields.is_empty():
			continue
		var row: Dictionary = {}
		for index in range(header.size()):
			row[header[index]] = fields[index]
		if row.has("code"):
			rows[row["code"]] = str(row.get("template", ""))
	file.close()
	return rows

func _fail(message: String) -> bool:
	last_error = message
	return false

func _fail_value(message: String) -> Variant:
	last_error = message
	return null
