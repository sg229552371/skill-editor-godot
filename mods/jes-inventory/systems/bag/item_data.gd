class_name ItemData
extends Resource

## 物品定义（数据层唯一真源，对应 .tres）
##
## 设计口径（D-52）：
##   - 只声明「我是什么、占多大、能不能叠」，不声明任何 UI / 表现
##   - 堆叠上限=1 表示唯一物（遗物），>1 表示可叠材料
##   - 占格尺寸用 grid_w / grid_h 表达；多格物品是背包系统的核心复杂度来源

@export var item_id: StringName = &""
@export var display_name: String = ""
@export var grid_w: int = 1          # 占几列（≥1）
@export var grid_h: int = 1          # 占几行（≥1）
@export var max_stack: int = 1       # 堆叠上限；1 = 唯一物
@export var tags: Array[StringName] = []


## 单件占格数（纯函数，供容量统计与排序使用）
func cell_count() -> int:
	return maxi(grid_w, 1) * maxi(grid_h, 1)


## 是否可堆叠
func is_stackable() -> bool:
	return max_stack > 1


## 自检：返回错误列表，空数组 = 合规。
## 这条是「声明面」判据 P2 的落点 —— 物品自己声明约束，机器来核对，
## 而不是让背包容器在运行时到处 if 判空、判 0。
func validate() -> Array[String]:
	var errs: Array[String] = []
	if item_id == &"":
		errs.append("item_id 不能为空")
	if grid_w < 1 or grid_h < 1:
		errs.append("grid_w/grid_h 必须 ≥1（当前 %d×%d）" % [grid_w, grid_h])
	if max_stack < 1:
		errs.append("max_stack 必须 ≥1（当前 %d）" % max_stack)
	if grid_w > 8 or grid_h > 8:
		errs.append("单件占格不得超过 8×8（当前 %d×%d），疑似配置错误" % [grid_w, grid_h])
	return errs
