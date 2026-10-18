extends RefCounted

## Pure cue selection. No playback, callbacks, host references or payload writes.
## event_bindings is injected adapter metadata: section -> logical event -> slot.
## An empty slot selects the whole section; a named slot selects that child only.
## TODO(U-T061-meta): reviewer integration must supply runtime routes/forbidden
## keys and reconcile this card's alignments with deployed scalar-field aliases.
const ShapeHit = preload("res://skill_core/runtime/shape_hit.gd")
const Settle = preload("res://skill_core/runtime/settle.gd")

var _ready: bool = false
var _error: String = ""
var _bindings: Dictionary = {}
var _routes: Dictionary = {}
var _sections: Array = []
var _forbidden: Array = []
var _alignments: Array = []


func configure(bindings: Dictionary, presentation_meta: Dictionary) -> Dictionary:
	_ready = false
	_error = ""
	_bindings.clear()
	_routes.clear()
	_sections.clear()
	_forbidden.clear()
	_alignments.clear()
	var sections: Variant = presentation_meta.get("required_sections", null)
	var routes: Variant = presentation_meta.get("event_bindings", null)
	var forbidden: Variant = presentation_meta.get("forbidden_logic_keys", null)
	if not sections is Array or sections.is_empty():
		return _configure_fail("presentation_meta.required_sections must be a nonempty Array")
	if not routes is Dictionary:
		return _configure_fail("presentation_meta.event_bindings must be a Dictionary")
	if not forbidden is Array or forbidden.is_empty():
		return _configure_fail("presentation_meta.forbidden_logic_keys must be a nonempty Array")
	for key in forbidden:
		if not key is String or key.is_empty():
			return _configure_fail("Invalid presentation_meta.forbidden_logic_keys entry")
		_forbidden.append(key)
	var events: Array = _logic_events()
	for section in sections:
		if not section is String or section.is_empty() or section.begins_with("_") or _sections.has(section):
			return _configure_fail("Invalid/duplicate presentation_meta.required_sections entry: " + str(section))
		_sections.append(section)
		var mapping: Variant = routes.get(section, null)
		if not mapping is Dictionary:
			return _configure_fail("Missing presentation_meta.event_bindings." + section)
		for event in mapping:
			if event is String and event.begins_with("_"):
				continue
			if not events.has(event):
				return _configure_fail("Unsupported logical event: " + str(event))
			if not mapping[event] is String:
				return _configure_fail("Invalid cue slot: " + section + "." + str(event))
		var segment: Variant = bindings.get(section, null)
		if not segment is Dictionary:
			return _configure_fail("presentation." + section + " must be a Dictionary")
	for section in routes:
		if section is String and section.begins_with("_"):
			continue
		if not _sections.has(section):
			return _configure_fail("Unknown presentation_meta.event_bindings section: " + str(section))
	for section in bindings:
		if section is String and section.begins_with("_"):
			continue
		if not _sections.has(section):
			return _configure_fail("Unknown presentation section: " + str(section))
	var problem: String = _check_value(bindings, "presentation")
	if not problem.is_empty():
		return _configure_fail(problem)
	_bindings = bindings.duplicate(true)
	_routes = routes.duplicate(true)
	problem = _read_alignments()
	if not problem.is_empty():
		return _configure_fail(problem)
	_ready = true
	return {"ok": true, "error": ""}


@warning_ignore("unused_parameter")
func on_event(event_name: String, payload: Dictionary) -> Dictionary:
	if not _logic_events().has(event_name):
		return _event_fail("Unsupported logical event: " + event_name)
	if not _ready:
		return _event_fail("PresentationBind is not configured for event: " + event_name)
	var cues: Array = []
	for section in _sections:
		var mapping: Dictionary = _routes[section]
		if not mapping.has(event_name):
			continue
		var segment: Dictionary = _bindings[section]
		if segment.is_empty():
			continue
		var slot: String = mapping[event_name]
		var selected: Variant = segment if slot.is_empty() else segment.get(slot, null)
		if selected == null:
			continue
		if (selected is Array or selected is Dictionary or selected is String) and selected.is_empty():
			continue
		if selected is Array or selected is Dictionary:
			selected = selected.duplicate(true)
		cues.append({"section": section, "event": event_name, "binding": selected})
	_error = ""
	return {"ok": true, "error": "", "cues": cues}


func alignments() -> Array:
	return _alignments.duplicate(true)


func get_error() -> String:
	return _error


func _logic_events() -> Array:
	return [ShapeHit.PROVISIONAL_META["hit_event"], Settle.PROVISIONAL_META["hit_record"], Settle.PROVISIONAL_META["evade_record"]]


func _check_value(value: Variant, path: String) -> String:
	if value is Dictionary:
		for key in value:
			if not key is String:
				return path + " contains a non-string key"
			var child_path: String = path + "." + key
			if _forbidden.has(key):
				return "Forbidden logic key: " + child_path
			var problem: String = _check_value(value[key], child_path)
			if not problem.is_empty():
				return problem
	elif value is Array:
		for index in range(value.size()):
			var problem: String = _check_value(value[index], path + "[" + str(index) + "]")
			if not problem.is_empty():
				return problem
	elif not (value == null or value is String or value is bool or value is int or value is float):
		return path + " must contain plain data, not executable/object values"
	return ""


func _read_alignments() -> String:
	var anim: Variant = _bindings.get("anim", null)
	if not anim is Dictionary or anim.is_empty():
		return ""
	var pairs: Variant = anim.get("alignments", null)
	var path: String = "presentation.anim.alignments"
	if not pairs is Array or pairs.is_empty():
		return path + " must be a nonempty Array when anim is bound"
	for index in range(pairs.size()):
		var pair: Variant = pairs[index]
		var pair_path: String = path + "[" + str(index) + "]"
		if not pair is Dictionary:
			return pair_path + " must be a Dictionary"
		for field in ["shot_tick", "frame"]:
			var value: Variant = pair.get(field, null)
			if not _is_integer(value):
				return pair_path + "." + field + " must be an integer (tick/frame, not seconds)"
			pair[field] = int(value)
		_alignments.append(pair.duplicate(true))
	return ""


func _is_integer(value: Variant) -> bool:
	if value is int:
		return true
	if not value is float:
		return false
	# Avoid overflow when converting a JSON number to signed int64.
	var number: float = value
	return is_finite(number) and floor(number) == number and number >= -9223372036854775808.0 and number < 9223372036854775808.0


func _configure_fail(message: String) -> Dictionary:
	_ready = false
	_bindings.clear()
	_routes.clear()
	_sections.clear()
	_forbidden.clear()
	_alignments.clear()
	_error = message
	return {"ok": false, "error": _error}


func _event_fail(message: String) -> Dictionary:
	_error = message
	return {"ok": false, "error": _error, "cues": []}
