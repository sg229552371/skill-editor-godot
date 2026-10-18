extends GutTest

const YamlLite = preload("res://skill_core/schema/yaml_lite.gd")
const CfgCodec = preload("res://skill_core/schema/cfg_codec.gd")

func _valid_cfg() -> Dictionary:
	return {
		"schema_version": "0.1",
		"skill_id": "mage_projectile_bolt",
		"meta": {"name": "测试技能", "tags": []},
		"bricks": [{
			"brick_id": "projectile_bolt",
			"name": "弹道",
			"tagline": "向前发射",
			"carrier": "independent",
			"summary": "发射一个弹体",
			"default_cfg": {},
			"author_params": [],
			"locked_params": {},
			"relic_params": {},
			"presentation": [],
			"player_text": ["发射弹体"],
			"status": "已登记",
		}],
		"params": {"empty_list": [], "enabled": true, "speed": 2.5},
		"presentation": {
			"fx": {}, "sfx": {}, "anim": {}, "trail": {},
			"camera": {}, "damage_number": {}, "status_icon": {},
		},
		"runtime_hints": {},
	}

func test_cfg_round_trip_is_deep_equal() -> void:
	var cfg: Dictionary = _valid_cfg()
	var dumped: String = YamlLite.dump(cfg)
	var parsed: Dictionary = YamlLite.parse(dumped)
	assert_true(parsed.ok, "canonical CFG YAML should parse")
	assert_eq(parsed.data, cfg, "dump then parse must preserve the complete CFG")
	var structure_errors: Array = CfgCodec.validate_structure(parsed.data)
	assert_eq(structure_errors.size(), 0, "the round-tripped CFG remains structurally valid")

func test_yaml_string_scalars_round_trip_preserves_type_and_value() -> void:
	var samples: Array[String] = ["0.1", "42", "true", "null", "", "- x", "a: b", "a #c"]
	for sample in samples:
		var parsed: Dictionary = YamlLite.parse(YamlLite.dump({"value": sample}))
		assert_true(parsed.ok, "string scalar must parse: %s" % sample)
		if not parsed.ok:
			continue
		var data: Dictionary = parsed["data"]
		assert_eq(typeof(data["value"]), TYPE_STRING, "scalar type must remain String: %s" % sample)
		assert_eq(data["value"], sample, "scalar value must survive: %s" % sample)

func test_yaml_quotes_ambiguous_strings_and_preserves_escapes() -> void:
	var samples: Array[String] = [
		"-3", "1e5", ".5", "false", "~", "#comment", "first\nsecond",
		" leading", "trailing ", "a: \"quoted\" #text", "a: C:\\folder\\",
		'a: \\" #text', 'a: \\\\" #text', "a: literal\\n", "a: tab\tend", "a: cr\rend",
	]
	for keyword in ["true", "false", "null", "yes", "no", "on", "off"]:
		samples.append(keyword)
		samples.append(keyword.to_upper())
		samples.append(keyword.capitalize())
	for sample in samples:
		var dumped: String = YamlLite.dump({"value": sample, "values": [sample, "tail"]})
		assert_true(dumped.begins_with("value: \""), "ambiguous string must be double quoted")
		var parsed: Dictionary = YamlLite.parse(dumped)
		assert_true(parsed.ok, "quoted scalar must parse: %s" % sample)
		if not parsed.ok:
			continue
		var data: Dictionary = parsed["data"]
		assert_eq(typeof(data["value"]), TYPE_STRING)
		assert_eq(data["value"], sample)
		var values: Array = data["values"]
		assert_eq(values.size(), 2, "escaped strings must not consume the next item")
		assert_eq(typeof(values[0]), TYPE_STRING)
		assert_eq(values[0], sample)
		assert_eq(values[1], "tail")

func test_yaml_escaped_quotes_preserve_inline_delimiters() -> void:
	var sample: String = 'a: \\" #text, : value'
	var parsed: Dictionary = YamlLite.parse("values: [" + JSON.stringify(sample) + ", \"tail\"]\n")
	assert_true(parsed.ok, "escaped quotes must not expose inline commas or comments")
	if not parsed.ok:
		return
	var data: Dictionary = parsed["data"]
	var values: Array = data["values"]
	assert_eq(values.size(), 2)
	assert_eq(typeof(values[0]), TYPE_STRING)
	assert_eq(values[0], sample)
	assert_eq(values[1], "tail")

func test_yaml_keeps_unambiguous_strings_bare() -> void:
	assert_eq(YamlLite.dump({"name": "弹道"}), "name: 弹道\n")
	for sample in ["hello world", "mage_projectile_bolt", "a:b", "a#b"]:
		assert_eq(YamlLite.dump({"value": sample}), "value: " + sample + "\n")

func test_yaml_supports_nested_sequences_comments_and_blocks() -> void:
	var parsed: Dictionary = YamlLite.parse("""
# comment
root:
  values: [1, 2.5, true, null, 'quoted, value']
  literal: |
    first
    second
  folded: >
    hello
    world
""")
	assert_true(parsed.ok, "the supported YAML subset should parse")
	var data: Dictionary = parsed["data"]
	var root: Dictionary = data["root"]
	var values: Array = root["values"]
	assert_eq(values[0], 1)
	assert_eq(values[4], "quoted, value")
	assert_eq(root["literal"], "first\nsecond\n")
	assert_eq(root["folded"], "hello world\n")

func test_yaml_rejects_duplicate_keys_with_location() -> void:
	var parsed: Dictionary = YamlLite.parse("meta:\n  name: one\n  name: two\n")
	assert_false(parsed.ok, "duplicate keys must be rejected")
	assert_true(str(parsed.error).contains("line 3"), "duplicate-key error identifies its source line")
	assert_true(str(parsed.error).contains("name"), "duplicate-key error identifies the key")

func test_yaml_rejects_unsafe_constructs() -> void:
	for source in ["x: !!str value\n", "x: &anchor value\n", "x: *anchor\n", "---\nx: 1\n", "x: yes\n", "x: .nan\n", "x: inf\n", "x:\n\tbad: 1\n"]:
		var parsed: Dictionary = YamlLite.parse(source)
		assert_false(parsed.ok, "unsafe YAML construct must be rejected: %s" % source.strip_edges())

func test_structure_rejects_extra_top_level_key_with_path() -> void:
	var cfg: Dictionary = _valid_cfg()
	cfg["extra"] = true
	var diagnostics: Array = CfgCodec.validate_structure(cfg)
	assert_true(_has_path(diagnostics, "extra"), "extra top-level field is located at extra")

func test_structure_rejects_missing_brick_field_with_indexed_path() -> void:
	var cfg: Dictionary = _valid_cfg()
	cfg["bricks"][0].erase("summary")
	var diagnostics: Array = CfgCodec.validate_structure(cfg)
	assert_true(_has_path(diagnostics, "bricks[0].summary"), "missing brick field uses the actual indexed slot")

func test_structure_rejects_instant_carrier() -> void:
	var cfg: Dictionary = _valid_cfg()
	cfg["bricks"][0]["carrier"] = "instant"
	var diagnostics: Array = CfgCodec.validate_structure(cfg)
	assert_true(_has_path(diagnostics, "bricks[0].carrier"), "instant is rejected at the carrier slot")

func test_structure_requires_all_presentation_slots() -> void:
	var cfg: Dictionary = _valid_cfg()
	cfg["presentation"].erase("camera")
	var diagnostics: Array = CfgCodec.validate_structure(cfg)
	assert_true(_has_path(diagnostics, "presentation.camera"), "missing presentation slot is located precisely")

func test_structure_rejects_four_player_text_lines() -> void:
	var cfg: Dictionary = _valid_cfg()
	cfg["bricks"][0]["player_text"] = ["a", "b", "c", "d"]
	var diagnostics: Array = CfgCodec.validate_structure(cfg)
	assert_true(_has_path(diagnostics, "bricks[0].player_text"), "player_text limit error is located precisely")

func test_empty_array_is_valid_but_missing_field_is_not() -> void:
	var cfg: Dictionary = _valid_cfg()
	cfg["bricks"][0]["author_params"] = []
	var valid_errors: Array = CfgCodec.validate_structure(cfg)
	assert_false(_has_path(valid_errors, "bricks[0].author_params"), "an explicit empty array means no configuration")
	cfg["bricks"][0].erase("author_params")
	var missing_errors: Array = CfgCodec.validate_structure(cfg)
	assert_true(_has_path(missing_errors, "bricks[0].author_params"), "a missing field is distinct from an empty array")

func test_null_is_rejected_at_actual_path() -> void:
	var cfg: Dictionary = _valid_cfg()
	cfg["params"]["optional_later"] = null
	var diagnostics: Array = CfgCodec.validate_structure(cfg)
	assert_true(_has_path(diagnostics, "params.optional_later"), "null is rejected at the nested field path")

func _has_path(diagnostics: Array, expected_path: String) -> bool:
	for diagnostic in diagnostics:
		if diagnostic.path == expected_path:
			return true
	return false
