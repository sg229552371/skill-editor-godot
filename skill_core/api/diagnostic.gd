class_name Diagnostic extends RefCounted

const SEV_BLOCK: int = 0
const SEV_WARN: int = 1
const SEV_HINT: int = 2

var rule_id: String = ""
var code: String = ""
var severity: int = SEV_BLOCK
var path: String = ""
var actual: String = ""
var expected: String = ""
var hint: String = ""

static func make(p_rule_id: String, p_code: String, p_path: String, p_actual: String, p_expected: String) -> Diagnostic:
	var diagnostic := Diagnostic.new()
	diagnostic.rule_id = p_rule_id
	diagnostic.code = p_code
	diagnostic.path = p_path
	diagnostic.actual = p_actual
	diagnostic.expected = p_expected
	diagnostic.severity = SEV_BLOCK
	diagnostic.hint = _render_message(p_rule_id, p_code, p_path, p_actual, p_expected)
	return diagnostic

func to_dict() -> Dictionary:
	return {
		"rule_id": rule_id,
		"code": code,
		"severity": severity,
		"path": path,
		"actual": actual,
		"expected": expected,
		"hint": hint,
	}

func text() -> String:
	return hint

func text_program() -> String:
	return "[%s/%s] %s" % [rule_id, code, hint]

static func _render_message(p_rule_id: String, p_code: String, p_path: String, p_actual: String, p_expected: String) -> String:
	var template := _find_template(p_code)
	if template.is_empty():
		return "规则 %s 在 %s 未通过" % [p_rule_id, p_path]
	var message := template
	message = message.replace("{path}", p_path)
	message = message.replace("{actual}", p_actual)
	message = message.replace("{expected}", p_expected)
	message = message.replace("{field}", p_path)
	message = message.replace("{id}", p_actual)
	message = message.replace("{version}", p_actual)
	message = message.replace("{reason}", p_expected)
	message = message.replace("{range}", p_expected)
	message = message.replace("{allowed}", p_expected)
	message = message.replace("{status}", p_actual)
	message = message.replace("{brick}", p_actual)
	message = message.replace("{ref}", p_actual)
	message = message.replace("{format}", p_expected)
	message = message.replace("{supported}", p_expected)
	message = message.replace("{context}", p_expected)
	return message

static func _find_template(p_code: String) -> String:
	var file := FileAccess.open("res://S_docs/collab/assets/error_messages.csv", FileAccess.READ)
	if file == null:
		return ""
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty() or line.begins_with("code,"):
			continue
		var columns := _parse_csv_line(line)
		if columns.size() >= 3 and columns[0] == p_code:
			return columns[2]
	return ""

static func _parse_csv_line(line: String) -> Array[String]:
	var fields: Array[String] = []
	var current := ""
	var quoted := false
	var index := 0
	while index < line.length():
		var character := line[index]
		if character == '"':
			if quoted and index + 1 < line.length() and line[index + 1] == '"':
				current += '"'
				index += 1
			else:
				quoted = not quoted
		elif character == ',' and not quoted:
			fields.append(current)
			current = ""
		else:
			current += character
		index += 1
	fields.append(current)
	return fields
