extends GutTest

const EditorPanelScript = preload("res://addons/skill_editor/ui/editor_panel.gd")
const SkillApiScript = preload("res://skill_core/api/skill_api.gd")
const DiagnosticScript = preload("res://skill_core/api/diagnostic.gd")

class WiringApi extends RefCounted:
	var resolve_calls: int = 0
	var result: Dictionary = {"ok": false, "error": "fixture assembly failure", "diagnostics": []}

	func get_brick(_catalog: Variant, _brick_id: String) -> Dictionary:
		return {}

	func resolve(cfg: Dictionary) -> Dictionary:
		resolve_calls += 1
		return result.duplicate(true)

class WiringPreviewRunner extends RefCounted:
	var starts: int = 0
	var advances: int = 0
	var snapshots: int = 0

	func start(_cfg: Variant, _options: Dictionary) -> Dictionary:
		starts += 1
		return {"ok": true, "error": ""}

	func stop() -> Dictionary:
		return {"ok": true, "error": ""}

	func advance_ticks(_count: int = 1) -> Dictionary:
		advances += 1
		return {"ok": true, "error": ""}

	func snapshot_state() -> Dictionary:
		snapshots += 1
		return {"ok": true, "events": [], "records": [], "budget": {"debug": []}, "frame_items": [{"kind": "shape", "pos": {"x": 1, "y": 2}, "size": 4.0, "ttl": 1, "color": "#ffffff", "shape": "circle"}]}

class WiringValidator extends RefCounted:
	var calls: int = 0
	var diagnostics: Array = []

	func validate(_cfg: Dictionary, _stage: StringName, _context: Dictionary) -> Dictionary:
		calls += 1
		return {"ok": true, "diagnostics": diagnostics.duplicate(), "error": ""}

func _root() -> Node:
	var root: Node = load("res://addons/skill_editor/ui/editor_panel.tscn").instantiate()
	add_child_autofree(root)
	return root

func test_startup_creates_every_workflow_module_and_exposes_status() -> void:
	var root: Node = _root()
	var names: Array[String] = ["SkillListPanel", "BrickPicker", "ParamForm", "ModifierPanel",
		"PresentationPanel", "DiagnosticPanel", "PreviewPanel", "PreviewViewport"]
	for name in names:
		assert_not_null(root.get_node_or_null("Body/%s" % name) if name in ["SkillListPanel", "BrickPicker"] else root.get_node_or_null("Body/Workspace/%s" % name), name)
	assert_not_null(root.get_node_or_null("Status"))
	assert_eq((root.get_node("Status") as Label).text, "编辑器已就绪")

func test_skill_open_forwards_one_cfg_to_form_modifiers_presentation_and_diagnostics() -> void:
	var root: Node = _root()
	var cfg: Dictionary = {"skill_id": "wiring_skill", "meta": {"name": "连线测试"}, "params": {}, "bricks": [], "presentation": {}}
	var before: int = root.get_node("Body/SkillListPanel").get_signal_connection_list("skill_opened").size()
	root.get_node("Body/SkillListPanel").emit_signal("skill_opened", cfg)
	assert_eq(root.get("current_cfg"), cfg)
	assert_eq(root.get_node("Body/Workspace/PresentationPanel").get_value()["fx"], {})
	root.get_node("Body/SkillListPanel").emit_signal("skill_opened", cfg)
	assert_eq(root.get_node("Body/SkillListPanel").get_signal_connection_list("skill_opened").size(), before)
	assert_eq(root.get("current_cfg"), cfg)

func test_brick_selection_delegates_assembly_to_core_and_surfaces_failure() -> void:
	var root: Node = _root()
	var api: WiringApi = WiringApi.new()
	root.configure_host({"api": api})
	root.get_node("Body/BrickPicker").emit_signal("brick_selected", "fixture_brick")
	assert_eq(api.resolve_calls, 1)
	assert_string_contains((root.get_node("Status") as Label).text, "fixture assembly failure")

func test_values_changed_calls_validator_and_forwards_exact_diagnostics() -> void:
	var root: Node = _root()
	var validator: WiringValidator = WiringValidator.new()
	var diagnostic: Variant = DiagnosticScript.new()
	diagnostic.rule_id = "V-TEST"
	diagnostic.code = "E-TEST"
	diagnostic.severity = DiagnosticScript.SEV_HINT
	diagnostic.path = "schema_version"
	diagnostic.actual = "bad"
	diagnostic.expected = "good"
	diagnostic.hint = "fixture"
	validator.diagnostics = [diagnostic]
	root.configure_host({"validator": validator})
	root.get_node("Body/Workspace/ParamForm").emit_signal("values_changed", {"schema_version": {"value": "bad"}})
	assert_eq(validator.calls, 1)
	var entries: Array = root.get_node("Body/Workspace/DiagnosticPanel").get_view_entries("planner")
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["rule_id"], "V-TEST")
	assert_eq(entries[0]["path"], "schema_version")


func test_preview_pipeline_stops_at_first_failed_stage_and_keeps_error_visible() -> void:
	var root: Node = _root()
	var result: Dictionary = root.launch_preview({})
	assert_false(result["ok"])
	assert_string_contains((root.get_node("Status") as Label).text, "preview_launcher")

func test_save_load_round_trip_preserves_unknown_fields() -> void:
	var root: Node = _root()
	var validator: WiringValidator = WiringValidator.new()
	root.configure_host({"validator": validator})
	var cfg: Dictionary = {
		"schema_version": "0.1",
		"skill_id": "round_trip",
		"meta": {"name": "往返", "tags": []},
		"bricks": [{
			"brick_id": "projectile_bolt", "name": "弹道", "tagline": "向前发射",
			"carrier": "independent", "summary": "发射一个弹体",
			"default_cfg": {}, "author_params": [], "locked_params": {}, "relic_params": {},
			"presentation": [], "player_text": ["发射弹体"], "status": "已登记",
		}],
		"params": {"custom": 7, "unknown_nested": {"keep": true}},
		"presentation": {"fx": {}, "sfx": {}, "anim": {}, "trail": {}, "camera": {}, "damage_number": {}, "status_icon": {}},
		"runtime_hints": {},
	}
	var codec: Variant = root.get("codec")
	var text: String = codec.encode(cfg)
	var context: Dictionary = {"schema_version_state": {}, "baseline_version_state": {}, "migration_state": {}, "draft_revision": 1}
	var loaded: Dictionary = root.load_current(text, context)
	assert_true(loaded.get("ok", false), "load must accept codec output")
	# 顶层是精确 7 键（_check_exact_keys），但 params 是自由 map：
	# 往返必须保留作者写在 params 里的自定义/未知嵌套键（D-23 以 Schema 落点为准）。
	assert_eq(loaded.get("cfg", {}).get("params", {}).get("unknown_nested", {}).get("keep", false), true)

func test_preview_pipeline_completes_all_stages_with_injected_runner() -> void:
	var root: Node = _root()
	var preview_runner: RefCounted = WiringPreviewRunner.new()
	root.configure_host({"runner": preview_runner})
	var options: Dictionary = {"seed": 1, "roots": [], "targets": [], "handlers": {}, "template_families": {}, "derivation_bindings": {}}
	var result: Dictionary = root.launch_preview(options)
	assert_true(result.get("ok", false), "preview must complete with a valid runner")
	assert_eq(preview_runner.starts, 1)
	assert_eq(preview_runner.advances, 1)
	assert_eq(preview_runner.snapshots, 1)
