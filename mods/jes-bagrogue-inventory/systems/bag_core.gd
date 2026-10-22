class_name BagCore
extends RefCounted

## 背包肉鸽核心逻辑（纯数据，零节点依赖）
## 模型（全部 Dictionary，无自定义 class，便于序列化/存档）：
##   bags[bag]["列,行"] = id（每个被占格都登记；锚点 = 道具包围盒左上角 (0,0)）
## 形状（v2，制作人 2026-10-22 裁定落地）：
##   def["shape"] = ["11","10",...] 每行等长的 0/1 字符串，1=占格 0=挖空
##   无 shape 字段 = 满矩形（按 w×h 展开），旧数据零改动兼容
##   锚点固定为包围盒左上角；建议形状 (0,0) 格为 1（与左上角拖拽锚点对齐）
## 规则：
##   - 只有 A 背包（武器背包）内的道具计入 stats
##   - drop：空位直落；落点被单个其他道具占住 → 互换锚点；
##     对方换不动 或 压住 ≥2 个道具 → 整体弹回（bounced）
## 返回：drop → { placed, swapped, bounced }（互斥）

var cfg: Dictionary      # { A: {cols, rows}, B: {cols, rows} }
var bags: Dictionary     # { "A": {"x,y": id, ...}, "B": {...} }
var item_map: Dictionary # { id: {def: {id,w,h,stats,shape?}, bag: String, x: int, y: int} }


func _init(p_cfg: Dictionary, layout: Array = []) -> void:
	cfg = p_cfg
	bags = {"A": {}, "B": {}}
	item_map = {}
	for L in layout:
		var def: Dictionary = L["def"]
		item_map[def["id"]] = {"def": def, "bag": L["bag"], "x": L["x"], "y": L["y"]}
		_occupy(def["id"])


## 道具的占格偏移列表：有 shape 按 0/1 展开，无 shape 按满矩形 w×h 展开
static func cells_of(def: Dictionary) -> Array:
	var out: Array = []
	if def.has("shape"):
		var rows: Array = def["shape"]
		for y in range(rows.size()):
			var row: String = rows[y]
			for x in range(row.length()):
				if row[x] == "1":
					out.append(Vector2i(x, y))
		return out
	for dy in range(int(def["h"])):
		for dx in range(int(def["w"])):
			out.append(Vector2i(dx, dy))
	return out


## 该道具当前覆盖的每个格子的占用者 id（空格返回 ""）
func occupant_at(bag: String, x: int, y: int) -> String:
	return String(bags[bag].get(_key(x, y), ""))


## def 的形状能否放在 (bag,x,y)（逐格越界 + 碰撞）
func fits_def(bag: String, x: int, y: int, def: Dictionary) -> bool:
	var g: Dictionary = cfg[bag]
	for c in cells_of(def):
		var cx: int = x + int(c.x)
		var cy: int = y + int(c.y)
		if cx < 0 or cy < 0 or cx >= int(g["cols"]) or cy >= int(g["rows"]):
			return false
		if bags[bag].has(_key(cx, cy)):
			return false
	return true


## 落子。返回 { placed, swapped, bounced }（互斥）
func drop(id: String, target: String, gx: int, gy: int) -> Dictionary:
	var cur: Dictionary = item_map[id]
	var def: Dictionary = cur["def"]
	var g: Dictionary = cfg[target]
	var cells: Array = cells_of(def)

	# 越界逐格快速失败 → 弹回
	for c in cells:
		var cx: int = gx + int(c.x)
		var cy: int = gy + int(c.y)
		if cx < 0 or cy < 0 or cx >= int(g["cols"]) or cy >= int(g["rows"]):
			return {"placed": false, "swapped": false, "bounced": true}

	_erase(id)  # 先移除自己再检查落点（自己不会挡自己）
	# 落点被哪些道具占住
	var occ_ids := {}
	for c in cells:
		var o: String = String(bags[target].get(_key(gx + int(c.x), gy + int(c.y)), ""))
		if o != "" and o != id:
			occ_ids[o] = true

	var swapped := false
	if occ_ids.size() == 1:
		# 互换：对方搬到我的旧锚点；放不下则双方弹回
		var other_id: String = occ_ids.keys()[0]
		var other: Dictionary = item_map[other_id]
		var old_ax: int = other["x"]
		var old_ay: int = other["y"]
		var old_bag: String = other["bag"]
		_erase(other_id)
		if fits_def(cur["bag"], cur["x"], cur["y"], other["def"]):
			other["bag"] = cur["bag"]
			other["x"] = cur["x"]
			other["y"] = cur["y"]
			_occupy(other_id)
			swapped = true
		else:
			other["bag"] = old_bag
			other["x"] = old_ax
			other["y"] = old_ay
			_occupy(other_id)
			_occupy(id)  # 我也弹回旧锚
			return {"placed": false, "swapped": false, "bounced": true}
	elif occ_ids.size() > 1:
		_occupy(id)  # 压住多个 → 弹回
		return {"placed": false, "swapped": false, "bounced": true}

	cur["bag"] = target
	cur["x"] = gx
	cur["y"] = gy
	_occupy(id)
	return {"placed": true, "swapped": swapped, "bounced": false}


## 属性汇总：只统计 A 背包内的道具
func stats(base: Dictionary) -> Dictionary:
	var s := base.duplicate(true)
	for id in item_map:
		var it: Dictionary = item_map[id]
		if it["bag"] != "A":
			continue
		for k in it["def"]["stats"]:
			s[k] = float(s.get(k, 0.0)) + float(it["def"]["stats"][k])
	return s


## 按 shape/w×h 的占格列表登记 "x,y" → id
func _occupy(id: String) -> void:
	var it: Dictionary = item_map[id]
	for c in cells_of(it["def"]):
		bags[it["bag"]][_key(it["x"] + int(c.x), it["y"] + int(c.y))] = id


## 按 shape/w×h 的占格列表删除占格
func _erase(id: String) -> void:
	var it: Dictionary = item_map[id]
	for c in cells_of(it["def"]):
		bags[it["bag"]].erase(_key(it["x"] + int(c.x), it["y"] + int(c.y)))


static func _key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]
