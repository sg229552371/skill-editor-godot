# 记忆图谱门禁（《项目记忆图谱与证据链 v1》§七 / §八、决策 D-20）。
#
# 目的：让"依据"这件事可被机器检验。三条断言分别防三种腐烂：
#   1. 图谱文件丢了 / 被改名          → 后来者没有入口，只能靠猜
#   2. 台账新增 D-* 却没进图谱        → 决策成了孤儿，没人知道它挂在哪
#   3. 图谱引用了不存在的文件         → **编造依据**，这是证据链最常见的死法
#
# 第 3 条最要紧：引用一个不存在的路径，文字读起来和真依据一模一样，
# 人工 review 抓不住；只有机器能稳定拦住。
extends GutTest

const DOCS_DIR := "res://mods/jes-skills/docs"
const GRAPH_PATH := "res://mods/jes-skills/docs/项目记忆图谱与证据链_v1.md"
const LEDGER_PATH := "res://mods/jes-skills/docs/踩坑与决策台账.md"

## 图谱至少要有这么多节点；只增不减，删节点等于删历史。
const MIN_NODES := 9

const DECISION_PATTERN := "D-[0-9][0-9]"
## 路径字符集：字母数字下划线点斜杠连字符 + CJK（本项目文件名是中文）。
const PATH_PATTERN := "res://[A-Za-z0-9_./\\-\\x{4e00}-\\x{9fff}]+"


func _read(path: String) -> String:
	assert_true(FileAccess.file_exists(path), "文件必须存在：%s" % path)
	return FileAccess.get_file_as_string(path)


func _match_all(pattern: String, text: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		assert_true(false, "正则必须可编译：%s" % pattern)
		return out
	for m in re.search_all(text):
		out.append(m.get_string())
	return out


func test_graph_exists_and_has_nodes() -> void:
	var text := _read(GRAPH_PATH)
	assert_gt(text.length(), 1000, "图谱内容不能为空壳")
	var nodes: Array[String] = []
	for n in _match_all("N[0-9][0-9]", text):
		if not nodes.has(n):
			nodes.append(n)
	assert_gte(nodes.size(), MIN_NODES, "图谱节点数不得少于 %d（只增不减）" % MIN_NODES)


func test_every_decision_is_mounted_on_graph() -> void:
	# 台账里的每条 D-* 都必须能在图谱里找到挂载点。
	# 找不到 = 这条决策没有历史位置，后来者无法判断它是否还成立。
	var decisions: Array[String] = []
	for d in _match_all(DECISION_PATTERN, _read(LEDGER_PATH)):
		if not decisions.has(d):
			decisions.append(d)

	var graph := _read(GRAPH_PATH)
	var orphans: Array[String] = []
	for d in decisions:
		if not graph.contains(d):
			orphans.append(d)

	assert_eq(
		orphans.size(), 0,
		"下列决策未挂载到《项目记忆图谱与证据链 v1》§三：\n" + ", ".join(orphans)
	)


func test_all_res_references_resolve() -> void:
	# 图谱里每个 res:// 引用都必须真实存在（文件或目录）。
	# 允许尾部标点，先剥掉再判。
	var graph := _read(GRAPH_PATH)
	var paths: Array[String] = _match_all(PATH_PATTERN, graph)
	assert_gt(paths.size(), 5, "图谱至少要引用 6 个真实路径，否则不构成证据链")

	var missing: Array[String] = []
	for raw in paths:
		var p := raw
		while p.length() > 0 and (p.ends_with(".") or p.ends_with("/")):
			p = p.substr(0, p.length() - 1)
		if p.is_empty():
			continue
		if FileAccess.file_exists(p):
			continue
		if DirAccess.dir_exists_absolute(p):
			continue
		if not missing.has(p):
			missing.append(p)

	assert_eq(
		missing.size(), 0,
		"图谱引用了不存在的路径（编造依据）：\n" + "\n".join(missing)
	)


func test_evidence_files_are_frozen_and_sourced() -> void:
	# docs/证据_*.md 是逐字摘录：必须自带冻结声明 + 可追溯来源。
	# 两者缺一，它就退化成"某个 AI 的转述"，不再是证据。
	var found := 0
	for f in DirAccess.get_files_at(DOCS_DIR):
		if not f.begins_with("证据_") or not f.ends_with(".md"):
			continue
		found += 1
		var text := FileAccess.get_file_as_string("%s/%s" % [DOCS_DIR, f])
		assert_true(text.contains("逐字摘录"), "证据文件必须标明【逐字摘录｜冻结】：%s" % f)
		assert_true(text.contains("冻结"), "证据文件必须含冻结声明：%s" % f)
		assert_true(text.contains("https://"), "证据文件必须写明可追溯来源 URL：%s" % f)

	assert_gt(found, 0, "至少要有一份 docs/证据_*.md 作为源头证据")
