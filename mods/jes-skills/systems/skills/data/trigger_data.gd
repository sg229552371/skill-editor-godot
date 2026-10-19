# TriggerData（规格 §3.4）：触发器数据单一真源。
# event: &"on_hit" &"on_crit" &"on_kill" &"on_take_damage" &"on_block" &"on_cooldown_end" &"on_interval"
class_name TriggerData
extends Resource

@export var event: StringName = &""
@export var chance: float = 1.0
@export var cooldown: float = 0.0
@export var interval: float = 0.0   # 仅 on_interval 使用
@export var linked_slot_index: int = 0
