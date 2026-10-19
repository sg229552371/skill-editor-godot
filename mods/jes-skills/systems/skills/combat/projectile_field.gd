# ProjectileField（规格 §9.1 / §9.2 / §9.3）：SoA 投射物容器。
#
# 为什么要它：一个投射物一个 Node2D 会带来节点树开销 + 每帧 _draw 调用，
# 300 发就撑不住。这里把全部状态放在平行数组里（位置/速度/寿命/半径/穿透），
# 渲染交给一个 MultiMeshInstance2D（见 sandbox_projectile_layer.gd）。
#
# 硬规则：
# - 容量固定，**永不扩容**；满了回收最旧（复用 ProjectilePool 的 seq 语义）
# - 命中走 SpatialHash 邻域查询，禁止 O(m×n) 全扫；距离用平方比较，不开方
# - 不持有 Node 引用（target 是鸭子类型的数组元素，渲染层单独负责）
# - **不按发创建 Node**：全是 512 个 Area2D 就没有 SoA 的意义了。
#   命中结算复用一个 HitboxComponent（它只是无状态结算器，hurtbox 不看 source）
# - 目标 id == targets 数组下标（调用方每帧重建哈希，下标稳定）
# - **命中冷却也不进 Dictionary**：Dictionary 每次 new 都是一个堆对象，
#   300 发 × 每帧重发会让对象数持续爬升（实测 200 帧涨 50 个）。改成定长 SoA 记忆槽。
class_name ProjectileField
extends RefCounted

const HIT_COOLDOWN_SEC := 0.1
const HIT_MEMO := 4   # 每发最多记住 4 个近期命中目标（足以覆盖穿透多目标）

var capacity: int
var pool: ProjectilePool

# ---- SoA 主体 ----
var px := PackedFloat32Array()
var py := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var age := PackedFloat32Array()
var life := PackedFloat32Array()
var radius := PackedFloat32Array()
var pierce := PackedInt32Array()
var alive := PackedByteArray()

# ---- 逐发射物的附属数据（对象引用，不进热循环的数值运算） ----
var _slots: Array = []        # Array[ProjectileSlot]
var _packets: Array = []      # Array[DamagePacket]
var _stats: Array = []        # Array[StatsComponent]
var _attackers: Array = []    # Array[Object] 发射者，命中时跳过
var _memo_tid := PackedInt32Array()   # capacity * HIT_MEMO：命中过的目标 id（-1 = 空）
var _memo_t := PackedFloat32Array()   # capacity * HIT_MEMO：对应命中时刻

var _hitbox: HitboxComponent = null   # 全局复用 1 个，命中前改 packet/attacker_stats

var _clock: float = 0.0
var _buf: Array = []          # 复用查询缓冲，避免每帧分配
var last_query_candidates: int = 0   # 上次 tick 遍历到的候选总数（压测判据）
var last_hit_points: Array = []      # 上次 tick 的命中点（演出层拿去放特效，不参与结算）


func _init(p_capacity: int = 512) -> void:
	capacity = maxi(p_capacity, 1)
	pool = ProjectilePool.new(capacity)
	px.resize(capacity)
	py.resize(capacity)
	vx.resize(capacity)
	vy.resize(capacity)
	age.resize(capacity)
	life.resize(capacity)
	radius.resize(capacity)
	pierce.resize(capacity)
	alive.resize(capacity)
	alive.fill(0)
	_slots.resize(capacity)
	_packets.resize(capacity)
	_stats.resize(capacity)
	_attackers.resize(capacity)
	_memo_tid.resize(capacity * HIT_MEMO)
	_memo_tid.fill(-1)
	_memo_t.resize(capacity * HIT_MEMO)
	_memo_t.fill(0.0)
	_hitbox = HitboxComponent.new()


func _notification(what: int) -> void:
	# Area2D 不是 RefCounted，必须显式 free，否则退出时报 ObjectDB 泄漏
	if what == NOTIFICATION_PREDELETE and _hitbox != null:
		_hitbox.free()
		_hitbox = null


## 发射一发，返回索引；容量满时最旧的一发被顶掉（视觉舍弃，帧率优先）
func spawn(pos: Vector2, direction: Vector2, speed: float, lifetime: float,
		p_radius: float, p_pierce: int, packet: DamagePacket,
		attacker: Object, attacker_stats: StatsComponent) -> int:
	var slot: ProjectileSlot = pool.acquire()
	if slot == null:
		return -1
	var i := slot.index
	if i < 0 or i >= capacity:
		return -1
	px[i] = pos.x
	py[i] = pos.y
	var dir := direction.normalized()
	vx[i] = dir.x * speed
	vy[i] = dir.y * speed
	age[i] = 0.0
	life[i] = maxf(lifetime, 0.001)
	radius[i] = p_radius
	pierce[i] = p_pierce
	alive[i] = 1
	_slots[i] = slot
	_packets[i] = packet
	_stats[i] = attacker_stats
	_attackers[i] = attacker
	_clear_memo(i)
	return i


## 清空某发的命中记忆（spawn 时调用；release 不清，下次 spawn 会覆盖）
func _clear_memo(i: int) -> void:
	var base := i * HIT_MEMO
	for k in HIT_MEMO:
		_memo_tid[base + k] = -1
		_memo_t[base + k] = 0.0


func release(i: int) -> void:
	if i < 0 or i >= capacity or alive[i] == 0:
		return
	alive[i] = 0
	pool.release(_slots[i])


func active_count() -> int:
	var n := 0
	for i in capacity:
		if alive[i] == 1:
			n += 1
	return n


func is_alive(i: int) -> bool:
	return i >= 0 and i < capacity and alive[i] == 1


## 推进一帧。targets[tid] 需有 is_dead()/global_position/radius()/hurtbox。
## grid 为空时退化为线性扫（仅供无哈希的单测；生产路径必须传 grid）。
## 返回本帧命中次数。
## 命名注意：参数不能叫 hash —— 那是 GDScript 内置函数名（SHADOWED_BUILTIN）。
func tick(dt: float, grid: SpatialHash, max_target_radius: float,
		targets: Array, rng: Object) -> int:
	_clock += dt
	var hits := 0
	last_query_candidates = 0
	last_hit_points.clear()
	for i in capacity:
		if alive[i] == 0:
			continue
		age[i] += dt
		px[i] += vx[i] * dt
		py[i] += vy[i] * dt
		var pos := Vector2(px[i], py[i])
		var reach := radius[i] + max_target_radius

		if grid != null:
			grid.query_near_into(_buf, pos, reach)
			last_query_candidates += _buf.size()
			for tid in _buf:
				if _strike_if_hit(i, int(tid), targets, rng):
					hits += 1
					if alive[i] == 0:
						break
		else:
			for tid in targets.size():
				last_query_candidates += 1
				if _strike_if_hit(i, tid, targets, rng):
					hits += 1
					if alive[i] == 0:
						break

		if alive[i] == 1 and age[i] >= life[i]:
			release(i)
	return hits


## 命中判定 + 结算；返回是否真的打中
func _strike_if_hit(i: int, tid: int, targets: Array, rng: Object) -> bool:
	if tid < 0 or tid >= targets.size():
		return false
	var t = targets[tid]
	if t == _attackers[i]:
		return false
	if t.is_dead():
		return false
	var base := i * HIT_MEMO
	# 命中冷却：只查该发自己的定长记忆槽，零分配
	for k in HIT_MEMO:
		if _memo_tid[base + k] == tid and _clock - _memo_t[base + k] < HIT_COOLDOWN_SEC:
			return false
	var to_t: Vector2 = t.global_position - Vector2(px[i], py[i])
	var rr: float = radius[i] + t.radius()
	if to_t.length_squared() > rr * rr:
		return false

	# defender 契约：必须传带 .stats 的实体本身（G7 时代的同一个坑）
	# 复用同一个 hitbox：它只做 packet 快照 + 调纯函数结算，不持有归属状态
	_hitbox.packet = _packets[i]
	_hitbox.attacker_stats = _stats[i]
	_hitbox.strike(t.hurtbox, rng, t)
	last_hit_points.append(t.global_position)
	# 写入记忆槽：优先占空位，满了顶掉最旧的一条
	var slot_k := 0
	var oldest := INF
	for k in HIT_MEMO:
		var idx := base + k
		if _memo_tid[idx] < 0:
			slot_k = k
			oldest = -1.0
			break
		if _memo_t[idx] < oldest:
			oldest = _memo_t[idx]
			slot_k = k
	_memo_tid[base + slot_k] = tid
	_memo_t[base + slot_k] = _clock
	if pierce[i] <= 0:
		release(i)
	else:
		pierce[i] -= 1
	return true


## 渲染层用：取第 i 发的视觉参数（不暴露内部数组语义）
func visual(i: int) -> Dictionary:
	return {&"pos": Vector2(px[i], py[i]), &"radius": radius[i], &"age": age[i], &"life": life[i]}


## 清空（测试/切场景用）
func clear_all() -> void:
	for i in capacity:
		if alive[i] == 1:
			release(i)
	_clock = 0.0
