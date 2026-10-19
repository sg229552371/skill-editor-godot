# bhv_summon（规格 §5 / M6）：召唤行为。实例化数量受词缀缩放，共享施法者召唤物伤害词缀。
# 不认识具体宝石，只消费行为计划。本里程碑只产出纯数据计划参数（真实场景实例化在演出层接入）。
class_name BhvSummon
extends RefCounted


## 从单条计划提取召唤参数。
static func plan_to_summon(plan: Dictionary) -> Dictionary:
	var params: Dictionary = plan.get(&"params", {})
	var max_count := maxi(int(params.get(&"max_count", 1)), 0)
	return {
		&"max_count": max_count,
		&"scene_path": String(params.get(&"scene", "")),
		&"lifetime": _scaled_lifetime(float(params.get(&"lifetime", 0.0)), plan),
	}


## duration 词缀缩放召唤物存续时间；0 = 永久（跟随上限管理）。
static func _scaled_lifetime(base: float, plan: Dictionary) -> float:
	var duration_mult: float = plan.get(&"duration_mult", 1.0)
	return base * duration_mult
