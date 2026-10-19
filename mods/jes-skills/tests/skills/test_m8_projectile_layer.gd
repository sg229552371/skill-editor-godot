# M8 批量绘制层测试（2026-10-19 R4）：SandboxProjectileLayer
# 目标：验证 MultiMesh 配置正确、实例数与存活数一致、位置/尺寸跟着 SoA 走。
# 说明：headless 下没有真实渲染，但 MultiMesh 的实例数据是 CPU 侧结构，可断言。
extends GutTest

const LayerScript := preload("res://mods/jes-skills/sandbox/sandbox_projectile_layer.gd")
const FieldScript := preload("res://mods/jes-skills/systems/skills/combat/projectile_field.gd")

var field: ProjectileField = null
var layer: SandboxProjectileLayer = null


func before_each() -> void:
	field = FieldScript.new(8)
	layer = autofree(LayerScript.new())
	layer.setup(field)


func after_each() -> void:
	layer = null
	field = null


func _spawn(pos: Vector2, radius: float = 8.0) -> int:
	var p := DamagePacket.new()
	p.elements = {&"physical": 1.0}
	return field.spawn(pos, Vector2.RIGHT, 0.0, 5.0, radius, 0, p, null, StatsComponent.new())


func test_pl1_multimesh_configured_once() -> void:
	assert_not_null(layer.multimesh, "setup 必须建出 MultiMesh")
	assert_eq(layer.multimesh.instance_count, field.capacity, "实例容量应等于投射物容量")
	assert_eq(layer.multimesh.visible_instance_count, 0, "空场时应一个都不画")
	assert_eq(layer.multimesh.transform_format, MultiMesh.TRANSFORM_2D, "2D 层必须用 TRANSFORM_2D")
	assert_true(layer.multimesh.use_colors, "需要逐实例颜色做淡出")
	assert_not_null(layer.multimesh.mesh, "必须挂 QuadMesh")


func test_pl2_visible_count_tracks_active() -> void:
	_spawn(Vector2(10, 10))
	_spawn(Vector2(20, 20))
	layer.sync()
	assert_eq(layer.multimesh.visible_instance_count, 2, "两发存活应画两个实例")


func test_pl3_instance_transform_follows_soa() -> void:
	var i := _spawn(Vector2(7, 9), 12.0)
	layer.sync()
	# headless 的 dummy 渲染器不保存 MultiMesh 实例数据，读回永远是默认值，
	# 所以位置/尺寸的断言打在纯函数 instance_state 上（sync 只是把它写进去）
	var st := SandboxProjectileLayer.instance_state(
			field.px[i], field.py[i], field.radius[i], field.age[i], field.life[i],
			SandboxProjectileLayer.DEFAULT_TINT)
	var t: Transform2D = st[&"transform"]
	assert_almost_eq(t.origin.x, 7.0, 0.001)
	assert_almost_eq(t.origin.y, 9.0, 0.001)
	# QuadMesh 是直径 2 的单位圆 → 缩放系数应等于半径
	assert_almost_eq(t.x.x, 12.0, 0.001, "缩放系数应等于半径")
	# 推进后位置应跟着 SoA 走
	field.tick(0.1, null, 20.0, [], RngService.new(0))
	var st2 := SandboxProjectileLayer.instance_state(
			field.px[i], field.py[i], field.radius[i], field.age[i], field.life[i],
			SandboxProjectileLayer.DEFAULT_TINT)
	assert_almost_eq(float((st2[&"transform"] as Transform2D).origin.x), 7.0, 0.001,
			"speed=0 时不应移动")


func test_pl4_release_hides_instance() -> void:
	var i := _spawn(Vector2.ZERO)
	layer.sync()
	assert_eq(layer.multimesh.visible_instance_count, 1)
	field.release(i)
	layer.sync()
	assert_eq(layer.multimesh.visible_instance_count, 0, "回收后不应继续绘制")


func test_pl5_color_alpha_fades_near_end_of_life() -> void:
	var tint := SandboxProjectileLayer.DEFAULT_TINT
	var full := SandboxProjectileLayer.instance_state(0.0, 0.0, 8.0, 0.0, 5.0, tint)
	var mid := SandboxProjectileLayer.instance_state(0.0, 0.0, 8.0, 4.5, 5.0, tint)
	var end := SandboxProjectileLayer.instance_state(0.0, 0.0, 8.0, 4.9, 5.0, tint)
	assert_gt(float((full[&"color"] as Color).a), float((mid[&"color"] as Color).a),
			"进入末期后透明度应下降")
	assert_lt(float((end[&"color"] as Color).a), float((mid[&"color"] as Color).a),
			"越接近寿命越透明")
	assert_gt(float((end[&"color"] as Color).a), 0.0, "未到寿命不应完全透明")
	# 半径收边但不会缩成 0（否则看起来像提前消失）
	assert_lt(float((end[&"transform"] as Transform2D).x.x), 8.0)
	assert_gt(float((end[&"transform"] as Transform2D).x.x), 4.0)
