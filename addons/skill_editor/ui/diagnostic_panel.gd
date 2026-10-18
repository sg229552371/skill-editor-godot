@tool
class_name DiagnosticPanel
extends VBoxContainer

signal field_requested(path: String)

const Diag = preload("res://skill_core/api/diagnostic.gd")

var api: Variant = null
var selected_path: String = ""
var location_emissions: int = 0

var _sorter: Variant = null
var _metadata: Dictionary = {}
var _default_pattern: RegEx = null
var _entries: Array = []
var _buttons: Dictionary = {}
var _details: Dictionary = {}
var _configured: bool = false
var _configuration_error: String = "未配置诊断面板"
var _selected_index: int = -1

## The caller supplies presentation metadata and a configured DiagnosticSorter.
## Validation, persistence and construction of source provenance belong upstream.
func configure(metadata: Dictionary, sorter: Variant) -> Dictionary:
	_configured = false
	_configuration_error = ""
	_clear_entries()
	_sorter = null
	_metadata.clear()
	_default_pattern = null
	if not sorter is Object or not sorter.has_method("sort_diagnostics"):
		return _config_fail("缺少 DiagnosticSorter")
	var order: Variant = metadata.get("severity_order", null)
	var labels: Variant = metadata.get("severity_value_to_text", null)
	var views: Variant = metadata.get("view_fields", null)
	var pattern: Variant = metadata.get("default_path_regex", null)
	var source_values: Variant = metadata.get("default_source_values", null)
	var notice: Variant = metadata.get("default_notice", null)
	if not order is Array or order.is_empty() or not labels is Dictionary:
		return _config_fail("缺少 severity_order 或 severity_value_to_text")
	if not views is Dictionary or not views.get("planner", null) is Array or not views.get("developer", null) is Array:
		return _config_fail("缺少 view_fields.planner / developer")
	for view in ["planner", "developer"]:
		var fields: Array = views[view]
		if fields.is_empty():
			return _config_fail("view_fields.%s 不能为空" % view)
		for field in fields:
			if not field is String or not Diag.new().to_dict().has(field):
				return _config_fail("view_fields.%s 有未登记字段" % view)
	if not pattern is String or pattern.is_empty() or not source_values is Array or source_values.is_empty():
		return _config_fail("缺少默认卡路径或来源元数据")
	if not notice is String or notice.is_empty():
		return _config_fail("缺少 default_notice")
	for value in order:
		if not (value is int or value is float) or not is_finite(float(value)) or floor(float(value)) != float(value):
			return _config_fail("severity_order 含非法值")
		if not labels.get(str(int(value)), null) is String:
			return _config_fail("severity_value_to_text 缺少分组名称")
	for source in source_values:
		if not source is String:
			return _config_fail("default_source_values 含非法值")
	var regex: RegEx = RegEx.new()
	if regex.compile(pattern) != OK:
		return _config_fail("default_path_regex 无效")
	_default_pattern = regex
	_metadata = metadata.duplicate(true)
	_sorter = sorter
	_configured = true
	(get_node("Status") as Label).text = "无诊断"
	return {"ok": true, "error": ""}

## Accepts raw diagnostics; only the injected sorter determines ordering/deduplication.
## `sources` is an upstream provenance table; `overrides` is accepted read-only and
## intentionally never retained or copied into any CFG field.
func set_diagnostics(diagnostics: Variant, sources: Dictionary = {}, _overrides: Dictionary = {}) -> Dictionary:
	_clear_entries()
	if not _configured:
		return _fail(_configuration_error)
	if not diagnostics is Array:
		return _fail("诊断必须是 Array")
	for item in diagnostics:
		if not item is Diag:
			return _fail("诊断元素必须是 Diagnostic")
	var result: Variant = _sorter.sort_diagnostics(diagnostics)
	if not result is Dictionary or result.get("ok", false) != true or not result.get("diagnostics", null) is Array:
		var reason: String = str(result.get("error", "排序失败")) if result is Dictionary else "排序失败"
		return _fail("DiagnosticSorter: " + reason)
	var sorted: Array = result["diagnostics"]
	var order: Array = _metadata["severity_order"]
	var labels: Dictionary = _metadata["severity_value_to_text"]
	for item in sorted:
		if not item is Diag:
			return _fail("DiagnosticSorter 返回非 Diagnostic 元素")
		var severity_index: int = _severity_index(order, item.severity)
		if severity_index < 0:
			return _fail("诊断严重度未登记")
		var raw: Dictionary = item.to_dict().duplicate(true)
		var path: String = raw["path"]
		var source: Variant = sources.get(path, null)
		var from_default: bool = _default_pattern.search(path) != null
		var target_path: String = path
		if source is Dictionary:
			var kind: Variant = source.get("source", null)
			from_default = from_default or (kind is String and _metadata["default_source_values"].has(kind))
			if from_default:
				var input_path: Variant = source.get("input_path", null)
				if input_path is String and not input_path.is_empty():
					target_path = input_path
		var entry: Dictionary = {
			"rule_id": raw["rule_id"], "severity": raw["severity"],
			"group": labels[str(int(order[severity_index]))],
			"path": path, "target_path": target_path,
			"from_default": from_default, "values": raw
		}
		_entries.append(entry)
	for view in ["planner", "developer"]:
		_render_view(view)
	(get_node("Status") as Label).text = "无诊断" if _entries.is_empty() else "%d 条诊断" % _entries.size()
	return {"ok": true, "error": "", "count": _entries.size()}

## 素材 JSON 的数字恒为 float（坑 9/14），严重度是 int，
## 直接用 Array.find(int) 匹配 float 数组会返回 -1，故按数值逐项比较。
func _severity_index(order: Array, severity: Variant) -> int:
	if not (severity is int or severity is float):
		return -1
	for index in range(order.size()):
		var value: Variant = order[index]
		if (value is int or value is float) and int(value) == int(severity):
			return index
	return -1

func get_view_entries(view: String) -> Array:
	if not _buttons.has(view):
		return []
	var results: Array = []
	for entry in _entries:
		results.append({
			"rule_id": entry["rule_id"], "severity": entry["severity"],
			"group": entry["group"], "path": entry["path"],
			"from_default": entry["from_default"],
			"text": _entry_text(entry, view)
		})
	return results.duplicate(true)

func get_entry_button(view: String, index: int) -> Button:
	var buttons: Variant = _buttons.get(view, null)
	if buttons is Array and index >= 0 and index < buttons.size():
		return buttons[index]
	return null

func _render_view(view: String) -> void:
	var container: VBoxContainer = get_node("Views/Planner/Groups") if view == "planner" else get_node("Views/Developer/Groups")
	var buttons: Array = []
	var details: Array = []
	var last_group: String = ""
	for index in range(_entries.size()):
		var entry: Dictionary = _entries[index]
		var row: VBoxContainer = VBoxContainer.new()
		if entry["group"] != last_group:
			var title: Label = Label.new()
			title.text = entry["group"]
			row.add_child(title)
			last_group = entry["group"]
		var button: Button = Button.new()
		button.text = _entry_text(entry, view)
		button.pressed.connect(_on_entry_pressed.bind(index))
		row.add_child(button)
		var detail: Label = Label.new()
		detail.name = "Details"
		detail.text = "%s\n%s" % [entry["path"], entry["values"]["hint"]]
		detail.visible = false
		row.add_child(detail)
		container.add_child(row)
		buttons.append(button)
		details.append(detail)
	_buttons[view] = buttons
	_details[view] = details

func _entry_text(entry: Dictionary, view: String) -> String:
	var fields: Array = _metadata["view_fields"][view]
	var parts: PackedStringArray = PackedStringArray()
	for field in fields:
		parts.append(str(entry["values"][field]))
	var text: String = " | ".join(parts)
	if entry["from_default"]:
		text = _metadata["default_notice"] + " · " + text
	return text

func _on_entry_pressed(index: int) -> void:
	if index < 0 or index >= _entries.size() or index == _selected_index:
		return
	_selected_index = index
	var entry: Dictionary = _entries[index]
	for view in ["planner", "developer"]:
		var details: Array = _details[view]
		for i in range(details.size()):
			details[i].visible = i == index
	selected_path = entry["target_path"]
	(get_node("FieldPath") as Label).text = selected_path
	(get_node("Notice") as Label).text = _metadata["default_notice"] if entry["from_default"] else ""
	location_emissions += 1
	field_requested.emit(selected_path)

func _clear_entries() -> void:
	_entries.clear()
	_buttons.clear()
	_details.clear()
	_selected_index = -1
	selected_path = ""
	var path_label: Label = get_node_or_null("FieldPath")
	if path_label != null:
		path_label.text = ""
	var notice_label: Label = get_node_or_null("Notice")
	if notice_label != null:
		notice_label.text = ""
	for view in ["Planner", "Developer"]:
		var container: Node = get_node_or_null("Views/%s/Groups" % view)
		if container != null:
			for child in container.get_children():
				container.remove_child(child)
				child.free()

func _config_fail(message: String) -> Dictionary:
	_configuration_error = message
	return _fail(message)

func _fail(message: String) -> Dictionary:
	var status: Label = get_node_or_null("Status")
	if status != null:
		status.text = "诊断面板错误：" + message
	return {"ok": false, "error": message}
