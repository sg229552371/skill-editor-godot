extends GutTest

## 判据 P3（免费接口）在背包系统上的检验。
##
## 【P3 免费接口】技能系统的表述是：新增一颗技能/辅助宝石，**不改任何 .gd**。
## 背包系统对应的检验是：新增一种物品，**不改任何 .gd**。
##
## 这条判据不成立的条件很具体：
##   ① 某类物品需要容器认识它的类型（例如"遗物必须放右上角"）→ 容器里出现 if item_type == ...
##   ② 某类物品需要代码特判（例如"卷轴不能叠"）→ 本该写成 max_stack=1
##   ③ 某类物品的占格口径写在代码里而不是 .tres 里
## 本文件把 ①②③ 逐一反向检查：只要容器代码里出现对具体 item_id 的引用，就红。
##
## 注意：本测试**故意不列举具体 item_id**。列举本身就会变成"新增物品要改测试"，
## 那就等于没做到免费接口。

const ITEM_DIR := "res://mods/jes-inventory/content/items"
const CODE_DIR := "res://mods/jes-inventory/systems"
## 允许被代码引用的 id 白名单为空——真的需要特判时，必须在这里登记理由。
const ID_IN_CODE_ALLOW: Array[String] = []


func _all_items() -> Array[ItemData]:
	var out: Array[ItemData] = []
	var d := DirAccess.open(ITEM_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if not String(f).ends_with(".tres"):
			continue
		var res := load("%s/%s" % [ITEM_DIR, String(f)])
		if res is ItemData:
			out.append(res as ItemData)
	return out


func _all_code_lines() -> Array:
	# 返回 [[相对路径, 行号, 行内容], ...]
	var out: Array = []
	_collect_code(CODE_DIR, out)
	return out


func _collect_code(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		var name := String(f)
		if not name.ends_with(".gd"):
			continue
		var path := "%s/%s" % [dir_path, name]
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			out.append([path, i + 1, lines[i]])
	for sub in d.get_directories():
		if String(sub).begins_with("."):
			continue
		_collect_code("%s/%s" % [dir_path, String(sub)], out)


func test_item_dir_is_not_empty() -> void:
	assert_gt(_all_items().size(), 0, "content/items 下没有 .tres，P3 等于没测")


func test_no_item_id_hardcoded_in_systems() -> void:
	# 免费接口的核心断言：容器不认识任何具体物品。
	var items := _all_items()
	var bad: Array[String] = []
	for rec in _all_code_lines():
		var path: String = rec[0]
		var lineno: int = rec[1]
		var line: String = rec[2]
		for item in items:
			var id := String(item.item_id)
			if ID_IN_CODE_ALLOW.has(id):
				continue
			# 用词边界式的粗判：代码里出现 "herb" / &"herb" / 'herb'
			if line.contains("\"%s\"" % id) or line.contains("'%s'" % id):
				bad.append("%s:%d  %s" % [path.get_file(), lineno, line.strip_edges()])
	assert_eq(
		bad.size(), 0,
		"容器代码里出现了具体 item_id，免费接口判据 P3 破裂。\n"
		+ "若确需特判，请在 ID_IN_CODE_ALLOW 登记并写明理由：\n" + "\n".join(bad)
	)


func test_item_count_does_not_affect_code() -> void:
	# 「新增物品不改代码」的可测代理：代码文件总行数不随物品数量增长。
	# 直接断言"行数不变"会变成又一个要手工维护的常量，故改为**结构性断言**：
	# 容器只以 ItemData 类型读写，从不用字符串构造物品。
	var bad: Array[String] = []
	for rec in _all_code_lines():
		var line: String = rec[2]
		# ItemData.new() 在运行时凭空造物品 = 绕过 .tres 真源
		if line.contains("ItemData.new("):
			bad.append("%s:%d  %s" % [String(rec[0]).get_file(), int(rec[1]), line.strip_edges()])
	assert_eq(bad.size(), 0, "代码里凭空构造 ItemData（应只从 .tres 加载）：\n" + "\n".join(bad))


func test_assets_load_through_resource_loader_only() -> void:
	# 反证：每个 .tres 都能被 ResourceLoader 正常加载成 ItemData。
	# 这一条塌了，上面两条的"零代码新增"就没有意义（数据根本读不进来）。
	for item in _all_items():
		assert_ne(item.resource_path, "", "物品没有资源路径（不是从 .tres 加载的？）")
		assert_true(ResourceLoader.exists(item.resource_path), "资源不存在：%s" % item.resource_path)
		var again := load(item.resource_path)
		assert_true(again is ItemData, "%s 加载后不是 ItemData" % item.resource_path)
		assert_eq((again as ItemData).item_id, item.item_id, "%s 两次加载 id 不一致" % item.resource_path)
