class_name TypesRules
extends RefCounted

const Diag = preload("res://skill_core/api/diagnostic.gd")
const RULES_PATH: String = "res://data/validation_rules.csv"
const MESSAGES_PATH: String = "res://data/error_messages.csv"
const META_REQUIRED: Array[String] = ["leaves", "arrays", "objects", "tick_fields", "enums", "rule_field_aliases", "restricted_reasons"]
const SEVERITIES: Dictionary = {"阻止保存": Diag.SEV_BLOCK, "警告": Diag.SEV_WARN, "提示": Diag.SEV_HINT}

var last_error: String = ""
var _meta: Dictionary = {}
var _rules: Array[Dictionary] = []
var _messages: Dictionary = {}
var _groups: Array[Dictionary] = []
var _ready: bool = false

func configure(metadata: Dictionary, rules_path: String = RULES_PATH, messages_path: String = MESSAGES_PATH) -> bool:
	_ready = false
	last_error = ""
	_meta = {}
	_rules.clear()
	_messages.clear()
	_groups.clear()
	for key in META_REQUIRED:
		var value: Variant = metadata.get(key, null)
		if value == null or not (value is Array or value is Dictionary):
			return _fail("参数元数据缺少 %s" % key)
	_meta = metadata.duplicate(true)
	var leaves: Variant = _meta.get("leaves", null)
	var arrays: Variant = _meta.get("arrays", null)
	var objects: Variant = _meta.get("objects", null)
	var ticks: Variant = _meta.get("tick_fields", null)
	if not leaves is Array or leaves.is_empty() or not arrays is Array or not objects is Array or not ticks is Array:
		return _fail("参数元数据集合无效")
	for entry in leaves:
		if not entry is Dictionary or not entry.get("path", null) is String or not entry.get("type", null) is String:
			return _fail("参数叶元数据无效")
	for field in ticks:
		if not field is String or field.is_empty():
			return _fail("tick_fields 含非法路径")
	var enums: Variant = _meta.get("enums", null)
	if not enums is Dictionary or enums.is_empty():
		return _fail("枚举元数据缺失")
	var aliases: Variant = _meta.get("rule_field_aliases", null)
	if not aliases is Dictionary:
		return _fail("rule_field_aliases 必须是映射")
	var restricted: Variant = _meta.get("restricted_reasons", null)
	if not restricted is Array:
		return _fail("restricted_reasons 必须是数组")
	_rules = _read_csv(rules_path, ["rule_id", "condition", "severity", "field_path", "error_code"])
	if not last_error.is_empty():
		return false
	var message_rows: Array[Dictionary] = _read_csv(messages_path, ["code", "audience", "template", "placeholders"])
	if not last_error.is_empty():
		return false
	for row in message_rows:
		var code: String = str(row.get("code", ""))
		if code.is_empty() or _messages.has(code):
			return _fail("文案 code 缺失或重复: %s" % code)
		_messages[code] = str(row.get("template", ""))
	if not register_group(19, 38, _handlers()):
		return false
	_ready = true
	return true

func register_group(first: int, last: int, handlers: Dictionary) -> bool:
	if first < 1 or last < first:
		return _fail("非法规则区间")
	for old_group in _groups:
		if first <= int(old_group.get("last", 0)) and last >= int(old_group.get("first", 0)):
			return _fail("规则区间重叠")
	var selected: Array[Dictionary] = []
	var seen: Dictionary = {}
	for row in _rules:
		var rule_id: String = str(row.get("rule_id", ""))
		var suffix: String = rule_id.trim_prefix("V-")
		if not rule_id.begins_with("V-") or not suffix.is_valid_int():
			return _fail("非法规则 ID: %s" % rule_id)
		var number: int = suffix.to_int()
		if number < first or number > last:
			continue
		if seen.has(number):
			return _fail("重复规则 ID: %s" % rule_id)
		var severity: String = str(row.get("severity", ""))
		if not SEVERITIES.has(severity):
			return _fail("未知严重度: %s" % severity)
		var handler: Variant = handlers.get(str(row.get("condition", "")), null)
		if not handler is Callable or not handler.is_valid():
			return _fail("未绑定条件: %s (%s)" % [str(row.get("condition", "")), rule_id])
		var bound: Dictionary = row.duplicate(true)
		bound["handler"] = handler
		bound["paths"] = _quoted_paths(str(row.get("field_path", "")))
		if bound.paths.is_empty():
			return _fail("规则字段路径缺失: %s" % rule_id)
		selected.append(bound)
		seen[number] = true
	if selected.size() != last - first + 1:
		return _fail("规则区间不完整: %d..%d" % [first, last])
	_groups.append({"first": first, "last": last, "rules": selected})
	return true

func validate(cfg: Dictionary, context: Dictionary) -> Dictionary:
	if not _ready:
		return _unavailable(last_error if not last_error.is_empty() else "未配置参数校验元数据")
	last_error = ""
	if not _check_context(context):
		return _unavailable(last_error)
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

func _handlers() -> Dictionary:
	return {
		"出现未登记字段、非法顶层键或重复映射键": _unknown_fields,
		"登记字段类型不符、数值非有限或不在声明范围": _typed_fields,
		"tick 字段为负数、分数或附带秒字符串": _tick_fields,
		"开始延迟或出手时间点不是非负整数 tick": _shot_point_fields,
		"出手时间表不是非递减序列或为空却声明主动出手": _shot_sequence,
		"载体不是主书稿四类载体之一": _carrier,
		"瞬时无载体实例声明非零寿命": _instant_lifetime,
		"持续效果体缺少合法寿命或契约允许的上限声明": _persistent_lifetime,
		"命中限额不是正整数": _positive_hit_limits,
		"重复接触间隔存在但不是正整数 tick": _rehit_interval,
		"重复跳伤的区域或环绕积木缺重复间隔": _repeat_interval_required,
		"同时配置限额与间隔，却把二者标成择一生效": _exclusive_hit_policy,
		"目标丢失策略超出 continue、terminate": _target_lost,
		"事件派生订阅不是 hit 或 vanish": _derivation_event,
		"vanish 原因包含 purge 或非冻结原因码": _vanish_reasons,
		"range_end 或 interrupted 派生未显式授权": _restricted_reason,
		"非抛射积木要求 landed 原因派生": _landed_reason,
		"配置要求瞬时实例以其他自然结束原因终止": _instant_reason,
		"派生规则试图按每份重复派生或订阅状态到期": _derivation_shape,
		"份类型未登记或固定索引重复": _parts
	}

func _unknown_fields(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		_walk_unknown(scope.value, "", scope.path, cfg, issues)
	return issues

func _typed_fields(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		for entry in _meta.leaves:
			var path_pattern: String = str(entry.get("path", ""))
			var matches: Array = []
			_expand(scope.value, _tokens(path_pattern), 0, "", matches)
			for hit in matches:
				var value: Variant = hit.value
				var reason: String = _type_or_range_error(value, entry)
				if not reason.is_empty():
					issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)), reason))
	return issues

func _tick_fields(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		for pattern in _meta.tick_fields:
			var matches: Array = []
			_expand(scope.value, _tokens(str(pattern)), 0, "", matches)
			for hit in matches:
				var value: Variant = hit.value
				if not (value is int):
					continue # V-020 owns type diagnostics; do not duplicate dependent range errors.
				var minimum: int = 1 if str(pattern).ends_with("rehit_interval_ticks") else 0
				if int(value) < minimum:
					issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)), "整数 tick，最小值 %d" % minimum))
	return issues

func _shot_point_fields(cfg: Dictionary, _context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		for pattern in ["start_delay_ticks", "shot_ticks[i]", "templates[i].cast.shot_ticks[i]"]:
			var matches: Array = []
			_expand(scope.value, _tokens(pattern), 0, "", matches)
			for hit in matches:
				if not hit.value is int or int(hit.value) < 0:
					issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)), "非负整数 tick"))
	return issues

func _shot_sequence(cfg: Dictionary, context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		for pattern in ["shot_ticks", "templates[i].cast.shot_ticks"]:
			var matches: Array = []
			_expand(scope.value, _tokens(pattern), 0, "", matches, true)
			var arrays: Array = []
			for hit in matches:
				if hit.value is Array and not arrays.has(hit):
					arrays.append(hit)
			for hit in arrays:
				var values: Array = hit.value
				var previous: int = -1
				for index in range(values.size()):
					if values[index] is int and int(values[index]) < previous:
						issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)) + "[%d]" % index, "出手 tick 必须非递减"))
						break
					if values[index] is int:
						previous = int(values[index])
				if values.is_empty() and _declares_active_shot(scope.value, context, str(hit.path)):
					issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)), "主动出手必须提供非空时间表"))
	return issues

func _carrier(cfg: Dictionary, _context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var allowed: Array = _enum("carrier")
	for scope in _scopes(cfg):
		for pattern in ["carrier", "templates[i].carrier"]:
			var matches: Array = []
			_expand(scope.value, _tokens(pattern), 0, "", matches)
			for hit in matches:
				if not hit.value is String or not allowed.has(hit.value):
					issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)), "载体枚举 %s" % str(allowed)))
	return issues

func _instant_lifetime(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		var carrier: Variant = scope.value.get("carrier", null)
		if carrier != "none":
			continue
		for pattern in ["lifetime_ticks", "templates[i].lifetime_ticks"]:
			var matches: Array = []
			_expand(scope.value, _tokens(pattern), 0, "", matches)
			for hit in matches:
				if hit.value is int and int(hit.value) != 0:
					issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)), "瞬时无载体寿命必须为 0"))
	return issues

func _persistent_lifetime(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		var carrier: Variant = scope.value.get("carrier", null)
		if carrier == null or carrier == "none":
			continue
		var path: String = scope.path + ".lifetime_ticks"
		if not scope.value.has("lifetime_ticks") or not scope.value.lifetime_ticks is int or int(scope.value.lifetime_ticks) < 0:
			issues.append(_issue(cfg, path, "持续效果体必须有合法非负寿命"))
	return issues

func _positive_hit_limits(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		for pattern in ["hit_policy.per_target_limit", "hit_policy.max_hits", "templates[i].hit_policy.per_target_limit", "templates[i].hit_policy.max_hits"]:
			var matches: Array = []
			_expand(scope.value, _tokens(pattern), 0, "", matches)
			for hit in matches:
				if not hit.value is int or int(hit.value) <= 0:
					issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)), "正整数"))
	return issues

func _rehit_interval(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		for pattern in ["hit_policy.rehit_interval_ticks", "templates[i].hit_policy.rehit_interval_ticks"]:
			var matches: Array = []
			_expand(scope.value, _tokens(pattern), 0, "", matches)
			for hit in matches:
				if not hit.value is int or int(hit.value) <= 0:
					issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)), "正整数 tick"))
	return issues

func _repeat_interval_required(cfg: Dictionary, context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		if not _has_repeat_capability(context, scope.path):
			continue
		var policy: Variant = scope.value.get("hit_policy", null)
		if not policy is Dictionary or not policy.has("rehit_interval_ticks"):
			issues.append(_issue(cfg, scope.path + ".hit_policy.rehit_interval_ticks", "重复跳伤必须声明重复间隔"))
	return issues

func _exclusive_hit_policy(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		var policy: Variant = scope.value.get("hit_policy", null)
		if not policy is Dictionary:
			continue
		if policy.has("per_target_limit") and policy.has("rehit_interval_ticks"):
			for key in ["strategy", "mode", "selection"]:
				var value: Variant = policy.get(key, null)
				if value in ["either", "exclusive", "one_of", "择一"]:
					issues.append(_issue(cfg, scope.path + ".hit_policy." + key, "限额与间隔应同时生效"))
	return issues

func _target_lost(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		for pattern in ["on_target_lost", "templates[i].on_target_lost"]:
			var matches: Array = []
			_expand(scope.value, _tokens(pattern), 0, "", matches)
			for hit in matches:
				if not hit.value is String or not _enum("on_target_lost").has(hit.value):
					issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)), "continue 或 terminate"))
	return issues

func _derivation_event(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		var patterns: Array[String] = []
		for pattern in _field_aliases("derivations[i].on", ["derivations[i].event"]):
			patterns.append(pattern)
			patterns.append("templates[i]." + pattern)
		for pattern in patterns:
			var matches: Array = []
			_expand(scope.value, _tokens(pattern), 0, "", matches)
			for hit in matches:
				if not hit.value is String or not _enum("event").has(hit.value):
					issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)), "hit 或 vanish"))
	return issues

func _vanish_reasons(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		for pattern in ["derivations[i].reasons[i]", "templates[i].derivations[i].reasons[i]"]:
			var matches: Array = []
			_expand(scope.value, _tokens(pattern), 0, "", matches)
			for hit in matches:
				if not hit.value is String or not _enum("vanish_reason").has(hit.value):
					issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)), "冻结结束原因码"))
	return issues

func _restricted_reason(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		for derivation_pattern in ["derivations[i]", "templates[i].derivations[i]"]:
			var matches: Array = []
			_expand(scope.value, _tokens(derivation_pattern), 0, "", matches, true)
			for hit in matches:
				if not hit.value is Dictionary:
					continue
				var reasons: Variant = hit.value.get("reasons", null)
				if not reasons is Array:
					continue
				for reason in _meta.restricted_reasons:
					if reasons.has(reason) and (not hit.value.has("allow_restricted_reason") or hit.value.get("allow_restricted_reason", null) != true):
						issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)) + ".allow_restricted_reason", "必须显式填写 true 才能使用 %s" % reason))
	return issues

func _landed_reason(cfg: Dictionary, context: Dictionary, _rule: Dictionary) -> Array:
	return _capability_reason_issues(cfg, context, false)

func _instant_reason(cfg: Dictionary, context: Dictionary, _rule: Dictionary) -> Array:
	return _capability_reason_issues(cfg, context, true)

func _capability_reason_issues(cfg: Dictionary, context: Dictionary, instant_only: bool) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		for pattern in ["derivations[i]", "templates[i].derivations[i]"]:
			var matches: Array = []
			_expand(scope.value, _tokens(pattern), 0, "", matches, true)
			for hit in matches:
				if not hit.value is Dictionary:
					continue
				var reasons: Variant = hit.value.get("reasons", null)
				if not reasons is Array:
					continue
				var capabilities: Variant = _capabilities_for(context, scope.path + _join_path(str(hit.path)))
				if capabilities == null:
					continue
				var projectile: bool = _capability_bool(capabilities, ["projectile", "is_projectile", "projectile_like"])
				var instant: bool = _capability_bool(capabilities, ["instant", "is_instant"])
				if not instant_only and not projectile and reasons.has("landed"):
					issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)) + ".reasons[%d]" % reasons.find("landed"), "非抛射积木不能派生 landed"))
				if instant_only and instant:
					for index in range(reasons.size()):
						if reasons[index] != "instant_end":
							issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)) + ".reasons[%d]" % index, "瞬时实例只能使用 instant_end"))
	return issues

func _derivation_shape(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		for pattern in ["derivations[i]", "templates[i].derivations[i]"]:
			var matches: Array = []
			_expand(scope.value, _tokens(pattern), 0, "", matches, true)
			for hit in matches:
				if not hit.value is Dictionary:
					continue
				for key in ["per_part", "per_piece", "per_settlement", "on_state", "state_expired", "on_expire"]:
					if hit.value.has(key):
						issues.append(_issue(cfg, scope.path + _join_path(str(hit.path)) + "." + key, "派生只能订阅 hit 或 vanish，不能按份或状态到期重复派生"))
	return issues

func _parts(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	var allowed: Array = _enum("part_type")
	for scope in _scopes(cfg):
		for pattern in ["parts[i]", "templates[i].parts[i]"]:
			var matches: Array = []
			_expand(scope.value, _tokens(pattern), 0, "", matches, true)
			var seen: Dictionary = {}
			for hit in matches:
				if not hit.value is Dictionary:
					continue
				var item: Dictionary = hit.value
				var actual: String = scope.path + _join_path(str(hit.path))
				var type_value: Variant = item.get("type", null)
				if not type_value is String or not allowed.has(type_value):
					issues.append(_issue(cfg, actual + ".type", "已登记份类型 %s" % str(allowed)))
				var index_value: Variant = item.get("part_index", null)
				if index_value is int:
					if seen.has(index_value):
						issues.append(_issue(cfg, actual + ".part_index", "固定索引不得重复"))
					else:
						seen[index_value] = true
	return issues

func _check_context(context: Dictionary) -> bool:
	var has_capability_context: bool = context.get("capabilities", null) is Dictionary or context.get("template_capabilities", null) is Dictionary or context.get("card_behaviors", null) is Dictionary
	if not has_capability_context:
		return _fail("缺少能力上下文；V-035/V-036 不能猜测积木是否抛射或瞬时")
	return true

func _scopes(cfg: Dictionary) -> Array[Dictionary]:
	var scopes: Array[Dictionary] = []
	var params: Variant = cfg.get("params", null)
	if params is Dictionary:
		scopes.append({"path": "params", "value": params})
	var bricks: Variant = cfg.get("bricks", null)
	if bricks is Array:
		for index in range(bricks.size()):
			if not bricks[index] is Dictionary:
				continue
			var card: Dictionary = bricks[index]
			var defaults: Variant = card.get("default_cfg", null)
			if defaults is Dictionary:
				var nested: Variant = defaults.get("params", null)
				if nested is Dictionary:
					scopes.append({"path": "bricks[%d].default_cfg.params" % index, "value": nested})
		if params is Dictionary:
			var overrides: Variant = params.get("brick_overrides", null)
			if overrides is Array:
				for override_index in range(overrides.size()):
					var override: Variant = overrides[override_index]
					if override is Dictionary and override.get("values", null) is Dictionary:
						scopes.append({"path": "params.brick_overrides[%d].values" % override_index, "value": override.values})
	return scopes

func _enum(name: String) -> Array:
	var enums: Variant = _meta.get("enums", null)
	if not enums is Dictionary:
		return []
	var value: Variant = enums.get(name, null)
	return value if value is Array else []

func _field_aliases(source: String, fallback: Array[String]) -> Array[String]:
	var aliases: Variant = _meta.get("rule_field_aliases", null)
	if aliases is Dictionary:
		var mapped: Variant = aliases.get(source, null)
		if mapped is Array and not mapped.is_empty():
			var result: Array[String] = []
			for item in mapped:
				if item is String and not item.is_empty():
					result.append("derivations[i]." + item if not item.begins_with("derivations[") else item)
			if not result.is_empty():
				return result
	return fallback

# V-020：类型不符、数值非有限或不在声明范围。字符串数字（"3"）算类型错，不参与数值比较。
func _type_or_range_error(value: Variant, entry: Dictionary) -> String:
	var expected_type: String = str(entry.get("type", ""))
	if expected_type == "string" and not value is String:
		return "字符串"
	if expected_type == "boolean" and not value is bool:
		return "布尔值"
	if expected_type == "integer" and not value is int:
		return "整数"
	if expected_type == "number" and not (value is int or value is float):
		return "有限数值"
	if value is float and not is_finite(float(value)):
		return "有限数值"
	if value is int or value is float:
		if entry.has("minimum") and float(value) < float(entry.minimum):
			return "不小于 %s" % str(entry.minimum)
		if entry.has("exclusiveMinimum") and float(value) <= float(entry.exclusiveMinimum):
			return "大于 %s" % str(entry.exclusiveMinimum)
		if entry.has("maximum") and float(value) > float(entry.maximum):
			return "不大于 %s" % str(entry.maximum)
	if value is String and entry.has("minLength") and value.length() < int(entry.minLength):
		return "非空字符串"
	var allowed: Variant = entry.get("enum", null)
	if allowed is Array and not allowed.has(value):
		return "登记枚举 %s" % str(allowed)
	return ""

func _capabilities_for(context: Dictionary, path: String) -> Variant:
	for key in ["capabilities", "template_capabilities", "card_behaviors"]:
		var table: Variant = context.get(key, null)
		if not table is Dictionary:
			continue
		if table.has(path):
			return table[path]
		var prefix: String = path
		while prefix.contains("."):
			prefix = prefix.rsplit(".", true, 1)[0]
			if table.has(prefix):
				return table[prefix]
	return null

func _capability_bool(value: Variant, keys: Array[String]) -> bool:
	if value is Dictionary:
		for key in keys:
			if value.get(key, null) is bool:
				return bool(value[key])
	if value is Array:
		for key in keys:
			if value.has(key):
				return true
	return false

func _has_repeat_capability(context: Dictionary, path: String) -> bool:
	var capability: Variant = _capabilities_for(context, path)
	if capability is Dictionary:
		for key in ["repeat_hit", "area", "orbit", "periodic", "repeated_damage"]:
			if capability.get(key, false) == true:
				return true
	if capability is Array:
		for item in capability:
			if str(item) in ["repeat_hit", "area", "orbit", "periodic", "repeated_damage"]:
				return true
	return false

func _declares_active_shot(value: Dictionary, context: Dictionary, path: String) -> bool:
	var capability: Variant = _capabilities_for(context, path)
	if capability is Dictionary and capability.get("active", null) is bool:
		return bool(capability.active)
	return value.has("carrier") or value.has("templates")

func _tokens(pattern: String) -> Array[String]:
	var result: Array[String] = []
	for part in pattern.split("."):
		if part.ends_with("[i]"):
			result.append(part.trim_suffix("[i]"))
			result.append("[i]")
		else:
			result.append(part)
	return result

func _expand(value: Variant, tokens: Array[String], index: int, path: String, output: Array, include_containers: bool = false) -> void:
	if index >= tokens.size():
		if include_containers or not (value is Dictionary or value is Array):
			output.append({"path": path, "value": value})
		return
	var token: String = tokens[index]
	if token == "[i]":
		if value is Array:
			for item_index in range(value.size()):
				_expand(value[item_index], tokens, index + 1, path + "[%d]" % item_index, output, include_containers)
		return
	if value is Dictionary and value.has(token):
		var child: Variant = value[token]
		var child_path: String = token if path.is_empty() else path + "." + token
		_expand(child, tokens, index + 1, child_path, output, include_containers)

func _walk_unknown(value: Variant, relative: String, actual: String, cfg: Dictionary, issues: Array) -> void:
	if value is Dictionary:
		if _is_additional_allowed(relative):
			return
		var allowed: Array[String] = _allowed_children(relative)
		for key in value:
			var key_name: String = str(key)
			var child_actual: String = actual + ("." if not actual.is_empty() else "") + key_name
			if not allowed.has(key_name):
				issues.append(_issue(cfg, child_actual, "Schema 已登记字段"))
				continue
			var child_relative: String = key_name if relative.is_empty() else relative + "." + key_name
			_walk_unknown(value[key], child_relative, child_actual, cfg, issues)
	elif value is Array:
		for index in range(value.size()):
			_walk_unknown(value[index], relative + "[i]", actual + "[%d]" % index, cfg, issues)

func _allowed_children(relative: String) -> Array[String]:
	var result: Array[String] = []
	var all_paths: Array[String] = []
	for entry in _meta.leaves:
		all_paths.append(str(entry.path))
	for entry in _meta.arrays:
		all_paths.append(str(entry.path))
	for entry in _meta.objects:
		all_paths.append(str(entry.path))
	for path in all_paths:
		var prefix: String = relative
		if not prefix.is_empty() and not path.begins_with(prefix + "."):
			continue
		var rest: String = path.trim_prefix(prefix + ".") if not prefix.is_empty() else path
		var next: String = rest.get_slice(".", 0).trim_suffix("[i]")
		if not next.is_empty() and not result.has(next):
			result.append(next)
	return result

func _is_additional_allowed(relative: String) -> bool:
	for entry in _meta.objects:
		var path: String = str(entry.get("path", ""))
		if path == relative and entry.get("additional_properties", false) != false:
			return true
	return false

func _join_path(path: String) -> String:
	if path.is_empty():
		return ""
	return "." + path

func _issue(cfg: Dictionary, path: String, expected: String, tokens: Dictionary = {}) -> Dictionary:
	var has_value: bool = _has_path(cfg, path)
	var value: Variant = _get_path(cfg, path)
	return {"path": path, "actual": "未填写" if not has_value else _display(value), "expected": expected, "tokens": tokens}

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

func _display(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Array and value.is_empty():
		return "空列表"
	return str(value)

func _diagnostic(rule: Dictionary, issue: Dictionary, notices: Array[String]):
	var diagnostic = Diag.new()
	diagnostic.rule_id = str(rule.rule_id)
	diagnostic.code = str(rule.error_code)
	diagnostic.severity = SEVERITIES[str(rule.severity)]
	diagnostic.path = str(issue.path)
	diagnostic.actual = str(issue.actual)
	diagnostic.expected = str(issue.expected)
	var tokens: Dictionary = {"path": diagnostic.path, "field": diagnostic.path, "actual": diagnostic.actual, "expected": diagnostic.expected, "id": diagnostic.actual, "version": diagnostic.actual, "reason": diagnostic.expected, "range": diagnostic.expected, "allowed": diagnostic.expected, "index": diagnostic.path, "previous": diagnostic.expected, "brick": diagnostic.actual, "source": diagnostic.actual, "key": diagnostic.path, "context": str(rule.condition), "contract": str(rule.condition), "suggestion": diagnostic.expected}
	var issue_tokens: Variant = issue.get("tokens", null)
	if issue_tokens is Dictionary:
		tokens.merge(issue_tokens, true)
	var template: String = str(_messages.get(str(rule.error_code), ""))
	if template.is_empty():
		var notice: String = "缺失文案模板 %s（规则 %s）" % [str(rule.error_code), str(rule.rule_id)]
		if not notices.has(notice):
			notices.append(notice)
		diagnostic.hint = "[%s/%s] %s：%s；要求 %s（%s）" % [str(rule.rule_id), str(rule.error_code), diagnostic.path, diagnostic.actual, diagnostic.expected, notice]
		return diagnostic
	for key in tokens:
		template = template.replace("{%s}" % key, str(tokens[key]))
	if template.contains("{"):
		notices.append("文案 %s 有未解析占位符: %s" % [str(rule.error_code), template])
		template += " [文案元数据不完整]"
	diagnostic.hint = template
	return diagnostic

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
	diagnostic.expected = "提供完整参数元数据和能力上下文"
	diagnostic.hint = message
	return {"ok": false, "diagnostics": [diagnostic], "notices": [message]}
