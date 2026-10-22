# bag_core.gd 测试（从 tests/test_bag_core.mjs 移植，TDD 红→绿）
# 运行：godot --headless --path . --script res://mods/jes-bagrogue-inventory/tests/test_bag_core.gd
extends SceneTree

const BagCoreScript := preload("res://mods/jes-bagrogue-inventory/systems/bag_core.gd")

const CFG := {
	"A": {"cols": 7, "rows": 5},
	"B": {"cols": 6, "rows": 5},
	"BASE": {"atk": 10.0, "spd": 1.0, "crit": 5.0, "move": 100.0, "hp": 100.0},
}

var passed: int = 0
var failed: int = 0
var _cur_failed: bool = false


func _initialize() -> void:
	print("== bag_core 逻辑测试（Godot）==")

	t("初始化：道具占格登记（含多格）", func() -> void:
		var m := _core([_lay(_it("sword", 1, 2, {"atk": 8}), "A", 0, 0)])
		assert_eq(m.occupant_at("A", 0, 0), "sword")
		assert_eq(m.occupant_at("A", 0, 1), "sword")
	)

	t("属性汇总：只有 A 背包生效，B 背包不计入", func() -> void:
		var m := _core([
			_lay(_it("a1", 1, 1, {"atk": 8}), "A", 0, 0),
			_lay(_it("b1", 1, 1, {"atk": 100}), "B", 0, 0),
		])
		assert_eq(m.stats(CFG["BASE"])["atk"], 18.0, "B 包 +100 不得计入")
	)

	t("移动到空位：成功，占格更新", func() -> void:
		var m := _core([_lay(_it("x", 1, 1), "A", 3, 1)])
		var r := m.drop("x", "A", 6, 4)
		assert_true(r.placed and not r.bounced, "应放置成功")
		assert_eq(m.occupant_at("A", 6, 4), "x")
		assert_eq(m.occupant_at("A", 3, 1), "")
	)

	t("移动出界：弹回原位，占格不变", func() -> void:
		var m := _core([_lay(_it("x", 1, 1), "A", 3, 1)])
		var r := m.drop("x", "A", 6, 5)  # 行 5 越界（rows=5）
		assert_true(r.bounced and not r.placed, "应弹回")
		assert_eq(m.occupant_at("A", 3, 1), "x")
		assert_eq(m.occupant_at("A", 6, 5), "")
	)

	t("互换：1x1 换 1x1，双方锚点交换", func() -> void:
		var m := _core([
			_lay(_it("p", 1, 1), "A", 5, 3),
			_lay(_it("q", 1, 1), "A", 3, 1),
		])
		var r := m.drop("p", "A", 3, 1)
		assert_true(r.placed and r.swapped, "应互换成功")
		assert_eq(m.occupant_at("A", 3, 1), "p")
		assert_eq(m.occupant_at("A", 5, 3), "q")
	)

	t("互换失败（对方在新锚放不下）：双方弹回，占格不变", func() -> void:
		# q 是 1x3 竖条在 (0,0)-(0,2)；p 1x1 在 (6,4) 角落
		var m := _core([
			_lay(_it("q", 1, 3), "A", 0, 0),
			_lay(_it("p", 1, 1), "A", 6, 4),
		])
		var r := m.drop("p", "A", 0, 1)  # 拖 p 盖住 q 中段
		# q 要搬去 p 的旧锚 (6,4)：需 (6,4)(6,5)(6,6) → 越界，换不动
		assert_true(r.bounced and not r.placed and not r.swapped, "应整体弹回")
		assert_eq(m.occupant_at("A", 6, 4), "p")
		assert_eq(m.occupant_at("A", 0, 1), "q")
	)

	t("落点压住两个道具：不互换，弹回", func() -> void:
		var m := _core([
			_lay(_it("x", 1, 1), "A", 0, 0),
			_lay(_it("y", 1, 1), "A", 1, 0),
			_lay(_it("z", 2, 1), "A", 4, 0),
		])
		var r := m.drop("z", "A", 0, 0)  # 压住 x、y 两个
		assert_true(r.bounced and not r.placed, "应弹回")
		assert_eq(m.occupant_at("A", 4, 0), "z")
	)

	t("跨包拖动：生效状态随包切换（A→B 属性降，B→A 属性升）", func() -> void:
		var m := _core([_lay(_it("x", 1, 1, {"atk": 3}), "A", 3, 1)])
		assert_eq(m.stats(CFG["BASE"])["atk"], 13.0)
		m.drop("x", "B", 0, 0)
		assert_eq(m.stats(CFG["BASE"])["atk"], 10.0, "进 B 包应失效")
		assert_eq(m.occupant_at("B", 0, 0), "x")
		m.drop("x", "A", 6, 4)
		assert_eq(m.stats(CFG["BASE"])["atk"], 13.0, "回 A 包应重新生效")
	)

	t("互换可跨包进行", func() -> void:
		var m := _core([
			_lay(_it("p", 1, 1), "A", 3, 1),
			_lay(_it("q", 1, 1), "B", 2, 2),
		])
		var r := m.drop("p", "B", 2, 2)
		assert_true(r.placed and r.swapped, "应跨包互换成功")
		assert_eq(m.occupant_at("B", 2, 2), "p")
		assert_eq(m.occupant_at("A", 3, 1), "q")
	)

	t("负属性道具：生效时扣减，失效时还原", func() -> void:
		var m := _core([_lay(_it("curse", 1, 1, {"hp": -15}), "A", 0, 4)])
		assert_eq(m.stats(CFG["BASE"])["hp"], 85.0)
		m.drop("curse", "B", 0, 0)
		assert_eq(m.stats(CFG["BASE"])["hp"], 100.0)
	)

	print("\n结果：%d 通过 / %d 失败" % [passed, failed])
	quit(1 if failed > 0 else 0)


# ---------- 测试辅助 ----------

## 道具定义：{id, w, h, stats}
func _it(id: String, w: int, h: int, stats: Dictionary = {}) -> Dictionary:
	return {"id": id, "w": w, "h": h, "stats": stats}


## 布局条目：{def, bag, x, y}
func _lay(def: Dictionary, bag: String, x: int, y: int) -> Dictionary:
	return {"def": def, "bag": bag, "x": x, "y": y}


func _core(layout: Array) -> BagCoreScript:
	return BagCoreScript.new(CFG, layout)


## 运行一个用例；首个断言失败后剩余断言静默跳过（防连锁误报）
func t(name: String, fn: Callable) -> void:
	_cur_failed = false
	fn.call()
	if _cur_failed:
		failed += 1
	else:
		passed += 1
		print("  ✔ " + name)


func assert_true(cond: bool, msg: String = "") -> void:
	if not cond and not _cur_failed:
		_cur_failed = true
		print("  ✘ " + msg)


func assert_eq(got, want, msg: String = "") -> void:
	if not _approx(got, want) and not _cur_failed:
		_cur_failed = true
		print("  ✘ %s —— 期望 %s，实际 %s" % [msg, str(want), str(got)])


func _approx(a, b) -> bool:
	if a is float and b is float:
		return absf(a - b) < 0.001
	return a == b
