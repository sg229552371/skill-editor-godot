## W0 可行性试刀（上级 AI）：验证无界面模式下从零构造 SkillData 并用
## ResourceSaver.save() 落盘，且能被 load() 逐字段还原。
## 产物只写 _probe/，不触碰 content/gems/。跑法见《策划配置表工具_施工总任务书.md》W0。
extends SceneTree

const OUT := "res://mods/jes-skills/tools/content_workbench/_probe/probe_skill.tres"


func _init() -> void:
	var part := SkillPart.new()
	part.damage_channel = 1
	part.damage_effectiveness = 1.0
	part.base_damage = {&"cold": 140.0}
	part.behavior_id = &"bhv_aoe_burst"
	part.behavior_params = {
		&"shape": &"circ",
		&"radius": 130.0,
		&"delay": 0.35,
		&"hit_count": 1,
		&"hit_interval": 0.0,
	}

	var scaling := GemLevelScaling.new()
	scaling.per_level = 0.1
	scaling.knee_level = 0
	scaling.per_level_late = 0.0

	var s := SkillData.new()
	s.gem_id = &"probe_skill"
	s.display_name = "试刀技能"
	var parts: Array[SkillPart] = [part]
	s.parts = parts
	var tags: Array[StringName] = [&"spell", &"aoe", &"cold"]
	s.tags = tags
	var allowed: Array[StringName] = []
	s.allowed_support_tags = allowed
	s.cast_mode = 0
	s.base_cast_time = 0.5
	s.cost_type = 0
	s.base_cost = 12.0
	s.base_cooldown = 2.5
	s.max_charges = 0
	s.charge_recharge_time = 0.0
	s.level_scaling = scaling

	var err: int = ResourceSaver.save(s, OUT)
	if err != OK:
		push_error("W0 试刀：保存失败，错误码 %d" % err)
		quit(1)
		return

	var back := load(OUT) as SkillData
	if back == null:
		push_error("W0 试刀：回读失败，load 返回的不是 SkillData")
		quit(1)
		return

	var failures: Array[String] = []
	_check(failures, "gem_id", back.gem_id == &"probe_skill")
	_check(failures, "display_name", back.display_name == "试刀技能")
	_check(failures, "base_cost", is_equal_approx(back.base_cost, 12.0))
	_check(failures, "base_cooldown", is_equal_approx(back.base_cooldown, 2.5))
	_check(failures, "base_cast_time", is_equal_approx(back.base_cast_time, 0.5))
	_check(failures, "max_charges", back.max_charges == 0)
	_check(failures, "tags", back.tags == tags)
	_check(failures, "parts 数量", back.parts.size() == 1)
	if back.parts.size() == 1:
		var p: SkillPart = back.parts[0]
		_check(failures, "behavior_id", p.behavior_id == &"bhv_aoe_burst")
		_check(failures, "damage_channel", p.damage_channel == 1)
		_check(failures, "base_damage.cold", is_equal_approx(float(p.base_damage.get(&"cold", -1.0)), 140.0))
		_check(failures, "behavior_params.radius", is_equal_approx(float(p.behavior_params.get(&"radius", -1.0)), 130.0))
		_check(failures, "behavior_params.shape", p.behavior_params.get(&"shape") == &"circ")
		_check(failures, "behavior_params.hit_count", int(p.behavior_params.get(&"hit_count", -1)) == 1)
	if back.level_scaling == null:
		failures.append("level_scaling 为 null")
	else:
		_check(failures, "level_scaling.per_level", is_equal_approx(back.level_scaling.per_level, 0.1))

	if failures.is_empty():
		print("W0 试刀通过：ResourceSaver.save 落盘 + load 逐字段还原成功（产物 %s）" % OUT)
		quit(0)
	else:
		push_error("W0 试刀失败字段：" + ", ".join(failures))
		quit(1)


func _check(failures: Array[String], field: String, ok: bool) -> void:
	if not ok:
		failures.append(field)
