class_name StageFit
extends Object

## 运行时舞台适配：让单个场景自行声明设计分辨率，不影响项目级窗口设置。
## 用法：在场景根节点 _ready 里调用 StageFit.apply(Vector2(390, 844))
## 原理：改主窗口尺寸 + 内容缩放尺寸（canvas_items 模式 + keep 比例），
##       窗口拉大时画面等比放大，UI 按设计分辨率坐标布局，不会被拉伸变形。
## 注意：只影响当前运行的那次窗口；项目设置和其他场景不受影响。

static func apply(design_size: Vector2) -> void:
	var ml := Engine.get_main_loop()
	if ml == null or not (ml is SceneTree):
		return
	var win: Window = (ml as SceneTree).root
	if win == null:
		return
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	win.content_scale_size = Vector2i(int(design_size.x), int(design_size.y))
	win.size = Vector2i(int(design_size.x), int(design_size.y))
