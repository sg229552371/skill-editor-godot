@tool
class_name ParamForm
extends VBoxContainer

## Data-driven parameter editor shell.  It renders only exposed schema leaves;
## validation and persistence remain in skill_core and downstream save flow.

signal values_changed(change_table: Dictionary)
signal submitted(change_table: Dictionary)

const UNREGISTERED: String = "未登记"
const LEVELS: Array[String] = ["新手", "进阶", "专家"]
const UNITS_SCRIPT = preload("res://skill_core/schema/units.gd")

var api: Variant = null
var params_meta: Dictionary = {}
var project_meta: Dictionary = {}
var definition: Dictionary = {}
var brick: Dictionary = {}
var mode: String = "author"

# 全局类缓存里没有 SkillUnits（项目不依赖编辑器 import 刷新缓存），一律走 preload 常量做类型标注。
var _units: UNITS_SCRIPT
var _rows: Dictionary = {}
var _values: Dictionary = {}
var _sources: Dictionary = {}
var _visible_levels: Dictionary = {"新手": true, "进阶": true, "专家": true}
var _ready_for_input: bool = false

func _ready() -> void:
	if _units == null:
		_units = UNITS_SCRIPT.new()
	if get_node_or_null("Rows") == null:
		var rows: VBoxContainer = VBoxContainer.new()
		rows.name = "Rows"
		rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(rows)

## Configure and render a form.  `definition` is a draft; it is copied and never
## written back.  The returned table is diagnostic-only and contains no save side effect.
func configure(metadata: Dictionary = {}, project: Dictionary = {}, draft: Dictionary = {}, card: Dictionary = {}, form_mode: String = "author") -> Dictionary:
	params_meta = metadata.duplicate(true) if not metadata.is_empty() else _load_params_meta()
	project_meta = project.duplicate(true)
	definition = draft.duplicate(true)
	brick = card.duplicate(true)
	mode = form_mode
	_values.clear()
	_sources.clear()
	_rows.clear()
	_ready_for_input = false
	_visible_levels = {"新手": true, "进阶": true, "专家": true}
	if _units == null:
		_units = UNITS_SCRIPT.new()
	var unit_result: Dictionary = _units.configure(project_meta, params_meta)
	_ready_for_input = unit_result.get("ok", false) or _tick_field_count() == 0
	_clear_rows()
	var leaves: Variant = params_meta.get("leaves", null)
	if not leaves is Array:
		_add_message("参数元数据缺少 leaves：" + UNREGISTERED)
		return {"ok": false, "error": "参数元数据缺少 leaves", "rows": 0}
	if not brick.is_empty() and mode != "relic" and not (brick.get("author_params", null) is Array or brick.get("author_params", null) is Dictionary):
		_add_message("所属积木的 author_params 未登记：" + UNREGISTERED)
		return {"ok": false, "error": "author_params 未登记", "rows": 0}
	if not brick.is_empty() and mode == "relic" and not brick.get("relic_params", null) is Dictionary:
		_add_message("所属积木的 relic_params 未登记：" + UNREGISTERED)
		return {"ok": false, "error": "relic_params 未登记", "rows": 0}
	for entry_value in leaves:
		if not entry_value is Dictionary:
			continue
		var entry: Dictionary = entry_value
		var path_value: Variant = entry.get("path", null)
		if not path_value is String or path_value.is_empty():
			continue
		var path: String = String(path_value)
		if not _is_exposed(path):
			continue
		_add_row(path, entry)
	if not unit_result.get("ok", false) and _tick_field_count() > 0:
		_add_message("时间单位未配置：" + String(unit_result.get("error", UNREGISTERED)))
	return {"ok": true, "rows": _rows.size(), "units_ok": unit_result.get("ok", false), "error": unit_result.get("error", "")}

func render(metadata: Dictionary = {}, project: Dictionary = {}, draft: Dictionary = {}, card: Dictionary = {}, form_mode: String = "author") -> Dictionary:
	return configure(metadata, project, draft, card, form_mode)

func set_context(metadata: Dictionary, project: Dictionary, draft: Dictionary = {}, card: Dictionary = {}, form_mode: String = "author") -> Dictionary:
	return configure(metadata, project, draft, card, form_mode)

## A display-level filter only.  Hiding a level never removes its value.
func set_level_visible(level: String, visible: bool) -> void:
	if not LEVELS.has(level):
		return
	_visible_levels[level] = visible
	for path in _rows:
		var row: Dictionary = _rows[path]
		var row_level: String = String(row.get("level", UNREGISTERED))
		var node: Control = row.get("container")
		if node != null:
			node.visible = bool(_visible_levels.get(row_level, true))

func expand_level(level: String, expanded: bool = true) -> void:
	set_level_visible(level, expanded)

func get_control(path: String) -> Control:
	var row: Variant = _rows.get(path, null)
	if row is Dictionary:
		var control: Variant = row.get("control", null)
		if control is Control:
			return control
	return null

func get_seconds_control(path: String) -> SpinBox:
	var row: Variant = _rows.get(path, null)
	if row is Dictionary:
		var control: Variant = row.get("seconds_control", null)
		if control is SpinBox:
			return control
	return null

func get_ticks_control(path: String) -> SpinBox:
	var row: Variant = _rows.get(path, null)
	if row is Dictionary:
		var control: Variant = row.get("ticks_control", null)
		if control is SpinBox:
			return control
	return null

func get_row(path: String) -> Dictionary:
	var row: Variant = _rows.get(path, null)
	if row is Dictionary:
		var copy: Dictionary = row.duplicate(true)
		copy.erase("container")
		copy.erase("control")
		copy.erase("seconds_control")
		copy.erase("ticks_control")
		return copy
	return {}

func set_value(path: String, value: Variant, source: String = "params") -> bool:
	var actual: String = _find_row_path(path)
	if actual.is_empty() or not _rows.has(actual):
		return false
	var row: Dictionary = _rows[actual]
	if bool(row.get("locked", false)) or not bool(row.get("editable", false)):
		return false
	if String(row.get("kind", "")) == "tick":
		return _set_tick_value(actual, value, false, source)
	var value_copy: Variant = _copy(value)
	if String(row.get("kind", "")) == "int" and (value_copy is int or value_copy is float):
		value_copy = int(value_copy)
	elif String(row.get("kind", "")) == "float" and (value_copy is int or value_copy is float):
		value_copy = float(value_copy)
	_values[actual] = value_copy
	_sources[actual] = source
	row["present"] = true
	_rows[actual] = row
	_update_control(row, value_copy)
	_emit_changed()
	return true

## Returns path -> {value, source, state}; null, zero and [] remain distinct.
func get_change_table() -> Dictionary:
	var result: Dictionary = {}
	for path in _rows:
		var row: Dictionary = _rows[path]
		var present: bool = bool(row.get("present", false))
		var value: Variant = _values.get(path, null)
		var state: String = "unset"
		if present:
			if value == null:
				state = "null"
			elif value is Array and value.is_empty():
				state = "empty_array"
			else:
				state = "value"
		result[path] = {"value": _copy(value), "source": _sources.get(path, "default"), "state": state}
	return result

func get_changes() -> Dictionary:
	return get_change_table()

func get_values() -> Dictionary:
	var result: Dictionary = {}
	for path in _values:
		var row: Variant = _rows.get(path, null)
		if row is Dictionary and bool(row.get("present", false)):
			result[path] = _copy(_values[path])
	return result

func submit_form() -> Dictionary:
	var table: Dictionary = get_change_table()
	submitted.emit(table.duplicate(true))
	return {"ok": true, "changes": table, "values": get_values(), "sources": _sources.duplicate(true)}

func submit() -> Dictionary:
	return submit_form()

func _add_row(path: String, entry: Dictionary) -> void:
	var kind: String = _normalized_kind(entry.get("type", null))
	if entry.get("enum", null) is Array and not entry["enum"].is_empty():
		kind = "enum"
	var unit: String = String(entry.get("unit", ""))
	var tick: bool = _is_tick_field(path)
	if tick:
		kind = "tick"
	var level: String = String(entry.get("level", UNREGISTERED))
	var default_info: Dictionary = _initial_value(path, entry)
	if (kind == "int" or kind == "tick") and (default_info.get("value") is int or default_info.get("value") is float):
		default_info["value"] = int(default_info["value"])
	elif kind == "float" and (default_info.get("value") is int or default_info.get("value") is float):
		default_info["value"] = float(default_info["value"])
	var row_box: HBoxContainer = HBoxContainer.new()
	row_box.name = _safe_name(path)
	row_box.visible = bool(_visible_levels.get(level, true))
	var label: Label = Label.new()
	label.text = String(entry.get("name", path))
	label.tooltip_text = path
	label.custom_minimum_size.x = 180
	row_box.add_child(label)
	var control: Control = _make_control(path, entry, kind, default_info.get("value"), tick)
	row_box.add_child(control)
	var seconds_control: Control = null
	var ticks_control: Control = null
	if tick:
		# The primary control is ticks; seconds is display/input convenience.
		ticks_control = control
		seconds_control = _make_seconds_control(path, default_info.get("value"))
		row_box.add_child(seconds_control)
		var seconds_label: Label = Label.new()
		seconds_label.text = "秒"
		row_box.add_child(seconds_label)
		var tick_label: Label = Label.new()
		tick_label.text = "tick"
		row_box.add_child(tick_label)
	else:
		var unit_label: Label = Label.new()
		unit_label.text = unit if not unit.is_empty() else ""
		row_box.add_child(unit_label)
	var lock_label: Label = Label.new()
	var locked_reason: String = _lock_reason(path)
	var editable: bool = kind != "unregistered" and locked_reason.is_empty() and (not tick or _ready_for_input)
	if not locked_reason.is_empty():
		lock_label.text = "🔒 " + locked_reason
		lock_label.tooltip_text = locked_reason
	elif kind == "unregistered":
		lock_label.text = UNREGISTERED
	elif not _column_registered(entry, "default") or not _column_registered(entry, "required") or not _column_registered(entry, "level"):
		lock_label.text = UNREGISTERED
	row_box.add_child(lock_label)
	var missing_columns: PackedStringArray = PackedStringArray()
	if not _column_registered(entry, "range"):
		missing_columns.append("取值范围：" + UNREGISTERED)
	if not _column_registered(entry, "required"):
		missing_columns.append("必填：" + UNREGISTERED)
	if not _column_registered(entry, "level"):
		missing_columns.append("分级：" + UNREGISTERED)
	var columns_label: Label = Label.new()
	columns_label.text = " / ".join(missing_columns)
	row_box.add_child(columns_label)
	var rows: Node = get_node_or_null("Rows")
	if rows != null:
		rows.add_child(row_box)
	var row: Dictionary = {"path": path, "entry": entry.duplicate(true), "kind": kind, "unit": unit, "level": level, "container": row_box, "control": control, "seconds_control": seconds_control, "ticks_control": ticks_control, "locked": not locked_reason.is_empty(), "lock_reason": locked_reason, "editable": editable, "present": default_info.get("present", false), "default": default_info.get("value"), "source": default_info.get("source", "default")}
	_rows[path] = row
	_values[path] = _copy(default_info.get("value"))
	_sources[path] = String(default_info.get("source", "default"))
	_apply_editability(row)
	_connect_control(path, row)

func _make_control(path: String, entry: Dictionary, kind: String, value: Variant, tick: bool) -> Control:
	if tick or kind == "int" or kind == "float":
		var spin: SpinBox = SpinBox.new()
		spin.name = "Value"
		spin.step = 1.0 if tick or kind == "int" else 0.01
		spin.allow_greater = true
		spin.allow_lesser = true
		spin.value = float(value) if value is int or value is float else 0.0
		return spin
	if kind == "bool":
		var check: CheckButton = CheckButton.new()
		check.button_pressed = value is bool and value
		return check
	if kind == "enum":
		var option: OptionButton = OptionButton.new()
		var options: Variant = entry.get("enum", null)
		if not options is Array:
			options = _enum_for_path(path)
		if options is Array:
			for option_value in options:
				if option_value is String:
					option.add_item(option_value)
		if value is String:
				var index: int = -1
				for i in range(option.item_count):
					if option.get_item_text(i) == value:
						index = i
						break
				if index >= 0 and index < option.item_count:
					option.select(index)
		return option
	if kind == "string" or kind == "ref":
		var line: LineEdit = LineEdit.new()
		line.text = String(value) if value != null else ""
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return line
	var unknown: Label = Label.new()
	unknown.text = UNREGISTERED + "类型"
	unknown.tooltip_text = "素材未登记可编辑控件类型"
	return unknown

func _make_seconds_control(path: String, ticks: Variant) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.name = "Seconds"
	spin.step = 0.0001
	spin.allow_greater = true
	spin.allow_lesser = false
	var result: Dictionary = _units.ticks_to_seconds(path, int(ticks) if ticks is int or ticks is float else 0)
	spin.value = float(result.get("seconds", 0.0)) if result.get("ok", false) else 0.0
	return spin

func _connect_control(path: String, row: Dictionary) -> void:
	var control: Control = row.get("control")
	if control is SpinBox:
		if String(row.get("kind", "")) == "tick":
			control.value_changed.connect(_on_ticks_changed.bind(path))
		else:
			control.value_changed.connect(_on_number_changed.bind(path))
	elif control is CheckButton:
		control.toggled.connect(_on_value_changed.bind(path))
	elif control is OptionButton:
		control.item_selected.connect(_on_option_changed.bind(path))
	elif control is LineEdit:
		control.text_changed.connect(_on_text_changed.bind(path))
	var seconds: Variant = row.get("seconds_control", null)
	if seconds is SpinBox:
		seconds.value_changed.connect(_on_seconds_changed.bind(path))

func _on_value_changed(value: bool, path: String) -> void:
	_commit(path, value)

func _on_option_changed(index: int, path: String) -> void:
	var option: OptionButton = get_control(path) as OptionButton
	if option != null and index >= 0:
		_commit(path, option.get_item_text(index))

func _on_text_changed(value: String, path: String) -> void:
	_commit(path, value)

func _on_ticks_changed(value: float, path: String) -> void:
	_set_tick_value(path, int(round(value)), true, "params")

func _on_number_changed(value: float, path: String) -> void:
	var row: Variant = _rows.get(path, null)
	if row is Dictionary and String(row.get("kind", "")) == "int":
		_commit(path, int(round(value)))
	else:
		_commit(path, value)

func _on_seconds_changed(value: float, path: String) -> void:
	_set_tick_value(path, value, true, "params", true)

func _commit(path: String, value: Variant) -> void:
	var row: Variant = _rows.get(path, null)
	if not row is Dictionary or bool(row.get("locked", false)) or not bool(row.get("editable", false)):
		return
	_values[path] = _copy(value)
	_sources[path] = "params"
	row["present"] = true
	_rows[path] = row
	_emit_changed()

func _set_tick_value(path: String, value: Variant, emit: bool, source: String, from_seconds: bool = false) -> bool:
	var row: Variant = _rows.get(path, null)
	if not row is Dictionary or bool(row.get("locked", false)) or not bool(row.get("editable", false)):
		return false
	var result: Dictionary = _units.seconds_to_ticks(path, value) if from_seconds else _units.accept_ticks(path, int(value))
	if not result.get("ok", false):
		return false
	var ticks: int = int(result.get("ticks", 0))
	_values[path] = ticks
	_sources[path] = source
	row["present"] = true
	_rows[path] = row
	var ticks_control: Variant = row.get("ticks_control", null)
	if ticks_control is SpinBox and int(round(ticks_control.value)) != ticks:
		ticks_control.set_value_no_signal(float(ticks))
	var seconds_control: Variant = row.get("seconds_control", null)
	if seconds_control is SpinBox:
		var display: Dictionary = _units.ticks_to_seconds(path, ticks)
		if display.get("ok", false):
			seconds_control.set_value_no_signal(float(display.get("seconds", 0.0)))
	if emit:
		_emit_changed()
	return true

func _update_control(row: Dictionary, value: Variant) -> void:
	var control: Variant = row.get("control", null)
	if control is LineEdit:
		control.text = String(value) if value != null else ""
	elif control is CheckButton:
		control.set_pressed_no_signal(value is bool and value)
	elif control is OptionButton:
		for index in range(control.item_count):
			if control.get_item_text(index) == String(value):
				control.select(index)
				break
	elif control is SpinBox:
		control.set_value_no_signal(float(value) if value is int or value is float else 0.0)

func _apply_editability(row: Dictionary) -> void:
	var editable: bool = bool(row.get("editable", false))
	var control: Variant = row.get("control", null)
	if control is LineEdit:
		control.editable = editable
	elif control is SpinBox:
		control.editable = editable
	elif control is CheckButton:
		control.disabled = not editable
	elif control is OptionButton:
		control.disabled = not editable
	if control is Control:
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE if not editable else Control.MOUSE_FILTER_STOP
	var seconds: Variant = row.get("seconds_control", null)
	if seconds is SpinBox:
		seconds.editable = editable

func _is_exposed(path: String) -> bool:
	var exposed: Variant = brick.get("author_params", null)
	if mode == "relic":
		var relic: Variant = brick.get("relic_params", null)
		if not relic is Dictionary:
			return false
		if not exposed is Array and not exposed is Dictionary:
			exposed = relic.keys()
		else:
			var intersection: Array = []
			for item in relic.keys():
				if _path_list_contains(exposed, String(item)):
					intersection.append(item)
			exposed = intersection
	if exposed == null:
			return false
	return _path_list_contains(exposed, path)

func _path_list_contains(values: Variant, path: String) -> bool:
	if values is Array:
		for value in values:
			if _matches_path(String(value), path):
				return true
	elif values is Dictionary:
		for key in values:
			if _matches_path(String(key), path):
				return true
	return false

func _lock_reason(path: String) -> String:
	var locks: Variant = brick.get("locked_params", null)
	if not locks is Dictionary:
		return ""
	for key in locks:
		if _matches_path(String(key), path):
			var reason: Variant = locks[key]
			return String(reason) if reason != null else UNREGISTERED
	return ""

func _matches_path(candidate: String, path: String) -> bool:
	var normalized_candidate: String = _normalize_index(candidate)
	var normalized_path: String = _normalize_index(path)
	if normalized_candidate == normalized_path:
		return true
	return normalized_candidate.trim_prefix("params.") == normalized_path or normalized_path.trim_prefix("params.") == normalized_candidate

func _normalize_index(path: String) -> String:
	var regex: RegEx = RegEx.new()
	regex.compile("\\[[0-9]+\\]")
	return regex.sub(path, "[i]", true)

func _initial_value(path: String, entry: Dictionary) -> Dictionary:
	var found: Dictionary = _lookup_definition(path)
	if found.get("present", false):
		return found
	var override_value: Dictionary = _lookup_override(path)
	if override_value.get("present", false):
		return override_value
	var relic_value: Dictionary = _lookup_nested(definition.get("relic_params", null), path)
	if relic_value.get("present", false):
		relic_value["source"] = "relic"
		return relic_value
	var card_default: Variant = _lookup_nested(brick.get("default_cfg", null), path)
	if card_default.get("present", false):
		card_default["source"] = "default"
		return card_default
	if entry.has("default"):
		return {"present": true, "value": _copy(entry["default"]), "source": "default"}
	return {"present": false, "value": null, "source": "default"}

func _lookup_override(path: String) -> Dictionary:
	var direct: Dictionary = _lookup_nested(definition.get("brick_override", null), path)
	if direct.get("present", false):
		direct["source"] = "brick_override"
		return direct
	var overrides: Variant = definition.get("brick_overrides", null)
	if overrides == null:
		var params: Variant = definition.get("params", null)
		if params is Dictionary:
			overrides = params.get("brick_overrides", null)
	if overrides is Array:
		for item in overrides:
			if not item is Dictionary:
				continue
			var values: Variant = item.get("values", item)
			var found: Dictionary = _lookup_nested(values, path)
			if found.get("present", false):
				found["source"] = "brick_override"
				return found
	return {"present": false, "value": null, "source": "brick_override"}

func _lookup_definition(path: String) -> Dictionary:
	var params: Variant = definition.get("params", null)
	var found: Dictionary = _lookup_nested(params, path)
	if found.get("present", false):
		found["source"] = "params"
		return found
	return {"present": false, "value": null, "source": "params"}

func _lookup_nested(root: Variant, path: String) -> Dictionary:
	if root == null:
		return {"present": false, "value": null}
	if root is Dictionary and root.has(path):
		return {"present": true, "value": _copy(root[path])}
	var current: Variant = root
	for segment in path.split("."):
		if segment.contains("[i]"):
			return {"present": false, "value": null}
		if not current is Dictionary or not current.has(segment):
			return {"present": false, "value": null}
		current = current[segment]
	return {"present": true, "value": _copy(current)}

func _normalized_kind(value: Variant) -> String:
	if not value is String:
		return "unregistered"
	match String(value):
		"int", "integer": return "int"
		"float", "number": return "float"
		"bool", "boolean": return "bool"
		"enum": return "enum"
		"string": return "string"
		"ref": return "unregistered"
		"array": return "unregistered"
	return "unregistered"

func _enum_for_path(path: String) -> Array:
	var enums: Variant = params_meta.get("enums", null)
	if not enums is Dictionary:
		return []
	var path_parts: PackedStringArray = _normalize_index(path).split(".")
	var leaf: String = path_parts[path_parts.size() - 1] if not path_parts.is_empty() else path
	var candidates: Array[String] = [leaf]
	for key in candidates:
		var values: Variant = enums.get(key, null)
		if values is Array:
			return values
	return []

func _is_tick_field(path: String) -> bool:
	var entries: Variant = params_meta.get("tick_fields", null)
	if not entries is Array:
		return false
	var normalized: String = _normalize_index(path)
	for entry in entries:
		if entry is String and _normalize_index(String(entry)) == normalized:
			return true
	return false

func _tick_field_count() -> int:
	var entries: Variant = params_meta.get("tick_fields", null)
	return entries.size() if entries is Array else 0

func _column_registered(entry: Dictionary, column: String) -> bool:
	if column == "range":
		for key in ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "minLength", "maxLength"]:
			if entry.has(key):
				return true
		return false
	return entry.has(column) or (column == "required" and entry.has("is_required"))

func _clear_rows() -> void:
	var rows: Node = get_node_or_null("Rows")
	if rows == null:
		return
	for child in rows.get_children():
		rows.remove_child(child)
		child.free()
	var message: Node = get_node_or_null("Message")
	if message != null:
		remove_child(message)
		message.free()

func _add_message(text: String) -> void:
	var message: Label = Label.new()
	message.name = "Message"
	message.text = text
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)

func _emit_changed() -> void:
	values_changed.emit(get_change_table())

func _find_row_path(path: String) -> String:
	if _rows.has(path):
		return path
	for existing in _rows:
		if _matches_path(existing, path):
			return existing
	return ""

func _safe_name(path: String) -> String:
	var text: String = path.replace(".", "_").replace("[", "_").replace("]", "")
	return "Row_" + text

func _copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value

func _load_params_meta() -> Dictionary:
	var file: FileAccess = FileAccess.open("res://data/params_meta.json", FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
