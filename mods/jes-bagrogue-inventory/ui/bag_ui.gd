class_name BagUI
extends Control

## bagrogue 双背包 UI —— 严格对齐 sandbox/layout_prototype_v1.html（v1.2 竖屏 390x844）
## 数据：ui/bag_defs.gd    逻辑：systems/bag_core.gd（本脚本零业务规则，只做表现层）
## 布局（与 HTML 逐项对齐）：
##   英雄面板 (8,8,374x96)：头像 80x80 / 名字行 / HP 条 / 四维属性（高于基础=绿，低于=红）
##   A 包 box (8,112,374x271) 标题"武器背包"+徽章"生效中 · 5×7"
##   B 包 box (8,528,374x271) 标题"临时仓库"+徽章"不生效 · 5×6"
##   包体内部：网格左上角在 box 内 (8,27)，CELL=44 GAP=4
##   底部提示条 (8,796,374x40)
## 交互（左上角锚点，制作人 2026-10-22 裁定）：
##   - 拖拽：按住道具移动超阈值 → 拖起（保持抓取偏移，道具左上角跟手，可跨包，置顶+半透明）
##           目标格 = 道具左上角所在格；实时高亮（绿=可放/可互换，红=不可放），只画网格内格子
##   - 松手：调用 core.drop → 落子 / 互换 / 弹回，统一 refresh
##   - 点按：显示 TIPS（含"当前生效/不生效"行）
##   - 只有 A 包道具显示 liveDot（左上角小圆点）并计入英雄属性

const BagCore := preload("res://mods/jes-bagrogue-inventory/systems/bag_core.gd")
const BagDefs := preload("res://mods/jes-bagrogue-inventory/ui/bag_defs.gd")

const CELL := 44
const GAP := 4
const DRAG_THRESHOLD := 3.0
const STAGE := Vector2(390, 844)

## 包体几何（对齐 HTML）
const BOX_X := 8.0
const BOX_W := 374.0
const BOX_A_Y := 112.0
const BOX_B_Y := 528.0
const GRID_LOCAL := Vector2(8, 27)   # 网格在 box 内偏移（padding 8 + 标题行 16 + 间距 3）
const BOX_H := 271.0

const BAG_TITLES := {"A": "武器背包", "B": "临时仓库"}
const BAG_TAGS := {"A": "生效中 · 5×7", "B": "不生效 · 5×6"}
const STAT_NAME := {"atk": "攻击", "spd": "攻速", "crit": "暴击", "move": "移速", "hp": "生命"}
const RARITY_NAME := {"common": "普通", "rare": "稀有", "epic": "史诗", "legend": "传说"}
## 稀有度底色/边框（实底，对齐 HTML .r-*）
const RARITY_BG := {
	"common": Color("3a3f4a"), "rare": Color("2e4356"),
	"epic": Color("452e56"), "legend": Color("54452a"),
}
const RARITY_BORDER := {
	"common": Color("565e70"), "rare": Color("4a7fa0"),
	"epic": Color("8a5ab0"), "legend": Color("c0a040"),
}
const ICON_EMOJI := {
	"sword": "🗡️", "bow": "🏹", "hammer": "🔨", "dagger": "🔪",
	"staff": "🔥", "bracer": "🛡️", "boots": "👟", "skull": "💀", "brick": "🧱",
}

var core: BagCore
var bag_panels := {}    # bag -> Panel（包体容器；网格在 draw 信号里按 GRID_LOCAL 自绘）
var item_nodes := {}    # id -> Panel（挂在 items_layer 上，舞台坐标系）
var stats_labels := {}  # stat_key -> Label（hp 的 label 即 HP 文本）
var stat_values := {}   # stat_key -> float（当前值缓存，供外部查询）
var items_layer: Control
var tips: PanelContainer
var hp_bar: ColorRect

var _drag := {}       # {id, started, start_pos, grab_off, target: {bag,x,y,ok}}
var _tips_for := ""   # 当前 TIPS 显示的道具 id（"" = 隐藏）


func _ready() -> void:
	# 舞台适配：本场景自带 390x844 竖屏声明，不改项目级窗口设置，其他系统分辨率不受影响
	StageFit.apply(STAGE)
	core = BagCore.new(_grid_cfg(), _initial_layout())
	_build_ui()
	refresh()


# ---------- 数据装配 ----------

func _grid_cfg() -> Dictionary:
	return {"A": BagDefs.GRID["A"].duplicate(), "B": BagDefs.GRID["B"].duplicate()}


func _initial_layout() -> Array:
	var out: Array = []
	for L in BagDefs.LAYOUT:
		out.append({
			"def": _def_of(String(L["item"])).duplicate(true),
			"bag": L["bag"], "x": L["x"], "y": L["y"],
		})
	return out


func _def_of(id: String) -> Dictionary:
	for d in BagDefs.ITEMS:
		if d["id"] == id:
			return d
	return {}


# ---------- UI 搭建 ----------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("23272f")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_build_hero_panel()
	for bag in ["A", "B"]:
		_build_bag_box(bag)

	# 道具舞台层：与包体同坐标系（舞台坐标）；拖起时置顶即可跨包拖动
	items_layer = Control.new()
	items_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	items_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(items_layer)

	for id in core.item_map:
		_make_item_node(String(id))

	_build_hint_bar()
	_build_tips()


## TIPS 弹层：固定宽 220（对齐 HTML #tips）
func _build_tips() -> void:
	tips = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color("14161c")
	st.border_color = Color("565e70")
	st.set_border_width_all(1)
	st.set_corner_radius_all(6)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	tips.add_theme_stylebox_override("panel", st)
	tips.custom_minimum_size = Vector2(220, 0)
	tips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tips.visible = false
	add_child(tips)


func _box_style(bg: Color, border: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	return st


## 英雄面板：头像 + 名字行 + HP 条 + 2×2 属性格
func _build_hero_panel() -> void:
	var p := Panel.new()
	p.position = Vector2(8, 8)
	p.size = Vector2(374, 96)
	p.add_theme_stylebox_override("panel", _box_style(Color("2b303b"), Color("4a5060")))
	add_child(p)

	var av := Panel.new()
	av.position = Vector2(8, 8)
	av.size = Vector2(80, 80)
	var av_st := _box_style(Color("3a4150"), Color("565e70"))
	av_st.set_corner_radius_all(6)
	av.add_theme_stylebox_override("panel", av_st)
	var face := _make_label("🧙", 34, Color.WHITE)
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Segoe UI Emoji", "Segoe UI Symbol", "Microsoft YaHei"])
	face.add_theme_font_override("font", sf)
	av.add_child(face)
	p.add_child(av)

	var info_x := 96.0
	var inner_w := 374.0 - info_x - 8.0
	var name_l := _make_label("流浪者", 14, Color("f0f2f6"))
	name_l.position = Vector2(info_x, 8)
	p.add_child(name_l)
	var lv_l := _make_label("Lv.1", 11, Color("8b93a3"))
	lv_l.position = Vector2(374 - 8 - 30, 10)
	p.add_child(lv_l)

	# HP 条
	var outer := Panel.new()
	outer.position = Vector2(info_x, 30)
	outer.size = Vector2(inner_w, 12)
	var ost := StyleBoxFlat.new()
	ost.bg_color = Color("1a1d24")
	ost.border_color = Color("4a5060")
	ost.set_border_width_all(1)
	ost.set_corner_radius_all(3)
	outer.add_theme_stylebox_override("panel", ost)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar = ColorRect.new()
	hp_bar.color = Color("c05050")
	hp_bar.position = Vector2(1, 1)
	hp_bar.size = Vector2(inner_w - 2, 10)
	outer.add_child(hp_bar)
	p.add_child(outer)

	var hp_l := _make_label("", 10, Color("a8afc0"))
	hp_l.position = Vector2(info_x, 44)
	p.add_child(hp_l)
	stats_labels["hp"] = hp_l

	# 2×2 属性格：左列 攻击/暴击，右列 攻速/移速
	var cols := [["atk", "spd"], ["crit", "move"]]
	for ci in 2:
		for ri in 2:
			var k: String = cols[ci][ri]
			var key_l := _make_label(STAT_NAME[k], 11, Color("9aa2b2"))
			key_l.position = Vector2(info_x + ci * 136, 62 + ri * 15)
			p.add_child(key_l)
			var val_l := _make_label("", 11, Color("e8c86a"))
			val_l.position = Vector2(info_x + ci * 136 + 60, 62 + ri * 15)
			p.add_child(val_l)
			stats_labels[k] = val_l
			stat_values[k] = 0.0


## 包体：外框 + 标题行（名称 + 徽章）+ 网格自绘
func _build_bag_box(bag: String) -> void:
	var g: Dictionary = BagDefs.GRID[bag]
	var p := Panel.new()
	p.position = Vector2(BOX_X, BOX_A_Y if bag == "A" else BOX_B_Y)
	p.size = Vector2(BOX_W, BOX_H)
	p.add_theme_stylebox_override("panel", _box_style(Color("2b303b"), Color("4a5060")))
	p.draw.connect(_draw_bag.bind(p, bag))
	add_child(p)
	bag_panels[bag] = p

	var title := _make_label(BAG_TITLES[bag], 12, Color("9aa2b2"))
	title.position = Vector2(8, 6)
	p.add_child(title)

	# 徽章：生效中 = 绿字绿框；不生效 = 灰字灰框
	var tag_active: bool = bag == "A"
	var tag := PanelContainer.new()
	var tst := StyleBoxFlat.new()
	tst.bg_color = Color.TRANSPARENT
	tst.border_color = Color("4a8a4a") if tag_active else Color("4a5060")
	tst.set_border_width_all(1)
	tst.set_corner_radius_all(3)
	tst.content_margin_left = 6
	tst.content_margin_right = 6
	tst.content_margin_top = 1
	tst.content_margin_bottom = 1
	tag.add_theme_stylebox_override("panel", tst)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(_make_label(BAG_TAGS[bag], 10,
			Color("6ecf6e") if tag_active else Color("8b93a3")))
	p.add_child(tag)
	tag.reset_size()
	tag.position = Vector2(BOX_W - 8 - tag.size.x, 5)


func _build_hint_bar() -> void:
	var p := Panel.new()
	p.position = Vector2(8, STAGE.y - 48)
	p.size = Vector2(374, 40)
	p.add_theme_stylebox_override("panel", _box_style(Color("2b303b"), Color("4a5060")))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _make_label("拖动道具换位 / 跨包搬运 · 点按或长按看详情 · 只有武器背包里的道具生效", 11, Color("8b93a3"))
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	p.add_child(l)
	add_child(p)


func _make_label(text: String, size_px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_item_node(id: String) -> void:
	var it: Dictionary = core.item_map[id]
	var def: Dictionary = it["def"]
	var w := int(def["w"])
	var h := int(def["h"])
	var p := Panel.new()
	p.size = Vector2(w * CELL + (w - 1) * GAP, h * CELL + (h - 1) * GAP)
	p.set_meta("id", id)
	# 节点本体透明，形状格子在 draw 信号里逐格绘制（挖空处不画）
	var st := StyleBoxFlat.new()
	st.bg_color = Color.TRANSPARENT
	st.set_border_width_all(0)
	p.add_theme_stylebox_override("panel", st)
	p.draw.connect(_draw_item.bind(p, id))
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var emoji := _make_label(String(ICON_EMOJI.get(def["icon"], "❓")), 20, Color.WHITE)
	emoji.name = "Icon"
	emoji.set_anchors_preset(Control.PRESET_FULL_RECT)
	emoji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emoji.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Segoe UI Emoji", "Segoe UI Symbol", "Microsoft YaHei"])
	emoji.add_theme_font_override("font", sf)
	p.add_child(emoji)

	# liveDot：左上角小圆点（对齐 HTML .liveDot）
	var dot := _make_label("●", 8, Color("6ecf6e"))
	dot.name = "LiveDot"
	dot.position = Vector2(3, 2)
	p.add_child(dot)

	p.gui_input.connect(_on_item_gui_input.bind(id))
	items_layer.add_child(p)
	item_nodes[id] = p


## 道具逐格绘制：按占格列表画每一格（挖空处不画）——异形道具支持
func _draw_item(p: Panel, id: String) -> void:
	var it: Dictionary = core.item_map[id]
	var def: Dictionary = it["def"]
	var bg: Color = RARITY_BG.get(def["rarity"], RARITY_BG["common"])
	var border: Color = RARITY_BORDER.get(def["rarity"], RARITY_BORDER["common"])
	var step := CELL + GAP
	for c in BagCore.cells_of(def):
		var r := Rect2(int(c.x) * step, int(c.y) * step, CELL, CELL)
		p.draw_rect(r, bg, true)
		p.draw_rect(r, border, false, 1.0)


## 包体网格 + 拖拽高亮（绿=可放 / 红=不可放），只画落在网格内的格子
func _draw_bag(p: Panel, bag: String) -> void:
	var g: Dictionary = BagDefs.GRID[bag]
	var cols := int(g["cols"])
	var rows := int(g["rows"])
	var step := CELL + GAP
	var origin := GRID_LOCAL
	for iy in range(rows):
		for ix in range(cols):
			var r := Rect2(origin.x + ix * step, origin.y + iy * step, CELL, CELL)
			p.draw_rect(r, Color("22262e"), true)
			p.draw_rect(r, Color("383e4a"), false, 1.0)
	var t: Dictionary = _drag.get("target", {})
	if _drag.get("started", false) and t.get("bag", "") == bag:
		var ok := bool(t["ok"])
		var base := Color("5a9a5a") if ok else Color("9a5a5a")
		var fill := Color("2c3a2c") if ok else Color("3a2c2c")
		var def: Dictionary = core.item_map[String(_drag["id"])]["def"]
		for c in BagCore.cells_of(def):
			var gx := int(t["x"]) + int(c.x)
			var gy := int(t["y"]) + int(c.y)
			if gx < 0 or gy < 0 or gx >= cols or gy >= rows:
				continue
			var r2 := Rect2(origin.x + gx * step, origin.y + gy * step, CELL, CELL)
			p.draw_rect(r2, fill, true)
			p.draw_rect(r2, base, false, 1.0)


# ---------- 交互（左上角锚点） ----------

## 注意：gui_input 信号自带 event 为第 1 参，bind(id) 追加在后 → 签名必须是 (event, id)
func _on_item_gui_input(ev: InputEvent, id: String) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			# 记住抓取偏移与起点：拖动时保持偏移，道具左上角跟手
			var node: Control = item_nodes[id]
			var mp := get_global_mouse_position()
			_drag = {"id": id, "started": false, "start_pos": mp,
					"grab_off": mp - node.global_position}
		else:
			_release(id)
	elif ev is InputEventMouseMotion and _drag.get("id", "") == id \
			and ev.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_drag_move()


func _drag_move() -> void:
	var id: String = _drag["id"]
	var mp := get_global_mouse_position()
	if not bool(_drag["started"]):
		if mp.distance_to(_drag["start_pos"]) < DRAG_THRESHOLD:
			return
		_drag["started"] = true
		_hide_tips()
		# 拖起：置顶 + 半透明（对齐 HTML .dragging）
		items_layer.move_child(item_nodes[id], items_layer.get_child_count() - 1)
		item_nodes[id].modulate.a = 0.85
	var node: Control = item_nodes[id]
	node.position = mp - _drag["grab_off"]  # 保持抓取偏移，道具左上角跟手
	_drag["target"] = _pick_target(id)
	for b in bag_panels:
		bag_panels[b].queue_redraw()


## 目标格 = 道具左上角所在格（制作人裁定：左上角锚点）
## bag 判定用左上角点（内缩 2px 防边缘抖动）；越界格不参与判定，但高亮阶段只画网格内格子
## ok = 全部实格在界内 且 压住 ≤1 个其他道具（空位 / 互换候选），最终由 core.drop 判定
func _pick_target(id: String) -> Dictionary:
	var tl: Vector2 = item_nodes[id].global_position + Vector2(2, 2)
	for bag in ["A", "B"]:
		var c := _cell_at(bag, tl)
		if c.is_empty():
			continue
		var def: Dictionary = core.item_map[id]["def"]
		var g: Dictionary = core.cfg[bag]
		var in_bounds := true
		for cell in BagCore.cells_of(def):
			var cx := int(c["x"]) + int(cell.x)
			var cy := int(c["y"]) + int(cell.y)
			if cx < 0 or cy < 0 or cx >= int(g["cols"]) or cy >= int(g["rows"]):
				in_bounds = false
				break
		var occ := _occupant_count(id, bag, int(c["x"]), int(c["y"]), def)
		return {"bag": bag, "x": int(c["x"]), "y": int(c["y"]), "ok": in_bounds and occ <= 1}
	return {}


## 统计 def 形状落在 (gx,gy) 时压住的其他道具数（去重）
func _occupant_count(id: String, bag: String, gx: int, gy: int, def: Dictionary) -> int:
	var occ := {}
	for c in BagCore.cells_of(def):
		var o: String = core.occupant_at(bag, gx + int(c.x), gy + int(c.y))
		if o != "" and o != id:
			occ[o] = true
	return occ.size()


func _cell_at(bag: String, gpos: Vector2) -> Dictionary:
	var origin: Vector2 = bag_panels[bag].position + GRID_LOCAL
	var local := gpos - origin
	var step := CELL + GAP
	var g: Dictionary = BagDefs.GRID[bag]
	var gx := int(floor(local.x / step))
	var gy := int(floor(local.y / step))
	# 左上角点须落在网格矩形内
	if gpos.x < origin.x or gpos.y < origin.y \
			or gx >= int(g["cols"]) or gy >= int(g["rows"]):
		return {}
	return {"x": gx, "y": gy}


func _release(id: String) -> void:
	if _drag.get("id", "") != id:
		return
	var started: bool = bool(_drag.get("started", false))
	var t: Dictionary = _drag.get("target", {})
	_drag = {}
	if started:
		item_nodes[id].modulate.a = 1.0
		if not t.is_empty():
			drop_item(id, String(t["bag"]), int(t["x"]), int(t["y"]))
		else:
			refresh()  # 网格外松手 → 弹回
	else:
		_show_tips(id)  # 点按 → TIPS
	for b in bag_panels:
		bag_panels[b].queue_redraw()


# ---------- 公共操作（冒烟测试同样走这里） ----------

## 落子并整体重渲染（placed / swapped / bounced 三种结果都统一走 refresh）
func drop_item(id: String, target: String, gx: int, gy: int) -> Dictionary:
	var res: Dictionary = core.drop(id, target, gx, gy)
	refresh()
	return res


## 按 core.item_map 重排所有道具节点 + 刷新 liveDot / 英雄属性
func refresh() -> void:
	for id in core.item_map:
		var it: Dictionary = core.item_map[id]
		var node: Control = item_nodes[String(id)]
		node.position = _item_pos(String(it["bag"]), int(it["x"]), int(it["y"]))
		node.modulate.a = 1.0
		var dot: Label = node.get_node("LiveDot")
		dot.visible = it["bag"] == "A"
	_refresh_stats()
	_hide_tips()


func _item_pos(bag: String, x: int, y: int) -> Vector2:
	return bag_panels[bag].position + GRID_LOCAL + Vector2(x * (CELL + GAP), y * (CELL + GAP))


func _refresh_stats() -> void:
	var s: Dictionary = core.stats(BagDefs.BASE_STATS)
	var hp := float(s.get("hp", 100.0))
	hp_bar.size.x = (374.0 - 96.0 - 8.0 - 2.0) * clampf(hp / 100.0, 0.0, 1.0)
	for k in stats_labels:
		var v := float(s.get(k, 0.0))
		if k == "hp":
			stats_labels[k].text = "HP %d/%d" % [int(round(hp)), int(round(hp))]
			continue
		stats_labels[k].text = _fmt_stat(k, v)
		# 高于基础=绿（buffed），低于=红（debuffed），持平=金
		var base := float(BagDefs.BASE_STATS.get(k, 0.0))
		var col := Color("e8c86a")
		if v > base:
			col = Color("6ecf6e")
		elif v < base:
			col = Color("e06c6c")
		stats_labels[k].add_theme_color_override("font_color", col)
		stat_values[k] = v


func _fmt_stat(k: String, v: float) -> String:
	match k:
		"spd":
			return "%.2f" % v
		"crit":
			return "%d%%" % int(round(v))
		_:
			return str(int(round(v)))


# ---------- TIPS ----------

func _show_tips(id: String) -> void:
	var it: Dictionary = core.item_map[id]
	var def: Dictionary = it["def"]
	for c in tips.get_children():
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	tips.add_child(vb)
	var col: Color = RARITY_BORDER.get(def["rarity"], RARITY_BORDER["common"])
	vb.add_child(_make_label(String(ICON_EMOJI.get(def["icon"], "")) + " " + String(def["name"]), 13, col))
	vb.add_child(_make_label(RARITY_NAME.get(def["rarity"], ""), 10, Color("8b93a3")))
	for k in def["stats"]:
		vb.add_child(_make_label("%s %s" % [STAT_NAME.get(k, k), _fmt_delta(def["stats"][k])],
				11, Color("b8e0b8")))
	vb.add_child(_make_label(String(def["desc"]), 11, Color("8b93a3")))
	vb.add_child(_make_label(
			"✔ 当前生效（武器背包）" if it["bag"] == "A" else "✖ 不生效（临时仓库）",
			10, Color("6ecf6e") if it["bag"] == "A" else Color("8b93a3")))
	tips.reset_size()
	# 位置：道具上方居中；放不下翻到下方；整体夹回视口
	var node: Control = item_nodes[id]
	var pos := node.global_position + Vector2(node.size.x / 2.0 - tips.size.x / 2.0,
			-tips.size.y - 6)
	if pos.y < 4:
		pos.y = node.global_position.y + node.size.y + 6
	pos.x = clampf(pos.x, 4, maxf(4, size.x - tips.size.x - 4))
	pos.y = clampf(pos.y, 4, maxf(4, size.y - tips.size.y - 4))
	tips.global_position = pos
	tips.visible = true
	_tips_for = id


func _hide_tips() -> void:
	tips.visible = false
	_tips_for = ""


func _fmt_delta(v) -> String:
	var f := float(v)
	var sign_s := "+" if f > 0.0 else ""
	if is_equal_approx(f, roundf(f)):
		return sign_s + str(int(roundf(f)))
	return sign_s + "%.2f" % f
