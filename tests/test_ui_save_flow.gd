extends GutTest

const SaveFlow = preload("res://addons/skill_editor/ui/save_flow.gd")

class FakeCodec extends RefCounted:
	func parse_text(text: String) -> Dictionary:
		var value: Variant = JSON.parse_string(text)
		return {"ok": value is Dictionary, "data": value, "diagnostics": []}

	func serialize(cfg: Dictionary) -> String:
		return JSON.stringify(cfg)

class FakeValidator extends RefCounted:
	var calls: int = 0
	func validate(_cfg: Dictionary, _stage: StringName, _context: Dictionary) -> Dictionary:
		calls += 1
		return {"ok": true, "diagnostics": [], "reason": ""}

class Writer extends RefCounted:
	var calls: int = 0
	var last_text: String = ""
	func write(text: String) -> Dictionary:
		calls += 1
		last_text = text
		return {"ok": true}

func _context(state: Dictionary = {"etag": "a"}, revision: int = 1, writer: Writer = null) -> Dictionary:
	var result: Dictionary = {
		"schema_version_state": {"current": "0.1"},
		"baseline_version_state": state.duplicate(true),
		"migration_state": {"allowed": true},
		"draft_revision": revision
	}
	if writer != null:
		result["write"] = Callable(writer, "write")
	return result

func _cfg(value: int = 1) -> Dictionary:
	return {"schema_version": "0.1", "params": {"damage": value}, "meta": {"name": "x"}}

func _flow(validator: FakeValidator = null) -> SaveFlow:
	var flow: SaveFlow = SaveFlow.new()
	var actual_validator: FakeValidator = validator if validator != null else FakeValidator.new()
	assert_true(flow.configure(actual_validator, FakeCodec.new(), {"current_schema_version": "0.1"})["ok"])
	return flow

func test_normal_save_increments_revision_and_writes_once() -> void:
	var writer: Writer = Writer.new()
	var flow: SaveFlow = _flow()
	var result: Dictionary = flow.save(_cfg(), _context({"etag": "a"}, 1, writer))
	assert_true(result["ok"])
	assert_true(result["changed"])
	assert_eq(result["revision"], 2)
	assert_eq(writer.calls, 1)

func test_same_fingerprint_does_not_write_or_advance_revision() -> void:
	var writer: Writer = Writer.new()
	var flow: SaveFlow = _flow()
	var first: Dictionary = flow.save(_cfg(), _context({"etag": "a"}, 1, writer))
	assert_true(first["ok"])
	var second: Dictionary = flow.save(_cfg(), _context({"etag": "a"}, 2, writer))
	assert_true(second["ok"])
	assert_false(second["changed"])
	assert_eq(second["revision"], first["revision"])
	assert_eq(writer.calls, 1)

func test_advanced_baseline_rejects_without_overwriting_and_exposes_actions() -> void:
	var writer: Writer = Writer.new()
	var flow: SaveFlow = _flow()
	assert_true(flow.save(_cfg(), _context({"etag": "a"}, 1, writer))["ok"])
	var before: String = writer.last_text
	var result: Dictionary = flow.save(_cfg(2), _context({"etag": "b"}, 2, writer))
	assert_false(result["ok"])
	assert_eq(result["reason"], "baseline_advanced")
	assert_eq(result["actions"], ["save_as", "reload_baseline"])
	assert_eq(writer.calls, 1)
	assert_eq(writer.last_text, before)

func test_unknown_higher_version_loads_read_only_and_save_is_rejected() -> void:
	var flow: SaveFlow = _flow()
	var context: Dictionary = _context()
	var loaded: Dictionary = flow.load(JSON.stringify(_cfg()), context)
	assert_true(loaded["ok"])
	assert_false(loaded["read_only"])
	var unknown: Dictionary = flow.load(JSON.stringify({"schema_version": "9.0", "params": {"damage": 1}}), context)
	assert_true(unknown["ok"])
	assert_true(unknown["read_only"])
	var draft: Dictionary = {"schema_version": "9.0", "params": {"damage": 2}}
	var before: Dictionary = draft.duplicate(true)
	var saved: Dictionary = flow.save(draft, _context())
	assert_false(saved["ok"])
	assert_eq(saved["reason"], "unknown_schema_version")
	assert_eq(draft, before)

func test_fingerprint_is_canonical_and_leaf_changes_are_visible() -> void:
	var flow: SaveFlow = _flow()
	var first: String = flow.fingerprint({"b": 2, "a": {"y": true, "x": 1}})
	var reordered: String = flow.fingerprint({"a": {"x": 1, "y": true}, "b": 2})
	var changed: String = flow.fingerprint({"a": {"x": 2, "y": true}, "b": 2})
	assert_eq(first, reordered)
	assert_ne(first, changed)

func test_missing_dependencies_and_context_fail_explicitly() -> void:
	var flow: SaveFlow = SaveFlow.new()
	var bad: Dictionary = flow.configure(null, null, {})
	assert_false(bad["ok"])
	assert_false(flow.save(_cfg(), {})["ok"])
	var configured: SaveFlow = _flow()
	var result: Dictionary = configured.save(_cfg(), {})
	assert_false(result["ok"])
	assert_string_contains(result["reason"], "schema_version_state")

func test_save_does_not_mutate_input_cfg() -> void:
	var writer: Writer = Writer.new()
	var flow: SaveFlow = _flow()
	var cfg: Dictionary = _cfg()
	var before: String = JSON.stringify(cfg)
	assert_true(flow.save(cfg, _context({"etag": "a"}, 1, writer))["ok"])
	assert_eq(JSON.stringify(cfg), before)
