## W2 反向导出（子代理 A）：把 67 个主动技能 + 13 个辅助石的「全部字段」导出成普通 JSON。
## 产物只写 _tmp/export.json（已加入 .gitignore，不入库）；不处理、不修改、不删除触发器。
##
## 跑法：
##   godot --headless --path . -s res://mods/jes-skills/tools/content_workbench/export/export_to_json.gd
##
## 字段清单严格以 systems/skills/data/*.gd 的 @export 声明为准（见下方常量），
## 并用 get_property_list() 做动态校验，任何字段增删都会立即报错停机，保证零丢失。
## 序列化规则：StringName→String、Dictionary 键排序、Array 保序、float 不做 snappedf 保真。
extends SceneTree

# —— @export 字段清单（只读契约：systems/skills/data/*.gd）——
const SKILL_FIELDS: PackedStringArray = [
	"gem_id", "display_name", "icon", "parts", "tags", "cast_mode",
	"base_cast_time", "cost_type", "base_cost", "base_cooldown",
	"max_charges", "charge_recharge_time", "level_scaling", "allowed_support_tags",
]
const PART_FIELDS: PackedStringArray = [
	"damage_channel", "base_damage", "damage_effectiveness", "behavior_id", "behavior_params",
]
const SUPPORT_FIELDS: PackedStringArray = [
	"support_id", "display_name", "require_tags", "require_any_tags",
	"add_tags", "exclude_tags", "cost_multiplier", "stat_modifiers",
	"behavior_overrides", "flags", "conflicts_with",
]
const MODIFIER_FIELDS: PackedStringArray = [
	"stat", "op", "value", "channel_mask", "require_tags", "exclude_tags",
]
const SCALING_FIELDS: PackedStringArray = ["per_level", "knee_level", "per_level_late"]

const OUT_PATH := "res://mods/jes-skills/tools/content_workbench/_tmp/export.json"


func _init() -> void:
	GemRegistry.reload()

	# 字段清单与运行时定义必须完全一致，否则停机，避免悄悄漏字段。
	if not _verify_fields():
		quit(1)
		return

	var skills: Array = []
	var supports: Array = []
	var source_files := {}

	# skills() / supports() 已按 id 排序，Array 天然保序；不遍历 triggers()。
	for s in GemRegistry.skills():
		skills.append(_dump_fields(s, SKILL_FIELDS))
		source_files[String(s.gem_id)] = s.resource_path.get_file()
	for g in GemRegistry.supports():
		supports.append(_dump_fields(g, SUPPORT_FIELDS))
		source_files[String(g.support_id)] = g.resource_path.get_file()

	var out := {
		"meta": {
			"skill_count": skills.size(),
			"support_count": supports.size(),
			"total": skills.size() + supports.size(),
		},
		# 文件名供 W2 自检核对「代号唯一且与文件名一致」，不参与逐字段比对。
		"source_files": _jsonify(source_files),
		"skills": skills,
		"supports": supports,
	}

	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("无法写入 %s" % OUT_PATH)
		quit(1)
		return
	# sort_keys=true 保证所有 Dictionary 键稳定有序；full_precision=true 保证 float 不做短精度截断。
	f.store_string(JSON.stringify(out, "  ", true, true))
	f.close()

	print("主动技能 %d 条 / 辅助石 %d 条 / 合计 %d 条" % [skills.size(), supports.size(), skills.size() + supports.size()])
	print("已写入 %s" % OUT_PATH)
	quit(0)


## 按给定清单逐字段导出为普通 Dictionary（值全部经 _jsonify 归一化）。
func _dump_fields(res: Resource, fields: PackedStringArray) -> Dictionary:
	var out := {}
	for field_name in fields:
		out[field_name] = _jsonify(res.get(field_name))
	return out


## 递归归一化：把引擎专属类型变成可稳定序列化、可跨语言比对的普通结构。
## 嵌套的数据类子资源（parts / level_scaling / stat_modifiers）同样按清单展开，
## 保证 SkillPart / GemLevelScaling / ModifierSpec 的全部字段一个不丢。
func _jsonify(v) -> Variant:
	if v is Dictionary:
		var out := {}
		var ks: Array = (v as Dictionary).keys()
		# 键统一按字符串字典序排，保证输出稳定（StringName 默认排序不保证字典序）。
		ks.sort_custom(func(a, b): return String(a) < String(b))
		for k in ks:
			out[String(k)] = _jsonify((v as Dictionary)[k])
		return out
	if v is Array:
		var out2: Array = []
		for e in (v as Array):
			out2.append(_jsonify(e))
		return out2
	if v is StringName:
		return String(v)
	if v is SkillData:
		return _dump_fields(v, SKILL_FIELDS)
	if v is SkillPart:
		return _dump_fields(v, PART_FIELDS)
	if v is SupportGemData:
		return _dump_fields(v, SUPPORT_FIELDS)
	if v is ModifierSpec:
		return _dump_fields(v, MODIFIER_FIELDS)
	if v is GemLevelScaling:
		return _dump_fields(v, SCALING_FIELDS)
	if v is Resource:
		# 非数据类资源（例如图标 Texture2D）只保留资源路径，不展开引擎内部属性。
		return String(v.resource_path)
	# int / float / String / bool / null：float 不做 snappedf，完整保留精度。
	return v


## 用 get_property_list() 动态核对清单是否覆盖全部脚本导出字段。
func _verify_fields() -> bool:
	var ok := true
	ok = _check(SkillData.new(), SKILL_FIELDS, "SkillData") and ok
	ok = _check(SkillPart.new(), PART_FIELDS, "SkillPart") and ok
	ok = _check(SupportGemData.new(), SUPPORT_FIELDS, "SupportGemData") and ok
	ok = _check(ModifierSpec.new(), MODIFIER_FIELDS, "ModifierSpec") and ok
	ok = _check(GemLevelScaling.new(), SCALING_FIELDS, "GemLevelScaling") and ok
	return ok


func _check(res: Resource, fields: PackedStringArray, cls: String) -> bool:
	var dynamic: Array[String] = []
	for p in res.get_property_list():
		if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var n := String(p.name)
		if n == "script":
			continue
		dynamic.append(n)

	var missing: Array[String] = []
	for f in fields:
		if not dynamic.has(f):
			missing.append(f)
	var extra: Array[String] = []
	for n in dynamic:
		if not fields.has(n):
			extra.append(n)

	if not missing.is_empty() or not extra.is_empty():
		push_error("%s 字段清单与运行时不一致：清单多出=%s，运行时多出=%s" % [cls, str(missing), str(extra)])
		return false
	print("%s 字段校验通过：%d 个 @export 字段全覆盖" % [cls, fields.size()])
	return true
