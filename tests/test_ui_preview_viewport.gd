extends GutTest

const PreviewViewport = preload("res://addons/skill_editor/ui/preview_viewport.gd")

func _metadata() -> Dictionary:
	return {
		"shapes": {"orb": "circle", "panel": "rect"},
		"damage_number_format": "DMG {text}",
	}

func _viewport() -> PreviewViewport:
	var viewport: PreviewViewport = PreviewViewport.new()
	add_child_autofree(viewport)
	return viewport

func _item(kind: String, ttl: int = 3) -> Dictionary:
	var item: Dictionary = {
		"kind": kind,
		"pos": {"x": 40, "y": 24},
		"size": {"x": 12, "y": 8},
		"color": "#22cc88",
		"ttl": ttl,
	}
	if kind == "shape":
		item["shape"] = "orb"
	elif kind == "damage_number":
		item["text"] = "17"
	return item

func test_configure_requires_injected_shape_and_damage_metadata() -> void:
	var viewport: PreviewViewport = _viewport()
	var missing: Dictionary = viewport.configure({})
	assert_false(missing["ok"])
	assert_string_contains(missing["error"], "元数据")
	var configured: Dictionary = viewport.configure(_metadata())
	assert_true(configured["ok"])
	assert_eq(configured["shapes"]["orb"], "circle")
	assert_eq(configured["damage_number_format"], "DMG {text}")

func test_three_kinds_are_drawn_and_can_be_read_back_without_input_mutation() -> void:
	var viewport: PreviewViewport = _viewport()
	assert_true(viewport.configure(_metadata())["ok"])
	var items: Array = [_item("shape"), _item("trail"), _item("damage_number")]
	var before: String = JSON.stringify(items)
	var result: Dictionary = viewport.render_frame(items)
	assert_true(result["ok"])
	assert_eq(result["drawn"], 3)
	assert_eq(JSON.stringify(items), before)
	var snapshot: Array = viewport.get_last_frame_items()
	assert_eq(snapshot.size(), 3)
	assert_eq(snapshot[0]["kind"], "shape")
	assert_eq(snapshot[1]["kind"], "trail")
	assert_eq(snapshot[2]["text"], "DMG 17")
	snapshot[0]["pos"] = Vector2(999, 999)
	assert_eq(viewport.get_last_frame_items()[0]["pos"], Vector2(40, 24))

func test_ttl_decreases_repeated_batch_and_stops_drawing_at_zero() -> void:
	var viewport: PreviewViewport = _viewport()
	assert_true(viewport.configure(_metadata())["ok"])
	var items: Array = [_item("shape", 3)]
	assert_eq(viewport.render_frame(items)["drawn"], 1)
	assert_eq(viewport.get_last_frame_items()[0]["ttl"], 3)
	assert_eq(viewport.render_frame(items)["drawn"], 1)
	assert_eq(viewport.get_last_frame_items()[0]["ttl"], 2)
	assert_eq(viewport.render_frame(items)["drawn"], 1)
	assert_eq(viewport.get_last_frame_items()[0]["ttl"], 1)
	assert_eq(viewport.render_frame(items)["drawn"], 0)
	assert_eq(viewport.get_last_frame_items()[0]["ttl"], 0)

func test_invalid_frames_name_item_and_field() -> void:
	var viewport: PreviewViewport = _viewport()
	assert_true(viewport.configure(_metadata())["ok"])
	var unknown: Dictionary = viewport.render_frame([{"kind": "unknown"}])
	assert_false(unknown["ok"])
	assert_string_contains(unknown["error"], "item[0].kind")
	var bad_pos: Dictionary = viewport.render_frame([{"kind": "trail", "pos": "bad", "size": 4, "color": "#fff", "ttl": 1}])
	assert_false(bad_pos["ok"])
	assert_string_contains(bad_pos["error"], "item[0].pos")
	var bad_items: Dictionary = viewport.render_frame("not an array")
	assert_false(bad_items["ok"])
	assert_string_contains(bad_items["error"], "items")

func test_render_before_configure_fails_explicitly() -> void:
	var viewport: PreviewViewport = _viewport()
	var result: Dictionary = viewport.render_frame([])
	assert_false(result["ok"])
	assert_string_contains(result["error"], "未配置")
