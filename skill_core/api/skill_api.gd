class_name SkillApi extends RefCounted

const STAGE_FILLING: StringName = &"filling"
const STAGE_CARD: StringName = &"card"
const STAGE_ASSEMBLY: StringName = &"assembly"
const STAGE_SAVE: StringName = &"save"
const STAGE_LOAD: StringName = &"load"
const STAGE_PREVIEW: StringName = &"preview"

# 职责：加载技能 CFG；参数：path 为 UTF-8 配置路径；返回：统一结果包；对应真源：第 16.1 节。
func load_cfg(path: String) -> Dictionary:
	return _not_implemented("load_cfg", path)

# 职责：校验并保存技能 CFG；参数：path 为目标路径、cfg 为定义；返回：统一结果包；对应真源：第 16.1、14 章。
func save_cfg(path: String, cfg: Dictionary) -> Dictionary:
	return _not_implemented("save_cfg", path)

# 职责：解析 YAML 子集；参数：text 为 UTF-8 文本；返回：统一结果包；对应真源：第 16.1 节。
func parse_yaml(text: String) -> Dictionary:
	return _not_implemented("parse_yaml", "text")

# 职责：把定义序列化为 YAML；参数：value 为待序列化值；返回：统一结果包；对应真源：第 16.1 节。
func dump_yaml(value: Variant) -> Dictionary:
	return _not_implemented("dump_yaml", "value")

# 职责：加载积木目录素材；参数：path 为 JSON 目录路径；返回：统一结果包；对应真源：第 1.8、卷三目录约定。
func load_catalog(path: String) -> Dictionary:
	return _not_implemented("load_catalog", path)

# 职责：按 brick_id 查询积木；参数：catalog 为目录、brick_id 为标识；返回：统一结果包；对应真源：第 1.8 节。
func get_brick(catalog: Variant, brick_id: String) -> Dictionary:
	return _not_implemented("get_brick", brick_id)

# 职责：按载体和状态筛选积木；参数：catalog 为目录、carrier/status 为空表示不筛选；返回：统一结果包；对应真源：第 8 章与目录素材。
func list_bricks(catalog: Variant, carrier: String = "", status: String = "") -> Dictionary:
	return _not_implemented("list_bricks", "%s/%s" % [carrier, status])

# 职责：在指定阶段校验 CFG；参数：cfg 为定义、stage 为六阶段常量之一；返回：统一结果包；对应真源：第 14 章与第 20.1 节。
func validate(cfg: Dictionary, stage: StringName = STAGE_SAVE) -> Dictionary:
	return _not_implemented("validate", String(stage))

# 职责：解析 CFG 得到确定性运行定义；参数：cfg 为已加载定义；返回：统一结果包；对应真源：第 5—7、16.2 节。
func resolve(cfg: Dictionary) -> Dictionary:
	return _not_implemented("resolve", "cfg")

# 职责：应用修饰器规则；参数：value 为基准值、modifiers 为修饰器列表；返回：统一结果包；对应真源：第 14.4、16.3 节。
func apply_modifiers(value: Variant, modifiers: Array = []) -> Dictionary:
	return _not_implemented("apply_modifiers", "modifiers")

# 职责：创建最小运行时模拟；参数：cfg 为运行定义、seed 为确定性种子；返回：统一结果包；对应真源：卷二第 4—7 章。
func create_sim(cfg: Dictionary, seed: int = 0) -> Dictionary:
	return _not_implemented("create_sim", str(seed))

# 职责：推进模拟固定步；参数：sim 为模拟状态、ticks 为步数；返回：统一结果包；对应真源：卷二第 14 章。
func step_sim(sim: Variant, ticks: int = 1) -> Dictionary:
	return _not_implemented("step_sim", str(ticks))

func _not_implemented(operation: String, path: String) -> Dictionary:
	var diagnostic := Diagnostic.new()
	diagnostic.rule_id = "API"
	diagnostic.code = "NOT_IMPLEMENTED"
	diagnostic.severity = Diagnostic.SEV_HINT
	diagnostic.path = path
	diagnostic.actual = operation
	diagnostic.expected = "实现对应接口"
	diagnostic.hint = "未实现"
	return {"ok": false, "diagnostics": [diagnostic]}
