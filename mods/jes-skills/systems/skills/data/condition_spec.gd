# ConditionSpec（规格 §6 第 4 条 / §10 data/）：条件门 —— 水晶接入的第四个口子。
#
# 本文件**只定义机制，不定义任何水晶效果**（规格 §6 明文：「本规格不定义水晶的具体效果」）。
# 它回答一个问题：某个修饰符 / 标签源 / 行为改写，在**什么条件下**才生效。
#
# 为什么要独立成类而不是塞进 SupportGemData：
#   §6 明确禁止「把水晶逻辑写进 SupportGemData（会破坏两种来源的正交性）」。
#   条件是可复用的判定单元：辅助石、水晶、装备词缀都可以挂同一套条件。
#
# 扩展方式（水晶 v0.5 文档到位时）：
#   - 新增判定类型 → 在 Kind 里加一枚枚举 + matches() 分支，不新建类
#   - 组合语义固定为 **AND**（全部满足才生效）；需要 OR 时由调用方拆成多条 spec
#   - 上下文字段由调用方填（见 SkillInstance.condition_context()），
#     本类只读不猜 —— is_rare / is_initial 属于水晶概念，规格未定义来源
class_name ConditionSpec
extends Resource

enum Kind {
	ALWAYS = 0,             # 无条件（默认值；缺省即生效，不改变现有内容行为）
	HAS_TAG = 1,            # 技能 tags 含 tag
	NOT_HAS_TAG = 2,        # 技能 tags 不含 tag
	SKILL_IS_RARE = 3,      # 仅稀有技能（§6 举例）
	SKILL_IS_INITIAL = 4,   # 仅初始技能（§6 举例）
	SKILL_LEVEL_AT_LEAST = 5,   # 技能等级 >= threshold
	SLOT_EQUALS = 6,        # 槽位下标 == threshold（"仅武器栏第 3 格"这类）
}

@export var kind: int = Kind.ALWAYS
@export var tag: StringName = &""
@export var threshold: int = 0


## 求值。ctx 缺失的键按「条件不成立」处理（保守：拿不到证据就不生效）。
## ctx 约定键：
##   &"tags": Array[StringName]   &"is_rare": bool   &"is_initial": bool
##   &"level": int                &"slot_index": int
func matches(ctx: Dictionary) -> bool:
	match kind:
		Kind.ALWAYS:
			return true
		Kind.HAS_TAG:
			var tags: Array = ctx.get(&"tags", [])
			return tags.has(tag)
		Kind.NOT_HAS_TAG:
			var tags2: Array = ctx.get(&"tags", [])
			return not tags2.has(tag)
		Kind.SKILL_IS_RARE:
			return bool(ctx.get(&"is_rare", false))
		Kind.SKILL_IS_INITIAL:
			return bool(ctx.get(&"is_initial", false))
		Kind.SKILL_LEVEL_AT_LEAST:
			return int(ctx.get(&"level", 0)) >= threshold
		Kind.SLOT_EQUALS:
			return int(ctx.get(&"slot_index", -1)) == threshold
	push_error("ConditionSpec：未知 kind %d" % kind)
	return false


## AND 语义：全部满足才生效。空数组 = 无条件下生效（不改变现有内容）。
static func all_match(conds: Array, ctx: Dictionary) -> bool:
	for c in conds:
		if c == null:
			continue
		if not (c as ConditionSpec).matches(ctx):
			return false
	return true


## 静态工厂（构造测试与将来水晶内容用，避免到处手填枚举）
static func always() -> ConditionSpec:
	return _make(Kind.ALWAYS)


static func has_tag(p_tag: StringName) -> ConditionSpec:
	var c := _make(Kind.HAS_TAG)
	c.tag = p_tag
	return c


static func not_has_tag(p_tag: StringName) -> ConditionSpec:
	var c := _make(Kind.NOT_HAS_TAG)
	c.tag = p_tag
	return c


static func is_rare() -> ConditionSpec:
	return _make(Kind.SKILL_IS_RARE)


static func is_initial() -> ConditionSpec:
	return _make(Kind.SKILL_IS_INITIAL)


static func level_at_least(n: int) -> ConditionSpec:
	var c := _make(Kind.SKILL_LEVEL_AT_LEAST)
	c.threshold = n
	return c


static func slot_equals(i: int) -> ConditionSpec:
	var c := _make(Kind.SLOT_EQUALS)
	c.threshold = i
	return c


static func _make(k: int) -> ConditionSpec:
	var c := ConditionSpec.new()
	c.kind = k
	return c
