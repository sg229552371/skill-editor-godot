# 属性组件（规格 §3.5 / 附录 B 抄 kit 的接口签名：add/remove_by_source）
# 单一职责：持有 Modifier 列表、按来源注入与卸载。
# 聚合计算不在本类做（管线负责），避免双管线。
class_name StatsComponent
extends RefCounted

var _modifiers: Array[StatModifier] = []


func add_modifier(m: StatModifier) -> void:
	_modifiers.append(m)


func add_modifiers(mods: Array, source_id: StringName) -> void:
	for m in mods:
		m.source_id = source_id
		_modifiers.append(m)


func remove_by_source(source_id: StringName) -> void:
	var kept: Array[StatModifier] = []
	for m in _modifiers:
		if m.source_id != source_id:
			kept.append(m)
	_modifiers = kept


func get_modifiers() -> Array[StatModifier]:
	return _modifiers
