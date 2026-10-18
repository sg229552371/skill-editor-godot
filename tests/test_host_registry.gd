extends "res://addons/gut/test.gd"

const RegistryScript = preload("res://skill_core/runtime/hosts/host_registry.gd")


class ProbeAdapter extends RefCounted:
	var label: String

	func _init(value: String = "first"):
		label = value

	func validate(request: Dictionary, ctx: Dictionary) -> Dictionary:
		return {"ok": true, "error": "", "path": "", "code": "",
			"label": label, "request": request, "ctx": ctx}

	func begin(request: Dictionary, ctx: Dictionary) -> Dictionary:
		return {"ok": true, "error": "", "state": {
			"label": label, "request": request.duplicate(true), "ctx": ctx.duplicate(true)}}

	func advance(state: Dictionary, tick: int, ctx: Dictionary) -> Dictionary:
		return {"ok": true, "error": "", "state": state, "tick": tick, "ctx": ctx,
			"emissions": {"spawn": [], "attach": [], "events": [], "records": []}}


class MissingValidate extends RefCounted:
	func begin(_request: Dictionary, _ctx: Dictionary) -> Dictionary:
		return {}

	func advance(_state: Dictionary, _tick: int, _ctx: Dictionary) -> Dictionary:
		return {}


class MissingBegin extends RefCounted:
	func validate(_request: Dictionary, _ctx: Dictionary) -> Dictionary:
		return {}

	func advance(_state: Dictionary, _tick: int, _ctx: Dictionary) -> Dictionary:
		return {}


class MissingAdvance extends RefCounted:
	func validate(_request: Dictionary, _ctx: Dictionary) -> Dictionary:
		return {}

	func begin(_request: Dictionary, _ctx: Dictionary) -> Dictionary:
		return {}


class FailingAdapter extends RefCounted:
	func validate(_request: Dictionary, _ctx: Dictionary) -> Dictionary:
		return {"ok": false, "error": "validate rejected", "path": "cast.shot_ticks[1]", "code": "PROBE_VALIDATE"}

	func begin(_request: Dictionary, _ctx: Dictionary) -> Dictionary:
		return {"ok": false, "error": "begin rejected", "path": "cast.cooldown_seconds", "code": "PROBE_BEGIN"}

	func advance(_state: Dictionary, _tick: int, _ctx: Dictionary) -> Dictionary:
		return {"ok": false, "error": "advance rejected", "path": "state.next_index", "code": "PROBE_ADVANCE"}


func _assert_failure(result: Dictionary, path: String, code: String, fragment: String):
	assert_false(result.get("ok", true), str(result))
	assert_eq(result.get("path", ""), path)
	assert_eq(result.get("code", ""), code)
	assert_true(str(result.get("error", "")).contains(fragment), str(result))


func test_unknown_section_is_rejected_and_named():
	var registry: RefCounted = RegistryScript.new()
	_assert_failure(registry.register("unknown_section", ProbeAdapter.new()),
		"section", "UNKNOWN_SECTION", "unknown_section")
	assert_false(registry.has_adapter("unknown_section"))
	assert_eq(registry.sections(), [])


func test_duplicate_registration_cannot_replace_first_adapter():
	var registry: RefCounted = RegistryScript.new()
	assert_true(registry.register("cast", ProbeAdapter.new("original"))["ok"])
	_assert_failure(registry.register("cast", ProbeAdapter.new("replacement")),
		"section", "DUPLICATE_ADAPTER", "cast")
	assert_eq(registry.validate("cast", {}, {})["label"], "original")
	assert_eq(registry.begin("cast", {}, {})["state"]["label"], "original")
	assert_eq(registry.sections(), ["cast"])


func test_null_adapter_is_rejected():
	var registry: RefCounted = RegistryScript.new()
	_assert_failure(registry.register("cast", null), "adapter", "INVALID_ADAPTER", "cast")
	assert_false(registry.has_adapter("cast"))


func test_non_object_adapter_is_rejected():
	var registry: RefCounted = RegistryScript.new()
	_assert_failure(registry.register("cast", 7), "adapter", "INVALID_ADAPTER", "cast")
	assert_false(registry.has_adapter("cast"))


func test_missing_validate_is_rejected():
	var registry: RefCounted = RegistryScript.new()
	_assert_failure(registry.register("cast", MissingValidate.new()),
		"adapter.validate", "INVALID_ADAPTER", "validate")
	assert_false(registry.has_adapter("cast"))


func test_missing_begin_is_rejected():
	var registry: RefCounted = RegistryScript.new()
	_assert_failure(registry.register("cast", MissingBegin.new()),
		"adapter.begin", "INVALID_ADAPTER", "begin")
	assert_false(registry.has_adapter("cast"))


func test_missing_advance_is_rejected():
	var registry: RefCounted = RegistryScript.new()
	_assert_failure(registry.register("cast", MissingAdvance.new()),
		"adapter.advance", "INVALID_ADAPTER", "advance")
	assert_false(registry.has_adapter("cast"))


func test_unregistered_sections_fail_at_all_three_entrypoints():
	var registry: RefCounted = RegistryScript.new()
	assert_eq(RegistryScript.SECTIONS, ["cast", "timing", "attached", "summon", "emission", "carrier"])
	for section in RegistryScript.SECTIONS:
		var results: Array = [registry.validate(section, {}, {}),
			registry.begin(section, {}, {}), registry.advance(section, {}, 4, {})]
		assert_eq(results.size(), 3)
		for result in results:
			_assert_failure(result, section, "HOST_ADAPTER_MISSING", "Host adapter")
			assert_true(str(result["error"]).contains(section), str(result))


func test_adapter_failures_preserve_complete_payload():
	var registry: RefCounted = RegistryScript.new()
	var adapter: RefCounted = FailingAdapter.new()
	assert_true(registry.register("cast", adapter)["ok"])
	assert_eq(registry.validate("cast", {}, {}), adapter.validate({}, {}))
	assert_eq(registry.begin("cast", {}, {}), adapter.begin({}, {}))
	assert_eq(registry.advance("cast", {}, 7, {}), adapter.advance({}, 7, {}))
	assert_eq(registry.validate("cast", {}, {})["path"], "cast.shot_ticks[1]")
	assert_eq(registry.advance("cast", {}, 7, {})["code"], "PROBE_ADVANCE")


func test_two_begins_have_independent_state_and_forward_inputs():
	var registry: RefCounted = RegistryScript.new()
	assert_true(registry.register("cast", ProbeAdapter.new())["ok"])
	var first: Dictionary = registry.begin("cast", {"payload": {"value": 1}}, {"shot_id": "a"})
	var second: Dictionary = registry.begin("cast", {"payload": {"value": 2}}, {"shot_id": "b"})
	assert_true(first["ok"])
	assert_true(second["ok"])
	assert_eq(first["state"]["request"]["payload"]["value"], 1)
	assert_eq(second["state"]["request"]["payload"]["value"], 2)
	first["state"]["request"]["payload"]["value"] = 99
	assert_eq(second["state"]["request"]["payload"]["value"], 2)
	assert_eq(first["state"]["ctx"]["shot_id"], "a")
	assert_eq(second["state"]["ctx"]["shot_id"], "b")
	var advanced: Dictionary = registry.advance("cast", first["state"], 17, {"interrupt": true})
	assert_true(advanced["ok"])
	assert_eq(advanced["state"], first["state"])
	assert_eq(advanced["tick"], 17)
	assert_eq(advanced["ctx"], {"interrupt": true})


func test_sections_follow_frozen_order_not_registration_order():
	var registry: RefCounted = RegistryScript.new()
	assert_eq(registry.sections(), [])
	for section in ["carrier", "emission", "summon", "attached", "timing", "cast"]:
		assert_true(registry.register(section, ProbeAdapter.new(section))["ok"])
		assert_true(registry.has_adapter(section))
	assert_eq(registry.sections(), ["cast", "timing", "attached", "summon", "emission", "carrier"])
	var exposed: Array = registry.sections()
	exposed.clear()
	assert_eq(registry.sections().size(), 6, "Returned list cannot erase registry entries")
