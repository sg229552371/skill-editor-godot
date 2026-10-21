# TagRegistry（规格 §3.5 / §10 util）：标签注册表 —— 全项目标签名的唯一真源。
#
# 为什么需要它：
#   辅助石靠「标签三元组」生效（§3.3），标签写错一个字，兼容判定就永远不通过，
#   而玩家看到的只是「这颗辅助装上没效果」。注册表 + 内容校验测试把这类错误挡在 CI。
#
# kind 的用途：
#   damage_type  伤害类型标签，参与元素归属（与 StatRegistry.ELEMENTS 对齐）
#   cast_type    施法类型（attack / spell）
#   form         形态与行为特征（melee / projectile / aoe / channel / movement / summon / buff）
#
# 硬规则：新增标签必须在这里注册，否则 `unknown_in()` 会把内容里的标签报出来。
class_name TagRegistry
extends RefCounted

const KIND_DAMAGE := &"damage_type"
const KIND_CAST := &"cast_type"
const KIND_FORM := &"form"

const DEFS := {
	# ---- 伤害类型（必须与 StatRegistry.ELEMENTS 一一对应）----
	&"physical": {&"kind": &"damage_type"},
	&"fire": {&"kind": &"damage_type"},
	&"cold": {&"kind": &"damage_type"},
	&"lightning": {&"kind": &"damage_type"},
	&"chaos": {&"kind": &"damage_type"},

	# ---- 施法类型 ----
	&"attack": {&"kind": &"cast_type"},
	&"spell": {&"kind": &"cast_type"},

	# ---- 形态与行为特征 ----
	&"melee": {&"kind": &"form"},
	&"projectile": {&"kind": &"form"},
	&"aoe": {&"kind": &"form"},
	&"channel": {&"kind": &"form"},
	&"movement": {&"kind": &"form"},
	&"summon": {&"kind": &"form"},
	&"buff": {&"kind": &"form"},
	# 预留：陷阱/预埋类（D-25 注册，尚无内容使用；契约参数 delay / zone_duration，启用前先过制作人裁定）
	&"trap": {&"kind": &"form"},
}


static func has_tag(tag: StringName) -> bool:
	return DEFS.has(tag)


static func kind_of(tag: StringName) -> StringName:
	if not DEFS.has(tag):
		push_error("TagRegistry：未注册的标签「%s」" % tag)
		return &""
	return DEFS[tag][&"kind"]


static func all_tags() -> Array:
	return DEFS.keys()


static func tags_of_kind(kind: StringName) -> Array:
	var out: Array = []
	for t in DEFS:
		if DEFS[t][&"kind"] == kind:
			out.append(t)
	return out


## 校验一组标签是否全部已注册；返回未注册的（空数组 = 全通过）
static func unknown_in(tags: Array) -> Array:
	var out: Array = []
	for t in tags:
		var key := StringName(t)
		if not DEFS.has(key) and not out.has(key):
			out.append(key)
	return out
