# bhv_channel（规格 §5 / M6）：引导行为。按 tick 结算，受 duration 词缀缩放。
# 不认识具体宝石，只消费行为计划。本里程碑只产出纯数据计划参数。
class_name BhvChannel
extends RefCounted


## 从单条计划提取引导参数（tick 时刻列表供真实结算器消费）。
static func plan_to_channel(plan: Dictionary) -> Dictionary:
	var params: Dictionary = plan.get(&"params", {})
	var tick_interval: float = maxf(float(params.get(&"tick_interval", 0.25)), 0.01)
	var max_time: float = _scaled_channel_time(float(params.get(&"max_channel_time", 3.0)), plan)
	var tick_count := int(floor(max_time / tick_interval))
	var ticks: Array[float] = []
	for i in tick_count:
		ticks.append(tick_interval * float(i + 1))
	return {
		&"tick_interval": tick_interval,
		&"max_channel_time": max_time,
		&"tick_count": tick_count,
		&"ticks": ticks,
	}


## duration 词缀缩放引导时长（§3.3：持续时间倍率）。
static func _scaled_channel_time(base: float, plan: Dictionary) -> float:
	var duration_mult: float = plan.get(&"duration_mult", 1.0)
	return base * duration_mult
