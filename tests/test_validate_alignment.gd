extends GutTest

const Rules = preload("res://skill_core/validate/rules/r_present.gd")
const Diag = preload("res://skill_core/api/diagnostic.gd")

func _meta() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/presentation_meta.json"))
	assert_true(data is Dictionary)
	return data if data is Dictionary else {}

func _cfg() -> Dictionary:
	return {"schema_version": "0.1", "meta": {"version": "1", "player_attributes": []}, "presentation": {
		"fx": {}, "sfx": {}, "anim": {}, "trail": {}, "camera": {"enabled": false},
		"damage_number": {}, "status_icon": {}}}

func _context() -> Dictionary:
	return {"player_attribute_bindings": {}, "resource_resolution": {}, "probe_credentials": {},
		"baseline_version_state": {"baseline_version": "1", "current_underlying_version": "1", "operation": "save"},
		"default_applications": [], "migration_state": {"migrating": false, "source_version": "0.1", "target_version": "0.1", "path_complete": true, "lossless": true},
		"preview_fingerprint": {"preview_fingerprint": "a", "current_fingerprint": "a", "operation": "save"}}

func _rules(metadata: Dictionary) -> Rules:
	var rules: Rules = Rules.new()
	assert_true(rules.configure(metadata), rules.last_error)
	return rules

func _paths(result: Dictionary, rule_id: String) -> Array[String]:
	var paths: Array[String] = []
	for diagnostic in result.diagnostics:
		if diagnostic.rule_id == rule_id:
			paths.append(diagnostic.path)
			assert_eq(diagnostic.severity, Diag.SEV_BLOCK)
			assert_false(diagnostic.hint.is_empty())
	return paths

func _blocked(rules: Rules, cfg: Dictionary, expected: Array) -> void:
	# NaN 不等于自身；用稳定文本比较避免只读断言因非有限测试值误红。
	var before: String = var_to_str(cfg)
	var result: Dictionary = rules.validate(cfg, _context())
	assert_false(result.ok)
	assert_false(expected.is_empty())
	assert_eq(_paths(result, "V-074"), expected)
	assert_eq(var_to_str(cfg), before, "校验不得改写 CFG 或补默认")

func test_enabled_missing_and_empty_alignments_block_at_array() -> void:
	var rules: Rules = _rules(_meta())
	var cfg: Dictionary = _cfg()
	cfg.presentation.anim["cast_clip"] = {"id": "cast"}
	_blocked(rules, cfg, ["presentation.anim.alignments"])
	cfg.presentation.anim["alignments"] = []
	_blocked(rules, cfg, ["presentation.anim.alignments"])

func _accepted_with_control(rules: Rules, cfg: Dictionary, broken: Dictionary, expected: Array) -> void:
	_blocked(rules, broken, expected)
	var before: Dictionary = cfg.duplicate(true)
	var result: Dictionary = rules.validate(cfg, _context())
	assert_true(result.ok, str(result.diagnostics))
	assert_eq(_paths(result, "V-074").size(), 0, "非空破坏对照后才断言无 V-074")
	assert_eq(cfg, before)

func test_each_missing_key_and_actual_later_index() -> void:
	var rules: Rules = _rules(_meta())
	var cfg: Dictionary = _cfg()
	cfg.presentation.anim["cast_clip"] = {"id": "cast"}
	cfg.presentation.anim["alignments"] = [{"frame": 0}]
	_blocked(rules, cfg, ["presentation.anim.alignments[0].shot_tick"])
	cfg.presentation.anim["alignments"] = [{"shot_tick": 0}]
	_blocked(rules, cfg, ["presentation.anim.alignments[0].frame"])
	cfg.presentation.anim["alignments"] = [{"shot_tick": 0, "frame": 0}, {}]
	_blocked(rules, cfg, ["presentation.anim.alignments[1].shot_tick", "presentation.anim.alignments[1].frame"])

func test_complete_nonempty_array_passes_with_empty_control() -> void:
	var rules: Rules = _rules(_meta())
	var cfg: Dictionary = _cfg()
	cfg.presentation.anim["cast_clip"] = {"id": "cast"}
	cfg.presentation.anim["alignments"] = [{"shot_tick": 0, "frame": 0}, {"shot_tick": 3, "frame": 7}]
	var broken: Dictionary = cfg.duplicate(true)
	broken.presentation.anim["alignments"] = []
	_accepted_with_control(rules, cfg, broken, ["presentation.anim.alignments"])

func test_old_scalars_do_not_replace_array_or_fill_missing_key() -> void:
	var rules: Rules = _rules(_meta())
	var cfg: Dictionary = _cfg()
	cfg.presentation.anim["logic_release_tick"] = 0
	cfg.presentation.anim["release_frame"] = 0
	_blocked(rules, cfg, ["presentation.anim.alignments"])
	cfg.presentation.anim["cast_clip"] = {"id": "cast"}
	_blocked(rules, cfg, ["presentation.anim.alignments"])
	cfg.presentation.anim["alignments"] = [{"shot_tick": 0}]
	_blocked(rules, cfg, ["presentation.anim.alignments[0].frame"])

func test_disabled_placeholders_have_enabled_nonempty_controls() -> void:
	var rules: Rules = _rules(_meta())
	for anim in [{}, {"cast_clip": {}}, {"alignments": []}, {"alignments": [], "cast_clip": {}, "on_hit": {}, "on_settled": {}}]:
		var cfg: Dictionary = _cfg()
		cfg.presentation["anim"] = anim.duplicate(true)
		var broken: Dictionary = cfg.duplicate(true)
		broken.presentation.anim["cast_clip"] = {"id": "cast"}
		_accepted_with_control(rules, cfg, broken, ["presentation.anim.alignments"])

func test_each_registered_activity_slot_enables_alignment_requirement() -> void:
	var metadata: Dictionary = _meta()
	var rules: Rules = _rules(metadata)
	var slots: Array = metadata.section_enable.anim.activity_slots
	assert_false(slots.is_empty())
	for slot in slots:
		var cfg: Dictionary = _cfg()
		cfg.presentation.anim[slot] = {"id": "cast"} if slot == "cast_clip" else {"alignments": "bound"}
		_blocked(rules, cfg, ["presentation.anim.alignments"])

func test_array_and_item_wrong_types_are_locatable() -> void:
	var rules: Rules = _rules(_meta())
	var cfg: Dictionary = _cfg()
	cfg.presentation.anim["cast_clip"] = {"id": "cast"}
	for value in [null, {}, "0", 0, false]:
		cfg.presentation.anim["alignments"] = value
		_blocked(rules, cfg, ["presentation.anim.alignments"])
	for value in [null, [], "0", 0, false]:
		cfg.presentation.anim["alignments"] = [{"shot_tick": 0, "frame": 0}, value]
		_blocked(rules, cfg, ["presentation.anim.alignments[1]"])

func test_tick_wrong_types_and_nonfinite_or_negative_values_block() -> void:
	var rules: Rules = _rules(_meta())
	var cfg: Dictionary = _cfg()
	cfg.presentation.anim["cast_clip"] = {"id": "cast"}
	for value in [null, "0", false, [], {}, 0.0, 0.5, -1, NAN, INF, -INF]:
		cfg.presentation.anim["alignments"] = [{"shot_tick": value, "frame": 0}]
		_blocked(rules, cfg, ["presentation.anim.alignments[0].shot_tick"])

func test_frame_wrong_types_and_nonfinite_or_negative_values_block() -> void:
	var rules: Rules = _rules(_meta())
	var cfg: Dictionary = _cfg()
	cfg.presentation.anim["cast_clip"] = {"id": "cast"}
	for value in [null, "0", false, [], {}, -1, -0.5, NAN, INF, -INF]:
		cfg.presentation.anim["alignments"] = [{"shot_tick": 0, "frame": 0}, {"shot_tick": 1, "frame": value}]
		_blocked(rules, cfg, ["presentation.anim.alignments[1].frame"])

func test_numeric_frame_and_zero_tick_boundaries_have_negative_controls() -> void:
	var rules: Rules = _rules(_meta())
	for frame in [0, 0.0, 0.5, 1000000]:
		var cfg: Dictionary = _cfg()
		cfg.presentation.anim["cast_clip"] = {"id": "cast"}
		cfg.presentation.anim["alignments"] = [{"shot_tick": 0, "frame": frame}]
		var broken: Dictionary = cfg.duplicate(true)
		broken.presentation.anim["alignments"][0]["frame"] = -1
		_accepted_with_control(rules, cfg, broken, ["presentation.anim.alignments[0].frame"])

func test_legal_alignment_keys_are_not_logic_writeback_but_unknown_key_is() -> void:
	var rules: Rules = _rules(_meta())
	var cfg: Dictionary = _cfg()
	cfg.presentation.anim["cast_clip"] = {"id": "cast"}
	cfg.presentation.anim["alignments"] = [{"shot_tick": 0, "frame": 0}]
	var broken: Dictionary = cfg.duplicate(true)
	broken.presentation.anim["alignments"] = []
	_accepted_with_control(rules, cfg, broken, ["presentation.anim.alignments"])
	cfg.presentation.anim["alignments"][0]["drive_shot"] = true
	var result: Dictionary = rules.validate(cfg, _context())
	assert_false(result.ok)
	assert_eq(_paths(result, "V-072"), ["presentation.anim.alignments[0].drive_shot"])

func test_metadata_rename_drives_array_required_keys_and_leaf_types() -> void:
	var metadata: Dictionary = _meta()
	var old_path: String = "presentation.anim.alignments"
	var new_path: String = "presentation.anim.cues"
	var renamed_arrays: int = 0
	for entry in metadata.arrays:
		if entry.path == old_path:
			entry["path"] = new_path
			entry["item"]["required"] = ["logic_tick", "visual_frame"]
			renamed_arrays += 1
	assert_eq(renamed_arrays, 1)
	var renamed_leaves: int = 0
	for entry in metadata.leaves:
		if entry.path == old_path + "[i].shot_tick":
			entry["path"] = new_path + "[i].logic_tick"
			entry["minimum"] = 2.0
			renamed_leaves += 1
		elif entry.path == old_path + "[i].frame":
			entry["path"] = new_path + "[i].visual_frame"
			entry["type"] = "integer"
			renamed_leaves += 1
	assert_eq(renamed_leaves, 2)
	var renamed_objects: int = 0
	for entry in metadata.objects:
		if entry.path == old_path + "[i]":
			entry["path"] = new_path + "[i]"
			entry["required"] = [new_path + "[i].logic_tick", new_path + "[i].visual_frame"]
			renamed_objects += 1
	assert_eq(renamed_objects, 1)
	metadata.enabled_requires["anim"] = ["cues"]
	var rules: Rules = _rules(metadata)
	var cfg: Dictionary = _cfg()
	cfg.presentation.anim["cast_clip"] = {"id": "cast"}
	_blocked(rules, cfg, [new_path])
	cfg.presentation.anim["cues"] = [{"logic_tick": 2, "visual_frame": 0}]
	var broken: Dictionary = cfg.duplicate(true)
	broken.presentation.anim["cues"][0].erase("logic_tick")
	_accepted_with_control(rules, cfg, broken, [new_path + "[0].logic_tick"])
	cfg.presentation.anim["cues"][0].erase("visual_frame")
	_blocked(rules, cfg, [new_path + "[0].visual_frame"])
	cfg.presentation.anim["cues"] = [{"logic_tick": 1, "visual_frame": 0.5}]
	_blocked(rules, cfg, [new_path + "[0].logic_tick", new_path + "[0].visual_frame"])
	cfg.presentation.anim["cues"] = [{"shot_tick": 2, "frame": 0}]
	_blocked(rules, cfg, [new_path + "[0].logic_tick", new_path + "[0].visual_frame"])
