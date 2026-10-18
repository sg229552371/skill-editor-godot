extends GutTest

const PresentationBind = preload("res://skill_core/runtime/presentation_bind.gd")

# Runtime adapter metadata is injected; these additions are absent from the
# deployed presentation_meta.json. No production file is changed by this suite.
func _metadata() -> Dictionary:
	var sections: Array = ["fx", "sfx", "anim", "trail", "camera", "damage_number", "status_icon"]
	var routes: Dictionary = {"_note": "comment, not a section"}
	for section in sections:
		routes[section] = {"hit": "on_hit", "hit_settled": "on_settled", "evaded_all": "on_evaded"}
	return {
		"required_sections": sections,
		"event_bindings": routes,
		"forbidden_logic_keys": ["damage", "hit_delta", "next_tick", "end_reason", "custom_logic_write"]
	}


func _bindings() -> Dictionary:
	return {
		"fx": {"on_hit": [{"resource": "impact_a"}], "on_settled": [{"resource": "settled_a"}], "on_evaded": [{"resource": "evade_a"}]},
		"sfx": {}, "anim": {}, "trail": {}, "camera": {}, "damage_number": {}, "status_icon": {}
	}


func test_logic_events_succeed_and_animation_callbacks_fail_in_pairs() -> void:
	var binder: PresentationBind = PresentationBind.new()
	assert_true(binder.configure(_bindings(), _metadata())["ok"])
	var pairs: Array = [["hit", "anim_finished", "impact_a"], ["hit_settled", "animation_callback", "settled_a"], ["evaded_all", "on_anim_end", "evade_a"]]
	for pair in pairs:
		var good: Dictionary = binder.on_event(pair[0], {"target_id": "target_a"})
		assert_true(good["ok"], str(good))
		assert_eq(good["cues"].size(), 1)
		assert_eq(good["cues"][0]["binding"][0]["resource"], pair[2])
		var bad: Dictionary = binder.on_event(pair[1], {})
		assert_false(bad["ok"])
		assert_string_contains(bad["error"], pair[1])
		assert_eq(bad["cues"], [])


func _forbidden_paths(value: Variant, forbidden: Array, path: String = "result") -> Array:
	var found: Array = []
	if value is Dictionary:
		for key in value:
			var child: String = path + "." + str(key)
			if forbidden.has(key):
				found.append(child)
			found.append_array(_forbidden_paths(value[key], forbidden, child))
	elif value is Array:
		for index in range(value.size()):
			found.append_array(_forbidden_paths(value[index], forbidden, path + "[" + str(index) + "]"))
	return found


func test_events_are_read_only_and_results_have_no_injected_forbidden_keys() -> void:
	var binder: PresentationBind = PresentationBind.new()
	var bindings: Dictionary = _bindings()
	var meta: Dictionary = _metadata()
	var payload: Dictionary = {"damage": 12, "hit_delta": 1, "next_tick": 20, "end_reason": "hit_end", "nested": [{"custom_logic_write": 9}]}
	var before_bindings: Dictionary = bindings.duplicate(true)
	var before_payload: Dictionary = payload.duplicate(true)
	var before_meta: Dictionary = meta.duplicate(true)
	assert_true(binder.configure(bindings, meta)["ok"])
	# Prove the recursive assertion can detect every injected key, even nested.
	assert_eq(_forbidden_paths(payload, meta["forbidden_logic_keys"]).size(), 5)
	for event in ["hit", "hit_settled", "evaded_all", "anim_finished"]:
		var result: Dictionary = binder.on_event(event, payload)
		assert_eq(_forbidden_paths(result, meta["forbidden_logic_keys"]), [])
		if event != "anim_finished":
			assert_true(result["ok"])
			assert_eq(result["cues"].size(), 1)
		else:
			assert_false(result["ok"])
		assert_eq(JSON.stringify(bindings), JSON.stringify(before_bindings))
		assert_eq(JSON.stringify(payload), JSON.stringify(before_payload))
		assert_eq(JSON.stringify(meta), JSON.stringify(before_meta))
	var first: Dictionary = binder.on_event("hit", payload)
	first["cues"][0]["binding"][0]["resource"] = "caller_mutated_result"
	bindings["fx"]["on_hit"][0]["resource"] = "caller_mutated_input"
	meta["event_bindings"]["fx"]["hit"] = "on_settled"
	assert_eq(binder.on_event("hit", payload)["cues"][0]["binding"][0]["resource"], "impact_a")


func test_nested_forbidden_binding_key_is_rejected_instead_of_echoed() -> void:
	var meta: Dictionary = _metadata()
	for key in meta["forbidden_logic_keys"]:
		var binder: PresentationBind = PresentationBind.new()
		var bindings: Dictionary = _bindings()
		bindings["fx"]["on_hit"][0][key] = 42
		var result: Dictionary = binder.configure(bindings, meta)
		assert_false(result["ok"])
		assert_string_contains(result["error"], "presentation.fx.on_hit[0]." + key)
		assert_eq(binder.alignments(), [])
		assert_false(binder.on_event("hit", {})["ok"])


func test_complete_alignment_normalizes_json_integers_and_returns_copies() -> void:
	var binder: PresentationBind = PresentationBind.new()
	var bindings: Dictionary = _bindings()
	var json_pair: Variant = JSON.parse_string('{"shot_tick":30.0,"frame":12.0}')
	bindings["anim"] = {"alignments": [{"shot_tick": 0, "frame": 0}, json_pair], "on_hit": {"clip": "impact"}}
	var before: Dictionary = bindings.duplicate(true)
	assert_true(binder.configure(bindings, _metadata())["ok"])
	var aligned: Array = binder.alignments()
	assert_eq(aligned.size(), 2)
	assert_eq(aligned[0], {"shot_tick": 0, "frame": 0})
	assert_eq(aligned[1], {"shot_tick": 30, "frame": 12})
	assert_true(aligned[1]["shot_tick"] is int)
	assert_true(aligned[1]["frame"] is int)
	assert_eq(JSON.stringify(bindings), JSON.stringify(before))
	aligned[1]["shot_tick"] = 99
	bindings["anim"]["alignments"][0]["frame"] = 99
	assert_eq(binder.alignments()[1]["shot_tick"], 30)
	assert_eq(binder.alignments()[0]["frame"], 0)


func test_each_missing_alignment_leaf_names_actual_index_and_clears_previous_state() -> void:
	for field in ["shot_tick", "frame"]:
		var binder: PresentationBind = PresentationBind.new()
		var bindings: Dictionary = _bindings()
		bindings["anim"] = {"alignments": [{"shot_tick": 0, "frame": 0}, {"shot_tick": 30, "frame": 12}]}
		assert_true(binder.configure(bindings, _metadata())["ok"])
		assert_eq(binder.alignments().size(), 2)
		bindings["anim"]["alignments"][1].erase(field)
		var result: Dictionary = binder.configure(bindings, _metadata())
		assert_false(result["ok"])
		assert_string_contains(result["error"], "presentation.anim.alignments[1]." + field)
		assert_eq(binder.alignments(), [])
		assert_false(binder.get_error().is_empty())
		assert_false(binder.on_event("hit", {})["ok"])


func test_alignment_requires_integral_numbers_not_seconds_or_coercible_values() -> void:
	for field in ["shot_tick", "frame"]:
		for invalid in [0.5, "30", null, true, [], {}, INF, NAN]:
			var binder: PresentationBind = PresentationBind.new()
			var bindings: Dictionary = _bindings()
			var pair: Dictionary = {"shot_tick": 30, "frame": 12}
			pair[field] = invalid
			bindings["anim"] = {"alignments": [pair]}
			var result: Dictionary = binder.configure(bindings, _metadata())
			assert_false(result["ok"], str(invalid))
			assert_string_contains(result["error"], "presentation.anim.alignments[0]." + field)
			assert_eq(binder.alignments(), [])


func test_empty_anim_is_unbound_but_nonempty_anim_requires_alignment_array() -> void:
	var binder: PresentationBind = PresentationBind.new()
	assert_true(binder.configure(_bindings(), _metadata())["ok"])
	assert_eq(binder.alignments(), [])
	assert_eq(binder.on_event("hit", {})["cues"].size(), 1)
	for invalid_anim in [{"on_hit": {"clip": "impact"}}, {"alignments": []}, {"alignments": null}, {"alignments": [null]}]:
		var bindings: Dictionary = _bindings()
		bindings["anim"] = invalid_anim
		var result: Dictionary = binder.configure(bindings, _metadata())
		assert_false(result["ok"])
		assert_string_contains(result["error"], "presentation.anim.alignments")
		assert_eq(binder.alignments(), [])


func test_all_seven_sections_follow_injected_routes_and_rebinding_changes_cues() -> void:
	var binder: PresentationBind = PresentationBind.new()
	var meta: Dictionary = _metadata()
	var sections: Array = meta["required_sections"]
	assert_eq(sections.size(), 7)
	var bindings: Dictionary = {}
	for section in sections:
		bindings[section] = {"on_hit": {"resource": section + "_first"}, "alternate": {"resource": section + "_second"}}
	bindings["anim"]["alignments"] = [{"shot_tick": 30, "frame": 12}]
	assert_true(binder.configure(bindings, meta)["ok"])
	var first: Dictionary = binder.on_event("hit", {})
	assert_true(first["ok"])
	assert_eq(first["cues"].size(), 7)
	for index in range(sections.size()):
		var section: String = sections[index]
		assert_eq(first["cues"][index], {"section": section, "event": "hit", "binding": {"resource": section + "_first"}})
		bindings[section]["on_hit"]["resource"] = section + "_rebound"
	assert_true(binder.configure(bindings, meta)["ok"])
	var rebound: Dictionary = binder.on_event("hit", {})
	assert_true(rebound["ok"])
	assert_eq(rebound["cues"].size(), 7)
	for index in range(sections.size()):
		assert_eq(rebound["cues"][index]["binding"]["resource"], sections[index] + "_rebound")
		meta["event_bindings"][sections[index]]["hit"] = "alternate"
	assert_true(binder.configure(bindings, meta)["ok"])
	var remapped: Dictionary = binder.on_event("hit", {})
	assert_true(remapped["ok"])
	assert_eq(remapped["cues"].size(), 7)
	for index in range(sections.size()):
		assert_eq(remapped["cues"][index]["binding"]["resource"], sections[index] + "_second")


func test_whole_section_route_and_empty_sections_do_not_invent_defaults() -> void:
	var binder: PresentationBind = PresentationBind.new()
	var meta: Dictionary = _metadata()
	var bindings: Dictionary = _bindings()
	meta["event_bindings"]["camera"]["hit"] = ""
	bindings["camera"] = {"trigger": "hit", "intensity": 0.25}
	assert_true(binder.configure(bindings, meta)["ok"])
	var result: Dictionary = binder.on_event("hit", {})
	assert_true(result["ok"])
	assert_eq(result["cues"].size(), 2)
	assert_eq(result["cues"][1], {"section": "camera", "event": "hit", "binding": bindings["camera"]})
	bindings["fx"] = {}
	bindings["camera"] = {}
	assert_true(binder.configure(bindings, meta)["ok"])
	assert_eq(binder.on_event("hit", {})["cues"], [])
	assert_eq(binder.alignments(), [])


func test_unconfigured_and_failed_reconfigure_are_explicit_and_recoverable() -> void:
	var binder: PresentationBind = PresentationBind.new()
	var initial: Dictionary = binder.on_event("hit", {})
	assert_false(initial["ok"])
	assert_string_contains(initial["error"], "hit")
	assert_eq(initial["cues"], [])
	assert_false(binder.get_error().is_empty())
	var valid: Dictionary = _bindings()
	valid["anim"] = {"alignments": [{"shot_tick": 0, "frame": 0}]}
	assert_true(binder.configure(valid, _metadata())["ok"])
	assert_eq(binder.alignments().size(), 1)
	var invalid: Dictionary = _bindings()
	invalid["anim"] = {"alignments": [{"frame": 0}]}
	assert_false(binder.configure(invalid, _metadata())["ok"])
	assert_eq(binder.alignments(), [])
	assert_false(binder.get_error().is_empty())
	assert_false(binder.on_event("hit", {})["ok"])
	assert_true(binder.configure(_bindings(), _metadata())["ok"])
	assert_eq(binder.get_error(), "")
	assert_eq(binder.on_event("hit", {})["cues"].size(), 1)


func test_missing_runtime_metadata_fails_explicitly_and_cannot_authorize_callbacks() -> void:
	for missing in ["forbidden_logic_keys", "event_bindings", "required_sections"]:
		var binder: PresentationBind = PresentationBind.new()
		var meta: Dictionary = _metadata()
		meta.erase(missing)
		var result: Dictionary = binder.configure(_bindings(), meta)
		assert_false(result["ok"])
		assert_string_contains(result["error"], "presentation_meta." + missing)
		assert_eq(binder.alignments(), [])
		assert_false(binder.get_error().is_empty())
	var binder: PresentationBind = PresentationBind.new()
	var meta: Dictionary = _metadata()
	meta["event_bindings"]["fx"]["anim_finished"] = "on_hit"
	var result: Dictionary = binder.configure(_bindings(), meta)
	assert_false(result["ok"])
	assert_string_contains(result["error"], "anim_finished")
	for event in ["vanish", "debug_record", "cast_started", "damage_taken", "unknown_event"]:
		assert_true(binder.configure(_bindings(), _metadata())["ok"])
		var rejected: Dictionary = binder.on_event(event, {})
		assert_false(rejected["ok"])
		assert_string_contains(rejected["error"], event)
		assert_eq(rejected["cues"], [])


func test_metadata_comments_are_ignored_and_empty_route_means_no_subscription() -> void:
	var binder: PresentationBind = PresentationBind.new()
	var meta: Dictionary = _metadata()
	meta["event_bindings"]["fx"]["_note"] = "not a logical event or cue slot"
	assert_true(binder.configure(_bindings(), meta)["ok"])
	var subscribed: Dictionary = binder.on_event("hit", {})
	assert_true(subscribed["ok"])
	assert_eq(subscribed["cues"].size(), 1)
	meta["event_bindings"]["fx"] = {}
	assert_true(binder.configure(_bindings(), meta)["ok"])
	var unsubscribed: Dictionary = binder.on_event("hit", {})
	assert_true(unsubscribed["ok"])
	assert_eq(unsubscribed["cues"], [])


