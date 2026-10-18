class_name CfgSchema
extends RefCounted

const CfgCodec = preload("res://skill_core/schema/cfg_codec.gd")
const Diag = preload("res://skill_core/api/diagnostic.gd")
const SCHEMA_PATH: String = "res://data/schema_meta.json"
const PARAMS_PATH: String = "res://data/params_meta.json"

var last_error: String = ""
var _definitions: Dictionary = {}
var _children: Dictionary = {}
var _ready: bool = false

func configure(schema_path: String = SCHEMA_PATH, params_path: String = PARAMS_PATH) -> bool:
	var schema: Variant = _read_json(schema_path)
	if not schema is Dictionary:
		return _fail("结构元数据缺失或非法: %s" % schema_path)
	var params: Variant = _read_json(params_path)
	if not params is Dictionary:
		return _fail("参数元数据缺失或非法: %s" % params_path)
	return configure_from_data(schema, params)

func configure_from_data(schema: Dictionary, params: Dictionary) -> bool:
	_ready = false
	last_error = ""
	_definitions.clear()
	_children.clear()
	for key in ["root", "brick", "brick_arrays", "meta", "params", "presentation", "presentation_sections", "runtime_hints", "runtime_enums", "version"]:
		if not schema.has(key):
			return _fail("结构元数据未登记: %s" % key)
	for key in ["leaves", "arrays", "objects", "tick_fields", "enums"]:
		if not params.has(key):
			return _fail("参数元数据未登记: %s" % key)
	if not _same_keys(schema.root, CfgCodec.TOP_LEVEL_KEYS) or not _same_keys(schema.brick, CfgCodec.BRICK_KEYS):
		return _fail("结构元数据与冻结七键/十二字段不一致")
	if not _same_values(schema.presentation, CfgCodec.PRESENTATION_KEYS):
		return _fail("结构元数据与冻结七表现段不一致")
	if not params.leaves is Array or not params.arrays is Array or not params.objects is Array or not params.tick_fields is Array or not params.enums is Dictionary:
		return _fail("参数元数据表形状非法")
	_put("", "object", {"required": CfgCodec.TOP_LEVEL_KEYS, "additional_properties": false})
	for field in CfgCodec.TOP_LEVEL_KEYS:
		_put(field, str(schema.root[field]))
	_put("bricks[i]", "object", {"required": CfgCodec.BRICK_KEYS, "additional_properties": false})
	for field in CfgCodec.BRICK_KEYS:
		_put("bricks[i]." + field, str(schema.brick[field]))
	for field in schema.brick_arrays:
		_put("bricks[i]." + str(field) + "[i]", str(schema.brick_arrays[field]))
	_set_enum("bricks[i].carrier", CfgCodec.CARRIERS)
	_set_enum("bricks[i].status", CfgCodec.STATUSES)
	_set_enum("bricks[i].presentation[i]", CfgCodec.PRESENTATION_KEYS)
	_put("meta", "object", {"required": schema.meta.required, "additional_properties": false})
	_register_fields("meta", schema.meta)
	_put("presentation", "object", {"required": CfgCodec.PRESENTATION_KEYS, "additional_properties": false})
	for field in CfgCodec.PRESENTATION_KEYS:
		var section: Variant = schema.presentation_sections.get(field, null)
		if not section is Dictionary or not section.has("fields"):
			return _fail("表现段元数据未登记: %s" % field)
		var section_path: String = "presentation." + field
		_put(section_path, "object", {"required": section.get("required", []), "additional_properties": false})
		_register_fields(section_path, section)
		if section.get("codec_carrier", false) == true:
			_set_enum(section_path + ".carrier", CfgCodec.CARRIERS)
	_put("runtime_hints", "object", {"additional_properties": false})
	for field in schema.runtime_hints:
		_put("runtime_hints." + str(field), str(schema.runtime_hints[field]))
	for field in schema.runtime_enums:
		_set_enum("runtime_hints." + str(field), schema.runtime_enums[field])
	_put("schema_version", "string", {"enum": [schema.version]})
	_put("params", "object", schema.params)
	for leaf in params.leaves:
		if not leaf is Dictionary or not leaf.has("path") or not leaf.has("type"):
			return _fail("参数叶字段元数据非法")
		var path: String = "params." + str(leaf.path)
		var options: Dictionary = {}
		if leaf.has("enum"):
			options["enum"] = leaf.enum
		_put(path, str(leaf.type), options)
	for array_entry in params.arrays:
		if not array_entry is Dictionary or not array_entry.has("path") or not array_entry.has("item_kind"):
			return _fail("参数数组元数据非法")
		var path: String = "params." + str(array_entry.path)
		_put(path, "array")
		var item: Variant = array_entry.get("item", null)
		var options: Dictionary = {}
		if item is Dictionary and item.has("enum"):
			options["enum"] = item.enum
		_put(path + "[i]", str(array_entry.item_kind), options)
	for obj in params.objects:
		if not obj is Dictionary or not obj.has("path") or not obj.has("required") or not obj.has("additional_properties"):
			return _fail("参数对象元数据非法")
		var path: String = "params" if obj.path == "params" else "params." + str(obj.path)
		_put(path, "object", {"required": obj.required, "additional_properties": obj.additional_properties})
	for tick in params.tick_fields:
		var path: String = "params." + str(tick)
		if not _definitions.has(path) or _definitions[path].get("type") != "integer":
			return _fail("tick 字段未登记为整数: %s" % path)
	for field in params.enums:
		if str(field).begins_with("_"):
			continue
		var choices: Variant = params.enums[field]
		if not choices is Array or choices.is_empty():
			return _fail("参数枚举缺失: %s" % str(field))
	_ready = true
	return true

func validate(cfg: Variant) -> Dictionary:
	if not _ready:
		return {"ok": false, "diagnostics": [], "error": last_error if not last_error.is_empty() else "结构元数据尚未配置"}
	var diagnostics: Array = []
	_walk(cfg, "", "", diagnostics)
	return {"ok": diagnostics.is_empty(), "diagnostics": diagnostics, "error": ""}

func _walk(value: Variant, path: String, pattern: String, diagnostics: Array) -> void:
	var definition: Variant = _definitions.get(pattern, null)
	if not definition is Dictionary:
		_issue(diagnostics, path, value, "未登记结构路径")
		return
	var kind: String = str(definition.get("type", "unknown"))
	if not _matches(value, kind):
		_issue(diagnostics, path, value, kind)
		return
	var choices: Variant = definition.get("enum", null)
	if choices is Array and not choices.has(value):
		_issue(diagnostics, path, value, "枚举 %s" % str(choices))
	if value is Dictionary:
		var required: Variant = definition.get("required", [])
		if required is Array:
			for field in required:
				if not value.has(field):
					_issue(diagnostics, _join(path, str(field)), "<missing>", "必填")
		var allowed: Variant = _children.get(pattern, [])
		for key in value:
			var field: String = str(key)
			var child_path: String = _join(path, field)
			var child_pattern: String = _join(pattern, field)
			if not key is String or field.contains("[") or field.contains("]"):
				_issue(diagnostics, child_path, value[key], "合法字段名")
			elif allowed.has(field):
				_walk(value[key], child_path, child_pattern, diagnostics)
			elif definition.get("additional_properties", true) == false:
				_issue(diagnostics, child_path, value[key], "未登记附加键")
			else:
				_check_free(value[key], child_path, diagnostics)
	elif value is Array:
		var item_pattern: String = pattern + "[i]"
		for index in range(value.size()):
			var item_path: String = "%s[%d]" % [path, index]
			if _definitions.has(item_pattern):
				_walk(value[index], item_path, item_pattern, diagnostics)
			else:
				_check_free(value[index], item_path, diagnostics)

func _check_free(value: Variant, path: String, diagnostics: Array) -> void:
	if typeof(value) == TYPE_NIL or (value is float and not is_finite(value)):
		_issue(diagnostics, path, value, "非 null 的有限值")
	elif value is Array:
		for index in range(value.size()):
			_check_free(value[index], "%s[%d]" % [path, index], diagnostics)
	elif value is Dictionary:
		for key in value:
			var child: String = _join(path, str(key))
			if not key is String or str(key).contains("[") or str(key).contains("]"):
				_issue(diagnostics, child, value[key], "合法字段名")
			else:
				_check_free(value[key], child, diagnostics)

func _matches(value: Variant, kind: String) -> bool:
	match kind:
		"string", "ref": return value is String
		"ref?": return typeof(value) == TYPE_NIL or value is String
		"integer": return value is int
		"number": return (value is int or value is float) and is_finite(float(value))
		"boolean": return value is bool
		"object": return value is Dictionary
		"array": return value is Array
		"unknown": return typeof(value) != TYPE_NIL
	return false

func _register_fields(parent: String, source: Dictionary) -> void:
	for field in source.fields:
		_put(_join(parent, str(field)), str(source.fields[field]))
	for field in source.get("arrays", {}):
		_put(_join(parent, str(field)) + "[i]", str(source.arrays[field]))
	for field in source.get("enums", {}):
		var field_path: String = _join(parent, str(field))
		if source.get("arrays", {}).has(field):
			field_path += "[i]"
		_set_enum(field_path, source.enums[field])

func _put(path: String, kind: String, options: Dictionary = {}) -> void:
	var entry: Dictionary = {"type": kind}
	for key in options:
		entry[key] = options[key]
	_definitions[path] = entry
	if path.is_empty():
		return
	var parent: String = path.substr(0, path.rfind(".")) if path.contains(".") else ""
	var field: String = path.substr(path.rfind(".") + 1) if path.contains(".") else path
	if field.ends_with("[i]"):
		return
	if not _children.has(parent):
		_children[parent] = []
	if not _children[parent].has(field):
		_children[parent].append(field)

func _set_enum(path: String, choices: Variant) -> void:
	if _definitions.has(path):
		_definitions[path]["enum"] = choices

func _same_keys(value: Variant, keys: Array[String]) -> bool:
	if not value is Dictionary or value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true

func _same_values(value: Variant, keys: Array[String]) -> bool:
	if not value is Array or value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true

func _read_json(path: String) -> Variant:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return null
	return parser.data

func _issue(diagnostics: Array, path: String, actual: Variant, expected: String) -> void:
	diagnostics.append(Diag.make("V-019", "E-0011", path, str(actual), expected))

func _join(parent: String, field: String) -> String:
	return field if parent.is_empty() else parent + "." + field

func _fail(message: String) -> bool:
	last_error = message
	_ready = false
	return false
