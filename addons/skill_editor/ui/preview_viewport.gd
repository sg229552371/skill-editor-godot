@tool
class_name PreviewViewport
extends Control

## Headless-testable frame renderer for the preview panel.
## All policy (shape names and damage text formatting) arrives through configure().

var metadata: Dictionary = {}
var _shape_methods: Dictionary = {}
var _damage_format: String = ""
var _configured: bool = false
var _error: String = ""
var _last_frame_items: Array = []
var _active_ttls: Dictionary = {}

func configure(meta: Dictionary) -> Dictionary:
	_configured = false
	_error = ""
	_shape_methods.clear()
	_damage_format = ""
	_last_frame_items.clear()
	_active_ttls.clear()
	metadata = meta.duplicate(true) if meta is Dictionary else {}
	if not meta is Dictionary or meta.is_empty():
		return _fail("预览元数据缺失")

	var shapes: Variant = meta.get("shapes", null)
	if shapes == null:
		shapes = meta.get("shape_renderers", null)
	if shapes == null:
		shapes = meta.get("shape_types", null)
	if shapes == null:
		shapes = meta.get("shape_modes", null)
	if not shapes is Dictionary or shapes.is_empty():
		return _fail("预览元数据缺少 shapes")
	for name_value in shapes.keys():
		var name: String = String(name_value)
		var method_value: Variant = shapes[name_value]
		if method_value is Dictionary:
			method_value = method_value.get("method", method_value.get("draw", ""))
		var method: String = String(method_value).to_lower()
		if name.is_empty() or not ["circle", "rect", "rectangle", "line"].has(method):
			return _fail("预览形状登记无效：" + name)
		_shape_methods[name] = method

	var format_value: Variant = meta.get("damage_number_format", null)
	if format_value == null:
		format_value = meta.get("damage_format", null)
	if format_value == null:
		var damage_meta: Variant = meta.get("damage_number", null)
		if damage_meta is Dictionary:
			format_value = damage_meta.get("format", null)
		elif damage_meta is String:
			format_value = damage_meta
	if not format_value is String or String(format_value).is_empty():
		return _fail("预览元数据缺少 damage_number_format")
	_damage_format = String(format_value)
	_configured = true
	return {"ok": true, "shapes": _shape_methods.duplicate(true), "damage_number_format": _damage_format}

func render_frame(items: Variant) -> Dictionary:
	if not _configured:
		return _fail("预览视口未配置")
	if not items is Array:
		return _fail("items 必须是 Array")

	var normalized: Array = []
	for index in range(items.size()):
		var value: Variant = items[index]
		if not value is Dictionary:
			return _frame_fail(index, "item", "必须是 Dictionary")
		var item: Dictionary = value
		var checked: Dictionary = _normalize_item(item, index)
		if not bool(checked.get("ok", false)):
			return checked
		normalized.append(checked["item"])

	var next_ttls: Dictionary = {}
	for index in range(normalized.size()):
		var item: Dictionary = normalized[index]
		var key: String = _item_key(item)
		var incoming_ttl: int = int(item["ttl"])
		var effective_ttl: int = incoming_ttl
		if _active_ttls.has(key):
			var previous: int = int(_active_ttls[key])
			if previous > 0:
				# Accept either an upstream-decremented model or a repeated batch.
				# Equal/higher input means the renderer owns this tick; lower input
				# is already decremented by the producer and is used as-is.
				if incoming_ttl >= previous:
					effective_ttl = previous - 1
		item["ttl"] = effective_ttl
		next_ttls[key] = effective_ttl
		normalized[index] = item
	_active_ttls = next_ttls
	_last_frame_items = normalized.duplicate(true)
	queue_redraw()
	var drawn: int = 0
	for item_value in _last_frame_items:
		if int(item_value.get("ttl", 0)) > 0:
			drawn += 1
	return {"ok": true, "drawn": drawn, "error": ""}

func get_last_frame_items() -> Array:
	return _last_frame_items.duplicate(true)

func get_error() -> String:
	return _error

func _normalize_item(item: Dictionary, index: int) -> Dictionary:
	var kind_value: Variant = item.get("kind", null)
	if not kind_value is String:
		return _frame_fail(index, "kind", "必须是已登记的字符串")
	var kind: String = String(kind_value)
	if not ["shape", "trail", "damage_number"].has(kind):
		return _frame_fail(index, "kind", "未登记：" + kind)

	var pos_value: Variant = item.get("pos", null)
	if not _is_vector_or_numeric(pos_value):
		return _frame_fail(index, "pos", "必须是数值 Vector2 或 {x,y}")
	var ttl_value: Variant = item.get("ttl", null)
	if not ttl_value is int:
		return _frame_fail(index, "ttl", "必须是 int")
	var size_value: Variant = item.get("size", null)
	if not _is_vector_or_numeric(size_value):
		return _frame_fail(index, "size", "必须是数值 Vector2 或 float")
	var color_value: Variant = item.get("color", null)
	if not _is_color(color_value):
		return _frame_fail(index, "color", "必须是 Color 或颜色字符串")

	var copy: Dictionary = item.duplicate(true)
	copy["pos"] = _vector2(pos_value)
	copy["size"] = _size_vector(size_value)
	copy["color"] = _color(color_value)
	if kind == "shape":
		var shape_value: Variant = copy.get("shape", copy.get("shape_name", copy.get("name", null)))
		var shape_text: Variant = copy.get("text", null)
		if shape_value == null and shape_text is String and _shape_methods.has(String(shape_text)):
			shape_value = String(shape_text)
		if shape_value == null and _shape_methods.size() == 1:
			shape_value = _shape_methods.keys()[0]
		if not shape_value is String or not _shape_methods.has(String(shape_value)):
			return _frame_fail(index, "shape", "未登记：" + str(shape_value))
		copy["shape"] = String(shape_value)
	elif kind == "damage_number":
		var text_value: Variant = copy.get("text", null)
		if not text_value is String:
			return _frame_fail(index, "text", "必须是 String")
		copy["text"] = _format_damage(String(text_value))
	return {"ok": true, "item": copy}

func _draw() -> void:
	if not _configured:
		return
	for item_value in _last_frame_items:
		var item: Dictionary = item_value
		if int(item.get("ttl", 0)) <= 0:
			continue
		var position: Vector2 = item["pos"]
		var size: Vector2 = item["size"]
		var color: Color = item["color"]
		var kind: String = String(item["kind"])
		if kind == "shape":
			var method: String = String(_shape_methods.get(String(item.get("shape", "")), ""))
			if method == "circle":
				draw_circle(position, maxf(size.x, size.y) * 0.5, color)
			elif method == "rect" or method == "rectangle":
				draw_rect(Rect2(position - size * 0.5, size), color, true)
			elif method == "line":
				draw_line(position - Vector2(size.x, 0.0), position + Vector2(size.x, 0.0), color, maxf(1.0, size.y))
		elif kind == "trail":
			draw_line(position - size, position, color, maxf(1.0, size.y))
		elif kind == "damage_number":
			draw_string(ThemeDB.fallback_font, position, String(item.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, color)

func _format_damage(text: String) -> String:
	if _damage_format.contains("{text}"):
		return _damage_format.replace("{text}", text)
	if _damage_format.contains("%s"):
		return _damage_format % text
	return _damage_format + text

## 去重键的取值转换：**不能直接用 `String(value)`** ——
## `String(Color)` / `String(null)` 在 Godot 4 里没有对应构造器，运行期直接抛
## `Invalid call. Nonexistent 'String' constructor.`（整条用例记 Unexpected Errors）。
## 归一化后的 item 里 `color` 已经是 Color 对象，所以必须走 to_html()。
func _key_text(value: Variant) -> String:
	if value == null:
		return ""
	if value is Color:
		var color: Color = value
		return color.to_html()
	if value is Vector2:
		var vector: Vector2 = value
		return "%s,%s" % [vector.x, vector.y]
	return str(value)

func _item_key(item: Dictionary) -> String:
	var position: Vector2 = item["pos"]
	var size: Vector2 = item["size"]
	return "%s|%s,%s|%s,%s|%s|%s|%s" % [
		_key_text(item.get("kind", "")), position.x, position.y, size.x, size.y,
		_key_text(item.get("color", "")), _key_text(item.get("shape", "")), _key_text(item.get("text", ""))]

func _is_vector_or_numeric(value: Variant) -> bool:
	if value is Vector2:
		return is_finite(value.x) and is_finite(value.y)
	if value is int or value is float:
		return is_finite(float(value))
	if value is Dictionary:
		var x: Variant = value.get("x", null)
		var y: Variant = value.get("y", null)
		return (x is int or x is float) and (y is int or y is float) and is_finite(float(x)) and is_finite(float(y))
	return false

func _vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value["x"]), float(value["y"]))
	var number: float = float(value)
	return Vector2(number, number)

func _size_vector(value: Variant) -> Vector2:
	return _vector2(value)

func _is_color(value: Variant) -> bool:
	if value is Color:
		return true
	if value is String:
		return not String(value).is_empty()
	return false

func _color(value: Variant) -> Color:
	return value if value is Color else Color(String(value))

func _frame_fail(index: int, field: String, detail: String) -> Dictionary:
	return _fail("item[%d].%s：%s" % [index, field, detail])

func _fail(message: String) -> Dictionary:
	_error = message
	return {"ok": false, "drawn": 0, "error": message}
