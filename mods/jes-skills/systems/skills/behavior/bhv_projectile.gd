# bhv_projectile（规格 §3.6 / M2）：投射物行为。
# 不认识具体宝石，只读 SkillExecutor 产出的行为计划。
# 热路径禁止 instantiate/free —— 真实发射走对象池（M8），本里程碑只产出计划参数。
class_name BhvProjectile
extends RefCounted


## 从单条计划提取发射参数（供真实投射物生成器或测试消费）。
static func plan_to_launch(plan: Dictionary) -> Dictionary:
	var params: Dictionary = plan.get(&"params", {})
	return {
		&"count": int(params.get(&"projectile_count", 1)),
		&"speed": float(params.get(&"speed", 900.0)),
		&"radius": float(params.get(&"radius", 12.0)),
		&"pierce": int(params.get(&"pierce", 0)),
		&"fork": int(params.get(&"fork_count", 0)),
		&"chain": int(params.get(&"chain_count", 0)),
		&"lifetime": float(params.get(&"lifetime", 1.2)),
		&"angle_deg": float(plan.get(&"angle_deg", 0.0)),
	}
