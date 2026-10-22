extends SceneTree

## bag_ui 截图夹具（非测试）：真实渲染 390x844 竖屏，走一遍拖拽交互后逐张出图
## 运行（必须带窗口，不能 --headless，dummy 渲染器不提交绘制）：
##   Godot --path <项目> --script res://mods/jes-bagrogue-inventory/tests/capture_bag_ui.gd

const UI_SCENE := "res://mods/jes-bagrogue-inventory/ui/bag_ui.tscn"
const OUT_DIR := "res://mods/jes-bagrogue-inventory/tests/_capture"

var ui: Control


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed: PackedScene = load(UI_SCENE)
	ui = packed.instantiate()
	root.add_child(ui)
	ui.size = Vector2(390, 844)

	await _shot("01_initial")

	# 拖起 w03 巨锤 2x2：模拟左上角锚点拖拽（道具左上角跟手，目标格 = 左上角所在格）
	var w03: Control = ui.item_nodes["w03"]
	ui._drag = {"id": "w03", "started": true, "start_pos": Vector2.ZERO,
			"grab_off": Vector2.ZERO}
	w03.position = ui.bag_panels["A"].position + ui.GRID_LOCAL + Vector2(2 * 48, 1 * 48)
	ui._drag["target"] = {"bag": "A", "x": 2, "y": 1, "ok": true}
	for b in ui.bag_panels:
		ui.bag_panels[b].queue_redraw()
	await _shot("02_dragging_ok")

	# 不可放：2x2 摆到 A(6,3) 右侧越界 → 红高亮
	ui._drag["target"] = {"bag": "A", "x": 6, "y": 3, "ok": false}
	for b in ui.bag_panels:
		ui.bag_panels[b].queue_redraw()
	await _shot("03_dragging_bad")

	ui._drag = {}
	for b in ui.bag_panels:
		ui.bag_panels[b].queue_redraw()

	# TIPS
	ui._show_tips("w03")
	await _shot("04_tips")

	ui._hide_tips()

	# 异形道具：w09 缺角铁牌（L 形）从 B 互换到 A(3,1)，看逐格渲染
	ui.drop_item("w09", "A", 3, 1)
	await _shot("05_shape")

	quit(0)


func _shot(tag: String) -> void:
	# 等两帧：第一帧提交绘制，第二帧再抓
	for i in 2:
		await process_frame
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, tag]
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("SHOT ", tag, " -> ", path, " err=", err, " size=", img.get_size())
