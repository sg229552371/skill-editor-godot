extends GutTest

const Query = preload("res://skill_core/resolve/field_query.gd")

func _card() -> Dictionary:
	return {
		"author_params": ["params.tune"],
		"locked_params": {"identity": "fixture contract"},
		"relic_params": {"behavior": "fixture permission"},
		"default_cfg": {"params": {"reserve": 7}},
	}

func test_unconfigured_and_unknown_fail_closed() -> void:
	var facade = Query.new()
	var result: Dictionary = facade.query("params.tune")
	assert_false(result.ok)
	assert_false(result.writable)
	assert_eq(result.source, "unknown")
	assert_ne(result.error, "")
	assert_eq(facade.query_all(), [])
	assert_ne(facade.last_error, "")
	assert_true(facade.configure(_card()).ok)
	result = facade.query("params.absent")
	assert_false(result.ok)
	assert_false(result.locked)
	assert_false(result.open)
	assert_false(result.writable)
	assert_eq(result.source, "unknown")
	assert_eq(result.path, "params.absent")
	assert_ne(result.error, "")

func test_locked_path_uses_catalog_reason() -> void:
	var facade = Query.new()
	var card: Dictionary = _card()
	assert_true(facade.configure(card).ok)
	var result: Dictionary = facade.query("identity")
	assert_true(result.ok)
	assert_true(result.locked)
	assert_false(result.open)
	assert_false(result.writable)
	assert_eq(result.source, "locked")
	assert_ne(result.lock_reason, "")
	assert_eq(result.lock_reason, card.locked_params["identity"])

func test_author_path_is_open_and_writable() -> void:
	var facade = Query.new()
	assert_true(facade.configure(_card()).ok)
	var result: Dictionary = facade.query("params.tune")
	assert_true(result.ok)
	assert_false(result.locked)
	assert_eq(result.lock_reason, "")
	assert_true(result.open)
	assert_true(result.writable)
	assert_eq(result.source, "author_params")

func test_unopened_relic_path_is_not_author_locked() -> void:
	var facade = Query.new()
	assert_true(facade.configure(_card()).ok)
	var result: Dictionary = facade.query("behavior")
	assert_true(result.ok)
	assert_false(result.locked)
	assert_false(result.open)
	assert_false(result.writable)
	assert_eq(result.lock_reason, "")
	assert_eq(result.source, "relic_params")

func test_default_only_path_is_readonly_not_locked() -> void:
	var facade = Query.new()
	assert_true(facade.configure(_card()).ok)
	var result: Dictionary = facade.query("params.reserve")
	assert_true(result.ok)
	assert_eq(result.source, "default_cfg")
	assert_false(result.locked)
	assert_false(result.open)
	assert_false(result.writable)

func test_lock_wins_over_open_and_default_does_not_hide_author_source() -> void:
	var facade = Query.new()
	var card: Dictionary = _card()
	card["author_params"] = ["params.tune", "identity"]
	card["default_cfg"] = {"params": {"tune": 1}, "identity": "seed"}
	assert_true(facade.configure(card).ok)
	var locked: Dictionary = facade.query("identity")
	assert_true(locked.locked)
	assert_false(locked.open)
	assert_false(locked.writable)
	assert_eq(locked.source, "locked")
	assert_eq(facade.query("params.tune").source, "author_params")

func test_material_template_paths_match_numeric_selectors_not_neighbor_fields() -> void:
	var card: Dictionary = _card()
	card["author_params"] = ["templates[i].amount", "templates[i].parts[i].factor"]
	var facade = Query.new()
	assert_true(facade.configure(card).ok)
	var selectors: Array = ["templates[0].amount", "templates[3].parts[2].factor"]
	assert_eq(selectors.size(), 2)
	for path in selectors:
		var result: Dictionary = facade.query(path)
		assert_true(result.ok, path)
		assert_true(result.writable, path)
		assert_eq(result.source, "author_params")
	assert_false(facade.query("templates[0].amount_extra").ok)
	assert_false(facade.query("templates[3].parts[2].other").ok)
	assert_true(facade.query("templates[i].amount").writable)
	assert_true(facade.query("templates[i].parts[i].factor").writable)

func test_default_array_addresses_keep_indices_distinct() -> void:
	var card: Dictionary = _card()
	card["default_cfg"] = {"arrays": [{"path": "one"}, {"path": "two"}]}
	var facade = Query.new()
	assert_true(facade.configure(card).ok)
	var selectors: Array = ["arrays[0].path", "arrays[1].path"]
	assert_eq(selectors.size(), 2)
	for path in selectors:
		var result: Dictionary = facade.query(path)
		assert_true(result.ok, path)
		assert_eq(result.source, "default_cfg")
		assert_false(result.open)
		assert_false(result.locked)
	assert_false(facade.query("arrays[2].path").ok)
	assert_false(facade.query("arrays[i].path").ok)

func test_author_scene_addresses_resolve_only_explicit_wrappers() -> void:
	var card: Dictionary = _card()
	card["author_params"] = ["x", "branch.y"]
	var facade = Query.new()
	assert_true(facade.configure(card).ok)
	var selectors: Array = ["bricks[2].author_params.x", "bricks[0].author_params.branch.y"]
	assert_eq(selectors.size(), 2)
	for path in selectors:
		var result: Dictionary = facade.query(path)
		assert_true(result.ok, path)
		assert_eq(result.path, path)
		assert_true(result.writable)
		assert_eq(result.source, "author_params")
	assert_false(facade.query("other.x").ok)
	assert_false(facade.query("bricks[-1].author_params.x").ok)
	assert_false(facade.query("bricks[2].unregistered.x").ok)

func test_author_keys_reject_indices_even_when_material_templates_are_valid() -> void:
	var facade = Query.new()
	var bad_keys: Array = ["templates[i]", "templates[0]"]
	assert_eq(bad_keys.size(), 2)
	for key in bad_keys:
		var card: Dictionary = _card()
		card["author_params"] = ["templates[i].amount", "templates[i].parts[i].factor"]
		card["default_cfg"] = {key: {"amount": 1}}
		var setup: Dictionary = facade.configure(card)
		assert_false(setup.ok, key)
		assert_ne(setup.error, "")
		assert_false(facade.query("templates[0].amount").ok)
	# Concrete selectors are accepted only in queries/generated tree addresses.
	var card: Dictionary = _card()
	card["author_params"] = ["templates[0].amount"]
	assert_false(facade.configure(card).ok)

func test_parent_locks_constrain_known_children_without_registering_unknowns() -> void:
	var card: Dictionary = _card()
	card["author_params"] = ["branch", "templates[i].amount"]
	card["locked_params"] = {"branch": "fixture branch reason", "templates": "fixture array reason"}
	card["default_cfg"] = {"branch": {"value": 0}, "branch_extra": {"value": 1}}
	var facade = Query.new()
	assert_true(facade.configure(card).ok)
	var result: Dictionary = facade.query("branch.value")
	assert_true(result.ok)
	assert_true(result.locked)
	assert_false(result.writable)
	assert_eq(result.lock_reason, card.locked_params["branch"])
	result = facade.query("templates[4].amount")
	assert_true(result.ok)
	assert_true(result.locked)
	assert_false(result.open)
	assert_eq(result.lock_reason, card.locked_params["templates"])
	assert_false(facade.query("branch_extra.value").locked)
	assert_false(facade.query("branch.missing").ok)

func test_query_all_keeps_first_declaration_order_and_returns_fresh_records() -> void:
	var card: Dictionary = {
		"default_cfg": {"params": {"third": 0, "first": 1}},
		"author_params": ["params.first", "second"],
		"locked_params": {"fourth": "fixture reason"},
		"relic_params": {"fifth": "fixture permission"},
	}
	var facade = Query.new()
	assert_true(facade.configure(card).ok)
	var rows: Array = facade.query_all()
	assert_eq(rows.size(), 5)
	var paths: Array = []
	for row in rows:
		assert_true(row.ok)
		paths.append(row.path)
	assert_eq(paths, ["params.third", "params.first", "second", "fourth", "fifth"])
	rows[1]["writable"] = false
	rows[3]["lock_reason"] = "external mutation"
	rows.clear()
	assert_true(facade.query("params.first").writable)
	assert_eq(facade.query("fourth").lock_reason, card.locked_params["fourth"])
	assert_eq(facade.query_all().size(), 5)
	var single: Dictionary = facade.query("fourth")
	single["locked"] = false
	assert_true(facade.query("fourth").locked)

func test_inputs_unchanged_and_mutations_after_configure_are_isolated() -> void:
	var card: Dictionary = _card()
	var policy: Dictionary = _policy()
	var before_card: String = JSON.stringify(card.duplicate(true))
	var before_policy: String = JSON.stringify(policy.duplicate(true))
	var facade = Query.new()
	assert_true(facade.configure(card, policy).ok)
	assert_eq(facade.query_all().size(), 4)
	assert_true(facade.query("params.tune").writable)
	assert_eq(JSON.stringify(card), before_card)
	assert_eq(JSON.stringify(policy), before_policy)
	card["author_params"].clear()
	card["locked_params"]["identity"] = "external change"
	card["default_cfg"]["params"]["reserve"] = {"new_leaf": 0}
	policy.clear()
	assert_true(facade.query("params.tune").writable)
	assert_eq(facade.query("identity").lock_reason, "fixture contract")
	assert_true(facade.query("params.reserve").ok)
	assert_false(facade.query("params.reserve.new_leaf").ok)

func test_reconfigure_changes_facts_from_tables_and_failure_discards_old_state() -> void:
	var facade = Query.new()
	assert_true(facade.configure(_card(), _policy()).ok)
	assert_true(facade.query("params.tune").writable)
	var replacement: Dictionary = {
		"author_params": ["identity"],
		"locked_params": {"params.tune": "replacement material reason"},
		"relic_params": {}, "default_cfg": {},
	}
	var policy: Dictionary = _policy()
	policy["categories"]["fixture_category"]["allowed"] = []
	assert_true(facade.configure(replacement, policy).ok)
	assert_false(facade.query("params.tune").writable)
	assert_eq(facade.query("params.tune").lock_reason, replacement.locked_params["params.tune"])
	assert_true(facade.query("identity").writable)
	assert_false(facade.query("behavior").ok)
	assert_false(facade.configure({}).ok)
	assert_eq(facade.query_all(), [])
	assert_ne(facade.last_error, "")
	assert_false(facade.query("identity").ok)

func test_item_policy_does_not_grant_or_remove_author_permissions() -> void:
	var facade = Query.new()
	var policy: Dictionary = _policy()
	assert_true(facade.configure(_card(), policy).ok)
	var before: Array = facade.query_all()
	policy["categories"]["fixture_category"]["allowed"] = []
	policy["categories"]["fixture_category"]["denied"] = policy["permissions"].duplicate(true)
	assert_true(facade.configure(_card(), policy).ok)
	assert_eq(facade.query_all(), before)
	assert_true(facade.query("params.tune").writable)
	assert_false(facade.query("behavior").locked)
	assert_false(facade.configure(_card(), []).ok)

func test_missing_or_invalid_lock_reason_fails_without_fabricated_fallback() -> void:
	var facade = Query.new()
	var invalid: Array = ["", " ", null, [], 1]
	assert_eq(invalid.size(), 5)
	for value in invalid:
		var card: Dictionary = _card()
		card["locked_params"]["identity"] = value
		var setup: Dictionary = facade.configure(card, _policy())
		assert_false(setup.ok)
		assert_ne(setup.error, "")
		assert_false(facade.query("identity").ok)
		assert_eq(facade.query_all(), [])

func test_deployed_catalog_gap_and_real_item_policy_are_not_silently_promoted() -> void:
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/bricks/brick_catalog.json"))
	var policy: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/item_permission_policy.json"))
	assert_true(catalog is Array)
	assert_true(policy is Dictionary)
	if not catalog is Array or not policy is Dictionary:
		return
	assert_gt(catalog.size(), 0)
	if catalog.is_empty():
		return
	var facade = Query.new()
	# Identity-only cards must fail until the reviewer deploys full card fields.
	assert_false(facade.configure(catalog[0], policy).ok)
	assert_false(facade.query("params.tune").ok)
	assert_true(facade.configure(_card(), policy).ok)
	assert_true(facade.query("params.tune").writable)
	assert_eq(facade.query("identity").lock_reason, "fixture contract")

func test_dictionary_author_declarations_and_empty_containers_are_known() -> void:
	var card: Dictionary = _card()
	card["author_params"] = {"params.editable": "fixture semantic note"}
	card["default_cfg"] = {"params": {"empty_array": [], "empty_object": {}, "nil_value": null}}
	var facade = Query.new()
	assert_true(facade.configure(card).ok)
	assert_true(facade.query("editable").writable)
	var selectors: Array = ["params.empty_array", "params.empty_object", "params.nil_value"]
	assert_eq(selectors.size(), 3)
	for path in selectors:
		var result: Dictionary = facade.query(path)
		assert_true(result.ok)
		assert_eq(result.source, "default_cfg")
		assert_false(result.writable)
		assert_false(result.locked)
	assert_false(facade.query("params.empty_array[0]").ok)
	assert_false(facade.query("params.empty_object.missing").ok)

func test_malformed_paths_and_empty_author_list_never_enable_arbitrary_writes() -> void:
	var card: Dictionary = _card()
	card["author_params"] = []
	var facade = Query.new()
	assert_true(facade.configure(card).ok)
	assert_false(facade.query("params.reserve").open)
	var selectors: Array = ["", "params..reserve", "arrays[-1].path", "arrays[abc].path", " params.reserve", "params.reserve "]
	assert_eq(selectors.size(), 6)
	for path in selectors:
		var result: Dictionary = facade.query(path)
		assert_false(result.ok, path)
		assert_false(result.writable, path)
		assert_eq(result.source, "unknown")
	assert_false(facade.last_error.is_empty())
	assert_true(facade.query("params.reserve").ok)
	assert_eq(facade.last_error, "")

func _policy() -> Dictionary:
	return {"permissions": ["fixture_permission"], "categories": {"fixture_category": {"allowed": ["fixture_permission"], "conditional": [], "denied": []}}}
