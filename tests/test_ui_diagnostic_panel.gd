extends GutTest

const SCENE: PackedScene = preload("res://addons/skill_editor/ui/diagnostic_panel.tscn")
const DiagnosticPanel = preload("res://addons/skill_editor/ui/diagnostic_panel.gd")
const Diag = preload("res://skill_core/api/diagnostic.gd")
const Sorter = preload("res://skill_core/validate/diagnostic_sorter.gd")

func _metadata() -> Dictionary:
	var metadata: Dictionary = Sorter.load_metadata()
	metadata["view_fields"] = {
		"planner": ["hint"],
		"developer": ["rule_id", "code", "path", "actual", "expected"]
	}
	metadata["default_path_regex"] = "^bricks\\[[0-9]+\\]\\.default_cfg(?:\\.|$)"
	metadata["default_source_values"] = ["default_cfg", "default"]
	metadata["default_notice"] = "错误来自默认卡"
	return metadata

func _panel(metadata: Dictionary = {}) -> DiagnosticPanel:
	var sorter: Sorter = Sorter.new()
	assert_true(sorter.configure(Sorter.load_metadata()))
	var panel: DiagnosticPanel = SCENE.instantiate()
	panel.set("api", SkillApi.new())
	add_child_autofree(panel)
	assert_true(panel.configure(_metadata() if metadata.is_empty() else metadata, sorter)["ok"])
	return panel

func _diagnostic(id: String, severity: int, path: String, hint: String) -> Diag:
	var item: Diag = Diag.new()
	item.rule_id = id
	item.code = "E-TEST"
	item.severity = severity
	item.path = path
	item.actual = "actual_" + id
	item.expected = "expected_" + id
	item.hint = hint
	return item

func _ids(entries: Array) -> Array:
	var result: Array = []
	for entry in entries:
		result.append(entry["rule_id"])
	return result

func _records(items: Array) -> Array:
	var result: Array = []
	for item in items:
		result.append(item.to_dict().duplicate(true))
	return result

func _diagnostic_ids(items: Array) -> Array:
	var ids: Array = []
	for item in items:
		ids.append(item.rule_id)
	return ids

func _groups(items: Array) -> Array:
	var groups: Array = []
	for item in items:
		groups.append(item["group"])
	return groups

func test_two_views_read_same_sorted_diagnostics_with_distinct_presentations() -> void:
	var panel: DiagnosticPanel = _panel()
	var items: Array = [
		_diagnostic("V-TEST-C", Diag.SEV_HINT, "params.ratio", "给策划的提示"),
		_diagnostic("V-TEST-A", Diag.SEV_BLOCK, "bricks[2].author_params", "缺少字段"),
		_diagnostic("V-TEST-B", Diag.SEV_WARN, "meta.name", "需要留意")
	]
	var expected_sorter: Sorter = Sorter.new()
	assert_true(expected_sorter.configure(Sorter.load_metadata()))
	var expected: Dictionary = expected_sorter.sort_diagnostics(items)
	assert_true(expected["ok"])
	assert_true(panel.set_diagnostics(items)["ok"])
	var planner: Array = panel.get_view_entries("planner")
	var developer: Array = panel.get_view_entries("developer")
	assert_eq(planner.size(), 3)
	assert_eq(developer.size(), planner.size())
	assert_eq(_ids(planner), _ids(developer))
	assert_eq(_ids(planner), _diagnostic_ids(expected["diagnostics"]))
	assert_eq(_ids(planner), ["V-TEST-A", "V-TEST-B", "V-TEST-C"])
	assert_eq(_groups(planner), ["阻止保存", "警告", "提示"])
	assert_string_contains(planner[0]["text"], "缺少字段")
	assert_false(planner[0]["text"].contains("E-TEST"))
	assert_string_contains(developer[0]["text"], "V-TEST-A")
	assert_string_contains(developer[0]["text"], "E-TEST")
	assert_string_contains(developer[0]["text"], "bricks[2].author_params")
	assert_string_contains(developer[0]["text"], "actual_V-TEST-A")
	assert_string_contains(developer[0]["text"], "expected_V-TEST-A")

func test_same_severity_keeps_sorter_order_and_view_fields_follow_metadata() -> void:
	var metadata: Dictionary = _metadata()
	metadata["view_fields"]["planner"] = ["path", "hint"]
	metadata["severity_value_to_text"]["0"] = "自定义阻断组"
	var panel: DiagnosticPanel = _panel(metadata)
	var inputs: Array = [
		_diagnostic("V-TEST-3", Diag.SEV_BLOCK, "bricks[10].author_params", "较后"),
		_diagnostic("V-TEST-2", Diag.SEV_BLOCK, "bricks[2].author_params", "较前"),
		_diagnostic("V-TEST-1", Diag.SEV_BLOCK, "meta.name", "最前")
	]
	var sorter: Sorter = Sorter.new()
	assert_true(sorter.configure(Sorter.load_metadata()))
	var expected: Dictionary = sorter.sort_diagnostics(inputs)
	assert_true(expected["ok"])
	assert_true(panel.set_diagnostics(inputs)["ok"])
	var planner: Array = panel.get_view_entries("planner")
	assert_eq(_ids(planner), _diagnostic_ids(expected["diagnostics"]))
	assert_eq(_ids(planner), _ids(panel.get_view_entries("developer")))
	assert_eq(planner[0]["group"], "自定义阻断组")
	assert_string_contains(planner[0]["text"], "meta.name")
	assert_string_contains(planner[0]["text"], "最前")
	assert_eq(panel.get_node("Views/Planner/Groups").get_child_count(), 3)

func test_click_expands_and_locates_once_even_after_switching_views() -> void:
	var panel: DiagnosticPanel = _panel()
	assert_true(panel.set_diagnostics([_diagnostic("V-TEST", Diag.SEV_BLOCK, "bricks[2].author_params", "检查积木")])["ok"])
	watch_signals(panel)
	var planner_button: Button = panel.get_entry_button("planner", 0)
	var developer_button: Button = panel.get_entry_button("developer", 0)
	assert_not_null(planner_button)
	assert_not_null(developer_button)
	assert_false((panel.get_node("Views/Planner/Groups").get_child(0).get_node("Details") as Label).visible)
	planner_button.emit_signal("pressed")
	assert_eq(panel.selected_path, "bricks[2].author_params")
	assert_signal_emitted_with_parameters(panel, "field_requested", ["bricks[2].author_params"])
	assert_eq(panel.location_emissions, 1)
	assert_true((panel.get_node("Views/Planner/Groups").get_child(0).get_node("Details") as Label).visible)
	assert_true((panel.get_node("Views/Developer/Groups").get_child(0).get_node("Details") as Label).visible)
	assert_eq((panel.get_node("FieldPath") as Label).text, "bricks[2].author_params")
	planner_button.emit_signal("pressed")
	developer_button.emit_signal("pressed")
	assert_eq(panel.location_emissions, 1)

func test_default_card_path_and_injected_source_warn_without_writing_overrides() -> void:
	var panel: DiagnosticPanel = _panel()
	var draft: Dictionary = {"params": {"brick_overrides": [{"brick_index": 2, "values": {"ratio": 3}}], "nested": {"keep": []}}}
	var before: Dictionary = draft.duplicate(true)
	var serialized: String = JSON.stringify(draft)
	var direct: Diag = _diagnostic("V-DEFAULT", Diag.SEV_BLOCK, "bricks[2].default_cfg.ratio", "默认值有错")
	var resolved: Diag = _diagnostic("V-SOURCE", Diag.SEV_WARN, "params.ratio", "来源有错")
	var input: Array = [resolved, direct]
	var input_before: Array = _records(input)
	assert_true(panel.set_diagnostics(input, {"params.ratio": {"source": "default_cfg", "input_path": "bricks[2].default_cfg.ratio"}}, draft["params"])["ok"])
	var planner: Array = panel.get_view_entries("planner")
	assert_eq(planner.size(), 2)
	assert_true(planner[0]["from_default"])
	assert_true(planner[1]["from_default"])
	assert_string_contains(planner[0]["text"], "错误来自默认卡")
	assert_string_contains(planner[1]["text"], "错误来自默认卡")
	panel.get_entry_button("planner", 1).emit_signal("pressed")
	assert_eq(panel.selected_path, "bricks[2].default_cfg.ratio")
	assert_string_contains((panel.get_node("Notice") as Label).text, "错误来自默认卡")
	assert_eq(draft, before)
	assert_eq(JSON.stringify(draft), serialized)
	assert_eq(_records(input), input_before, "panel must not mutate injected Diagnostic objects")
	assert_eq(panel.get_view_entries("developer").size(), 2)
	assert_eq(draft, before)
	assert_eq(JSON.stringify(draft), serialized)

func test_override_source_is_not_misidentified_as_default() -> void:
	var panel: DiagnosticPanel = _panel()
	var path: String = "params.brick_overrides[2].values.ratio"
	assert_true(panel.set_diagnostics([_diagnostic("V-OVERRIDE", Diag.SEV_BLOCK, path, "覆盖错误")], {path: {"source": "params"}})["ok"])
	assert_false(panel.get_view_entries("planner")[0]["from_default"])
	panel.get_entry_button("planner", 0).emit_signal("pressed")
	assert_eq(panel.selected_path, path)
	assert_false((panel.get_node("Notice") as Label).text.contains("错误来自默认卡"))

func test_empty_then_clear_returns_to_empty_state_without_stale_rows() -> void:
	var panel: DiagnosticPanel = _panel()
	assert_true(panel.set_diagnostics([])["ok"])
	assert_eq((panel.get_node("Status") as Label).text, "无诊断")
	assert_eq(panel.get_view_entries("planner").size(), 0)
	assert_true(panel.set_diagnostics([_diagnostic("V-TEST", Diag.SEV_BLOCK, "meta.name", "错误")])["ok"])
	assert_eq(panel.get_view_entries("planner").size(), 1)
	assert_true(panel.set_diagnostics([])["ok"])
	assert_eq((panel.get_node("Status") as Label).text, "无诊断")
	assert_eq(panel.get_view_entries("planner").size(), 0)
	assert_eq(panel.get_view_entries("developer").size(), 0)
	assert_eq(panel.get_node("Views/Planner/Groups").get_child_count(), 0)
	assert_eq(panel.get_node("Views/Developer/Groups").get_child_count(), 0)
	assert_eq(panel.selected_path, "")

func test_invalid_input_and_missing_metadata_fail_visibly_without_stale_results() -> void:
	var panel: DiagnosticPanel = _panel()
	assert_true(panel.set_diagnostics([_diagnostic("V-TEST", Diag.SEV_BLOCK, "meta.name", "错误")])["ok"])
	var bad_array: Dictionary = panel.set_diagnostics({"not": "an array"})
	assert_false(bad_array["ok"])
	assert_string_contains((panel.get_node("Status") as Label).text, "Array")
	assert_eq(panel.get_view_entries("planner").size(), 0)
	var bad_element: Dictionary = panel.set_diagnostics([{"path": "meta.name"}])
	assert_false(bad_element["ok"])
	assert_string_contains(bad_element["error"], "Diagnostic")
	assert_eq(panel.get_view_entries("developer").size(), 0)
	var metadata: Dictionary = _metadata()
	metadata.erase("view_fields")
	var missing: DiagnosticPanel = SCENE.instantiate()
	add_child_autofree(missing)
	var sorter: Sorter = Sorter.new()
	assert_true(sorter.configure(Sorter.load_metadata()))
	var result: Dictionary = missing.configure(metadata, sorter)
	assert_false(result["ok"])
	assert_string_contains((missing.get_node("Status") as Label).text, "view_fields")
	assert_false(missing.set_diagnostics([])["ok"])

func test_snapshot_is_detached_and_sorter_deduplicates_without_mutating_input() -> void:
	var panel: DiagnosticPanel = _panel()
	var one: Diag = _diagnostic("V-TEST", Diag.SEV_BLOCK, "meta.name", "提示原文")
	var items: Array = [one, one]
	var before: Array = _records(items)
	assert_true(panel.set_diagnostics(items)["ok"])
	assert_eq(panel.get_view_entries("planner").size(), 1)
	var readback: Array = panel.get_view_entries("planner")
	readback[0]["text"] = "篡改副本"
	one.hint = "之后的外部变更"
	items.clear()
	assert_eq(panel.get_view_entries("planner")[0]["text"], "提示原文")
	assert_eq(before.size(), 2)
	assert_eq(before[0], before[1])
	assert_false(panel.get_view_entries("planner")[0].has("diagnostic"))
