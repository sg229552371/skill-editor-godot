class_name YamlLite extends RefCounted

# YAML subset used by skill CFG files.
# Canonical output sorts mapping keys lexicographically (Unicode code-point order),
# uses two spaces per level, and writes empty mappings/sequences explicitly.

var _lines: PackedStringArray = []
var _index: int = 0
var _error: String = ""

static func parse(text: String) -> Dictionary:
	var parser := YamlLite.new()
	return parser._parse(text)

static func dump(data: Variant) -> String:
	var result: Array[String] = []
	_dump_value(data, 0, result)
	return "\n".join(result) + "\n"

func _parse(text: String) -> Dictionary:
	_lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n", false)
	_index = 0
	_error = ""
	for line_number in range(_lines.size()):
		if _lines[line_number].find("\t") >= 0:
			return _fail("line %d: tab indentation is not allowed" % (line_number + 1))
		var trimmed: String = _strip_comment(_lines[line_number]).strip_edges()
		if trimmed == "---" or trimmed == "...":
			return _fail("line %d: multiple documents are not supported" % (line_number + 1))
		if trimmed.begins_with("%"):
			return _fail("line %d: directives are not supported" % (line_number + 1))
	var first: int = _next_content(_index)
	if first < 0:
		return {"ok": true, "data": {}}
	_index = first
	var value: Variant = _parse_block(_indent(_lines[_index]))
	if not _error.is_empty():
		return _fail(_error)
	var rest: int = _next_content(_index)
	if rest >= 0:
		return _fail("line %d: unexpected trailing content" % (rest + 1))
	return {"ok": true, "data": value, "error": ""}

func _parse_block(indent: int) -> Variant:
	var at: int = _next_content(_index)
	if at < 0:
		return {}
	_index = at
	var line: String = _strip_comment(_lines[_index])
	if _indent(line) < indent:
		return {}
	if _indent(line) != indent:
		_error = "line %d: unexpected indentation" % (_index + 1)
		return null
	if line.substr(indent).begins_with("-") and (line.length() == indent + 1 or line[indent + 1] == " "):
		return _parse_sequence(indent)
	return _parse_mapping(indent)

func _parse_mapping(indent: int) -> Dictionary:
	var result: Dictionary = {}
	while true:
		var at: int = _next_content(_index)
		if at < 0:
			_index = _lines.size()
			break
		_index = at
		var raw: String = _strip_comment(_lines[_index])
		var current_indent: int = _indent(raw)
		if current_indent < indent:
			break
		if current_indent > indent:
			_error = "line %d: unexpected indentation" % (_index + 1)
			break
		var body: String = raw.substr(indent)
		var colon: int = _find_mapping_colon(body)
		if colon < 0:
			_error = "line %d: expected mapping key" % (_index + 1)
			break
		var key: String = body.substr(0, colon).strip_edges()
		if key.is_empty():
			_error = "line %d: empty mapping key" % (_index + 1)
			break
		var key_value: Variant = _parse_key(key)
		if not (key_value is String):
			break
		key = String(key_value)
		if result.has(key):
			_error = "line %d: duplicate key '%s'" % [_index + 1, key]
			break
		var rest: String = body.substr(colon + 1).strip_edges()
		_index += 1
		if rest == "|" or rest == ">":
			result[key] = _parse_block_scalar(indent, rest == ">")
		elif rest.is_empty():
			var child: int = _next_content(_index)
			if child >= 0 and _indent(_strip_comment(_lines[child])) > indent:
				_index = child
				result[key] = _parse_block(_indent(_strip_comment(_lines[child])))
			else:
				result[key] = {}
		else:
			result[key] = _parse_scalar(rest, _index)
		if not _error.is_empty():
			break
	return result

func _parse_sequence(indent: int) -> Array:
	var result: Array = []
	while true:
		var at: int = _next_content(_index)
		if at < 0:
			_index = _lines.size()
			break
		_index = at
		var raw: String = _strip_comment(_lines[_index])
		var current_indent: int = _indent(raw)
		if current_indent < indent:
			break
		if current_indent != indent:
			_error = "line %d: unexpected sequence indentation" % (_index + 1)
			break
		var body: String = raw.substr(indent)
		if not body.begins_with("-") or (body.length() > 1 and body[1] != " "):
			break
		var rest: String = body.substr(1).strip_edges()
		_index += 1
		if rest.is_empty():
			var child: int = _next_content(_index)
			if child >= 0 and _indent(_strip_comment(_lines[child])) > indent:
				_index = child
				result.append(_parse_block(_indent(_strip_comment(_lines[child]))))
			else:
				result.append(null)
			continue
		var colon: int = _find_mapping_colon(rest)
		if colon >= 0:
			var item: Dictionary = {}
			if not _parse_map_pair(item, rest, indent):
				break
			var child_at: int = _next_content(_index)
			if child_at >= 0 and _indent(_strip_comment(_lines[child_at])) > indent:
				_index = child_at
				var continuation: Variant = _parse_block(_indent(_strip_comment(_lines[child_at])))
				if continuation is Dictionary:
					for continuation_key in continuation.keys():
						if item.has(continuation_key):
							_error = "line %d: duplicate key '%s'" % [child_at + 1, continuation_key]
							break
						item[continuation_key] = continuation[continuation_key]
			result.append(item)
		else:
			result.append(_parse_scalar(rest, _index))
		if not _error.is_empty():
			break
	return result

func _parse_map_pair(target: Dictionary, text: String, parent_indent: int) -> bool:
	var colon: int = _find_mapping_colon(text)
	if colon < 0:
		_error = "line %d: expected mapping key" % _index
		return false
	var key: String = text.substr(0, colon).strip_edges()
	var key_value: Variant = _parse_key(key)
	if not (key_value is String):
		return false
	key = String(key_value)
	var rest: String = text.substr(colon + 1).strip_edges()
	if rest == "|" or rest == ">":
		target[key] = _parse_block_scalar(parent_indent, rest == ">")
	elif rest.is_empty():
		var child: int = _next_content(_index)
		if child >= 0 and _indent(_strip_comment(_lines[child])) > parent_indent:
			_index = child
			target[key] = _parse_block(_indent(_strip_comment(_lines[child])))
		else:
			target[key] = {}
	else:
		target[key] = _parse_scalar(rest, _index)
	return _error.is_empty()

func _parse_key(text: String) -> Variant:
	var value: Variant = _parse_scalar(text, _index)
	if not value is String:
		_error = "line %d: mapping keys must be strings" % (_index + 1)
	return value

func _parse_scalar(text: String, line_index: int) -> Variant:
	var value: String = text.strip_edges()
	if value.is_empty():
		return ""
	if value.begins_with("&") or value.begins_with("*") or value.begins_with("!!"):
		_error = "line %d: anchors, aliases and custom tags are not supported" % (line_index + 1)
		return null
	if value.begins_with("[") or value.begins_with("{"):
		return _parse_inline(value, line_index)
	if (value.begins_with("\"") and value.ends_with("\"")):
		var json_value: Variant = JSON.parse_string(value)
		if json_value == null and value != "\"null\"":
			_error = "line %d: invalid quoted string" % (line_index + 1)
			return null
		return String(json_value)
	if value.begins_with("'") and value.ends_with("'"):
		return value.substr(1, value.length() - 2).replace("''", "'")
	var lower: String = value.to_lower()
	if lower == "yes" or lower == "no" or lower == "on" or lower == "off":
		_error = "line %d: implicit boolean '%s' is not supported" % [line_index + 1, value]
		return null
	if lower == "null" or value == "~":
		return null
	if lower == "nan" or lower == ".nan" or lower == "inf" or lower == ".inf" or lower == "+inf" or lower == "-inf" or lower == "+.inf" or lower == "-.inf":
		_error = "line %d: non-finite numbers are not supported" % (line_index + 1)
		return null
	if value == "true":
		return true
	if value == "false":
		return false
	if value.is_valid_int() and not (value.begins_with("0") and value.length() > 1):
		return value.to_int()
	if value.is_valid_float():
		var number: float = value.to_float()
		if is_nan(number) or is_inf(number):
			_error = "line %d: non-finite numbers are not supported" % (line_index + 1)
			return null
		return number
	return value

func _parse_inline(value: String, line_index: int) -> Variant:
	if value.ends_with("]") and value.begins_with("["):
		var body: String = value.substr(1, value.length() - 2).strip_edges()
		if body.is_empty():
			return []
		var items: Array = []
		for part in _split_inline(body, ','):
			items.append(_parse_scalar(part, line_index))
			if not _error.is_empty():
				return null
		return items
	if value.ends_with("}") and value.begins_with("{"):
		var map_body: String = value.substr(1, value.length() - 2).strip_edges()
		if map_body.is_empty():
			return {}
		var result: Dictionary = {}
		for part in _split_inline(map_body, ','):
			var colon: int = _find_mapping_colon(part)
			if colon < 0:
				_error = "line %d: invalid inline mapping" % (line_index + 1)
				return null
			var key_value: Variant = _parse_key(part.substr(0, colon).strip_edges())
			if not (key_value is String) or result.has(String(key_value)):
				_error = "line %d: invalid or duplicate inline key" % (line_index + 1)
				return null
			result[String(key_value)] = _parse_scalar(part.substr(colon + 1), line_index)
		return result
	_error = "line %d: malformed inline collection" % (line_index + 1)
	return null

func _parse_block_scalar(parent_indent: int, folded: bool) -> String:
	var parts: Array[String] = []
	var content_indent: int = -1
	var probe: int = _index
	while probe < _lines.size():
		var probe_line: String = _lines[probe]
		if probe_line.strip_edges().is_empty():
			probe += 1
			continue
		if _indent(probe_line) <= parent_indent:
			break
		content_indent = _indent(probe_line)
		break
	if content_indent < 0:
		return "\n"
	while _index < _lines.size():
		var raw: String = _lines[_index]
		if raw.strip_edges().is_empty():
			parts.append("")
			_index += 1
			continue
		if _indent(raw) <= parent_indent:
			break
		parts.append(raw.substr(content_indent))
		_index += 1
	if folded:
		return " ".join(parts).strip_edges() + "\n"
	return "\n".join(parts) + "\n"

static func _dump_value(value: Variant, indent: int, output: Array[String]) -> void:
	var prefix: String = " ".repeat(indent)
	if value is Dictionary:
		if value.is_empty():
			output.append(prefix + "{}")
			return
		var keys: Array = value.keys()
		keys.sort()
		for key_variant in keys:
			var key: String = String(key_variant)
			var child: Variant = value[key_variant]
			if child is Dictionary and child.is_empty() or child is Array and child.is_empty():
				output.append(prefix + _quote_key(key) + ": " + _scalar_text(child))
			elif child is Dictionary or child is Array:
				output.append(prefix + _quote_key(key) + ":")
				_dump_value(child, indent + 2, output)
			else:
				output.append(prefix + _quote_key(key) + ": " + _scalar_text(child))
	elif value is Array:
		if value.is_empty():
			output.append(prefix + "[]")
			return
		for child in value:
			if child is Dictionary or child is Array:
				output.append(prefix + "-")
				_dump_value(child, indent + 2, output)
			else:
				output.append(prefix + "- " + _scalar_text(child))
	else:
		output.append(prefix + _scalar_text(value))

static func _scalar_text(value: Variant) -> String:
	if value == null:
		return "null"
	if value is bool:
		return "true" if value else "false"
	if value is String:
		var text: String = value
		var lower: String = text.to_lower()
		if (text.is_valid_float() or text.is_valid_int()
				or lower in ["true", "false", "null", "~", "yes", "no", "on", "off"]
				or text.is_empty() or text.begins_with("- ") or text.begins_with("#")
				or text.contains(": ") or text.contains(" #") or text.contains("\n")
				or text.contains("\r") or text.contains("\t") or text != text.strip_edges()):
			return JSON.stringify(text)
		return text
	if value is Dictionary:
		return "{}"
	if value is Array:
		return "[]"
	return str(value)

static func _quote_key(key: String) -> String:
	if key.is_empty() or key.find(" ") >= 0 or key.find(":") >= 0 or key.find("#") >= 0:
		return JSON.stringify(key)
	return key

func _split_inline(text: String, delimiter: String) -> Array[String]:
	var result: Array[String] = []
	var start: int = 0
	var depth: int = 0
	var quote: String = ""
	var escaped: bool = false
	for index in range(text.length()):
		var character: String = text[index]
		if not quote.is_empty():
			if escaped:
				escaped = false
				continue
			if quote == "\"" and character == "\\":
				escaped = true
				continue
			if character == quote:
				if quote == "'" and index + 1 < text.length() and text[index + 1] == "'":
					continue
				quote = ""
		elif character == "'" or character == "\"":
			quote = character
		elif character == "[" or character == "{":
			depth += 1
		elif character == "]" or character == "}":
			depth -= 1
		elif character == delimiter and depth == 0:
			result.append(text.substr(start, index - start).strip_edges())
			start = index + 1
	result.append(text.substr(start).strip_edges())
	return result

func _find_mapping_colon(text: String) -> int:
	var quote: String = ""
	var depth: int = 0
	var escaped: bool = false
	for index in range(text.length()):
		var character: String = text[index]
		if not quote.is_empty():
			if escaped:
				escaped = false
				continue
			if quote == "\"" and character == "\\":
				escaped = true
				continue
			if character == quote:
				quote = ""
		elif character == "'" or character == "\"":
			quote = character
		elif character == "[" or character == "{":
			depth += 1
		elif character == "]" or character == "}":
			depth -= 1
		elif character == ":" and depth == 0:
			return index
	return -1

func _strip_comment(line: String) -> String:
	var quote: String = ""
	var escaped: bool = false
	for index in range(line.length()):
		var character: String = line[index]
		if not quote.is_empty():
			if escaped:
				escaped = false
				continue
			if quote == "\"" and character == "\\":
				escaped = true
				continue
			if character == quote:
				quote = ""
		elif character == "'" or character == "\"":
			quote = character
		elif character == "#" and (index == 0 or line[index - 1] == " " or line[index - 1] == "\t"):
			return line.substr(0, index)
	return line

func _next_content(start: int) -> int:
	var cursor: int = start
	while cursor < _lines.size():
		if not _strip_comment(_lines[cursor]).strip_edges().is_empty():
			return cursor
		cursor += 1
	return -1

static func _indent(line: String) -> int:
	var count: int = 0
	while count < line.length() and line[count] == " ":
		count += 1
	return count

func _fail(message: String) -> Dictionary:
	return {"ok": false, "data": null, "error": message}
