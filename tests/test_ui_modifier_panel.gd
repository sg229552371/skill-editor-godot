extends GutTest

const ModPanel = preload("res://addons/skill_editor/ui/modifier_panel.gd")

func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _item_policy() -> Dictionary:
	var policy: Dictionary = _json("res://data/item_permission_policy.json")
	# 宿主注入的展示口径；部署素材目前缺此列，不写回 data。
	policy["ui_access"] = {
		"author": {"visible": true, "editable": true},
		"relic": {"visible": true, "editable": false},
		"locked": {"visible": false, "editable": false},
	}
	return policy

func _view() -> Dictionary:
	return {
		"input_path": "params.modifiers", "tags_path": "meta.tags",
		"fields": {
			"modifier_id": {"type": "string"}, "permission": {"type": "string"},
			"scope": {"type": "string"}, "inheritable": {"type": "boolean"},
			"targets": {"type": "array"}, "stack_rule": {"type": "object"},
		},
		"roles": {"scope": "scope", "targets": "targets"},
		"tagged_scope": "tagged", "field_access": "author",
		"display_access_by_target": {},
	}

func _definition(id: String = "mod_a", scope: String = "own_skill") -> Dictionary:
	return {"modifier_id": id, "permission": "mutate_number", "scope": scope,
		"inheritable": false, "targets": ["params.power"],
		"stack_rule": {"operation_profile": "op_add", "operands": [2]}}

func _entries(access: String = "author") -> Array:
	return [{"definition": _definition(), "access": access, "priority": 3}]

func _fields() -> Array:
	return [{"field_path": "params.power", "permissions": ["mutate_number"],
		"min": 0, "max": 100, "live": false, "inheritable": false,
		"set_conflict_note": "最后挂载者覆盖"}]

func _cfg() -> Dictionary:
	return {"meta": {"tags": ["fire"]}, "params": {"power": 10}}

func _panel() -> ModPanel:
	var panel: ModPanel = ModPanel.new()
	add_child_autofree(panel)
	return panel

func _configure(panel: ModPanel, entries: Array, fields: Array) -> Dictionary:
	return panel.configure(_cfg(), entries, fields,
		_json("res://data/exposed_fields_meta.json"), _item_policy(),
		_json("res://data/relic_policy.json"), _view())

func test_definition_count_and_order_follow_injection() -> void:
	var panel: ModPanel = _panel()
	var entries: Array = _entries()
	entries.append({"definition": _definition("mod_b"), "access": "author"})
	assert_true(_configure(panel, entries, _fields())["ok"])
	assert_eq(panel.get_rows().size(), 2)
	assert_eq(panel.get_rows()[0]["definition"]["modifier_id"], "mod_a")
	entries.reverse()
	assert_true(_configure(panel, entries, _fields())["ok"])
	assert_eq(panel.get_rows()[0]["definition"]["modifier_id"], "mod_b")
	assert_eq(panel.get_rows()[1]["definition"]["modifier_id"], "mod_a")

func _inputs(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is LineEdit or child is CheckBox or child is SpinBox or child is OptionButton or child is TextEdit:
			result.append(child)
		result.append_array(_inputs(child))
	return result

func _tags(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child.has_meta("scope_tags"):
			result.append(child)
		result.append_array(_tags(child))
	return result

func test_no_input_outside_six_modifier_keys_or_six_exposed_groups() -> void:
	var panel: ModPanel = _panel()
	assert_true(_configure(panel, _entries(), _fields())["ok"])
	var inputs: Array = _inputs(panel)
	assert_eq(inputs.size(), 12, "非空证明：一条修饰器六输入 + 一条暴露六组")
	var allowed: Dictionary = {"modifier": _view()["fields"].keys(),
		"exposed": ["reference", "permissions", "bounds", "live", "inheritable", "note"]}
	var outside: int = 0
	for control in inputs:
		var section: String = control.get_meta("section", "")
		if not allowed.has(section) or not allowed[section].has(control.get_meta("input_field", "")):
			outside += 1
	assert_eq(outside, 0)
	assert_null(panel.get_control(0, "value"))
	assert_null(panel.get_exposed_control(0, "unregistered"))

func test_unknown_keys_are_named_and_fail_without_partial_rows() -> void:
	var panel: ModPanel = _panel()
	var fields: Array = _fields()
	fields[0]["rogue_field"] = 9
	fields[0]["second_rogue"] = false
	var result: Dictionary = _configure(panel, _entries(), fields)
	assert_false(result["ok"])
	assert_string_contains(result["error"], "rogue_field")
	assert_string_contains(result["error"], "second_rogue")
	assert_eq(panel.get_rows().size(), 0)
	assert_eq(_inputs(panel).size(), 0)
	assert_string_contains((panel.get_node("PanelError") as Label).text, "rogue_field")
	var entries: Array = _entries()
	entries[0]["definition"]["value"] = 8
	result = _configure(panel, entries, _fields())
	assert_false(result["ok"])
	assert_string_contains(result["error"], "value")

func test_tagged_scope_has_read_only_scope_tag_label() -> void:
	var panel: ModPanel = _panel()
	var entries: Array = _entries()
	entries[0]["definition"]["scope"] = "tagged"
	assert_true(_configure(panel, entries, _fields())["ok"])
	var tags: Array = _tags(panel)
	assert_eq(tags.size(), 1)
	assert_true(tags[0] is Label)
	assert_false(tags[0] is LineEdit)
	assert_string_contains(tags[0].text, "作用域标签")
	assert_string_contains(tags[0].text, "fire")
	assert_false(panel.set_modifier_value(0, "tag_filter", ["ice"])["ok"])
	assert_eq(panel.get_draft()["meta"]["tags"], ["fire"])

func test_relic_is_read_only_and_rejects_update_add_remove() -> void:
	var panel: ModPanel = _panel()
	assert_true(_configure(panel, _entries("relic"), _fields())["ok"])
	assert_eq(panel.get_rows().size(), 1)
	assert_false((panel.get_control(0, "modifier_id") as LineEdit).editable)
	assert_true((panel.get_control(0, "inheritable") as CheckBox).disabled)
	var before: String = JSON.stringify(panel.get_draft())
	assert_false(panel.set_modifier_value(0, "modifier_id", "changed")["ok"])
	assert_false(panel.add_modifier(_entries("relic")[0])["ok"])
	assert_false(panel.remove_modifier(0)["ok"])
	assert_eq(JSON.stringify(panel.get_draft()), before)

func test_author_can_edit_add_remove_and_controls_use_same_api() -> void:
	var panel: ModPanel = _panel()
	assert_true(_configure(panel, _entries(), _fields())["ok"])
	assert_true((panel.get_control(0, "modifier_id") as LineEdit).editable)
	(panel.get_control(0, "modifier_id") as LineEdit).text_submitted.emit("renamed")
	assert_eq(panel.get_draft()["params"]["modifiers"][0]["modifier_id"], "renamed")
	(panel.get_control(0, "inheritable") as CheckBox).toggled.emit(true)
	assert_true(panel.get_draft()["params"]["modifiers"][0]["inheritable"])
	assert_true(panel.add_modifier({"definition": _definition("mod_b"), "access": "author"})["ok"])
	assert_eq(panel.get_rows().size(), 2)
	assert_true(panel.remove_modifier(0)["ok"])
	assert_eq(panel.get_rows().size(), 1)
	assert_eq(panel.get_draft()["params"]["modifiers"][0]["modifier_id"], "mod_b")

func test_locked_has_no_row_and_cannot_be_edited_or_removed() -> void:
	var panel: ModPanel = _panel()
	assert_true(_configure(panel, _entries("locked"), _fields())["ok"])
	assert_eq(panel.get_rows().size(), 0)
	assert_null(panel.get_control(0, "modifier_id"))
	assert_false(panel.set_modifier_value(0, "modifier_id", "escape")["ok"])
	assert_false(panel.remove_modifier(0)["ok"])
	assert_false(panel.add_modifier(_entries("locked")[0])["ok"])
	assert_eq(panel.get_draft()["params"]["modifiers"].size(), 1, "隐藏不等于删除定义")

func test_draft_and_all_returned_data_are_deeply_isolated() -> void:
	var panel: ModPanel = _panel()
	var cfg: Dictionary = _cfg()
	var original: Dictionary = cfg.duplicate(true)
	var before: String = JSON.stringify(cfg)
	var entries: Array = _entries()
	var fields: Array = _fields()
	assert_true(panel.configure(cfg, entries, fields,
		_json("res://data/exposed_fields_meta.json"), _item_policy(),
		_json("res://data/relic_policy.json"), _view())["ok"])
	assert_true(panel.set_modifier_value(0, "targets", ["params.other"])["ok"])
	assert_true(panel.set_exposed_value(0, "bounds", [1, 90])["ok"])
	assert_true(panel.add_modifier({"definition": _definition("second"), "access": "author"})["ok"])
	assert_true(panel.remove_modifier(1)["ok"])
	assert_eq(JSON.stringify(cfg), before)
	assert_eq(cfg, original)
	var returned: Dictionary = panel.get_draft()
	returned["params"]["modifiers"][0]["targets"].append("bad")
	returned["params"]["exposed_fields"][0]["min"] = -100
	var rows: Array = panel.get_rows()
	rows[0]["definition"]["stack_rule"]["operands"].append(999)
	entries[0]["definition"]["modifier_id"] = "external"
	fields[0]["min"] = -300
	assert_eq(panel.get_draft()["params"]["modifiers"][0]["targets"], ["params.other"])
	assert_eq(panel.get_draft()["params"]["modifiers"][0]["modifier_id"], "mod_a")
	assert_eq(panel.get_draft()["params"]["modifiers"][0]["stack_rule"]["operands"], [2])
	assert_eq(panel.get_draft()["params"]["exposed_fields"][0]["min"], 1)

func test_unconfigured_and_missing_policy_show_explicit_error() -> void:
	var panel: ModPanel = _panel()
	assert_false(panel.render()["ok"])
	assert_false((panel.get_node("PanelError") as Label).text.is_empty())
	assert_false(panel.set_modifier_value(0, "modifier_id", "x")["ok"])
	var result: Dictionary = panel.configure(_cfg(), _entries(), _fields(),
		_json("res://data/exposed_fields_meta.json"),
		_json("res://data/item_permission_policy.json"),
		_json("res://data/relic_policy.json"), _view())
	assert_false(result["ok"], "真实部署素材缺 UI 列，禁止静默默认 author")
	assert_string_contains(result["error"], "ui_access")
	assert_string_contains((panel.get_node("PanelError") as Label).text, "ui_access")
	assert_eq(_inputs(panel).size(), 0)

func test_access_keys_and_field_order_are_data_driven() -> void:
	var panel: ModPanel = _panel()
	var policy: Dictionary = _item_policy()
	policy["ui_access"] = {"writer_x": {"visible": true, "editable": true},
		"reader_y": {"visible": true, "editable": false},
		"hidden_z": {"visible": false, "editable": false}}
	var view: Dictionary = _view()
	view["field_access"] = "writer_x"
	var reversed: Dictionary = {}
	var keys: Array = view["fields"].keys()
	keys.reverse()
	for key in keys:
		reversed[key] = view["fields"][key]
	view["fields"] = reversed
	var entries: Array = _entries("writer_x")
	entries.append({"definition": _definition("reader"), "access": "reader_y"})
	entries.append({"definition": _definition("hidden"), "access": "hidden_z"})
	assert_true(panel.configure(_cfg(), entries, _fields(),
		_json("res://data/exposed_fields_meta.json"), policy,
		_json("res://data/relic_policy.json"), view)["ok"])
	assert_eq(panel.get_rows().size(), 2)
	assert_true(panel.set_modifier_value(0, "modifier_id", "new_id")["ok"])
	assert_false(panel.set_modifier_value(1, "modifier_id", "bad")["ok"])
	assert_null(panel.get_control(2, "modifier_id"))
	var inputs: Array = _inputs(panel)
	assert_gt(inputs.size(), 0)
	assert_eq(inputs[0].get_meta("input_field"), keys[0])

func test_display_path_match_is_not_a_validation_or_save_verdict() -> void:
	var panel: ModPanel = _panel()
	var view: Dictionary = _view()
	view["display_access_by_target"] = {"params.power": "relic"}
	var result: Dictionary = panel.configure(_cfg(), _entries(), _fields(),
		_json("res://data/exposed_fields_meta.json"), _item_policy(),
		_json("res://data/relic_policy.json"), view)
	assert_true(result["ok"])
	assert_false(result.has("can_save"))
	assert_false(result.has("diagnostics"))
	assert_eq(panel.get_rows().size(), 1)
	assert_false(panel.set_modifier_value(0, "modifier_id", "bad")["ok"])
	assert_false(panel.has_method("save"))
	assert_false(panel.has_method("validate"))

func test_exposed_bounds_are_one_control_and_keep_registered_keys() -> void:
	var panel: ModPanel = _panel()
	assert_true(_configure(panel, _entries(), _fields())["ok"])
	(panel.get_exposed_control(0, "bounds") as LineEdit).text_submitted.emit("[3, 8]")
	var exposed: Dictionary = panel.get_draft()["params"]["exposed_fields"][0]
	assert_eq(exposed["min"], 3.0)
	assert_eq(exposed["max"], 8.0)
	assert_eq(exposed.size(), 7)
	assert_false(exposed.has("bounds"))
	assert_false(exposed.has("value"))
	assert_false(panel.set_exposed_value(0, "extra", 10)["ok"])

func test_invalid_edit_and_invalid_json_do_not_change_draft() -> void:
	var panel: ModPanel = _panel()
	assert_true(_configure(panel, _entries(), _fields())["ok"])
	var before: String = JSON.stringify(panel.get_draft())
	assert_false(panel.set_modifier_value(0, "inheritable", "true")["ok"])
	assert_false(panel.set_modifier_value(9, "modifier_id", "x")["ok"])
	(panel.get_control(0, "stack_rule") as LineEdit).text_submitted.emit("{oops")
	assert_string_contains((panel.get_node("PanelError") as Label).text, "JSON")
	assert_eq(JSON.stringify(panel.get_draft()), before)

func test_new_template_button_adds_only_definition_not_display_metadata() -> void:
	var panel: ModPanel = _panel()
	var view: Dictionary = _view()
	view["new_entry"] = {"definition": _definition("new_one"), "access": "author", "priority": 10}
	assert_true(panel.configure(_cfg(), _entries(), _fields(),
		_json("res://data/exposed_fields_meta.json"), _item_policy(),
		_json("res://data/relic_policy.json"), view)["ok"])
	(panel.get_node("AddModifier") as Button).pressed.emit()
	assert_eq(panel.get_rows().size(), 2)
	var added: Dictionary = panel.get_draft()["params"]["modifiers"][1]
	assert_eq(added["modifier_id"], "new_one")
	assert_eq(added.size(), 6)
	assert_false(added.has("access"))
	assert_false(added.has("priority"))

func test_counterfeit_six_fields_cannot_replace_frozen_key_with_value() -> void:
	var panel: ModPanel = _panel()
	var view: Dictionary = _view()
	view["fields"].erase("modifier_id")
	view["fields"]["value"] = {"type": "number"}
	var result: Dictionary = panel.configure(_cfg(), _entries(), _fields(),
		_json("res://data/exposed_fields_meta.json"), _item_policy(),
		_json("res://data/relic_policy.json"), view)
	assert_false(result["ok"])
	assert_string_contains(result["error"], "value")
	assert_eq(_inputs(panel).size(), 0)

func test_missing_material_after_success_removes_stale_controls() -> void:
	var panel: ModPanel = _panel()
	assert_true(_configure(panel, _entries(), _fields())["ok"])
	assert_eq(panel.get_rows().size(), 1)
	var result: Dictionary = panel.configure(_cfg(), _entries(), _fields(),
		{"fields": {}}, _item_policy(), {"enum": []}, _view())
	assert_false(result["ok"])
	assert_false(result["error"].is_empty())
	assert_eq(panel.get_rows().size(), 0)
	assert_eq(_inputs(panel).size(), 0)
	assert_false((panel.get_node("PanelError") as Label).text.is_empty())
	assert_eq(panel.get_draft(), {})

func test_exposed_slot_names_follow_metadata_and_multiple_rows_keep_order() -> void:
	var panel: ModPanel = _panel()
	var metadata: Dictionary = _json("res://data/exposed_fields_meta.json")
	metadata["fields"]["destination"] = metadata["fields"]["field_path"]
	metadata["fields"].erase("field_path")
	metadata["roles"]["reference"] = "destination"
	var fields: Array = _fields()
	fields[0]["destination"] = fields[0]["field_path"]
	fields[0].erase("field_path")
	var second: Dictionary = fields[0].duplicate(true)
	second["destination"] = "params.second"
	fields.append(second)
	assert_true(panel.configure(_cfg(), _entries(), fields, metadata,
		_item_policy(), _json("res://data/relic_policy.json"), _view())["ok"])
	assert_eq(_inputs(panel).size(), 18)
	assert_eq((panel.get_exposed_control(0, "reference") as LineEdit).text, "params.power")
	assert_eq((panel.get_exposed_control(1, "reference") as LineEdit).text, "params.second")
	assert_true(panel.set_exposed_value(0, "reference", "params.changed")["ok"])
	assert_eq(panel.get_draft()["params"]["exposed_fields"][0]["destination"], "params.changed")
	assert_false(panel.get_draft()["params"]["exposed_fields"][0].has("field_path"))

func test_setter_value_and_policy_injection_cannot_alias_internal_state() -> void:
	var panel: ModPanel = _panel()
	var policy: Dictionary = _item_policy()
	var view: Dictionary = _view()
	view["field_access"] = "relic"
	assert_true(panel.configure(_cfg(), _entries(), _fields(),
		_json("res://data/exposed_fields_meta.json"), policy,
		_json("res://data/relic_policy.json"), view)["ok"])
	var stack: Dictionary = {"operation_profile": "other", "operands": [4]}
	assert_true(panel.set_modifier_value(0, "stack_rule", stack)["ok"])
	stack["operands"].append(999)
	policy["ui_access"]["relic"]["editable"] = true
	view["field_access"] = "author"
	assert_eq(panel.get_draft()["params"]["modifiers"][0]["stack_rule"]["operands"], [4])
	assert_false(panel.set_exposed_value(0, "bounds", [1, 2])["ok"])
	assert_false((panel.get_exposed_control(0, "bounds") as LineEdit).editable)


