# bhv_aoe_burst（规格 §5 / M6）：范围爆发行为。
# 不认识具体宝石，只消费 SkillExecutor 产出的行为计划。
# 本里程碑只产出纯数据计划参数（延迟/半径/打击时刻），真实 Area2D 结算在命中闭环接入。
class_name BhvAoeBurst
extends RefCounted


## 从单条计划提取范围爆发参数。
static func plan_to_burst(plan: Dictionary) -> Dictionary:
	var params: Dictionary = plan.get(&"params", {})
	var radius: float = _scaled_area(float(params.get(&"radius", 160.0)), plan)
	var delay: float = _scaled_delay(float(params.get(&"delay", 0.0)), plan)
	var hit_count := maxi(int(params.get(&"hit_count", 1)), 1)
	var hit_interval := float(params.get(&"hit_interval", 0.0))
	var hits: Array[float] = []
	for i in hit_count:
		hits.append(delay + hit_interval * float(i))
	return {
		&"radius": radius,
		&"delay": delay,
		&"hit_count": hit_count,
		&"hits": hits,
		&"angle_deg": float(plan.get(&"angle_deg", 0.0)),
	}


## area_size 词缀缩放半径（§3.3：范围半径倍率）。
static func _scaled_area(base: float, plan: Dictionary) -> float:
	var area_mult: float = plan.get(&"area_mult", 1.0)
	return base * area_mult


## duration 词缀缩放延迟（§3.3：持续时间倍率）。
static func _scaled_delay(base: float, plan: Dictionary) -> float:
	var duration_mult: float = plan.get(&"duration_mult", 1.0)
	return base * duration_mult
