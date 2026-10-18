extends GutTest

const PresentationPanel = preload("res://addons/skill_editor/ui/presentation_panel.gd")
const META_PATH: String = "res://data/presentation_meta.json"

func _metadata() -> Dictionary:
	var file: FileAccess = FileAccess.open(META_PATH, FileAccess.READ)
	assert_not_null(file)
	var parser: JSON = JSON.new()
	assert_eq(parser.parse(file.get_as_text()), OK)
	assert_true(parser.data is Dictionary)
	return parser.data.duplicate(true)

func _panel() -> PresentationPanel:
	var panel: PresentationPanel = PresentationPanel.new()
	add_child_autofree(panel)
	return panel

func _leaf_fields(metadata: Dictionary, section: String) -> Array:
	var result: Array = []
	for entry_value in metadata.get("leaves", []):
		if entry_value is Dictionary:
			var path: String = String(entry_value.get("path", ""))
			var prefix: String = "presentation." + section + "."
			if path.begins_with(prefix) and not path.trim_prefix(prefix).contains("."):
				result.append(path.trim_prefix(prefix))
	return result

func test_sections_are_derived_from_metadata_and_all_render() -> void:
	var metadata: Dictionary = _metadata()
	var panel: PresentationPanel = _panel()
	var result: Dictionary = panel.configure(metadata, {})
	assert_true(result["ok"])
	var expected: Array = metadata["required_sections"].duplicate()
	assert_eq(panel.get_section_names(), expected)
	assert_eq(panel.get_section_names().size(), expected.size())
	for section_value in expected:
		var section: String = String(section_value)
		assert_eq(panel.get_section_fields(section), metadata["section_field_index"][section])
		assert_string_contains(panel.get_status(section), "未绑定")
		for field_value in metadata["section_field_index"][section]:
			assert_not_null(panel.get_control(section, String(field_value)))

func test_empty_sections_stay_unbound_and_get_value_has_empty_dictionaries() -> void:
	var metadata: Dictionary = _metadata()
	var panel: PresentationPanel = _panel()
	assert_true(panel.configure(metadata, {})["ok"])
	var value: Dictionary = panel.get_value()
	for section_value in metadata["required_sections"]:
		var section: String = String(section_value)
		assert_true(value.has(section))
		assert_eq(value[section], {})
		assert_eq(panel.get_status(section), "未绑定")
	var changed: Dictionary = panel.get_value()
	changed["fx"]["anchor"] = "caster"
	assert_eq(panel.get_value()["fx"], {})

func test_leaf_fields_follow_metadata_without_defaults_being_invented() -> void:
	var metadata: Dictionary = _metadata()
	var panel: PresentationPanel = _panel()
	var cfg: Dictionary = {"presentation": {"fx": {"anchor": "world"}, "trail": {"carrier": "none"}}}
	assert_true(panel.configure(metadata, cfg)["ok"])
	for section_value in ["fx", "sfx", "anim", "trail", "camera", "damage_number", "status_icon"]:
		var section: String = String(section_value)
		var expected: Array = metadata["section_field_index"][section]
		assert_eq(panel.get_section_fields(section), expected)
		for field_value in _leaf_fields(metadata, section):
			assert_not_null(panel.get_control(section, String(field_value)))
	assert_eq(panel.get_value()["fx"]["anchor"], "world")
	assert_false(panel.get_value()["fx"].has("follow_mode"))
	assert_eq(panel.get_value()["sfx"], {})

func test_carrier_options_are_metadata_driven_and_invalid_value_is_named() -> void:
	var metadata: Dictionary = _metadata()
	var panel: PresentationPanel = _panel()
	assert_true(panel.configure(metadata, {})["ok"])
	var carrier: OptionButton = panel.get_control("trail", "carrier") as OptionButton
	assert_not_null(carrier)
	var expected: Array = []
	for entry_value in metadata["leaves"]:
		if entry_value is Dictionary and entry_value.get("path", "") == "presentation.trail.carrier":
			expected = entry_value["enum"].duplicate()
	assert_eq(carrier.item_count, expected.size())
	for index in range(expected.size()):
		assert_eq(carrier.get_item_text(index), expected[index])
	assert_false(panel.set_value("trail", "carrier", "instant"))
	assert_string_contains(panel.get_error(), "presentation.trail.carrier")
	assert_true(panel.set_value("trail", "carrier", expected[0]))

func test_cfg_and_readback_are_detached_from_panel_draft() -> void:
	var metadata: Dictionary = _metadata()
	var cfg: Dictionary = {"schema_version": "0.1", "presentation": {"trail": {"carrier": "self"}, "fx": {}}}
	var before: String = JSON.stringify(cfg)
	var panel: PresentationPanel = _panel()
	assert_true(panel.configure(metadata, cfg)["ok"])
	assert_true(panel.set_value("trail", "carrier", "attached"))
	assert_eq(JSON.stringify(cfg), before)
	var readback: Dictionary = panel.get_value()
	readback["trail"]["carrier"] = "none"
	assert_eq(panel.get_value()["trail"]["carrier"], "attached")
	assert_eq(JSON.stringify(cfg), before)

func test_missing_metadata_or_configuration_fails_visibly() -> void:
	var panel: PresentationPanel = _panel()
	var missing: Dictionary = panel.configure({"required_sections": []}, {})
	assert_false(missing["ok"])
	assert_string_contains(panel.get_error(), "required_sections")
	assert_string_contains((panel.get_node("Status") as Label).text, "required_sections")
	assert_false(panel.set_value("fx", "anchor", "caster"))
	var unconfigured: PresentationPanel = _panel()
	assert_false(unconfigured.set_value("fx", "anchor", "caster"))
	assert_string_contains(unconfigured.get_error(), "未配置")

func test_section_vocabulary_changes_with_replaced_metadata() -> void:
	var metadata: Dictionary = _metadata()
	metadata["required_sections"] = ["custom"]
	metadata["section_field_index"] = {"custom": ["custom_value"]}
	metadata["leaves"] = [{"path": "presentation.custom.custom_value", "type": "string"}]
	var panel: PresentationPanel = _panel()
	assert_true(panel.configure(metadata, {})["ok"])
	assert_eq(panel.get_section_names(), ["custom"])
	assert_not_null(panel.get_control("custom", "custom_value"))
	assert_null(panel.get_control("fx", "anchor"))
