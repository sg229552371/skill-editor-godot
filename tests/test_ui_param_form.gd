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

func test_level_visibility_does_not_drop_values() -> void:
	var metadata: Dictionary = _metadata()
	for entry in metadata["leaves"]:
		if entry["path"] == "ratio":
			entry["level"] = "专家"
	var form: ParamForm = FORM_SCENE.instantiate()
	add_child_autofree(form)
	form.configure(metadata, {"tick_rate": 60.0}, {}, _card())
	form.set_level_visible("专家", false)
	assert_true(form.set_value("ratio", 2.5))
	assert_eq(form.get_change_table()["ratio"]["value"], 2.5)
	form.set_level_visible("专家", true)
	assert_eq(form.get_change_table()["ratio"]["value"], 2.5)

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
