extends GutTest

const SKILL_SCENE: PackedScene = preload("res://addons/skill_editor/ui/skill_list_panel.tscn")
const BRICK_SCENE: PackedScene = preload("res://addons/skill_editor/ui/brick_picker.tscn")
const ROOT_SCENE: PackedScene = preload("res://addons/skill_editor/ui/editor_panel.tscn")

# 仅替代 API 的返回；不加载素材或绕过 API 访问 core 内部类。
class FixtureApi extends SkillApi:
	var load_result: Dictionary = {"ok": false, "diagnostics": []}
	var list_result: Dictionary = {"ok": false, "diagnostics": []}
	var requests: Array[Array] = []
	var loaded_paths: Array[String] = []

	func load_cfg(path: String) -> Dictionary:
		loaded_paths.append(path)
		return load_result.duplicate(true)

	func load_catalog(_path: String) -> Dictionary:
		return {"ok": true, "data": {"fixture_catalog": true}}

	func list_bricks(catalog: Variant, carrier: String = "", status: String = "") -> Dictionary:
		requests.append([catalog, carrier, status])
		return list_result.duplicate(true)

func test_open_displays_ids_and_names_without_merging_same_names() -> void:
	var api: FixtureApi = FixtureApi.new()
	var panel: Control = SKILL_SCENE.instantiate()
	panel.set("api", api)
	add_child_autofree(panel)
	var items: ItemList = panel.get_node("Skills")
	var path_input: LineEdit = panel.get_node("Path")
	path_input.text = "res://fixture.yaml"
	for id: String in ["role_active_one", "role_active_two"]:
		api.load_result = {"ok": true, "data": {"skill_id": id, "meta": {"name": "同名技能"}}}
		panel.get_node("Actions/Open").emit_signal("pressed")
	assert_eq(items.item_count, 2)
	assert_eq(items.get_item_text(0), "role_active_one | 同名技能")
	assert_eq(items.get_item_text(1), "role_active_two | 同名技能")
	assert_eq(items.get_item_metadata(0), "role_active_one")
	assert_eq(items.get_item_metadata(1), "role_active_two")
	assert_eq(api.loaded_paths, ["res://fixture.yaml", "res://fixture.yaml"])
	api.load_result = {"ok": false, "diagnostics": []}
	panel.get_node("Actions/Open").emit_signal("pressed")
	assert_eq(items.item_count, 2, "失败不得清空先前成功打开的条目")
	for action: String in ["New", "Delete", "Rename"]:
		panel.get_node("Actions/" + action).emit_signal("pressed")
		assert_eq(items.item_count, 2, "缺接口不得修改已有列表")

func test_malformed_success_does_not_create_skill() -> void:
	var api: FixtureApi = FixtureApi.new()
	var panel: Control = SKILL_SCENE.instantiate()
	panel.set("api", api)
	add_child_autofree(panel)
	var items: ItemList = panel.get_node("Skills")
	var path_input: LineEdit = panel.get_node("Path")
	var message: Label = panel.get_node("Message")
	path_input.text = "res://fixture.yaml"
	for data: Variant in [null, [], {}, {"skill_id": "sample", "meta": {}}]:
		api.load_result = {"ok": true, "data": data}
		panel.get_node("Actions/Open").emit_signal("pressed")
		assert_eq(items.item_count, 0)
		assert_string_contains(message.text, "打开失败")

func test_brick_filters_are_forwarded_to_api_and_group_by_carrier() -> void:
	var api: FixtureApi = FixtureApi.new()
	# 使用假 carrier/status，证明 UI 不枚举业务值，也不按中文名分类。
	api.list_result = {"ok": true, "data": [
		{"brick_id": "fixture_a", "name": "同名", "carrier": "fixture_carrier_a", "status": "fixture_status_a"},
		{"brick_id": "fixture_b", "name": "同名", "carrier": "fixture_carrier_b", "status": "fixture_status_b"},
	]}
	var panel: Control = BRICK_SCENE.instantiate()
	panel.set("api", api)
	add_child_autofree(panel)
	var carrier: OptionButton = panel.get_node("Filters/Carrier")
	var status: OptionButton = panel.get_node("Filters/Status")
	var tree: Tree = panel.get_node("Bricks")
	assert_eq(carrier.item_count, 3)
	assert_eq(status.item_count, 3)
	assert_eq(tree.get_root().get_child_count(), 2)
	assert_eq(tree.get_root().get_child(0).get_text(0), "fixture_carrier_a")
	assert_eq(tree.get_root().get_child(1).get_text(0), "fixture_carrier_b")
	assert_string_contains(tree.get_root().get_child(1).get_child(0).get_text(0), "fixture_status_b")
	api.list_result = {"ok": true, "data": [
		{"brick_id": "fixture_b", "name": "同名", "carrier": "fixture_carrier_b", "status": "fixture_status_b"},
	]}
	carrier.select(2)
	status.select(2)
	status.emit_signal("item_selected", 2)
	assert_eq(api.requests.size(), 2)
	assert_eq(api.requests[1], [{"fixture_catalog": true}, "fixture_carrier_b", "fixture_status_b"])
	assert_eq(tree.get_root().get_child_count(), 1)
	assert_eq(tree.get_root().get_child(0).get_child(0).get_metadata(0), "fixture_b")
	watch_signals(panel)
	tree.get_root().get_child(0).get_child(0).select(0)
	tree.emit_signal("item_selected")
	assert_signal_emitted_with_parameters(panel, "brick_selected", ["fixture_b"])
	api.list_result = {"ok": false, "diagnostics": []}
	status.emit_signal("item_selected", 2)
	assert_null(tree.get_root(), "筛选失败不能继续展示旧结果冒充新结果")
	var message: Label = panel.get_node("Message")
	assert_string_contains(message.text, "功能未就绪")

func test_brick_list_stub_after_catalog_success_is_safe() -> void:
	var panel: Control = BRICK_SCENE.instantiate()
	panel.set("api", FixtureApi.new())
	add_child_autofree(panel)
	var message: Label = panel.get_node("Message")
	var tree: Tree = panel.get_node("Bricks")
	assert_string_contains(message.text, "功能未就绪")
	assert_null(tree.get_root())


func test_missing_editor_bridge_degrades_without_api_call() -> void:
	var skills: Control = SKILL_SCENE.instantiate()
	var bricks: Control = BRICK_SCENE.instantiate()
	add_child_autofree(skills)
	add_child_autofree(bricks)
	skills.set("api", null)
	bricks.set("api", null)
	var path_input: LineEdit = skills.get_node("Path")
	path_input.text = "res://fixture.yaml"
	skills.get_node("Actions/Open").emit_signal("pressed")
	bricks.get_node("Filters/Refresh").emit_signal("pressed")
	var skill_message: Label = skills.get_node("Message")
	var brick_message: Label = bricks.get_node("Message")
	assert_string_contains(skill_message.text, "编辑器可执行桥接")
	assert_string_contains(brick_message.text, "编辑器可执行桥接")

func test_plugin_content_contains_both_panels() -> void:
	var panel: Control = ROOT_SCENE.instantiate()
	add_child_autofree(panel)
	assert_not_null(panel.get_node_or_null("Body/SkillListPanel/Skills"))
	assert_not_null(panel.get_node_or_null("Body/BrickPicker/Bricks"))


func test_missing_crud_interfaces_do_not_mutate_list() -> void:
	var panel: Control = SKILL_SCENE.instantiate()
	add_child_autofree(panel)
	var message: Label = panel.get_node("Message")
	var items: ItemList = panel.get_node("Skills")
	for action: String in ["New", "Delete", "Rename"]:
		panel.get_node("Actions/" + action).emit_signal("pressed")
		assert_string_contains(message.text, "功能未就绪")
		assert_string_contains(message.text, "未修改任何技能")
		assert_eq(items.item_count, 0)

func test_brick_panel_controls_and_stub_degradation() -> void:
	var panel: Control = BRICK_SCENE.instantiate()
	add_child_autofree(panel)
	for path: String in ["Filters/Carrier", "Filters/Status", "Filters/Refresh", "Bricks", "Message"]:
		assert_not_null(panel.get_node_or_null(path), path)
	var message: Label = panel.get_node("Message")
	var tree: Tree = panel.get_node("Bricks")
	assert_string_contains(message.text, "功能未就绪")
	assert_null(tree.get_root(), "桩失败不显示虚构的积木")
	panel.get_node("Filters/Refresh").emit_signal("pressed")
	assert_string_contains(message.text, "功能未就绪")


func test_skill_panel_controls_and_stub_open() -> void:
	var panel: Control = SKILL_SCENE.instantiate()
	add_child_autofree(panel)
	for path: String in ["Actions/New", "Actions/Open", "Actions/Delete", "Actions/Rename", "Skills", "Message"]:
		assert_not_null(panel.get_node_or_null(path), path)
	var items: ItemList = panel.get_node("Skills")
	var message: Label = panel.get_node("Message")
	var path_input: LineEdit = panel.get_node("Path")
	path_input.text = "res://data/skills/not_ready.yaml"
	panel.get_node("Actions/Open").emit_signal("pressed")
	assert_string_contains(message.text, "功能未就绪")
	assert_eq(items.item_count, 0, "桩失败不得伪造技能条目")
