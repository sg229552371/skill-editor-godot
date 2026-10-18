extends GutTest

const PreviewPanel = preload("res://addons/skill_editor/ui/preview_panel.gd")

func _json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(value is Dictionary, "Fixture metadata must load: " + path)
	return value if value is Dictionary else {}

func _limits() -> Dictionary:
	var params: Dictionary = _json("res://data/params_meta.json")
	var records: Dictionary = _json("res://data/record_fields.json")
	var debug_types: Array = []
	for kind in records["not_subscribable"]:
		if not params["enums"]["event"].has(kind) and not params["enums"]["record"].has(kind):
			debug_types.append(kind)
	assert_eq(debug_types.size(), 1, "Only the registered debug-only type remains")
	return {
		"type_field": "type",
		"sources": ["events", "records", "budget.debug"],
		"column_types": {
			"events": params["enums"]["event"].duplicate(true),
			"settle": params["enums"]["record"].duplicate(true),
			"debug": debug_types,
		},
	}

func _views() -> Dictionary:
	return {
		"events": ["type", "tick", "body_id"],
		"settle": ["type", "tick", "target_id", "parts"],
		"debug": ["type", "kind", "reason"],
	}

func _panel() -> PreviewPanel:
	var panel: PreviewPanel = PreviewPanel.new()
	add_child_autofree(panel)
	return panel

func _mixed(limits: Dictionary) -> Array:
	var columns: Dictionary = limits["column_types"]
	var derive: Dictionary = _json("res://data/derive_meta.json")
	var batch: Array = []
	# Interleave records intentionally; input position is NOT a column identity.
	for index in range(columns["settle"].size()):
		batch.append({"type": columns["settle"][index], "tick": 20 - index,
			"target_id": "target_%d" % index,
			"parts": [{"amount": index + 1, "_note": "not a displayed part field"}]})
		if index < columns["events"].size():
			batch.append({"type": columns["events"][index], "tick": 10 - index,
				"body_id": "body_%d" % index})
		if index < 2:
			batch.append({"type": columns["debug"][0], "kind": derive["records"]["budget"],
				"reason": "debug_%d" % index})
	return batch

func _types(entries: Array) -> Array:
	var result: Array = []
	for entry in entries:
		result.append(entry["type"])
	return result

func test_mixed_records_populate_three_distinct_columns_without_cross_routing() -> void:
	var limits: Dictionary = _limits()
	var panel: PreviewPanel = _panel()
	assert_true(panel.configure(_views(), limits)["ok"])
	var result: Dictionary = panel.ingest({"records": _mixed(limits)})
	assert_true(result["ok"], result["error"])
	var events: Array = panel.get_entries("events")
	var settle: Array = panel.get_entries("settle")
	var debug: Array = panel.get_entries("debug")
	assert_eq(events.size(), 2)
	assert_eq(settle.size(), 4)
	assert_eq(debug.size(), 2)
	assert_eq(_types(events), limits["column_types"]["events"])
	assert_eq(_types(settle), limits["column_types"]["settle"])
	assert_eq(_types(debug), [limits["column_types"]["debug"][0], limits["column_types"]["debug"][0]])
	for entry in settle:
		assert_false(limits["column_types"]["debug"].has(entry["type"]))
		assert_false(str(entry["type"]).begins_with("debug_"))
	for entry in debug:
		assert_false(limits["column_types"]["settle"].has(entry["type"]))
		assert_false(limits["column_types"]["events"].has(entry["type"]))
	for pair in [[events, settle], [events, debug], [settle, debug]]:
		for left in pair[0]:
			for right in pair[1]:
				assert_ne(left, right, "Columns must differ item-by-item, not just by length")
	assert_eq(events[0]["tick"], 10)
	assert_eq(events[1]["tick"], 9, "The panel must not sort by tick")
	assert_eq(settle[0]["target_id"], "target_0")
	assert_eq(settle[3]["target_id"], "target_3")
	assert_eq(debug[0]["reason"], "debug_0")
	assert_eq(debug[1]["reason"], "debug_1")
	assert_eq(panel.get_node("Columns").get_child_count(), 3)
	for column in _views():
		assert_eq(panel.get_node("Columns").get_child(_views().keys().find(column)).get_child_count(), 1 + panel.get_entries(column).size())

func test_comment_keys_and_comment_only_records_never_render() -> void:
	var limits: Dictionary = _limits()
	var panel: PreviewPanel = _panel()
	assert_true(panel.configure(_views(), limits)["ok"])
	var batch: Array = _mixed(limits)
	assert_true(panel.ingest({"records": batch})["ok"])
	var expected: Dictionary = {}
	for column in _views():
		expected[column] = panel.get_entries(column)
	var mapped: Dictionary = {"_note": {"type": "unregistered_comment_kind"}}
	for index in range(batch.size()):
		mapped["row_%d" % index] = batch[index].duplicate(true)
		mapped["row_%d" % index]["_note"] = "row comment"
	assert_true(panel.ingest({"_note": "snapshot comment", "records": mapped})["ok"])
	for column in _views():
		assert_gt(expected[column].size(), 0)
		assert_eq(panel.get_entries(column), expected[column])
	var annotated: Array = batch.duplicate(true)
	annotated.insert(0, {"_note": "array comment, not an unknown record"})
	annotated.append({"_source": "more metadata"})
	assert_true(panel.ingest({"records": annotated})["ok"])
	for column in _views():
		assert_eq(panel.get_entries(column), expected[column])
		for entry in panel.get_entries(column):
			assert_false(entry.has("_note"))
	for entry in panel.get_entries("settle"):
		assert_eq(entry["parts"].size(), 1)
		assert_false(entry["parts"][0].has("_note"))

func test_unknown_record_kind_fails_names_kind_and_clears_every_column() -> void:
	var limits: Dictionary = _limits()
	var panel: PreviewPanel = _panel()
	assert_true(panel.configure(_views(), limits)["ok"])
	# Unknown types in ANY registered stream must fail, even after valid rows.
	for source in limits["sources"]:
		assert_true(panel.ingest({"records": _mixed(limits)})["ok"])
		for column in _views():
			assert_gt(panel.get_entries(column).size(), 0)
		var bad: Dictionary = {"type": "not_registered_T051"}
		var snapshot: Dictionary = {"records": _mixed(limits)}
		if source == "budget.debug":
			snapshot["budget"] = {"debug": [bad]}
		elif source == "records":
			snapshot["records"].append(bad)
		else:
			snapshot[source] = [bad]
		var result: Dictionary = panel.ingest(snapshot)
		assert_false(result["ok"])
		assert_string_contains(result["error"], "not_registered_T051")
		assert_string_contains(result["error"], source)
		assert_string_contains(panel.get_node("Status").text, "not_registered_T051")
		for column in _views():
			assert_eq(panel.get_entries(column), [])
			assert_eq(result["entries"][column], [])

func test_snapshot_and_returned_entries_are_deeply_detached() -> void:
	var limits: Dictionary = _limits()
	var views: Dictionary = _views()
	var panel: PreviewPanel = _panel()
	assert_true(panel.configure(views, limits)["ok"])
	# Injection is detached too, not just each frame.
	views["settle"].clear()
	limits["column_types"]["settle"].clear()
	limits["sources"].clear()
	var snapshot: Dictionary = {"records": _mixed(_limits()), "_note": "untouched"}
	var before: Dictionary = snapshot.duplicate(true)
	var result: Dictionary = panel.ingest(snapshot)
	assert_true(result["ok"], result["error"])
	assert_eq(JSON.stringify(snapshot), JSON.stringify(before))
	var expected: Array = panel.get_entries("settle")
	assert_eq(expected.size(), 4)
	result["entries"]["settle"][0]["parts"][0]["amount"] = 999
	result["entries"]["events"].clear()
	assert_eq(panel.get_entries("settle"), expected)
	assert_eq(panel.get_entries("events").size(), 2)
	var returned: Array = panel.get_entries("settle")
	returned[0]["parts"][0]["amount"] = 888
	returned.append({"type": "fake"})
	assert_eq(panel.get_entries("settle"), expected)
	snapshot["records"][0]["parts"][0]["amount"] = 777
	assert_eq(panel.get_entries("settle"), expected)
	assert_eq(before["records"][0]["parts"][0]["amount"], 1)

func test_changing_view_fields_changes_exact_field_sets_and_visible_text() -> void:
	var limits: Dictionary = _limits()
	var panel: PreviewPanel = _panel()
	assert_true(panel.configure(_views(), limits)["ok"])
	var snapshot: Dictionary = {"records": _mixed(limits)}
	assert_true(panel.ingest(snapshot)["ok"])
	var old_settle: Array = panel.get_entries("settle")
	assert_eq(old_settle[0].keys(), ["type", "tick", "target_id", "parts"])
	var views: Dictionary = {
		"events": ["body_id"], "settle": ["target_id"], "debug": ["reason"],
	}
	assert_true(panel.configure(views, limits)["ok"])
	assert_true(panel.ingest(snapshot)["ok"])
	for column in views:
		var entries: Array = panel.get_entries(column)
		assert_gt(entries.size(), 0)
		for entry in entries:
			assert_eq(entry.keys(), views[column])
			assert_false(entry.has("type"))
	assert_eq(panel.get_entries("events"), [{"body_id": "body_0"}, {"body_id": "body_1"}])
	assert_eq(panel.get_entries("debug"), [{"reason": "debug_0"}, {"reason": "debug_1"}])
	var settle_rows: Node = panel.get_node("Columns").get_child(1)
	assert_eq(settle_rows.get_child(1).text, "target_id: target_0")
	assert_ne(panel.get_entries("settle"), old_settle)

func test_runner_shaped_streams_replace_previous_snapshot_and_clear_keeps_configuration() -> void:
	var limits: Dictionary = _limits()
	var panel: PreviewPanel = _panel()
	assert_true(panel.configure(_views(), limits)["ok"])
	var batch: Array = _mixed(limits)
	var snapshot: Dictionary = {"clock": {"tick": 20}, "entities": {}, "events": [],
		"records": [], "budget": {"debug": [], "settlements": []},
		"derive": {"records": {"_note": "not a second formal stream"}}}
	for record in batch:
		if limits["column_types"]["events"].has(record["type"]):
			snapshot["events"].append(record)
		elif limits["column_types"]["settle"].has(record["type"]):
			snapshot["records"].append(record)
			# Runner duplicates settlement history in budget; do not double count it.
			snapshot["budget"]["settlements"].append(record.duplicate(true))
		else:
			snapshot["budget"]["debug"].append(record)
	var first: Dictionary = panel.ingest(snapshot)
	assert_true(first["ok"])
	assert_eq(first["entries"]["events"].size(), 2)
	assert_eq(first["entries"]["settle"].size(), 4)
	assert_eq(first["entries"]["debug"].size(), 2)
	assert_eq(panel.ingest(snapshot)["entries"], first["entries"], "Repeated complete snapshots must not append history")
	panel.clear()
	for column in _views():
		assert_eq(panel.get_entries(column), [])
	assert_eq(panel.get_entries("unknown_column"), [])
	assert_eq(panel.ingest(snapshot)["entries"], first["entries"])
	assert_true(panel.ingest({"events": [], "records": [], "budget": {}})["ok"])
	for column in _views():
		assert_eq(panel.get_entries(column), [])

func test_missing_and_overlapping_configuration_fail_without_old_results() -> void:
	var panel: PreviewPanel = _panel()
	assert_false(panel.ingest({})["ok"])
	assert_false(panel.configure(_views(), {})["ok"])
	var limits: Dictionary = _limits()
	assert_true(panel.configure(_views(), limits)["ok"])
	assert_true(panel.ingest({"records": _mixed(limits)})["ok"])
	var duplicate: Dictionary = limits.duplicate(true)
	duplicate["column_types"]["settle"].append(limits["column_types"]["debug"][0])
	var rejected: Dictionary = panel.configure(_views(), duplicate)
	assert_false(rejected["ok"])
	assert_string_contains(rejected["error"], limits["column_types"]["debug"][0])
	assert_false(panel.ingest({"records": _mixed(limits)})["ok"])
	for column in _views():
		assert_eq(panel.get_entries(column), [])
	var missing: Dictionary = limits.duplicate(true)
	missing["column_types"].erase("settle")
	assert_false(panel.configure(_views(), missing)["ok"])
	assert_false(panel.configure({"_note": "not a view"}, limits)["ok"])
	var overlapping: Dictionary = limits.duplicate(true)
	overlapping["sources"] = ["budget", "budget.debug"]
	assert_false(panel.configure(_views(), overlapping)["ok"])
	var empty_fields: Dictionary = _views()
	empty_fields["events"] = []
	assert_false(panel.configure(empty_fields, limits)["ok"])

func test_columns_sources_and_type_field_follow_injection_not_literal_names() -> void:
	var original: Dictionary = _limits()
	var custom: Dictionary = {
		"type_field": "record_tag", "sources": ["track.items"],
		"column_types": {"轨迹": original["column_types"]["events"],
			"结果": original["column_types"]["settle"], "诊断": original["column_types"]["debug"],
			"_note": "not a column"},
	}
	var views: Dictionary = {"轨迹": ["record_tag", "body_id"],
		"结果": ["record_tag", "target_id"], "诊断": ["record_tag", "reason"],
		"_note": "not a view"}
	var batch: Array = _mixed(original)
	for record in batch:
		record["record_tag"] = record["type"]
		record.erase("type")
	var panel: PreviewPanel = _panel()
	assert_true(panel.configure(views, custom)["ok"])
	assert_true(panel.ingest({"track": {"items": batch}})["ok"])
	assert_eq(panel.get_entries("轨迹").size(), 2)
	assert_eq(panel.get_entries("结果").size(), 4)
	assert_eq(panel.get_entries("诊断").size(), 2)
	assert_eq(panel.get_entries("events"), [])
	assert_eq(panel.get_node("Columns").get_child_count(), 3)
	for column in ["轨迹", "结果", "诊断"]:
		for entry in panel.get_entries(column):
			assert_eq(entry.keys(), views[column])

func test_invalid_records_fail_and_color_null_fields_render_without_string_constructor() -> void:
	var limits: Dictionary = _limits()
	var panel: PreviewPanel = _panel()
	assert_true(panel.configure(_views(), limits)["ok"])
	for invalid in [{}, {"type": null}, {"type": []}, {"type": 1}, "not a record"]:
		var result: Dictionary = panel.ingest({"records": [invalid]})
		assert_false(result["ok"])
		assert_string_contains(result["error"], "records[0]")
	assert_false(panel.ingest({"records": "not a stream"})["ok"])
	assert_false(panel.ingest({"budget": []})["ok"])
	var views: Dictionary = _views()
	views["events"] = ["type", "tint", "optional", "absent"]
	assert_true(panel.configure(views, limits)["ok"])
	var event: Dictionary = {"type": limits["column_types"]["events"][0],
		"tint": Color(0.2, 0.4, 0.6, 1), "optional": null}
	var result: Dictionary = panel.ingest({"events": [event]})
	assert_true(result["ok"])
	assert_eq(panel.get_entries("events").size(), 1)
	assert_eq(panel.get_entries("events")[0]["tint"], event["tint"])
	assert_null(panel.get_entries("events")[0]["optional"])
	assert_null(panel.get_entries("events")[0]["absent"])
	var row: Label = panel.get_node("Columns").get_child(0).get_child(1)
	assert_string_contains(row.text, "tint: " + str(event["tint"]))
	assert_string_contains(row.text, "optional: " + str(null))
