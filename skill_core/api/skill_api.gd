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
const ValidatorScript = preload("res://skill_core/validate/validator.gd")
const IdentityRulesScript = preload("res://skill_core/validate/rules/r_identity.gd")
const TypesRulesScript = preload("res://skill_core/validate/rules/r_types.gd")
const ModifierRulesScript = preload("res://skill_core/validate/rules/r_modifier.gd")
const PresentationRulesScript = preload("res://skill_core/validate/rules/r_present.gd")
const IdentityMetaScript = preload("res://skill_core/validate/identity_meta.gd")

## 只读注入点（T-082 P1-8）：留空表示用 IdentityMeta 默认路径；
## 测试可指向 user:// 下的元数据夹具，用于覆盖「supported_schema_versions 缺失/为空」分支。
var identity_meta_path: String = ""


## 严格版本段判定：纯数字且无前导零（"0" 本身合法）。
## 不用 is_valid_int —— 它会接受 -1 / +1，把非法形态放行成「未知版本」。
static func _is_version_part(text: String) -> bool:
	if text.is_empty():
		return false
	if text.length() > 1 and text.begins_with("0"):
		return false
	for index in range(text.length()):
		var code: int = text.unicode_at(index)
		if code < 48 or code > 57:
			return false
	return true

# 职责：加载技能 CFG；参数：path 为 UTF-8 配置路径；返回：统一结果包；对应真源：第 16.1 节。
# T-082（U-37 填桩授权）。ok 语义（第 4 轮修订）：
#   ok = 零「有效」诊断（所有版本同一口径）；openable 表示「内容读得出来」：
#     early-failure 包（路径/读盘/解析失败）openable=false；可解析的包即使 ok=false 也 openable=true。
#   版本不受支持时只剔除「版本枚举不匹配」一条诊断，其余结构/类型诊断照常拦截。
#   schema_version 缺失/空值/null → SCHEMA_VERSION_MISSING；
#   非字符串（未加引号的 9.9 被解析成 float）或非「纯数字.纯数字」→ SCHEMA_VERSION_INVALID。
# V-083 只读不降级：不受支持的版本原样返回并标 read_only，绝不改写/迁移。
func load_cfg(path: String) -> Dictionary:
	var failure: Callable = func(field: String, message: String, diagnostics: Array) -> Dictionary:
		if not diagnostics.is_empty():
			return {"ok": false, "openable": false, "path": field, "error": message, "cfg": null, "data": null, "diagnostics": diagnostics}
		var diagnostic: RefCounted = Diagnostic.new()
		diagnostic.rule_id = "API"
		diagnostic.code = "LOAD_FAILED"
		diagnostic.path = field
		diagnostic.actual = path
		diagnostic.expected = message
		diagnostic.hint = message
		return {"ok": false, "openable": false, "path": field, "error": message, "cfg": null, "data": null, "diagnostics": [diagnostic]}
	if path.strip_edges().is_empty():
		return failure.call("path", "加载路径不能为空", [])
	if not FileAccess.file_exists(path):
		return failure.call("path", "CFG 不存在: %s" % path, [])
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return failure.call("path", "CFG 读取失败（%s）: %s" % [error_string(FileAccess.get_open_error()), path], [])
	var text: String = file.get_as_text()
	file.close()
	if text.is_empty():
		return failure.call("path", "CFG 为空文件: %s" % path, [])
	var codec: RefCounted = CodecScript.new()
	var parsed: Dictionary = codec.parse_text(text)
	if not bool(parsed.get("ok", false)):
		return failure.call("cfg", String(parsed.get("error", "YAML 解析失败")), parsed.get("diagnostics", []))
	var cfg: Dictionary = parsed["cfg"]
	var diagnostics: Array = parsed.get("diagnostics", []).duplicate()
	var schema: RefCounted = SchemaScript.new()
	if not schema.configure():
		return failure.call("schema", schema.last_error, [])
	var checked: Dictionary = schema.validate(cfg)
	diagnostics.append_array(checked.get("diagnostics", []))
	var metadata: Dictionary = IdentityMetaScript.load_metadata() if identity_meta_path.is_empty() else IdentityMetaScript.load_metadata(identity_meta_path)
	var supported: Variant = metadata.get("supported_schema_versions", null)
	if not supported is Array or supported.is_empty():
		return failure.call("metadata", "身份元数据缺失或未登记 supported_schema_versions", [])
	# 版本判定只认「字符串且形如 X.Y」。非字符串（未加引号的 9.9 会被解析成 float）、
	# 空值、null、"null" 一律判非法 —— 否则它们的类型诊断会被下面的枚举剔除一起洗白。
	var raw: Variant = cfg.get("schema_version", null)
	var declared: String = raw if raw is String else ""
	var missing: bool = not cfg.has("schema_version") or raw == null \
		or (raw is String and declared.strip_edges().is_empty())
	var version_parts: PackedStringArray = declared.split(".")
	var well_formed: bool = version_parts.size() == 2 \
		and _is_version_part(version_parts[0]) and _is_version_part(version_parts[1])
	var invalid_text: bool = (not missing) and ((not raw is String) or not well_formed)
	var version_supported: bool = false
	if not missing and not invalid_text:
		version_supported = supported.has(declared)
	if not missing and not invalid_text and not version_supported:
		# 版本不受支持：**只**剔除「版本枚举不匹配」这一条（expected 以「枚举」开头且 actual 等于声明值），
		# 其余结构/类型诊断一律保留。
		var kept: Array = []
		for entry in diagnostics:
			var is_enum_mismatch: bool = str(entry.get("path")) == "schema_version" \
				and str(entry.get("expected")).begins_with("枚举") \
				and str(entry.get("actual")) == declared
			if is_enum_mismatch:
				continue
			kept.append(entry)
		diagnostics = kept
	if missing or invalid_text:
		var version_diagnostic: RefCounted = Diagnostic.new()
		version_diagnostic.rule_id = "API"
		version_diagnostic.code = "SCHEMA_VERSION_MISSING" if missing else "SCHEMA_VERSION_INVALID"
		version_diagnostic.path = "schema_version"
		version_diagnostic.actual = str(raw)
		version_diagnostic.expected = "必须显式声明形如 X.Y 的 schema_version 字符串"
		version_diagnostic.hint = "版本缺失或形态非法时无法判定兼容性，按阻止保存处理"
		diagnostics.append(version_diagnostic)
	var blocking: bool = not diagnostics.is_empty()
	# data 为既有 UI 消费的增量别名（U-37 第 3 条只增键），给副本：调用方改 data 不得污染 cfg。
	var alias: Dictionary = cfg.duplicate(true)
	return {"ok": not blocking, "openable": true, "cfg": cfg, "data": alias, "path": path,
		"diagnostics": diagnostics,
		"error": "" if not blocking else "CFG 存在结构或类型问题，详见 diagnostics",
		"fingerprint": text.sha256_text(), "bytes": text.to_utf8_buffer().size(),
		"schema_version": declared, "version_supported": version_supported,
		"read_only": not version_supported}

# 职责：校验并保存技能 CFG；参数：path 为目标路径、cfg 为定义；返回：统一结果包；对应真源：第 16.1、14 章。
# T-081（U-37 填桩授权）：结构 + Schema 双重前置校验通过后才落盘，禁止「先保存再补校验」。
# 语义校验（V-001…V-084）依赖调用方 context，仍走 validate_with_context；本入口只保证「落盘前不可能写出结构/类型非法的 CFG」。
func save_cfg(path: String, cfg: Dictionary) -> Dictionary:
	var failure: Callable = func(field: String, message: String, diagnostics: Array) -> Dictionary:
		if not diagnostics.is_empty():
			return {"ok": false, "path": field, "error": message, "diagnostics": diagnostics}
		var diagnostic: RefCounted = Diagnostic.new()
		diagnostic.rule_id = "API"
		diagnostic.code = "SAVE_REJECTED"
		diagnostic.path = field
		diagnostic.actual = path
		diagnostic.expected = message
		diagnostic.hint = message
		return {"ok": false, "path": field, "error": message, "diagnostics": [diagnostic]}
	if path.strip_edges().is_empty():
		return failure.call("path", "保存路径不能为空", [])
	var structural: Array = CodecScript.validate_structure(cfg)
	if not structural.is_empty():
		return failure.call("cfg", "CFG 结构不合法，拒绝保存", structural)
	var schema: RefCounted = SchemaScript.new()
	if not schema.configure():
		return failure.call("schema", schema.last_error, [])
	var checked: Dictionary = schema.validate(cfg)
	if not checked["ok"]:
		return failure.call("cfg", "CFG 不符合 Schema，拒绝保存", checked["diagnostics"])
	var codec: RefCounted = CodecScript.new()
	var text: String = codec.encode(cfg)
	if text.is_empty():
		return failure.call("cfg", "序列化器返回空文本，拒绝写入（codec 结构校验已通过，属序列化层异常）", [])
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return failure.call("path", "无法写入 CFG（%s）: %s" % [error_string(FileAccess.get_open_error()), path], [])
	file.store_string(text)
	file.flush()
	var write_error: int = file.get_error()
	file.close()
	if write_error != OK:
		return failure.call("path", "CFG 写入失败（%s）: %s" % [error_string(write_error), path], [])
	return {"ok": true, "path": path, "error": "", "diagnostics": [],
		"fingerprint": text.sha256_text(), "bytes": text.to_utf8_buffer().size(),
		"validation_scope": "structure+schema", "requires_semantic_validation": true}

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

# Narrow validation entry: callers must provide the real validation facts explicitly.
# The frozen validate(cfg, stage) stub remains unchanged for legacy callers.
func validate_with_context(cfg: Dictionary, stage: StringName = STAGE_SAVE, context: Dictionary = {}) -> Dictionary:
	var failure: Callable = func(path: String, message: String) -> Dictionary:
		return {"ok": false, "path": path, "error": message, "diagnostics": []}
	var required_context: Array[Dictionary] = [
		{"key": "draft_revision", "type": "int"},
		{"key": "submitted_paths", "type": "Array"},
		{"key": "baseline_version_state", "type": "Dictionary"},
		{"key": "migration_state", "type": "Dictionary"},
		{"key": "probe_credentials", "type": "Dictionary"},
		{"key": "preview_fingerprint", "type": "Dictionary"}
	]
	for requirement in required_context:
		var key: String = str(requirement["key"])
		if not context.has(key):
			return failure.call("context." + key, "调用方必须显式提供 context." + key)
		var value: Variant = context[key]
		var expected: String = str(requirement["type"])
		if expected == "int" and not value is int:
			return failure.call("context." + key, "context.%s 必须是 int" % key)
		if expected == "Array" and not value is Array:
			return failure.call("context." + key, "context.%s 必须是 Array" % key)
		if expected == "Dictionary" and not value is Dictionary:
			return failure.call("context." + key, "context.%s 必须是 Dictionary" % key)
	var cross_card_present: bool = context.has("cross_card_facts") or context.has("assembly_facts") or context.has("cross_card")
	if not cross_card_present:
		return failure.call("context.cross_card_facts", "调用方必须显式提供跨卡事实 context.cross_card_facts/assembly_facts/cross_card")

	var load_json: Callable = func(path: String) -> Dictionary:
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file == null:
			return {}
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		return parsed if parsed is Dictionary else {}
	var identity: Variant = IdentityRulesScript.new()
	var types: Variant = TypesRulesScript.new()
	var modifier: Variant = ModifierRulesScript.new()
	var presentation: Variant = PresentationRulesScript.new()
	var identity_metadata: Dictionary = IdentityMetaScript.load_metadata()
	var params_metadata: Dictionary = load_json.call("res://data/params_meta.json")
	var presentation_metadata: Dictionary = load_json.call("res://data/presentation_meta.json")
	if identity_metadata.is_empty() or params_metadata.is_empty() or presentation_metadata.is_empty():
		return failure.call("validator.metadata", "真实校验元数据缺失")
	if not identity.configure(identity_metadata):
		return failure.call("validator.identity", identity.last_error)
	if not types.configure(params_metadata):
		return failure.call("validator.types", types.last_error)
	if not modifier.configure(params_metadata):
		return failure.call("validator.modifier", modifier.last_error)
	if not presentation.configure(presentation_metadata):
		return failure.call("validator.presentation", presentation.last_error)

	var card_table: Array[Dictionary] = [
		{"name": "identity", "card": identity, "first": 1, "last": 18},
		{"name": "types", "card": types, "first": 19, "last": 38},
		{"name": "modifier", "card": modifier, "first": 39, "last": 69},
		{"name": "presentation", "card": presentation, "first": 70, "last": 84}
	]
	var spec: Dictionary = {"cards": [], "groups": [], "stages": {}}
	for entry in card_table:
		spec["cards"].append({"name": entry["name"], "card": entry["card"]})
		spec["groups"].append({"first": entry["first"], "last": entry["last"], "card": entry["name"], "stages": []})
	var stage_keys: Array[StringName] = [STAGE_FILLING, STAGE_CARD, STAGE_ASSEMBLY, STAGE_SAVE, STAGE_LOAD, STAGE_PREVIEW]
	var all_groups: Array[int] = [0, 1, 2, 3]
	for stage_key in stage_keys:
		spec["stages"][stage_key] = all_groups.duplicate()
	var validator: Variant = ValidatorScript.new()
	if not validator.configure(spec):
		return failure.call("validator", validator.last_error)
	return validator.validate(cfg, stage, context)
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
# Narrow host-adapter entry for M6. The frozen create_sim contract remains
# unchanged; runtime targets and settlement handlers stay outside CFG.
func create_sim_with_hosts(cfg: Dictionary, seed: int = 0, hosts: Dictionary = {}) -> Dictionary:
	var failure: Callable = func(path: String, message: String) -> Dictionary:
		return {"ok": false, "path": path, "error": message, "diagnostics": []}
	var diagnostics: Array = CodecScript.validate_structure(cfg)
	if not diagnostics.is_empty():
		return {"ok": false, "path": "cfg", "error": "CFG structure rejected", "diagnostics": diagnostics}
	var schema: RefCounted = SchemaScript.new()
	if not schema.configure():
		return failure.call("schema", schema.last_error)
	var checked: Dictionary = schema.validate(cfg)
	if not checked["ok"]:
		return {"ok": false, "path": "cfg", "error": "CFG schema rejected", "diagnostics": checked["diagnostics"]}
	if not hosts.has("targets") or not hosts["targets"] is Array:
		return failure.call("hosts.targets", "Explicit target roster array required")
	if not hosts.has("handlers") or not hosts["handlers"] is Dictionary:
		return failure.call("hosts.handlers", "Explicit settlement handler table required")
	var targets: Array = hosts["targets"].duplicate(true)
	var supplied_handlers: Dictionary = hosts["handlers"]
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
		var brick_id: Variant = brick.get("brick_id", null)
		var brick_path: String = "bricks[%d]" % index
		if not brick_id is String or not carriers.has(brick_id):
			return failure.call(brick_path + ".brick_id", "Brick is not registered in catalog")
		if brick["carrier"] != carriers[brick_id]:
			return failure.call(brick_path + ".carrier", "Carrier disagrees with catalog")
		if carriers[brick_id] != BodyScript.CARRIER_INDEPENDENT:
			continue
		var registration: Variant = brick.get("default_cfg", null)
		if not registration is Dictionary:
			return failure.call(brick_path + ".default_cfg", "Root registration must be an object")
		var template_id: Variant = registration.get("template_id", null)
		var shot_id: Variant = registration.get("shot_id", null)
		if not template_id is String or template_id.is_empty() or not shot_id is String or shot_id.is_empty():
			return failure.call(brick_path + ".default_cfg", "Explicit template_id and shot_id required")
		roots.append({"template_id": template_id, "shot_id": shot_id, "instance_id": "api:root:%d" % index})
	if roots.is_empty():
		return failure.call("bricks", "No catalog-classified independent root registration")
	var metadata_path: String = "res://data/params_meta.json"
	if not FileAccess.file_exists(metadata_path):
		return failure.call("hosts.handlers", "Missing part type metadata")
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	var enums: Variant = metadata.get("enums", null) if metadata is Dictionary else null
	var part_types: Variant = enums.get("part_type", null) if enums is Dictionary else null
	if not part_types is Array or part_types.is_empty():
		return failure.call("hosts.handlers", "Expected nonempty part_type registry")
	var handlers: Dictionary = {}
	for kind in part_types:
		if not kind is String or kind.is_empty():
			return failure.call("hosts.handlers", "Invalid registered part type")
		var handler: Variant = supplied_handlers.get(kind, null)
		if not handler is Callable or not handler.is_valid():
			return failure.call("hosts.handlers." + str(kind), "Missing valid settlement host adapter")
		handlers[kind] = handler
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
		var template_key: Variant = template.get("template_id", null)
		if not template_key is String or template_key.is_empty():
			return failure.call("params.templates", "Explicit template identity required")
		families[template_key] = template_key
	var options: Dictionary = {"seed": seed, "roots": roots, "handlers": handlers,
		"template_families": families, "derivation_bindings": {}, "targets": targets}
	for optional_key in ["project_config", "motion_inputs", "runtime_host"]:
		if hosts.has(optional_key):
			options[optional_key] = hosts[optional_key]
	var runner: RefCounted = RunnerScript.new()
	var started: Dictionary = runner.start(cfg, options)
	print("SkillApi.create_sim_with_hosts PreviewRunner.start: ", started)
	if not started["ok"]:
		return started
	return {"ok": true, "diagnostics": [], "sim": {"runner": runner}, "fingerprint": started["fingerprint"]}

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
