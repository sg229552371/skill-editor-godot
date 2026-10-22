class_name InventoryGrid
extends RefCounted

## 格子背包（纯逻辑，零节点、零 UI）
##
## 设计口径（D-52）：
##   - **格子口径只有这一处定义**（判据 P1 单真源）：调用方传 cols/rows，本类不硬编码 5×6 / 5×7
##   - 坐标一律 (col, row)，左上角 = (0,0)
##   - 多格物品占一片矩形区域，放置时保证不越界、不与已占格重叠
##   - 堆叠按 item_id 合并：先找同类未满的堆，再找空位
##   - 不放任隐式行为：放不下就明确返回失败，不做「自动挪位置」魔法

var cols: int = 0
var rows: int = 0

# 已占格：Dictionary<Vector2i, int>  →  (col,row) -> 占用者的 uid
var _cells: Dictionary = {}
# 实例：Dictionary<int, Dictionary> → uid -> {item, count, origin(Vector2i), w, h}
var _items: Dictionary = {}
var _next_uid: int = 1


func _init(p_cols: int = 0, p_rows: int = 0) -> void:
	cols = maxi(p_cols, 0)
	rows = maxi(p_rows, 0)


## 总格数
func capacity() -> int:
	return cols * rows


## 已被占用的格数（多格物品按实际占格数计）
func used_cells() -> int:
	return _cells.size()


## 剩余格数
func free_cells() -> int:
	return capacity() - used_cells()


## 该坐标是否被占用
func is_occupied(col: int, row: int) -> bool:
	return _cells.has(Vector2i(col, row))


## 该坐标的占用者 uid（-1 = 空）
func occupant_at(col: int, row: int) -> int:
	return int(_cells.get(Vector2i(col, row), -1))


## 能否把 w×h 的物品放在 (col,row)：越界或重叠即 false
func can_fit(col: int, row: int, w: int, h: int) -> bool:
	if w < 1 or h < 1:
		return false
	if col < 0 or row < 0 or col + w > cols or row + h > rows:
		return false
	for dy in h:
		for dx in w:
			if _cells.has(Vector2i(col + dx, row + dy)):
				return false
	return true


## 找第一个能放下 w×h 的位置；找不到返回 Vector2i(-1,-1)
func find_free_rect(w: int, h: int) -> Vector2i:
	for row in rows:
		for col in cols:
			if can_fit(col, row, w, h):
				return Vector2i(col, row)
	return Vector2i(-1, -1)


## 放入物品。返回 { ok, uid, placed(count), leftover(count), reason }
## 语义：
##   - 可叠物品优先并入同 item_id 的现有堆（未满的），余量再找空位
##   - 不可叠物品按「每件一个 uid」逐个放置
##   - 放不完的部分明确留在 leftover，不静默丢弃
func put(item: ItemData, count: int = 1) -> Dictionary:
	if item == null:
		return _fail(&"item_null", count)
	var errs := item.validate()
	if not errs.is_empty():
		return _fail(StringName(errs[0]), count)
	if count <= 0:
		return _fail(&"count_not_positive", count)

	var remaining := count

	# ① 先并入现有堆（仅可叠物品）
	if item.is_stackable():
		for uid in _items.keys():
			if remaining <= 0:
				break
			var e: Dictionary = _items[uid]
			if e[&"item"] != item:
				continue
			var room: int = item.max_stack - int(e[&"count"])
			if room <= 0:
				continue
			var moved := mini(room, remaining)
			e[&"count"] = int(e[&"count"]) + moved
			remaining -= moved

	# ② 再找空位。可叠物品一个新堆最多吃 max_stack；唯一物每件一格
	while remaining > 0:
		var pos := find_free_rect(item.grid_w, item.grid_h)
		if pos.x < 0:
			break
		var chunk := mini(item.max_stack, remaining) if item.is_stackable() else 1
		var uid := _next_uid
		_next_uid += 1
		_items[uid] = {
			&"item": item,
			&"count": chunk,
			&"origin": pos,
			&"w": item.grid_w,
			&"h": item.grid_h,
		}
		_occupy(uid, pos, item.grid_w, item.grid_h)
		remaining -= chunk

	var ok := remaining < count
	return {
		&"ok": ok,
		&"uid": _last_uid_of(item),
		&"placed": count - remaining,
		&"leftover": remaining,
		&"reason": &"" if remaining == 0 else &"no_room",
	}


## 取出指定 uid 的 n 件；n 超量时取全部。返回 { ok, removed }
func take(uid: int, n: int = 1) -> Dictionary:
	if not _items.has(uid):
		return {&"ok": false, &"removed": 0}
	var e: Dictionary = _items[uid]
	var have := int(e[&"count"])
	var removed := mini(maxi(n, 0), have)
	if removed <= 0:
		return {&"ok": false, &"removed": 0}
	if removed == have:
		_remove_entry(uid)
	else:
		e[&"count"] = have - removed
	return {&"ok": true, &"removed": removed}


## 把某格上的物品整堆取出（UI 拖拽常用入口）
func take_at(col: int, row: int, n: int = -1) -> Dictionary:
	var uid := occupant_at(col, row)
	if uid < 0:
		return {&"ok": false, &"removed": 0}
	var count := int(_items[uid][&"count"]) if n < 0 else n
	return take(uid, count)


## 某 uid 的快照（只读，供 UI / 测试）
func entry(uid: int) -> Dictionary:
	return _items.get(uid, {})


## 全部实例 uid（升序，顺序稳定）
func uids() -> Array:
	var out: Array = _items.keys()
	out.sort()
	return out


## 按 item_id 统计总数（跨所有堆）
func count_of(item_id: StringName) -> int:
	var total := 0
	for uid in _items:
		var e: Dictionary = _items[uid]
		if (e[&"item"] as ItemData).item_id == item_id:
			total += int(e[&"count"])
	return total


## 清空（测试用）
func clear() -> void:
	_cells.clear()
	_items.clear()
	_next_uid = 1


# ---------------- 内部 ----------------

func _occupy(uid: int, origin: Vector2i, w: int, h: int) -> void:
	for dy in h:
		for dx in w:
			_cells[Vector2i(origin.x + dx, origin.y + dy)] = uid


func _remove_entry(uid: int) -> void:
	var e: Dictionary = _items[uid]
	var origin: Vector2i = e[&"origin"]
	for dy in int(e[&"h"]):
		for dx in int(e[&"w"]):
			_cells.erase(Vector2i(origin.x + dx, origin.y + dy))
	_items.erase(uid)


## 最近一次放入后，该 item 的某个 uid（可能并入旧堆，返回那个旧 uid）
## 按 item_id 匹配而非对象身份：.tres 经 ResourceLoader 缓存后虽同引用，
## 但跨实例（如测试里 duplicate）就会变成两个对象，身份比较会静默漏掉。
func _last_uid_of(item: ItemData) -> int:
	var best := -1
	for uid in _items:
		if same_item(_items[uid][&"item"], item):
			best = maxi(best, int(uid))
	return best


## 物品同类判定：以 item_id 为准（空 id 才回退对象身份）
static func same_item(a: ItemData, b: ItemData) -> bool:
	if a == null or b == null:
		return false
	if a.item_id != &"" and b.item_id != &"":
		return a.item_id == b.item_id
	return a == b


func _fail(reason: StringName, count: int) -> Dictionary:
	return {&"ok": false, &"uid": -1, &"placed": 0, &"leftover": count, &"reason": reason}
