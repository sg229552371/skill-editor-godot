@tool
extends VBoxContainer

signal brick_selected(brick_id: String)

const API_SCRIPT = preload("res://skill_core/api/skill_api.gd")
const CATALOG_PATH: String = "res://data/bricks/brick_catalog.json"
var api: SkillApi
var _catalog: Variant = null

@onready var _carrier: OptionButton = $Filters/Carrier
@onready var _status: OptionButton = $Filters/Status
@onready var _tree: Tree = $Bricks
@onready var _message: Label = $Message

func _ready() -> void:
	# TODO(U-UI-03): API 桩未就绪，UI 按 ok:false 降级。
	if api == null:
		api = API_SCRIPT.new()
	$Filters/Refresh.pressed.connect(reload_catalog)
	_carrier.item_selected.connect(_filter_changed)
	_status.item_selected.connect(_filter_changed)
	_tree.item_selected.connect(_select_brick)
	reload_catalog()

func reload_catalog() -> void:
	_catalog = null
	_tree.clear()
	_fill_options(_carrier, [], "全部 carrier")
	_fill_options(_status, [], "全部 status")
	if api == null:
		_message.text = "功能未就绪：core API 尚无编辑器可执行桥接。"
		return
	var result: Dictionary = api.load_catalog(CATALOG_PATH)
	if not result.get("ok", false):
		_message.text = "功能未就绪或目录加载失败：等待 core 积木目录接口。"
		return
	_catalog = result.get("data")
	if _catalog == null:
		_message.text = "目录加载失败：core 未返回 data。"
		return
	var listed: Dictionary = api.list_bricks(_catalog, "", "")
	if not _show_result(listed):
		return
	var entries: Array = listed["data"]
	var carriers: Array[String] = []
	var statuses: Array[String] = []
	for value: Variant in entries:
		var entry: Dictionary = value
		var carrier: String = entry["carrier"]
		var status: String = entry["status"]
		if not carriers.has(carrier):
			carriers.append(carrier)
		if not statuses.has(status):
			statuses.append(status)
	carriers.sort()
	statuses.sort()
	_fill_options(_carrier, carriers, "全部 carrier")
	_fill_options(_status, statuses, "全部 status")

func _fill_options(control: OptionButton, values: Array, label: String) -> void:
	control.clear()
	control.add_item(label)
	control.set_item_metadata(0, "")
	for value: String in values:
		var index: int = control.item_count
		control.add_item(value)
		control.set_item_metadata(index, value)
	control.select(0)

func _filter_changed(_index: int) -> void:
	if _catalog == null:
		_message.text = "功能未就绪：请先成功加载目录。"
		return
	var carrier: String = str(_carrier.get_item_metadata(_carrier.selected))
	var status: String = str(_status.get_item_metadata(_status.selected))
	var result: Dictionary = api.list_bricks(_catalog, carrier, status)
	_show_result(result)

func _show_result(result: Dictionary) -> bool:
	_tree.clear()
	if not result.get("ok", false):
		_message.text = "功能未就绪或筛选失败：core 未返回成功。"
		return false
	var data: Variant = result.get("data")
	if not data is Array:
		_message.text = "目录响应无效：core 未返回积木数组。"
		return false
	var entries: Array = data
	for value: Variant in entries:
		if not value is Dictionary:
			_message.text = "目录响应无效：积木不是对象。"
			return false
		var entry: Dictionary = value
		for field: String in ["brick_id", "name", "carrier", "status"]:
			if not entry.get(field) is String:
				_message.text = "目录响应无效：缺少显示字段 %s。" % field
				return false
	var root: TreeItem = _tree.create_item()
	var groups: Dictionary = {}
	for value: Variant in entries:
		var entry: Dictionary = value
		var carrier: String = entry["carrier"]
		if not groups.has(carrier):
			var group: TreeItem = _tree.create_item(root)
			group.set_text(0, carrier)
			group.set_selectable(0, false)
			groups[carrier] = group
		var parent: TreeItem = groups[carrier]
		var item: TreeItem = _tree.create_item(parent)
		item.set_text(0, "%s | %s | %s" % [entry["brick_id"], entry["name"], entry["status"]])
		item.set_metadata(0, entry["brick_id"])
	# TODO(U-UI-02): API 转接 BrickCatalog，并提供导出资格；UI 不推导 status 业务规则。
	_message.text = "共 %d 项；仅浏览与选择，本轮不提供导出。" % entries.size()
	return true

func _select_brick() -> void:
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return
	var id: Variant = item.get_metadata(0)
	if id is String:
		brick_selected.emit(str(id))
