@tool
class_name SkillEditorPanel
extends VBoxContainer

## Composition root for the editor host.  Modules own their data contracts;
## this node only forwards one detached CFG through the workflow.

const SkillApiScript = preload("res://skill_core/api/skill_api.gd")
const ValidatorScript = preload("res://skill_core/validate/validator.gd")
const SorterScript = preload("res://skill_core/validate/diagnostic_sorter.gd")
const CodecScript = preload("res://skill_core/schema/cfg_codec.gd")
const SaveFlowScript = preload("res://addons/skill_editor/ui/save_flow.gd")
const LauncherScript = preload("res://addons/skill_editor/ui/preview_launcher.gd")
const DiagPanelScript = preload("res://addons/skill_editor/ui/diagnostic_panel.gd")

class HostRunner extends RefCounted:
	func start(_cfg: Variant, _options: Dictionary) -> Dictionary:
		return {"ok": false, "path": "runner", "error": "未注入预览运行器", "diagnostics": []}

	func stop() -> Dictionary:
		return {"ok": true, "error": ""}

	func advance_ticks(_count: int = 1) -> Dictionary:
		return {"ok": false, "path": "runner.advance_ticks", "error": "未注入预览运行器"}

	func snapshot_state() -> Dictionary:
		return {"ok": false, "path": "runner.snapshot_state", "error": "未注入预览运行器"}


@onready var skill_list: Node = $Body/SkillListPanel
@onready var brick_picker: Node = $Body/BrickPicker
@onready var param_form: Node = $Body/Workspace/ParamForm
@onready var modifier_panel: Node = $Body/Workspace/ModifierPanel
@onready var presentation_panel: Node = $Body/Workspace/PresentationPanel
@onready var diagnostic_panel: Node = $Body/Workspace/DiagnosticPanel
@onready var preview_panel: Node = $Body/Workspace/PreviewPanel
@onready var preview_viewport: Node = $Body/Workspace/PreviewViewport
@onready var status_label: Label = $Status

var api: Variant = null
var validator: Variant = null
var codec: Variant = null
var sorter: Variant = null
var runner: Variant = null
var save_flow: Variant = null
var preview_launcher: Variant = null
var current_cfg: Dictionary = {}
var current_catalog: Variant = null
var project_metadata: Dictionary = {}
var limits: Dictionary = {}
var _wired: bool = false
var _ready_once: bool = false

func _ready() -> void:
	if api == null:
		api = SkillApiScript.new()
	if validator == null:
		validator = ValidatorScript.new()
	if codec == null:
		codec = CodecScript.new()
	if sorter == null:
		sorter = SorterScript.new()
	if runner == null:
		runner = HostRunner.new()
	if save_flow == null:
		save_flow = SaveFlowScript.new()
	if preview_launcher == null:
		preview_launcher = LauncherScript.new()
	_wire_signals()
	_configure_modules()
	_ready_once = true

## Optional host injection point used by the editor bridge and headless tests.
## Reconfiguration is deliberately explicit and does not reconnect signals.
func configure_host(injected: Dictionary = {}) -> Dictionary:
	for key in ["api", "validator", "codec", "sorter", "runner", "save_flow", "preview_launcher"]:
		var value: Variant = injected.get(key, null)
		if value != null:
			set(key, value)
	if injected.get("project_metadata", null) is Dictionary:
		project_metadata = injected["project_metadata"].duplicate(true)
	if injected.get("limits", null) is Dictionary:
		limits = injected["limits"].duplicate(true)
	if _ready_once:
		return _configure_modules()
	return {"ok": true, "error": ""}

func get_status() -> String:
	return status_label.text

func _wire_signals() -> void:
	if _wired:
		return
	_wired = true
	skill_list.skill_opened.connect(_on_skill_opened)
	brick_picker.brick_selected.connect(_on_brick_selected)
	param_form.values_changed.connect(_on_values_changed)
	if modifier_panel.has_signal("draft_changed"):
		modifier_panel.draft_changed.connect(_on_modifier_changed)
	if presentation_panel.has_signal("value_changed"):
		presentation_panel.value_changed.connect(_on_presentation_changed)

func _configure_modules() -> Dictionary:
	var failures: Array[String] = []
	if project_metadata.is_empty():
		project_metadata = {}
	if limits.is_empty():
		limits = project_metadata.get("project_limits", {}) if project_metadata is Dictionary else {}
	var parameter_meta: Dictionary = {}
	var presentation_meta: Dictionary = {}
	var diagnostic_meta: Dictionary = SorterScript.load_metadata()
	var records: Dictionary = {}
	if skill_list != null:
		skill_list.set("api", api)
	if brick_picker != null:
		brick_picker.set("api", api)
	if not diagnostic_meta.has("view_fields"):
		diagnostic_meta["view_fields"] = {"planner": ["rule_id", "path", "hint"], "developer": ["rule_id", "code", "path", "actual", "expected", "severity", "hint"]}
		diagnostic_meta["default_path_regex"] = "^$"
		diagnostic_meta["default_source_values"] = ["default"]
		diagnostic_meta["default_notice"] = "来自默认卡"
	if sorter.has_method("configure") and not sorter.configure(SorterScript.load_metadata()):
		failures.append("sorter: " + str(sorter.last_error))
	var diag_result: Dictionary = diagnostic_panel.configure(diagnostic_meta, sorter)
	if not diag_result.get("ok", false):
		failures.append("diagnostic_panel: " + _result_error(diag_result))
	var form_result: Dictionary = param_form.configure(parameter_meta, project_metadata, {}, {}, "author")
	if not form_result.get("ok", false):
		failures.append("param_form: " + _result_error(form_result))
	parameter_meta = param_form.params_meta.duplicate(true)
	var presentation_result: Dictionary = presentation_panel.configure(presentation_meta, {})
	if not presentation_result.get("ok", false):
		failures.append("presentation_panel: " + _result_error(presentation_result))
	presentation_meta = presentation_panel.metadata.duplicate(true)
	var modifier_result: Dictionary = modifier_panel.configure({}, [], [], _modifier_meta(parameter_meta), _item_policy(parameter_meta), {}, _modifier_view(parameter_meta))
	if not modifier_result.get("ok", false):
		failures.append("modifier_panel: " + _result_error(modifier_result))
	var viewport_result: Dictionary = preview_viewport.configure(_viewport_meta())
	if not viewport_result.get("ok", false):
		failures.append("preview_viewport: " + _result_error(viewport_result))
	var preview_result: Dictionary = preview_panel.configure(_preview_views(records), _preview_limits(records))
	if not preview_result.get("ok", false):
		failures.append("preview_panel: " + _result_error(preview_result))
	var save_result: Dictionary = save_flow.configure(validator, codec, _save_limits())
	if not save_result.get("ok", false):
		failures.append("save_flow: " + _result_error(save_result))
	var launch_result: Dictionary = preview_launcher.configure(runner)
	if not launch_result.get("ok", false):
		failures.append("preview_launcher: " + _result_error(launch_result))
	if failures.is_empty():
		_set_status("编辑器已就绪")
		return {"ok": true, "error": ""}
	_set_status("初始化失败：" + "；".join(failures))
	return {"ok": false, "error": "；".join(failures)}

func _on_skill_opened(cfg: Dictionary) -> void:
	current_cfg = cfg.duplicate(true)
	var bricks: Variant = current_cfg.get("bricks", [])
	var first_brick: Dictionary = bricks[0] if bricks is Array and not bricks.is_empty() and bricks[0] is Dictionary else {}
	var form_result: Dictionary = param_form.set_context(param_form.params_meta, project_metadata, current_cfg, first_brick)
	if not _accept(form_result, "param_form"):
		return
	var modifier_result: Dictionary = modifier_panel.configure(current_cfg, _modifier_entries(current_cfg), _exposed_entries(current_cfg), {}, _item_policy(param_form.params_meta), {}, _modifier_view(param_form.params_meta))
	if not _accept(modifier_result, "modifier_panel"):
		return
	var presentation_result: Dictionary = presentation_panel.configure(presentation_panel.metadata, current_cfg)
	if not _accept(presentation_result, "presentation_panel"):
		return
	var validation: Dictionary = _validate_current(SkillApiScript.STAGE_FILLING)
	if validation.has("diagnostics"):
		diagnostic_panel.set_diagnostics(validation["diagnostics"], {})
	if validation.get("ok", false) != true and validation.get("error", "") != "":
		_set_status("校验失败：" + str(validation["error"]))

func _on_brick_selected(brick_id: String) -> void:
	if api == null or not api.has_method("get_brick"):
		_fail_visible("brick_picker", "core API 缺少 get_brick")
		return
	var assembled: Variant = null
	if api.has_method("assemble"):
		assembled = api.call("assemble", current_cfg.duplicate(true), brick_id)
	elif api.has_method("resolve"):
		assembled = api.call("resolve", current_cfg.duplicate(true))
	else:
		_fail_visible("brick_picker", "core API 缺少装配入口")
		return
	if not assembled is Dictionary or not assembled.get("ok", false):
		var failed: Dictionary = assembled if assembled is Dictionary else {"error": "装配返回无效"}
		_fail_visible("assembly", _result_error(failed))
		return
	var data: Variant = assembled.get("cfg", assembled.get("data", assembled.get("resolved", null)))
	if data is Dictionary:
		current_cfg = data.duplicate(true)
		_on_skill_opened(current_cfg)
	else:
		_fail_visible("assembly", "core 装配未返回 CFG")

func _on_values_changed(change_table: Dictionary) -> void:
	var values: Dictionary = param_form.get_changes() if param_form.has_method("get_changes") else {}
	_apply_param_values(values)
	var submitted_paths: Array = []
	for path_value in change_table.keys():
		var path: String = str(path_value)
		var state: Variant = change_table[path].get("state", null) if change_table[path] is Dictionary else null
		if state != "unset":
			submitted_paths.append("params." + path.trim_prefix("params."))
	var validation: Dictionary = _validate_current(SkillApiScript.STAGE_FILLING, submitted_paths)
	var diagnostics: Variant = validation.get("diagnostics", [])
	var shown: Dictionary = diagnostic_panel.set_diagnostics(diagnostics, {})
	if not shown.get("ok", false):
		_fail_visible("diagnostic_panel", _result_error(shown))
	elif validation.get("error", "") != "":
		_set_status("校验失败：" + str(validation["error"]))

func _on_modifier_changed(draft: Dictionary) -> void:
	if draft is Dictionary:
		current_cfg = draft.duplicate(true)
		_on_values_changed({})

func _on_presentation_changed(value: Dictionary) -> void:
	current_cfg["presentation"] = value.duplicate(true)
	_on_values_changed({})

func save_current(context: Dictionary) -> Dictionary:
	var result: Dictionary = save_flow.save(current_cfg, context)
	if not result.get("ok", false):
		_fail_visible("save_flow", _result_error(result))
	return result

func load_current(text: String, context: Dictionary) -> Dictionary:
	var result: Dictionary = save_flow.load(text, context)
	if result.get("ok", false) and result.get("cfg", null) is Dictionary:
		_on_skill_opened(result["cfg"])
	else:
		_fail_visible("save_flow", _result_error(result))
	return result

func launch_preview(options: Dictionary) -> Dictionary:
	var launched: Dictionary = preview_launcher.launch(current_cfg, options)
	if not launched.get("ok", false):
		_fail_visible("preview_launcher.launch", _result_error(launched))
		return launched
	var advanced: Dictionary = runner.advance_ticks(1) if runner != null and runner.has_method("advance_ticks") else {"ok": false, "error": "runner 缺少 advance_ticks"}
	if not advanced.get("ok", false):
		_fail_visible("preview_runner.advance_ticks", _result_error(advanced))
		return advanced
	var snapshot: Dictionary = runner.snapshot_state() if runner.has_method("snapshot_state") else {"ok": false, "error": "runner 缺少 snapshot_state"}
	if snapshot.get("ok", true) == false:
		_fail_visible("preview_runner.snapshot_state", _result_error(snapshot))
		return snapshot
	var ingested: Dictionary = preview_panel.ingest(snapshot)
	if not ingested.get("ok", false):
		_fail_visible("preview_panel.ingest", _result_error(ingested))
		return ingested
	var frame_items: Variant = snapshot.get("frame_items", snapshot.get("items", []))
	var rendered: Dictionary = preview_viewport.render_frame(frame_items)
	if not rendered.get("ok", false):
		_fail_visible("preview_viewport.render_frame", _result_error(rendered))
		return rendered
	return rendered

func _apply_param_values(values: Dictionary) -> void:
	var params: Variant = current_cfg.get("params", null)
	if not params is Dictionary:
		params = {}
		current_cfg["params"] = params
	for path_value in values.keys():
		var path: String = str(path_value).trim_prefix("params.")
		var segments: PackedStringArray = path.split(".")
		var cursor: Dictionary = params
		for index in range(segments.size() - 1):
			var segment: String = segments[index]
			var child: Variant = cursor.get(segment, null)
			if not child is Dictionary:
				child = {}
				cursor[segment] = child
			cursor = child
		if not segments.is_empty():
			var entry: Variant = values[path_value]
			if entry is Dictionary and entry.has("value") and entry.get("state", "unset") != "unset":
				cursor[segments[segments.size() - 1]] = entry["value"]


func _validate_current(stage: StringName, submitted_paths: Array = []) -> Dictionary:
	if validator == null or not validator.has_method("validate"):
		return {"ok": false, "error": "校验器缺少 validate", "diagnostics": []}
	var context: Dictionary = {"draft_revision": 1, "submitted_paths": submitted_paths, "cross_card_facts": {}, "baseline_version_state": {}, "migration_state": {}, "probe_credentials": {}, "preview_fingerprint": {}}
	return validator.validate(current_cfg.duplicate(true), stage, context)

func _accept(result: Dictionary, name: String) -> bool:
	if result.get("ok", false):
		return true
	_fail_visible(name, _result_error(result))
	return false

func _fail_visible(name: String, message: String) -> void:
	_set_status(name + " 失败：" + message)
	var diagnostics: Variant = [{"rule_id": "HOST", "code": "HOST_ERROR", "severity": 0, "path": name, "actual": message, "expected": "ok", "hint": message}]
	if diagnostic_panel != null and diagnostic_panel.has_method("set_diagnostics"):
		# The diagnostic panel intentionally rejects plain dictionaries; keep the
		# original host error visible even when no Diagnostic instance is available.
		var status: Node = diagnostic_panel.get_node_or_null("Status")
		if status is Label:
			status.text = message

func _set_status(message: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = message

func _result_error(result: Dictionary) -> String:
	return str(result.get("error", result.get("reason", "未说明错误")))

func _save_limits() -> Dictionary:
	var result: Dictionary = limits.duplicate(true)
	if not result.has("current_schema_version"):
		result["current_schema_version"] = "0.1"
	return result

func _item_policy(parameter_meta: Dictionary) -> Dictionary:
	var permissions: Variant = parameter_meta.get("enums", {}).get("permission", []) if parameter_meta.get("enums", {}) is Dictionary else []
	return {"permissions": permissions.duplicate(true) if permissions is Array else [], "ui_access": {"author": {"visible": true, "editable": true}, "relic": {"visible": true, "editable": false}, "locked": {"visible": false, "editable": false}}}

func _modifier_meta(_parameter_meta: Dictionary) -> Dictionary:
	return {}

func _modifier_view(parameter_meta: Dictionary) -> Dictionary:
	var fields: Dictionary = {}
	var required: Array = ["modifier_id", "permission", "scope", "inheritable", "targets", "stack_rule"]
	for path_value in parameter_meta.get("leaves", []):
		if not path_value is Dictionary:
			continue
		var path: String = str(path_value.get("path", ""))
		for field in required:
			if path.ends_with("." + field) and path.begins_with("modifiers[i]."):
				fields[field] = {"type": str(path_value.get("type", "object"))}
	fields["targets"] = {"type": "array"}
	fields["stack_rule"] = {"type": "object"}
	return {"input_path": "params.modifiers", "tags_path": "meta.tags", "fields": fields,
		"roles": {"scope": "scope", "targets": "targets"}, "tagged_scope": "tagged", "field_access": "author", "display_access_by_target": {}}

func _modifier_entries(cfg: Dictionary) -> Array:
	var params: Variant = cfg.get("params", null)
	var value: Variant = params.get("modifiers", []) if params is Dictionary else []
	var result: Array = []
	if value is Array:
		for entry in value:
			if entry is Dictionary:
				result.append({"definition": entry.duplicate(true), "access": "author"})
	return result

func _exposed_entries(cfg: Dictionary) -> Array:
	var params: Variant = cfg.get("params", {})
	var value: Variant = params.get("exposed_fields", []) if params is Dictionary else []
	return value.duplicate(true) if value is Array else []

func _viewport_meta() -> Dictionary:
	return {"shapes": {"circle": "circle", "sector": "circle", "line": "line", "rectangle": "rect"}, "damage_number_format": "{text}"}

func _preview_views(_records: Dictionary) -> Dictionary:
	return {"events": ["type", "tick", "body_id", "target_id"], "settlements": ["type", "tick", "source", "target", "total"], "debug": ["type", "tick", "reason"]}

func _preview_limits(_records: Dictionary) -> Dictionary:
	return {"type_field": "type", "column_types": {"events": ["hit", "vanish"], "settlements": ["hit_settled", "evaded_all", "damage_taken", "cast_started"], "debug": ["debug_record"]}, "sources": ["events", "records", "budget.debug"]}
