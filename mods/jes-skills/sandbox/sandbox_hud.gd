# 沙盒 HUD（S3）：显示资源/冷却/命中/DoT 状态与操作说明。
# 纯展示，只读 SandboxMain 公开状态，不参与任何判定。
class_name SandboxHud
extends CanvasLayer

var main: SandboxMain = null
var _lines: PackedStringArray = []


func _ready() -> void:
	layer = 10


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if main == null:
		return
	_lines = []
	_lines.append("=== 技能系统沙盒 ===  1~7 施放  Q 组合演示  R 木桩回血")
	var mana_cur: float = main.mana.get_current(&"mana")
	_lines.append("蓝量: %d / %d" % [int(mana_cur), int(SandboxMain.MANA_MAX)])
	# 各槽位冷却/充能状态
	var cd_status := ""
	for i in main.cooldowns.size():
		var cd: CooldownComponent = main.cooldowns[i]
		if cd.is_ready():
			continue
		if cd.is_charged_mode():
			cd_status += " [槽%d 充能 %d/%d]" % [i, cd.charges, cd.max_charges]
		else:
			cd_status += " [槽%d CD %.1fs]" % [i, cd.cooldown_duration()]
	if cd_status == "":
		cd_status = " 全部就绪"
	_lines.append("冷却:%s" % cd_status)
	_lines.append("投射物: %d/%d   DoT 活跃: %d" % [
		main.projectile_pool.active_count(), main.projectile_pool.capacity(),
		main.player.dot_ticker.active_count(),
	])
	# 木桩血量
	for s in main.stumps:
		var hp: float = s.health.current_health
		_lines.append("%s: %d / %d%s" % [
			s.entity_name, int(hp), int(s.health.max_health),
			"  (死亡,重生中)" if s.is_dead() else "",
		])
	var y := 8.0
	for line in _lines:
		draw_string(ThemeDB.fallback_font, Vector2(8.0, y), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1))
		y += 18.0
