@tool
extends EditorPlugin

const PANEL_SCENE: PackedScene = preload("res://addons/skill_editor/ui/editor_panel.tscn")
var _panel: Control

func _enter_tree() -> void:
	_panel = PANEL_SCENE.instantiate()
	add_control_to_bottom_panel(_panel, "技能编辑器")

func _exit_tree() -> void:
	if is_instance_valid(_panel):
		remove_control_from_bottom_panel(_panel)
		_panel.queue_free()
		_panel = null
