class_name BagDefs
extends RefCounted

## 背包肉鸽 · 静态配置 —— 与 sandbox/layout_prototype_v1.html 的 CFG 完全一致
## 只放数据，不放逻辑；逻辑在 systems/bag_core.gd，UI 在 ui/bag_ui.gd

## 背包规格：A = 武器背包（生效），B = 临时仓库（不生效）
const GRID := {
	"A": {"cols": 7, "rows": 5},
	"B": {"cols": 6, "rows": 5},
}

## 角色基础属性（A 包道具在此基础上累加）
const BASE_STATS := {"atk": 10.0, "spd": 1.0, "crit": 5.0, "move": 100.0, "hp": 100.0}

## 道具定义（icon 字段保留以便后续换纹理，Godot 版暂用名字渲染）
const ITEMS := [
	{"id": "w01", "name": "铁剑", "icon": "sword", "rarity": "common", "w": 1, "h": 2,
		"stats": {"atk": 8}, "desc": "最普通的铁剑，聊胜于无。"},
	{"id": "w02", "name": "猎弓", "icon": "bow", "rarity": "rare", "w": 1, "h": 3,
		"stats": {"atk": 5, "crit": 8}, "desc": "远距离 QUIET 一击。"},
	{"id": "w03", "name": "巨锤", "icon": "hammer", "rarity": "epic", "w": 2, "h": 2,
		"stats": {"atk": 20, "move": -10}, "desc": "很重，但砸下去很痛快。"},
	{"id": "w04", "name": "匕首", "icon": "dagger", "rarity": "common", "w": 1, "h": 1,
		"stats": {"atk": 3, "spd": 0.15}, "desc": "快，但不深。"},
	{"id": "w05", "name": "烈焰法杖", "icon": "staff", "rarity": "legend", "w": 2, "h": 3,
		"stats": {"atk": 15, "crit": 5, "spd": -0.2}, "desc": "持有者能闻到自己的眉毛味。"},
	{"id": "w06", "name": "护腕", "icon": "bracer", "rarity": "rare", "w": 1, "h": 1,
		"stats": {"hp": 20}, "desc": "护住要害的旧护腕。"},
	{"id": "w07", "name": "疾风之靴", "icon": "boots", "rarity": "rare", "w": 1, "h": 2,
		"stats": {"move": 15}, "desc": "跑得快是活下来的第一要义。"},
	{"id": "w08", "name": "破戒", "icon": "skull", "rarity": "epic", "w": 1, "h": 1,
		"stats": {"atk": 12, "hp": -15}, "desc": "力量是有代价的。"},
	# 异形道具示例（v2）：shape = 每行等长的 0/1 字符串，1=占格 0=挖空；
	# w/h 为包围盒尺寸（渲染节点大小），锚点 = 包围盒左上角，建议 (0,0) 格为 1
	{"id": "w09", "name": "缺角铁牌", "icon": "brick", "rarity": "epic", "w": 2, "h": 2,
		"shape": ["11", "10"],
		"stats": {"hp": 30}, "desc": "缺了一角，但很能扛。"},
]

## 初始布局（锚点 = 道具左上角）
const LAYOUT := [
	{"item": "w01", "bag": "A", "x": 0, "y": 0},
	{"item": "w04", "bag": "A", "x": 3, "y": 1},
	{"item": "w06", "bag": "A", "x": 5, "y": 3},
	{"item": "w02", "bag": "B", "x": 0, "y": 0},
	{"item": "w07", "bag": "B", "x": 2, "y": 2},
	{"item": "w03", "bag": "B", "x": 4, "y": 3},
	{"item": "w09", "bag": "B", "x": 4, "y": 0},
]
