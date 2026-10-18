class_name ExposedFields
extends RefCounted

const Diag = preload("res://skill_core/api/diagnostic.gd")
const METADATA_PATH: String = "res://data/exposed_fields_meta.json"
const MESSAGES_PATH: String = "res://data/error_messages.csv"

# 待素材替换：本卡明确许可的过渡表。必须显式 configure 此表；加载失败不回退。
# schema required 保持四项；min/max 的必填性来自 V-048，而非改写 Schema。
const TRANSITION_METADATA: Dictionary = {
	"input_path": "params.exposed_fields",
	"fields": {
		"field_path": {"type": "ref"},
		"permissions": {"type": "permissions"},
		"min": {"type": "number"},
		"max": {"type": "number"},
		"live": {"type": "boolean", "default": false},
		"inheritable": {"type": "boolean", "default": false},
		"set_conflict_note": {"type": "string"},
	},
	"required": ["field_path", "permissions", "live", "inheritable"],
	"permissions": ["mutate_number", "add_behavior", "mutate_live_instance"],
	"roles": {"reference": "field_path", "permissions": "permissions", "lower": "min", "upper": "max", "live": "live", "inheritable": "inheritable", "note": "set_conflict_note"},
	"live_permission": "mutate_live_instance",
}
const RULES: Dictionary = {
	"structure": {"id": "V-020", "code": "E-0012", "severity": Diag.SEV_BLOCK},
	"unknown": {"id": "V-019", "code": "E-0011", "severity": Diag.SEV_BLOCK},
	"bounds": {"id": "V-048", "code": "E-0026", "severity": Diag.SEV_BLOCK},
	"live": {"id": "V-045", "code": "E-0025", "severity": Diag.SEV_BLOCK},
	"set": {"id": "V-050", "code": "E-0027", "severity": Diag.SEV_WARN},
	"reference": {"id": "V-043", "code": "E-0024", "severity": Diag.SEV_BLOCK},
}
const ROLE_TYPES: Dictionary = {"reference": "ref", "permissions": "permissions", "lower": "number", "upper": "number", "live": "boolean", "inheritable": "boolean", "note": "string"}
static var _metadata_cache: Dictionary = {}

var last_error: String = ""
var _ready: bool = false
var _metadata: Dictionary = {}
var _messages: Dictionary = {}

func configure_from_file(path: String = METADATA_PATH, messages_path: String = MESSAGES_PATH) -> bool:
	_ready = false
	last_error = ""
	if not path.begins_with("res://data/"):
		return _fail("元数据必须从 res://data/ 载入: %s" % path)
	var metadata: Variant = _metadata_cache.get(path, null)
	if metadata == null:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			return _fail("无法读取暴露字段元数据: %s" % path)
		var parser: JSON = JSON.new()
		var error: Error = parser.parse(file.get_as_text())
		file.close()
		if error != OK or not parser.data is Dictionary:
			return _fail("暴露字段元数据 JSON 无效: %s；%s" % [path, parser.get_error_message()])
		metadata = parser.data
	if not configure(metadata, null, messages_path):
		return false
	_metadata_cache[path] = metadata.duplicate(true)
	return true

# messages 为 null 时读部署 CSV；显式 Dictionary 可用于注入/缺文案测试。
func configure(metadata: Dictionary, messages: Variant = null, messages_path: String = MESSAGES_PATH) -> bool:
	_ready = false
	last_error = ""
	_metadata = metadata.duplicate(true)
	_messages.clear()
	if not _validate_metadata():
		return false
	if messages == null:
		if not _load_messages(messages_path):
			return false
	elif messages is Dictionary:
		for code in messages:
			if not code is String or not messages[code] is String:
				return _fail("文案注入必须为 code -> template 字符串映射")
		_messages = messages.duplicate(true)
	else:
		return _fail("文案注入必须是 Dictionary")
	_ready = true
	return true

# context 是装配层的已解析事实，不是 CFG 字段：
# set_counts: {精确 field_path: 生效 set 数量}
# live_requests: [{field_path: 精确目标, permission: 物品实际申请权限或 null}]
# 只登记/检查，不施加修改，不碰 snapshot、历史或运行实例；V-047 实际拦截属 T-035。
func register_fields(cfg: Dictionary, context: Dictionary = {}) -> Dictionary:
	if not _ready:
		return _unavailable(last_error if not last_error.is_empty() else "尚未配置暴露字段元数据")
	last_error = ""
	var result: Dictionary = {"ok": true, "fields": {}, "sources": {}, "diagnostics": [], "notices": []}
	var root: String = _metadata.input_path
	var parent: Variant = cfg
	var prefix: String = ""
	var segments: PackedStringArray = root.split(".")
	for index in range(segments.size() - 1):
		var segment: String = segments[index]
		prefix = segment if prefix.is_empty() else prefix + "." + segment
		if not parent.has(segment):
			break
		parent = parent[segment]
		if not parent is Dictionary:
			_emit(result, "structure", prefix, _display(parent), "Dictionary")
			return _finish(result)
	var entries: Variant = _get_path(cfg, root)
	if entries == null and not _has_path(cfg, root):
		entries = [] # 未使用暴露能力是合法空登记，不补写 CFG。
	if not entries is Array:
		_emit(result, "structure", root, _display(entries), "array")
		return _finish(result)
	var fields: Dictionary = _metadata.fields
	var roles: Dictionary = _metadata.roles
	for index in range(entries.size()):
		var input_path: String = "%s[%d]" % [root, index]
		var entry: Variant = entries[index]
		if not entry is Dictionary:
			# 对非对象也给出实际必填槽位，不报成笼统的“暴露字段对象”。
			for field in _required_fields():
				_emit(result, _field_rule(field), input_path + "." + field, _display(entry), "对象内的必填槽位")
			continue
		var start: int = result.diagnostics.size()
		for field in fields:
			var path: String = input_path + "." + field
			if not entry.has(field):
				if _required_fields().has(field):
					_emit(result, _field_rule(field), path, "未填写", "必填 %s" % fields[field].type)
				continue
			if not _valid_value(entry[field], fields[field].type):
				_emit(result, _field_rule(field), path, _display(entry[field]), "合法 %s" % fields[field].type)
		for field in entry:
			if not fields.has(field):
				_emit(result, "unknown", input_path + "." + str(field), _display(entry[field]), "仅允许登记字段")
		var low: Variant = entry.get(roles.lower, null)
		var high: Variant = entry.get(roles.upper, null)
		if _valid_value(low, "number") and _valid_value(high, "number") and low > high:
			_emit(result, "bounds", input_path + "." + roles.lower, _display(low), "min <= max")
			_emit(result, "bounds", input_path + "." + roles.upper, _display(high), "max >= min")
		if result.diagnostics.size() != start:
			continue
		var reference: String = entry[roles.reference]
		if result.fields.has(reference):
			_emit(result, "reference", input_path + "." + roles.reference, reference, "字段引用必须唯一，不能隐式覆盖另一条登记")
			continue
		result.fields[reference] = entry.duplicate(true)
		var slots: Dictionary = {}
		for field in fields:
			slots[field] = input_path + "." + field
		result.sources[reference] = {"source": "params", "input_path": input_path, "slots": slots}
	_check_context(result, context)
	return _finish(result)

func _required_fields() -> Array:
	var required: Array = _metadata.required.duplicate()
	for role in ["lower", "upper"]:
		var field: String = _metadata.roles[role]
		if not required.has(field):
			required.append(field)
	return required

func _field_rule(field: String) -> String:
	return "bounds" if field in [_metadata.roles.lower, _metadata.roles.upper] else "structure"

func _valid_value(value: Variant, kind: String) -> bool:
	match kind:
		"ref":
			return value is String and not value.strip_edges().is_empty()
		"string":
			return value is String
		"boolean":
			return value is bool
		"number":
			return (value is int or value is float) and is_finite(float(value))
		"permissions":
			if not value is Array or value.is_empty():
				return false
			var seen: Dictionary = {}
			for permission in value:
				if not permission is String or not _metadata.permissions.has(permission) or seen.has(permission):
					return false
				seen[permission] = true
			return true
	return false

func _finish(result: Dictionary) -> Dictionary:
	if not result.ok:
		result.fields = {}
		result.sources = {}
	return result

func _get_path(root: Dictionary, path: String) -> Variant:
	var current: Variant = root
	for segment in path.split("."):
		if not current is Dictionary:
			return null
		current = current.get(segment, null)
	return current

func _has_path(root: Dictionary, path: String) -> bool:
	var current: Variant = root
	for segment in path.split("."):
		if not current is Dictionary or not current.has(segment):
			return false
		current = current[segment]
	return true

func _display(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Array and value.is_empty():
		return "空列表"
	return "%s (%s)" % [str(value), type_string(typeof(value))]

func _validate_metadata() -> bool:
	var input_path: Variant = _metadata.get("input_path", null)
	if not input_path is String or input_path.is_empty():
		return _fail("缺少 input_path")
	for segment in input_path.split("."):
		if segment.is_empty():
			return _fail("input_path 含空路径段")
	var fields: Variant = _metadata.get("fields", null)
	var roles: Variant = _metadata.get("roles", null)
	var required: Variant = _metadata.get("required", null)
	var permissions: Variant = _metadata.get("permissions", null)
	if not fields is Dictionary or fields.is_empty() or not roles is Dictionary:
		return _fail("缺少 fields / roles 元数据")
	if not required is Array or required.is_empty() or not permissions is Array or permissions.is_empty():
		return _fail("required / permissions 必须是非空数组")
	var seen: Dictionary = {}
	for permission in permissions:
		if not permission is String or permission.is_empty() or seen.has(permission):
			return _fail("权限枚举必须为非空、唯一字符串")
		seen[permission] = true
	var live_permission: Variant = _metadata.get("live_permission", null)
	if not live_permission is String or not permissions.has(live_permission):
		return _fail("live_permission 必须引用已登记权限")
	for field in fields:
		var descriptor: Variant = fields[field]
		if not field is String or field.is_empty() or not descriptor is Dictionary:
			return _fail("非法字段描述")
		var kind: Variant = descriptor.get("type", null)
		if not kind is String or not ROLE_TYPES.values().has(kind):
			return _fail("字段 %s 的类型未登记" % str(field))
		if descriptor.has("default") and not _valid_value(descriptor.default, kind):
			return _fail("字段 %s 的默认值类型无效" % str(field))
	seen.clear()
	for field in required:
		if not field is String or not fields.has(field) or seen.has(field):
			return _fail("required 含未登记或重复字段")
		seen[field] = true
	seen.clear()
	for role in ROLE_TYPES:
		var field: Variant = roles.get(role, null)
		if not field is String or not fields.has(field) or seen.has(field):
			return _fail("角色 %s 缺失、未登记或复用同一槽位" % role)
		if fields[field].type != ROLE_TYPES[role]:
			return _fail("角色 %s 类型不匹配" % role)
		seen[field] = true
	for role in ["reference", "permissions", "live", "inheritable"]:
		if not required.has(roles[role]):
			return _fail("required 缺少必填角色 %s" % role)
	return true

func _load_messages(path: String) -> bool:
	if not path.begins_with("res://data/"):
		return _fail("文案必须从 res://data/ 载入")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("无法读取文案 CSV: %s" % path)
	var header: PackedStringArray = file.get_csv_line()
	if not header.is_empty():
		header[0] = header[0].trim_prefix("﻿")
	for column in ["code", "template"]:
		if not header.has(column):
			return _fail("文案 CSV 缺少列 %s" % column)
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() == 1 and row[0].is_empty():
			continue
		if row.size() != header.size():
			return _fail("文案 CSV 列数错误")
		var code: String = row[header.find("code")]
		if code.is_empty() or _messages.has(code):
			return _fail("文案 CSV code 缺失或重复: %s" % code)
		_messages[code] = row[header.find("template")]
	file.close()
	if _messages.is_empty():
		return _fail("文案 CSV 为空")
	return true

func _emit(result: Dictionary, kind: String, path: String, actual: String, expected: String) -> void:
	var rule: Dictionary = RULES[kind]
	var diagnostic = Diag.new()
	diagnostic.rule_id = rule.id
	diagnostic.code = rule.code
	diagnostic.severity = rule.severity
	diagnostic.path = path
	diagnostic.actual = actual
	diagnostic.expected = expected
	var template: String = _messages.get(rule.code, "")
	var tokens: Dictionary = {"path": path, "field": path, "actual": actual, "expected": expected, "detail": expected, "target": path, "missing": expected, "reason": expected, "modifier": "已解析装配上下文", "version": "v0.1", "key": path}
	if template.is_empty():
		var notice: String = "缺失文案模板 %s（规则 %s）" % [rule.code, rule.id]
		if not result.notices.has(notice):
			result.notices.append(notice)
		template = "[%s/%s] %s：%s；要求 %s（%s）" % [rule.id, rule.code, path, actual, expected, notice]
	else:
		for token in tokens:
			template = template.replace("{%s}" % token, str(tokens[token]))
		if template.contains("{"):
			result.notices.append("文案 %s 有未解析占位符: %s" % [rule.code, template])
			template += " [文案元数据不完整]"
	diagnostic.hint = template
	result.diagnostics.append(diagnostic)
	if diagnostic.severity == Diag.SEV_BLOCK:
		result.ok = false

func _unavailable(message: String) -> Dictionary:
	last_error = message
	var diagnostic = Diag.new()
	diagnostic.rule_id = "EXPOSED_FIELDS_SETUP"
	diagnostic.code = "VALIDATION_METADATA_UNAVAILABLE"
	diagnostic.path = "validation_context"
	diagnostic.actual = message
	diagnostic.expected = "提供完整暴露元数据、文案与已解析上下文"
	diagnostic.hint = message
	return {"ok": false, "fields": {}, "sources": {}, "diagnostics": [diagnostic], "notices": [message]}

func _check_context(result: Dictionary, context: Dictionary) -> void:
	for key in context:
		if key not in ["set_counts", "live_requests"]:
			_context_failure(result, "未登记上下文键: %s" % str(key))
			return
	var counts: Variant = context.get("set_counts", null)
	if counts == null and not context.has("set_counts"):
		counts = {}
	var requests: Variant = context.get("live_requests", null)
	if requests == null and not context.has("live_requests"):
		requests = []
	if not counts is Dictionary or not requests is Array:
		_context_failure(result, "set_counts 必须为 Dictionary，live_requests 必须为 Array")
		return
	var roles: Dictionary = _metadata.roles
	for reference in counts:
		var count: Variant = counts[reference]
		if not reference is String or not result.fields.has(reference):
			_context_failure(result, "set_counts 引用未成功登记的目标: %s" % str(reference))
			continue
		if not (count is int or count is float) or not is_finite(float(count)) or count < 0 or float(count) != floor(float(count)):
			_context_failure(result, "set_counts 必须为非负整数值: %s" % reference)
			continue
		var entry: Dictionary = result.fields[reference]
		var source: Dictionary = result.sources[reference]
		var note: Variant = entry.get(roles.note, null)
		if count > 1 and (not note is String or note.strip_edges().is_empty()):
			_emit(result, "set", source.slots[roles.note], "未填写" if not entry.has(roles.note) else _display(note), "说明最后挂载者覆盖")
	for request in requests:
		if not request is Dictionary:
			_context_failure(result, "live_requests 条目必须为 Dictionary")
			continue
		var reference: Variant = request.get(roles.reference, null)
		if not reference is String or not result.fields.has(reference):
			_context_failure(result, "live_requests 引用未成功登记的目标: %s" % str(reference))
			continue
		var entry: Dictionary = result.fields[reference]
		var source: Dictionary = result.sources[reference]
		var permission: Variant = request.get("permission", null)
		var missing: Array[String] = []
		if permission != _metadata.live_permission:
			missing.append("物品申请必须为 %s" % _metadata.live_permission)
		if not entry[roles.permissions].has(_metadata.live_permission):
			missing.append("目标 permissions 未登记 %s" % _metadata.live_permission)
		if not missing.is_empty():
			_emit(result, "live", source.slots[roles.permissions], _display(permission), "；".join(missing))
		if not entry[roles.live]:
			_emit(result, "live", source.slots[roles.live], _display(entry[roles.live]), "目标 live 暴露必须为 true")

func _context_failure(result: Dictionary, message: String) -> void:
	var failure: Dictionary = _unavailable(message)
	result.diagnostics.append_array(failure.diagnostics)
	result.notices.append_array(failure.notices)
	result.ok = false

func _fail(message: String) -> bool:
	last_error = message
	return false
