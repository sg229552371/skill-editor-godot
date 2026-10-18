extends GutTest

const Units = preload("res://skill_core/schema/units.gd")
const META_PATH = "res://data/params_meta.json"


func _units(rate: Variant = 60, meta: Variant = null) -> RefCounted:
	var units: RefCounted = Units.new()
	var result: Dictionary = units.configure({"tick_rate": rate}, meta)
	assert_true(result["ok"], "valid project rate and tick metadata must configure")
	return units


func _meta() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	assert_true(parsed is Dictionary, "the deployed metadata must be readable")
	return parsed if parsed is Dictionary else {}


func test_seconds_ceil_fractional_product() -> void:
	var result: Dictionary = _units().seconds_to_ticks("windup_ticks", 1.001)
	assert_true(result["ok"])
	assert_eq(result["ticks"], 61)
	assert_eq(result["rate"], 60)
	assert_eq(result["seconds"], 1.001)
	assert_eq(result["field"], "windup_ticks")


func test_seconds_exact_product_does_not_add_one() -> void:
	assert_eq(_units().seconds_to_ticks("windup_ticks", 2.0)["ticks"], 120)


func test_zero_seconds_stays_zero() -> void:
	assert_eq(_units().seconds_to_ticks("windup_ticks", 0)["ticks"], 0)


func test_rate_thirty_is_injected() -> void:
	assert_eq(_units(30).seconds_to_ticks("windup_ticks", 1.001)["ticks"], 31)


func test_rate_sixty_is_injected() -> void:
	assert_eq(_units(60).seconds_to_ticks("windup_ticks", 1.001)["ticks"], 61)


func test_rate_one_hundred_twenty_is_injected() -> void:
	assert_eq(_units(120).seconds_to_ticks("windup_ticks", 1.001)["ticks"], 121)


func test_missing_rate_fails_explicitly() -> void:
	var units: RefCounted = Units.new()
	assert_false(units.configure({})["ok"])
	assert_false(units.seconds_to_ticks("windup_ticks", 1)["ok"])


func test_zero_rate_fails_explicitly() -> void:
	assert_false(Units.new().configure({"tick_rate": 0})["ok"])


func test_negative_rate_fails_explicitly() -> void:
	assert_false(Units.new().configure({"tick_rate": -30})["ok"])


func test_nonnumeric_rate_fails_explicitly() -> void:
	assert_false(Units.new().configure({"tick_rate": []})["ok"])


func test_string_rate_fails_explicitly() -> void:
	assert_false(Units.new().configure({"tick_rate": "60"})["ok"])


func test_nonfinite_rate_fails_explicitly() -> void:
	assert_false(Units.new().configure({"tick_rate": INF})["ok"])


func test_non_tick_fields_are_rejected() -> void:
	var units: RefCounted = _units()
	assert_false(units.seconds_to_ticks("damage", 1.0)["ok"])
	assert_false(units.seconds_to_ticks("max_range", 1.0)["ok"])
	assert_false(units.accept_ticks("damage", 1)["ok"])


func test_every_registered_tick_field_accepts_conversion() -> void:
	var meta: Dictionary = _meta()
	if not meta.has("tick_fields"):
		assert_true(false, "tick_fields must be present")
		return
	var fields: Array = meta["tick_fields"]
	assert_eq(fields.size(), 16, "the currently deployed metadata registers 16 fields")
	for field in fields:
		if str(field).begins_with("_"):
			continue
		var result: Dictionary = _units().seconds_to_ticks(str(field).replace("[i]", "[0]"), 1.001)
		assert_true(result["ok"], "registered field must convert: %s" % field)
		if result["ok"]:
			assert_eq(result["ticks"], 61)


func test_extended_metadata_registers_another_field_without_code_change() -> void:
	var meta: Dictionary = _meta()
	var fields: Array = meta["tick_fields"]
	fields.append("custom_phase_ticks")
	fields.append("_note: commentary is not a field")
	var units: RefCounted = _units(30, meta)
	assert_eq(units.seconds_to_ticks("custom_phase_ticks", 1.001)["ticks"], 31)
	assert_false(units.seconds_to_ticks("_note: commentary is not a field", 1)["ok"])


func test_integer_ticks_pass_without_reconversion() -> void:
	var result: Dictionary = _units().accept_ticks("windup_ticks", 61)
	assert_true(result["ok"])
	assert_eq(result["ticks"], 61)
	assert_eq(result["field"], "windup_ticks")
	assert_eq(_units().accept_ticks("windup_ticks", -1)["ticks"], -1, "semantic tick ranges belong to the validator")


func test_fractional_ticks_fail() -> void:
	assert_false(_units().accept_ticks("windup_ticks", 1.5)["ok"])


func test_float_even_if_integral_is_not_an_integer_tick() -> void:
	assert_false(_units().accept_ticks("windup_ticks", 2.0)["ok"])


func test_nonfinite_seconds_fail() -> void:
	var units: RefCounted = _units()
	for value in [NAN, INF, -INF]:
		assert_false(units.seconds_to_ticks("windup_ticks", value)["ok"])


func test_negative_seconds_fail_without_clamping() -> void:
	assert_false(_units().seconds_to_ticks("windup_ticks", -0.01)["ok"])


func test_string_seconds_fail_without_parsing() -> void:
	assert_false(_units().seconds_to_ticks("windup_ticks", "1.5")["ok"])


func test_explicit_null_fails_but_absent_field_is_not_an_error() -> void:
	var units: RefCounted = _units()
	var missing: Dictionary = units.convert_field({}, "windup_ticks", true)
	assert_true(missing["ok"])
	assert_false(missing["present"])
	assert_false(missing.has("ticks"))
	assert_false(units.convert_field({"windup_ticks": null}, "windup_ticks", true)["ok"])
	assert_false(units.convert_field({"windup_ticks": null}, "windup_ticks", false)["ok"])


func test_display_reverse_conversion_is_labeled_and_does_not_change_cfg() -> void:
	var cfg: Dictionary = {"windup_ticks": 61, "nested": {"value": [1, 2]}}
	var before: Dictionary = cfg.duplicate(true)
	var result: Dictionary = _units().ticks_to_seconds("windup_ticks", cfg["windup_ticks"])
	assert_true(result["ok"])
	assert_true(result["display_only"])
	assert_eq(result["seconds"], 61.0 / 60.0)
	assert_eq(result["ticks"], 61)
	assert_eq(cfg, before, "display data must never write back to CFG")


func test_conversion_does_not_modify_input_cfg_or_submit_seconds() -> void:
	var cfg: Dictionary = {"windup_ticks": 1.001, "nested": {"value": [1, 2]}}
	var before: Dictionary = cfg.duplicate(true)
	var result: Dictionary = _units().convert_field(cfg, "windup_ticks", true)
	assert_true(result["ok"])
	assert_true(result["present"])
	assert_eq(result["ticks"], 61)
	assert_false(result.has("cfg"), "only the returned ticks may be submitted")
	assert_eq(cfg, before, "conversion must not mutate its input")


func test_existing_tick_cfg_value_stays_the_same() -> void:
	var cfg: Dictionary = {"windup_ticks": 61}
	var result: Dictionary = _units().convert_field(cfg, "windup_ticks", false)
	assert_true(result["ok"])
	assert_eq(result["ticks"], 61)
	assert_eq(cfg, {"windup_ticks": 61})


func test_missing_or_invalid_metadata_fails_without_empty_registry_fallback() -> void:
	var units: RefCounted = Units.new()
	assert_false(units.configure({"tick_rate": 60}, {"tick_fields": []})["ok"])
	assert_false(units.seconds_to_ticks("windup_ticks", 1)["ok"])
	assert_false(units.configure({"tick_rate": 60}, {"tick_fields": "invalid"})["ok"])
	assert_false(units.configure({"tick_rate": 60}, {"tick_fields": ["_note"]})["ok"])
	assert_false(units.configure({"tick_rate": 60}, "not json metadata")["ok"])
	assert_false(units.configure({"tick_rate": 60}, null, "res://data/no_such_units_metadata.json")["ok"])


func test_overflowing_seconds_fail_instead_of_wrapping_tick_integer() -> void:
	assert_false(_units().seconds_to_ticks("windup_ticks", 1.0e20)["ok"])
