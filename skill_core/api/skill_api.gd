class_name SkillApi extends RefCounted

const STAGE_FILLING: StringName = &"filling"
const STAGE_CARD: StringName = &"card"
const STAGE_ASSEMBLY: StringName = &"assembly"
const STAGE_SAVE: StringName = &"save"
const STAGE_LOAD: StringName = &"load"
const STAGE_PREVIEW: StringName = &"preview"

const RunnerScript = preload("res://skill_core/runtime/preview_runner.gd")
const CodecScript = preload("res://skill_core/schema/cfg_codec.gd")
const SchemaScript = preload("res://skill_core/schema/cfg_schema.gd")
const ResolverScript = preload("res://skill_core/resolve/param_resolver.gd")
const BodyScript = preload("res://skill_core/runtime/effect_body.gd")

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
	# const RunnerScript hoisted to script scope
	# const CodecScript hoisted to script scope
	# const SchemaScript hoisted to script scope
	# const ResolverScript hoisted to script scope
	# const BodyScript hoisted to script scope
	# const DiagnosticScript hoisted to script scope
	var failure: Callable = func(path: String, message: String) -> Dictionary:
		var diagnostic: RefCounted = Diagnostic.new()
		diagnostic.rule_id = "API"
		diagnostic.code = "INVALID_SIM_INPUT"
		diagnostic.path = path
		diagnostic.expected = message
		diagnostic.hint = message
		return {"ok": false, "path": path, "error": message, "diagnostics": [diagnostic]}
	var diagnostics: Array = CodecScript.validate_structure(cfg)
	if not diagnostics.is_empty():
		return {"ok": false, "path": "cfg", "error": "CFG structure rejected", "diagnostics": diagnostics}
	var schema: RefCounted = SchemaScript.new()
	if not schema.configure():
		return failure.call("schema", schema.last_error)
	var checked: Dictionary = schema.validate(cfg)
	if not checked["ok"]:
		return {"ok": false, "path": "cfg", "error": "CFG schema rejected", "diagnostics": checked["diagnostics"]}
	var catalog_path: String = "res://data/bricks/brick_catalog.json"
	if not FileAccess.file_exists(catalog_path):
		return failure.call("catalog", "Missing brick catalog")
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	if not catalog is Array or catalog.is_empty():
		return failure.call("catalog", "Expected nonempty brick catalog array")
	var carriers: Dictionary = {}
	for entry in catalog:
		if not entry is Dictionary:
			return failure.call("catalog", "Expected catalog entry object")
		var id: Variant = entry.get("brick_id", null)
		var carrier: Variant = entry.get("carrier", null)
		if not id is String or id.is_empty() or not carrier is String or carriers.has(id):
			return failure.call("catalog", "Invalid or duplicate catalog identity/carrier")
		carriers[id] = carrier
	var roots: Array = []
	for index in range(cfg["bricks"].size()):
		var brick: Dictionary = cfg["bricks"][index]
		var id: Variant = brick.get("brick_id", null)
		var path: String = "bricks[%d]" % index
		if not id is String or not carriers.has(id):
			return failure.call(path + ".brick_id", "Brick is not registered in catalog")
		if brick["carrier"] != carriers[id]:
			return failure.call(path + ".carrier", "Carrier disagrees with catalog")
		if carriers[id] != BodyScript.CARRIER_INDEPENDENT:
			continue
		# True source does not specify root routing. This increment requires an
		# explicit registration in default_cfg; never guess from an ID or order.
		var registration: Variant = brick.get("default_cfg", null)
		if not registration is Dictionary:
			return failure.call(path + ".default_cfg", "Root registration must be an object")
		var template_id: Variant = registration.get("template_id", null)
		var shot_id: Variant = registration.get("shot_id", null)
		if not template_id is String or template_id.is_empty() or not shot_id is String or shot_id.is_empty():
			return failure.call(path + ".default_cfg", "Explicit template_id and shot_id required")
		roots.append({"template_id": template_id, "shot_id": shot_id, "instance_id": "api:root:%d" % index})
	if roots.is_empty():
		return failure.call("bricks", "No catalog-classified independent root registration")
	var metadata_path: String = "res://data/params_meta.json"
	if not FileAccess.file_exists(metadata_path):
		return failure.call("handlers", "Missing part type metadata")
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	var enums: Variant = metadata.get("enums", null) if metadata is Dictionary else null
	var part_types: Variant = enums.get("part_type", null) if enums is Dictionary else null
	if not part_types is Array or part_types.is_empty():
		return failure.call("handlers", "Expected nonempty part_type registry")
	var _unsupported_part: Callable = func(_part: Dictionary, _record: Dictionary, _target: Dictionary) -> bool:
		return false
	var handlers: Dictionary = {}
	for kind in part_types:
		if not kind is String or kind.is_empty():
			return failure.call("handlers", "Invalid registered part type")
		handlers[kind] = _unsupported_part
	var resolved: Dictionary = ResolverScript.new().resolve(cfg)
	if not resolved["ok"]:
		return {"ok": false, "path": "params", "error": "Parameter resolution rejected", "diagnostics": resolved["diagnostics"]}
	var params: Variant = resolved["resolved"].get("params", null)
	var templates: Variant = params.get("templates", null) if params is Dictionary else null
	if not templates is Array or templates.is_empty():
		return failure.call("params.templates", "Nonempty template registry required")
	var families: Dictionary = {}
	for template in templates:
		if not template is Dictionary:
			return failure.call("params.templates", "Expected template object")
		var id: Variant = template.get("template_id", null)
		if not id is String or id.is_empty():
			return failure.call("params.templates", "Explicit template identity required")
		families[id] = id
	# No host roster or derivation routing is exposed by the frozen signature.
	# Empty targets is an explicit lifecycle sandbox; unresolved routes fail in start.
	var options: Dictionary = {"seed": seed, "roots": roots, "handlers": handlers,
		"template_families": families, "derivation_bindings": {}, "targets": []}
	var runner: RefCounted = RunnerScript.new()
	var started: Dictionary = runner.start(cfg, options)
	print("SkillApi.create_sim PreviewRunner.start: ", started)
	if not started["ok"]:
		return started
	return {"ok": true, "diagnostics": [], "sim": {"runner": runner}, "fingerprint": started["fingerprint"]}

# 职责：推进模拟固定步；参数：sim 为模拟状态、ticks 为步数；返回：统一结果包；对应真源：卷二第 14 章。
func step_sim(sim: Variant, ticks: int = 1) -> Dictionary:
	# const RunnerScript hoisted to script scope
	# const DiagnosticScript hoisted to script scope
	var failure: Callable = func(path: String, message: String) -> Dictionary:
		var diagnostic: RefCounted = Diagnostic.new()
		diagnostic.rule_id = "API"
		diagnostic.code = "INVALID_SIM_INPUT"
		diagnostic.path = path
		diagnostic.expected = message
		diagnostic.hint = message
		return {"ok": false, "path": path, "error": message, "diagnostics": [diagnostic]}
	if ticks <= 0:
		return failure.call("ticks", "Expected positive integer tick count")
	if not sim is Dictionary:
		return failure.call("sim", "Expected simulation handle")
	var runner: Variant = sim.get("runner", null)
	if not runner is Object or not is_instance_valid(runner):
		return failure.call("sim.runner", "Missing or expired preview runner")
	if not runner is RunnerScript:
		return failure.call("sim.runner", "Handle must contain a PreviewRunner")
	var advanced: Dictionary = runner.advance_ticks(ticks)
	if not advanced["ok"]:
		if not advanced.has("diagnostics"):
			advanced["diagnostics"] = []
		return advanced
	return {"ok": true, "diagnostics": [], "snapshot": runner.snapshot_state()}

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
