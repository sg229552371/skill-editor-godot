extends GutTest

const Fingerprint = preload("res://skill_core/runtime/preview_fingerprint.gd")


func _configured(notice: String = "not previewed") -> RefCounted:
	var tracker: RefCounted = Fingerprint.new()
	assert_true(tracker.configure({"tick_rate": 60, "notice": notice})["ok"])
	return tracker


func test_missing_tick_rate_and_unconfigured_calls_fail_explicitly():
	var tracker: RefCounted = Fingerprint.new()
	var missing: Dictionary = tracker.configure({"notice": "injected"})
	assert_false(missing["ok"])
	assert_false(String(missing["error"]).is_empty())
	var compute_result: Dictionary = tracker.compute({}, 1)
	assert_false(compute_result["ok"])
	assert_false(String(compute_result["error"]).is_empty())
	var state: Dictionary = tracker.state_for({}, 1)
	assert_false(state["ok"])
	assert_false(String(state["error"]).is_empty())


func test_fingerprint_is_canonical_and_includes_cfg_seed_tick_rate_and_extra():
	var first: RefCounted = _configured()
	var second: RefCounted = _configured()
	var cfg_a: Dictionary = {"z": {"second": 2, "first": [true, "x"]}, "a": 1}
	var cfg_b: Dictionary = {"a": 1, "z": {"first": [true, "x"], "second": 2}}
	var first_result: Dictionary = first.compute(cfg_a, 17, {"mode": "preview"})
	var second_result: Dictionary = second.compute(cfg_b, 17, {"mode": "preview"})
	assert_true(first_result["ok"])
	assert_true(second_result["ok"])
	assert_eq(first_result["fingerprint"], second_result["fingerprint"])

	var changed_leaf: Dictionary = cfg_a.duplicate(true)
	changed_leaf["z"]["first"][1] = "changed"
	assert_true(first.compute(changed_leaf, 17, {"mode": "preview"})["fingerprint"] != first_result["fingerprint"])
	assert_true(first.compute(cfg_a, 18, {"mode": "preview"})["fingerprint"] != first_result["fingerprint"])
	assert_true(first.compute(cfg_a, 17, {"mode": "other"})["fingerprint"] != first_result["fingerprint"])

	var changed_rate: RefCounted = Fingerprint.new()
	assert_true(changed_rate.configure({"tick_rate": 30, "notice": "not previewed"})["ok"])
	assert_true(changed_rate.compute(cfg_a, 17, {"mode": "preview"})["fingerprint"] != first_result["fingerprint"])


func test_compute_does_not_mutate_cfg_or_extra():
	var tracker: RefCounted = _configured()
	var cfg: Dictionary = {"nested": {"items": [1, {"value": "before"}]}}
	var extra: Dictionary = {"options": {"enabled": true}}
	var cfg_before: String = JSON.stringify(cfg)
	var extra_before: String = JSON.stringify(extra)
	var result: Dictionary = tracker.compute(cfg, {"seed": 9}, extra)
	assert_true(result["ok"])
	assert_eq(JSON.stringify(cfg), cfg_before)
	assert_eq(JSON.stringify(extra), extra_before)


func test_save_and_certify_verdicts_are_separate_and_certification_is_fingerprint_bound():
	var tracker: RefCounted = _configured("review required")
	var cfg: Dictionary = {"skill": {"value": 1}}
	var before: Dictionary = tracker.state_for(cfg, 4)
	assert_false(before["match"])
	assert_eq(before["save_verdict"], "allow_with_notice")
	assert_eq(before["certify_verdict"], "block")
	assert_eq(before["notice"], "review required")

	var computed: Dictionary = tracker.compute(cfg, 4)
	tracker.certify(computed["fingerprint"])
	var same: Dictionary = tracker.state_for(cfg, 4)
	assert_true(same["match"])
	assert_eq(same["save_verdict"], "allow")
	assert_eq(same["certify_verdict"], "allow")
	assert_eq(same["certified_fingerprint"], computed["fingerprint"])

	var changed: Dictionary = tracker.state_for({"skill": {"value": 2}}, 4)
	assert_false(changed["match"])
	assert_eq(changed["save_verdict"], "allow_with_notice")
	assert_eq(changed["certify_verdict"], "block")


func test_notice_is_injected_and_can_change_without_being_hardcoded():
	var tracker: RefCounted = Fingerprint.new()
	assert_true(tracker.configure({"tick_rate": 60, "notices": {"unpreviewed": "CUSTOM_NOTICE"}})["ok"])
	var state: Dictionary = tracker.state_for({}, 0)
	assert_eq(state["notice"], "CUSTOM_NOTICE")
	var empty_notice: RefCounted = Fingerprint.new()
	assert_true(empty_notice.configure({"tick_rate": 60})["ok"])
	assert_eq(empty_notice.state_for({}, 0)["notice"], "")
