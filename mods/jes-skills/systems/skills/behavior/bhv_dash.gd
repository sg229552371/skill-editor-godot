# bhv_dash（规格 §5 / M6）：冲刺位移行为。路径伤害可选（path_damage 非空即启用）。
# 不认识具体宝石，只消费行为计划。本里程碑只产出纯数据计划参数。
class_name BhvDash
extends RefCounted


## 从单条计划提取冲刺参数。
static func plan_to_dash(plan: Dictionary) -> Dictionary:
	var params: Dictionary = plan.get(&"params", {})
	var distance: float = maxf(float(params.get(&"distance", 300.0)), 0.0)
	var speed: float = maxf(float(params.get(&"speed", 1500.0)), 0.01)
	var has_path_damage: bool = params.has(&"path_damage")
	return {
		&"distance": distance,
		&"speed": speed,
		&"move_time": distance / speed,
		&"has_path_damage": has_path_damage,
		&"path_damage": params.get(&"path_damage", {}),
		&"angle_deg": float(plan.get(&"angle_deg", 0.0)),
	}
