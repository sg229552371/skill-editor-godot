class_name ModifierRules
extends "res://skill_core/validate/rules/r_types.gd"

# Reuse CSV binding, diagnostics, metadata path expansion and source-slot helpers.
const DATA_FILES: Dictionary = {
	"limits": "project_limits", "policy": "item_permission_policy", "protected": "protected_targets",
	"records": "record_fields", "contract": "validation_context_contract", "exposure": "exposed_fields_meta"
}
static var _data_cache: Dictionary = {}
var _data: Dictionary = {}
var _context_failed: bool = false
var _context_notices: Array[String] = []

func configure(metadata: Dictionary, rules_path: String = RULES_PATH, messages_path: String = MESSAGES_PATH) -> bool:
	_ready = false
	last_error = ""
	_groups.clear()
	_messages.clear()
	_data.clear()
	for key in META_REQUIRED:
		var value: Variant = metadata.get(key, null)
		if not (value is Dictionary or value is Array):
			return _fail("参数元数据缺少 %s" % key)
	_meta = metadata.duplicate(true)
	if not _meta.leaves is Array or _meta.leaves.is_empty() or not _meta.enums is Dictionary or not _meta.rule_field_aliases is Dictionary:
		return _fail("参数叶/枚举/别名元数据无效")
	for key in DATA_FILES:
		var loaded: Dictionary = _load_data(str(DATA_FILES[key]))
		if loaded.is_empty():
			return false
		_data[key] = loaded
	if not _data_valid():
		return false
	_rules = _read_csv(rules_path, ["rule_id", "condition", "severity", "field_path", "error_code"])
	if not last_error.is_empty():
		return false
	var messages: Array[Dictionary] = _read_csv(messages_path, ["code", "audience", "template", "placeholders"])
	if not last_error.is_empty():
		return false
	for row in messages:
		var code: String = str(row.code)
		if code.is_empty() or _messages.has(code):
			return _fail("文案 code 缺失或重复: %s" % code)
		_messages[code] = str(row.template)
	if not register_group(39, 69, _handlers()):
		return false
	_ready = true
	return true

func _load_data(name: String) -> Dictionary:
	if _data_cache.has(name):
		return _data_cache[name].duplicate(true)
	var file: FileAccess = FileAccess.open("res://data/" + name + ".json", FileAccess.READ)
	if file == null:
		_fail("无法读取元数据: %s" % name)
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary or parser.data.is_empty():
		_fail("元数据解析失败: %s" % name)
		return {}
	var parsed: Dictionary = parser.data
	_data_cache[name] = parsed.duplicate(true)
	return parsed

func _data_valid() -> bool:
	for pair in [["limits", "defaults"], ["limits", "hard_caps"], ["policy", "categories"],
		["policy", "permission_roles"], ["protected", "groups"], ["records", "records"],
		["contract", "context_keys"], ["contract", "failure_policy"], ["exposure", "roles"]]:
		if not _data[pair[0]].get(pair[1], null) is Dictionary or _data[pair[0]][pair[1]].is_empty():
			return _fail("元数据缺少 %s.%s" % [pair[0], pair[1]])
	if _data.protected.get("match_mode", null) != "segment":
		return _fail("受保护目标必须按路径段匹配")
	for key in ["permission", "scope", "record", "part_type"]:
		if _enum(key).is_empty():
			return _fail("枚举缺少 %s" % key)
		for value in _enum(key):
			if not _text(value):
				return _fail("枚举含非法值: %s" % key)
	for leaf in _meta.leaves:
		if not leaf is Dictionary or not _text(leaf.get("path", null)) or not _text(leaf.get("type", null)):
			return _fail("参数叶登记损坏")
	for source in ["triggers[i].on", "triggers[i].produces", "derivations[i].produces"]:
		var aliases: Variant = _meta.rule_field_aliases.get(source, null)
		if not aliases is Array or aliases.is_empty():
			return _fail("缺少 Schema 别名: %s" % source)
		for alias in aliases:
			if not _text(alias):
				return _fail("Schema 别名非法: %s" % source)
	for category in _data.policy.categories.values():
		if not category is Dictionary:
			return _fail("物品类别权限表损坏")
		for key in ["allowed", "conditional", "denied"]:
			if not category.get(key, null) is Array:
				return _fail("物品类别缺少 %s" % key)
			for permission in category[key]:
				if not _enum("permission").has(permission):
					return _fail("类别使用未登记权限")
	if _number_permission().is_empty():
		return _fail("物品权限表缺少数值修改语义角色")
	for group in _data.protected.groups.values():
		if not group is Dictionary or not group.get("rule_ids", null) is Array or not group.get("segments", null) is Array or group.segments.is_empty():
			return _fail("受保护路径组损坏")
	if not _data.protected.groups.get("source_chain", null) is Dictionary:
		return _fail("缺少来源链路径组")
	for record in _enum("record"):
		var definition: Variant = _data.records.records.get(record, null)
		if not definition is Dictionary or not definition.get("payload_roles", null) is Array:
			return _fail("缺少记录载荷: %s" % record)
	for role in ["reference", "permissions", "lower", "upper", "live", "inheritable", "note"]:
		if not _text(_data.exposure.roles.get(role, null)):
			return _fail("暴露字段缺少角色 %s" % role)
	if not _enum("permission").has(_data.exposure.get("live_permission", null)):
		return _fail("live_permission 未登记")
	for key in _data.contract.context_keys:
		var entry: Variant = _data.contract.context_keys[key]
		if not entry is Dictionary or not entry.get("consumers", null) is Array or not entry.get("required_by", null) is Array:
			return _fail("上下文契约损坏: %s" % key)
		if not ["Dictionary", "Array", "String"].has(entry.get("type", null)):
			return _fail("上下文类型未实现: %s" % key)
	return true

func validate(cfg: Dictionary, context: Dictionary) -> Dictionary:
	if not _ready:
		return _unavailable(last_error if not last_error.is_empty() else "未配置修饰器校验元数据")
	last_error = ""
	_context_failed = false
	_context_notices.clear()
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
	notices.append_array(_context_notices)
	# Unavailable analysis is not a successful warning-only validation.
	# Keep each diagnostic's CSV severity unchanged (D-27).
	return {"ok": ok and not _context_failed, "diagnostics": diagnostics, "notices": notices}

func _handlers() -> Dictionary:
	return {
		"修饰器标识缺失或重复": _modifier_ids,
		"单个修饰器声明多个权限或未知权限": _permissions,
		"水晶申请非 mutate_number 权限": _item_permissions,
		"scope 不合法或 tagged 缺少合法匹配标签": _scopes_and_tags,
		"修改目标未暴露、名称不明确或不是字段引用": _exposed_targets,
		"mutate_number 目标不存在，试图凭空添加行为": _existing_targets,
		"live 权限没有物品申请与目标 live 暴露双向许可": _live_permissions,
		"任一权限试图修改来源链、实例身份、快照或历史结果": _protected_targets,
		"修饰器试图修改 max_generation、max_chain_depth、allow_self_chain": _protected_targets,
		"暴露字段未声明上下限或上下限倒置": _exposed_bounds,
		"数值叠加类别不是 set、add、mul、clamp": _stack_categories,
		"同字段多个 set 未说明最后挂载者覆盖": _set_conflicts,
		"合并后值违反类型或积木硬范围，不能合法夹取": _merged_values,
		"inheritable 非布尔或隐式要求全部修饰继承": _inheritance,
		"派生上限非非负整数或超过项目硬上限": _generation_limit,
		"已配置派生路径必然被代数上限截断": _truncated_paths,
		"cast_budget 非正整数或缺少可解析项目默认": _cast_budget,
		"预计路径可能超过合法施放预算": _budget_estimate,
		"分裂配置允许分裂体重置 split_budget": _split_resets,
		"连锁配置要求每代重置 chain_remaining 或 visited": _chain_resets,
		"触发点标识缺失、重复或不能稳定进入来源标记": _trigger_ids,
		"被动订阅非四种结算记录，含 hit、vanish、debug_record": _trigger_records,
		"触发产出不是效果体模板或修饰器引用": _produced_types,
		"条件访问该记录没有的字段或未成立份": _condition_fields,
		"触发概率不是零到一的有限数": _trigger_chance,
		"内置冷却缺失、负数或不是整数 tick": _internal_cooldown,
		"零内置冷却缺显式说明或有效预算保障": _zero_cooldown,
		"因果深度上限缺失、非法或越过项目硬上限": _chain_depth,
		"允许自链但最坏情况说明不完整": _self_chain,
		"召唤积木缺正整数 summon_cap": _summon_cap,
		"依附、绑定、霰弹和自链布尔字段类型错误": _strict_bools
	}

func _modifier_ids(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	return _unique_ids(cfg, _items(cfg, "modifiers[i]"), "modifier_id")

func _permissions(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for hit in _items(cfg, "modifiers[i]"):
		# V-040 是权限的类型/枚举关卡：多个权限（数组）、未知权限、null 都在这里拦截。
		# 其余规则只对「已是合法权限字符串」的条目生效，不得拿非法值与字符串做比较。
		var permission: Variant = hit.value.get("permission", null) if hit.value is Dictionary else null
		if not permission is String or not _enum("permission").has(permission):
			issues.append(_issue(cfg, hit.path + ".permission", "单个已登记权限 %s" % str(_enum("permission"))))
	return issues

# 取出合法权限字符串；非字符串（数组 / null / 数字）一律返回 ""，由 V-040 负责报告。
# Godot 4 里 Variant == Variant 跨类型比较（Array vs String）会抛运行时错误，
# 被 GUT 计为 Unexpected Errors，会让整个用例红掉。
func _permission_text(hit: Dictionary) -> String:
	if not hit.value is Dictionary:
		return ""
	var permission: Variant = (hit.value as Dictionary).get("permission", null)
	return permission if permission is String else ""

func _item_permissions(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	for hit in _items(cfg, "modifiers[i]"):
		var path: String = hit.path + ".permission"
		var category: Variant = _fact(context, "item_category", rule, path, issues)
		if category == null:
			continue
		var policy: Variant = _data.policy.categories.get(category, null)
		if not policy is Dictionary:
			_context_error(issues, rule, path, "item_category", category, "未登记类别")
			continue
		var permission: String = _permission_text(hit)
		if permission.is_empty():
			continue  # 权限不是合法字符串：V-040 已报告，此处不重复判定
		if not policy.allowed.has(permission) and not policy.conditional.has(permission):
			issues.append(_issue(cfg, path, "物品类别许可 %s / 条件许可 %s" % [str(policy.allowed), str(policy.conditional)]))
	return issues

func _scopes_and_tags(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for hit in _items(cfg, "modifiers[i]"):
		if not hit.value is Dictionary:
			continue
		var scope: Variant = hit.value.get("scope", _leaf_default("modifiers[i].scope"))
		if not _enum("scope").has(scope):
			issues.append(_issue(cfg, hit.path + ".scope", "已登记作用域 %s" % str(_enum("scope"))))
		elif scope == "tagged":
			var tags: Variant = hit.value.get("tag_filter", null)
			if not tags is Array or tags.is_empty():
				issues.append(_issue(cfg, hit.path + ".tag_filter", "tagged 必须声明非空合法匹配标签"))
			else:
				for index in range(tags.size()):
					if not _text(tags[index]):
						issues.append(_issue(cfg, hit.path + ".tag_filter[%d]" % index, "非空标签字符串"))
	var meta_tags: Variant = _get_path(cfg, "meta.tags")
	if meta_tags is Array:
		for index in range(meta_tags.size()):
			if not _text(meta_tags[index]):
				issues.append(_issue(cfg, "meta.tags[%d]" % index, "非空标签字符串"))
	return issues

func _targets(hit: Dictionary) -> Array:
	var output: Array = []
	var targets: Variant = hit.value.get("targets", null) if hit.value is Dictionary else null
	if not targets is Array or targets.is_empty():
		return [{"path": hit.path + ".targets", "value": targets}]
	for index in range(targets.size()):
		output.append({"path": hit.path + ".targets[%d]" % index, "value": targets[index]})
	return output

func _reference(value: Variant) -> bool:
	if not _text(value) or value != value.strip_edges() or not value.contains("."):
		return false
	if value.contains("*") or value.contains("..") or value.contains("\n"):
		return false
	for segment in value.replace("[", ".").replace("]", "").split("."):
		if segment.is_empty():
			return false
	return true

func _exposed_targets(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	for hit in _items(cfg, "modifiers[i]" ):
		for target in _targets(hit):
			var exposed: Variant = _fact(context, "exposed", rule, target.path, issues)
			if exposed == null:
				continue
			if not _reference(target.value) or not exposed.get(target.value, null) is Dictionary:
				issues.append(_issue(cfg, target.path, "明确且已登记的字段引用"))
				continue
			var registered: Dictionary = exposed[target.value]
			var permissions: Variant = registered.get(_role("permissions"), null)
			var permission: Variant = hit.value.get("permission", null) if hit.value is Dictionary else null
			if not permissions is Array:
				_context_error(issues, rule, target.path, "exposed", registered, "登记字段缺少权限数组")
			elif not permissions.has(permission):
				issues.append(_issue(cfg, target.path, "目标必须为当前权限开放，暴露不等于任意方式可修改"))
	return issues

func _number_permission() -> String:
	# Semantic binding uses the deployed role map, not enum array order.
	for permission in _data.policy.permission_roles:
		if _data.policy.permission_roles[permission] == "只改已有数值（影响未来），不新增行为":
			return str(permission)
	return ""

func _existing_targets(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var number_permission: String = _number_permission()
	if number_permission.is_empty():
		return issues
	for hit in _items(cfg, "modifiers[i]"):
		if not hit.value is Dictionary or _permission_text(hit) != number_permission:
			continue
		for target in _targets(hit):
			var exposed: Variant = _fact(context, "exposed", rule, target.path, issues)
			if exposed == null:
				continue
			if not _reference(target.value) or not exposed.has(target.value) or not _has_path(cfg, target.value) or not _number(_get_path(cfg, target.value)):
				issues.append(_issue(cfg, target.path, "mutate_number 只能指向已存在且已暴露的有限数值字段"))
	return issues

func _live_permissions(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var live_permission: String = str(_data.exposure.live_permission)
	for hit in _items(cfg, "modifiers[i]"):
		if not hit.value is Dictionary or _permission_text(hit) != live_permission:
			continue
		var path: String = hit.path + ".permission"
		var exposed: Variant = _fact(context, "exposed", rule, path, issues)
		var requests: Variant = _fact(context, "live_requests", rule, path, issues)
		if exposed == null or requests == null:
			continue
		for request in requests:
			if not request is Dictionary or not _reference(request.get(_role("reference"), null)) or not _text(request.get("permission", null)):
				_context_error(issues, rule, path, "live_requests", request, "申请必须含字段引用与单权限")
		for target in _targets(hit):
			var registered: Variant = exposed.get(target.value, null) if target.value is String else null
			var applied: bool = false
			for request in requests:
				if request is Dictionary and request.get(_role("reference"), null) == target.value and request.get("permission", null) == live_permission:
					applied = true
			if not applied:
				issues.append(_issue(cfg, path, "物品必须逐字段申请 live 权限: %s" % str(target.value)))
			var live: Variant = registered.get(_role("live"), null) if registered is Dictionary else null
			var permissions: Variant = registered.get(_role("permissions"), null) if registered is Dictionary else null
			if not live is bool or not live or not permissions is Array or not permissions.has(live_permission):
				issues.append(_issue(cfg, _exposure_path(cfg, target.value, _role("live"), path), "目标必须显式 live=true 且开放 live 权限"))
	return issues

func _exposure_path(cfg: Dictionary, reference: Variant, field: String, fallback: String) -> String:
	for hit in _items(cfg, "exposed_fields[i]"):
		if hit.value is Dictionary and hit.value.get(_role("reference"), null) == reference:
			return hit.path + "." + field
	return fallback

func _protected_targets(cfg: Dictionary, _context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	for hit in _items(cfg, "modifiers[i]"):
		for target in _targets(hit):
			if not target.value is String:
				continue
			var segments: PackedStringArray = target.value.replace("[", ".").replace("]", "").split(".")
			for group in _data.protected.groups.values():
				if not group.rule_ids.has(rule.rule_id):
					continue
				for segment in group.segments:
					if segments.has(segment):
						issues.append(_issue(cfg, target.path, "不可修改受保护路径段 %s" % segment))
						break
	return issues

func _exposed_bounds(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for hit in _items(cfg, "exposed_fields[i]"):
		if not hit.value is Dictionary:
			continue
		var lower: String = _role("lower")
		var upper: String = _role("upper")
		var low: Variant = hit.value.get(lower, null)
		var high: Variant = hit.value.get(upper, null)
		for field in [lower, upper]:
			if not _number(hit.value.get(field, null)):
				issues.append(_issue(cfg, hit.path + "." + field, "必填有限数值上下限（不接受字符串数字）"))
		if _number(low) and _number(high) and low > high:
			issues.append(_issue(cfg, hit.path + "." + lower, "下限不能高于上限"))
	return issues

func _leaf_default(pattern: String) -> Variant:
	for leaf in _meta.leaves:
		if leaf.path == pattern:
			return leaf.get("default", null)
	return null

func _numeric_modifier(hit: Dictionary) -> bool:
	if not hit.value is Dictionary:
		return false
	var permission: String = _permission_text(hit)
	if permission.is_empty():
		return false
	return permission == _number_permission() or permission == str(_data.exposure.live_permission)

func _operation_categories() -> Dictionary:
	# These are operation implementations, not profile-reference parsing.
	return {"set": _op_set, "add": _op_add, "mul": _op_mul, "clamp": _op_clamp}

func _op_set(_base: float, operands: Array) -> float:
	return float(operands[0])

func _op_add(base: float, operands: Array) -> float:
	return base + float(operands[0])

func _op_mul(base: float, operands: Array) -> float:
	return base * float(operands[0])

func _op_clamp(base: float, operands: Array) -> float:
	return clampf(base, float(operands[0]), float(operands[1]))

func _resolved_operation(context: Dictionary, hit: Dictionary, rule: Dictionary, path: String, issues: Array) -> Variant:
	var table: Variant = _fact(context, "stack_operations", rule, path, issues, true)
	if table == null:
		return null
	var id: Variant = hit.value.get("modifier_id", null)
	var operation: Variant = table.get(id, null) if id is String else null
	if not operation is Dictionary:
		_context_error(issues, rule, path, "stack_operations", operation, "缺少 modifier_id 对应的已解析运算")
		return null
	return operation

func _stack_categories(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	for hit in _items(cfg, "modifiers[i]"):
		if not _numeric_modifier(hit):
			continue
		var path: String = hit.path + ".stack_rule"
		var operation: Variant = _resolved_operation(context, hit, rule, path, issues)
		if operation != null and not _operation_categories().has(operation.get("category", null)):
			issues.append(_issue(cfg, path, "解析后的类别必须为 %s" % str(_operation_categories().keys())))
	return issues

func _set_conflicts(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var counts: Dictionary = {}
	var fallback: Dictionary = {}
	for hit in _items(cfg, "modifiers[i]"):
		if not _numeric_modifier(hit):
			continue
		var operation: Variant = _resolved_operation(context, hit, rule, hit.path + ".stack_rule", issues)
		if operation == null:
			continue
		if not _operation_categories().has(operation.get("category", null)):
			_context_error(issues, rule, hit.path + ".stack_rule", "stack_operations", operation, "未登记运算类别")
			continue
		if operation.category == "set":
			for target in _targets(hit):
				if target.value is String:
					counts[target.value] = int(counts.get(target.value, 0)) + 1
					fallback[target.value] = target.path
	var provided: Variant = _fact(context, "set_counts", rule, "params.exposed_fields", issues)
	if provided != null:
		for reference in provided:
			if not _reference(reference) or not provided[reference] is int or provided[reference] < 0:
				_context_error(issues, rule, "params.exposed_fields", "set_counts", provided[reference], "字段引用到非负整数次数")
			else:
				counts[reference] = maxi(int(counts.get(reference, 0)), int(provided[reference]))
	for reference in counts:
		if counts[reference] <= 1:
			continue
		var path: String = _exposure_path(cfg, reference, _role("note"), str(fallback.get(reference, "params.exposed_fields")))
		if not _text(_get_path(cfg, path)):
			issues.append(_issue(cfg, path, "同字段多个 set 必须说明最后挂载者覆盖"))
	return issues

func _merged_values(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var by_target: Dictionary = {}
	for hit in _items(cfg, "modifiers[i]"):
		if not _numeric_modifier(hit):
			continue
		for target in _targets(hit):
			var operation: Variant = _resolved_operation(context, hit, rule, target.path, issues)
			var exposed: Variant = _fact(context, "exposed", rule, target.path, issues, true)
			if operation == null or exposed == null or not _reference(target.value):
				continue
			var bounds: Variant = exposed.get(target.value, null)
			if not bounds is Dictionary:
				_context_error(issues, rule, target.path, "exposed", bounds, "缺少目标字段登记")
				continue
			if not _number(bounds.get(_role("lower"), null)) or not _number(bounds.get(_role("upper"), null)) or bounds[_role("lower")] > bounds[_role("upper")]:
				_context_error(issues, rule, target.path, "exposed", bounds, "登记范围必须是有序有限上下限")
				continue
			if not _valid_operation(operation):
				_context_error(issues, rule, target.path, "stack_operations", operation, "需登记类别、有限操作数/基准/硬范围及非负整数 mount_order")
				continue
			var entries: Variant = by_target.get(target.value, null)
			if entries == null:
				entries = []
				by_target[target.value] = entries
			entries.append({"operation": operation, "path": target.path, "bounds": bounds})
	for reference in by_target:
		var entries: Array = by_target[reference]
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.operation.mount_order < b.operation.mount_order)
		var first: Dictionary = entries[0]
		var base: float = float(first.operation.base_value)
		var result: float = base
		var minimum: float = float(first.operation.hard_range.min)
		var maximum: float = float(first.operation.hard_range.max)
		var mount_orders: Dictionary = {}
		var consistent: bool = true
		for entry in entries:
			var op: Dictionary = entry.operation
			if mount_orders.has(op.mount_order) or float(op.base_value) != base:
				_context_error(issues, rule, entry.path, "stack_operations", op, "同字段须一致基准和唯一挂载顺序")
				consistent = false
			mount_orders[op.mount_order] = true
			minimum = maxf(minimum, maxf(float(op.hard_range.min), float(entry.bounds[_role("lower")])))
			maximum = minf(maximum, minf(float(op.hard_range.max), float(entry.bounds[_role("upper")])))
		if not consistent:
			continue
		for category in _operation_categories():
			var apply: Callable = _operation_categories()[category]
			for entry in entries:
				if entry.operation.category == category:
					result = apply.call(result, entry.operation.operands)
					if not is_finite(result):
						break
			if not is_finite(result):
				break
		var actual: Variant = _get_path(cfg, reference)
		var valid: bool = is_finite(result) and minimum <= maximum and result >= minimum and result <= maximum
		var leaf: Dictionary = _parameter_leaf(cfg, reference)
		var integer_field: bool = leaf.get("type", "") == "integer" or (leaf.is_empty() and actual is int)
		if integer_field and result != floor(result):
			valid = false
		if not _number(actual):
			valid = false
		if valid and not leaf.is_empty():
			var typed_result: Variant = int(result) if integer_field else result
			if not _type_or_range_error(typed_result, leaf).is_empty():
				valid = false
		if not valid:
			issues.append(_issue(cfg, first.path, "合并后须保持字段类型并落入硬范围 [%s, %s]；结果 %s" % [minimum, maximum, result]))
	return issues

func _valid_operation(operation: Dictionary) -> bool:
	if not _operation_categories().has(operation.get("category", null)) or not _number(operation.get("base_value", null)):
		return false
	if not operation.get("mount_order", null) is int or operation.mount_order < 0:
		return false
	var operands: Variant = operation.get("operands", null)
	var hard_range: Variant = operation.get("hard_range", null)
	if not operands is Array or not hard_range is Dictionary:
		return false
	var arity: int = 2 if operation.category == "clamp" else 1
	if operands.size() != arity:
		return false
	for value in operands:
		if not _number(value):
			return false
	if arity == 2 and operands[0] > operands[1]:
		return false
	return _number(hard_range.get("min", null)) and _number(hard_range.get("max", null)) and hard_range.min <= hard_range.max

func _inheritance(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for hit in _items(cfg, "modifiers[i]"):
		if hit.value is Dictionary and hit.value.has("inheritable") and not hit.value.inheritable is bool:
			issues.append(_issue(cfg, hit.path + ".inheritable", "逐修饰器显式布尔；缺省使用 Schema 默认，不允许隐式全部继承"))
	return issues

func _limit(context: Dictionary, section: String, field: String, rule: Dictionary, path: String, issues: Array) -> Variant:
	var source: Variant = _data.limits[section].get(field, null)
	if not source is Dictionary:
		_context_error(issues, rule, path, "project_limits", source, "缺少项目限值登记")
		return null
	var injected: Variant = context.get("project_limits", null)
	if context.has("project_limits") and not injected is Dictionary:
		_context_error(issues, rule, path, "project_limits", injected, "必须是 Dictionary")
		return null
	var section_values: Variant = injected.get(section, null) if injected is Dictionary else null
	if injected is Dictionary and injected.has(section) and not section_values is Dictionary:
		_context_error(issues, rule, path, "project_limits." + section, section_values, "必须是 Dictionary")
		return null
	var value: Variant = source.get("value", null)
	if section_values is Dictionary and section_values.has(field):
		value = section_values[field]
	elif source.get("_provisional", false) == true:
		_context_error(issues, rule, path, "project_limits." + section + "." + field, "未填写", "临时示例值必须由项目注入")
		return null
	if not value is int or value < 0 or (field == "cast_budget" and value == 0):
		_context_error(issues, rule, path, "project_limits." + section + "." + field, value, "合法整数限值，预算必须为正")
		return null
	return value

func _generation_limit(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _scopes(cfg):
		var path: String = scope.path + ".max_generation"
		var cap: Variant = _limit(context, "hard_caps", "max_generation", rule, path, issues)
		var value: Variant = scope.value.get("max_generation", null)
		if not scope.value.has("max_generation"):
			value = _limit(context, "defaults", "max_generation", rule, path, issues)
		if not value is int or value < 0 or (cap != null and value > cap):
			issues.append(_issue(cfg, path, "不超过项目硬上限的非负整数"))
	return issues

func _canonical_analysis_path(path: String) -> String:
	for source in _meta.rule_field_aliases:
		var source_parent: String = str(source).get_slice(".", 0).trim_suffix("[i]")
		var leaf: String = str(source).get_slice(".", 1)
		var aliases: Variant = _meta.rule_field_aliases[source]
		if aliases is Array and aliases.size() == 1 and path.contains(source_parent + "[") and path.ends_with("." + leaf):
			return path.trim_suffix(leaf) + str(aliases[0])
	return path

func _truncated_paths(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var derivations: Array = _derivations(cfg)
	if derivations.is_empty():
		return issues
	var fallback: String = derivations[0].path + "." + str(_meta.rule_field_aliases["derivations[i].produces"][0])
	var analysis: Variant = _fact(context, "derivation_analysis", rule, fallback, issues)
	if analysis == null:
		return issues
	var paths: Variant = analysis.get("truncated_paths", null)
	if not paths is Array:
		_context_error(issues, rule, fallback, "derivation_analysis", paths, "truncated_paths 必须是 Array")
		return issues
	for entry in paths:
		if not entry is Dictionary or not _text(entry.get("path", null)) or not _text(entry.get("blocked_by", null)) or not entry.get("generation", null) is int or entry.generation < 0:
			_context_error(issues, rule, fallback, "derivation_analysis", entry, "需 path/blocked_by/非负整数 generation")
			continue
		var path: String = _canonical_analysis_path(entry.path)
		if not _has_path(cfg, path):
			_context_error(issues, rule, fallback, "derivation_analysis", entry, "分析路径必须指向本 CFG 实际槽位")
			continue
		issues.append(_issue(cfg, path, "理论请求路径将在第 %d 代被 %s 截断" % [entry.generation, entry.blocked_by]))
	return issues

func _effective_budget(scope: Dictionary, context: Dictionary, rule: Dictionary, issues: Array) -> Variant:
	if scope.value.has("cast_budget"):
		return scope.value.cast_budget
	return _limit(context, "defaults", "cast_budget", rule, scope.path + ".cast_budget", issues)

func _cast_budget(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	for scope in _budget_scopes(cfg):
		var path: String = scope.path + ".cast_budget"
		var cap: Variant = _limit(context, "hard_caps", "cast_budget", rule, path, issues)
		var value: Variant = _effective_budget(scope, context, rule, issues)
		if not value is int or value <= 0 or (cap != null and value > cap):
			issues.append(_issue(cfg, path, "正整数施放预算，且不超过项目硬上限"))
	return issues

func _budget_fact(context: Dictionary, rule: Dictionary, path: String, issues: Array) -> Variant:
	var estimate: Variant = _fact(context, "budget_estimate", rule, path, issues, true)
	if estimate == null:
		return null
	if not estimate.get("total_requested_instances", null) is int or estimate.total_requested_instances < 0 or not estimate.get("capped", null) is bool or not estimate.get("guarantee_bindings", null) is Array:
		_context_error(issues, rule, path, "budget_estimate", estimate, "需理论非负整数请求数、bool capped、Array guarantee_bindings")
		return null
	return estimate

func _budget_estimate(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	if _scopes(cfg).is_empty():
		return issues
	var estimate: Variant = _budget_fact(context, rule, "params.cast_budget", issues)
	if estimate == null:
		return issues
	for scope in _budget_scopes(cfg):
		var budget: Variant = _effective_budget(scope, context, rule, issues)
		if budget is int and budget > 0 and estimate.total_requested_instances > budget:
			issues.append(_issue(cfg, scope.path + ".cast_budget", "理论请求 %d 可能超过预算 %d（不是截断后的创建数）" % [estimate.total_requested_instances, budget]))
	return issues

func _split_resets(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	return _reset_issues(cfg, context, rule, ["split_budget"], "params.split_budget")

func _chain_resets(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var fields: Array = ["chain_remaining", "visited"]
	fields.append_array(_data.protected.groups.source_chain.segments)
	return _reset_issues(cfg, context, rule, fields, "params.chain_remaining")

func _reset_issues(cfg: Dictionary, context: Dictionary, rule: Dictionary, fields: Array, fallback: String) -> Array:
	var issues: Array = []
	# Root budgets are legitimate configuration. Descendant writes are not resets of that authority.
	for scope in _scopes(cfg):
		for key in scope.value:
			var child: Variant = scope.value[key]
			if child is Dictionary or child is Array:
				_scan_reset_keys(cfg, child, scope.path + "." + str(key), fields, issues)
	var writes: Variant = _fact(context, "reset_writes", rule, fallback, issues)
	if writes == null:
		return issues
	for write in writes:
		if not write is Dictionary or not _text(write.get("path", null)) or not _text(write.get("kind", null)) or not _text(write.get("source", null)):
			_context_error(issues, rule, fallback, "reset_writes", write, "需 path/kind/source 字符串")
			continue
		if not _has_path(cfg, write.path):
			_context_error(issues, rule, fallback, "reset_writes", write, "写入证据必须定位到本 CFG 槽位")
			continue
		if fields.has(write.kind):
			issues.append(_issue(cfg, write.path, "子体不得重置 %s（来源 %s）" % [write.kind, write.source]))
	return issues

func _scan_reset_keys(cfg: Dictionary, value: Variant, path: String, fields: Array, issues: Array) -> void:
	if value is Dictionary:
		for key in value:
			var actual: String = path + "." + str(key)
			if fields.has(key) and not _registered_leaf(cfg, actual):
				issues.append(_issue(cfg, actual, "子体继承安全状态，不得重置"))
			else:
				_scan_reset_keys(cfg, value[key], actual, fields, issues)
	elif value is Array:
		for index in range(value.size()):
			_scan_reset_keys(cfg, value[index], path + "[%d]" % index, fields, issues)

func _registered_leaf(cfg: Dictionary, path: String) -> bool:
	return not _parameter_leaf(cfg, path).is_empty()

func _parameter_leaf(cfg: Dictionary, path: String) -> Dictionary:
	var relative: String = ""
	var longest: int = -1
	for scope in _scopes(cfg):
		if path.begins_with(scope.path + ".") and scope.path.length() > longest:
			relative = path.trim_prefix(scope.path + ".")
			longest = scope.path.length()
	if longest < 0:
		return {}
	var pattern: String = ""
	var in_index: bool = false
	for character in relative:
		if character == "[":
			pattern += "[i]"
			in_index = true
		elif character == "]":
			in_index = false
		elif not in_index:
			pattern += character
	for leaf in _meta.leaves:
		if leaf.path == pattern:
			return leaf
	return {}

func _budget_scopes(cfg: Dictionary) -> Array:
	var scopes: Array = _scopes(cfg)
	for hit in _items(cfg, "safety"):
		if hit.value is Dictionary:
			scopes.append(hit)
	return scopes

func _trigger_ids(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var items: Array = _triggers(cfg)
	items.append_array(_derivations(cfg))
	return _unique_ids(cfg, items, "trigger_id")

func _trigger_records(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	var field: String = str(_meta.rule_field_aliases["triggers[i].on"][0])
	for hit in _triggers(cfg):
		if not hit.value is Dictionary or not _enum("record").has(hit.value.get(field, null)):
			issues.append(_issue(cfg, hit.path + "." + field, "四种已登记结算记录 %s" % str(_enum("record"))))
	return issues

func _produced_types(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	for hit in _triggers(cfg):
		if not hit.value is Dictionary:
			continue
		for field in _meta.rule_field_aliases["triggers[i].produces"]:
			if field == "produces" and not hit.value.has(field):
				continue
			var value: Variant = hit.value.get(field, null)
			var slots: Array = []
			if field == "produces" and value is Array:
				for index in range(value.size()):
					slots.append({"path": hit.path + "." + field + "[%d]" % index, "value": value[index]})
			else:
				slots.append({"path": hit.path + "." + field, "value": value})
			for slot in slots:
				var types: Variant = _fact(context, "produced_types", rule, slot.path, issues)
				if types == null:
					continue
				if not _text(slot.value):
					issues.append(_issue(cfg, slot.path, "效果体模板或修饰器引用"))
				elif not types.has(slot.value) or not types[slot.value] is String:
					_context_error(issues, rule, slot.path, "produced_types", types.get(slot.value, null), "引用缺少解析类型")
				elif not ["effect_template", "modifier"].has(types[slot.value]):
					issues.append(_issue(cfg, slot.path, "产出必须为效果体模板或修饰器，不能直接写结算"))
	return issues

func _condition_fields(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	for hit in _triggers(cfg):
		if not hit.value is Dictionary:
			continue
		var path: String = hit.path + ".condition"
		var records: Variant = _fact(context, "record_fields", rule, path, issues)
		var registry: Variant = _fact(context, "condition_registry", rule, path, issues)
		if records == null or registry == null:
			continue
		var table: Variant = records.get("records", null)
		if not table is Dictionary:
			_context_error(issues, rule, path, "record_fields", records, "须注入 record_fields.json 的 records 结构")
			continue
		var condition_ref: Variant = hit.value.get("condition", null)
		var condition: Variant = registry.get(condition_ref, null) if condition_ref is String else null
		if not condition is Dictionary:
			_context_error(issues, rule, path, "condition_registry", condition_ref, "条件必须是已注册 ref，不执行表达式字符串")
			continue
		var accesses: Variant = condition.get("accessible_fields", null)
		var filters: Variant = condition.get("part_filters", null)
		if not accesses is Array or not filters is Array:
			_context_error(issues, rule, path, "condition_registry", condition, "需 accessible_fields/part_filters 数组")
			continue
		var record: Variant = hit.value.get("record", null)
		if not record is String or not _enum("record").has(record):
			continue # V-060 owns the invalid subscription.
		var definition: Variant = table.get(record, null)
		var deployed: Variant = _data.records.records.get(record, null)
		if not definition is Dictionary or not definition.get("payload_roles", null) is Array or not deployed is Dictionary:
			_context_error(issues, rule, path, "record_fields", definition, "缺少记录载荷声明")
			continue
		if definition.payload_roles != deployed.payload_roles:
			_context_error(issues, rule, path, "record_fields", definition, "注入载荷与部署的只读字段表不一致")
			continue
		var invalid: bool = false
		for field in accesses:
			if not field is String or not definition.payload_roles.has(field):
				invalid = true
		for part in filters:
			if not part is String or not _enum("part_type").has(part):
				invalid = true
		# A part discriminator is not evidence that any particular part succeeded.
		if accesses.has("part_type") and filters.is_empty():
			invalid = true
		if not filters.is_empty() and not definition.payload_roles.has("part_type"):
			invalid = true
		if filters.has("heal") and not accesses.has("target"):
			invalid = true
		if invalid:
			issues.append(_issue(cfg, path, "只访问该记录载荷；份级访问须有已登记份过滤，治疗还须目标身份过滤"))
	return issues

func _trigger_chance(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for hit in _triggers(cfg):
		if not hit.value is Dictionary:
			continue
		var chance: Variant = hit.value.get("chance", _leaf_default("triggers[i].chance"))
		if not _number(chance) or chance < 0 or chance > 1:
			issues.append(_issue(cfg, hit.path + ".chance", "[0, 1] 内有限数值"))
	return issues

func _internal_cooldown(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for hit in _triggers(cfg):
		var cooldown: Variant = hit.value.get("internal_cooldown_ticks", null) if hit.value is Dictionary else null
		if not cooldown is int or cooldown < 0:
			issues.append(_issue(cfg, hit.path + ".internal_cooldown_ticks", "必须显式提供非负整数 tick"))
	return issues

func _zero_cooldown(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	for hit in _triggers(cfg):
		if not hit.value is Dictionary:
			continue
		var cooldown: Variant = hit.value.get("internal_cooldown_ticks", null)
		if not cooldown is int or cooldown != 0:
			continue
		var path: String = hit.path + ".zero_cooldown_note"
		var estimate: Variant = _budget_fact(context, rule, path, issues)
		if estimate == null:
			continue
		var bound: bool = false
		for binding in estimate.guarantee_bindings:
			if not binding is Dictionary or not _text(binding.get("trigger_path", null)) or not _text(binding.get("budget_path", null)):
				_context_error(issues, rule, path, "budget_estimate.guarantee_bindings", binding, "需 trigger_path 与 budget_path 两个实际路径")
				continue
			if binding.trigger_path != hit.path:
				continue
			for scope in _budget_scopes(cfg):
				if binding.budget_path != scope.path + ".cast_budget":
					continue
				var budget: Variant = _effective_budget(scope, context, rule, issues)
				var cap: Variant = _limit(context, "hard_caps", "cast_budget", rule, path, issues)
				if budget is int and budget > 0 and cap is int and budget <= cap:
					bound = true
		# V-065 says missing explanation OR missing effective budget is invalid.
		if not _text(hit.value.get("zero_cooldown_note", null)) or not bound:
			issues.append(_issue(cfg, path, "零冷却必须同时有显式说明和确实约束本触发链的预算绑定"))
	return issues

func _chain_depth(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var depth_owners: Array = _triggers(cfg)
	depth_owners.append_array(_items(cfg, "safety"))
	for hit in depth_owners:
		var path: String = hit.path + ".max_chain_depth"
		var cap: Variant = _limit(context, "hard_caps", "max_chain_depth", rule, path, issues)
		var value: Variant = hit.value.get("max_chain_depth", null) if hit.value is Dictionary else null
		if not value is int or value < 0 or (cap != null and value > cap):
			issues.append(_issue(cfg, path, "必填非负整数因果深度，不能越过项目硬上限"))
	return issues

func _self_chain(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	for hit in _triggers(cfg):
		if not hit.value is Dictionary:
			continue
		var enabled: Variant = hit.value.get("allow_self_chain", null)
		if not hit.value.has("allow_self_chain") and hit.path.contains(".passive.triggers["):
			var passive_path: String = hit.path.get_slice(".triggers[", 0)
			enabled = _get_path(cfg, passive_path + ".allow_self_chain")
		if not enabled is bool or not enabled:
			continue
		var path: String = hit.path + ".self_chain_note"
		var evidence: Variant = _fact(context, "self_chain_evidence", rule, path, issues)
		if evidence == null:
			continue
		var complete: bool = _text(hit.value.get("self_chain_note", null))
		for key in ["depth_bound", "source_mark_bound", "cooldown_bound", "budget_bound", "worst_case_note_complete"]:
			if not evidence.get(key, null) is bool:
				_context_error(issues, rule, path, "self_chain_evidence." + key, evidence.get(key, null), "证据必须为严格 bool")
				complete = false
			elif not evidence[key]:
				complete = false
		if not complete:
			issues.append(_issue(cfg, path, "自链最坏情况必须完整覆盖深度、来源标记、冷却与预算"))
	return issues

func _summon_cap(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var scopes: Array = _scopes(cfg)
	var probes: Array = []
	for scope in scopes:
		probes.append({"path": scope.path, "value": scope.value, "cap_path": scope.path + ".summon_cap"})
		var templates: Variant = scope.value.get("templates", null)
		if templates is Array:
			for index in range(templates.size()):
				probes.append({"path": scope.path + ".templates[%d]" % index, "value": scope.value, "cap_path": scope.path + ".summon_cap"})
	for scope in probes:
		var path: String = scope.cap_path
		var normalized: Dictionary = context.duplicate(false)
		var has_table: bool = false
		for key in ["capabilities", "template_capabilities", "card_behaviors"]:
			if context.has(key):
				if not context[key] is Dictionary:
					_context_error(issues, rule, path, key, context[key], "能力表必须是 Dictionary")
				else:
					has_table = true
		if not has_table:
			_fact(context, "capabilities", rule, path, issues)
			continue
		# The alternative tables are the T-011 contract, not extra CFG switches.
		if not normalized.get("capabilities", null) is Dictionary:
			normalized["capabilities"] = {}
		if _fact(normalized, "capabilities", rule, path, issues) == null:
			continue
		var capability: Variant = _capabilities_for(context, scope.path)
		var summon: bool = false
		if capability is Dictionary:
			var value: Variant = capability.get("summon", null)
			if not value is bool:
				_context_error(issues, rule, path, "capabilities", capability, "召唤能力须有明确 bool summon")
				continue
			summon = value
		elif capability is Array:
			var valid: bool = true
			for item in capability:
				if not item is String:
					valid = false
			if not valid:
				_context_error(issues, rule, path, "capabilities", capability, "能力数组只能包含字符串")
				continue
			summon = capability.has("summon")
		else:
			_context_error(issues, rule, path, "capabilities", capability, "缺少本路径可解析的能力事实")
			continue
		if summon or scope.value.has("summon_cap"):
			var cap: Variant = scope.value.get("summon_cap", null)
			if not cap is int or cap <= 0:
				issues.append(_issue(cfg, path, "召唤能力必须配置正整数 summon_cap"))
	return issues

func _strict_bools(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	# Select every registered occurrence, including templates and passive wrappers.
	var fields: Array = ["attach_to_caster", "bind_owner", "shotgun_allowed", "allow_self_chain"]
	for entry in _meta.leaves:
		var pattern: String = str(entry.path)
		if not fields.has(pattern.get_slice(".", pattern.get_slice_count(".") - 1)):
			continue
		for hit in _items(cfg, pattern):
			if not hit.value is bool:
				issues.append(_issue(cfg, hit.path, "严格 bool，不接受数字或字符串布尔"))
	return issues

func _unique_ids(cfg: Dictionary, items: Array, field: String) -> Array:
	var issues: Array = []
	var seen: Dictionary = {}
	for hit in items:
		var value: Variant = hit.value.get(field, null) if hit.value is Dictionary else null
		if not _text(value) or seen.has(value):
			issues.append(_issue(cfg, hit.path + "." + field, "非空且唯一、可稳定保存的标识"))
		elif value.strip_edges() != value or value.contains("\n") or value.contains("\r") or value.contains(String.chr(0)):
			issues.append(_issue(cfg, hit.path + "." + field, "标识不得含边缘空白、换行或 NUL"))
		else:
			seen[value] = true
	return issues

func _items(cfg: Dictionary, pattern: String) -> Array:
	var output: Array = []
	for scope in _scopes(cfg):
		var matches: Array = []
		_expand(scope.value, _tokens(pattern), 0, "", matches, true)
		for hit in matches:
			output.append({"path": scope.path + "." + str(hit.path), "value": hit.value})
	return output

func _triggers(cfg: Dictionary) -> Array:
	var items: Array = _items(cfg, "triggers[i]")
	items.append_array(_items(cfg, "passive.triggers[i]"))
	return items

func _derivations(cfg: Dictionary) -> Array:
	var items: Array = _items(cfg, "derivations[i]")
	items.append_array(_items(cfg, "templates[i].derivations[i]"))
	return items

func _issue(cfg: Dictionary, path: String, expected: String, tokens: Dictionary = {}) -> Dictionary:
	var issue: Dictionary = super._issue(cfg, path, expected, tokens)
	var parent_path: String = path
	var owner: Variant = null
	while parent_path.contains("."):
		parent_path = parent_path.rsplit(".", true, 1)[0]
		var candidate: Variant = _get_path(cfg, parent_path)
		if candidate is Dictionary and (candidate.has("modifier_id") or candidate.has("trigger_id")):
			owner = candidate
			break
	var replacements: Dictionary = {
		"modifier": path, "permission": issue.actual, "constraint": expected, "scope": issue.actual,
		"target": issue.actual, "missing": expected, "detail": expected, "requested": expected,
		"limit": expected, "budget": expected, "trigger": path, "record": issue.actual, "exception": expected
	}
	if owner is Dictionary:
		replacements["modifier"] = _display(owner.get("modifier_id", null))
		replacements["permission"] = _display(owner.get("permission", null))
		replacements["scope"] = _display(owner.get("scope", null))
		replacements["trigger"] = _display(owner.get("trigger_id", null))
		replacements["record"] = _display(owner.get("record", null))
	replacements.merge(tokens, true)
	issue["tokens"] = replacements
	return issue

func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _role(name: String) -> String:
	return str(_data.exposure.roles[name])

func _context_error(issues: Array, rule: Dictionary, path: String, key: String, actual: Variant, reason: String) -> void:
	var message: String = "%s：上下文 %s 不可用（%s）；实际 %s" % [rule.rule_id, key, reason, _display(actual)]
	last_error = message if last_error.is_empty() else last_error + "\n" + message
	_context_failed = true
	issues.append({"path": path, "actual": _display(actual), "expected": message,
		"tokens": {"modifier": path, "permission": _display(actual), "constraint": message, "scope": _display(actual),
			"target": path, "missing": message, "detail": message, "requested": _display(actual), "limit": reason,
			"budget": key, "trigger": path, "record": key, "exception": message}})

func _fact(context: Dictionary, key: String, rule: Dictionary, path: String, issues: Array, needed: bool = false) -> Variant:
	var contract: Variant = _data.contract.context_keys.get(key, null)
	if not contract is Dictionary or not contract.consumers.has(rule.rule_id):
		_context_error(issues, rule, path, key, null, "未登记消费者")
		return null
	if not context.has(key):
		if needed or contract.required_by.has(rule.rule_id):
			_context_error(issues, rule, path, key, "未填写", "缺少必需事实")
		else:
			var notice: String = "%s：可选上下文 %s 缺省，该子检查未执行" % [rule.rule_id, key]
			if not _context_notices.has(notice):
				_context_notices.append(notice)
		return null
	var value: Variant = context[key]
	var valid: bool = (contract.type == "Dictionary" and value is Dictionary) or (contract.type == "Array" and value is Array) or (contract.type == "String" and value is String)
	if not valid:
		_context_error(issues, rule, path, key, value, "要求 " + str(contract.type))
		return null
	return value
