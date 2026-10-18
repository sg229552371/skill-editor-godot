class_name DiagnosticSorter
extends RefCounted

const Diag = preload("res://skill_core/api/diagnostic.gd")
const META_PATH: String = "res://data/diagnostic_meta.json"
const API_FIELDS: Array[String] = ["rule_id", "code", "path", "actual", "expected", "severity", "hint"]
const MAX_INDEX: String = "2147483647"

static var _metadata_loaded: bool = false
static var _metadata_cache: Dictionary = {}

var last_error: String = ""
var _ready: bool = false
var _severity_order: Array = []
var _field_order: Array = []
var _dedupe_keys: Array = []

static func load_metadata() -> Dictionary:
	if _metadata_loaded:
		return _metadata_cache.duplicate(true)
	_metadata_loaded = true
	var file: FileAccess = FileAccess.open(META_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	var parsed: Dictionary = parser.data
	_metadata_cache = parsed.duplicate(true)
	return _metadata_cache.duplicate(true)

func configure(metadata: Dictionary) -> bool:
	_ready = false
	last_error = ""
	_severity_order.clear()
	_field_order.clear()
	_dedupe_keys.clear()
	var severities: Variant = metadata.get("severity_order", null)
	var fields: Variant = metadata.get("field_order", null)
	var keys: Variant = metadata.get("dedupe_keys", null)
	if not severities is Array or severities.is_empty():
		return _fail("severity_order 必须是非空数组")
	if not fields is Array or fields.is_empty():
		return _fail("field_order 必须是非空数组")
	if not keys is Array or keys.size() != 5:
		return _fail("dedupe_keys 必须是五字段数组")
	for value in severities:
		if not (value is int or value is float):
			return _fail("severity_order 含非数字")
		var number: float = float(value)
		if not is_finite(number) or floor(number) != number or absf(number) > 2147483647.0:
			return _fail("severity_order 含非有限或非整数")
		if _severity_order.has(int(number)):
			return _fail("severity_order 有重复值")
		_severity_order.append(int(number))
	for field in fields:
		if not field is String or field.is_empty() or not field.is_valid_identifier():
			return _fail("field_order 含非法首段")
		if _field_order.has(field):
			return _fail("field_order 有重复值")
		_field_order.append(field)
	for key in keys:
		if not key is String or not API_FIELDS.has(key) or _dedupe_keys.has(key):
			return _fail("dedupe_keys 含重复或未知字段")
		_dedupe_keys.append(key)
	_ready = true
	return true

func sort_diagnostics(diagnostics: Array) -> Dictionary:
	if not _ready:
		return _failure(last_error if not last_error.is_empty() else "未配置诊断排序元数据")
	last_error = ""
	var records: Array = []
	for item in diagnostics:
		var values: Dictionary = _values(item)
		if not last_error.is_empty():
			return _failure(last_error)
		var severity: int = _severity_order.find(values["severity"])
		if severity < 0:
			return _failure("诊断严重度不在 severity_order 内")
		var indices: Array = _path_indices(values["path"])
		if not last_error.is_empty():
			return _failure(last_error)
		var root: String = values["path"].get_slice(".", 0).get_slice("[", 0)
		var field: int = _field_order.find(root)
		if field < 0:
			return _failure("诊断 path 首段不在 field_order 内: %s" % root)
		records.append({"source": item, "values": values, "severity": severity,
			"field": field, "indices": indices})
	var unique: Array = []
	var duplicates: Array = []
	var seen: Dictionary = {}
	for record in records:
		var parts: Array = []
		for key in _dedupe_keys:
			parts.append(record["values"][key])
		var fingerprint: String = JSON.stringify(parts)
		if seen.has(fingerprint):
			duplicates.append(record["source"])
		else:
			seen[fingerprint] = true
			unique.append(record)
	# Insertion sort retains arrival order when all configured sort keys tie.
	for index in range(1, unique.size()):
		var current: Dictionary = unique[index]
		var position: int = index
		while position > 0 and _less(current, unique[position - 1]):
			unique[position] = unique[position - 1]
			position -= 1
		unique[position] = current
	var sorted: Array = []
	for record in unique:
		sorted.append(record["source"])
	return {"ok": true, "diagnostics": sorted, "removed": duplicates.size(),
		"duplicates": duplicates, "error": ""}

func _values(item: Variant) -> Dictionary:
	var fields: Dictionary = {}
	if item is Diag:
		fields = item.to_dict()
	elif item is Dictionary:
		fields = item
	else:
		_fail("诊断必须是 Diagnostic 或 Dictionary")
		return {}
	for key in API_FIELDS:
		if not fields.has(key):
			_fail("诊断缺少字段: %s" % key)
			return {}
		var value: Variant = fields[key]
		if key == "severity":
			if not value is int:
				_fail("诊断 severity 必须是整数")
				return {}
		elif not value is String:
			_fail("诊断 %s 必须是字符串" % key)
			return {}
	if fields["rule_id"].is_empty() or fields["code"].is_empty() or fields["path"].is_empty():
		_fail("诊断 rule_id、code、path 不得为空")
		return {}
	return fields

func _path_indices(path: String) -> Array:
	var indices: Array = []
	for segment in path.split("."):
		var name: String = segment.get_slice("[", 0)
		if name.is_empty() or not name.is_valid_identifier():
			_fail("诊断 path 含非法字段段: %s" % path)
			return []
		var cursor: int = name.length()
		while cursor < segment.length():
			if segment[cursor] != "[":
				_fail("诊断 path 含非法下标: %s" % path)
				return []
			var close: int = segment.find("]", cursor + 1)
			if close < 0 or close == cursor + 1:
				_fail("诊断 path 含非法下标: %s" % path)
				return []
			var digits: String = segment.substr(cursor + 1, close - cursor - 1)
			for character in digits:
				if not "0123456789".contains(character):
					_fail("诊断 path 含非有限下标: %s" % path)
					return []
			while digits.length() > 1 and digits.begins_with("0"):
				digits = digits.substr(1)
			if digits.length() > MAX_INDEX.length() or (digits.length() == MAX_INDEX.length() and digits > MAX_INDEX):
				_fail("诊断 path 下标超出有限范围: %s" % path)
				return []
			indices.append(digits)
			cursor = close + 1
	return indices

func _less(left: Dictionary, right: Dictionary) -> bool:
	if left["severity"] != right["severity"]:
		return left["severity"] < right["severity"]
	if left["field"] != right["field"]:
		return left["field"] < right["field"]
	var a: Array = left["indices"]
	var b: Array = right["indices"]
	for index in range(mini(a.size(), b.size())):
		if a[index].length() != b[index].length():
			return a[index].length() < b[index].length()
		if a[index] != b[index]:
			return a[index] < b[index]
	if a.size() != b.size():
		return a.size() < b.size()
	return left["values"]["rule_id"] < right["values"]["rule_id"]

func _fail(message: String) -> bool:
	last_error = message
	return false

func _failure(message: String) -> Dictionary:
	last_error = message
	return {"ok": false, "diagnostics": [], "removed": 0, "duplicates": [], "error": message}
