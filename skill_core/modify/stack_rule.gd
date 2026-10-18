class_name StackRule
extends RefCounted

const Diag = preload("res://skill_core/api/diagnostic.gd")

# 待素材替换：运算顺序是可注入元数据，不由求值代码决定。
const TRANSITION_METADATA: Dictionary = {
	"operation_order": ["set", "add", "mul", "clamp"],
	"operations": {
		"set": {"arity": 1},
		"add": {"arity": 1},
		"mul": {"arity": 1},
		"clamp": {"arity": 2},
	},
}
const RULES: Dictionary = {
	"unknown_operation": {"id": "V-049", "code": "E-0012", "severity": Diag.SEV_BLOCK},
	"set_conflict": {"id": "V-050", "code": "E-0027", "severity": Diag.SEV_WARN},
	"invalid_result": {"id": "V-051", "code": "E-0026", "severity": Diag.SEV_BLOCK},
}

var last_error: String = ""
var _ready: bool = false
var _metadata: Dictionary = {}
var _profiles: Dictionary = {}
var _operators: Dictionary = {}

func configure(metadata: Dictionary = TRANSITION_METADATA, profiles: Dictionary = {}) -> bool:
	_ready = false
	last_error = ""
	if not _validate_metadata(metadata):
		return false
	_metadata = metadata.duplicate(true)
	_profiles = profiles.duplicate(true)
	_operators = {
		"set": Callable(self, "_apply_set"),
		"add": Callable(self, "_apply_add"),
		"mul": Callable(self, "_apply_mul"),
		"clamp": Callable(self, "_apply_clamp"),
	}
	_ready = true
	return true

# 求值结果只含新值，不修改 base 或调用方传入的 CFG。
# operations 的每项是已解析的 stack_operations 条目：
# {category, operands, mount_order, base_value?, hard_range?}。
func evaluate(base_value: Variant, operations: Array, exposed: Dictionary, path: String = "field") -> Dictionary:
	if not _ready:
		return _unavailable()
	var result: Dictionary = _result()
	if not _number(base_value):
		_emit(result, "invalid_result", path, _display(base_value), "有限数值基准")
		return result
	if not _valid_bounds(exposed):
		_emit(result, "invalid_result", path, _display(exposed), "暴露字段必须提供有限 min/max 且 min <= max")
		return result
	var entries: Array = []
	for index in range(operations.size()):
		var operation: Variant = operations[index]
		if not operation is Dictionary or not _valid_operation(operation, path, result):
			continue
		var copied: Dictionary = operation.duplicate(true)
		if not copied.has("mount_order"):
			copied["mount_order"] = index
		if copied["category"] == "clamp":
			var clamp_operands: Array = copied["operands"]
			if clamp_operands[0] < exposed["min"] or clamp_operands[1] > exposed["max"]:
				_emit(result, "invalid_result", path + ".operands", _display(clamp_operands), "clamp 上下限必须位于暴露范围 [%s, %s]" % [str(exposed["min"]), str(exposed["max"])])
		entries.append(copied)
	if not result.ok:
		return result
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["mount_order"]) < int(b["mount_order"]))
	var set_count: int = 0
	for entry in entries:
		if entry["category"] == "set":
			set_count += 1
	if set_count > 1 and not _has_conflict_note(exposed):
		_emit(result, "set_conflict", path + ".set_conflict_note", "未填写", "说明最后挂载者覆盖")
	var value: float = float(base_value)
	for category in _metadata["operation_order"]:
		for entry in entries:
			if entry["category"] != category:
				continue
			var apply: Callable = _operators[category]
			value = float(apply.call(value, entry["operands"]))
			if not is_finite(value):
				_emit(result, "invalid_result", path, str(value), "合并结果必须为有限数值")
				return result
	if value < float(exposed["min"]) or value > float(exposed["max"]):
		_emit(result, "invalid_result", path, str(value), "结果必须落入暴露上下限 [%s, %s]" % [str(exposed["min"]), str(exposed["max"])])
		return result
	if exposed.has("integer") and exposed["integer"] == true and value != floor(value):
		_emit(result, "invalid_result", path, str(value), "结果必须保持整数类型")
		return result
	result["value"] = int(value) if base_value is int else value
	return result

func calculate(base_value: Variant, operations: Array, exposed: Dictionary, path: String = "field") -> Dictionary:
	return evaluate(base_value, operations, exposed, path)

# 从 modifier CFG 和注入的 profile 注册表生产 T-012 消费的 stack_operations。
# 返回形状：{ok, values, stack_operations, diagnostics, notices}。
func resolve(modifiers: Array, exposed_fields: Dictionary, profiles: Dictionary = {}, context: Dictionary = {}) -> Dictionary:
	if not _ready:
		return _unavailable()
	var result: Dictionary = _result()
	var registry: Dictionary = profiles if not profiles.is_empty() else _profiles
	var by_target: Dictionary = {}
	for index in range(modifiers.size()):
		var modifier: Variant = modifiers[index]
		if not modifier is Dictionary:
			_emit(result, "unknown_operation", "params.modifiers[%d].stack_rule" % index, _display(modifier), "已登记 operation_profile 引用")
			continue
		var modifier_id: Variant = modifier.get("modifier_id", null)
		var stack: Variant = modifier.get("stack_rule", null)
		var profile_name: Variant = stack.get("operation_profile", null) if stack is Dictionary else null
		var profile: Variant = registry.get(profile_name, null) if profile_name is String else null
		if not profile is Dictionary:
			_emit(result, "unknown_operation", "params.modifiers[%d].stack_rule.operation_profile" % index, _display(profile_name), "已登记 operation_profile；不得执行字符串表达式")
			continue
		var targets: Variant = modifier.get("targets", null)
		if not targets is Array:
			_emit(result, "invalid_result", "params.modifiers[%d].targets" % index, _display(targets), "字段引用数组")
			continue
		var operation: Dictionary = profile.duplicate(true)
		operation["modifier_id"] = modifier_id
		operation["mount_order"] = int(operation.get("mount_order", index))
		result["stack_operations"][str(modifier_id)] = operation.duplicate(true)
		for target_index in range(targets.size()):
			var target: Variant = targets[target_index]
			if not target is String or not exposed_fields.has(target):
				_emit(result, "invalid_result", "params.modifiers[%d].targets[%d]" % [index, target_index], _display(target), "已登记暴露字段引用")
				continue
			var entry: Dictionary = {"category": operation.get("category", null), "operands": operation.get("operands", []), "mount_order": operation["mount_order"], "base_value": operation.get("base_value", null), "hard_range": operation.get("hard_range", null)}
			var list: Variant = by_target.get(target, null)
			if not list is Array:
				list = []
				by_target[target] = list
			list.append(entry)
	for target in by_target:
		var field: Dictionary = exposed_fields[target]
		var base_values: Variant = context.get("base_values", null)
		var base: Variant = base_values.get(target, null) if base_values is Dictionary else null
		if base == null:
			base = field.get("base_value", null)
		if base == null:
			_emit(result, "invalid_result", "params.modifiers[%s].targets" % str(target), "未填写", "提供基准值")
			continue
		var calculated: Dictionary = evaluate(base, by_target[target], field, str(target))
		result["diagnostics"].append_array(calculated["diagnostics"])
		result["notices"].append_array(calculated["notices"])
		if not calculated["ok"]:
			result["ok"] = false
		else:
			result["values"][target] = calculated["value"]
	if not context.is_empty() and not context.has("base_values"):
		_emit(result, "invalid_result", "stack_operations", "未提供 base_values", "运行态基准必须从上下文注入")
	return result

func _validate_metadata(metadata: Dictionary) -> bool:
	var order: Variant = metadata.get("operation_order", null)
	var operations: Variant = metadata.get("operations", null)
	if not order is Array or order.is_empty() or not operations is Dictionary:
		return _fail("缺少 operation_order / operations 元数据")
	var seen: Dictionary = {}
	for category in order:
		if not category is String or category.is_empty() or seen.has(category) or not operations.has(category):
			return _fail("operation_order 含未登记、重复或非法类别")
		seen[category] = true
		var definition: Variant = operations[category]
		if not definition is Dictionary or not definition.get("arity", null) is int or int(definition["arity"]) < 0:
			return _fail("运算类别必须登记非负整数 arity")
	return true

func _valid_operation(operation: Dictionary, path: String, result: Dictionary) -> bool:
	var category: Variant = operation.get("category", null)
	if not category is String or not _metadata["operations"].has(category):
		_emit(result, "unknown_operation", path + ".operation_profile", _display(category), "已登记数值叠加类别")
		return false
	var definition: Dictionary = _metadata["operations"][category]
	var operands: Variant = operation.get("operands", null)
	if not operands is Array or operands.size() != int(definition["arity"]):
		_emit(result, "unknown_operation", path + ".operands", _display(operands), "符合已登记运算元数")
		return false
	for operand in operands:
		if not _number(operand):
			_emit(result, "unknown_operation", path + ".operands", _display(operand), "有限数值操作数")
			return false
	if category == "clamp" and operands[0] > operands[1]:
		_emit(result, "invalid_result", path + ".operands", _display(operands), "clamp 下限不得高于上限")
		return false
	if operation.has("mount_order") and (not operation["mount_order"] is int or int(operation["mount_order"]) < 0):
		_emit(result, "invalid_result", path + ".mount_order", _display(operation["mount_order"]), "非负整数挂载顺序")
		return false
	return true

func _valid_bounds(exposed: Dictionary) -> bool:
	return _number(exposed.get("min", null)) and _number(exposed.get("max", null)) and exposed["min"] <= exposed["max"]

func _has_conflict_note(exposed: Dictionary) -> bool:
	var note: Variant = exposed.get("set_conflict_note", null)
	return note is String and not note.strip_edges().is_empty()

func _apply_set(_value: float, operands: Array) -> float: return float(operands[0])
func _apply_add(value: float, operands: Array) -> float: return value + float(operands[0])
func _apply_mul(value: float, operands: Array) -> float: return value * float(operands[0])
func _apply_clamp(value: float, operands: Array) -> float: return clampf(value, float(operands[0]), float(operands[1]))

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _result() -> Dictionary:
	return {"ok": true, "value": null, "values": {}, "stack_operations": {}, "diagnostics": [], "notices": []}

func _emit(result: Dictionary, kind: String, path: String, actual: String, expected: String) -> void:
	var rule: Dictionary = RULES[kind]
	var diagnostic = Diag.new()
	diagnostic.rule_id = rule["id"]
	diagnostic.code = rule["code"]
	diagnostic.severity = rule["severity"]
	diagnostic.path = path
	diagnostic.actual = actual
	diagnostic.expected = expected
	diagnostic.hint = "%s：%s；要求 %s" % [rule["id"], path, expected]
	result["diagnostics"].append(diagnostic)
	if diagnostic.severity == Diag.SEV_BLOCK:
		result["ok"] = false

func _unavailable() -> Dictionary:
	last_error = "stack_rule 尚未配置元数据"
	var result: Dictionary = _result()
	result["ok"] = false
	result["notices"].append(last_error)
	return result

func _fail(message: String) -> bool:
	last_error = message
	return false

func _display(value: Variant) -> String:
	if value == null:
		return "null"
	return "%s (%s)" % [str(value), type_string(typeof(value))]
