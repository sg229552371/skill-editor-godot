# M8 投射物 SoA 容器测试（2026-10-19 R4）：ProjectileField
# 目标：headless 验证「无 Node 的投射物」在生命周期/命中/穿透/容量/哈希一致性上全部正确。
# 硬门禁：不建任何投射物 Node；目标用鸭子类型假体；RNG 注入固定种子。
extends GutTest

const FieldScript := preload("res://mods/jes-skills/systems/skills/combat/projectile_field.gd")


# ---------------- 假体（鸭子类型契约：is_dead/global_position/radius/hurtbox/stats） ----------------

class FakeHurtbox extends RefCounted:
	var hits: Array = []

	func receive_hit(hit: Dictionary, _source) -> void:
		hits.append(hit)


class FakeTarget extends RefCounted:
	var stats := StatsComponent.new()
	var hurtbox := FakeHurtbox.new()
	var global_position := Vector2.ZERO
	var dead := false
	var _radius := 20.0

	func _init(pos: Vector2, r: float = 20.0) -> void:
		global_position = pos
		_radius = r
		# 注意：这里**不能**让 hurtbox 反向持有 target —— RefCounted 不回收引用环，
		# 双向引用会直接变成 ObjectDB 泄漏（824 个实例的教训）

	func is_dead() -> bool:
		return dead

	func radius() -> float:
		return _radius

	func hit_count() -> int:
		return hurtbox.hits.size()

	func damage_taken() -> float:
		var total := 0.0
		for h in hurtbox.hits:
			total += float(h.get(&"total", 0.0))
		return total


# ---------------- 工具 ----------------

var field: ProjectileField = null
var rng := RngService.new(12345)


func before_each() -> void:
	rng = RngService.new(12345)   # 每个用例重置：同 seed ⇒ 同暴击序列
	field = FieldScript.new(16)


func after_each() -> void:
	# RefCounted 靠引用计数释放；显式置空让内部的复用 Hitbox(Area2D) 及时 free
	field = null


func _packet(amount: float = 10.0) -> DamagePacket:
	var p := DamagePacket.new()
	p.elements = {&"physical": amount}
	p.source_instance_id = &"test"
	return p


func _spawn(from: Vector2, dir: Vector2, speed: float, life: float,
		radius: float, pierce: int) -> int:
	return field.spawn(from, dir, speed, life, radius, pierce,
			_packet(), null, StatsComponent.new())


func _hash_of(targets: Array, cell: float = 64.0) -> SpatialHash:
	var h := SpatialHash.new(cell)
	for i in targets.size():
		h.insert(i, targets[i].global_position)
	return h


# ---------------- 生命周期 ----------------

func test_pf1_spawn_writes_soa_fields() -> void:
	var i := _spawn(Vector2(10, 20), Vector2.RIGHT, 400.0, 1.5, 8.0, 2)
	assert_eq(i, 0, "首发应落在下标 0")
	assert_eq(field.alive[i], 1)
	assert_almost_eq(field.px[i], 10.0, 0.0001)
	assert_almost_eq(field.py[i], 20.0, 0.0001)
	assert_almost_eq(field.vx[i], 400.0, 0.0001, "朝右速度应全在 x 上")
	assert_almost_eq(field.vy[i], 0.0, 0.0001)
	assert_almost_eq(field.life[i], 1.5, 0.0001)
	assert_almost_eq(field.radius[i], 8.0, 0.0001)
	assert_eq(field.pierce[i], 2)
	assert_eq(field.active_count(), 1)


func test_pf2_direction_is_normalized() -> void:
	var i := _spawn(Vector2.ZERO, Vector2(3, 4), 100.0, 1.0, 4.0, 0)
	# (3,4) 归一化 = (0.6,0.8)：速度大小必须等于 speed，否则斜射更快
	assert_almost_eq(Vector2(field.vx[i], field.vy[i]).length(), 100.0, 0.0001)


func test_pf3_expires_after_lifetime() -> void:
	_spawn(Vector2.ZERO, Vector2.RIGHT, 60.0, 0.5, 4.0, 0)
	field.tick(0.2, null, 20.0, [], rng)
	assert_eq(field.active_count(), 1, "未到寿命应存活")
	field.tick(0.4, null, 20.0, [], rng)
	assert_eq(field.active_count(), 0, "超过寿命应自动回收")


func test_pf4_moves_along_velocity() -> void:
	var i := _spawn(Vector2.ZERO, Vector2.RIGHT, 100.0, 10.0, 4.0, 0)
	field.tick(0.5, null, 20.0, [], rng)
	assert_almost_eq(field.px[i], 50.0, 0.0001, "x 应前进 speed × dt")


# ---------------- 命中 ----------------

func test_pf5_hits_target_in_range_and_dies() -> void:
	var t := FakeTarget.new(Vector2(10, 0), 20.0)
	var targets := [t]
	_spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 5.0, 8.0, 0)
	var hits := field.tick(0.016, _hash_of(targets), 20.0, targets, rng)
	assert_eq(hits, 1, "射程内应命中 1 次")
	assert_eq(t.hit_count(), 1, "hurtbox 应收到 1 次结算")
	assert_almost_eq(t.damage_taken(), 10.0, 0.0001, "无护甲时应吃满 10 点物理")
	assert_eq(field.active_count(), 0, "pierce=0 命中即消亡")


func test_pf6_pierce_keeps_projectile_alive() -> void:
	var t := FakeTarget.new(Vector2(10, 0), 20.0)
	var targets := [t]
	var i := _spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 5.0, 8.0, 2)
	field.tick(0.016, _hash_of(targets), 20.0, targets, rng)
	assert_eq(field.active_count(), 1, "还有穿透次数应存活")
	assert_eq(field.pierce[i], 1, "穿透次数应递减")


func test_pf7_out_of_range_misses() -> void:
	var t := FakeTarget.new(Vector2(200, 0), 20.0)
	var targets := [t]
	_spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 5.0, 8.0, 0)
	var hits := field.tick(0.016, _hash_of(targets), 20.0, targets, rng)
	assert_eq(hits, 0, "超出 radius + target_radius 不应命中")
	assert_eq(t.hit_count(), 0)


func test_pf8_skips_attacker_itself() -> void:
	var self_target := FakeTarget.new(Vector2(5, 0), 20.0)
	var targets := [self_target]
	# attacker 就是自己 → 出生点重叠也不能自伤
	field.spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 5.0, 8.0, 0,
			_packet(), self_target, StatsComponent.new())
	field.tick(0.016, _hash_of(targets), 20.0, targets, rng)
	assert_eq(self_target.hit_count(), 0, "不得命中发射者自身")
	assert_eq(field.active_count(), 1, "未命中不应消亡")


func test_pf9_skips_dead_target() -> void:
	var t := FakeTarget.new(Vector2(10, 0), 20.0)
	t.dead = true
	var targets := [t]
	_spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 5.0, 8.0, 0)
	field.tick(0.016, _hash_of(targets), 20.0, targets, rng)
	assert_eq(t.hit_count(), 0, "尸体不该被再次结算")


func test_pf10_hit_cooldown_blocks_retick() -> void:
	var t := FakeTarget.new(Vector2(10, 0), 20.0)
	var targets := [t]
	_spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 5.0, 8.0, 99)
	field.tick(0.016, _hash_of(targets), 20.0, targets, rng)
	field.tick(0.016, _hash_of(targets), 20.0, targets, rng)
	assert_eq(t.hit_count(), 1, "同一目标的重复命中受冷却限制（0.1s 内只结算 1 次）")
	# 冷却过后可以再次命中（穿透型弹幕持续啃同一个目标）
	field.tick(0.2, _hash_of(targets), 20.0, targets, rng)
	assert_eq(t.hit_count(), 2, "冷却结束后应可再次命中")


func test_pf11_multiple_targets_with_pierce() -> void:
	var a := FakeTarget.new(Vector2(10, 0), 14.0)
	var b := FakeTarget.new(Vector2(16, 0), 14.0)
	var c := FakeTarget.new(Vector2(22, 0), 14.0)
	var targets := [a, b, c]
	_spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 5.0, 8.0, 2)
	var hits := field.tick(0.016, _hash_of(targets), 20.0, targets, rng)
	assert_eq(hits, 3, "pierce=2 应能连续命中 3 个目标（2 次后仍有 1 次）")
	assert_eq(field.active_count(), 0, "穿透耗尽后消亡")


# ---------------- 容量与池 ----------------

func test_pf12_capacity_recycles_oldest() -> void:
	field = FieldScript.new(3)
	var i0 := _spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 5.0, 4.0, 0)
	_spawn(Vector2(1, 0), Vector2.RIGHT, 0.0, 5.0, 4.0, 0)
	_spawn(Vector2(2, 0), Vector2.RIGHT, 0.0, 5.0, 4.0, 0)
	assert_eq(field.active_count(), 3)
	var i3 := _spawn(Vector2(99, 0), Vector2.RIGHT, 0.0, 5.0, 4.0, 0)
	assert_eq(field.active_count(), 3, "容量固定，永远不扩容")
	assert_eq(i3, i0, "满容量时应回收最旧的槽位（下标复用）")
	assert_almost_eq(field.px[i3], 99.0, 0.0001, "回收的槽位应写入新状态")


func test_pf13_release_is_idempotent() -> void:
	var i := _spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 5.0, 4.0, 0)
	field.release(i)
	field.release(i)
	field.release(999)
	assert_eq(field.active_count(), 0)
	# 二次 release 不应把槽位塞进空闲队列两次（否则会拿到同一槽位的两个持有者）
	_spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 5.0, 4.0, 0)
	assert_eq(field.active_count(), 1)


func test_pf14_clear_all_empties_field() -> void:
	_spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 5.0, 4.0, 0)
	_spawn(Vector2.ONE, Vector2.RIGHT, 0.0, 5.0, 4.0, 0)
	field.clear_all()
	assert_eq(field.active_count(), 0)
	assert_eq(field.pool.active_count(), 0, "池内的活跃计数也要归零")


# ---------------- 哈希正确性与收益 ----------------

func test_pf15_hash_result_matches_bruteforce() -> void:
	# 64 个目标排成 8×8 网格，间距 40px；一发大半径弹幕扫过去
	var targets: Array = []
	for gy in 8:
		for gx in 8:
			targets.append(FakeTarget.new(Vector2(gx * 40.0, gy * 40.0), 12.0))
	var with_hash := FieldScript.new(16)
	var no_hash := FieldScript.new(16)
	with_hash.spawn(Vector2(-30, -30), Vector2.RIGHT, 0.0, 9.0, 60.0, 999,
			_packet(), null, StatsComponent.new())
	no_hash.spawn(Vector2(-30, -30), Vector2.RIGHT, 0.0, 9.0, 60.0, 999,
			_packet(), null, StatsComponent.new())
	var h1 := with_hash.tick(0.016, _hash_of(targets, 40.0), 12.0, targets, rng)
	var h2 := no_hash.tick(0.016, null, 12.0, targets, rng)
	assert_eq(h1, h2, "哈希路径与暴力路径的命中数必须一致")
	assert_gt(h1, 0, "该场景应至少命中一个目标")
	with_hash = null
	no_hash = null


func test_pf16_hash_reduces_candidate_scan() -> void:
	# 200 个目标铺满 4000px 长条，弹幕只在一角：哈希应只扫到极小一部分
	var targets: Array = []
	for i in 200:
		targets.append(FakeTarget.new(Vector2(float(i) * 20.0, 0.0), 10.0))
	var hashed := FieldScript.new(4)
	hashed.spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 5.0, 30.0, 999,
			_packet(), null, StatsComponent.new())
	hashed.tick(0.016, _hash_of(targets, 64.0), 10.0, targets, rng)
	var hashed_candidates := hashed.last_query_candidates

	var linear := FieldScript.new(4)
	linear.spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 5.0, 30.0, 999,
			_packet(), null, StatsComponent.new())
	linear.tick(0.016, null, 10.0, targets, rng)
	var linear_candidates := linear.last_query_candidates

	assert_lt(hashed_candidates, linear_candidates,
			"哈希候选数（%d）必须远小于线性全扫（%d）" % [hashed_candidates, linear_candidates])
	assert_lt(hashed_candidates, 20, "本场景哈希候选应少于 20 个")
	hashed = null
	linear = null


# ---------------- 渲染接口 ----------------

func test_pf17_visual_reads_without_mutating() -> void:
	var i := _spawn(Vector2(7, 8), Vector2.RIGHT, 100.0, 2.0, 6.0, 0)
	var v := field.visual(i)
	assert_eq(v[&"pos"], Vector2(7, 8))
	assert_almost_eq(float(v[&"radius"]), 6.0, 0.0001)
	field.tick(0.1, null, 20.0, [], rng)
	var v2 := field.visual(i)
	assert_almost_eq(float(v2[&"pos"].x), 17.0, 0.0001, "visual 应反映推进后的位置")
	assert_almost_eq(float(v2[&"age"]), 0.1, 0.0001)


func test_pf18_is_alive_guards_bounds() -> void:
	assert_false(field.is_alive(-1))
	assert_false(field.is_alive(0))
	assert_false(field.is_alive(999))
	var i := _spawn(Vector2.ZERO, Vector2.RIGHT, 0.0, 5.0, 4.0, 0)
	assert_true(field.is_alive(i))
