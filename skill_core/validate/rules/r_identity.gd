class_name IdentityRules
extends RefCounted

const Diag = preload("res://skill_core/api/diagnostic.gd")
const RULES_PATH: String = "res://data/validation_rules.csv"
const MESSAGES_PATH: String = "res://data/error_messages.csv"
const SEVERITIES: Dictionary = {"阻止保存": Diag.SEV_BLOCK, "警告": Diag.SEV_WARN, "提示": Diag.SEV_HINT}

var last_error: String = ""
var _policy: Dictionary = {}
var _rules: Array[Dictionary] = []
var _messages: Dictionary = {}
var _groups: Array[Dictionary] = []
var _ready: bool = false
var _id_regex: RegEx = RegEx.new()
var _version_regex: RegEx = RegEx.new()

# 元数据由调用方从专用 JSON 载入；不读取 Schema YAML/Markdown。
func configure(metadata: Dictionary, rules_path: String = RULES_PATH, messages_path: String = MESSAGES_PATH) -> bool:
	_ready = false
	last_error = ""
	_groups.clear()
	_rules.clear()
	_messages.clear()
	_policy = metadata.duplicate(true)
	for key in ["supported_schema_versions", "categories", "required_card_fields", "runnable_statuses", "internal_terms", "sentence_delimiters"]:
		var values: Variant = _policy.get(key, null)
		if not values is Array or values.is_empty():
			return _fail("元数据 %s 必须是非空字符串数组" % key)
		for value in values:
			if not value is String or value.is_empty():
				return _fail("元数据 %s 含非法条目" % key)
	for key in ["id_pattern", "id_format", "version_pattern"]:
		var value: Variant = _policy.get(key, null)
		if not value is String or value.is_empty():
			return _fail("缺少元数据 %s" % key)
	var verbs: Variant = _policy.get("verb_behaviors", null)
	if not verbs is Dictionary or verbs.is_empty():
		return _fail("缺少动词到行为的登记映射 verb_behaviors")
	for verb in verbs:
		var behaviors: Variant = verbs[verb]
		if not verb is String or verb.is_empty() or not behaviors is Array or behaviors.is_empty():
			return _fail("非法动词行为映射")
		for behavior in behaviors:
			if not behavior is String or behavior.is_empty():
				return _fail("非法行为标识")
	var sentence_limit: Variant = _policy.get("max_player_sentences", null)
	# JSON 的整数数值由 Godot 解析为 float，接受有限的整数值，不接受分数。
	if not (sentence_limit is int or sentence_limit is float):
		return _fail("缺少 max_player_sentences")
	if not is_finite(float(sentence_limit)) or float(sentence_limit) < 1 or float(sentence_limit) != floor(float(sentence_limit)):
		return _fail("max_player_sentences 必须为正整数")
	var produce_paths: Variant = _policy.get("v016_produce_paths", null)
	if produce_paths != null and not produce_paths is Dictionary:
		return _fail("v016_produce_paths 必须是 集合名 -> 字段数组 的映射")
	if produce_paths is Dictionary:
		for collection in produce_paths:
			var fields: Variant = produce_paths[collection]
			if not collection is String or collection.is_empty() or not fields is Array or fields.is_empty():
				return _fail("非法产出引用落点: %s" % str(collection))
			for field in fields:
				# 落点可写字符串，或写 {field, required}；required 缺省视为必填。
				if field is Dictionary:
					if not field.get("field", "") is String or str(field.field).is_empty() or not field.get("required", true) is bool:
						return _fail("非法产出引用落点项: %s.%s" % [str(collection), str(field)])
				elif not field is String or field.is_empty():
					return _fail("非法产出引用字段: %s" % str(field))
	if _id_regex.compile(_policy.id_pattern) != OK or _version_regex.compile(_policy.version_pattern) != OK:
		return _fail("身份元数据正则无效")
	_rules = _read_csv(rules_path, ["rule_id", "condition", "severity", "field_path", "error_code"])
	if not last_error.is_empty():
		return false
	var messages: Array[Dictionary] = _read_csv(messages_path, ["code", "audience", "template", "placeholders"])
	if not last_error.is_empty():
		return false
	for message in messages:
		var code: String = message.code
		if _messages.has(code):
			return _fail("重复文案 code: %s" % code)
		_messages[code] = message.template
	if not register_group(1, 18, _identity_handlers()):
		return false
	_ready = true
	return true

# 分组边界仅用于注册；规则语义按 CSV condition 绑定，不按规则 ID 分支。
# 后续规则组可提供 condition -> Callable(cfg, context, rule) -> Array[Dictionary]。
func register_group(first: int, last: int, handlers: Dictionary) -> bool:
	if first < 1 or last < first:
		return _fail("非法规则区间")
	for group in _groups:
		if first <= int(group.last) and last >= int(group.first):
			return _fail("规则区间重叠")
	var selected: Array[Dictionary] = []
	var seen: Dictionary = {}
	for row in _rules:
		var id: String = row.rule_id
		var suffix: String = id.trim_prefix("V-")
		if not id.begins_with("V-") or not suffix.is_valid_int():
			return _fail("非法规则 ID: %s" % id)
		var number: int = suffix.to_int()
		if number < first or number > last:
			continue
		if seen.has(number):
			return _fail("重复规则 ID: %s" % id)
		if not SEVERITIES.has(row.severity):
			return _fail("未知严重度: %s" % row.severity)
		var handler: Variant = handlers.get(row.condition, null)
		if not handler is Callable or not handler.is_valid():
			return _fail("未绑定条件: %s (%s)" % [row.condition, id])
		var bound: Dictionary = row.duplicate(true)
		bound["handler"] = handler
		bound["paths"] = _quoted_paths(row.field_path)
		if bound.paths.is_empty():
			return _fail("规则字段路径缺失: %s" % id)
		selected.append(bound)
		seen[number] = true
	if selected.size() != last - first + 1:
		return _fail("规则区间不完整: %d..%d" % [first, last])
	_groups.append({"first": first, "last": last, "rules": selected})
	return true

func validate(cfg: Dictionary, context: Dictionary) -> Dictionary:
	if not _ready:
		return _unavailable(last_error if not last_error.is_empty() else "未配置校验元数据")
	last_error = ""
	if not _check_context(context):
		return _unavailable(last_error)
	for index in range(_array_at(cfg, "bricks").size()):
		var card_path: String = "bricks[%d]" % index
		if not context.card_behaviors.has(card_path):
			return _unavailable("缺少 %s 的实际启用行为；不能拿目录能力代替装配结果" % card_path)
	var diagnostics: Array = []
	var notices: Array[String] = []
	var ok: bool = true
	for group in _groups:
		for rule in group.rules:
			var issues: Array = rule.handler.call(cfg, context, rule)
			for issue in issues:
				var diagnostic = _diagnostic(rule, issue, notices)
				diagnostics.append(diagnostic)
				if diagnostic.severity == Diag.SEV_BLOCK:
					ok = false
	return {"ok": ok, "diagnostics": diagnostics, "notices": notices}

func _identity_handlers() -> Dictionary:
	return {
		"版本缺失、非字符串或不是受支持版本": _schema_version,
		"ID 不符合角色、类别、短名、可选变体格式": _identity_format,
		"ID 与其他定义冲突": _duplicate_identity,
		"角色未登记，或与 ID 组成不符": _role,
		"类别不在四种枚举内，或与 ID 不符": _category,
		"短名或变体组成不能还原完整 ID": _name_components,
		"技能版本不符合约定格式或覆盖同版不同内容": _skill_version,
		"显示名为空": _display_name,
		"池引用不存在或同一成员重复": _registered_list,
		"标签不存在或重复": _registered_list,
		"积木目录不存在对应定义或版本不可解析": _brick_reference,
		"保存了未登记或预留积木并要求参与运行": _brick_status,
		"登记卡缺少任一冻结字段": _card_fields,
		"作者覆盖了积木锁定字段": _locked_overrides,
		"同一积木覆盖索引不存在或重复赋值不明确": _override_indices,
		"派生或触发产出引用未解析到有效定义": _output_references,
		"玩家文字含内部事件、原因码或权限术语": _internal_terms,
		"玩家文字超过三句或动词无对应行为": _player_text_behavior,
	}

func _player_text_behavior(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var bricks: Array = _array_at(cfg, "bricks")
	for index in range(bricks.size()):
		var path: String = rule.paths[0].replace("[i]", "[%d]" % index)
		var texts: Array[String] = _text_lines(_get_path(cfg, path))
		var reasons: Array[String] = []
		var count: int = 0
		for text in texts:
			var separated: String = text
			for delimiter in _policy.sentence_delimiters:
				separated = separated.replace(delimiter, "\n")
			for sentence in separated.split("\n", false):
				if not sentence.strip_edges().is_empty():
					count += 1
		if count > int(_policy.max_player_sentences):
			reasons.append("共 %d 句，最多 %d 句" % [count, int(_policy.max_player_sentences)])
		var id: Variant = bricks[index].get("brick_id", null) if bricks[index] is Dictionary else null
		var entry: Variant = context.catalog.get(id, null) if id is String else null
		# 引用无效先由引用规则阻断，不凭缺失上下文推导文案行为错误。
		if entry is Dictionary and entry.resolved:
			var behaviors: Array = context.card_behaviors["bricks[%d]" % index]
			for verb in _policy.verb_behaviors:
				var mentioned: bool = false
				for text in texts:
					mentioned = mentioned or _contains_term(text, verb)
				if not mentioned:
					continue
				var supported: bool = false
				for behavior in _policy.verb_behaviors[verb]:
					supported = supported or behaviors.has(behavior)
				if not supported:
					reasons.append("动词 %s 无对应登记行为" % str(verb))
		if not reasons.is_empty():
			issues.append(_issue(cfg, path, "；".join(reasons)))
	return issues

func _internal_terms(cfg: Dictionary, _context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	for index in range(_array_at(cfg, "bricks").size()):
		var path: String = rule.paths[0].replace("[i]", "[%d]" % index)
		var texts: Array[String] = _text_lines(_get_path(cfg, path))
		var found: Array[String] = []
		for term in _policy.internal_terms:
			for text in texts:
				if _contains_term(text, term) and not found.has(term):
					found.append(term)
		if not found.is_empty():
			issues.append(_issue(cfg, path, "请替换内部术语: %s" % str(found)))
	return issues

func _text_lines(value: Variant) -> Array[String]:
	var lines: Array[String] = []
	if value is Array:
		for item in value:
			if item is String:
				lines.append(item)
	elif value is String:
		lines.append(value)
	return lines

func _contains_term(text: String, term: String) -> bool:
	var lower: String = text.to_lower()
	var needle: String = term.to_lower()
	var start: int = 0
	while start < lower.length():
		var index: int = lower.find(needle, start)
		if index < 0:
			return false
		var end: int = index + needle.length()
		var left_ok: bool = not _ascii_word(needle, 0) or index == 0 or not _ascii_word(lower, index - 1)
		var right_ok: bool = not _ascii_word(needle, needle.length() - 1) or end == lower.length() or not _ascii_word(lower, end)
		if left_ok and right_ok:
			return true
		start = index + 1
	return false

func _ascii_word(text: String, index: int) -> bool:
	var code: int = text.unicode_at(index)
	return (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 95

func _output_references(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _param_scopes(cfg):
		for target in _produce_targets(rule):
			var collection: String = str(target.collection)
			var field: String = str(target.field)
			var required: bool = bool(target.required)
			var entries: Variant = scope.value.get(collection, null)
			if not entries is Array:
				continue
			for index in range(entries.size()):
				var path: String = "%s.%s[%d].%s" % [scope.path, collection, index, field]
				var value: Variant = _get_path(cfg, path)
				if value is Array:
					# Schema 的 produces 是数组：逐项定位到实际下标，不整段判一次。
					for slot in range(value.size()):
						_check_reference(cfg, context, issues, "%s[%d]" % [path, slot], value[slot])
				elif value == null and not _has_path(cfg, path):
					# 必填落点缺失等同于引用未解析；可选落点缺省合法，交给 V-019 判未登记字段。
					if required:
						issues.append(_issue(cfg, path, "引用须唯一解析到有效定义"))
				else:
					_check_reference(cfg, context, issues, path, value)
	return issues

func _check_reference(cfg: Dictionary, context: Dictionary, issues: Array, path: String, reference: Variant) -> void:
	var candidates: Variant = context.outputs.get(reference, null) if reference is String else null
	if not candidates is Array or candidates.size() != 1 or not candidates[0].resolved:
		issues.append(_issue(cfg, path, "引用须唯一解析到有效定义"))

# 落点由数据决定（U-10）：第 14 章写作统称 produces，第 16 章／Schema 的实际字段是
# derivations.child_template 与 triggers.action_profile。元数据给出别名时以其为准；
# 没有别名时退回 CSV 路径。别名不在代码里写死，新增集合只改素材。
func _produce_targets(rule: Dictionary) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	var seen: Dictionary = {}
	var aliases: Variant = _policy.get("v016_produce_paths", null)
	if aliases is Dictionary and not aliases.is_empty():
		for collection in aliases:
			var fields: Variant = aliases[collection]
			if not fields is Array:
				continue
			for field in fields:
				if field is Dictionary:
					_append_target(targets, seen, str(collection), str(field.get("field", "")), bool(field.get("required", true)))
				elif field is String:
					_append_target(targets, seen, str(collection), field, true)
		return targets
	for pattern in rule.paths:
		var text: String = str(pattern).trim_prefix("params.")
		_append_target(targets, seen, text.get_slice("[i]", 0), text.get_slice("[i]", 1).trim_prefix("."), true)
	return targets

func _append_target(targets: Array[Dictionary], seen: Dictionary, collection: String, field: String, required: bool) -> void:
	if collection.is_empty() or field.is_empty():
		return
	var key: String = collection + "." + field
	if seen.has(key):
		return
	seen[key] = true
	targets.append({"collection": collection, "field": field, "required": required})

func _override_indices(cfg: Dictionary, _context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var bricks: Array = _array_at(cfg, "bricks")
	for scope in _param_scopes(cfg):
		var overrides: Variant = scope.value.get("brick_overrides", null)
		if not overrides is Array:
			continue
		var seen: Dictionary = {}
		for index in range(overrides.size()):
			var override: Variant = overrides[index]
			var path: String = rule.paths[0].replace("params.", scope.path + ".").replace("[i]", "[%d]" % index)
			var brick_index: Variant = override.get("brick_index", null) if override is Dictionary else null
			if not brick_index is int or brick_index < 0 or brick_index >= bricks.size() or not bricks[brick_index] is Dictionary:
				issues.append(_issue(cfg, path, "指向现有登记卡的整数索引"))
				continue
			if seen.has(brick_index):
				issues.append(_issue(cfg, path, "索引重复，首次覆盖项 %d" % seen[brick_index]))
			elif override.has("brick_id") and override.brick_id != bricks[brick_index].get("brick_id", null):
				issues.append(_issue(cfg, path, "覆盖项 brick_id 必须与索引指向的卡一致"))
			seen[brick_index] = index
	return issues

func _locked_overrides(cfg: Dictionary, _context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var bricks: Array = _array_at(cfg, "bricks")
	var seen: Dictionary = {}
	var override_pattern: String = rule.paths[0]
	for scope in _param_scopes(cfg):
		var params: Dictionary = scope.value
		var generic: Dictionary = params.duplicate(true)
		generic.erase("brick_overrides")
		# 默认卡本身包含锁定值，不是作者覆盖；只对通用 params 检查这一层。
		if scope.path == "params":
			for card in bricks:
				_check_locks(cfg, card, generic, scope.path, issues, seen)
		var overrides: Variant = params.get("brick_overrides", null)
		if not overrides is Array:
			continue
		for index in range(overrides.size()):
			var override: Variant = overrides[index]
			if not override is Dictionary:
				continue
			var brick_index: Variant = override.get("brick_index", null)
			if not brick_index is int or brick_index < 0 or brick_index >= bricks.size():
				continue
			var values: Variant = override.get("values", null)
			if not values is Dictionary:
				continue
			var path: String = override_pattern.replace("params.", scope.path + ".").replace("[i]", "[%d]" % index)
			_check_locks(cfg, bricks[brick_index], values, path, issues, seen)
	return issues

func _check_locks(cfg: Dictionary, card: Variant, values: Dictionary, path: String, issues: Array, seen: Dictionary) -> void:
	if not card is Dictionary:
		return
	var locked: Variant = card.get("locked_params", null)
	if not locked is Dictionary:
		return
	var leaves: Array[Dictionary] = []
	_collect_leaves(values, "", leaves)
	for key in locked:
		var protected: String = str(key).trim_prefix("params.")
		var writes: Array[String] = []
		for leaf in leaves:
			var logical: String = str(leaf.path).trim_prefix("params.")
			if _paths_overlap(logical, protected):
				writes.append(leaf.path)
		# 数组整体替换也可能删除受锁叶；此时定位到实际提交的数组。
		if writes.is_empty():
			for candidate in [protected, "params." + protected]:
				var array_path: String = _array_ancestor(values, candidate)
				if not array_path.is_empty() and not writes.has(array_path):
					writes.append(array_path)
		for relative in writes:
			var actual_path: String = path + "." + relative
			if not seen.has(actual_path):
				issues.append(_issue(cfg, actual_path, "禁止覆盖锁定字段 %s" % str(key), {"contract": str(locked[key])}))
				seen[actual_path] = true

func _array_ancestor(values: Dictionary, protected: String) -> String:
	var current: Variant = values
	var walked: String = ""
	for segment in protected.replace("[", ".").replace("]", "").split("."):
		if current is Array:
			return walked
		if not current is Dictionary or not current.has(segment):
			return ""
		current = current[segment]
		walked = segment if walked.is_empty() else walked + "." + segment
	return ""

func _paths_overlap(left: String, right: String) -> bool:
	return left == right or left.begins_with(right + ".") or left.begins_with(right + "[") or right.begins_with(left + ".") or right.begins_with(left + "[")

func _collect_leaves(value: Variant, path: String, leaves: Array[Dictionary]) -> void:
	if value is Dictionary and not value.is_empty():
		for key in value:
			_collect_leaves(value[key], str(key) if path.is_empty() else path + "." + str(key), leaves)
	elif value is Array and not value.is_empty():
		for index in range(value.size()):
			_collect_leaves(value[index], path + "[%d]" % index, leaves)
	elif not path.is_empty():
		leaves.append({"path": path, "value": value})

func _param_scopes(cfg: Dictionary) -> Array[Dictionary]:
	var scopes: Array[Dictionary] = []
	var params: Variant = cfg.get("params", null)
	if params is Dictionary:
		scopes.append({"path": "params", "value": params})
	var bricks: Array = _array_at(cfg, "bricks")
	for index in range(bricks.size()):
		if not bricks[index] is Dictionary:
			continue
		var defaults: Variant = bricks[index].get("default_cfg", null)
		if not defaults is Dictionary:
			continue
		scopes.append({"path": "bricks[%d].default_cfg" % index, "value": defaults})
		var nested: Variant = defaults.get("params", null)
		if nested is Dictionary:
			scopes.append({"path": "bricks[%d].default_cfg.params" % index, "value": nested})
	var base_scopes: Array[Dictionary] = scopes.duplicate()
	for scope in base_scopes:
		var overrides: Variant = scope.value.get("brick_overrides", null)
		if not overrides is Array:
			continue
		for index in range(overrides.size()):
			if not overrides[index] is Dictionary:
				continue
			var values: Variant = overrides[index].get("values", null)
			if not values is Dictionary:
				continue
			var path: String = scope.path + ".brick_overrides[%d].values" % index
			scopes.append({"path": path, "value": values})
			var nested_values: Variant = values.get("params", null)
			if nested_values is Dictionary:
				scopes.append({"path": path + ".params", "value": nested_values})
	return scopes

func _card_fields(cfg: Dictionary, _context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var root_pattern: String = rule.paths[0].get_slice("].", 0) + "]"
	var bricks: Array = _array_at(cfg, "bricks")
	for index in range(bricks.size()):
		var card: Variant = bricks[index]
		for field in _policy.required_card_fields:
			if not card is Dictionary or not card.has(field):
				var path: String = root_pattern.replace("[i]", "[%d]" % index) + "." + field
				issues.append(_issue(cfg, path, "登记卡必填槽位 %s" % field))
	return issues

func _brick_status(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var bricks: Array = _array_at(cfg, "bricks")
	for index in range(bricks.size()):
		if not bricks[index] is Dictionary:
			continue
		var card: Dictionary = bricks[index]
		var path: String = rule.paths[0].replace("[i]", "[%d]" % index)
		var status: Variant = card.get("status", null)
		var id: Variant = card.get("brick_id", null)
		var entry: Variant = context.catalog.get(id, null) if id is String else null
		var catalog_status: Variant = entry.get("status", null) if entry is Dictionary else null
		if not _policy.runnable_statuses.has(status) or not _policy.runnable_statuses.has(catalog_status):
			issues.append(_issue(cfg, path, "可运行状态: %s" % str(_policy.runnable_statuses), {"brick": str(id), "status": "卡=%s，目录=%s" % [str(status), str(catalog_status)]}))
	return issues

func _brick_reference(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	for index in range(_array_at(cfg, "bricks").size()):
		var path: String = rule.paths[0].replace("[i]", "[%d]" % index)
		var id: Variant = _get_path(cfg, path)
		var entry: Variant = context.catalog.get(id, null) if id is String else null
		if not entry is Dictionary or not entry.resolved:
			issues.append(_issue(cfg, path, "积木定义必须存在且版本可解析"))
	return issues

func _array_at(root: Dictionary, path: String) -> Array:
	var value: Variant = _get_path(root, path)
	return value if value is Array else []

func _registered_list(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var pattern: String = rule.paths[0]
	var path: String = pattern.trim_suffix("[i]")
	var registry: Array = context[path.get_slice(".", 1)]
	var values: Variant = _get_path(cfg, path)
	if not values is Array:
		return [] # 可选集合缺省合法；类型由 T-011 处理。
	var seen: Dictionary = {}
	var issues: Array = []
	for index in range(values.size()):
		var value: Variant = values[index]
		var actual_path: String = pattern.replace("[i]", "[%d]" % index)
		if not value is String or not registry.has(value):
			issues.append(_issue(cfg, actual_path, "引用必须存在于登记表"))
		elif seen.has(value):
			issues.append(_issue(cfg, actual_path, "引用重复，首次位置 %s[%d]" % [path, seen[value]]))
		else:
			seen[value] = index
	return issues

func _display_name(cfg: Dictionary, _context: Dictionary, rule: Dictionary) -> Array:
	var path: String = rule.paths[0]
	var value: Variant = _get_path(cfg, path)
	if not value is String or value.strip_edges().is_empty():
		return [_issue(cfg, path, "非空显示名")]
	return []

func _skill_version(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var path: String = rule.paths[0]
	var version: Variant = _get_path(cfg, path)
	if not version is String or _version_regex.search(version) == null:
		return [_issue(cfg, path, _policy.version_pattern)]
	for entry in context.definitions:
		if entry.source != context.current_source or context.current_source.is_empty():
			continue
		if _get_path(entry.cfg, path) == version and not _same_value(entry.cfg, cfg):
			return [_issue(cfg, path, "同版不同内容；请递增技能版本")]
	return []

# 字典键顺序不是内容；数组顺序和实际值类型仍有意义。
func _same_value(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not _same_value(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for index in range(left.size()):
			if not _same_value(left[index], right[index]):
				return false
		return true
	return left == right

func _name_components(cfg: Dictionary, _context: Dictionary, rule: Dictionary) -> Array:
	var paths: Array = rule.paths
	var short_name: Variant = _get_path(cfg, paths[0])
	var variant: Variant = _get_path(cfg, paths[1]) if _has_path(cfg, paths[1]) else ""
	var issues: Array = []
	if not short_name is String or short_name.is_empty():
		issues.append(_issue(cfg, paths[0], "非空短名"))
	if not variant is String:
		issues.append(_issue(cfg, paths[1], "可空的字符串变体"))
	if not issues.is_empty():
		return issues
	var role: Variant = _get_path(cfg, "meta.role")
	var category: Variant = _get_path(cfg, "meta.category")
	var id: Variant = cfg.get("skill_id", null)
	if not role is String or not category is String or not id is String:
		return []
	var prefix: String = role + "_" + category + "_"
	if not id.begins_with(prefix):
		return []
	var reconstructed: String = prefix + short_name + ("_" + variant if not variant.is_empty() else "")
	if reconstructed != id:
		issues.append(_issue(cfg, paths[0], "短名与变体应还原 %s，实际还原 %s" % [id, reconstructed]))
		if not variant.is_empty():
			issues.append(_issue(cfg, paths[1], "与短名共同还原 %s" % id))
	return issues

func _category(cfg: Dictionary, _context: Dictionary, rule: Dictionary) -> Array:
	var path: String = rule.paths[0]
	var category: Variant = _get_path(cfg, path)
	if not category is String or not _policy.categories.has(category):
		return [_issue(cfg, path, str(_policy.categories))]
	var role: Variant = _get_path(cfg, "meta.role")
	var id: Variant = cfg.get("skill_id", null)
	if role is String and id is String and id.begins_with(role + "_"):
		if not id.begins_with(role + "_" + category + "_"):
			return [_issue(cfg, path, "与 skill_id 的类别组成一致")]
	return []

func _role(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var path: String = rule.paths[0]
	var role: Variant = _get_path(cfg, path)
	var id: Variant = cfg.get("skill_id", null)
	if not role is String or not context.roles.has(role):
		return [_issue(cfg, path, "已登记角色: %s" % str(context.roles))]
	if id is String and _id_regex.search(id) != null and not id.begins_with(role + "_"):
		return [_issue(cfg, path, "与 skill_id 的角色前缀一致")]
	return []

func _duplicate_identity(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var path: String = rule.paths[0]
	var id: Variant = _get_path(cfg, path)
	if not id is String or id.is_empty():
		return []
	for entry in context.definitions:
		if not context.current_source.is_empty() and entry.source == context.current_source:
			continue
		if _get_path(entry.cfg, path) == id:
			return [_issue(cfg, path, "不得与其他定义重复", {"conflict": entry.source})]
	return []

func _identity_format(cfg: Dictionary, _context: Dictionary, rule: Dictionary) -> Array:
	var path: String = rule.paths[0]
	var value: Variant = _get_path(cfg, path)
	if not value is String or _id_regex.search(value) == null:
		return [_issue(cfg, path, _policy.id_format)]
	return []

func _schema_version(cfg: Dictionary, _context: Dictionary, rule: Dictionary) -> Array:
	var path: String = rule.paths[0]
	var value: Variant = _get_path(cfg, path)
	if not value is String or not _policy.supported_schema_versions.has(value):
		return [_issue(cfg, path, str(_policy.supported_schema_versions))]
	return []

func _check_context(context: Dictionary) -> bool:
	for key in ["roles", "pools", "tags", "definitions"]:
		if not context.get(key, null) is Array:
			return _fail("校验上下文缺少数组 %s" % key)
	for key in ["roles", "pools", "tags"]:
		for entry in context[key]:
			if not entry is String or entry.is_empty():
				return _fail("登记表 %s 含非法标识" % key)
	for key in ["catalog", "outputs", "card_behaviors"]:
		if not context.get(key, null) is Dictionary:
			return _fail("校验上下文缺少映射 %s" % key)
	if not context.get("current_source", null) is String:
		return _fail("校验上下文缺少 current_source；新定义可显式传空字符串")
	for entry in context.definitions:
		if not entry is Dictionary or not entry.get("source", null) is String or not entry.get("cfg", null) is Dictionary:
			return _fail("definitions 项必须含 source 与 cfg")
	for id in context.catalog:
		var entry: Variant = context.catalog[id]
		if not entry is Dictionary or not entry.get("resolved", null) is bool or not entry.get("status", null) is String:
			return _fail("目录 %s 缺少 resolved/status" % str(id))
	for path in context.card_behaviors:
		var behaviors: Variant = context.card_behaviors[path]
		if not behaviors is Array:
			return _fail("%s 的实际行为必须是数组" % str(path))
		for behavior in behaviors:
			if not behavior is String or behavior.is_empty():
				return _fail("%s 含非法行为标识" % str(path))
	for id in context.outputs:
		var entries: Variant = context.outputs[id]
		if not entries is Array:
			return _fail("产出引用 %s 必须映射到解析候选数组" % str(id))
		for entry in entries:
			if not entry is Dictionary or not entry.get("resolved", null) is bool:
				return _fail("产出引用 %s 缺少 resolved" % str(id))
	return true

func _read_csv(path: String, required: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("无法读取 CSV: %s" % path)
		return rows
	var header: PackedStringArray = file.get_csv_line()
	if not header.is_empty():
		header[0] = header[0].trim_prefix("﻿")
	for column in required:
		if not header.has(column):
			_fail("CSV %s 缺少列 %s" % [path, column])
			return []
	while not file.eof_reached():
		var columns: PackedStringArray = file.get_csv_line()
		if columns.size() == 1 and columns[0].is_empty():
			continue
		if columns.size() != header.size():
			_fail("CSV %s 列数错误（记录 %d）" % [path, rows.size() + 2])
			return []
		var row: Dictionary = {}
		for index in range(header.size()):
			row[header[index]] = columns[index]
		rows.append(row)
	if rows.is_empty():
		_fail("CSV 为空: %s" % path)
	return rows

func _quoted_paths(description: String) -> Array[String]:
	var paths: Array[String] = []
	var parts: PackedStringArray = description.split("`")
	for index in range(1, parts.size(), 2):
		paths.append(parts[index])
	return paths

func _get_path(root: Variant, path: String) -> Variant:
	var current: Variant = root
	for segment in path.replace("[", ".").replace("]", "").split("."):
		if current is Dictionary:
			current = current.get(segment, null)
		elif current is Array and segment.is_valid_int():
			var index: int = segment.to_int()
			if index < 0 or index >= current.size():
				return null
			current = current[index]
		else:
			return null
	return current

func _has_path(root: Variant, path: String) -> bool:
	var current: Variant = root
	for segment in path.replace("[", ".").replace("]", "").split("."):
		if current is Dictionary and current.has(segment):
			current = current[segment]
		elif current is Array and segment.is_valid_int():
			var index: int = segment.to_int()
			if index < 0 or index >= current.size():
				return false
			current = current[index]
		else:
			return false
	return true

func _issue(cfg: Dictionary, path: String, expected: String, tokens: Dictionary = {}) -> Dictionary:
	var value: Variant = _get_path(cfg, path)
	var actual: String = "未填写" if not _has_path(cfg, path) else _display(value)
	return {"path": path, "actual": actual, "expected": expected, "tokens": tokens}

func _display(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Array and value.is_empty():
		return "空列表"
	return str(value)

func _diagnostic(rule: Dictionary, issue: Dictionary, notices: Array[String]):
	var diagnostic = Diag.new()
	diagnostic.rule_id = rule.rule_id
	diagnostic.code = rule.error_code
	diagnostic.severity = SEVERITIES[rule.severity]
	diagnostic.path = issue.path
	diagnostic.actual = issue.actual
	diagnostic.expected = issue.expected
	var tokens: Dictionary = {
		"path": issue.path, "field": issue.path, "actual": issue.actual,
		"expected": issue.expected, "id": issue.actual, "version": issue.actual,
		"reason": issue.expected, "ref": issue.actual, "brick": issue.actual,
		"status": issue.actual, "format": issue.expected, "supported": issue.expected,
		"context": rule.condition, "conflict": issue.expected,
		"source": "作者覆盖", "contract": rule.condition,
		"suggestion": issue.expected
	}
	tokens.merge(issue.tokens, true)
	var template: String = str(_messages.get(rule.error_code, ""))
	if template.is_empty():
		var notice: String = "缺失文案模板 %s（规则 %s）" % [rule.error_code, rule.rule_id]
		if not notices.has(notice):
			notices.append(notice)
		diagnostic.hint = "[%s/%s] %s：%s；要求 %s（%s）" % [rule.rule_id, rule.error_code, issue.path, issue.actual, issue.expected, notice]
		return diagnostic
	for key in tokens:
		template = template.replace("{%s}" % key, str(tokens[key]))
	if template.contains("{"):
		var notice: String = "文案 %s 有未解析占位符: %s" % [rule.error_code, template]
		notices.append(notice)
		template += " [文案元数据不完整]"
	diagnostic.hint = template
	return diagnostic

func _fail(message: String) -> bool:
	last_error = message
	return false

func _unavailable(message: String) -> Dictionary:
	last_error = message
	var diagnostic = Diag.new()
	diagnostic.rule_id = "VALIDATION_SETUP"
	diagnostic.code = "VALIDATION_METADATA_UNAVAILABLE"
	diagnostic.path = "validation_context"
	diagnostic.actual = message
	diagnostic.expected = "提供完整元数据和引用解析上下文"
	diagnostic.hint = message
	return {"ok": false, "diagnostics": [diagnostic], "notices": [message]}
