class_name ParamResolver
extends RefCounted

const DEFAULT_SOURCE: String = "default_cfg"
const GENERIC_SOURCE: String = "params"
const BRICK_SOURCE: String = "brick_override"
const RELIC_POLICY_FAILURE_RULE: String = "RESOLVE-POLICY"

static var _relic_policy_loaded: bool = false
static var _relic_policy: Array[String] = []

func resolve(cfg: Dictionary) -> Dictionary:
	var resolved: Dictionary = {}
	var sources: Dictionary = {}
	var diagnostics: Array = []
	var bricks: Array = []
	var bricks_value: Variant = cfg.get("bricks", [])
	if bricks_value is Array:
		bricks = bricks_value
	var root_default: Variant = cfg.get("default_cfg", {})
	if root_default is Dictionary:
		_merge_layer(resolved, sources, root_default, DEFAULT_SOURCE, "default_cfg")
	for index in range(bricks.size()):
		var brick_value: Variant = bricks[index]
		if not brick_value is Dictionary:
			continue
		var brick: Dictionary = brick_value
		var card_default: Variant = brick.get("default_cfg", {})
		if card_default is Dictionary:
			_merge_layer(resolved, sources, card_default, DEFAULT_SOURCE, "bricks[%d].default_cfg" % index)

	var params_value: Variant = cfg.get("params", {})
	if params_value is Dictionary:
		var generic: Dictionary = params_value.duplicate(true)
		generic.erase("brick_overrides")
		_apply_layer(resolved, sources, generic, GENERIC_SOURCE, "params", bricks, -1, diagnostics, "params")
		var overrides_value: Variant = params_value.get("brick_overrides", [])
		if overrides_value is Array:
			for override_index in range(overrides_value.size()):
				var override_value: Variant = overrides_value[override_index]
				if not override_value is Dictionary:
					diagnostics.append(_diagnostic("V-015", "params.brick_overrides[%d]" % override_index, "覆盖项必须是对象"))
					continue
				var override: Dictionary = override_value
				var brick_index: int = int(override.get("brick_index", -1))
				if brick_index < 0 or brick_index >= bricks.size():
					diagnostics.append(_diagnostic("V-015", "params.brick_overrides[%d].brick_index" % override_index, "积木索引不存在"))
					continue
				var values_value: Variant = override.get("values", {})
				if not values_value is Dictionary:
					diagnostics.append(_diagnostic("V-014", "params.brick_overrides[%d].values" % override_index, "覆盖值必须是对象"))
					continue
				var prefix: String = "" if values_value.has("params") else "params"
				_apply_layer(resolved, sources, values_value, BRICK_SOURCE, "params.brick_overrides[%d].values" % override_index, bricks, brick_index, diagnostics, prefix)

	return {"ok": diagnostics.is_empty(), "resolved": resolved, "params": resolved, "sources": sources, "source_table": sources, "diagnostics": diagnostics}

func resolve_params(cfg: Dictionary) -> Dictionary:
	return resolve(cfg)

func _apply_layer(target: Dictionary, sources: Dictionary, layer: Dictionary, source_kind: String, input_root: String, bricks: Array, brick_index: int, diagnostics: Array, prefix: String = "") -> void:
	var leaves: Array[Dictionary] = []
	_collect_leaves(layer, prefix, leaves)
	for leaf in leaves:
		var path: String = String(leaf["path"])
		var rel: String = String(leaf["rel"])
		var value: Variant = leaf["value"]
		var card: Dictionary = {}
		if brick_index >= 0 and brick_index < bricks.size() and bricks[brick_index] is Dictionary:
			card = bricks[brick_index]
		elif brick_index < 0:
			card = _find_card(path, bricks)
		if not _authorized(path, card):
			diagnostics.append(_diagnostic("V-014", _join(input_root, rel), "参数未由该积木开放"))
			continue
		if not _locked(path, card).is_empty():
			diagnostics.append(_diagnostic("V-014", _join(input_root, rel), "锁定参数不可被覆盖"))
			continue
		var existing: Variant = _get_path(target, path)
		if source_kind == BRICK_SOURCE and not _relic_allows(path, card, existing, diagnostics):
			diagnostics.append(_diagnostic("V-014", _join(input_root, rel), "遗物权限不允许该覆盖"))
			continue
		_set_path(target, path, value)
		_record(sources, path, source_kind, _join(input_root, rel), value)

func _merge_layer(target: Dictionary, sources: Dictionary, layer: Dictionary, source_kind: String, input_root: String) -> void:
	var leaves: Array[Dictionary] = []
	_collect_leaves(layer, "", leaves)
	for leaf in leaves:
		var path: String = String(leaf["path"])
		var rel: String = String(leaf["rel"])
		var value: Variant = leaf["value"]
		_set_path(target, path, value)
		_record(sources, path, source_kind, _join(input_root, rel), value)

func _collect_leaves(value: Variant, prefix: String, output: Array[Dictionary], rel: String = "") -> void:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
		for key_value in keys:
			var key: String = String(key_value)
			var child: String = _join(prefix, key)
			var child_rel: String = _join(rel, key)
			_collect_leaves(value[key_value], child, output, child_rel)
		return
	output.append({"path": prefix, "rel": rel, "value": value})

func _find_card(path: String, bricks: Array) -> Dictionary:
	for brick_value in bricks:
		if not brick_value is Dictionary:
			continue
		var brick: Dictionary = brick_value
		if _path_in(brick.get("locked_params", {}), path) or _path_in(brick.get("author_params", []), path):
			return brick
	return {}

func _path_in(values: Variant, path: String) -> bool:
	if values is Dictionary:
		for key_value in values.keys():
			if _same_path(String(key_value), path):
				return true
	elif values is Array:
			for value in values:
				if _same_path(String(value), path):
					return true
	return false

func _same_path(candidate: String, path: String) -> bool:
	return path == candidate or path.ends_with("." + candidate) or path.get_file() == candidate

func _authorized(path: String, card: Dictionary) -> bool:
	var authors: Variant = card.get("author_params", [])
	return card.is_empty() or not authors is Array or authors.is_empty() or _path_in(authors, path)

func _locked(path: String, card: Dictionary) -> String:
	var locked: Variant = card.get("locked_params", {})
	if locked is Dictionary:
		for key_value in locked.keys():
			var key: String = String(key_value)
			if _same_path(key, path):
				return key
	return ""

func _relic_allows(path: String, card: Dictionary, existing: Variant, diagnostics: Array) -> bool:
	var relic: Variant = card.get("relic_params", {})
	if not relic is Dictionary:
		return true
	var status: String = ""
	for key_value in relic.keys():
		var key: String = String(key_value)
		if _same_path(key, path):
			status = String(relic[key_value])
			break
	if status.is_empty():
		return false
	var policy: Array[String] = _load_relic_policy()
	if policy.is_empty():
		var reported: bool = false
		for diagnostic_value in diagnostics:
			if diagnostic_value is Dictionary and String(diagnostic_value.get("rule_id", "")) == RELIC_POLICY_FAILURE_RULE:
				reported = true
				break
		if not reported:
			diagnostics.append(_diagnostic(RELIC_POLICY_FAILURE_RULE, "", "遗物权限策略未载入，无法判定", 0))
		return false
	if policy.size() >= 3 and status == policy[2]:
		return false
	if policy.size() >= 2 and status == policy[1]:
		return existing == null
	return true

func _load_relic_policy() -> Array[String]:
	if _relic_policy_loaded:
		return _relic_policy
	_relic_policy_loaded = true
	var file: FileAccess = FileAccess.open("res://data/relic_policy.json", FileAccess.READ)
	if file == null:
		return _relic_policy
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return _relic_policy
	var enum_value: Variant = parsed.get("enum", [])
	if not enum_value is Array:
		return _relic_policy
	for item_value in enum_value:
		if not item_value is String or String(item_value).is_empty():
			_relic_policy.clear()
			return _relic_policy
		_relic_policy.append(String(item_value))
	if _relic_policy.size() < 3:
		_relic_policy.clear()
	return _relic_policy

func _get_path(root: Dictionary, path: String) -> Variant:
	var current: Variant = root
	for segment in path.split("."):
		if not current is Dictionary or not current.has(segment):
			return null
		current = current[segment]
	return current

func _set_path(root: Dictionary, path: String, value: Variant) -> void:
	var parts: PackedStringArray = path.split(".")
	if parts.is_empty() or parts[0].is_empty():
		return
	var current: Dictionary = root
	for index in range(parts.size() - 1):
		var segment: String = parts[index]
		var child: Variant = current.get(segment, null)
		if not child is Dictionary:
			child = {}
			current[segment] = child
		current = child
	current[parts[parts.size() - 1]] = _copy(value)

func _record(sources: Dictionary, path: String, kind: String, input_path: String, value: Variant) -> void:
	var record: Dictionary = {"source": kind, "input_path": input_path, "value": _copy(value), "final_value": _copy(value)}
	if sources.has(path):
		var previous: Variant = sources[path]
		if previous is Dictionary:
			record["default_value"] = _copy(previous.get("default_value", previous.get("value")))
			var history: Array = previous.get("history", [])
			history.append(previous.duplicate(true))
			record["history"] = history
	elif kind != DEFAULT_SOURCE:
		record["default_value"] = null
	sources[path] = record

func _join(root: String, leaf: String) -> String:
	if root.is_empty():
		return leaf
	if leaf.is_empty():
		return root
	return "%s.%s" % [root, leaf]

func _copy(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value

func _diagnostic(rule_id: String, path: String, message: String, severity: int = 0) -> Dictionary:
	return {"rule_id": rule_id, "code": rule_id, "severity": severity, "path": path, "message": message}
