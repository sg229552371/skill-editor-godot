# M6 测试：其余行为组件（aoe_burst / channel / summon / dash / buff_self）
# 验收线：规格 §5 行为接口 + §3.3 area_size/duration 管线 + §12 W1 8 主动全部可由数据表达
# 硬门禁：行为只消费计划（纯数据），不认识具体宝石；数值倍率走统一 stat 管线
# 所有期望值均可手算核对。
extends GutTest

const SkillDataScript := preload("res://mods/jes-skills/systems/skills/data/skill_data.gd")
const SkillPartScript := preload("res://mods/jes-skills/systems/skills/data/skill_part.gd")
const ScalingScript := preload("res://mods/jes-skills/systems/skills/data/gem_level_scaling.gd")
const StatModifierScript := preload("res://mods/jes-skills/systems/skills/stat_modifier.gd")
const SkillChannelScript := preload("res://mods/jes-skills/systems/skills/skill_channel.gd")


func _make_stats() -> StatsComponent:
	return StatsComponent.new()


func _mod(stat: StringName, op: int, value: float) -> StatModifier:
	var m := StatModifierScript.new()
	m.stat = stat
	m.op = op
	m.value = value
	m.source_id = &"test:m6"
	return m


func _skill(behavior_id: StringName, params: Dictionary, base_damage: Dictionary = {&"physical": 100.0}) -> SkillData:
	var data: SkillData = SkillDataScript.new()
	data.gem_id = &"test_m6_gem"
	data.display_name = "M6测试技能"
	data.tags = [&"spell"] as Array[StringName]
	data.level_scaling = ScalingScript.new()
	var part: SkillPart = SkillPartScript.new()
	part.damage_channel = SkillChannelScript.Channel.HIT
	part.base_damage = base_damage
	part.damage_effectiveness = 1.0
	part.behavior_id = behavior_id
	part.behavior_params = params
	data.parts = [part]
	return data


# ---------- 注册表：5 个新行为全部注册，且不破坏旧 2 个 ----------
func test_all_behaviors_registered() -> void:
	for bid in [&"bhv_projectile", &"bhv_melee_swing", &"bhv_aoe_burst",
			&"bhv_channel", &"bhv_summon", &"bhv_dash", &"bhv_buff_self"]:
		assert_true(SkillExecutor.BEHAVIORS.has(bid), "行为应已注册: %s" % bid)
	assert_eq(SkillExecutor.BEHAVIORS.size(), 7, "共 7 个行为")


# ---------- aoe_burst 金样：radius 160 / delay 0.15（火焰新星参数） ----------
func test_aoe_burst_golden() -> void:
	var data := _skill(&"bhv_aoe_burst", {&"radius": 160.0, &"delay": 0.15, &"hit_count": 1})
	var plans := SkillExecutor.cast(data, 1, _make_stats())
	assert_eq(plans.size(), 1, "非投射行为单条计划")
	var burst := BhvAoeBurst.plan_to_burst(plans[0])
	assert_almost_eq(float(burst.get(&"radius")), 160.0, 0.0001)
	assert_almost_eq(float(burst.get(&"delay")), 0.15, 0.0001)
	assert_eq(int(burst.get(&"hit_count")), 1)


# ---------- area_size INCREASED +50% → radius 160 × 1.5 = 240 ----------
func test_aoe_burst_area_size_increased() -> void:
	var data := _skill(&"bhv_aoe_burst", {&"radius": 160.0, &"delay": 0.15})
	var sc := _make_stats()
	sc.add_modifier(_mod(&"area_size", StatModifierScript.Op.INCREASED, 50.0))
	var plans := SkillExecutor.cast(data, 1, sc)
	var burst := BhvAoeBurst.plan_to_burst(plans[0])
	assert_almost_eq(float(burst.get(&"radius")), 240.0, 0.0001, "160 × 1.5 = 240")


# ---------- area_size INC+30% 与 MORE+25% 混合：160 × 1.3 × 1.25 = 260 ----------
func test_aoe_burst_area_size_inc_more_mixed() -> void:
	var data := _skill(&"bhv_aoe_burst", {&"radius": 160.0, &"delay": 0.0})
	var sc := _make_stats()
	sc.add_modifier(_mod(&"area_size", StatModifierScript.Op.INCREASED, 30.0))
	sc.add_modifier(_mod(&"area_size", StatModifierScript.Op.MORE, 25.0))
	var plans := SkillExecutor.cast(data, 1, sc)
	var burst := BhvAoeBurst.plan_to_burst(plans[0])
	assert_almost_eq(float(burst.get(&"radius")), 260.0, 0.0001, "160 × 1.3 × 1.25 = 260")


# ---------- aoe_burst hit_count=2 多段打击（W4 连环爆裂形态） ----------
func test_aoe_burst_hit_count_two() -> void:
	var data := _skill(&"bhv_aoe_burst", {&"radius": 120.0, &"delay": 0.1, &"hit_count": 2, &"hit_interval": 0.3})
	var plans := SkillExecutor.cast(data, 1, _make_stats())
	var burst := BhvAoeBurst.plan_to_burst(plans[0])
	assert_eq(int(burst.get(&"hit_count")), 2)
	var hits: Array = burst.get(&"hits")
	assert_eq(hits.size(), 2, "两段打击时刻")
	assert_almost_eq(float(hits[0]), 0.1, 0.0001, "第一击 = delay")
	assert_almost_eq(float(hits[1]), 0.4, 0.0001, "第二击 = delay + hit_interval")


# ---------- channel 金样：tick 0.25 / max 3.0 → 12 tick（引导光束参数） ----------
func test_channel_golden() -> void:
	var data := _skill(&"bhv_channel", {&"tick_interval": 0.25, &"max_channel_time": 3.0})
	var plans := SkillExecutor.cast(data, 1, _make_stats())
	assert_eq(plans.size(), 1)
	var ch := BhvChannel.plan_to_channel(plans[0])
	assert_almost_eq(float(ch.get(&"tick_interval")), 0.25, 0.0001)
	assert_almost_eq(float(ch.get(&"max_channel_time")), 3.0, 0.0001)
	assert_eq(int(ch.get(&"tick_count")), 12, "3.0 / 0.25 = 12 tick")


# ---------- duration INCREASED +50% → 引导时长 3.0 × 1.5 = 4.5 → 18 tick ----------
func test_channel_duration_scaling() -> void:
	var data := _skill(&"bhv_channel", {&"tick_interval": 0.25, &"max_channel_time": 3.0})
	var sc := _make_stats()
	sc.add_modifier(_mod(&"duration", StatModifierScript.Op.INCREASED, 50.0))
	var plans := SkillExecutor.cast(data, 1, sc)
	var ch := BhvChannel.plan_to_channel(plans[0])
	assert_almost_eq(float(ch.get(&"max_channel_time")), 4.5, 0.0001)
	assert_eq(int(ch.get(&"tick_count")), 18, "4.5 / 0.25 = 18 tick")


# ---------- duration INC+50% 与 MORE+40% 混合（W4 延时持久形态）：8 × 1.5 × 1.4 = 16.8 ----------
func test_buff_duration_inc_more_mixed() -> void:
	var data := _skill(&"bhv_buff_self", {&"duration": 8.0, &"buff_mods": []})
	var sc := _make_stats()
	sc.add_modifier(_mod(&"duration", StatModifierScript.Op.INCREASED, 50.0))
	sc.add_modifier(_mod(&"duration", StatModifierScript.Op.MORE, 40.0))
	var plans := SkillExecutor.cast(data, 1, sc)
	var buff := BhvBuffSelf.plan_to_buff(plans[0])
	assert_almost_eq(float(buff.get(&"duration")), 16.8, 0.0001, "8 × 1.5 × 1.4 = 16.8")


# ---------- summon 金样：max_count 3（召唤骷髅参数） ----------
func test_summon_golden() -> void:
	var data := _skill(&"bhv_summon", {&"max_count": 3})
	var plans := SkillExecutor.cast(data, 1, _make_stats())
	assert_eq(plans.size(), 1)
	var sm := BhvSummon.plan_to_summon(plans[0])
	assert_eq(int(sm.get(&"max_count")), 3)


# ---------- dash 金样：distance 300 / speed 1500 → 位移 0.2s（冲锋参数） ----------
func test_dash_golden() -> void:
	var data := _skill(&"bhv_dash", {&"distance": 300.0, &"speed": 1500.0})
	var plans := SkillExecutor.cast(data, 1, _make_stats())
	assert_eq(plans.size(), 1)
	var d := BhvDash.plan_to_dash(plans[0])
	assert_almost_eq(float(d.get(&"distance")), 300.0, 0.0001)
	assert_almost_eq(float(d.get(&"speed")), 1500.0, 0.0001)
	assert_almost_eq(float(d.get(&"move_time")), 0.2, 0.0001, "300 / 1500 = 0.2s")


# ---------- buff_self 金样：duration 8 + 增益词缀透传（熔岩护体形态） ----------
func test_buff_self_golden() -> void:
	var mods := [{"stat": &"damage_taken", "op": 0, "value": -10.0}]
	var data := _skill(&"bhv_buff_self", {&"duration": 8.0, &"buff_mods": mods})
	var plans := SkillExecutor.cast(data, 1, _make_stats())
	var buff := BhvBuffSelf.plan_to_buff(plans[0])
	assert_almost_eq(float(buff.get(&"duration")), 8.0, 0.0001, "无 duration 词缀时 1.0 倍")
	var out_mods: Array = buff.get(&"buff_mods")
	assert_eq(out_mods.size(), 1, "增益词缀透传")
	assert_eq(out_mods[0].get("stat"), &"damage_taken")


# ---------- W5 边界零代码证明：melee 360° 环形仅改数据即可表达 ----------
func test_melee_arc_360_boundary() -> void:
	var data := _skill(&"bhv_melee_swing", {&"arc_deg": 360.0, &"range": 90.0})
	var plans := SkillExecutor.cast(data, 1, _make_stats())
	var swing := BhvMeleeSwing.plan_to_swing(plans[0])
	assert_almost_eq(float(swing.get(&"arc_deg")), 360.0, 0.0001, "360° 环形仅数据")
	assert_almost_eq(float(swing.get(&"range")), 90.0, 0.0001)


# ---------- 回归：未知行为仍被跳过，不崩溃 ----------
func test_unknown_behavior_still_skipped() -> void:
	var data := _skill(&"bhv_nonexistent", {})
	var plans := SkillExecutor.cast(data, 1, _make_stats())
	assert_eq(plans.size(), 0)
