# 装配实验台（S4 UI 层）：技能下拉 × 辅助宝石多选，实时展示「是否生效 + 具体效果」。
# 硬门禁：不出现 gem_id / support_id 逻辑分支 —— 下拉项与勾选项全部来自 GEMS 数据表，
#         预览走 SocketGraph.assemble / SkillExecutor.cast 同一条通用管线。
# 交互：勾选即写入槽 0（SandboxMain.apply_lab_loadout），Q 实放当前配置；
#       默认勾选自动施法，持续开火（D-33 用户裁定：不再设 1~9 槽位键）。
class_name SandboxLab
extends Control


const PANEL_LEFT := 10.0
const PANEL_TOP := 172.0        # 让开左上角 HUD 文字
const PANEL_WIDTH := 352.0
const PANEL_BOTTOM_MARGIN := 10.0
const FONT_SMALL := 12

# 参数键 → 中文显示名（纯展示映射，不参与任何判定）
const PARAM_NAMES := {
	&"projectile_count": "投射物",
	&"pierce": "穿透",
	&"chain_count": "连锁",
	&"fork_count": "分裂",
	&"radius": "半径",
	&"speed": "弹速",
	&"lifetime": "寿命",
	&"arc_deg": "扇形角",
	&"range": "射程",
	&"hit_count": "段数",
	&"hit_interval": "段间隔",
	&"delay": "延迟",
	&"tick_interval": "tick间隔",
	&"max_channel_time": "引导时长",
	&"duration": "持续",
	&"distance": "距离",
	&"max_count": "召唤数",
}

# 内部规范化键（projectile_count 的 base 载体）：报告里只显示 projectile_count
const HIDDEN_PARAMS := [&"count_base"]

var main: SandboxMain = null
var _skills: Array = []        # Array[SkillData]
var _supports: Array = []      # Array[SupportGemData]
var _checks: Array[CheckBox] = []

var _picker: OptionButton = null
var _report: RichTextLabel = null
var _auto_cast_check: CheckBox = null
var _applying := false
var _notice := ""              # 一次性的操作提示（镶嵌被拒 / 换技能自动卸下）


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_skills = GemRegistry.skills()
	_supports = GemRegistry.supports()
	_build_ui()


## 由 SandboxMain 在自身 _ready 后调用（此时槽位已建好）
func bind(p_main: SandboxMain) -> void:
	main = p_main
	if _auto_cast_check != null:
		_auto_cast_check.set_pressed_no_signal(main.auto_cast)
	_sync_from_slot()


# ---------------- UI 构建 ----------------

func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.offset_left = PANEL_LEFT
	panel.offset_right = PANEL_LEFT + PANEL_WIDTH
	panel.offset_top = PANEL_TOP
	panel.offset_bottom = -PANEL_BOTTOM_MARGIN
	panel.add_theme_stylebox_override(&"panel", _panel_style())
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 8)
	margin.add_theme_constant_override(&"margin_right", 8)
	margin.add_theme_constant_override(&"margin_top", 8)
	margin.add_theme_constant_override(&"margin_bottom", 8)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 6)
	margin.add_child(root)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override(&"separation", 6)
	root.add_child(title_row)

	var title := Label.new()
	title.text = "装配实验台"
	title.add_theme_font_size_override(&"font_size", 15)
	title_row.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)

	_auto_cast_check = CheckBox.new()
	_auto_cast_check.text = "每秒自动放技能"
	_auto_cast_check.tooltip_text = "每 %.0f 秒自动施放实验台当前配置（仍走冷却与蓝量门禁）" % SandboxMain.AUTO_CAST_INTERVAL
	_auto_cast_check.add_theme_font_size_override(&"font_size", FONT_SMALL)
	_auto_cast_check.toggled.connect(_on_auto_cast_toggled)
	title_row.add_child(_auto_cast_check)

	# 技能下拉
	var skill_row := HBoxContainer.new()
	root.add_child(skill_row)
	var skill_label := Label.new()
	skill_label.text = "技能"
	skill_label.add_theme_font_size_override(&"font_size", FONT_SMALL)
	skill_row.add_child(skill_label)
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.add_theme_font_size_override(&"font_size", FONT_SMALL)
	for i in _skills.size():
		var sk: SkillData = _skills[i]
		_picker.add_item("%d  %s" % [i + 1, sk.display_name], i)
	_picker.item_selected.connect(_on_skill_selected)
	skill_row.add_child(_picker)

	# 辅助宝石池（多选）
	var pool_title := Label.new()
	pool_title.text = "辅助宝石池（勾选生效）"
	pool_title.add_theme_font_size_override(&"font_size", FONT_SMALL)
	root.add_child(pool_title)

	var pool_scroll := ScrollContainer.new()
	pool_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pool_scroll.custom_minimum_size = Vector2(0, 132)
	pool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(pool_scroll)

	var pool_box := VBoxContainer.new()
	pool_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool_box.add_theme_constant_override(&"separation", 0)
	pool_scroll.add_child(pool_box)

	for i in _supports.size():
		var sp: SupportGemData = _supports[i]
		var cb := CheckBox.new()
		cb.text = _support_label(sp)
		cb.add_theme_font_size_override(&"font_size", FONT_SMALL)
		cb.toggled.connect(_on_support_toggled.bind(i))
		pool_box.add_child(cb)
		_checks.append(cb)

	root.add_child(HSeparator.new())

	# 结算报告
	var report_scroll := ScrollContainer.new()
	report_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_scroll.custom_minimum_size = Vector2(0, 148)
	report_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(report_scroll)

	_report = RichTextLabel.new()
	_report.bbcode_enabled = true
	_report.fit_content = true
	_report.scroll_active = false
	_report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_report.add_theme_font_size_override(&"normal_font_size", FONT_SMALL)
	_report.add_theme_font_size_override(&"bold_font_size", FONT_SMALL)
	report_scroll.add_child(_report)

	# 操作按钮
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 6)
	root.add_child(buttons)
	var cast_btn := Button.new()
	cast_btn.text = "施放 (Q)"
	cast_btn.pressed.connect(_on_cast_pressed)
	buttons.add_child(cast_btn)
	var clear_btn := Button.new()
	clear_btn.text = "清空辅助"
	clear_btn.pressed.connect(_on_clear_pressed)
	buttons.add_child(clear_btn)


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.92)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(1.0, 1.0, 1.0, 0.12)
	return sb


func _support_label(sp: SupportGemData, suffix: String = "") -> String:
	var need := "通用"
	if not sp.require_tags.is_empty():
		need = "需 " + _join_tags(sp.require_tags)
	var label := "%s  ·  %s  ·  耗魔×%s" % [sp.display_name, need, _num(sp.cost_multiplier)]
	if suffix != "":
		label += "  [%s]" % suffix
	return label


## 临时槽位（socket_count 固定为上限，用于准入校验与预览）
func _temp_slot(gem: SkillData, supports: Array) -> SkillSlot:
	var slot := SkillSlot.new()
	slot.slot_index = 0
	slot.active_gem = gem
	slot.active_level = 1
	slot.socket_count = SandboxMain.SOCKET_COUNT
	for s in supports:
		slot.supports.append(s)
	return slot


func _error_reason(chk: AssemblyResult, sp: SupportGemData) -> String:
	match chk.error_code:
		AssemblyResult.ErrorCode.ERR_NO_SOCKET:
			return "孔位已满"
		AssemblyResult.ErrorCode.ERR_CONFLICT:
			return "与已选辅助互斥"
		AssemblyResult.ErrorCode.ERR_INCOMPATIBLE_SUPPORT:
			if chk.error_support_id == sp.support_id:
				return "与技能不兼容"
			return "与已选辅助不兼容"
		_:
			return "不可镶嵌"


# ---------------- 交互 ----------------

func _on_skill_selected(_index: int) -> void:
	_drop_invalid_after_skill_change()
	_apply()


## 换技能后，已勾但不再合法的辅助会被移除（等价 PoE2：非法组合不允许存在）
func _drop_invalid_after_skill_change() -> void:
	var gem := _current_gem()
	if gem == null:
		return
	var removed := PackedStringArray()
	for _round in 12:
		var picked := _checked_supports()
		var chk := SocketGraph.assemble_cached(_temp_slot(gem, picked))
		if chk.ok:
			break
		var bad_id := StringName(chk.error_support_id)
		var hit := false
		_applying = true
		for i in _checks.size():
			if not _checks[i].button_pressed:
				continue
			if (_supports[i] as SupportGemData).support_id == bad_id:
				_checks[i].button_pressed = false
				removed.append((_supports[i] as SupportGemData).display_name)
				hit = true
				break
		_applying = false
		if not hit:
			break
	if not removed.is_empty():
		_notice = "[color=#ff8f8f]换技能后自动卸下：%s（不再兼容）[/color]" % "、".join(removed)


func _on_support_toggled(pressed: bool, index: int) -> void:
	if _applying:
		return
	if pressed:
		var gem := _current_gem()
		if gem != null:
			# 用「除自己以外」的已选集合做准入判定（此刻按钮已是按下状态）
			var others: Array = []
			for i in _checks.size():
				if i != index and _checks[i].button_pressed:
					others.append(_supports[i])
			var sp: SupportGemData = _supports[index]
			var chk := SocketGraph.socket_check(_temp_slot(gem, others), sp)
			if not chk.ok:
				_applying = true
				_checks[index].button_pressed = false
				_applying = false
				_notice = "[color=#ff8f8f]%s 无法镶嵌：%s[/color]" % [sp.display_name, _error_reason(chk, sp)]
				_apply()
				return
	_notice = ""
	_apply()


func _on_cast_pressed() -> void:
	if main != null:
		main.try_cast(0)


func _current_gem() -> SkillData:
	var idx := maxi(_picker.selected, 0)
	return _skills[idx] if idx < _skills.size() else null


func _checked_supports() -> Array:
	var picked: Array = []
	for i in _checks.size():
		if _checks[i].button_pressed:
			picked.append(_supports[i])
	return picked


## 单独装配某个辅助是否兼容（用于失败时区分「不兼容」与「被连坐」）
func _single_ok(gem: SkillData, sp: SupportGemData) -> bool:
	var slot := SkillSlot.new()
	slot.active_gem = gem
	slot.supports.append(sp)
	return SocketGraph.assemble_cached(slot).ok


## 剔除问题辅助：循环移除「单独不兼容」与「互斥报告」的勾选项，直到装配成功
## 说明：正常路径下不可达（准入层已拦住非法组合），保留用于"外部导入的非法配置"兜底。
func _on_prune_pressed() -> void:
	if main == null or _applying:
		return
	for _round in 10:
		var gem := _current_gem()
		var picked := _checked_supports()
		if gem == null or _evaluate(gem, picked)[&"ok"]:
			break
		var bad_id := StringName(_evaluate(gem, picked)[&"error_support"])
		var removed := false
		_applying = true
		for i in _checks.size():
			if not _checks[i].button_pressed:
				continue
			var sp: SupportGemData = _supports[i]
			if sp.support_id == bad_id or not _single_ok(gem, sp):
				_checks[i].button_pressed = false
				removed = true
		_applying = false
		if not removed:
			break
	_apply()


func _on_clear_pressed() -> void:
	_applying = true
	for cb in _checks:
		cb.button_pressed = false
	_applying = false
	_notice = ""
	_apply()


## 自动施法开关（勾选即生效，取消即停）
func _on_auto_cast_toggled(on: bool) -> void:
	if main != null:
		main.set_auto_cast(on)


## 按 PoE2 语义刷新可镶嵌状态：非法/满孔的未勾选项直接置灰禁用
func _refresh_availability() -> void:
	var gem := _current_gem()
	if gem == null:
		return
	var picked := _checked_supports()
	var probe := _temp_slot(gem, picked)
	var full := picked.size() >= SandboxMain.SOCKET_COUNT
	for i in _checks.size():
		var cb: CheckBox = _checks[i]
		var sp: SupportGemData = _supports[i]
		if cb.button_pressed:
			cb.disabled = false
			cb.text = _support_label(sp)
			continue
		if full:
			cb.disabled = true
			cb.text = _support_label(sp, "孔位已满")
			continue
		var chk := SocketGraph.socket_check(probe, sp)
		cb.disabled = not chk.ok
		cb.text = _support_label(sp, "" if chk.ok else _error_reason(chk, sp))


## 用槽 0 当前状态回填 UI（初次绑定时调用）
func _sync_from_slot() -> void:
	if main == null:
		return
	var slot := main.slot_bar.get_slot(0)
	if slot == null or slot.active_gem == null:
		return
	_applying = true
	for i in _skills.size():
		if (_skills[i] as SkillData).gem_id == slot.active_gem.gem_id:
			_picker.selected = i
			break
	for i in _supports.size():
		var sid: StringName = (_supports[i] as SupportGemData).support_id
		var on := false
		for s in slot.supports:
			if (s as SupportGemData).support_id == sid:
				on = true
				break
		_checks[i].button_pressed = on
	_applying = false
	_apply()


# ---------------- 应用 + 结算 ----------------

func _apply() -> void:
	if _applying or main == null:
		return
	var gem := _current_gem()
	if gem == null:
		return
	var picked := _checked_supports()
	main.apply_lab_loadout(gem, picked)
	_report.text = _build_report(gem, picked)
	_refresh_availability()


## 预览结算：装配 → 注入词缀 → 施法计划（与 SandboxMain.try_cast 同序，纯预览不落盘）
func _evaluate(gem: SkillData, supports: Array) -> Dictionary:
	var slot := _temp_slot(gem, supports)

	var asm := SocketGraph.assemble_cached(slot)
	var out := {
		&"ok": asm.ok,
		&"error_code": asm.error_code,
		&"error_support": asm.error_support_id,
		&"cost_mult": asm.cost_multiplier,
		&"tags": asm.effective_tags,
		&"mods": asm.modifiers,
		&"cost": CostCalculator.compute_cost(gem, asm.cost_multiplier, 1.0),
		&"plans": [],
	}
	if asm.ok:
		var stats := StatsComponent.new()
		stats.add_modifiers(asm.modifiers, &"lab_preview")
		out[&"plans"] = SkillExecutor.cast(gem, 1, stats, [], asm.behavior_overrides)
		stats.remove_by_source(&"lab_preview")
	return out


func _build_report(gem: SkillData, picked: Array) -> String:
	var base := _evaluate(gem, [])
	var cur := _evaluate(gem, picked)
	var lines := PackedStringArray()

	if _notice != "":
		lines.append(_notice)

	lines.append("[b][color=#9ecbff]%s[/color][/b]  [color=#7a8798]%s[/color]"
		% [gem.display_name, _join_tags(gem.tags)])

	if cur[&"ok"]:
		lines.append("[color=#8fd18f]✓ 装配成功[/color]  孔位 %d/%d  耗魔 %s → %s（×%s）" % [
			picked.size(), SandboxMain.SOCKET_COUNT,
			_num(base[&"cost"]), _num(cur[&"cost"]), _num(cur[&"cost_mult"]),
		])
	else:
		var reason := _error_text(int(cur[&"error_code"]))
		var bad := _find_support(cur[&"error_support"])
		var detail := ""
		if bad != null:
			detail = "（%s：需 %s）" % [bad.display_name, _join_tags(bad.require_tags)]
		lines.append("[color=#ff8f8f]✗ 装配失败 %s[/color]%s" % [reason, detail])
		lines.append("[color=#8a97a8]整组不生效（G7 兜底）；正常操作不会走到这里，非法项已置灰[/color]")

	# 逐项状态：✓ 生效 / ✗ 问题源 / ○ 本身可用但被整组失败拖累
	if not picked.is_empty():
		var marks := PackedStringArray()
		for s in picked:
			var sp: SupportGemData = s
			if cur[&"ok"]:
				marks.append("[color=#8fd18f]✓ 生效[/color] %s" % sp.display_name)
			elif sp.support_id == StringName(cur[&"error_support"]):
				var why := "不兼容" if int(cur[&"error_code"]) \
						== AssemblyResult.ErrorCode.ERR_INCOMPATIBLE_SUPPORT else "互斥"
				marks.append("[color=#ff8f8f]✗ %s（%s，拖累整组）[/color]" % [sp.display_name, why])
			elif _single_ok(gem, sp):
				marks.append("[color=#d8b45a]○ %s（本身兼容，被整组失败拖累）[/color]" % sp.display_name)
			else:
				marks.append("[color=#ff8f8f]✗ %s（不兼容）[/color]" % sp.display_name)
		lines.append("逐项 " + "\n逐项 ".join(marks))
		if not cur[&"ok"]:
			lines.append("[color=#8a97a8]整组失败 = 所有辅助都不生效；点「剔除问题辅助」自动移除[/color]")

	# 伤害与参数差异（只在装配成功时有意义）
	if cur[&"ok"]:
		var bp := _first_plan(base)
		var cp := _first_plan(cur)
		if cp.is_empty():
			lines.append("[color=#d8b45a]该技能无伤害段（增益/召唤类）[/color]")
		else:
			var be: Dictionary = bp.get(&"elements", {})
			var ce: Dictionary = cp.get(&"elements", {})
			var keys := {}
			for k in be:
				keys[k] = true
			for k in ce:
				keys[k] = true
			var dmg := PackedStringArray()
			for k in keys:
				dmg.append("%s %s" % [String(k), _arrow(float(be.get(k, 0.0)), float(ce.get(k, 0.0)))])
			lines.append("伤害 " + " · ".join(dmg))

			var bparams: Dictionary = bp.get(&"params", {})
			var cparams: Dictionary = cp.get(&"params", {})
			var diffs := PackedStringArray()
			for k in cparams:
				if HIDDEN_PARAMS.has(k):
					continue
				var cv = cparams[k]
				if not (cv is float or cv is int):
					continue
				var bv := float(bparams.get(k, 0.0))
				var cf := float(cv)
				if absf(bv - cf) > 0.0001:
					diffs.append("%s %s" % [_param_name(k), _arrow(bv, cf)])
			if diffs.is_empty():
				lines.append("[color=#8a97a8]行为参数无变化[/color]")
			else:
				lines.append("参数 " + " · ".join(diffs))

			var ba := float(bp.get(&"area_mult", 1.0))
			var ca := float(cp.get(&"area_mult", 1.0))
			var bd := float(bp.get(&"duration_mult", 1.0))
			var cd := float(cp.get(&"duration_mult", 1.0))
			# 命名注意：不能叫 scale —— Control 基类已有同名属性（SHADOWED_BASE_CLASS）
			var mult_lines := PackedStringArray()
			if absf(ba - ca) > 0.0001:
				mult_lines.append("范围倍率 %s" % _arrow(ba, ca))
			if absf(bd - cd) > 0.0001:
				mult_lines.append("持续倍率 %s" % _arrow(bd, cd))
			if not mult_lines.is_empty():
				lines.append("倍率 " + " · ".join(mult_lines))

		if not cur[&"mods"].is_empty():
			var ms := PackedStringArray()
			for m in cur[&"mods"]:
				ms.append("%s%s%s" % [String(m.stat), _op_text(m.op), _num(m.value)])
			lines.append("词缀 " + " · ".join(ms))

	lines.append("[color=#6f7c8c]已写入槽 0 —— 按 Q 实放 / 勾选自动施法持续开火；不可镶嵌的辅助已置灰（PoE2 前置拦截）[/color]")
	return "\n".join(lines)


func _first_plan(res: Dictionary) -> Dictionary:
	var plans: Array = res[&"plans"]
	if plans.is_empty():
		return {}
	return plans[0]


func _find_support(sid: StringName) -> SupportGemData:
	for s in _supports:
		if (s as SupportGemData).support_id == sid:
			return s
	return null


# ---------------- 文本工具 ----------------

func _error_text(code: int) -> String:
	match code:
		AssemblyResult.ErrorCode.ERR_INCOMPATIBLE_SUPPORT:
			return "· 不兼容"
		AssemblyResult.ErrorCode.ERR_CONFLICT:
			return "· 辅助互斥"
		AssemblyResult.ErrorCode.ERR_NO_ACTIVE_GEM:
			return "· 缺少主动宝石"
		AssemblyResult.ErrorCode.ERR_MULTIPLE_ACTIVE:
			return "· 组内多个主动宝石"
		_:
			return ""


func _arrow(before: float, after: float) -> String:
	if absf(before - after) < 0.0001:
		return _num(before)
	var col := "#8fd18f" if after > before else "#ff8f8f"
	return "%s→[color=%s]%s[/color]" % [_num(before), col, _num(after)]


func _num(v: float) -> String:
	if absf(v - round(v)) < 0.0001:
		return str(int(round(v)))
	return "%.2f" % v


func _op_text(op: int) -> String:
	match op:
		StatModifier.Op.FLAT_ADD:
			return " +"
		StatModifier.Op.INCREASED:
			return " +%"
		StatModifier.Op.MORE:
			return " ×%"
		_:
			return " "


func _param_name(key: StringName) -> String:
	return PARAM_NAMES.get(key, String(key))


func _join_tags(tags: Array) -> String:
	var out := PackedStringArray()
	for t in tags:
		out.append(String(t))
	return " · ".join(out)
