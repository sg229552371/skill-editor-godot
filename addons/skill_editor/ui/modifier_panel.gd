@tool
extends VBoxContainer

## Draft editor only: no persistence, runtime authorization or validation verdict.
signal draft_changed(draft: Dictionary)

var last_error: String = "尚未 configure 修饰器面板"
var _configured: bool = false
var _draft: Dictionary = {}
var _entries: Array = []
var _exposed: Array = []
var _meta: Dictionary = {}
var _item_policy: Dictionary = {}
var _view: Dictionary = {}
var _rows: Array = []
var _controls: Dictionary = {}
var _exposed_controls: Dictionary = {}

func _ready() -> void:
	if not _configured:
		_show_error(last_error)

# entries: [{definition: 六字段对象, access: 展示权限key, priority?: 展示信息}]
# item_policy.ui_access 必须由宿主注入；部署素材没有 UI 三档映射，不猜测。
func configure(cfg: Dictionary, entries: Array, exposed: Array,
		metadata: Dictionary = {}, item_policy: Dictionary = {},
		relic_policy: Dictionary = {}, view: Dictionary = {}) -> Dictionary:
	_configured = false
	_clear()
	_meta = metadata.duplicate(true)
	_item_policy = item_policy.duplicate(true)
	_view = view.duplicate(true)
	if _meta.is_empty():
		_meta = _load("res://data/exposed_fields_meta.json")
	if _item_policy.is_empty():
		_item_policy = _load("res://data/item_permission_policy.json")
	var relic: Dictionary = relic_policy.duplicate(true)
	if relic.is_empty():
		relic = _load("res://data/relic_policy.json")
	var error: String = _configuration_error(relic)
	if not error.is_empty():
		return _fail(error)
	for entry in entries:
		error = _entry_error(entry)
		if not error.is_empty():
			return _fail(error)
	for field in exposed:
		error = _unknown_keys(field, _meta["fields"], "暴露字段")
		if not error.is_empty():
			return _fail(error)
	var template: Variant = _view.get("new_entry", null)
	if template != null:
		error = _entry_error(template)
		if not error.is_empty():
			return _fail("新增模板: " + error)
	_entries = entries.duplicate(true)
	_exposed = exposed.duplicate(true)
	_draft = cfg.duplicate(true)
	_sync_draft()
	_configured = true
	last_error = ""
	_render()
	return {"ok": true, "rows": _rows.size(), "error": ""}

func get_draft() -> Dictionary:
	return _draft.duplicate(true) if _configured else {}

func get_rows() -> Array:
	return _rows.duplicate(true)

func get_control(index: int, field: String) -> Control:
	return _controls.get("%d:%s" % [index, field], null)

func get_exposed_control(index: int, role: String) -> Control:
	return _exposed_controls.get("%d:%s" % [index, role], null)

func render() -> Dictionary:
	if not _configured:
		return _fail(last_error)
	_render()
	return {"ok": true, "rows": _rows.size(), "error": ""}

func set_modifier_value(index: int, field: String, value: Variant) -> Dictionary:
	if not _configured:
		return _fail(last_error)
	if index < 0 or index >= _entries.size():
		return _edit_error("修饰器下标越界")
	var access: Dictionary = _display_access(_entries[index])
	if not access["visible"] or not access["editable"]:
		return _edit_error("展示权限拒绝修改")
	if not _view["fields"].has(field):
		return _edit_error("未知修饰器字段: " + field)
	if not _valid_type(value, _view["fields"][field]["type"]):
		return _edit_error("字段类型错误: " + field)
	_entries[index]["definition"][field] = _copy(value)
	_changed()
	return {"ok": true, "error": ""}

func add_modifier(entry: Dictionary) -> Dictionary:
	if not _configured:
		return _fail(last_error)
	var error: String = _entry_error(entry)
	if not error.is_empty():
		return _edit_error(error)
	var access: Dictionary = _display_access(entry)
	if not access["visible"] or not access["editable"]:
		return _edit_error("展示权限拒绝新增")
	_entries.append(entry.duplicate(true))
	_changed()
	return {"ok": true, "error": ""}

func remove_modifier(index: int) -> Dictionary:
	if not _configured:
		return _fail(last_error)
	if index < 0 or index >= _entries.size():
		return _edit_error("修饰器下标越界")
	var access: Dictionary = _display_access(_entries[index])
	if not access["visible"] or not access["editable"]:
		return _edit_error("展示权限拒绝删除")
	_entries.remove_at(index)
	_changed()
	return {"ok": true, "error": ""}

# lower/upper 合成一组范围，仍写回元数据声明的两个键，不创建 range/value。
func set_exposed_value(index: int, role: String, value: Variant) -> Dictionary:
	if not _configured:
		return _fail(last_error)
	if index < 0 or index >= _exposed.size():
		return _edit_error("暴露字段下标越界")
	var access: Dictionary = _item_policy["ui_access"][_view["field_access"]]
	if not access["visible"] or not access["editable"]:
		return _edit_error("展示权限拒绝修改暴露字段")
	var roles: Dictionary = _meta["roles"]
	if role == "bounds":
		if not value is Array or value.size() != 2:
			return _edit_error("范围必须是两个数值")
		for number in value:
			if not _valid_type(number, "number"):
				return _edit_error("范围必须是有限数值")
		_exposed[index][roles["lower"]] = value[0]
		_exposed[index][roles["upper"]] = value[1]
	elif roles.has(role) and role not in ["lower", "upper"]:
		var key: String = roles[role]
		if not _valid_type(value, _meta["fields"][key]["type"]):
			return _edit_error("字段类型错误: " + key)
		_exposed[index][key] = _copy(value)
	else:
		return _edit_error("未知暴露字段角色: " + role)
	_changed()
	return {"ok": true, "error": ""}

func _configuration_error(relic: Dictionary) -> String:
	for key in ["fields", "roles"]:
		if not _meta.get(key, null) is Dictionary:
			return "缺少暴露元数据: " + key
	if not _meta.get("input_path", null) is String:
		return "缺少暴露元数据 input_path"
	var roles: Dictionary = _meta["roles"]
	if roles.size() != 7 or _meta["fields"].size() != 7:
		return "暴露元数据须为七个落盘键、六组展示（上下限一组）"
	var seen_roles: Dictionary = {}
	for role in ["reference", "permissions", "lower", "upper", "live", "inheritable", "note"]:
		var key: Variant = roles.get(role, null)
		if not key is String or not _meta["fields"].has(key) or seen_roles.has(key):
			return "暴露元数据缺少角色或重复槽位: " + role
		seen_roles[key] = true
		var descriptor: Variant = _meta["fields"][key]
		if not descriptor is Dictionary or not descriptor.get("type", null) is String:
			return "暴露元数据缺少类型: " + key
		if not _supported_type(descriptor["type"]):
			return "暴露元数据类型未登记: " + key
	if not _item_policy.get("permissions", null) is Array or _item_policy["permissions"].is_empty():
		return "缺少 item_permission_policy.permissions"
	if not relic.get("enum", null) is Array or relic["enum"].size() != 3:
		return "缺少 relic_policy.enum"
	var tiers: Variant = _item_policy.get("ui_access", null)
	if not tiers is Dictionary or tiers.is_empty():
		return "缺少 item_permission_policy.ui_access 展示权限映射（非运行态授权）"
	for tier in tiers:
		var access: Variant = tiers[tier]
		if not tier is String or not access is Dictionary:
			return "ui_access 条目非法"
		if not access.get("visible", null) is bool or not access.get("editable", null) is bool:
			return "ui_access 缺少 visible/editable: " + str(tier)
		if not access["visible"] and access["editable"]:
			return "隐藏条目不得可编辑: " + str(tier)
	for path_key in ["input_path", "tags_path"]:
		var path: Variant = _view.get(path_key, null)
		if not path is String or not _valid_path(path):
			return "view 缺少合法路径: " + path_key
	if not _valid_path(_meta["input_path"]):
		return "暴露 input_path 非法"
	var fields: Variant = _view.get("fields", null)
	if not fields is Dictionary or fields.size() != 6:
		return "view.fields 必须严格六字段"
	# 六键清单来自已部署 Schema 抽取，不允许用注入的第七孤立字段替换核心键。
	var schema: Dictionary = _load("res://data/params_meta.json")
	var objects: Variant = schema.get("objects", null)
	if not objects is Array:
		return "缺少 params_meta.objects 六字段契约"
	var frozen: Array = []
	for object in objects:
		if not object is Dictionary:
			continue
		var object_path: Variant = object.get("path", null)
		if object_path is String and object_path == "modifiers[i]":
			var required: Variant = object.get("required", null)
			if required is Array:
				frozen = required
	if frozen.size() != 6:
		return "缺少 Schema 修饰器六字段登记"
	for key in fields:
		if not frozen.has(key):
			return "修饰器未知键: " + str(key)
	for key in fields:
		var descriptor: Variant = fields[key]
		if not key is String or not descriptor is Dictionary:
			return "修饰器字段描述非法"
		if not descriptor.get("type", null) is String or not _supported_type(descriptor["type"]):
			return "修饰器字段类型未登记: " + key
	var view_roles: Variant = _view.get("roles", null)
	if not view_roles is Dictionary:
		return "缺少 view.roles"
	for role in ["scope", "targets"]:
		var field: Variant = view_roles.get(role, null)
		if not field is String or not fields.has(field):
			return "view.roles 缺少: " + role
	if fields[view_roles["scope"]]["type"] != "string" or fields[view_roles["targets"]]["type"] != "array":
		return "view.roles 的 scope/targets 须分别为 string/array"
	if not _view.get("tagged_scope", null) is String:
		return "缺少 view.tagged_scope"
	var field_access: Variant = _view.get("field_access", null)
	if not field_access is String or not tiers.has(field_access):
		return "未登记暴露字段展示权限"
	# // TODO(U-22): façade 到位后替换本展示映射注入口，不改保存/校验授权接口。
	var matches: Variant = _view.get("display_access_by_target", null)
	if not matches is Dictionary:
		return "缺少 display_access_by_target（可显式为空）"
	for path in matches:
		var tier: Variant = matches[path]
		if not path is String or not tier is String or not tiers.has(tier):
			return "未登记路径展示权限: " + str(path)
	return ""

func _entry_error(entry: Variant) -> String:
	if not entry is Dictionary:
		return "修饰器定义必须是对象"
	var access: Variant = entry.get("access", null)
	if not access is String or not _item_policy["ui_access"].has(access):
		return "修饰器缺少已登记展示权限 access"
	var definition: Variant = entry.get("definition", null)
	var error: String = _unknown_keys(definition, _view["fields"], "修饰器")
	if not error.is_empty():
		return error
	for field in _view["fields"]:
		if not definition.has(field):
			return "缺少修饰器字段: " + field
		if not _valid_type(definition[field], _view["fields"][field]["type"]):
			return "修饰器字段类型错误: " + field
	return ""

func _unknown_keys(value: Variant, allowed: Dictionary, label: String) -> String:
	if not value is Dictionary:
		return label + "定义必须是对象"
	var unknown: PackedStringArray = []
	for key in value:
		if not allowed.has(key):
			unknown.append(str(key))
	return "" if unknown.is_empty() else label + "未知键: " + ", ".join(unknown)

func _display_access(entry: Dictionary) -> Dictionary:
	var access: Dictionary = _item_policy["ui_access"][entry["access"]].duplicate(true)
	# // TODO(U-22): 仅展示侧精确路径匹配；由 core façade 替换，不输出保存/校验结论。
	var matches: Dictionary = _view["display_access_by_target"]
	var targets: Variant = entry["definition"].get(_view["roles"]["targets"], null)
	if targets is Array:
		for target in targets:
			if target is String and matches.has(target):
				var other: Dictionary = _item_policy["ui_access"][matches[target]]
				access["visible"] = access["visible"] and other["visible"]
				access["editable"] = access["editable"] and other["editable"]
	return access

func _render() -> void:
	_clear()
	var template: Variant = _view.get("new_entry", null)
	if template is Dictionary:
		var add: Button = Button.new()
		add.name = "AddModifier"
		add.text = "新增修饰器"
		var template_access: Dictionary = _display_access(template)
		add.disabled = not template_access["visible"] or not template_access["editable"]
		add.pressed.connect(func() -> void: add_modifier(template))
		add_child(add)
	# 标签只读展示，不做匹配成功判定。
	var tags_value: Variant = _lookup(_draft, _view["tags_path"])
	for index in range(_entries.size()):
		var entry: Dictionary = _entries[index]
		var access: Dictionary = _display_access(entry)
		if not access["visible"]:
			continue
		var row: VBoxContainer = VBoxContainer.new()
		row.name = "Modifier%d" % index
		add_child(row)
		_rows.append({"index": index, "definition": entry["definition"].duplicate(true),
			"editable": access["editable"]})
		for field in _view["fields"]:
			var control: Control = _make_input(row, field, entry["definition"][field],
				_view["fields"][field]["type"], access["editable"], "modifier", index)
			_controls["%d:%s" % [index, field]] = control
			_wire(control, _view["fields"][field]["type"], _set_from_input.bind(index, field, "modifier"))
		# 优先级来自装配展示输入，不偷偷落成修饰器第七字段。
		if entry.has("priority"):
			_label(row, "优先级（展示）: " + str(entry["priority"]))
		var scope: String = entry["definition"][_view["roles"]["scope"]]
		if scope == _view["tagged_scope"]:
			var tags: Label = _label(row, "作用域标签: " + str(tags_value))
			tags.set_meta("scope_tags", true)
		var remove: Button = Button.new()
		remove.text = "删除修饰器"
		remove.disabled = not access["editable"]
		remove.pressed.connect(func() -> void: remove_modifier(index))
		row.add_child(remove)
	var field_access: Dictionary = _item_policy["ui_access"][_view["field_access"]]
	if not field_access["visible"]:
		return
	for index in range(_exposed.size()):
		var row: VBoxContainer = VBoxContainer.new()
		row.name = "Exposed%d" % index
		add_child(row)
		for role in ["reference", "permissions", "bounds", "live", "inheritable", "note"]:
			var value: Variant = null
			var kind: String = "array"
			if role == "bounds":
				value = [_exposed[index].get(_meta["roles"]["lower"], null),
					_exposed[index].get(_meta["roles"]["upper"], null)]
			else:
				var field: String = _meta["roles"][role]
				value = _exposed[index].get(field, null)
				kind = _meta["fields"][field]["type"]
			var control: Control = _make_input(row, role, value, kind, field_access["editable"], "exposed", index)
			_exposed_controls["%d:%s" % [index, role]] = control
			_wire(control, kind, _set_from_input.bind(index, role, "exposed"))
	if not last_error.is_empty():
		_show_error(last_error)

func _make_input(parent: Node, field: String, value: Variant, kind: String,
		editable: bool, section: String, index: int) -> Control:
	_label(parent, field)
	var control: Control
	if kind == "boolean":
		var check: CheckBox = CheckBox.new()
		check.button_pressed = value is bool and value
		check.disabled = not editable
		control = check
	else:
		var line: LineEdit = LineEdit.new()
		line.text = str(value) if kind in ["string", "ref"] and value != null else JSON.stringify(value)
		line.editable = editable
		control = line
	control.set_meta("input_field", field)
	control.set_meta("section", section)
	control.set_meta("entry_index", index)
	parent.add_child(control)
	return control

func _set_from_input(value: Variant, index: int, field: String, section: String) -> void:
	if section == "modifier":
		set_modifier_value(index, field, value)
	else:
		set_exposed_value(index, field, value)

# Bind appends index/field/section after the signal value.
func _wire(control: Control, kind: String, setter: Callable) -> void:
	if control is CheckBox:
		control.toggled.connect(func(value: bool) -> void: setter.call(value))
	elif control is LineEdit:
		control.text_submitted.connect(func(text: String) -> void:
			if kind in ["string", "ref"]:
				setter.call(text)
			else:
				var parser: JSON = JSON.new()
				if parser.parse(text) != OK:
					_edit_error("输入不是合法 JSON: " + parser.get_error_message())
					return
				setter.call(parser.data)
		)

func _changed() -> void:
	last_error = ""
	_sync_draft()
	_render()
	draft_changed.emit(get_draft())

func _sync_draft() -> void:
	var definitions: Array = []
	for entry in _entries:
		definitions.append(entry["definition"].duplicate(true))
	_set_path(_draft, _view["input_path"], definitions)
	_set_path(_draft, _meta["input_path"], _exposed.duplicate(true))

func _set_path(root: Dictionary, path: String, value: Variant) -> void:
	var segments: PackedStringArray = path.split(".")
	var current: Dictionary = root
	for index in range(segments.size() - 1):
		var child: Variant = current.get(segments[index], null)
		if not child is Dictionary:
			child = {}
			current[segments[index]] = child
		current = child
	current[segments[segments.size() - 1]] = value

func _lookup(root: Dictionary, path: String) -> Variant:
	var current: Variant = root
	for segment in path.split("."):
		if not current is Dictionary:
			return null
		current = current.get(segment, null)
	return current

func _valid_path(path: String) -> bool:
	if path.is_empty():
		return false
	for segment in path.split("."):
		if not segment.is_valid_identifier():
			return false
	return true

func _supported_type(kind: String) -> bool:
	return kind in ["string", "ref", "boolean", "number", "integer", "array", "permissions", "object"]

func _valid_type(value: Variant, kind: String) -> bool:
	match kind:
		"string", "ref": return value is String
		"boolean": return value is bool
		"number": return (value is int or value is float) and is_finite(float(value))
		"integer": return value is int
		"array", "permissions": return value is Array
		"object": return value is Dictionary
	return false

func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value

func _load(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func _clear() -> void:
	_rows.clear()
	_controls.clear()
	_exposed_controls.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()

func _label(parent: Node, text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	parent.add_child(label)
	return label

func _show_error(error: String) -> void:
	var label: Label = get_node_or_null("PanelError") as Label
	if label == null:
		label = _label(self, error)
		label.name = "PanelError"
	else:
		label.text = error

func _fail(error: String) -> Dictionary:
	last_error = error if not error.is_empty() else "尚未 configure 修饰器面板"
	_configured = false
	_clear()
	_show_error(last_error)
	return {"ok": false, "error": last_error}

func _edit_error(error: String) -> Dictionary:
	last_error = error
	_show_error(error)
	return {"ok": false, "error": error}
