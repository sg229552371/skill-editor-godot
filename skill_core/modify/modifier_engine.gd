class_name ModifierEngine
extends RefCounted

const Diag = preload("res://skill_core/api/diagnostic.gd")
const Registry = preload("res://skill_core/resolve/exposed_fields.gd")
const POLICY_PATH: String = "res://data/modifier_meta.json"
const EXPOSURE_PATH: String = "res://data/exposed_fields_meta.json"
const RULES_PATH: String = "res://data/validation_rules.csv"
const MESSAGES_PATH: String = "res://data/error_messages.csv"
const RULE_IDS: Array[String] = ["V-019", "V-020", "V-039", "V-040", "V-041", "V-042", "V-043", "V-044", "V-045", "V-046", "V-047", "V-049", "V-051", "V-052"]
static var _json_cache: Dictionary = {}

var last_error: String = ""
var _ready: bool = false
var _policy: Dictionary = {}
var _exposure: Dictionary = {}
var _rules: Dictionary = {}
var _messages: Dictionary = {}
var _registry = Registry.new()

func configure_from_file(policy_path: String = POLICY_PATH, exposure_path: String = EXPOSURE_PATH) -> bool:
	_ready = false
	last_error = ""
	var policy: Variant = _load_json(policy_path)
	if not policy is Dictionary:
		return false
	var exposure: Variant = _load_json(exposure_path)
	if not exposure is Dictionary:
		return false
	return configure(policy, exposure)

# 只接受显式策略/暴露元数据注入；没有内置权限表，也不解析 md/yaml。
# messages == null 读取部署 CSV，{} 则显式测试缺文案回退。
func configure(policy: Dictionary, exposure: Dictionary, messages: Variant = null) -> bool:
	_ready = false
	last_error = ""
	_policy = policy.duplicate(true)
	_exposure = exposure.duplicate(true)
	_rules.clear()
	_messages.clear()
	if not _load_tables(messages):
		return false
	if not _registry.configure(_exposure, _messages):
		return _fail(_registry.last_error)
	if not _validate_policy():
		return false
	_ready = true
	return true

# cfg 是同一目标技能的装配 CFG；values 是 T-030 的 resolved 或实例当前值。
# context（不落盘）：source_kind 必填；registered_tags 为合法标签登记表；
# live=true 表示申请修改现存实例；inherit_all=true 一律拒绝，不能自动复制全部修饰。
# 本入口只授权，不求值 stack_rule，不把运行态写回 CFG。
func authorize(cfg: Dictionary, values: Dictionary, context: Dictionary = {}) -> Dictionary:
	if not _ready:
		return _unavailable(last_error if not last_error.is_empty() else "尚未配置修饰器元数据")
	last_error = ""
	var result: Dictionary = _new_result()
	if not _check_context(result, context):
		return result
	var registration: Dictionary = _registry.register_fields(cfg)
	_merge_registration(result, registration)
	if not registration.ok:
		return result
	var lookup: Dictionary = _lookup(cfg, _policy.input_path)
	if not lookup.exists:
		return result
	var modifiers: Variant = lookup.value
	if not modifiers is Array:
		_emit(result, "V-020", _policy.input_path, _display(modifiers), "修饰器数组")
		return result
	var seen: Dictionary = {}
	var counts: Dictionary = {}
	for index in range(modifiers.size()):
		var path: String = "%s[%d]" % [_policy.input_path, index]
		var modifier: Variant = modifiers[index]
		if not modifier is Dictionary:
			_emit(result, "V-020", path, _display(modifier), "修饰器对象")
			continue
		_authorize_one(result, cfg, values, modifier, path, context, registration, seen, counts)
	if not counts.is_empty():
		# V-050 仍由 T-032 登记器检查，不复制暴露登记或警告逻辑。
		var with_counts: Dictionary = _registry.register_fields(cfg, {"set_counts": counts})
		_merge_registration(result, with_counts)
	return _finish(result)

# changes 是可信运算层提供的最终数值候选 {field_path: value}，不是可执行表达式。
# T-034 负责 set/add/mul/clamp 求值；此处只做 live 授权、现有类型/暴露范围检查和原子复制。
# 返回 values 是独立副本；失败不发布部分副本，调用方不得据此修改 CFG。
func apply_live(cfg: Dictionary, instance: Dictionary, changes: Dictionary, context: Dictionary = {}) -> Dictionary:
	var live_context: Dictionary = context.duplicate(true)
	live_context.live = true
	var result: Dictionary = authorize(cfg, instance, live_context)
	result.values = {}
	result.applied = []
	if not result.ok:
		return result
	if changes.is_empty():
		_emit(result, "V-043", _policy.input_path, "空修改集合", "至少一个已授权 live 数值目标")
		return _finish(result)
	var registration: Dictionary = _registry.register_fields(cfg)
	var roles: Dictionary = _exposure.roles
	var authorized: Dictionary = {}
	for entry in result.approved:
		authorized[entry.target] = entry
	var candidates: Dictionary = {}
	for target in changes:
		if not target is String or not authorized.has(target):
			var rule: String = _protected_rule(target) if target is String else ""
			_emit(result, rule if not rule.is_empty() else "V-043", "live_changes[\"%s\"]" % str(target), str(target), "只能提交本批已授权的 live 目标")
			continue
		var entry: Dictionary = authorized[target]
		var value: Variant = changes[target]
		var current: Variant = _lookup(instance, target).value
		var exposed: Dictionary = registration.fields[target]
		var path: String = entry.target_path
		if not _finite_number(value):
			_emit(result, "V-051", path, _display(value), "live 候选必须是有限数值，不能注入行为/对象")
			continue
		if current is int and value is float:
			# GDScript int 的表示边界，不是技能策略范围；先检查再转换，避免溢出。
			if value < -9223372036854775808.0 or value >= 9223372036854775808.0 or value != floor(value):
				_emit(result, "V-051", path, _display(value), "保留现有 int64 类型，不截断小数或溢出")
				continue
		if value < exposed[roles.lower] or value > exposed[roles.upper]:
			_emit(result, "V-051", path, _display(value), "必须位于暴露范围 [%s, %s]" % [str(exposed[roles.lower]), str(exposed[roles.upper])])
			continue
		candidates[target] = int(value) if current is int else float(value)
	if not result.ok:
		return _finish(result)
	var updated: Dictionary = instance.duplicate(true)
	for target in candidates:
		_set_existing(updated, target, candidates[target])
	result.values = updated
	result.applied = candidates.keys()
	return result

func _set_existing(root: Dictionary, path: String, value: Variant) -> void:
	var tokens: Array = _path_tokens(path)
	var current: Variant = root
	for index in range(tokens.size() - 1):
		current = current[tokens[index]]
	current[tokens[tokens.size() - 1]] = value

func _authorize_one(result: Dictionary, cfg: Dictionary, values: Dictionary, modifier: Dictionary, path: String, context: Dictionary, registration: Dictionary, seen: Dictionary, counts: Dictionary) -> void:
	var fields: Dictionary = _policy.fields
	var roles: Dictionary = _exposure.roles
	var start: int = result.diagnostics.size()
	var identifier: Variant = modifier.get(fields.id, null)
	if not identifier is String or not identifier.is_valid_identifier() or seen.has(identifier):
		_emit(result, "V-039", path + "." + fields.id, _slot(modifier, fields.id), "唯一标识")
	else:
		seen[identifier] = true
	# 权限字段可能被作者填成数组 / 数字 / null。V-040 负责拦截；
	# 其余判定一律吃 permission_text（非合法权限字符串即为空），
	# 不得拿原值与字符串做 ==/!= —— Godot 4 跨类型 Variant 比较会抛运行时错误。
	var permission: Variant = modifier.get(fields.permission, null)
	var permission_text: String = permission if permission is String else ""
	if permission_text.is_empty() or not _exposure.permissions.has(permission_text):
		_emit(result, "V-040", path + "." + fields.permission, _slot(modifier, fields.permission), "单个已登记权限")
	elif not _policy.source_permissions[context.source_kind].has(permission_text):
		_emit(result, "V-041", path + "." + fields.permission, permission_text, "来源 %s 只可申请 %s" % [context.source_kind, str(_policy.source_permissions[context.source_kind])])
	var live_permission: String = str(_policy.permission_roles.live)
	var behavior_permission: String = str(_policy.permission_roles.behavior)
	var live_request: bool = context.get("live", false)
	if live_request and permission_text != live_permission:
		_emit(result, "V-045", path + "." + fields.permission, _slot(modifier, fields.permission), "物品必须显式申请 %s" % _policy.permission_roles.live)
	var inheritable: Variant = modifier.get(fields.inheritable, null)
	if not inheritable is bool or context.get("inherit_all", false):
		_emit(result, "V-052", path + "." + fields.inheritable, _slot(modifier, fields.inheritable), "显式布尔；不得要求全部修饰自动继承")
	_check_scope(result, cfg, modifier, path, context)
	var allowed_fields: Array = []
	for role in ["id", "permission", "scope", "inheritable", "targets", "stack", "tags", "profile"]:
		allowed_fields.append(fields[role])
	for key in modifier:
		if not allowed_fields.has(key):
			_emit(result, "V-019", path + "." + str(key), _display(modifier[key]), "已登记的修饰器字段")
	var operation: Dictionary = _operation(result, modifier, path)
	var targets: Variant = modifier.get(fields.targets, null)
	if not targets is Array or targets.is_empty():
		_emit(result, "V-043", path + "." + fields.targets, _slot(modifier, fields.targets), "非空字段引用数组")
		return
	var unique_targets: Dictionary = {}
	for index in range(targets.size()):
		var target: Variant = targets[index]
		var target_path: String = "%s.%s[%d]" % [path, fields.targets, index]
		if not target is String or _path_tokens(target).is_empty() or unique_targets.has(target):
			_emit(result, "V-043", target_path, _display(target), "唯一、明确的字段引用")
			continue
		unique_targets[target] = true
		var protected_rule: String = _protected_rule(target)
		if not protected_rule.is_empty():
			_emit(result, protected_rule, target_path, target, "任一权限不得修改受保护字段及其子字段")
			continue
		if not registration.fields.has(target):
			_emit(result, "V-043", target_path, target, "目标必须显式暴露")
			continue
		var exposed: Dictionary = registration.fields[target]
		var source: Dictionary = registration.sources[target]
		if live_request or permission_text == live_permission:
			if not exposed[roles.permissions].has(_policy.permission_roles.live):
				_emit(result, "V-045", source.slots[roles.permissions], _display(exposed[roles.permissions]), "目标必须开放 %s" % _policy.permission_roles.live)
			if not exposed[roles.live]:
				_emit(result, "V-045", source.slots[roles.live], _display(exposed[roles.live]), "目标 live 暴露必须为 true")
		elif not permission_text.is_empty() and not exposed[roles.permissions].has(permission_text):
			_emit(result, "V-043", target_path, _display(permission_text), "目标未开放申请的确切权限；三档互不包含")
		var value: Dictionary = _lookup(values, target)
		if permission_text == behavior_permission:
			if value.exists and value.value != null:
				_emit(result, "V-043", target_path, target, "新增行为不能覆盖既有内容或改变结算顺序")
			if not operation.is_empty() and operation.kind != "behavior":
				_emit(result, "V-043", target_path, str(operation.kind), "新增行为必须使用行为配置，不替代数值或 live 权限")
		else:
			if not value.exists or not _finite_number(value.value):
				_emit(result, "V-044", target_path, _display(value.value), "数值/live 目标必须是已有有限数值，不得凭空增加行为")
			if not operation.is_empty() and operation.kind != "number":
				_emit(result, "V-045" if live_request or permission_text == live_permission else "V-044", target_path, str(operation.kind), "数值/live 权限不增加行为，不改历史或结算顺序")
	if result.diagnostics.size() != start:
		return
	for target in targets:
		result.approved.append({"target": target, "permission": permission, "input_path": path, "target_path": "%s.%s[%d]" % [path, fields.targets, targets.find(target)], "inheritable": inheritable, "operation_profile": operation.profile})
		if operation.is_set:
			counts[target] = int(counts.get(target, 0)) + 1

func _check_scope(result: Dictionary, cfg: Dictionary, modifier: Dictionary, path: String, context: Dictionary) -> void:
	var fields: Dictionary = _policy.fields
	var scope: Variant = modifier.get(fields.scope, null)
	var slot: String = path + "." + fields.scope
	if not scope is String or not _policy.scope_roles.values().has(scope):
		_emit(result, "V-042", slot, _slot(modifier, fields.scope), "已登记作用域")
		return
	if scope != _policy.scope_roles.tagged:
		return
	var filter: Variant = modifier.get(fields.tags, null)
	var tags: Variant = _lookup(cfg, _policy.tags_path).value
	var registered: Variant = context.get("registered_tags", null)
	if not filter is Array or filter.is_empty() or not tags is Array or not registered is Array or registered.is_empty():
		_emit(result, "V-042", slot, _display(filter), "tagged 必须有合法标签登记及匹配目标标签")
		return
	var matched: bool = false
	var valid: bool = true
	var seen: Dictionary = {}
	for tag in filter:
		if not tag is String or tag.strip_edges().is_empty() or not registered.has(tag) or seen.has(tag):
			valid = false
		else:
			seen[tag] = true
			if tags.has(tag):
				matched = true
	for index in range(tags.size()):
		if not tags[index] is String or not registered.has(tags[index]):
			_emit(result, "V-042", "%s[%d]" % [_policy.tags_path, index], _display(tags[index]), "已登记的作用域标签")
	if not valid or not matched:
		_emit(result, "V-042", slot, _display(filter), "合法且至少匹配一个目标标签")

func _operation(result: Dictionary, modifier: Dictionary, path: String) -> Dictionary:
	var fields: Dictionary = _policy.fields
	var stack: Variant = modifier.get(fields.stack, null)
	var slot: String = path + "." + fields.stack
	if not stack is Dictionary:
		_emit(result, "V-049", slot, _slot(modifier, fields.stack), "含已登记 operation_profile 的对象")
		return {}
	var profile: Variant = stack.get(fields.profile, null)
	if not profile is String or not _policy.operations.has(profile):
		_emit(result, "V-049", slot + "." + fields.profile, _slot(stack, fields.profile), "已登记运算引用；不得执行字符串表达式")
		return {}
	if modifier.has(fields.profile) and modifier[fields.profile] != profile:
		# TODO(U-T033-01): 两处 profile 的组合映射未提供，较严口径拒绝歧义。
		_emit(result, "V-049", path + "." + fields.profile, _display(modifier[fields.profile]), "与 stack_rule 引用一致，或补齐已审核组合映射")
	for key in stack:
		if key not in [fields.profile, fields.operands, fields.note]:
			_emit(result, "V-019", slot + "." + str(key), _display(stack[key]), "已登记 stack_rule 字段")
	if stack.has(fields.operands) and not stack[fields.operands] is Array:
		_emit(result, "V-020", slot + "." + fields.operands, _display(stack[fields.operands]), "array")
	if stack.has(fields.note) and not stack[fields.note] is String:
		_emit(result, "V-020", slot + "." + fields.note, _display(stack[fields.note]), "string")
	var operation: Dictionary = _policy.operations[profile].duplicate(true)
	operation.profile = profile
	return operation

func _check_context(result: Dictionary, context: Dictionary) -> bool:
	for key in context:
		if key not in ["source_kind", "registered_tags", "live", "inherit_all"]:
			_merge_failure(result, "未登记修饰器上下文键: %s" % str(key))
			return false
	var source: Variant = context.get("source_kind", null)
	if not source is String or not _policy.source_permissions.has(source):
		_merge_failure(result, "缺少已登记 source_kind，不能猜测物品来源")
		return false
	for key in ["live", "inherit_all"]:
		if context.has(key) and not context[key] is bool:
			_merge_failure(result, "%s 必须是 bool" % key)
			return false
	if context.has("registered_tags") and not context.registered_tags is Array:
		_merge_failure(result, "registered_tags 必须是 Array")
		return false
	return true

func _protected_rule(path: String) -> String:
	var tokens: Array = _path_tokens(path)
	for rule in _policy.protected_segments:
		for token in tokens:
			if _policy.protected_segments[rule].has(token):
				return rule
	return ""

func _path_tokens(path: String) -> Array:
	var tokens: Array = []
	for segment in path.split("."):
		var bracket: int = segment.find("[")
		var name_part: String = segment if bracket < 0 else segment.substr(0, bracket)
		if not name_part.is_valid_identifier():
			return []
		tokens.append(name_part)
		if bracket < 0:
			continue
		var rest: String = segment.substr(bracket)
		while not rest.is_empty():
			if not rest.begins_with("["):
				return []
			var end: int = rest.find("]")
			if end < 0:
				return []
			var number: String = rest.substr(1, end - 1)
			if not number.is_valid_int() or int(number) < 0 or str(int(number)) != number:
				return []
			tokens.append(int(number))
			rest = rest.substr(end + 1)
	return tokens

func _lookup(root: Dictionary, path: String) -> Dictionary:
	var tokens: Array = _path_tokens(path)
	if tokens.is_empty():
		return {"exists": false, "value": null}
	var current: Variant = root
	for token in tokens:
		if token is String and current is Dictionary and current.has(token):
			current = current[token]
		elif token is int and current is Array and token < current.size():
			current = current[token]
		else:
			return {"exists": false, "value": null}
	return {"exists": true, "value": current}

func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _validate_policy() -> bool:
	for key in ["input_path", "tags_path"]:
		var path: Variant = _policy.get(key, null)
		if not path is String or _path_tokens(path).is_empty():
			return _fail("缺少合法策略路径: %s" % key)
	for key in ["fields", "permission_roles", "scope_roles", "source_permissions", "protected_segments", "operations"]:
		var table: Variant = _policy.get(key, null)
		if not table is Dictionary or table.is_empty():
			return _fail("缺少非空策略表: %s" % key)
	if _policy.permission_roles.size() != 3 or _exposure.permissions.size() != 3:
		return _fail("三档权限角色必须完整且无未实现的附加角色")
	if _policy.scope_roles.size() != 2:
		return _fail("作用域角色只能包含已实现的 own / tagged 角色")
	var names: Dictionary = {}
	for role in ["id", "permission", "scope", "inheritable", "targets", "stack", "tags", "profile", "operands", "note"]:
		var field: Variant = _policy.fields.get(role, null)
		if not field is String or not field.is_valid_identifier() or names.has(field):
			return _fail("字段角色缺失、非法或重复: %s" % role)
		names[field] = true
	names.clear()
	for role in ["number", "behavior", "live"]:
		var permission: Variant = _policy.permission_roles.get(role, null)
		if not permission is String or not _exposure.permissions.has(permission) or names.has(permission):
			return _fail("权限角色必须独立引用暴露权限枚举: %s" % role)
		names[permission] = true
	if _policy.permission_roles.live != _exposure.live_permission:
		return _fail("live 角色必须与暴露元数据一致")
	names.clear()
	for role in ["own", "tagged"]:
		var scope: Variant = _policy.scope_roles.get(role, null)
		if not scope is String or scope.is_empty() or names.has(scope):
			return _fail("scope 角色缺失或重复: %s" % role)
		names[scope] = true
	for source in _policy.source_permissions:
		var permissions: Variant = _policy.source_permissions[source]
		if not source is String or source.is_empty() or not permissions is Array or permissions.is_empty():
			return _fail("来源权限表无效")
		for permission in permissions:
			if not _exposure.permissions.has(permission):
				return _fail("来源引用未知权限")
	for rule in ["V-046", "V-047"]:
		var segments: Variant = _policy.protected_segments.get(rule, null)
		if not segments is Array or segments.is_empty():
			return _fail("受保护字段表缺失: %s" % rule)
		for segment in segments:
			if not segment is String or not segment.is_valid_identifier():
				return _fail("受保护字段必须是明确路径段")
	for rule in _policy.protected_segments:
		if rule not in ["V-046", "V-047"]:
			return _fail("受保护字段表引用未知规则")
	for profile in _policy.operations:
		var operation: Variant = _policy.operations[profile]
		if not profile is String or profile.is_empty() or not operation is Dictionary:
			return _fail("运算登记无效")
		if operation.get("kind", null) not in ["number", "behavior"] or not operation.get("is_set", null) is bool:
			return _fail("运算登记必须显式提供 kind / is_set")
		if operation.kind == "behavior" and operation.is_set:
			return _fail("新增行为不能冒充数值 set")
	return true

func _load_json(path: String) -> Variant:
	if not path.begins_with("res://data/") or path.contains(".."):
		_fail("元数据只能从 res://data/ 载入: %s" % path)
		return null
	var cached: Variant = _json_cache.get(path, null)
	if cached != null:
		return cached.duplicate(true)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("无法读取修饰器元数据: %s" % path)
		return null
	var parser: JSON = JSON.new()
	var error: Error = parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary:
		_fail("修饰器元数据 JSON 无效: %s；%s" % [path, parser.get_error_message()])
		return null
	var data: Dictionary = parser.data
	_json_cache[path] = data.duplicate(true)
	return data

func _load_tables(messages: Variant) -> bool:
	var rows: Array = _csv_rows(RULES_PATH, ["rule_id", "error_code", "severity"])
	if not last_error.is_empty():
		return false
	# 复核方修正：Diagnostic 没有 SEV_INFO，第三档是 SEV_HINT（见 skill_core/api/diagnostic.gd:2-5）
	var severities: Dictionary = {"阻止保存": Diag.SEV_BLOCK, "警告": Diag.SEV_WARN, "提示": Diag.SEV_HINT}
	for row in rows:
		if not RULE_IDS.has(row.rule_id):
			continue
		if _rules.has(row.rule_id) or not severities.has(row.severity):
			return _fail("规则重复或严重度未知: %s" % row.rule_id)
		# 本卡所检查规则均为阻止保存；素材损坏不能把硬门禁降级。
		if severities[row.severity] != Diag.SEV_BLOCK:
			return _fail("阻止保存规则严重度被降级: %s" % row.rule_id)
		_rules[row.rule_id] = {"code": row.error_code, "severity": severities[row.severity]}
	for rule in RULE_IDS:
		if not _rules.has(rule):
			return _fail("缺少规则素材: %s" % rule)
	if messages == null:
		rows = _csv_rows(MESSAGES_PATH, ["code", "template"])
		if not last_error.is_empty():
			return false
		for row in rows:
			if row.code.is_empty() or _messages.has(row.code):
				return _fail("文案 code 缺失或重复")
			_messages[row.code] = row.template
	elif messages is Dictionary:
		for code in messages:
			if not code is String or not messages[code] is String:
				return _fail("文案必须为 code -> template 字符串表")
		_messages = messages.duplicate(true)
	else:
		return _fail("文案注入必须为 Dictionary")
	return true

func _csv_rows(path: String, required: Array) -> Array:
	var rows: Array = []
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("无法读取部署 CSV: %s" % path)
		return rows
	var header: PackedStringArray = file.get_csv_line()
	if not header.is_empty():
		header[0] = header[0].trim_prefix("﻿")
	for column in required:
		if not header.has(column):
			_fail("CSV 缺少列: %s / %s" % [path, column])
			file.close()
			return []
	while not file.eof_reached():
		var line: PackedStringArray = file.get_csv_line()
		if line.size() == 1 and line[0].is_empty():
			continue
		if line.size() != header.size():
			_fail("CSV 列数错误: %s" % path)
			file.close()
			return []
		var row: Dictionary = {}
		for index in range(header.size()):
			row[header[index]] = line[index]
		rows.append(row)
	file.close()
	if rows.is_empty():
		_fail("CSV 为空: %s" % path)
	return rows

func _emit(result: Dictionary, rule_id: String, path: String, actual: String, expected: String) -> void:
	var rule: Dictionary = _rules[rule_id]
	var diagnostic = Diag.new()
	diagnostic.rule_id = rule_id
	diagnostic.code = rule.code
	diagnostic.severity = rule.severity
	diagnostic.path = path
	diagnostic.actual = actual
	diagnostic.expected = expected
	var template: String = _messages.get(rule.code, "")
	var tokens: Dictionary = {"field": path, "path": path, "actual": actual, "expected": expected, "modifier": path, "permission": actual, "constraint": expected, "scope": actual, "reason": expected, "target": actual, "missing": expected, "source": "修饰器", "contract": rule_id + ": " + expected, "detail": expected, "version": "0.1", "key": path, "id": actual, "conflict": expected}
	if template.is_empty():
		var notice: String = "缺失文案模板 %s（规则 %s）" % [rule.code, rule_id]
		if not result.notices.has(notice):
			result.notices.append(notice)
		template = "[%s/%s] %s：%s；要求 %s（%s）" % [rule_id, rule.code, path, actual, expected, notice]
	else:
		for token in tokens:
			template = template.replace("{%s}" % token, str(tokens[token]))
		if template.contains("{"):
			result.notices.append("文案 %s 有未解析占位符: %s" % [rule.code, template])
			template += " [文案元数据不完整]"
	diagnostic.hint = template
	result.diagnostics.append(diagnostic)
	if diagnostic.severity == Diag.SEV_BLOCK:
		result.ok = false

func _merge_registration(result: Dictionary, registration: Dictionary) -> void:
	result.diagnostics.append_array(registration.diagnostics)
	for notice in registration.notices:
		if not result.notices.has(notice):
			result.notices.append(notice)
	if not registration.ok:
		result.ok = false

func _new_result() -> Dictionary:
	return {"ok": true, "approved": [], "diagnostics": [], "notices": []}

func _finish(result: Dictionary) -> Dictionary:
	if not result.ok:
		result.approved = []
	return result

func _slot(object: Dictionary, key: String) -> String:
	return _display(object[key]) if object.has(key) else "未填写"

func _display(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Array and value.is_empty():
		return "空列表"
	return "%s (%s)" % [str(value), type_string(typeof(value))]

func _unavailable(message: String) -> Dictionary:
	last_error = message
	var diagnostic = Diag.new()
	diagnostic.rule_id = "MODIFIER_SETUP"
	diagnostic.code = "VALIDATION_METADATA_UNAVAILABLE"
	diagnostic.severity = Diag.SEV_BLOCK
	diagnostic.path = "validation_context"
	diagnostic.actual = message
	diagnostic.expected = "完整、已审核的修饰器与暴露元数据"
	diagnostic.hint = message
	return {"ok": false, "approved": [], "diagnostics": [diagnostic], "notices": [message]}

func _merge_failure(result: Dictionary, message: String) -> void:
	var failure: Dictionary = _unavailable(message)
	result.ok = false
	result.diagnostics.append_array(failure.diagnostics)
	result.notices.append_array(failure.notices)

func _fail(message: String) -> bool:
	last_error = message
	return false
