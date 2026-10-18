@tool
class_name PresentationPanel
extends VBoxContainer

## Data-driven presentation editor. Metadata owns section and field vocabulary;
## this panel keeps a detached presentation draft and never mutates the input CFG.

const META_PATH: String = "res://data/presentation_meta.json"
const UNBOUND: String = "未绑定"

signal value_changed(value: Dictionary)

var metadata: Dictionary = {}
var _presentation: Dictionary = {}
var _controls: Dictionary = {}
var _sections: Array[String] = []
var _section_fields: Dictionary = {}
var _configured: bool = false
var _error: String = ""

func _ready() -> void:
	if get_node_or_null("Status") == null:
		var status: Label = Label.new()
		status.name = "Status"
		add_child(status)
	if get_node_or_null("Sections") == null:
		var sections: VBoxContainer = VBoxContainer.new()
		sections.name = "Sections"
		sections.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(sections)

func configure(meta: Dictionary = {}, cfg: Dictionary = {}) -> Dictionary:
	_clear_render()
	_configured = false
	_error = ""
	metadata = meta.duplicate(true) if not meta.is_empty() else _load_metadata()
	if metadata.is_empty():
		return _fail("表现元数据缺失：" + META_PATH)
	var required: Variant = metadata.get("required_sections", null)
	var index: Variant = metadata.get("section_field_index", null)
	if not required is Array or required.is_empty():
		return _fail("表现元数据缺少 required_sections")
	if not index is Dictionary:
		return _fail("表现元数据缺少 section_field_index")
	_sections.clear()
	_section_fields.clear()
	for section_value in required:
		if not section_value is String or String(section_value).is_empty():
			return _fail("表现元数据的槽位名无效")
		var section: String = String(section_value)
		var fields_value: Variant = index.get(section, null)
		if not fields_value is Array:
			return _fail("表现元数据缺少字段登记：" + section)
		_sections.append(section)
		var fields: Array[String] = []
		for field_value in fields_value:
			if field_value is String and not String(field_value).is_empty():
				fields.append(String(field_value))
		_section_fields[section] = fields
	_presentation = {}
	var source_presentation: Variant = cfg.get("presentation", null)
	if source_presentation is Dictionary:
		_presentation = source_presentation.duplicate(true)
	for section in _sections:
		var existing: Variant = _presentation.get(section, null)
		if not existing is Dictionary:
			_presentation[section] = {}
	var invalid: String = _find_invalid_value()
	if not invalid.is_empty():
		_render()
		return _fail(invalid)
	_configured = true
	_render()
	_set_status("已配置")
	return {"ok": true, "sections": _sections.duplicate(), "fields": get_section_fields()}

func render(meta: Dictionary = {}, cfg: Dictionary = {}) -> Dictionary:
	return configure(meta, cfg)

func set_context(meta: Dictionary, cfg: Dictionary = {}) -> Dictionary:
	return configure(meta, cfg)

func get_value() -> Dictionary:
	return _presentation.duplicate(true)

func get_sections() -> Array[String]:
	return _sections.duplicate()

func get_section_names() -> Array[String]:
	return get_sections()

func get_section_fields(section: String = "") -> Variant:
	if section.is_empty():
		return _section_fields.duplicate(true)
	var fields: Variant = _section_fields.get(section, null)
	return fields.duplicate() if fields is Array else []

func get_control(section: String, field: String) -> Control:
	var row: Variant = _controls.get(_control_key(section, field), null)
	return row if row is Control else null

func get_status(section: String) -> String:
	var node: Node = get_node_or_null("Sections/" + _safe_name(section) + "/Status")
	return node.text if node is Label else ""

func get_error() -> String:
	return _error

func set_value(section: String, field: String, value: Variant) -> bool:
	if not _configured or not _sections.has(section):
		_set_error("面板未配置或槽位未登记：" + section)
		return false
	var fields: Variant = _section_fields.get(section, null)
	if not fields is Array or not fields.has(field):
		_set_error("字段未登记：presentation.%s.%s" % [section, field])
		return false
	var entry: Dictionary = _entry_for(section, field)
	if not _valid_value(value, entry):
		_set_error("非法值：presentation.%s.%s" % [section, field])
		return false
	var section_value: Variant = _presentation.get(section, null)
	if not section_value is Dictionary:
		section_value = {}
		_presentation[section] = section_value
	var copied: Variant = _copy(value)
	section_value[field] = copied
	_update_control(section, field, copied)
	_update_status(section)
	value_changed.emit(get_value())
	return true

func _load_metadata() -> Dictionary:
	var file: FileAccess = FileAccess.open(META_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	return parser.data.duplicate(true)

func _find_invalid_value() -> String:
	for section in _sections:
		var section_value: Variant = _presentation.get(section, null)
		if not section_value is Dictionary:
			continue
		for field_value in _section_fields.get(section, []):
			var field: String = String(field_value)
			if not section_value.has(field):
				continue
			var entry: Dictionary = _entry_for(section, field)
			if not _valid_value(section_value[field], entry):
				return "非法值：presentation.%s.%s" % [section, field]
	return ""

func _entry_for(section: String, field: String) -> Dictionary:
	var path: String = "presentation.%s.%s" % [section, field]
	for collection_name in ["leaves", "arrays", "objects"]:
		var collection: Variant = metadata.get(collection_name, null)
		if not collection is Array:
			continue
		for item_value in collection:
			if item_value is Dictionary and String(item_value.get("path", "")) == path:
				return item_value.duplicate(true)
	return {}

func _valid_value(value: Variant, entry: Dictionary) -> bool:
	if entry.is_empty():
		return true
	var kind: String = String(entry.get("type", entry.get("item_kind", "")))
	if entry.has("const"):
		return typeof(value) == typeof(entry["const"]) and value == entry["const"]
	if kind == "string" or kind == "ref":
		if not value is String:
			return false
	elif kind == "boolean":
		if not value is bool:
			return false
	elif kind == "integer":
		if not value is int:
			return false
	elif kind == "number":
		if not (value is int or value is float):
			return false
	elif kind == "object":
		if not value is Dictionary:
			return false
	elif kind == "array":
		if not value is Array:
			return false
	var allowed: Variant = entry.get("enum", null)
	if allowed is Array and not allowed.has(value):
		return false
	return true

func _render() -> void:
	var sections_node: Node = get_node_or_null("Sections")
	if sections_node == null:
		return
	for child in sections_node.get_children():
		child.free()
	_controls.clear()
	for section in _sections:
		var box: VBoxContainer = VBoxContainer.new()
		box.name = _safe_name(section)
		var title: Label = Label.new()
		title.name = "Title"
		title.text = section
		box.add_child(title)
		var status: Label = Label.new()
		status.name = "Status"
		box.add_child(status)
		sections_node.add_child(box)
		for field_value in _section_fields.get(section, []):
			_add_field(box, section, String(field_value))
		_update_status(section)

func _add_field(box: VBoxContainer, section: String, field: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = _safe_name(field)
	var label: Label = Label.new()
	label.text = field
	label.tooltip_text = "presentation.%s.%s" % [section, field]
	label.custom_minimum_size.x = 180
	row.add_child(label)
	var entry: Dictionary = _entry_for(section, field)
	var value: Variant = null
	var section_value: Variant = _presentation.get(section, null)
	if section_value is Dictionary and section_value.has(field):
		value = section_value[field]
	var control: Control = _make_control(section, field, entry, value)
	row.add_child(control)
	box.add_child(row)
	_controls[_control_key(section, field)] = control

func _make_control(section: String, field: String, entry: Dictionary, value: Variant) -> Control:
	var kind: String = String(entry.get("type", entry.get("item_kind", "")))
	if entry.get("enum", null) is Array:
		var option: OptionButton = OptionButton.new()
		for option_value in entry["enum"]:
			option.add_item(String(option_value))
		if value is String:
			for index in range(option.item_count):
				if option.get_item_text(index) == value:
					option.select(index)
					break
		# 枚举控件必须无条件返回 OptionButton：初值未绑定时若落到 LineEdit，
		# 调用方拿不到下拉、也无法做取值校验（T-060 首轮就是栽在这里）。
		option.item_selected.connect(_on_option_selected.bind(section, field, option))
		return option
	if kind == "boolean":
		var check: CheckButton = CheckButton.new()
		check.button_pressed = value is bool and value
		check.toggled.connect(_on_bool_changed.bind(section, field))
		return check
	if kind == "integer" or kind == "number":
		var spin: SpinBox = SpinBox.new()
		spin.step = 1.0 if kind == "integer" else 0.01
		spin.allow_greater = true
		spin.allow_lesser = true
		spin.value = float(value) if value is int or value is float else 0.0
		spin.value_changed.connect(_on_number_changed.bind(section, field, kind))
		return spin
	var line: LineEdit = LineEdit.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.placeholder_text = UNBOUND if value == null else ""
	line.text = _display_value(value)
	line.text_submitted.connect(_on_text_submitted.bind(section, field, entry))
	return line

func _on_option_selected(index: int, section: String, field: String, option: OptionButton) -> void:
	if index >= 0 and index < option.item_count:
		set_value(section, field, option.get_item_text(index))

func _on_bool_changed(value: bool, section: String, field: String) -> void:
	set_value(section, field, value)

func _on_number_changed(value: float, section: String, field: String, kind: String) -> void:
	set_value(section, field, int(round(value)) if kind == "integer" else value)

func _on_text_submitted(text: String, section: String, field: String, entry: Dictionary) -> void:
	var kind: String = String(entry.get("type", entry.get("item_kind", "")))
	var value: Variant = text
	if kind == "array" or kind == "object":
		var parsed: Variant = JSON.parse_string(text)
		if parsed == null and not text == "null":
			_set_error("非法值：presentation.%s.%s" % [section, field])
			return
		value = parsed
	set_value(section, field, value)

func _update_control(section: String, field: String, value: Variant) -> void:
	var control: Control = get_control(section, field)
	if control is LineEdit:
		control.text = _display_value(value)
		control.placeholder_text = "" if value != null else UNBOUND
	elif control is CheckButton:
		control.set_pressed_no_signal(value is bool and value)
	elif control is SpinBox:
		control.set_value_no_signal(float(value) if value is int or value is float else 0.0)

func _update_status(section: String) -> void:
	var section_value: Variant = _presentation.get(section, null)
	var status: Node = get_node_or_null("Sections/" + _safe_name(section) + "/Status")
	if status is Label:
		status.text = UNBOUND if not section_value is Dictionary or section_value.is_empty() else "已配置"

func _clear_render() -> void:
	var sections_node: Node = get_node_or_null("Sections")
	if sections_node != null:
		for child in sections_node.get_children():
			child.free()
	_controls.clear()

func _fail(message: String) -> Dictionary:
	_configured = false
	_set_error(message)
	return {"ok": false, "error": message}

func _set_error(message: String) -> void:
	_error = message
	_set_status(message)

func _set_status(message: String) -> void:
	var status: Node = get_node_or_null("Status")
	if status is Label:
		status.text = message

func _control_key(section: String, field: String) -> String:
	return section + "." + field

func _safe_name(value: String) -> String:
	return value.replace("/", "_").replace("[", "_").replace("]", "_").replace(".", "_")

func _display_value(value: Variant) -> String:
	if value == null:
		return ""
	if value is Array or value is Dictionary:
		return JSON.stringify(value)
	return String(value)

func _copy(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value
