# CombatEventBus（规格 §7.1）：战斗事件单一总线。
# 全局唯一实例（autoload），触发系统据此驱动 trigger_cast。
# 本工程为纯数据管线：总线只承载信号，不做任何判定。
class_name CombatEventBus
extends RefCounted

signal hit_landed(packet, target)
signal crit_landed(packet, target)
signal entity_killed(victim, killer)
signal damage_taken(entity, packet)
signal block_occurred(entity, packet)
signal skill_cooldown_finished(instance)
