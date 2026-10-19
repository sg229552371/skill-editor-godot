# SocketGraph（规格 §5.2）：插槽连通分量 + 装配纯函数（自研层，无参考实现）。
#
# 装配六步（规格 §3.3，顺序不可交换）：
#   1. 兼容判定（allowed_support_tags × require_tags / exclude_tags）
#   2. add_tags 多轮收敛（靠前辅助可"打开"靠后辅助的兼容性）
#   3. 逐个辅助注入 stat_modifiers（source_id = support_id，由注入方填写）
#   4. behavior_overrides：加法先合并，乘法后合并
#   5. cost = Π(cost_multiplier)
#   6. conflicts_with 检查，命中即装配失败、回滚全部注入
#
# 硬门禁：禁止出现任何 if gem_id == / if support_id == 分支（规格 §11）。
# 硬规则：装配结果只含数据、不持 Node；装配是纯函数，可缓存
#（key = (gem_id, level, support_ids 排序后哈希) —— 缓存层后续接，先保证正确）。
class_name SocketGraph
extends RefCounted

const AssemblyResultScript := preload("res://mods/jes-skills/systems/skills/assembly_result.gd")


static func _find(parent: Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]  # 路径减半
		i = parent[i]
	return i


static func _union(parent: Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb


## 装配纯函数：SkillSlot → AssemblyResult。
static func assemble(slot: SkillSlot) -> AssemblyResult:
	var res: AssemblyResult = AssemblyResultScript.new()

	if slot.active_gem == null:
		res.error_code = AssemblyResult.ErrorCode.ERR_NO_ACTIVE_GEM
		return res

	# ---------- 并查集分组 ----------
	var groups := _build_groups(slot.links, slot.supports.size())
	var any_ok := false
	for group in groups:
		var sub := _assemble_group(slot, group)
		if sub.ok:
			any_ok = true
			_merge_result(res, sub)
		elif sub.error_code == AssemblyResult.ErrorCode.ERR_INCOMPATIBLE_SUPPORT \
				or sub.error_code == AssemblyResult.ErrorCode.ERR_CONFLICT:
			# 兼容/冲突失败必须整体失败（G7：不得静默忽略）
			return sub
		# ERR_NO_ACTIVE_GEM 的空组（全辅助组无主动石）属于合法结构：辅助不生效，跳过
	if not any_ok:
		# 没有任何含主动宝石的组：视为无可装配内容（例如全辅助未连通），返回成功空结果
		pass
	res.ok = true  # 走到这里说明没有任何兼容/冲突失败（失败已在上面提前 return）
	return res


## 构建 groups：孔 0 = 主动宝石；孔 i+1 = supports[i]。links 里的下标即孔位。
## 契约：links 为空 = 全部孔位默认全连通（未显式断连的辅助都参与装配）。
static func _build_groups(links: Array, support_count: int) -> Array:
	var n := support_count + 1
	var parent: Array[int] = []
	parent.resize(n)
	for i in n:
		parent[i] = i
	if links.is_empty():
		# 默认全连通：所有孔并入同一分量
		for i in range(1, n):
			_union(parent, 0, i)
	for k in range(0, links.size() - 1, 2):
		var a := int(links[k])
		var b := int(links[k + 1])
		if a >= 0 and a < n and b >= 0 and b < n:
			_union(parent, a, b)
	var groups: Array = []
	var seen := {}
	for i in n:
		var root := _find(parent, i)
		if seen.has(root):
			continue
		seen[root] = true
		var g: Array[int] = []
		for j in n:
			if _find(parent, j) == root:
				g.append(j)
		groups.append(g)
	return groups


## 装配单个连通分量（六步全部在此，组内标签集独立收敛）
static func _assemble_group(slot: SkillSlot, group: Array) -> AssemblyResult:
	var res: AssemblyResult = AssemblyResultScript.new()
	var gem: SkillData = null
	var group_supports: Array[SupportGemData] = []

	for hole in group:
		if hole == 0:
			gem = slot.active_gem
		else:
			group_supports.append(slot.supports[hole - 1])

	if gem == null:
		res.error_code = AssemblyResult.ErrorCode.ERR_NO_ACTIVE_GEM
		return res

	# ---------- 六步 1+2：兼容判定 + add_tags 多轮收敛 ----------
	var effective: Array[StringName] = []
	effective.assign(gem.tags)
	var pending: Array[SupportGemData] = []
	for g in group_supports:
		pending.append(g)

	# 多轮收敛：每一轮尝试装配全部 pending，至少有一个通过则重复，直到一轮内无新增
	var accepted: Array[SupportGemData] = []
	while not pending.is_empty():
		var progressed := false
		var still_pending: Array[SupportGemData] = []
		for g in pending:
			if _compatible(gem, g, effective):
				progressed = true
				accepted.append(g)
				for t in g.add_tags:
					if not effective.has(t):
						effective.append(t)
			else:
				still_pending.append(g)
		if not progressed:
			# 一整轮无新增 → 剩余全部不兼容，取第一个报告（确定性）
			res.error_code = AssemblyResult.ErrorCode.ERR_INCOMPATIBLE_SUPPORT
			res.error_support_id = still_pending[0].support_id
			return res
		pending = still_pending

	# ---------- 六步 3：注入 stat_modifiers（source_id 由注入方按 support 填写）----------
	for g in accepted:
		for spec in g.stat_modifiers:
			res.modifiers.append(spec.to_modifier())

	# ---------- 六步 4：behavior_overrides（加法先合并，乘法后合并）----------
	var adds := {}    # stat -> float（相加）
	var muls := {}    # stat -> float（连乘因子）
	var other := {}   # 非 add/mul 的覆盖原样合并（后者覆盖前者，同声明顺序）
	for g in accepted:
		for stat_key in g.behavior_overrides:
			var v = g.behavior_overrides[stat_key]
			if v is Dictionary and (v.has(&"add") or v.has(&"mul")):
				if v.has(&"add"):
					adds[stat_key] = float(adds.get(stat_key, 0.0)) + float(v[&"add"])
				if v.has(&"mul"):
					muls[stat_key] = float(muls.get(stat_key, 1.0)) * float(v[&"mul"])
			else:
				other[stat_key] = v
	for stat_key in adds:
		var entry := {}
		entry[&"add"] = adds[stat_key]
		res.behavior_overrides[stat_key] = entry
	for stat_key in muls:
		var entry2: Dictionary = res.behavior_overrides.get(stat_key, {})
		entry2[&"mul"] = muls[stat_key]
		res.behavior_overrides[stat_key] = entry2
	for stat_key in other:
		res.behavior_overrides[stat_key] = other[stat_key]

	# ---------- 六步 5：cost 连乘 ----------
	res.cost_multiplier = 1.0
	for g in accepted:
		res.cost_multiplier *= g.cost_multiplier

	# ---------- 六步 6：conflicts_with 独占检查（失败即回滚）----------
	for a in accepted:
		for b in accepted:
			if a == b:
				continue
			if a.conflicts_with.has(b.support_id):
				res.error_code = AssemblyResult.ErrorCode.ERR_CONFLICT
				res.error_support_id = a.support_id
				# 回滚 = 丢弃本组已组装的全部数据（res 不再被调用方采信）
				res.modifiers.clear()
				res.behavior_overrides.clear()
				return res

	res.effective_tags = effective
	res.ok = true
	return res


## 兼容判定（六步 1）：require 全具备 + exclude 不命中 + 主动石 allowed 白名单
static func _compatible(gem: SkillData, g: SupportGemData, effective_tags: Array[StringName]) -> bool:
	for t in g.require_tags:
		if not effective_tags.has(t):
			return false
	for t in g.exclude_tags:
		if effective_tags.has(t):
			return false
	# allowed_support_tags 空数组 = 接受所有辅助
	if not gem.allowed_support_tags.is_empty():
		var allowed := false
		for t in g.require_tags:
			if gem.allowed_support_tags.has(t):
				allowed = true
				break
		if not allowed:
			return false
	return true


## 多组结果合并到主结果
static func _merge_result(main: AssemblyResult, sub: AssemblyResult) -> void:
	for m in sub.modifiers:
		main.modifiers.append(m)
	for stat_key in sub.behavior_overrides:
		main.behavior_overrides[stat_key] = sub.behavior_overrides[stat_key]
	for t in sub.effective_tags:
		if not main.effective_tags.has(t):
			main.effective_tags.append(t)
	main.cost_multiplier *= sub.cost_multiplier
	for f in sub.flags:
		if not main.flags.has(f):
			main.flags.append(f)
