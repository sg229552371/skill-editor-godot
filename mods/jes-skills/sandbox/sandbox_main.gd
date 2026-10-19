# 沙盒主控（S3）：程序化搭建玩家 + 木桩 + 技能栏，把整套运行时串成闭环。
# 施法链路：SocketGraph.assemble → 注入 modifiers → 消耗 → 冷却 → SkillExecutor.cast
#         → 行为计划 → 演出（投射物/近战/范围/引导/冲刺/buff/召唤）→ 命中结算 → 事件总线
# 硬门禁：无 gem_id 运行时分支（行为分派读计划 behavior_id）；无 Timer 节点；
#         RNG 注入（种子固定，确定性可回放）。
class_name SandboxMain
extends Node2D

const GEMS := preload("res://mods/jes-skills/sandbox/sandbox_gems.gd")
const RNG_SEED := 20261019
const PLAYER_START := Vector2(300, 300)
const STUMP_SPACING := Vector2(0, 110)
const STUMP_START := Vector2(700, 190)
const RESPAWN_WAIT := 2.0
const MANA_MAX := 200.0
const MANA_REGEN_PER_SEC := 20.0
const ACTIVE_SLOT_COUNT := 7
const TRIGGER_SLOT := 7   # 触发器目标槽（雷光斩的复制实例，含 on_crit 触发）

# 行为分派只认计划里的 behavior_id（数据驱动，与宝石无关）
const BEHAVIOR_HANDLERS := {
	&"bhv_projectile": &"_exec_projectile",
	&"bhv_melee_swing": &"_exec_melee",
	&"bhv_aoe_burst": &"_exec_aoe",
	&"bhv_channel": &"_exec_channel",
	&"bhv_dash": &"_exec_dash",
	&"bhv_buff_self": &"_exec_buff",
	&"bhv_summon": &"_exec_summon",
}

var rng := RandomNumberGenerator.new()
var bus := CombatEventBus.new()

var player: SandboxEntity = null
var stumps: Array = []          # Array[SandboxEntity]
var entities: Array = []        # Array[SandboxEntity]（玩家 + 木桩，投射物目标列表）

var mana := ResourcePool.new()
var slot_bar := SkillSlotBar.new()
var cooldowns: Array = []       # Array[CooldownComponent]，与槽位对齐
var trigger_mgr := TriggerManager.new()

var projectile_pool := ProjectilePool.new()
var projectiles: Array = []     # Array[SandboxProjectile]

# 进行中效果状态
var _pending_aoe: Array = []    # {fire_at, radius, elements, tags}
var _channel: Dictionary = {}   # {tick_times, next_idx, plan, start_at}
var _dash: Dictionary = {}      # {remaining, dir, speed, plan, hit_cd}
var _buffs: Array = []          # {until, mods, source_id}
var _summons: Array = []        # {until, node}
var _elapsed: float = 0.0
var _hud = null                 # SandboxHud（可选）


func _ready() -> void:
	rng.seed = RNG_SEED
	_build_entities()
	_build_skills()
	trigger_mgr.bus = bus
	trigger_mgr._ready()
	trigger_mgr.trigger_cast_requested.connect(_on_trigger_cast)
	# 总线演出观测（HUD 计数）
	var hud := get_node_or_null("Hud")
	if hud != null:
		_hud = hud
		_hud.main = self


## 玩家 + 三种木桩（普通 / 50% 全抗 / 200 护甲）
func _build_entities() -> void:
	player = SandboxEntity.new("player", true)
	player.position = PLAYER_START
	add_child(player)
	entities.append(player)
	player.hurtbox.owner_died.connect(_on_entity_died.bind(player))

	var stump_defs := [
		{"name": "stump_plain", "mods": []},
		{"name": "stump_resist", "mods": [
			{"stat": &"fire_resistance", "op": 0, "value": 50.0},
			{"stat": &"cold_resistance", "op": 0, "value": 50.0},
			{"stat": &"lightning_resistance", "op": 0, "value": 50.0},
			{"stat": &"chaos_resistance", "op": 0, "value": 50.0},
		]},
		{"name": "stump_armor", "mods": [
			{"stat": &"armor", "op": 0, "value": 200.0},
		]},
	]
	for i in stump_defs.size():
		var def: Dictionary = stump_defs[i]
		var e := SandboxEntity.new(def["name"], false)
		e.position = STUMP_START + STUMP_SPACING * float(i)
		add_child(e)
		var idx := 0
		for m in def["mods"]:
			var mod := StatModifier.new()
			mod.stat = m["stat"]
			mod.op = m["op"]
			mod.value = m["value"]
			mod.source_id = StringName("stump_def_%d" % idx)
			e.stats.add_modifier(mod)
			idx += 1
		stumps.append(e)
		entities.append(e)
		e.hurtbox.owner_died.connect(_on_entity_died.bind(e))


## 7 个主动槽（0~6 演示技能）+ 槽 7（触发器专用雷光斩复制）+ 演示辅助/触发器
func _build_skills() -> void:
	mana.set_max(&"mana", MANA_MAX)
	mana.set_current(&"mana", MANA_MAX)

	var skills: Array = GEMS.all_skills()
	for i in ACTIVE_SLOT_COUNT:
		_bind_skill_slot(i, skills[i])
	# 槽 7：触发器目标（独立 SkillSlot 实例，防止与槽 2 共用装配状态）
	_bind_skill_slot(TRIGGER_SLOT, GEMS.lightning_slash())

	# 槽 0 挂多重投射 + 寒冰聚焦双辅助（演示 G5/G6 装配链路 + stat_modifiers 注入链路：
	# 霜矛为 projectile+cold，两个辅助均兼容；cost = 10 × 1.4 × 1.2 = 16.8）
	var slot0 := slot_bar.get_slot(0)
	slot0.supports.append(GEMS.support_multi_projectile())
	slot0.supports.append(GEMS.support_cold_focus())

	# 演示触发器：暴击 → 施放槽 7
	trigger_mgr.add_trigger(GEMS.trigger_on_crit())


func _bind_skill_slot(index: int, skill: SkillData) -> void:
	var slot := SkillSlot.new()
	slot.slot_index = index
	slot.active_gem = skill
	slot.active_level = 1
	slot.socket_count = 4
	slot_bar.bind_slot(index, slot)
	var cd := CooldownComponent.new()
	cd.configure(skill.base_cooldown, 1.0, skill.max_charges, skill.charge_recharge_time)
	cooldowns.append(cd)


# ---------------- 输入 ----------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event
		# 1~7 施放槽 0~6；Q 触发演示组合；R 全体木桩回满血
		if key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_7:
			try_cast(int(key.physical_keycode) - KEY_1)
		elif key.physical_keycode == KEY_Q:
			_demo_combo()
		elif key.physical_keycode == KEY_R:
			for s in stumps:
				s.respawn()


# ---------------- 施法主链路 ----------------

## 完整施法流程：装配 → 注词缀 → 消耗/冷却 → 计划 → 执行。供按键与触发器共用。
func try_cast(slot_index: int) -> bool:
	var slot := slot_bar.get_slot(slot_index)
	if slot == null or slot.active_gem == null:
		return false
	var cd: CooldownComponent = cooldowns[slot_index]
	if not cd.is_ready():
		return false
	var skill: SkillData = slot.active_gem

	# ① 装配（六步纯函数）
	var res := SocketGraph.assemble(slot)
	if not res.ok:
		return false
	# ② 辅助词缀注入（source_id = 槽位，卸下即还原）
	var source_id := StringName("slot_%d" % slot_index)
	player.stats.add_modifiers(res.modifiers, source_id)

	# ③ 消耗判定（资源不足不进入 cast，规格 §8.3）
	var cost := CostCalculator.compute_cost(skill, res.cost_multiplier, 1.0)
	if not mana.can_afford(&"mana", cost):
		player.stats.remove_by_source(source_id)
		return false
	mana.spend(&"mana", cost)

	# ④ 冷却/充能消耗
	cd.start()

	# ⑤ 出手结算 → 行为计划
	var plans := SkillExecutor.cast(skill, slot.active_level, player.stats,
			[], res.behavior_overrides)
	player.stats.remove_by_source(source_id)

	# ⑥ 执行计划（演出层）
	for plan in plans:
		_execute_plan(plan)
	return true


func _execute_plan(plan: Dictionary) -> void:
	var behavior: StringName = plan.get(&"behavior_id", &"")
	var handler: StringName = BEHAVIOR_HANDLERS.get(behavior, &"")
	if handler != &"":
		call(handler, plan)


# ---------------- 各行为执行（只读计划，不认识宝石） ----------------

func _nearest_stump_pos() -> Vector2:
	# AOE 落点对准最近的存活木桩；无目标时回退玩家右前方 120px
	for t in stumps:
		if not t.is_dead():
			return t.global_position
	return player.global_position + Vector2.RIGHT * 120.0


func _aim_angle() -> float:
	# 朝最近存活木桩瞄准；无目标则朝右
	var best: SandboxEntity = null
	var best_d := INF
	for t in stumps:
		if t.is_dead():
			continue
		var d: float = t.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = t
	if best == null:
		return 0.0
	return (best.global_position - player.global_position).angle()


func _exec_projectile(plan: Dictionary) -> void:
	var launch := BhvProjectile.plan_to_launch(plan)
	# SkillExecutor already splits multi-shot into one plan per projectile,
	# so each plan must spawn exactly one projectile (launch count is per-plan).
	for i in mini(int(launch[&"count"]), 1):
		var base_angle: float = _aim_angle() + deg_to_rad(float(launch[&"angle_deg"]))
		var p := SandboxProjectile.new()
		add_child(p)
		p.global_position = player.global_position
		p.setup(_make_packet(plan), player.stats, projectile_pool, launch[&"pierce"])
		p.speed = launch[&"speed"]
		p.lifetime = launch[&"lifetime"]
		p.radius = launch[&"radius"]
		p.direction = Vector2.RIGHT.rotated(base_angle)
		projectiles.append(p)


func _exec_melee(plan: Dictionary) -> void:
	var swing := BhvMeleeSwing.plan_to_swing(plan)
	var aim := _aim_angle()
	var half := deg_to_rad(float(swing[&"arc_deg"])) / 2.0
	var rng_len := float(swing[&"range"])
	var packet := _make_packet(plan)
	for t in stumps:
		if t.is_dead():
			continue
		var to_t: Vector2 = t.global_position - player.global_position
		if to_t.length() > rng_len + t.radius():
			continue
		if absf(angle_difference(aim, to_t.angle())) > half:
			continue
		_strike(packet, t)


func _exec_aoe(plan: Dictionary) -> void:
	var burst := BhvAoeBurst.plan_to_burst(plan)
	for fire_time in burst[&"hits"]:
		_pending_aoe.append({
			&"fire_at": _elapsed + float(fire_time),
			&"radius": float(burst[&"radius"]),
			&"center": player.global_position + Vector2.RIGHT.rotated(_aim_angle()) \
					* player.global_position.distance_to(_nearest_stump_pos()),
			&"plan": plan,
		})


func _exec_channel(plan: Dictionary) -> void:
	var ch := BhvChannel.plan_to_channel(plan)
	_channel = {
		&"tick_times": ch[&"ticks"],
		&"next_idx": 0,
		&"plan": plan,
		&"start_at": _elapsed,
	}


func _exec_dash(plan: Dictionary) -> void:
	var dash := BhvDash.plan_to_dash(plan)
	_dash = {
		&"remaining": float(dash[&"move_time"]),
		&"speed": float(dash[&"speed"]),
		&"dir": Vector2.RIGHT.rotated(_aim_angle()),
		&"plan": plan,
		&"has_path_damage": dash[&"has_path_damage"],
	}


func _exec_buff(plan: Dictionary) -> void:
	var buff := BhvBuffSelf.plan_to_buff(plan)
	var source_id := StringName("buff_%f" % _elapsed)
	player.stats.add_modifiers(_dicts_to_modifiers(buff[&"buff_mods"]), source_id)
	_buffs.append({&"until": _elapsed + float(buff[&"duration"]), &"source_id": source_id})


func _exec_summon(plan: Dictionary) -> void:
	var s := BhvSummon.plan_to_summon(plan)
	var summoned: Array = []
	for i in int(s[&"max_count"]):
		var minion := SandboxEntity.new("summon_%d" % (randi() % 1000), false, 14.0)
		minion.position = player.global_position + Vector2(-40.0, -30.0 + 30.0 * float(i))
		add_child(minion)
		summoned.append(minion)
	if not summoned.is_empty():
		_summons.append({&"until": _elapsed + float(s[&"lifetime"]), &"nodes": summoned})


# ---------------- 命中与事件 ----------------

func _make_packet(plan: Dictionary) -> DamagePacket:
	var packet := DamagePacket.new()
	packet.elements = plan.get(&"elements", {})
	packet.tags = plan.get(&"tags", [])
	packet.source_instance_id = &"sandbox"
	return packet


## 命中闭环：Hitbox.strike → DamageCalculator.resolve → receive_hit → 扣血 + 总线广播。
func _strike(packet: DamagePacket, target: SandboxEntity) -> Dictionary:
	var hitbox := HitboxComponent.new()
	hitbox.packet = packet
	hitbox.attacker_stats = player.stats
	# DamageCalculator defender 契约要求传含 .stats 的实体本身（hurtbox 只负责收伤）
	var hit := hitbox.strike(target.hurtbox, rng, target)
	hitbox.free()
	# 总线事件（触发器链路的数据源）：命中 + 暴击
	bus.hit_landed.emit(packet, target)
	if hit.get(&"crit", false):
		bus.crit_landed.emit(packet, target)
	return hit


## 木桩死亡：总线击杀事件 + 定时重生。
func _on_entity_died(e: SandboxEntity) -> void:
	if e == player:
		return   # 玩家死亡本沙盒不做失败结算，只标记
	bus.entity_killed.emit(e, null)
	e.start_respawn(RESPAWN_WAIT)


func _on_trigger_cast(slot_index: int) -> void:
	try_cast(slot_index)


# ---------------- 主循环驱动（统一 tick，无 Timer 节点） ----------------

func _process(delta: float) -> void:
	tick(delta)


func tick(dt: float) -> void:
	_elapsed += dt
	# 回蓝（简单线性回蓝，演示资源系统）
	mana.set_current(&"mana", mana.get_current(&"mana") + MANA_REGEN_PER_SEC * dt)
	# 冷却推进
	for cd in cooldowns:
		cd.advance(dt)
	# 触发器推进
	trigger_mgr.advance(dt)
	# 实体推进（DoT / 重生）
	for e in entities:
		e.tick(dt)
	# 投射物推进
	var live: Array = []
	for p in projectiles:
		if p.is_active():
			p.tick(dt, entities, rng)
		if p.is_active():
			live.append(p)
		else:
			p.queue_free()
	projectiles = live
	_tick_aoe(dt)
	_tick_channel()
	_tick_dash(dt)
	_tick_buffs()
	_tick_summons()


func _tick_aoe(_dt: float) -> void:
	var remaining: Array = []
	for a in _pending_aoe:
		if _elapsed >= float(a[&"fire_at"]):
			var packet := _make_packet(a[&"plan"])
			for t in stumps:
				if not t.is_dead() \
						and t.global_position.distance_to(a[&"center"]) <= float(a[&"radius"]) + t.radius():
					_strike(packet, t)
		else:
			remaining.append(a)
	_pending_aoe = remaining


func _tick_channel() -> void:
	if _channel.is_empty():
		return
	var times: Array = _channel[&"tick_times"]
	var idx := int(_channel[&"next_idx"])
	var start: float = _channel[&"start_at"]
	while idx < times.size() and _elapsed - start >= float(times[idx]):
		# 每 tick 沿引导方向做一次小范围判定
		var packet := _make_packet(_channel[&"plan"])
		var beam_end: Vector2 = player.global_position + Vector2.RIGHT.rotated(_aim_angle()) * 400.0
		for t in stumps:
			if t.is_dead():
				continue
			# 点到线段距离
			var closest: Vector2 = _closest_point(player.global_position, beam_end, t.global_position)
			if closest.distance_to(t.global_position) <= t.radius() + 10.0:
				_strike(packet, t)
		idx += 1
	_channel[&"next_idx"] = idx
	if idx >= times.size():
		_channel = {}


func _tick_dash(dt: float) -> void:
	if _dash.is_empty():
		return
	var step: float = float(_dash[&"speed"]) * dt
	player.global_position += Vector2(_dash[&"dir"]) * step
	_dash[&"remaining"] = float(_dash[&"remaining"]) - dt
	if bool(_dash[&"has_path_damage"]):
		var packet := _make_packet(_dash[&"plan"])
		for t in stumps:
			if not t.is_dead() \
					and t.global_position.distance_to(player.global_position) <= 40.0 + t.radius():
				_strike(packet, t)
	if float(_dash[&"remaining"]) <= 0.0:
		_dash = {}


func _tick_buffs() -> void:
	var remaining: Array = []
	for b in _buffs:
		if _elapsed < float(b[&"until"]):
			remaining.append(b)
		else:
			player.stats.remove_by_source(b[&"source_id"])
	_buffs = remaining


func _tick_summons() -> void:
	var remaining: Array = []
	for s in _summons:
		if _elapsed < float(s[&"until"]):
			remaining.append(s)
		else:
			for n in s[&"nodes"]:
				# 冒烟测试中 main 常在树外驱动，queue_free 不生效，演示层统一用 free()
				n.free()
	_summons = remaining


# ---------------- 演示组合与工具 ----------------

## Q 键演示：多重投射霜矛（槽 0 已带辅助）→ 展示装配 + 多发 + 触发链。
func _demo_combo() -> void:
	try_cast(0)


func _closest_point(a: Vector2, b: Vector2, p: Vector2) -> Vector2:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return a + ab * t


func _dicts_to_modifiers(arr: Array) -> Array:
	var out: Array = []
	for d in arr:
		var m := StatModifier.new()
		m.stat = d.get(&"stat", &"")
		m.op = int(d.get(&"op", 0))
		m.value = float(d.get(&"value", 0.0))
		out.append(m)
	return out
