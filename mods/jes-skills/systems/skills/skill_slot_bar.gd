# SkillSlotBar（规格 §5.3）：技能栏 1~8 键，每键绑定一个 SkillSlot。
# 同一时刻一个 SkillSlot 派生一个 SkillInstance（§5.1）。
## 硬门禁：纯数据容器无演出逻辑；越界操作安全返回（null / false）。
class_name SkillSlotBar
extends RefCounted

const MAX_SLOTS := 8

var slot_count: int = MAX_SLOTS
var _slots: Array = []


func _init() -> void:
	_slots.resize(MAX_SLOTS)
	_slots.fill(null)


## 绑定技能位。索引越界返回 false，不做任何修改。
func bind_slot(index: int, slot: SkillSlot) -> bool:
	if index < 0 or index >= MAX_SLOTS:
		return false
	_slots[index] = slot
	return true


## 读取技能位。越界返回 null。
func get_slot(index: int) -> SkillSlot:
	if index < 0 or index >= MAX_SLOTS:
		return null
	return _slots[index]
