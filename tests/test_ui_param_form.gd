extends GutTest

const FORM_SCENE: PackedScene = preload("res://addons/skill_editor/ui/param_form.tscn")
# 新增脚本的 class_name 不会进全局类缓存（项目不依赖编辑器 import），测试里一律用 preload 常量标注类型。
const ParamForm = preload("res://addons/skill_editor/ui/param_form.gd")

func _metadata() -> Dictionary:
	return {
		"leaves": [
			{"path": "damage", "type": "integer", "unit": "", "default": 0},
			{"path": "ratio", "type": "number", "unit": ""},
			{"path": "enabled", "type": "boolean", "unit": "", "default": false},
			{"path": "mode", "type": "string", "unit": "", "enum": ["alpha", "beta"]},
			{"path": "label", "type": "string", "unit": ""},
			{"path": "mystery", "type": "ref", "unit": ""},
			{"path": "empty_list", "type": "array", "unit": ""},
			{"path": "windup_ticks", "type": "integer", "unit": "tick"},
			{"path": "hidden", "type": "integer", "unit": ""}
		],
		"tick_fields": ["windup_ticks"],
		"enums": {"mode": ["alpha", "beta"]}
	}

func _card() -> Dictionary:
	return {
		"author_params": ["damage", "ratio", "enabled", "mode", "label", "mystery", "empty_list", "windup_ticks"],
		"locked_params": {"damage": "系统锁定"},
		"default_cfg": {"ratio": 1.5, "label": "默认", "empty_list": []}
	}

func _option_items(option: OptionButton) -> Array:
	var items: Array = []
	for index in range(option.item_count):
		items.append(option.get_item_text(index))
	return items

func _form(project_rate: float = 60.0, draft: Dictionary = {}) -> ParamForm:
	var form: ParamForm = FORM_SCENE.instantiate()
	add_child_autofree(form)
	form.configure(_metadata(), {"tick_rate": project_rate}, draft, _card())
	return form

func test_only_opened_paths_are_rendered_and_locked_rows_are_not_editable() -> void:
	var form: ParamForm = _form()
	assert_not_null(form.get_control("damage"))
	assert_not_null(form.get_control("mode"))
	assert_null(form.get_control("hidden"))
	var damage: SpinBox = form.get_control("damage") as SpinBox
	assert_false(damage.editable)
	assert_string_contains(form.get_row("damage")["lock_reason"], "系统锁定")
	assert_false(form.set_value("damage", 99), "locked parameter must reject edits")
	assert_eq(form.get_change_table()["damage"]["value"], 0)

func test_seconds_and_ticks_use_injected_project_rate_and_persist_integer_ticks() -> void:
	var form_60: ParamForm = _form(60.0)
	var form_30: ParamForm = _form(30.0)
	assert_true(form_60.set_value("windup_ticks", 0))
	assert_true(form_30.set_value("windup_ticks", 0))
	var seconds_60: SpinBox = form_60.get_seconds_control("windup_ticks")
	var seconds_30: SpinBox = form_30.get_seconds_control("windup_ticks")
	# Public set_value accepts the canonical tick value; the seconds control is
	# the UI path that performs ceil conversion.
	seconds_60.value = 0.101
	seconds_30.value = 0.101
	assert_eq(form_60.get_change_table()["windup_ticks"]["value"], 7)
	assert_eq(form_30.get_change_table()["windup_ticks"]["value"], 4)
	assert_true(form_60.get_change_table()["windup_ticks"]["value"] is int)
	form_60.get_ticks_control("windup_ticks").value = 6
	assert_true(abs(form_60.get_seconds_control("windup_ticks").value - 0.1) < 0.0001)

func test_level_visibility_does_not_drop_values_or_unlock_expert_fields() -> void:
	var metadata: Dictionary = _metadata()
	for entry in metadata["leaves"]:
		if entry["path"] == "ratio" or entry["path"] == "damage":
			entry["level"] = "专家"
		elif entry["path"] == "enabled":
			entry["level"] = "进阶"
	var form: ParamForm = FORM_SCENE.instantiate()
	add_child_autofree(form)
	form.configure(metadata, {"tick_rate": 60.0}, {}, _card())
	form.set_level_visible("进阶", false)
	form.set_level_visible("专家", false)
	assert_false(form.get_control("enabled").get_parent().visible)
	assert_false(form.get_control("ratio").get_parent().visible)
	assert_true(form.set_value("ratio", 2.5))
	assert_true(form.set_value("enabled", true))
	form.set_level_visible("进阶", true)
	form.expand_level("专家", true)
	assert_true(form.get_control("damage").get_parent().visible)
	assert_eq(form.get_change_table()["ratio"]["value"], 2.5)
	assert_eq(form.get_change_table()["enabled"]["value"], true)
	var locked: SpinBox = form.get_control("damage") as SpinBox
	assert_false(locked.editable)
	assert_false(form.set_value("damage", 99))
	assert_eq(form.get_change_table()["damage"]["value"], 0)

func test_types_and_distinct_empty_states_are_not_collapsed() -> void:
	var form: ParamForm = _form()
	assert_true(form.get_control("damage") is SpinBox)
	assert_true(form.get_control("ratio") is SpinBox)
	assert_true(form.get_control("enabled") is CheckButton)
	assert_true(form.get_control("mode") is OptionButton)
	assert_true(form.get_control("label") is LineEdit)
	assert_true(form.get_control("mystery") is Label)
	assert_true(form.get_control("empty_list") is Label)
	assert_true(form.set_value("label", null))
	var table: Dictionary = form.get_change_table()
	assert_eq(table["label"]["state"], "null")
	assert_eq(table["empty_list"]["state"], "empty_array")
	assert_eq(table["damage"]["value"], 0)
	assert_eq(table["damage"]["state"], "value")
	assert_eq(table["mystery"]["state"], "unset")
	assert_ne(table["label"]["state"], table["damage"]["state"])

func test_relic_mode_intersects_relic_and_exposed_paths() -> void:
	var card: Dictionary = _card()
	card["relic_params"] = {"ratio": "可改", "hidden": "可改"}
	var form: ParamForm = FORM_SCENE.instantiate()
	add_child_autofree(form)
	form.configure(_metadata(), {"tick_rate": 60.0}, {}, card, "relic")
	assert_not_null(form.get_control("ratio"))
	assert_null(form.get_control("hidden"))
	assert_null(form.get_control("damage"))

func test_missing_columns_are_explicit_and_do_not_throw() -> void:
	var metadata: Dictionary = _metadata()
	metadata["leaves"] = [{"path": "value", "type": "integer"}]
	var card: Dictionary = {"author_params": ["value"]}
	var form: ParamForm = FORM_SCENE.instantiate()
	add_child_autofree(form)
	var result: Dictionary = form.configure(metadata, {"tick_rate": 48.0}, {}, card)
	assert_true(result.has("rows"))
	assert_not_null(form.get_control("value"))
	assert_string_contains(form.get_row("value").get("level", ""), "未登记")
	var row: Dictionary = form.get_row("value")
	var entry: Dictionary = row["entry"]
	assert_false(entry.has("minimum") or entry.has("maximum"), "missing range must not be guessed")
	assert_false(entry.has("required") or entry.has("is_required"), "missing requiredness must not be guessed")
	var row_box: Control = form.get_control("value").get_parent() as Control
	var marker: Label = row_box.get_child(row_box.get_child_count() - 1) as Label
	assert_string_contains(marker.text, "取值范围：未登记")
	assert_string_contains(marker.text, "必填：未登记")
	assert_string_contains(marker.text, "分级：未登记")
	assert_true(form.set_value("value", 123))
	assert_eq(form.get_change_table()["value"]["value"], 123, "the UI must not invent an unregistered limit")
	var range_only: Dictionary = metadata.duplicate(true)
	range_only["leaves"][0]["default"] = 0
	range_only["leaves"][0]["required"] = false
	range_only["leaves"][0]["level"] = "新手"
	var other: ParamForm = FORM_SCENE.instantiate()
	add_child_autofree(other)
	other.configure(range_only, {"tick_rate": 48.0}, {}, card)
	var other_row: Control = other.get_control("value").get_parent() as Control
	var other_marker: Label = other_row.get_child(other_row.get_child_count() - 1) as Label
	assert_string_contains(other_marker.text, "取值范围：未登记", "registered defaults/level cannot mask a missing range")
	assert_false(other_marker.text.contains("必填：未登记"))
	assert_false(other_marker.text.contains("分级：未登记"))

func test_draft_is_unchanged_and_submission_retains_path_values_and_sources() -> void:
	var draft: Dictionary = {
		"schema_version": "0.1", "skill_id": "hero_spell_probe",
		"params": {"ratio": 1.25, "enabled": false, "windup_ticks": 3, "empty_list": []},
		"runtime_hints": {"example": {"labels": ["kept"]}}
	}
	var before: Dictionary = draft.duplicate(true)
	var before_text: String = JSON.stringify(draft)
	var form: ParamForm = _form(60.0, draft)
	assert_eq(form.get_change_table()["ratio"]["source"], "params")
	assert_eq(form.get_change_table()["ratio"]["value"], 1.25)
	assert_true(form.set_value("ratio", 2.5, "params"))
	assert_true(form.set_value("label", "override", "brick_override"))
	assert_true(form.set_value("enabled", true, "relic"))
	var result: Dictionary = form.submit_form()
	assert_true(result["ok"])
	var changes: Dictionary = result["changes"]
	assert_eq(changes["ratio"]["value"], 2.5)
	assert_eq(changes["ratio"]["source"], "params")
	assert_eq(changes["label"]["value"], "override")
	assert_eq(changes["label"]["source"], "brick_override")
	assert_eq(changes["enabled"]["value"], true)
	assert_eq(changes["enabled"]["source"], "relic")
	assert_eq(result["values"]["windup_ticks"], 3)
	assert_eq(draft, before, "form submission must not write into nested draft CFG")
	assert_eq(JSON.stringify(draft), before_text, "draft serialization must be byte-identical")

func test_enum_options_follow_the_injected_enumeration() -> void:
	var metadata: Dictionary = _metadata()
	for entry in metadata["leaves"]:
		if entry["path"] == "mode":
			entry["type"] = "enum"
			entry.erase("enum")
	var form: ParamForm = FORM_SCENE.instantiate()
	add_child_autofree(form)
	form.configure(metadata, {"tick_rate": 60.0}, {}, _card())
	var options: OptionButton = form.get_control("mode") as OptionButton
	assert_eq(_option_items(options), metadata["enums"]["mode"])
	var changed: Dictionary = metadata.duplicate(true)
	changed["enums"]["mode"] = ["gamma", "delta", "epsilon"]
	var alternate: ParamForm = FORM_SCENE.instantiate()
	add_child_autofree(alternate)
	alternate.configure(changed, {"tick_rate": 60.0}, {}, _card())
	var alternate_options: OptionButton = alternate.get_control("mode") as OptionButton
	assert_eq(_option_items(alternate_options), changed["enums"]["mode"])
	assert_ne(_option_items(alternate_options), _option_items(options), "a cached or hard-coded list cannot pass")

func test_missing_tick_rate_makes_time_inputs_explicitly_unavailable() -> void:
	var form: ParamForm = FORM_SCENE.instantiate()
	add_child_autofree(form)
	var result: Dictionary = form.configure(_metadata(), {}, {}, _card())
	assert_false(result["units_ok"])
	assert_string_contains(result["error"], "tick_rate")
	var message: Label = form.get_node("Message") as Label
	assert_string_contains(message.text, "tick_rate")
	assert_false(form.get_ticks_control("windup_ticks").editable)
	assert_false(form.get_seconds_control("windup_ticks").editable)
	assert_false(form.set_value("windup_ticks", 60))
	assert_eq(form.get_change_table()["windup_ticks"]["state"], "unset")

func test_seconds_input_rounds_tiny_positive_up_but_preserves_zero() -> void:
	var form: ParamForm = _form(60.0)
	var seconds: SpinBox = form.get_seconds_control("windup_ticks")
	seconds.value = 0.0001
	var positive: Variant = form.get_change_table()["windup_ticks"]["value"]
	assert_true(positive is int)
	assert_true(positive is int and positive >= 1, "positive duration must not collapse to zero")
	assert_eq(positive, 1)
	seconds.value = 0.0
	var zero: Variant = form.get_change_table()["windup_ticks"]["value"]
	assert_true(zero is int)
	assert_eq(zero, 0)
	assert_eq(form.get_change_table()["windup_ticks"]["state"], "value")
