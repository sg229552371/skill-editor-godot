# 投射物批量绘制层（M8 / 规格 §9.1）：一个 MultiMeshInstance2D 画完全部投射物。
#
# 为什么要它：SoA 数据里没有 Node，也就没有 300 个 _draw()。整层只有 1 个
# CanvasItem、1 次 draw call，每帧只做「写 instance transform」这一件小事。
#
# 硬规则：
# - 只读 ProjectileField 的 SoA 数组，不回写任何战斗状态（渲染不得影响结算）
# - instance_count 只在 setup 时按容量设定一次；每帧只改 visible_instance_count，
#   避免重建 MultiMesh 缓冲
# - 贴图程序化生成（GradientTexture2D 径向渐变），不依赖外部美术资源
class_name SandboxProjectileLayer
extends MultiMeshInstance2D

const TEX_SIZE := 64
const DEFAULT_TINT := Color(0.62, 0.86, 1.0)
const FADE_START := 0.8      # 寿命进度超过这个值开始收边淡出

var field: ProjectileField = null
var tint: Color = DEFAULT_TINT

var _built: bool = false


func setup(p_field: ProjectileField, p_tint: Color = DEFAULT_TINT) -> void:
	field = p_field
	tint = p_tint
	_build()
	multimesh.instance_count = field.capacity
	multimesh.visible_instance_count = 0


func _ready() -> void:
	# 允许在 tscn 里手挂：脚本挂上但没 setup() 时保持不可见，不报错
	if field == null:
		visible = false


## 每帧调用（在 field.tick 之后）：把存活发压缩写入实例 0..n-1
func sync() -> void:
	if not _built or field == null:
		return
	var n := 0
	for i in field.capacity:
		if field.alive[i] == 0:
			continue
		var st := instance_state(field.px[i], field.py[i], field.radius[i],
				field.age[i], field.life[i], tint)
		multimesh.set_instance_transform_2d(n, st[&"transform"])
		multimesh.set_instance_color(n, st[&"color"])
		n += 1
	multimesh.visible_instance_count = n


## 纯函数：一发投射物的 SoA 状态 → 实例变换 + 颜色。
## 抽出来是为了让「位置/缩放/淡出」这套数学能在 headless 下被断言
## （dummy 渲染器不保存 MultiMesh 实例数据，读回来永远是默认值）。
static func instance_state(px: float, py: float, radius: float,
		age: float, life: float, tint_color: Color) -> Dictionary:
	# 生命末期收边：半径收缩 + 透明度衰减，替代逐发动画
	var frac := age / maxf(life, 0.0001)
	var k := 1.0 - clampf((frac - FADE_START) / (1.0 - FADE_START), 0.0, 1.0)
	var s := radius * (0.55 + 0.45 * k)
	var c := tint_color
	c.a = (0.45 + 0.55 * k) * tint_color.a
	return {
		&"transform": Transform2D(Vector2(s, 0.0), Vector2(0.0, s), Vector2(px, py)),
		&"color": c,
	}


func _build() -> void:
	if _built:
		return
	_built = true

	# 径向渐变贴图：中心实、边缘透明，加法混合自然成「发光弹丸」
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.45, Color(1, 1, 1, 0.75))
	grad.add_point(0.75, Color(1, 1, 1, 0.18))

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = TEX_SIZE
	tex.height = TEX_SIZE

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = tex
	# 关键：不吃 albedo_color 而吃逐实例颜色，否则每发子弹一个色做不到
	mat.vertex_color_use_as_albedo = true

	# 单位圆直径 2：缩放系数直接等于半径，省一次乘法
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.material = mat

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = quad
