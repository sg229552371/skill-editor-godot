extends GutTest

## 判据 P1（单真源）+ P2（声明面）在背包系统上的检验。
##
## 【P1 单真源】要检验的不是「有没有文档」，而是「同一份事实有没有第二份可写的副本」。
## 技能系统的 P1 是「轴值 → behavior_id 的映射只在白名单矩阵里展开一次」；
## 背包系统对应的唯一事实是**物品占格尺寸**：它同时出现在
##   ① .tres 的 grid_w / grid_h（数据真源）
##   ② 容器里已占格的坐标集合（运行态缓存）
##   ③ 将来必然出现的 UI 图标尺寸（尚未写）
## 能自证的是 ①↔②：容器占格必须恒等于物品自声明的 w×h。
## 一旦哪天为了性能在容器里另存一份尺寸并允许它偏离，P1 在背包上就破了。
##
## 【P2 声明面】物品自己声明「占几格 / 能不能叠 / 尺寸合法吗」，
## 由机器（本测试）核对，而不是让容器在运行时 if 判空、判 0。

const ITEM_DIR := "res://mods/jes-inventory/content/items"


func _all_items() -> Array[ItemData]:
	var out: Array[ItemData] = []
	var d := DirAccess.open(ITEM_DIR)
	assert_not_null(d, "物品目录必须存在：%s" % ITEM_DIR)
	if d == null:
		return out
	var names: Array = d.get_files()
	for f in names:
		var name := String(f)
		if not name.ends_with(".tres"):
			continue
		var res := load("%s/%s" % [ITEM_DIR, name])
		if res is ItemData:
			out.append(res as ItemData)
	out.sort_custom(func(a: ItemData, b: ItemData): return a.item_id < b.item_id)
	return out


func test_item_dir_is_not_empty() -> void:
	# 空目录会让下面所有循环零次通过——「全绿但没测」比红更危险（技能模块 D-23 的教训）。
	assert_gt(_all_items().size(), 0, "content/items 下没有 .tres，判据测试等于没跑")


func test_every_item_declares_valid_geometry() -> void:
	# P2：自检由物品自己声明（validate()），测试只负责"全部调用一遍"。
	var bad: Array[String] = []
	for item in _all_items():
		var errs := item.validate()
		if not errs.is_empty():
			bad.append("%s → %s" % [item.item_id, ", ".join(errs)])
	assert_eq(bad.size(), 0, "物品自检不通过：\n" + "\n".join(bad))


func test_item_ids_are_unique() -> void:
	# 单真源的另一面：一个 item_id 只能对应一份声明。
	# 两份 .tres 写同一个 id 时，堆叠会串、覆盖会错，而运行时不会报错。
	var seen: Dictionary = {}
	var dup: Array[String] = []
	for item in _all_items():
		if seen.has(item.item_id):
			dup.append("%s（%s 与 %s）" % [item.item_id, seen[item.item_id], item.resource_path])
		seen[item.item_id] = item.resource_path
	assert_eq(dup.size(), 0, "item_id 重复：\n" + "\n".join(dup))


func test_file_name_matches_item_id() -> void:
	# 命名即索引：不看资源内容也能从文件名猜到 id，减少"打开才知道"的成本。
	var bad: Array[String] = []
	for item in _all_items():
		var base := item.resource_path.get_file().get_basename()
		if base != String(item.item_id):
			bad.append("%s ← 文件名 %s" % [item.item_id, base])
	assert_eq(bad.size(), 0, "文件名与 item_id 不一致：\n" + "\n".join(bad))


func test_container_cells_equal_declared_geometry() -> void:
	# P1 的硬断言：容器实际占格数 == 物品自声明格数。
	# 这是「数据真源 ↔ 运行态」之间唯一允许的连接方式（读，不允许另存副本）。
	for item in _all_items():
		var grid := InventoryGrid.new(10, 10)
		var r := grid.put(item, 1)
		assert_true(bool(r[&"ok"]), "%s 放不进 10×10 空背包" % item.item_id)
		assert_eq(
			grid.used_cells(), item.cell_count(),
			"%s 占用格数与声明不符（声明 %d×%d）" % [item.item_id, item.grid_w, item.grid_h]
		)
		# 逐格核对：不止数量对，形状也得对（防止"算对总数、摆错形状"）。
		var origin: Vector2i = grid.entry(int(r[&"uid"]))[&"origin"]
		for dy in item.grid_h:
			for dx in item.grid_w:
				assert_true(
					grid.is_occupied(origin.x + dx, origin.y + dy),
					"%s 在 (%d,%d) 应被占用" % [item.item_id, origin.x + dx, origin.y + dy]
				)
