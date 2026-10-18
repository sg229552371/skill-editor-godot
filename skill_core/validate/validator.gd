class_name Validator
extends RefCounted

const SkillApi = preload("res://skill_core/api/skill_api.gd")
const Diag = preload("res://skill_core/api/diagnostic.gd")
const Sorter = preload("res://skill_core/validate/diagnostic_sorter.gd")

# 跨卡事实的 context 键：主键在前，其余为兼容别名（宿主可任选其一注入，有其一即算齐备）。
const CROSS_CARD_KEYS: Array[String] = ["cross_card_facts", "assembly_facts", "cross_card"]

# The validator is an orchestration layer. Rule cards own rule semantics; this
# class only selects registered groups, aggregates their results and applies the
# shared diagnostic sorter.
var last_error: String = ""
var _ready: bool = false
var _groups: Array[Dictionary] = []
var _stages: Dictionary = {}
var _cards: Dictionary = {}
var _sorter: Sorter = null
var _accepted_revision: int = -1

func configure(spec: Dictionary) -> bool:
	_ready = false
	last_error = ""
	_groups.clear()
	_stages.clear()
	_cards.clear()
	_sorter = null
	_accepted_revision = -1

	var sorter_value: Variant = spec.get("sorter", null)
	if sorter_value is Sorter:
		_sorter = sorter_value
	else:
		_sorter = Sorter.new()
		var sorter_meta: Variant = spec.get("sorter_metadata", null)
		var metadata: Dictionary = sorter_meta if sorter_meta is Dictionary else Sorter.load_metadata()
		if not _sorter.configure(metadata):
			return _fail("诊断排序器配置失败: " + _sorter.last_error)

	var cards: Variant = spec.get("cards", null)
	if not cards is Array or cards.is_empty():
		return _fail("规则卡未配置")
	for entry in cards:
		if not entry is Dictionary:
			return _fail("规则卡登记项必须是对象")
		var name: String = str(entry.get("name", ""))
		var card: Variant = entry.get("card", null)
		if name.is_empty() or card == null or not card.has_method("validate"):
			return _fail("规则卡登记项无效: " + name)
		if not _card_is_configured(card, entry):
			return _fail("规则卡未 configure: " + name)
		_cards[name] = card

	var groups: Variant = spec.get("groups", null)
	if not groups is Array or groups.is_empty():
		return _fail("规则区间未配置")
	for group in groups:
		if not group is Dictionary:
			return _fail("规则区间登记项必须是对象")
		var card_name: String = str(group.get("card", ""))
		if not _cards.has(card_name):
			return _fail("规则区间引用未登记规则卡: " + card_name)
		var first: Variant = group.get("first", null)
		var last: Variant = group.get("last", null)
		if not first is int or not last is int:
			return _fail("规则区间边界必须是整数")
		var stages: Variant = group.get("stages", null)
		if stages is Array:
			for stage in stages:
				if not _valid_stage(stage):
					return _fail("规则区间含非法阶段: " + str(stage))
		if not register_group(int(first), int(last), _cards[card_name], stages if stages is Array else [], card_name):
			return false

	var stage_map: Variant = spec.get("stages", null)
	if stage_map is Dictionary:
		for stage_key in stage_map:
			if not _valid_stage(stage_key):
				return _fail("阶段登记含非法阶段: " + str(stage_key))
			var group_refs: Variant = stage_map[stage_key]
			if not group_refs is Array or group_refs.is_empty():
				return _fail("阶段未登记规则区间: " + str(stage_key))
			var selected: Array[int] = []
			for ref in group_refs:
				var index: int = _group_index(ref)
				if index < 0:
					return _fail("阶段引用未知规则区间: " + str(ref))
				if not selected.has(index):
					selected.append(index)
			_stages[_stage_key(stage_key)] = selected
	else:
		for index in range(_groups.size()):
			var group_stages: Array = _groups[index].get("stages", [])
			for stage in group_stages:
				var key: StringName = _stage_key(stage)
				if not _stages.has(key):
					_stages[key] = []
				_stages[key].append(index)

	for stage in _all_stages():
		var key: StringName = _stage_key(stage)
		if not _stages.has(key) or _stages[key].is_empty():
			return _fail("阶段未登记规则区间: " + String(key))
	_ready = true
	return true

# Public injection point for callers that build the registry incrementally.
func register_group(first: int, last: int, card: Variant, stages: Array = [], card_name: String = "") -> bool:
	if first < 1 or last < first:
		return _fail("非法规则区间")
	if card == null or not card.has_method("validate"):
		return _fail("规则卡无效")
	if not _card_is_configured(card, {}):
		return _fail("规则卡未 configure")
	for old_group in _groups:
		if first <= int(old_group["last"]) and last >= int(old_group["first"]):
			return _fail("规则区间重叠")
	_groups.append({"first": first, "last": last, "card": card,
		"card_name": card_name, "stages": stages.duplicate(true)})
	return true

func register_stage(stage: StringName, group_indices: Array) -> bool:
	if not _valid_stage(stage):
		return _fail("非法阶段: " + String(stage))
	if group_indices.is_empty():
		return _fail("阶段未登记规则区间: " + String(stage))
	var selected: Array[int] = []
	for ref in group_indices:
		var index: int = _group_index(ref)
		if index < 0:
			return _fail("阶段引用未知规则区间")
		selected.append(index)
	_stages[stage] = selected
	return true

func validate(cfg: Dictionary, stage: StringName = SkillApi.STAGE_SAVE, context: Dictionary = {}) -> Dictionary:
	var revision: Variant = context.get("draft_revision", null)
	if not revision is int:
		return _failure("缺少或非法 context.draft_revision", -1)
	var result_revision: int = int(revision)
	if not _ready:
		return _failure(last_error if not last_error.is_empty() else "校验器未配置", result_revision)
	var stage_key: StringName = _stage_key(stage)
	if not _valid_stage(stage_key):
		return _failure("阶段名非法", result_revision)
	if not _stages.has(stage_key) or _stages[stage_key].is_empty():
		return _failure("阶段未登记规则区间", result_revision)
	var context_error: String = _context_error(stage_key, context)
	if not context_error.is_empty():
		return _failure(context_error, result_revision)

	var diagnostics: Array = []
	var notices: Array = []
	var selected: Array = _stages[stage_key]
	for group_index in selected:
		var group: Dictionary = _groups[int(group_index)]
		var card: Variant = group["card"]
		var card_result: Variant = card.validate(cfg, context)
		if not card_result is Dictionary or not card_result.has("diagnostics") or not card_result["diagnostics"] is Array:
			return _failure("规则卡返回结果无效", result_revision)
		for item in card_result["diagnostics"]:
			if stage_key == SkillApi.STAGE_FILLING and not _submitted(item, context["submitted_paths"]):
				continue
			diagnostics.append(_clone_diagnostic(item))
		var card_notices: Variant = card_result.get("notices", null)
		if card_notices is Array:
			for notice in card_notices:
				notices.append(str(notice))

	var sorted: Dictionary = _sorter.sort_diagnostics(diagnostics)
	if not sorted.get("ok", false):
		return _failure("诊断排序失败: " + str(sorted.get("error", "")), result_revision)
	var accepted: bool = true
	if result_revision >= _accepted_revision:
		_accepted_revision = result_revision
	else:
		accepted = false
	return {"ok": _has_no_block(sorted["diagnostics"]), "diagnostics": sorted["diagnostics"],
		"notices": notices, "removed": sorted["removed"], "duplicates": sorted["duplicates"],
		"revision": result_revision, "stale": not accepted, "accepted": accepted, "error": ""}

func is_stale(result: Dictionary) -> bool:
	var revision: Variant = result.get("revision", null)
	return result.get("stale", false) == true or not revision is int or int(revision) < _accepted_revision

func _context_error(stage: StringName, context: Dictionary) -> String:
	if stage == SkillApi.STAGE_FILLING and not context.get("submitted_paths", null) is Array:
		return "filling 缺少 context.submitted_paths"
	if stage == SkillApi.STAGE_ASSEMBLY and not _has_any_dictionary(context, CROSS_CARD_KEYS):
		# 报错必须点名可接受的键，否则调用方无法定位是哪个 context 键没给
		return "assembly 缺少跨卡事实 context（可接受: " + ", ".join(CROSS_CARD_KEYS) + "）"
	if stage == SkillApi.STAGE_LOAD:
		for key in ["baseline_version_state", "migration_state"]:
			if not context.get(key, null) is Dictionary:
				return "load 缺少 context." + key
	if stage == SkillApi.STAGE_PREVIEW:
		for key in ["probe_credentials", "preview_fingerprint"]:
			if not context.get(key, null) is Dictionary:
				return "preview 缺少 context." + key
	return ""

func _submitted(item: Variant, paths: Array) -> bool:
	var path: String = ""
	if item is Diag:
		path = item.path
	elif item is Dictionary:
		var value: Variant = item.get("path", null)
		path = value if value is String else ""
	if path.is_empty():
		return false
	for submitted in paths:
		if not submitted is String or submitted.is_empty():
			continue
		if path == submitted or path.begins_with(submitted + ".") or path.begins_with(submitted + "["):
			return true
	return false

func _clone_diagnostic(item: Variant) -> Variant:
	if item is Diag:
		var copy: Diag = Diag.new()
		copy.rule_id = item.rule_id
		copy.code = item.code
		copy.severity = item.severity
		copy.path = item.path
		copy.actual = item.actual
		copy.expected = item.expected
		copy.hint = item.hint
		return copy
	if item is Dictionary:
		return item.duplicate(true)
	return item

func _has_no_block(items: Array) -> bool:
	for item in items:
		var severity: Variant = item.severity if item is Diag else item.get("severity", null) if item is Dictionary else null
		if severity == Diag.SEV_BLOCK:
			return false
	return true

func _failure(message: String, revision: int) -> Dictionary:
	last_error = message
	return {"ok": false, "diagnostics": [], "notices": [], "removed": 0, "duplicates": [],
		"revision": revision, "stale": false, "accepted": false, "error": message}

func _fail(message: String) -> bool:
	last_error = message
	return false

func _card_is_configured(card: Variant, entry: Dictionary) -> bool:
	if entry.has("configured"):
		return entry["configured"] == true
	var configured: Variant = card.get("configured")
	if configured != null:
		return configured == true
	var ready: Variant = card.get("_ready")
	if ready != null:
		return ready == true
	return true

func _group_index(ref: Variant) -> int:
	if ref is int:
		return ref if ref >= 0 and ref < _groups.size() else -1
	if ref is String and ref.is_valid_int():
		var index: int = ref.to_int()
		return index if index >= 0 and index < _groups.size() else -1
	return -1

func _all_stages() -> Array[StringName]:
	return [SkillApi.STAGE_FILLING, SkillApi.STAGE_CARD, SkillApi.STAGE_ASSEMBLY,
		SkillApi.STAGE_SAVE, SkillApi.STAGE_LOAD, SkillApi.STAGE_PREVIEW]

func _valid_stage(stage: Variant) -> bool:
	return _all_stages().has(_stage_key(stage))

func _stage_key(stage: Variant) -> StringName:
	return StringName(str(stage))

func _has_any_dictionary(context: Dictionary, keys: Array) -> bool:
	for key in keys:
		if context.get(key, null) is Dictionary:
			return true
	return false
