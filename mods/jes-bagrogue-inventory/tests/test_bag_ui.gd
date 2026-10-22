extends SceneTree

## bagrogue UI 冒烟测试（headless）
## 验证：场景实例化、道具节点、drop 落子/互换/弹回、liveDot、属性面板、TIPS
## 运行：
##   Godot --headless --path <项目> --script res://mods/jes-bagrogue-inventory/tests/test_bag_ui.gd

const UI_SCENE := "res://mods/jes-bagrogue-inventory/ui/bag_ui.tscn"

var _fails := 0
var _total := 0


func _initialize() -> void:
	# _initialize 阶段场景树还没开始跑，add_child 不会触发 _ready。
	# 挂到第一次 process_frame：此时树在运行中，add_child 会同步触发 _ready。
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var packed: PackedScene = load(UI_SCENE)
	_check(packed != null, "场景加载成功")
	if packed == null:
		_finish()
		return

	var ui: Control = packed.instantiate()
	root.add_child(ui)

	# 1. 实例化后结构完整
	_check(ui.core != null, "core 已创建")
	_check(ui.item_nodes.size() == 7, "道具节点数 = 7（LAYOUT 摆放 7 件，含异形 w09）")
	_check(ui.bag_panels.size() == 2, "背包面板数 = 2（A/B）")
	_check(ui.stats_labels.size() == 5, "属性标签数 = 5")

	# 2. 初始摆放与 LAYOUT 一致
	_check(ui.core.item_map["w01"]["bag"] == "A" and ui.core.item_map["w01"]["x"] == 0
			and ui.core.item_map["w01"]["y"] == 0, "w01 初始在 A(0,0)")
	_check(ui.core.item_map["w04"]["bag"] == "A", "w04 初始在 A 包")
	_check(ui.core.item_map["w02"]["bag"] == "B", "w02 初始在 B 包")

	# 3. 初始 liveDot：A 包可见 / B 包隐藏
	_check(ui.item_nodes["w01"].get_node("LiveDot").visible, "A 包道具 liveDot 可见")
	_check(not ui.item_nodes["w02"].get_node("LiveDot").visible, "B 包道具 liveDot 隐藏")

	# 4. 节点位置与 item_map 同步（refresh 后）
	var n01: Control = ui.item_nodes["w01"]
	_check(n01.position == ui._item_pos("A", 0, 0), "w01 节点位置 = A(0,0) 格坐标")

	# 5. 正常落子：w06 从 A(5,3) 移到 B(0,4)
	var r1: Dictionary = ui.drop_item("w06", "B", 0, 4)
	_check(bool(r1.get("placed", false)), "w06 → B(0,4) placed=true")
	_check(String(ui.core.item_map["w06"]["bag"]) == "B", "w06 现在在 B 包")
	_check(not ui.item_nodes["w06"].get_node("LiveDot").visible, "移入 B 后 liveDot 隐藏")

	# 6. 互换：w06(1x1) 压到 w04 所在 A(3,1)，w04 弹到 w06 原位 B(0,4)
	var r2: Dictionary = ui.drop_item("w06", "A", 3, 1)
	_check(bool(r2.get("swapped", false)), "w06 压 w04 → swapped=true")
	_check(String(ui.core.item_map["w06"]["bag"]) == "A", "互换后 w06 在 A 包")
	_check(String(ui.core.item_map["w04"]["bag"]) == "B", "互换后 w04 在 B 包")
	_check(int(ui.core.item_map["w04"]["x"]) == 0 and int(ui.core.item_map["w04"]["y"]) == 4,
			"w04 落在 w06 原位 B(0,4)")

	# 7. 越界弹回：w03(2x2) 放到 A(6,4) 超出 7 列 → bounced，且留在原位
	var r3: Dictionary = ui.drop_item("w03", "A", 6, 4)
	_check(bool(r3.get("bounced", false)), "w03 → A(6,4) 越界 bounced=true")
	_check(String(ui.core.item_map["w03"]["bag"]) == "B"
			and int(ui.core.item_map["w03"]["x"]) == 4 and int(ui.core.item_map["w03"]["y"]) == 3,
			"w03 弹回原位 B(4,3)")

	# 8. 压多个道具 → 弹回：把 w04(1x1, 在 B(0,4)) 放到 B(0,0)（w02 1x3 占 B(0,0..2)，与 A 包无关；
	#    B(0,1) 只压 w02 一个 → 会互换，所以选压 ≥2 的点：B(2,2) 有 w07(1x2)，B(2,2) 仅 1 个。
	#    改为对 w07(1x2, B(2,2..3))：w08 未摆放，跳过压多场景（bag_core 测试已覆盖），此处验证
	#    背包外目标 → 弹回即可（UI 层 _pick_target 返回空时走 refresh 分支）。
	var r4: Dictionary = ui.drop_item("w04", "A", 99, 99)
	_check(bool(r4.get("bounced", false)), "w04 → A(99,99) 越界 bounced=true")

	# 9. 属性面板已刷新（只统计 A 包）
	_check(String(ui.stats_labels["atk"].text) != "", "攻击标签文本非空")

	# 10. TIPS 显示 / 隐藏
	ui._show_tips("w01")
	_check(ui.tips.visible, "点按 w01 → TIPS 可见")
	_check(ui._tips_for == "w01", "TIPS 绑定 w01")
	ui._hide_tips()
	_check(not ui.tips.visible, "_hide_tips 后 TIPS 隐藏")

	# 11. 异形道具（w09 缺角铁牌 shape=["11","10"]，2x2 包围盒挖 (1,1)）
	_check(String(ui.core.item_map["w09"]["bag"]) == "B" and int(ui.core.item_map["w09"]["x"]) == 4,
			"w09 初始在 B(4,0)")
	_check(ui.item_nodes["w09"].size == Vector2(92, 92), "w09 节点为 2x2 包围盒 92x92")
	# 异形逐格越界：A(6,4) 时实格 (7,4) 出界 → bounced，弹回 B(4,0)
	var r5: Dictionary = ui.drop_item("w09", "A", 6, 4)
	_check(bool(r5.get("bounced", false)), "w09 → A(6,4) 实格越界 bounced=true")
	_check(String(ui.core.item_map["w09"]["bag"]) == "B"
			and int(ui.core.item_map["w09"]["x"]) == 4 and int(ui.core.item_map["w09"]["y"]) == 0,
			"w09 弹回原位 B(4,0)")
	# 异形互换：w09 锚 A(3,1)，实格 (3,1) 压住 w06（单个）→ 互换，w06 落 w09 原位 B(4,0)
	var r6: Dictionary = ui.drop_item("w09", "A", 3, 1)
	_check(bool(r6.get("swapped", false)), "w09 实格压 w06 → swapped=true")
	_check(String(ui.core.item_map["w09"]["bag"]) == "A"
			and int(ui.core.item_map["w09"]["x"]) == 3 and int(ui.core.item_map["w09"]["y"]) == 1,
			"互换后 w09 在 A(3,1)")
	_check(String(ui.core.item_map["w06"]["bag"]) == "B"
			and int(ui.core.item_map["w06"]["x"]) == 4 and int(ui.core.item_map["w06"]["y"]) == 0,
			"互换后 w06 落在 w09 原位 B(4,0)")
	# 挖空格验证：B(0,0) 空位可放（异形实际只占 3 格）
	ui.drop_item("w09", "B", 0, 0)
	_check(String(ui.core.item_map["w09"]["bag"]) == "B"
			and int(ui.core.item_map["w09"]["x"]) == 0 and int(ui.core.item_map["w09"]["y"]) == 0,
			"w09 放回 B(0,0) placed")

	_finish()


func _check(ok: bool, label: String) -> void:
	_total += 1
	if ok:
		print("  PASS  ", label)
	else:
		_fails += 1
		print("  FAIL  ", label)


func _finish() -> void:
	print("---")
	print("bag_ui 冒烟测试：%d/%d 通过" % [_total - _fails, _total])
	quit(1 if _fails > 0 else 0)
