@tool
extends VBoxContainer

signal skill_opened(cfg: Dictionary)

const API_SCRIPT = preload("res://skill_core/api/skill_api.gd")
var api: SkillApi
var _loaded_cfgs: Array[Dictionary] = []

@onready var _skills: ItemList = $Skills
@onready var _message: Label = $Message
@onready var _path: LineEdit = $Path

func _ready() -> void:
	# TODO(U-UI-03): API 桩未就绪，UI 按 ok:false 降级。
	if api == null:
		api = API_SCRIPT.new()
	$Actions/New.pressed.connect(_unavailable.bind("新建"))
	$Actions/Open.pressed.connect(open_skill)
	$Actions/Delete.pressed.connect(_unavailable.bind("删除"))
	$Actions/Rename.pressed.connect(_unavailable.bind("重命名"))
	_skills.item_activated.connect(_activate_skill)
	_message.text = "功能未就绪：技能索引接口尚未提供；下方仅列出本次打开成功的技能。"

func open_skill() -> void:
	var path: String = _path.text.strip_edges()
	if path.is_empty():
		_message.text = "请填写技能 CFG 路径。"
		return
	if api == null:
		_message.text = "功能未就绪：core API 尚无编辑器可执行桥接。"
		return
	var result: Dictionary = api.load_cfg(path)
	if not result.get("ok", false):
		_message.text = "功能未就绪或打开失败：core 未返回成功；列表保持不变。"
		return
	var data: Variant = result.get("data")
	if not data is Dictionary:
		_message.text = "打开失败：core 返回的 data 不是技能定义。"
		return
	var cfg: Dictionary = data
	var meta_value: Variant = cfg.get("meta")
	if not meta_value is Dictionary or not cfg.get("skill_id") is String:
		_message.text = "打开失败：core 返回缺少 skill_id 或 meta。"
		return
	var meta: Dictionary = meta_value
	if not meta.get("name") is String:
		_message.text = "打开失败：core 返回缺少技能名称。"
		return
	var skill_id: String = cfg["skill_id"]
	var index: int = -1
	for i: int in range(_loaded_cfgs.size()):
		if _loaded_cfgs[i].get("skill_id") == skill_id:
			index = i
			break
	if index < 0:
		index = _skills.add_item("")
		_loaded_cfgs.append({})
	_loaded_cfgs[index] = cfg.duplicate(true)
	_skills.set_item_text(index, "%s | %s" % [skill_id, meta["name"]])
	_skills.set_item_metadata(index, skill_id)
	_skills.select(index)
	_message.text = "已打开；仅展示 core 返回的数据，未保存或更改定义。"
	skill_opened.emit(cfg.duplicate(true))

func _activate_skill(index: int) -> void:
	if index >= 0 and index < _loaded_cfgs.size():
		skill_opened.emit(_loaded_cfgs[index].duplicate(true))

func _unavailable(operation: String) -> void:
	# TODO(U-UI-01): 申请 core 技能索引及创建/删除/重命名接口；不得由 UI 实现业务。
	_message.text = "功能未就绪：%s接口尚未提供；未修改任何技能。" % operation
