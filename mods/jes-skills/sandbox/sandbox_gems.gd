# 沙盒演示宝石工厂（S3）：程序化构建覆盖 7 行为 × 5 元素的演示技能。
# 全部为 Resource 构造器：装配/消耗/施法/命中仍走通用管线，本文件不含任何运行时逻辑。
# 硬门禁：无 gem_id 分支（这里是数据构造，不是运行时判定）。
extends RefCounted

# ---------- 演示参数常量（集中声明） ----------
const BASE_COST := 10.0
const SUMMON_COST := 20.0
const SCALE_PER_LEVEL := 0.1
const FROST_SPEED := 600.0
const FROST_LIFETIME := 2.0
const FROST_SPREAD := 6.0
const FIRE_RADIUS := 100.0
const FIRE_DELAY := 0.5
const MELEE_RANGE := 130.0
const MELEE_ARC := 90.0
const CHANNEL_TICK := 0.5
const CHANNEL_TIME := 2.0
const DASH_DISTANCE := 300.0
const DASH_SPEED := 1000.0
const BUFF_DURATION := 5.0
const SUMMON_LIFETIME := 10.0


static func _tags(arr: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for t in arr:
		out.append(StringName(t))
	return out


static func _scaling(per_level: float) -> GemLevelScaling:
	var s := GemLevelScaling.new()
	s.per_level = per_level
	return s


static func _part(base: Dictionary, behavior: StringName, params: Dictionary) -> SkillPart:
	var p := SkillPart.new()
	p.damage_channel = SkillChannel.Channel.HIT
	var d := {}
	for k in base:
		d[StringName(k)] = float(base[k])
	p.base_damage = d
	p.damage_effectiveness = 1.0
	p.behavior_id = behavior
	p.behavior_params = params
	return p


static func _skill(id: String, display: String, tags: Array, part: SkillPart,
		cost: float = BASE_COST, cooldown: float = 0.0,
		charges: int = 0, recharge: float = 0.0) -> SkillData:
	var s := SkillData.new()
	s.gem_id = StringName(id)
	s.display_name = display
	s.tags = _tags(tags)
	var parts: Array[SkillPart] = [part]
	s.parts = parts
	s.base_cost = cost
	s.base_cooldown = cooldown
	s.max_charges = charges
	s.charge_recharge_time = recharge
	s.level_scaling = _scaling(SCALE_PER_LEVEL)
	s.allowed_support_tags = []   # 空 = 接受所有辅助
	return s


# ---------- 7 行为 × 5 元素演示技能（槽 0~6） ----------

## 槽 0：霜矛（bhv_projectile / cold）
static func frost_shard() -> SkillData:
	return _skill("frost_shard", "霜矛",
		["attack", "projectile", "cold"],
		_part({&"cold": 100.0}, &"bhv_projectile", {
			&"count_base": 1.0, &"speed": FROST_SPEED,
			&"radius": 14.0, &"lifetime": FROST_LIFETIME,
			&"spread_deg": FROST_SPREAD,
		}))


## 槽 1：烈焰爆发（bhv_aoe_burst / fire）
static func fire_burst() -> SkillData:
	return _skill("fire_burst", "烈焰爆发",
		["spell", "aoe", "fire"],
		_part({&"fire": 150.0}, &"bhv_aoe_burst", {
			&"radius": FIRE_RADIUS, &"delay": FIRE_DELAY,
			&"hit_count": 1, &"hit_interval": 0.0,
		}), 10.0, 2.0)


## 槽 2：雷光斩（bhv_melee_swing / lightning + physical，3 充能）
static func lightning_slash() -> SkillData:
	return _skill("lightning_slash", "雷光斩",
		["attack", "melee", "lightning"],
		_part({&"physical": 30.0, &"lightning": 120.0}, &"bhv_melee_swing", {
			&"arc_deg": MELEE_ARC, &"range": MELEE_RANGE,
		}), 10.0, 0.0, 3, 1.0)


## 槽 3：蚀骨引线（bhv_channel / chaos）
static func chaos_beam() -> SkillData:
	return _skill("chaos_beam", "蚀骨引线",
		["spell", "channel", "chaos"],
		_part({&"chaos": 40.0}, &"bhv_channel", {
			&"tick_interval": CHANNEL_TICK, &"max_channel_time": CHANNEL_TIME,
		}), 10.0, 3.0)


## 槽 4：暗影冲刺（bhv_dash / physical，带路径伤害）
static func shadow_dash() -> SkillData:
	return _skill("shadow_dash", "暗影冲刺",
		["attack", "movement", "physical"],
		_part({&"physical": 80.0}, &"bhv_dash", {
			&"distance": DASH_DISTANCE, &"speed": DASH_SPEED,
			&"path_damage": {&"physical": 80.0},
		}), 10.0, 4.0)


## 槽 5：狂暴（bhv_buff_self / 自身增益，无伤害段）
static func berserk() -> SkillData:
	var mods: Array = [
		{&"stat": &"physical_damage", &"op": 1, &"value": 30.0},   # INCREASED +30%
		{&"stat": &"crit_chance", &"op": 0, &"value": 25.0},       # FLAT_ADD +25%
	]
	return _skill("berserk", "狂暴",
		["spell", "buff"],
		_part({}, &"bhv_buff_self", {
			&"duration": BUFF_DURATION, &"buff_mods": mods,
		}), 10.0, 6.0)


## 槽 6：灵魂召唤（bhv_summon / 召唤物近战）
static func spirit_summon() -> SkillData:
	return _skill("spirit_summon", "灵魂召唤",
		["spell", "summon", "physical"],
		_part({}, &"bhv_summon", {
			&"max_count": 2, &"lifetime": SUMMON_LIFETIME,
		}), SUMMON_COST, 5.0)


## 槽 0~6 顺序表
static func all_skills() -> Array:
	return [frost_shard(), fire_burst(), lightning_slash(), chaos_beam(),
		shadow_dash(), berserk(), spirit_summon()]


# ---------- 演示辅助宝石（槽 7 组合用） ----------

## 多重投射：require projectile，追加 2 发，耗魔 ×1.4
static func support_multi_projectile() -> SupportGemData:
	var s := SupportGemData.new()
	s.support_id = &"support_multi"
	s.display_name = "多重投射"
	s.require_tags = _tags(["projectile"])
	s.cost_multiplier = 1.4
	s.behavior_overrides = {&"projectile_count": {&"add": 2.0}}
	return s


## 寒冷聚焦：require cold，寒冷伤害 +50%，耗魔 ×1.2
static func support_cold_focus() -> SupportGemData:
	var s := SupportGemData.new()
	s.support_id = &"support_cold_focus"
	s.display_name = "寒冷聚焦"
	s.require_tags = _tags(["cold"])
	s.cost_multiplier = 1.2
	var spec := ModifierSpec.new()
	spec.stat = &"cold_damage"
	spec.op = StatModifier.Op.INCREASED
	spec.value = 50.0
	var mods: Array[ModifierSpec] = [spec]
	s.stat_modifiers = mods
	return s


# ---------- 演示触发器（on_crit → 槽 2） ----------

## 必暴触发：暴击时施放槽 2（雷光斩），CD 2s
static func trigger_on_crit() -> TriggerData:
	var td := TriggerData.new()
	td.event = &"on_crit"
	td.chance = 1.0
	td.cooldown = 2.0
	td.linked_slot_index = 2
	return td
