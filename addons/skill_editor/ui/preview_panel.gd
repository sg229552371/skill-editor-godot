@tool
class_name PreviewPanel
extends VBoxContainer

## Snapshot-only consumer. The caller owns runner startup and supplies reviewed
## vocabulary; this panel never reads core internals, sorts, or writes CFG.
## view_fields: {column: [field, ...]}.
## limits: {type_field: field, column_types: {column: [registered_type, ...]},
##          sources: [dot_separated_snapshot_path, ...]}.
## Each type belongs to exactly one column, regardless of its source stream.
## TODO(U-T051-hit): dispatch lists hit as settlement; D-24 and enums.event
## register it as an event. Supply enums.record for the formal column, not hit.

var _views: Dictionary = {}
var _routes: Dictionary = {}
var _sources: Array = []
var _type_field: String = ""
var _entries: Dictionary = {}
var _containers: Dictionary = {}
var _configured: bool = false
var _error: String = "未配置预览面板"
var _status: Label
var _columns: HBoxContainer

func configure(view_fields: Dictionary, limits: Dictionary) -> Dictionary:
	_configured = false
	clear()
	_views.clear()
	_routes.clear()
	_sources.clear()
	_type_field = ""
	var type_field: Variant = limits.get("type_field", null)
	var types: Variant = limits.get("column_types", null)
	var sources: Variant = limits.get("sources", null)
	if not _name(type_field) or not types is Dictionary or not sources is Array or sources.is_empty():
		return _fail("缺少 type_field / column_types / sources 注入素材")
	var views: Dictionary = {}
	var routes: Dictionary = {}
	for column in view_fields:
		if str(column).begins_with("_"):
			continue
		if not _name(column):
			return _fail("view_fields 含非法列名: " + str(column))
		var fields: Variant = view_fields[column]
		var kinds: Variant = types.get(column, null)
		if not fields is Array or fields.is_empty() or not kinds is Array or kinds.is_empty():
			return _fail("列缺少非空字段或记录种类: " + column)
		var seen: Dictionary = {}
		for field in fields:
			if not _name(field) or seen.has(field):
				return _fail("列含非法或重复字段: " + column + ": " + str(field))
			seen[field] = true
		for kind in kinds:
			if not _name(kind) or routes.has(kind):
				return _fail("记录种类非法、重复或跨栏登记: " + str(kind))
			routes[kind] = column
		views[column] = fields.duplicate(true)
	if views.is_empty():
		return _fail("view_fields 没有业务列")
	for column in types:
		if str(column).begins_with("_"):
			continue
		if not views.has(column):
			return _fail("column_types 含未登记列: " + str(column))
	var paths: Array = []
	for source in sources:
		if not source is String or source.is_empty():
			return _fail("sources 含非法路径: " + str(source))
		for segment in source.split("."):
			if not _name(segment):
				return _fail("sources 含非法路径: " + source)
		for previous in paths:
			if source == previous or source.begins_with(previous + ".") or previous.begins_with(source + "."):
				return _fail("sources 路径重复或重叠: " + source)
		paths.append(source)
	_views = views
	_routes = routes
	_sources = paths
	_type_field = type_field
	_configured = true
	_error = ""
	_build_columns()
	clear()
	return {"ok": true, "error": ""}

## Replaces a complete snapshot, never appends to an old frame. A failed frame
## clears all columns so a partial/stale frame cannot look like a valid result.
func ingest(snapshot: Dictionary) -> Dictionary:
	if not _configured:
		return _fail(_error)
	var staged: Dictionary = {}
	for column in _views:
		staged[column] = []
	for source in _sources:
		var current: Variant = snapshot
		for segment in source.split("."):
			if not current is Dictionary:
				return _fail("快照路径中间层必须是 Dictionary: " + source)
			current = current.get(segment, null)
			if current == null:
				break
		# A runner that has not started can have absent/empty streams.
		if current == null:
			continue
		var records: Array = []
		if current is Array:
			records = current
		elif current is Dictionary:
			if current.has(_type_field):
				records.append(current)
			else:
				for key in current:
					if not str(key).begins_with("_"):
						records.append(current[key])
		else:
			return _fail("快照记录流必须是 Array / Dictionary: " + source)
		for index in range(records.size()):
			var record: Variant = records[index]
			var location: String = "%s[%d]" % [source, index]
			if not record is Dictionary:
				return _fail("快照条目必须是 Dictionary: " + location)
			if _comment_only(record):
				continue
			var kind: Variant = record.get(_type_field, null)
			if not kind is String or not _routes.has(kind):
				return _fail("未登记记录种类 %s: %s.%s" % [str(kind), location, _type_field])
			var column: String = _routes[kind]
			var entry: Dictionary = {}
			for field in _views[column]:
				entry[field] = _display_value(record.get(field, null))
			staged[column].append(entry)
	_entries = staged
	_error = ""
	_render()
	return {"ok": true, "error": "", "entries": _entries.duplicate(true)}

func get_entries(column: String) -> Array:
	var entries: Variant = _entries.get(column, null)
	return entries.duplicate(true) if entries is Array else []

func clear() -> void:
	_entries.clear()
	for column in _views:
		_entries[column] = []
	for column in _containers:
		var container: VBoxContainer = _containers[column]
		while container.get_child_count() > 1:
			var row: Node = container.get_child(1)
			container.remove_child(row)
			row.free()
	if is_instance_valid(_status):
		_status.text = ""

static func _name(value: Variant) -> bool:
	return value is String and not value.is_empty() and not value.begins_with("_")

static func _comment_only(record: Dictionary) -> bool:
	if record.is_empty():
		return false
	for key in record:
		if not str(key).begins_with("_"):
			return false
	return true

## Absent display fields remain explicit nulls; comments never become rows or
## nested payload fields. Arrays/dictionaries are detached from the input.
static func _display_value(value: Variant) -> Variant:
	if value is Dictionary:
		var cleaned_dict: Dictionary = {}
		for key in value:
			if not str(key).begins_with("_"):
				cleaned_dict[key] = _display_value(value[key])
		return cleaned_dict
	if value is Array:
		var cleaned_array: Array = []
		for item in value:
			if item is Dictionary and _comment_only(item):
				continue
			cleaned_array.append(_display_value(item))
		return cleaned_array
	return value

func _ensure_ui() -> void:
	if not is_instance_valid(_status):
		_status = Label.new()
		_status.name = "Status"
		add_child(_status)
	if not is_instance_valid(_columns):
		_columns = HBoxContainer.new()
		_columns.name = "Columns"
		add_child(_columns)

func _build_columns() -> void:
	_ensure_ui()
	_containers.clear()
	for child in _columns.get_children():
		_columns.remove_child(child)
		child.free()
	for column in _views:
		var container: VBoxContainer = VBoxContainer.new()
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_columns.add_child(container)
		var heading: Label = Label.new()
		heading.text = column
		container.add_child(heading)
		_containers[column] = container

func _render() -> void:
	for column in _views:
		var container: VBoxContainer = _containers[column]
		while container.get_child_count() > 1:
			var old_row: Node = container.get_child(1)
			container.remove_child(old_row)
			old_row.free()
		for entry in _entries[column]:
			var pieces: PackedStringArray = []
			for field in _views[column]:
				pieces.append(str(field) + ": " + str(entry[field]))
			var row: Label = Label.new()
			row.text = " | ".join(pieces)
			container.add_child(row)
	_status.text = ""

func _fail(message: String) -> Dictionary:
	_error = message
	clear()
	_ensure_ui()
	_status.text = message
	return {"ok": false, "error": message, "entries": _entries.duplicate(true)}
