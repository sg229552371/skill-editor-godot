# bhv_melee_swing（规格 §11 M2）：近战挥砍行为。
# 不认识具体宝石，只读行为计划。扇形范围判定在 M4 命中闭环接入。
class_name BhvMeleeSwing
extends RefCounted


## 从单条计划提取挥砍参数。
static func plan_to_swing(plan: Dictionary) -> Dictionary:
	var params: Dictionary = plan.get(&"params", {})
	return {
		&"arc_deg": float(params.get(&"arc_deg", 90.0)),
		&"range": float(params.get(&"range", 80.0)),
		&"angle_deg": float(plan.get(&"angle_deg", 0.0)),
	}
