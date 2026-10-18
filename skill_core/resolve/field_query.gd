class_name FieldQuery
extends RefCounted

# Display facts only; this is neither a save gate nor resolved-value provenance.
# Policy describes item permissions, not author editability (raw ch04 / D-26).
var last_error: String = ""
var _configured: bool = false
var _declarations: Array[Dictionary] = []
var _paths: Array[String] = []

func configure(catalog_entry: Dictionary, policy: Variant = null) -> Dictionary:
	_configured = false
	_declarations.clear()
	_paths.clear()
	last_error = ""
	if policy != null and not policy is Dictionary:
		return _setup_error("policy must be a Dictionary or null")
	var authors: Variant = catalog_entry.get("author_params", null)
	var locks: Variant = catalog_entry.get("locked_params", null)
	var relics: Variant = catalog_entry.get("relic_params", null)
	var defaults: Variant = catalog_entry.get("default_cfg", null)
	if not (authors is Array or authors is Dictionary) or not locks is Dictionary or not relics is Dictionary or not defaults is Dictionary:
		return _setup_error("Card requires author_params, locked_params, relic_params and default_cfg")
	# Iterate the card, not a fixed section ordering. First declaration owns order.
	for section in catalog_entry:
		match section:
			"author_params", "locked_params", "relic_params":
				var values: Variant = catalog_entry[section]
				var paths: Array = values.keys() if values is Dictionary else values
				for path in paths:
					if not _valid_declaration_path(path):
						return _setup_error("Invalid declaration path in %s: %s" % [section, str(path)])
					var reason: String = ""
					if section == "locked_params":
						var text: Variant = values[path]
						if not text is String or text.strip_edges().is_empty():
							return _setup_error("locked_params requires nonempty material reasons: %s" % path)
						reason = text
					_add(path, section, reason)
			"default_cfg":
				if not _collect_defaults(defaults, ""):
					return _setup_error("default_cfg contains an invalid path key")
	_configured = true
	return {"ok": true, "error": ""}

func query(path: String) -> Dictionary:
	if not _configured:
		return _query_error(path, last_error if not last_error.is_empty() else "FieldQuery is not configured")
	var logical: String = _logical_path(path)
	if not _valid_query_path(logical):
		return _query_error(path, "Invalid query path: %s" % path)
	return _query_logical(path, logical)

# Returns logical declaration paths, including [i] templates and concrete default
# array leaves. Does not invent instances for empty/default-less arrays.
func query_all() -> Array:
	if not _configured:
		last_error = last_error if not last_error.is_empty() else "FieldQuery is not configured"
		return []
	last_error = ""
	var result: Array = []
	for path in _paths:
		result.append(_query_logical(path, _normalize(path)))
	return result

func _query_logical(display_path: String, logical: String) -> Dictionary:
	var known: bool = false
	var author: bool = false
	var relic: bool = false
	var reason: String = ""
	# An ancestor declaration constrains known children, but does not register
	# arbitrary nonexistent descendants. Array templates match concrete indices.
	for entry in _declarations:
		var exact: bool = _matches(entry.path, logical, false)
		known = known or exact
		if entry.section == "author_params" and _matches(entry.path, logical, true):
			author = true
		elif entry.section == "relic_params" and exact:
			relic = true
		elif entry.section == "locked_params" and _matches(entry.path, logical, true):
			if reason.is_empty():
				reason = entry.reason
	if not known:
		return _query_error(display_path, "Unknown field path: %s" % display_path)
	last_error = ""
	var locked: bool = not reason.is_empty()
	var opened: bool = author and not locked
	var source: String = "default_cfg"
	if locked:
		source = "locked"
	elif author:
		source = "author_params"
	elif relic:
		source = "relic_params"
	return {"ok": true, "error": "", "path": display_path, "locked": locked, "lock_reason": reason, "open": opened, "source": source, "writable": opened and not locked}

func _add(path: String, section: String, reason: String = "") -> void:
	var normalized: String = _normalize(path)
	_declarations.append({"path": normalized, "section": section, "reason": reason})
	for existing in _paths:
		if _normalize(existing) == normalized:
			return
	_paths.append(path)

func _collect_defaults(value: Variant, prefix: String) -> bool:
	if value is Dictionary and not value.is_empty():
		for key in value:
			# Default CFG keys are author keys, not material path expressions.
			if not _valid_author_key(key):
				return false
			var child: String = key if prefix.is_empty() else prefix + "." + key
			if not _collect_defaults(value[key], child):
				return false
	elif value is Array and not value.is_empty():
		for index in range(value.size()):
			if not _collect_defaults(value[index], "%s[%d]" % [prefix, index]):
				return false
	elif not prefix.is_empty():
		_add(prefix, "default_cfg")
	return true

# Material declarations can have [i]; numeric indices are generated by tree
# traversal/query addresses and must never be accepted as author-supplied keys.
func _valid_declaration_path(value: Variant) -> bool:
	if not value is String:
		return false
	return _path_regex("i").search(value) != null

func _valid_author_key(value: Variant) -> bool:
	return _valid_declaration_path(value) and not value.contains(".") and not value.contains("[") and not value.contains("]")

func _valid_query_path(value: String) -> bool:
	return _path_regex("i|[0-9]+").search(value) != null

func _path_regex(index_pattern: String) -> RegEx:
	var regex: RegEx = RegEx.new()
	regex.compile("^[^\\s.\\[\\]]+(?:\\[(?:%s)\\])*(?:\\.[^\\s.\\[\\]]+(?:\\[(?:%s)\\])*)*$" % [index_pattern, index_pattern])
	return regex

func _normalize(path: String) -> String:
	return path.trim_prefix("params.")

func _logical_path(path: String) -> String:
	var wrapper: RegEx = RegEx.new()
	wrapper.compile("^bricks\\[[0-9]+\\]\\.(?:author_params|locked_params|relic_params|default_cfg)\\.(.+)$")
	var found: RegExMatch = wrapper.search(path)
	return _normalize(found.get_string(1) if found != null else path)

func _matches(candidate: String, logical: String, descendants: bool) -> bool:
	var pattern: PackedStringArray = candidate.split(".")
	var actual: PackedStringArray = logical.split(".")
	if pattern.size() > actual.size() or (not descendants and pattern.size() != actual.size()):
		return false
	for index in range(pattern.size()):
		# Only [i] is a wildcard; concrete default indices remain distinct.
		var regex: RegEx = RegEx.new()
		var expression: String = _escape_regex(pattern[index]).replace("\\[i\\]", "\\[(?:i|[0-9]+)\\]")
		if descendants and index == pattern.size() - 1:
			expression += "(?:\\[(?:i|[0-9]+)\\])*"
		regex.compile("^" + expression + "$")
		if regex.search(actual[index]) == null:
			return false
	return true

func _escape_regex(text: String) -> String:
	var result: String = ""
	for character in text:
		if "\\.^$|?*+()[]{}".contains(character):
			result += "\\"
		result += character
	return result

func _setup_error(message: String) -> Dictionary:
	_declarations.clear()
	_paths.clear()
	last_error = message
	return {"ok": false, "error": message}

func _query_error(path: String, message: String) -> Dictionary:
	last_error = message
	return {"ok": false, "error": message, "path": path, "locked": false, "lock_reason": "", "open": false, "source": "unknown", "writable": false}
