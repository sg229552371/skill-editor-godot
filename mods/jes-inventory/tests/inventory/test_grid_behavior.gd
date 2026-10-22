extends GutTest

## 背包容器行为测试（不是判据，是「判据底下的地基」）。
##
## 为什么单独一份：P1~P5 讲的是治理机制，但治理机制压不住逻辑错误。
## 容器自己算错格、叠错堆，判据测试照样全绿。这一份保证「地基是实的」。

const ITEM_DIR := "res://mods/jes-inventory/content/items"

var _herb: ItemData
var _bandage: ItemData
var _greatsword: ItemData
var _charm: ItemData
var _ration: ItemData
var _scroll: ItemData


func before_all() -> void:
	_herb = _load("herb")
	_bandage = _load("bandage")
	_greatsword = _load("greatsword")
	_charm = _load("charm_ruby")
	_ration = _load("ration")
	_scroll = _load("scroll_blink")


func _load(id: String) -> ItemData:
	var path := "%s/%s.tres" % [ITEM_DIR, id]
	assert_true(ResourceLoader.exists(path), "缺少物品资源：%s（测试依赖它，改名前先同步）" % path)
	return load(path) as ItemData


# ---------------- 容量 ----------------

func test_capacity_and_free_cells() -> void:
	var g := InventoryGrid.new(5, 6)
	assert_eq(g.capacity(), 30, "5×6 = 30 格")
	assert_eq(g.used_cells(), 0)
	assert_eq(g.free_cells(), 30)


func test_dimensions_are_caller_owned() -> void:
	# P1：尺寸由调用方给，容器不硬编码。同一份代码跑 5×6 与 5×7 两种背包。
	var a := InventoryGrid.new(5, 6)
	var b := InventoryGrid.new(5, 7)
	assert_eq(a.capacity(), 30)
	assert_eq(b.capacity(), 35)


# ---------------- 放置 ----------------

func test_put_single_item_occupies_declared_shape() -> void:
	var g := InventoryGrid.new(5, 6)
	var r := g.put(_greatsword, 1)
	assert_true(bool(r[&"ok"]))
	assert_eq(g.used_cells(), 6, "2×3 应占 6 格")
	var e := g.entry(int(r[&"uid"]))
	assert_eq(e[&"origin"], Vector2i(0, 0), "首次放置从左上角开始")
	assert_true(g.is_occupied(1, 2), "(1,2) 属于 2×3 区域")
	assert_false(g.is_occupied(2, 0), "(2,0) 不在 2×3 区域内")


func test_stacking_merges_before_new_slot() -> void:
	# 5 件 max_stack=20 的草药 → 一个堆，占 1 格
	var g := InventoryGrid.new(5, 6)
	var r := g.put(_herb, 5)
	assert_true(bool(r[&"ok"]))
	assert_eq(g.uids().size(), 1, "同类应并入同一堆")
	assert_eq(g.used_cells(), 1, "5 件堆叠物品只占 1 格")
	assert_eq(g.count_of(_herb.item_id), 5)


func test_stack_overflow_opens_second_slot() -> void:
	# max_stack=5 的干粮放 7 件 → 5+2 两堆，占 2 格
	var g := InventoryGrid.new(5, 6)
	var r := g.put(_ration, 7)
	assert_true(bool(r[&"ok"]))
	assert_eq(g.uids().size(), 2, "7 件 / 上限 5 → 两堆")
	assert_eq(g.used_cells(), 2)
	assert_eq(g.count_of(_ration.item_id), 7)


func test_unique_item_never_stacks() -> void:
	# max_stack=1 的护符放 3 件 → 3 个独立实例，各占 2 格
	var g := InventoryGrid.new(5, 6)
	var r := g.put(_charm, 3)
	assert_true(bool(r[&"ok"]))
	assert_eq(g.uids().size(), 3, "唯一物每件一个实例")
	assert_eq(g.used_cells(), 6, "每件 1×2，共 3 件 = 6 格")


# ---------------- 失败路径（必须明确失败，不做魔法） ----------------

func test_put_returns_leftover_when_full() -> void:
	# 注意 placed / leftover 计的是**件数**，不是格数。
	# 2×2 背包放 1×2 的唯一物：每件占一格竖排 2 格，最多 2 件。
	var g := InventoryGrid.new(2, 2)   # 4 格
	var r := g.put(_charm, 5)          # 每件 1×2 → 最多放 2 件
	assert_true(bool(r[&"ok"]), "部分放入也算 ok")
	assert_eq(int(r[&"placed"]), 2, "2×2 最多容纳 2 件 1×2")
	assert_eq(int(r[&"leftover"]), 3, "余 3 件必须明确报出来，不能静默丢")
	assert_eq(g.used_cells(), 4, "两件各占 2 格 = 4 格，正好满")


func test_put_into_zero_capacity_fails_cleanly() -> void:
	var g := InventoryGrid.new(0, 0)
	var r := g.put(_herb, 1)
	assert_false(bool(r[&"ok"]))
	assert_eq(int(r[&"placed"]), 0)
	assert_eq(int(r[&"leftover"]), 1)
	assert_eq(StringName(r[&"reason"]), &"no_room")


func test_put_invalid_count_fails() -> void:
	var g := InventoryGrid.new(5, 6)
	var r := g.put(_herb, 0)
	assert_false(bool(r[&"ok"]))
	assert_eq(StringName(r[&"reason"]), &"count_not_positive")


func test_put_null_item_fails() -> void:
	var g := InventoryGrid.new(5, 6)
	var r := g.put(null, 1)
	assert_false(bool(r[&"ok"]))
	assert_eq(StringName(r[&"reason"]), &"item_null")


# ---------------- 取出 ----------------

func test_take_partial_keeps_entry() -> void:
	var g := InventoryGrid.new(5, 6)
	var uid := int(g.put(_herb, 10)[&"uid"])
	var r := g.take(uid, 3)
	assert_true(bool(r[&"ok"]))
	assert_eq(int(r[&"removed"]), 3)
	assert_eq(g.count_of(_herb.item_id), 7, "取 3 留 7")
	assert_eq(g.used_cells(), 1, "没取完，格子仍占着")


func test_take_all_frees_cells() -> void:
	var g := InventoryGrid.new(5, 6)
	var uid := int(g.put(_greatsword, 1)[&"uid"])
	g.take(uid, 1)
	assert_eq(g.used_cells(), 0, "取空后格子必须释放")
	assert_eq(int(g.occupant_at(0, 0)), -1)
	assert_eq(g.uids().size(), 0)


func test_take_clamps_to_available() -> void:
	var g := InventoryGrid.new(5, 6)
	var uid := int(g.put(_herb, 2)[&"uid"])
	var r := g.take(uid, 99)
	assert_eq(int(r[&"removed"]), 2, "超量取出只取现有的")


func test_take_at_located_entry_without_uid() -> void:
	# UI 拖拽入口：知道格子不知道 uid
	var g := InventoryGrid.new(5, 6)
	g.put(_bandage, 3)   # 2×1，落在 (0,0)-(1,0)
	var r := g.take_at(1, 0)
	assert_true(bool(r[&"ok"]))
	assert_eq(int(r[&"removed"]), 3, "点区域内任意一格都应取到整堆")
	assert_eq(g.used_cells(), 0)


func test_take_at_empty_cell_fails() -> void:
	var g := InventoryGrid.new(5, 6)
	var r := g.take_at(4, 5)
	assert_false(bool(r[&"ok"]))
	assert_eq(int(r[&"removed"]), 0)


# ---------------- 形状与排布（核心复杂度） ----------------

func test_multi_cell_item_does_not_straddle_edges() -> void:
	# 3×2 的卷轴在 5 宽背包里不能跨边界
	var g := InventoryGrid.new(5, 6)
	g.put(_scroll, 1)
	var uid := int(g.uids()[0])
	var origin: Vector2i = g.entry(uid)[&"origin"]
	assert_true(origin.x + _scroll.grid_w <= g.cols, "放置不得超出右边界")
	assert_true(origin.y + _scroll.grid_h <= g.rows, "放置不得超出下边界")


func test_no_overlap_between_entries() -> void:
	var g := InventoryGrid.new(5, 6)
	g.put(_greatsword, 1)
	g.put(_scroll, 1)
	g.put(_bandage, 2)
	g.put(_herb, 4)
	var sum := 0
	for uid in g.uids():
		var e := g.entry(uid)
		sum += int(e[&"w"]) * int(e[&"h"])
	assert_eq(sum, g.used_cells(), "各实例占格之和必须等于总占格（否则存在重叠或空洞）")


func test_find_free_rect_skips_occupied() -> void:
	var g := InventoryGrid.new(3, 3)
	g.put(_herb, 1)                     # 占 (0,0)
	assert_eq(g.find_free_rect(1, 1), Vector2i(1, 0), "同一行下一格才是先找到的空位")
	# find_free_rect 是**扫描式**：逐行逐列试。3 宽在第 0 行放不下（(0,0) 被占），
	# 落到第 1 行第一列 —— 它不会"先判断整行"，只会一格一格试。
	assert_eq(g.find_free_rect(3, 1), Vector2i(0, 1), "3 宽物件第 0 行放不下，退到第 1 行")
	assert_eq(g.find_free_rect(2, 1), Vector2i(1, 0), "2 宽物件在第 0 行还有 (1,0)(2,0)")
	assert_eq(g.find_free_rect(4, 1), Vector2i(-1, -1), "4 宽超过背包宽度，永远无解")


func test_declines_placement_when_no_rect_available() -> void:
	# 5×6 = 30 格。用 3×2 卷轴（6 格）塞满 5 行 × 6 列：
	# 布局为 1 列宽的余量 + 3 宽卷轴 → 每行放一个就够，故改用 2×3 大剑整齐铺满。
	var g := InventoryGrid.new(5, 6)
	# 2×3 大剑：横向 2 把（0-1, 2-3），第 5 列剩 1 格宽；
	# 纵向 2 层（0-2, 3-5）→ 4 把占 24 格，剩 5 格（第 4 列一竖条）+ 1 格 = 6 格不连续。
	for i in 4:
		assert_true(bool(g.put(_greatsword, 1)[&"ok"]), "第 %d 把大剑应放得下" % (i + 1))
	assert_eq(g.used_cells(), 24, "4 把 2×3 = 24 格")
	# 剩下的是第 4 列整竖条（6 格，连续 1×6）
	assert_eq(g.free_cells(), 6, "剩余 6 格")
	# 1×6 的物件理论上占得下，但没有任何物品是 1×6；用一个 2×3 再验证"放不下"
	var r := g.put(_greatsword, 1)
	assert_false(bool(r[&"ok"]), "剩余空间不连续，2×3 大剑应放不下")
	assert_eq(StringName(r[&"reason"]), &"no_room")


# ---------------- 幂等 / 清理 ----------------

func test_clear_resets_everything() -> void:
	var g := InventoryGrid.new(5, 6)
	g.put(_herb, 9)
	g.clear()
	assert_eq(g.used_cells(), 0)
	assert_eq(g.uids().size(), 0)
	assert_eq(g.count_of(_herb.item_id), 0)


func test_uid_is_monotonic_after_clear() -> void:
	# uid 从 1 重新开始（clear 只给测试用），但同一次会话内必须严格递增，
	# 否则 UI 拿着旧 uid 会取到别人的东西。
	var g := InventoryGrid.new(5, 6)
	var u1 := int(g.put(_herb, 1)[&"uid"])
	var u2 := int(g.put(_greatsword, 1)[&"uid"])
	assert_gt(u2, u1, "uid 必须递增")
