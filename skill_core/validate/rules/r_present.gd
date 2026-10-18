class_name PresentationRules
extends "res://skill_core/validate/rules/r_types.gd"

const CONTRACT_PATH := "res://data/validation_context_contract.json"
static var _contract_cache: Dictionary = {}
var _contract: Dictionary = {}
var _failed: bool = false
var _notices: Array[String] = []

func configure(metadata: Dictionary, rules_path: String = RULES_PATH, messages_path: String = MESSAGES_PATH) -> bool:
	_ready = false
	last_error = ""
	_groups.clear()
	_rules.clear()
	_messages.clear()
	for key in ["leaves", "arrays", "objects", "required_sections", "section_enable", "section_field_index", "enabled_requires", "enabled_minimum_overrides", "trail_carrier_policy", "damage_number_policy", "subscription_fields", "forbidden_subscription_values", "natural_reason_keys", "logic_writeback", "runtime_hints", "rule_field_aliases"]:
		var value: Variant = metadata.get(key, null)
		if not (value is Array or value is Dictionary) or value.is_empty():
			return _fail("表现元数据缺失: " + key)
	if metadata.get("additional_properties", null) != false:
		return _fail("表现未关闭附加字段")
	for entry in metadata.leaves:
		if not entry is Dictionary or not entry.get("path", null) is String or not entry.get("type", null) is String:
			return _fail("表现叶字段损坏")
	_meta = metadata.duplicate(true)
	if _contract_cache.is_empty():
		var file: FileAccess = FileAccess.open(CONTRACT_PATH, FileAccess.READ)
		if file == null:
			return _fail("上下文契约无法读取")
		var parser: JSON = JSON.new()
		if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
			return _fail("上下文契约解析失败")
		_contract_cache = parser.data
	_contract = _contract_cache.duplicate(true)
	var contracts: Variant = _contract.get("context_keys", null)
	if not contracts is Dictionary:
		return _fail("上下文契约缺少 context_keys")
	for key in ["damage_number_semantics", "player_attribute_bindings", "resource_resolution", "probe_credentials", "baseline_version_state", "default_applications", "migration_state", "preview_fingerprint"]:
		var spec: Variant = contracts.get(key, null)
		if not spec is Dictionary or not spec.get("consumers", null) is Array or not spec.get("required_by", null) is Array or not ["Array", "Dictionary"].has(spec.get("type", null)):
			return _fail("上下文契约损坏: " + key)
	_rules = _read_csv(rules_path, ["rule_id", "condition", "severity", "field_path", "error_code"])
	if not last_error.is_empty():
		return false
	var messages: Array[Dictionary] = _read_csv(messages_path, ["code", "audience", "template", "placeholders"])
	if not last_error.is_empty():
		return false
	for row in messages:
		var code: String = str(row.get("code", ""))
		if code.is_empty() or _messages.has(code):
			return _fail("重复/空文案 code")
		_messages[code] = str(row.get("template", ""))
	if not register_group(70, 84, _handlers()):
		return false
	_ready = true
	return true

func _handlers() -> Dictionary:
	return {
		"表现段缺七类必备槽位或出现其他未登记段": _sections,
		"正式表现订阅 debug_record 或结算之外的调试数据": _subscriptions,
		"表现配置存在逻辑回写或动画回调驱动出手": _writeback,
		"音效启用但并发上限缺失或不是正整数": _sfx,
		"动画启用却缺逻辑 tick 与动画帧对齐": _anim,
		"拖尾未区分 independent 与瞬时外观方式": _trail,
		"数字合并跨目标、跨类型或回写合并后的逻辑伤害": _damage,
		"玩家数字手填值与当前生效参数脱离": _attributes,
		"资源缺失但有合法禁用占位方式": _resources,
		"装载前行为契约探针失败": _probes,
		"非功能提示试图改变事件、来源链、排序或预算丢弃语义": _hints,
		"保存时底层定义已被其他操作更新": _baseline,
		"已合法应用默认值但作者尚未显式填写": _defaults,
		"迁移没有完整路径、目标版本未知或语义不能无损解释": _migration,
		"预览使用内容与待保存内容指纹不同": _preview
	}

func validate(cfg: Dictionary, context: Dictionary) -> Dictionary:
	if not _ready:
		return _unavailable(last_error if not last_error.is_empty() else "表现元数据不可用")
	last_error = ""
	_failed = false
	_notices.clear()
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
	notices.append_array(_notices)
	return {"ok": ok and not _failed, "diagnostics": diagnostics, "notices": notices}

func _spec(entries: Array, path: String) -> Variant:
	for entry in entries:
		if entry is Dictionary and entry.get("path", null) == path:
			return entry
	return null

func _valid(value: Variant, entry: Dictionary) -> bool:
	var kind: String = str(entry.get("type", ""))
	if kind == "string" and not value is String:
		return false
	if kind == "boolean" and not value is bool:
		return false
	if kind == "object" and not value is Dictionary:
		return false
	if kind == "integer" and not value is int:
		return false
	if kind == "number" and not (value is float or value is int):
		return false
	if kind == "const" or entry.has("const"):
		var constant: Variant = entry.get("const", null)
		if typeof(value) != typeof(constant) or value != constant:
			return false
	if value is float and not is_finite(value):
		return false
	if value is int or value is float:
		if entry.has("minimum") and float(value) < float(entry.minimum):
			return false
		if entry.has("maximum") and float(value) > float(entry.maximum):
			return false
	if value is String and entry.has("minLength") and value.length() < int(entry.minLength):
		return false
	var allowed: Variant = entry.get("enum", null)
	return not allowed is Array or allowed.has(value)

func _children(pattern: String) -> Array[String]:
	var result: Array[String] = []
	for collection in [_meta.leaves, _meta.arrays, _meta.objects]:
		for entry in collection:
			var full: String = str(entry.get("path", ""))
			if full.begins_with(pattern + "."):
				var child: String = full.trim_prefix(pattern + ".").get_slice(".", 0).trim_suffix("[i]")
				if not result.has(child):
					result.append(child)
	return result

func _walk(cfg: Dictionary, value: Variant, path: String, pattern: String, issues: Array) -> void:
	var obj: Variant = _spec(_meta.objects, pattern)
	var arr: Variant = _spec(_meta.arrays, pattern)
	if obj is Dictionary and not value is Dictionary:
		issues.append(_issue(cfg, path, "Schema 对象"))
		return
	if arr is Dictionary:
		if not value is Array:
			issues.append(_issue(cfg, path, "Schema 数组"))
			return
		for index in range(value.size()):
			var item: Variant = value[index]
			var item_path: String = "%s[%d]" % [path, index]
			var kind: String = str(arr.get("item_kind", ""))
			var item_spec: Variant = arr.get("item", null)
			if not _valid(item, {"type": kind}) or (item_spec is Dictionary and not _valid(item, item_spec)):
				issues.append(_issue(cfg, item_path, "合法的数组元素"))
			elif item is Dictionary:
				_walk(cfg, item, item_path, pattern + "[i]", issues)
		return
	if not value is Dictionary or not obj is Dictionary or obj.get("additional_properties", null) != false:
		return
	var allowed: Array[String] = _children(pattern)
	if pattern == "presentation.fx.vanish_by_reason":
		for reason in _meta.natural_reason_keys:
			allowed.append(str(reason))
	for key in value:
		var child_path: String = path + "." + str(key)
		if not allowed.has(str(key)):
			issues.append(_issue(cfg, child_path, "Schema 登记字段"))
		else:
			_walk(cfg, value[key], child_path, pattern + "." + str(key), issues)

func _sections(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	var presentation: Variant = cfg.get("presentation", null)
	if not presentation is Dictionary:
		for section in _meta.required_sections:
			issues.append(_issue(cfg, "presentation." + str(section), "必备表现段"))
		return issues
	for section in _meta.required_sections:
		if not presentation.has(section):
			issues.append(_issue(cfg, "presentation." + str(section), "必备表现段"))
	for section in presentation:
		var path: String = "presentation." + str(section)
		if not _meta.required_sections.has(section):
			issues.append(_issue(cfg, path, "只允许登记的七段"))
		else:
			_walk(cfg, presentation[section], path, path, issues)
	for entry in _meta.leaves:
		var matches: Array = []
		_expand(cfg, _tokens(str(entry.path)), 0, "", matches, true)
		for hit in matches:
			if not _valid(hit.value, entry):
				issues.append(_issue(cfg, str(hit.path), "Schema 类型、枚举和范围"))
	return issues

func _scan_subscription(cfg: Dictionary, value: Variant, path: String, issues: Array) -> void:
	if value is Dictionary:
		for key in value:
			var child: String = path + "." + str(key)
			if _meta.forbidden_subscription_values.has(key) or (path.ends_with("vanish_by_reason") and not _meta.natural_reason_keys.has(key)):
				issues.append(_issue(cfg, child, "自然原因和正式结算订阅"))
			_scan_subscription(cfg, value[key], child, issues)
	elif value is Array:
		for index in range(value.size()):
			_scan_subscription(cfg, value[index], "%s[%d]" % [path, index], issues)
	elif value is String and _meta.forbidden_subscription_values.has(value):
		issues.append(_issue(cfg, path, "不可订阅调试数据"))

func _subscriptions(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	for section in _meta.required_sections:
		var fields: Variant = _meta.subscription_fields.get(section, null)
		if fields is Array:
			for field in fields:
				var path: String = "presentation.%s.%s" % [section, field]
				if _has_path(cfg, path):
					_scan_subscription(cfg, _get_path(cfg, path), path, issues)
	return issues

func _writeback(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	var policy: Dictionary = _meta.logic_writeback
	for path in policy.const_fields:
		if _has_path(cfg, path) and not _valid(_get_path(cfg, path), {"const": policy.const_fields[path]}):
			issues.append(_issue(cfg, path, "只读表现常量"))
	for path in policy.enum_fields:
		var value: Variant = _get_path(cfg, path)
		if _has_path(cfg, path) and (not value is String or not policy.enum_fields[path].has(value)):
			issues.append(_issue(cfg, path, "只读回调枚举"))
	var alignments: Variant = _get_path(cfg, "presentation.anim.alignments")
	if alignments is Array and _meta.get("logic_writeback_forbidden", false) == true:
		for index in range(alignments.size()):
			var item: Variant = alignments[index]
			if item is Dictionary:
				for key in item:
					if not _children("presentation.anim.alignments[i]").has(str(key)):
						issues.append(_issue(cfg, "presentation.anim.alignments[%d].%s" % [index, str(key)], "对齐项不得驱动逻辑"))
	return issues

func _enabled(cfg: Dictionary, section: String) -> bool:
	var value: Variant = _get_path(cfg, "presentation." + section)
	var spec: Variant = _meta.section_enable.get(section, null)
	if not value is Dictionary or not spec is Dictionary:
		return false
	var field: Variant = spec.get("enabled_field", null)
	if field is String and not field.is_empty():
		var enabled: Variant = value.get(field, spec.get("enabled_default", null))
		return enabled is bool and enabled
	var slots: Variant = spec.get("activity_slots", null)
	if slots is Array:
		for slot in slots:
			if not value.has(slot):
				continue
			var content: Variant = value[slot]
			if content is Array or content is Dictionary:
				if not content.is_empty():
					return true
			elif content is String:
				if not content.strip_edges().is_empty():
					return true
			elif content != null:
				return true
	return false

func _sfx(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	if _enabled(cfg, "sfx"):
		for field in _meta.enabled_requires.get("sfx", []):
			var path: String = "presentation.sfx." + str(field)
			var value: Variant = _get_path(cfg, path)
			var spec: Variant = _spec(_meta.leaves, path)
			var minimum: Variant = _meta.enabled_minimum_overrides.get(path, null)
			if not _has_path(cfg, path) or not spec is Dictionary or not _valid(value, spec) or ((minimum is int or minimum is float) and (value is int or value is float) and float(value) < float(minimum)):
				issues.append(_issue(cfg, path, "启用时正整数；未启用按 Schema 范围"))
	return issues

func _anim(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	if _enabled(cfg, "anim"):
		for field in _meta.enabled_requires.get("anim", []):
			var path: String = "presentation.anim." + str(field)
			var spec: Variant = _spec(_meta.leaves, path)
			if not _has_path(cfg, path) or not spec is Dictionary or not _valid(_get_path(cfg, path), spec):
				issues.append(_issue(cfg, path, "合法的逻辑 tick 与动画帧对齐"))
	return issues

func _trail(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	if not _enabled(cfg, "trail"):
		return issues
	var policy: Dictionary = _meta.trail_carrier_policy
	var path: String = str(policy.carrier_field)
	var carrier: Variant = _get_path(cfg, path)
	if not carrier is String or not policy.carrier_enum.has(carrier):
		issues.append(_issue(cfg, path, "登记的拖尾载体"))
		return issues
	var required: Variant = policy.required_end_policy.get(carrier, null)
	if required is String:
		var spec: Variant = _spec(_meta.leaves, required)
		if not _has_path(cfg, required) or not spec is Dictionary or not _valid(_get_path(cfg, required), spec):
			issues.append(_issue(cfg, required, "显式结束策略"))
	var forbidden: Variant = policy.forbidden_end_policy.get(carrier, null)
	if forbidden is Array:
		for candidate in forbidden:
			if _has_path(cfg, candidate):
				issues.append(_issue(cfg, str(candidate), "此载体不适用的结束策略"))
	return issues

func _damage(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var policy: Dictionary = _meta.damage_number_policy
	for pair in [["source", "source_enum"], ["merge_policy", "merge_policy_enum"]]:
		var path: String = "presentation.damage_number." + str(pair[0])
		var value: Variant = _get_path(cfg, path)
		if _has_path(cfg, path) and (not value is String or not policy[pair[1]].has(value)):
			issues.append(_issue(cfg, path, "登记的表现枚举"))
	var fallback: String = "presentation.damage_number.fallback_total"
	if _has_path(cfg, fallback) and not _valid(_get_path(cfg, fallback), {"const": policy.fallback_total_const}):
		issues.append(_issue(cfg, fallback, "不得回写逻辑伤害"))
	var merge: String = "presentation.damage_number.merge_policy"
	var facts: Variant = _fact(context, str(policy.optional_context_key), rule, merge, issues)
	if facts is Dictionary:
		for key in ["cross_target", "cross_type", "writeback"]:
			var value: Variant = facts.get(key, null)
			if not value is bool:
				_context_issue(issues, rule, merge, str(policy.optional_context_key), value, "严格 bool " + key)
			elif value and policy.get(key + "_forbidden", false) == true:
				issues.append(_issue(cfg, merge, "不得跨目标、跨类型或回写"))
	return issues

func _attributes(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var facts: Variant = _fact(context, "player_attribute_bindings", rule, "meta.player_attributes", issues)
	if facts is Dictionary:
		for key in facts:
			var item: Variant = facts[key]
			if not item is Dictionary or not item.get("matches", null) is bool or not item.get("resolved_path", null) is String or not item.has("resolved_value"):
				_context_issue(issues, rule, "meta.player_attributes", "player_attribute_bindings", item, "完整的解析绑定")
			elif not item.matches:
				issues.append(_issue(cfg, "meta.player_attributes", "当前生效参数一致"))
	return issues

func _resources(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var facts: Variant = _fact(context, "resource_resolution", rule, "presentation", issues)
	if facts is Dictionary:
		for path in facts:
			var item: Variant = facts[path]
			if not path is String or not item is Dictionary or not item.get("resolved", null) is bool or not item.get("placeholder_legal", null) is bool:
				_context_issue(issues, rule, str(path), "resource_resolution", item, "解析及占位事实")
			elif not item.resolved and item.placeholder_legal:
				issues.append(_issue(cfg, path, "合法禁用占位"))
	return issues

func _probes(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var facts: Variant = _fact(context, "probe_credentials", rule, "bricks", issues)
	if facts is Dictionary:
		for path in facts:
			var item: Variant = facts[path]
			if not path is String or not item is Dictionary or not item.get("result", null) is String or not item.get("content_fingerprint", null) is String or str(item.get("content_fingerprint", "")).is_empty() or not item.get("runtime_version", null) is String or str(item.get("runtime_version", "")).is_empty() or not item.get("capabilities", null) is Array or not item.get("coverage", null) is Dictionary:
				_context_issue(issues, rule, str(path), "probe_credentials", item, "完整绑定凭据")
			elif item.result != "pass" or item.coverage.is_empty():
				issues.append(_issue(cfg, path, "通过且覆盖完整的探针"))
	return issues

func _hints(cfg: Dictionary, _context: Dictionary, _rule: Dictionary) -> Array:
	var issues: Array = []
	if cfg.has("runtime_hints"):
		_hint_leaf(cfg, cfg.runtime_hints, "runtime_hints", _meta.runtime_hints, issues)
	return issues

func _hint_leaf(cfg: Dictionary, value: Variant, path: String, registry: Dictionary, issues: Array) -> void:
	if path == "runtime_hints":
		if not value is Dictionary:
			issues.append(_issue(cfg, path, "提示对象"))
			return
	else:
		var leaf: Variant = _spec(registry.leaves, path)
		if leaf is Dictionary:
			if not _valid(value, leaf):
				issues.append(_issue(cfg, path, "合法提示叶"))
			return
		var array: Variant = _spec(registry.arrays, path)
		if array is Dictionary:
			if not value is Array:
				issues.append(_issue(cfg, path, "提示数组"))
				return
			for index in range(value.size()):
				var item: Variant = value[index]
				if not _valid(item, {"type": array.item_kind}) or not _valid(item, array.item):
					issues.append(_issue(cfg, "%s[%d]" % [path, index], "提示数组项"))
			return
	if value is Dictionary:
		for key in value:
			_hint_leaf(cfg, value[key], path + "." + str(key), registry, issues)
	elif value is Array:
		for index in range(value.size()):
			_hint_leaf(cfg, value[index], "%s[%d]" % [path, index], registry, issues)
	else:
		issues.append(_issue(cfg, path, "已登记提示叶"))

func _baseline(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var item: Variant = _fact(context, "baseline_version_state", rule, "meta.version", issues)
	if item is Dictionary:
		if not item.get("baseline_version", null) is String or not item.get("current_underlying_version", null) is String or not item.get("operation", null) is String:
			_context_issue(issues, rule, "meta.version", "baseline_version_state", item, "版本与操作字符串")
		elif item.baseline_version != item.current_underlying_version:
			issues.append(_issue(cfg, "meta.version", "保存基线一致"))
	return issues

func _defaults(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var items: Variant = _fact(context, "default_applications", rule, "presentation", issues)
	if items is Array:
		for item in items:
			if not item is Dictionary or not item.get("path", null) is String or not item.has("default_value") or not item.get("author_filled", null) is bool or not item.get("legally_applied", null) is bool:
				_context_issue(issues, rule, "presentation", "default_applications", item, "合法默认及实际路径")
			elif item.legally_applied and not item.author_filled:
				issues.append(_issue(cfg, item.path, "显式填写默认字段"))
	return issues

func _migration(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var item: Variant = _fact(context, "migration_state", rule, "schema_version", issues)
	if item is Dictionary:
		if not item.get("migrating", null) is bool or not item.get("source_version", null) is String or not item.get("target_version", null) is String or not item.get("path_complete", null) is bool or not item.get("lossless", null) is bool:
			_context_issue(issues, rule, "schema_version", "migration_state", item, "完整迁移事实")
		elif item.migrating and (item.target_version.is_empty() or not item.path_complete or not item.lossless):
			issues.append(_issue(cfg, "schema_version", "已知目标及完整无损迁移路径"))
	return issues

func _preview(cfg: Dictionary, context: Dictionary, rule: Dictionary) -> Array:
	var issues: Array = []
	var item: Variant = _fact(context, "preview_fingerprint", rule, "meta.version", issues)
	if item is Dictionary:
		var operation: Variant = item.get("operation", null)
		if not item.get("preview_fingerprint", null) is String or not item.get("current_fingerprint", null) is String or not operation is String or not ["save", "certify"].has(operation):
			_context_issue(issues, rule, "meta.version", "preview_fingerprint", item, "指纹与入口")
		elif item.preview_fingerprint != item.current_fingerprint:
			if operation == "certify":
				issues.append(_issue(cfg, "meta.version", "预览指纹与当前内容一致"))
			else:
				_notices.append("V-084：未预览/未认证；普通保存允许")
	return issues

func _fact(context: Dictionary, key: String, rule: Dictionary, path: String, issues: Array) -> Variant:
	var spec: Variant = _contract.context_keys.get(key, null)
	if not spec is Dictionary or not spec.consumers.has(rule.rule_id):
		_context_issue(issues, rule, path, key, null, "消费者未登记")
		return null
	if not context.has(key):
		if spec.required_by.has(rule.rule_id):
			_context_issue(issues, rule, path, key, "未填写", "必需上下文缺失")
		else:
			_notices.append("%s：可选上下文 %s 缺失，子检查跳过" % [rule.rule_id, key])
		return null
	var value: Variant = context[key]
	if not ((spec.type == "Dictionary" and value is Dictionary) or (spec.type == "Array" and value is Array)):
		_context_issue(issues, rule, path, key, value, "类型 " + str(spec.type))
		return null
	return value

func _context_issue(issues: Array, rule: Dictionary, path: String, key: String, actual: Variant, expected: String) -> void:
	_failed = true
	var message: String = "%s：上下文 %s 不可用（%s），实际 %s" % [rule.rule_id, key, expected, _display(actual)]
	last_error = message if last_error.is_empty() else last_error + "\n" + message
	issues.append({"path": path, "actual": _display(actual), "expected": message})
