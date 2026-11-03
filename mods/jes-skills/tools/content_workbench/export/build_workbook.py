# -*- coding: utf-8 -*-
"""W2 反向导出 · 生成中文 Excel 工作簿（6 页签）。

只读输入：
  - tools/content_workbench/schema.json   （冻结契约 v1.3，绝不修改）
  - tools/content_workbench/_tmp/export.json （A 脚本产物）
独占输出：
  - mods/jes-skills/content_src/技能配置表.xlsx

【零丢失纪律 / 编解码约定】（与 export/selfcheck.py 各自独立实现，互相印证）
  1. 显式中文列只承载「能用一个单元格无损表达」的字段；其余字段（含数组、字典、
     嵌套子资源、未知参数键、复杂参数值）以 JSON 原文写入隐藏列「高级数据」。
  2. 枚举单元格一律写中文词表 label。④ 辅助石「属性」列按 enums.stat_labels 中文化；
     「运算」按 enums.op 中文化；「③ 效果段」的 formation / motion 参数列按
     param_enum_columns 中文化；W3 负责把中文 label 依契约映射回原英文 value。
  3. 多值列用「+」分隔；伤害类型 label 与基础伤害数值两列顺序一一对应。
  4. 参数列按 param_labels 展开成中文列；值为复杂结构或不在 param_labels 的键
     （如 path_damage）按 unknown_param_policy 原样进「高级数据」。
     契约 v1.3：buff_mods 参数不再是一列，而是按 buff_spec.columns 展开成三条对齐列
     （增益属性 / 增益运算 / 增益数值），本端把该行全部条目按行序铺进三列；
     条目含 stat/op/value 之外的键或列表为空时整份回落到 __extras，保证零丢失。
  5. 「属于哪个技能」用中文技能名关联技能卡（引用型下拉，单选、填错即拦）。
  6. 显式列的值直接从 export.json 取，因此 W3 按 generate_rule「显式列为准」覆盖
     __extras 同名字段后，值不变——这是往返零差异的基础。
  7. 契约 v1.2：每张表第 2 行起是锁定示例行，主键列以 example_row_policy.marker
     「【示例】」开头，W3 据此跳过；② ④ 的备注列同样带该前缀。
     契约 v1.3：示例行补齐——② 4 行、③ 5 行（含「线 + 范围爆发」「引导」「自我增益」）、
     ④ 4 行，全部锁定且不进入资源。
  8. 契约 v1.2：三色黄色只按 behavior_required；shape_keys 是「形状可用键」而非
     必填键，形状尺寸参数列一律白色选填，不再因 shape_keys 标黄（shape_keys_policy）。
  9. 契约 v1.3：② ③ ④ 每个在 column_notes 里有文案的数据列，表头单元格写 Excel 批注
     （openpyxl Comment），文案一律取自 column_notes，不另编。
 10. 契约 v1.3：单值枚举列（类型 enum:* 或 param_enum_columns 指向的列）下拉
     开 showErrorMessage=True + 中文错误提示；含「+ 分隔」的多值列保持允许自由文本，
     只设中文 promptTitle/prompt 填写提示。
 11. 契约 v1.4 new_row_policy.editable_scope：②③④ 数据行之后按 reserved_rows
     （② 40 / ③ 90 / ④ 30）追加「可编辑预留行」。预留行可见数据列 unlocked 白底、
     受同一份 DataValidation 覆盖；代号列（②④ 的「代号（自动，别填）」）保持
     灰底 locked，并以浅灰文字 + 单元格批注给出中文占位说明（不写死任何具体代号）；
     高级数据（隐藏）列保持 locked。
     预留行的「代号（自动，别填）」列是表格主体、也是主键列（②④），抹灰会覆盖掉
     主键列原有的黄色必填批注，这里按锁定示例行标记的同一口径补回中文批注。
 12. 契约 v1.4：预留行数量与列口径一律从 schema.new_row_policy 读取，脚本常量只做
     前置校验（与契约不一致即中文报错，不静默漂移）。
 13. 契约 v1.5：② 技能卡 在「备注（不进游戏）」前渲染「图标」列（白底可编辑，填
     res:// 路径，留空＝用引擎默认）；④ 辅助石 在「备注（不进游戏）」前渲染
     「行为覆盖（工具自动，勿改）」列（灰底只读，展示该行 behavior_overrides 的
     JSON 原文，无则留空）。两列批注文案取自 column_notes。两字段升为显式列后：
     显式列优先、缺失仍由 __extras 兜底补齐（extras_policy.generate_rule），
     80 条内容零丢失。
"""
from __future__ import annotations

import json
from pathlib import Path

from openpyxl import Workbook
from openpyxl.comments import Comment
from openpyxl.styles import Alignment, Font, PatternFill, Protection
from openpyxl.utils import get_column_letter
from openpyxl.workbook.defined_name import DefinedName
from openpyxl.worksheet.datavalidation import DataValidation

# —— 路径（全部相对本文件推导，不写本机盘符绝对路径）——
HERE = Path(__file__).resolve().parent                 # export/
WORKBENCH = HERE.parent                               # content_workbench/
SCHEMA_PATH = WORKBENCH / "schema.json"
EXPORT_JSON = WORKBENCH / "_tmp" / "export.json"
MODULE_DIR = WORKBENCH.parent.parent                  # mods/jes-skills/
WORKBOOK_PATH = MODULE_DIR / "content_src" / "技能配置表.xlsx"

# 契约 v1.2 example_row_policy.marker：主键列以此前缀开头即锁定示例行，W3 跳过。
EXAMPLE_PREFIX = "【示例】"
EXAMPLE_MARK = EXAMPLE_PREFIX + "这是例子，照着填"
LEGACY_EXAMPLE_MARK = "这是例子，照着填"  # v1.1 旧文本，B 端不再写出
REPORT_HEADERS = ["页签", "行", "列", "问题", "怎么改"]

# 契约 v1.3：示例行数量（② 4 行 / ③ 5 行 / ④ 4 行）
EXAMPLE_ROWS = {"skills": 4, "parts": 5, "supports": 4}

# 契约 v1.3：引用型下拉的 defined name（指向 ② 技能卡 的数据行技能名）
SKILL_REF_NAME = "OPT_SKILL_NAMES"
SINGLE_ENUM_ERROR = "只能选列表里的中文选项"
EXTRAS_LABEL = "高级数据（工具自动，勿改）"
# 契约 v1.5：②「图标」列（白底可编辑，填 res:// 路径）；④「行为覆盖」列（灰底只读）
ICON_LABEL = "图标"
BO_LABEL = "行为覆盖（工具自动，勿改）"

# 契约 v1.4 new_row_policy.reserved_rows：预留行数量（只在契约缺字段时兜底，
# main() 会与契约逐项核对，不一致即中文报错）
RESERVED_ROWS = {"skills": 40, "parts": 90, "supports": 30}

# 契约 v1.4 new_row_policy.code_column：预留行代号列的中文占位提示（不写死具体代号）
NEW_ROW_ID_HINT = "新技能由工具生成代号，填了技能名即可"
NEW_ROW_ID_COMMENT = (
    "行留空就是「新增」：填了「技能名」即可；"
    "代号（skill_ / support_ + 三位序号）由工具自动生成，冲突会中文报错。"
)
FONT_HINT = Font(size=10, italic=True, color="808080")   # 预留行代号列的浅灰占位文字

# 契约 v1.3：多值列中文填写提示（promptTitle 用列头，prompt 用下面文案）
MULTI_PROMPTS = {
    "标签（用 + 分隔）": "可填多个，用 + 分隔（例：投射物+闪电）。",
    "允许的辅助标签": "可填多个，用 + 分隔（例：投射物+近战）；留空＝不限制。",
    "伤害类型（用 + 分隔）": "可填多个伤害类型，用 + 分隔；顺序与「基础伤害」列一一对应。",
    "基础伤害（用 + 分隔，与上一列顺序对应）":
        "可填多个数值，用 + 分隔；个数、顺序与「伤害类型」列一一对应。",
    "需要的标签（全部，+ 分隔）": "可填多个标签，用 + 分隔；全部满足才装得上。",
    "需要的标签（任一，+ 分隔）": "可填多个标签，用 + 分隔；满足任意一个即可。",
    "添加标签": "可填多个标签，用 + 分隔；装上后追加给技能。",
    "排除标签": "可填多个标签，用 + 分隔；技能带这些标签就装不上。",
    "特性（+ 分隔）": "可填多个特性，用 + 分隔。",
    "冲突辅助（+ 分隔）": "填辅助石中文名，多个用 + 分隔（例：火焰专注+冰冷专注）。",
    "增益属性（用 + 分隔）": "可填多项属性，用 + 分隔；与后两列逐项对齐。",
    "增益运算（用 + 分隔，与上一列顺序对应）": "可填多项运算，用 + 分隔；与上下两列逐项对齐。",
    "增益数值（用 + 分隔，与上一列顺序对应）": "可填多个数值，用 + 分隔；与上面两列逐项对齐。",
}

# 契约 v1.4：数据行主键列（② 技能名 / ④ 辅助石名）代号格的批注文案（全中文）
KEY_COLUMN_NOTE = "这一行的主键列（必填，黄色）。代号由工具自动生成，别改。"


def is_example_marker(value) -> bool:
    return value is not None and str(value).startswith(EXAMPLE_PREFIX)


# 三色 + 辅助色
FILL_YELLOW = PatternFill("solid", fgColor="FFF2CC")   # 本行必填
FILL_GRAY = PatternFill("solid", fgColor="D9D9D9")     # 不用填 / 代号只读
FILL_WHITE = PatternFill("solid", fgColor="FFFFFF")    # 选填
FILL_EXAMPLE = PatternFill("solid", fgColor="DDEBF7")  # 示例行
FILL_HEADER = PatternFill("solid", fgColor="4472C4")   # 表头
FILL_LEGEND = {
    "黄": PatternFill("solid", fgColor="FFF2CC"),
    "灰": PatternFill("solid", fgColor="D9D9D9"),
    "白": PatternFill("solid", fgColor="FFFFFF"),
}
FONT_TITLE = Font(bold=True, size=20)
FONT_BODY = Font(size=14)
FONT_NOTE = Font(size=12)
FONT_BOLD = Font(bold=True, size=12)
FONT_HEADER = Font(bold=True, color="FFFFFF", size=11)

# 显式列承载的顶层字段（其余全部进 __extras）
# 契约 v1.5：icon / behavior_overrides 升为显式中文列，不再依赖 __extras 兜底
EXPLICIT_SKILL_FIELDS = {
    "display_name", "gem_id", "icon", "cast_mode", "cost_type", "base_cost",
    "base_cooldown", "base_cast_time", "max_charges", "charge_recharge_time",
    "level_scaling", "tags", "allowed_support_tags",
}
EXPLICIT_SUPPORT_FIELDS = {
    "display_name", "support_id", "require_tags", "require_any_tags",
    "add_tags", "exclude_tags", "cost_multiplier", "flags", "conflicts_with",
    "behavior_overrides",
}


# ============================ 词表与枚举工具 ============================

def build_enum_maps(schema: dict) -> dict:
    """把 schema.enums 归一成 {name: {labels, values, v2l, l2v}}。"""
    maps: dict = {}
    for name, entries in schema["enums"].items():
        if entries and isinstance(entries[0], dict):
            labels = [e["label"] for e in entries]
            values = [e["value"] for e in entries]
        else:
            labels = list(entries)
            values = list(entries)
        maps[name] = {
            "labels": labels,
            "values": values,
            "v2l": {str(v): l for v, l in zip(values, labels)},
            "l2v": {l: v for l, v in zip(labels, values)},
        }
    return maps


def enc_enum(name: str, value, maps: dict):
    """单值：value -> 中文 label；词表不认识就原样返回（保证无损、不丢类型）。"""
    if value is None:
        return ""
    key = str(value)
    if key in maps[name]["v2l"]:
        return maps[name]["v2l"][key]
    return value


def enc_multi(name: str, values, maps: dict) -> str:
    """数组 -> 中文 label 用 + 连接；空数组 -> 空串。"""
    return "+".join(str(enc_enum(name, v, maps)) for v in values)


def fmt_num(v) -> str:
    """数值转文本（用于 + 拼接）：整数值去掉 .0，其余保持原样。"""
    if v is None:
        return ""
    if isinstance(v, bool):
        return str(v)
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v)


def enum_of_type(type_str: str):
    """从 columns 的 type 推导词表名（enum:xxx / multienum:xxx）。"""
    if type_str.startswith("enum:") or type_str.startswith("multienum:"):
        return type_str.split(":", 1)[1]
    return None


def param_enum_map(schema: dict) -> dict:
    """schema.param_enum_columns 去掉说明键，只留「参数键 -> 词表名」。"""
    return {k: v for k, v in schema.get("param_enum_columns", {}).items()
            if k != "note" and isinstance(v, str)}


# ============================ 参数列规划 ============================

def plan_param_columns(schema: dict):
    """参数列按「形状 / 行为 / 其它」三段分组，并把 buff_mods 展开成三条对齐列。

    返回 (specs, groups, shape_dim_keys, gray_keys)：
      specs: [{"key","sub","label","group"}]，sub 仅 buff_spec 展开列非空；
      groups: [(起始下标, 结束下标)]，用于列分组折叠；
      shape_dim_keys: 形状尺寸参数键（一律白色选填）；
      gray_keys: 非形状的行为必填键（灰色候选，仅提示不用填）。
    """
    shape_keys_set = {k for ks in schema["shape_keys"].values() for k in ks}
    behavior_req_set = {k for ks in schema["behavior_required"].values() for k in ks}
    # shape 由「形状」固定列承载，不再作为独立参数列
    all_keys = [k for k in schema["param_labels"] if k != "shape"]
    g_shape = [k for k in all_keys if k in shape_keys_set]
    g_behavior = [k for k in all_keys if k not in shape_keys_set and k in behavior_req_set]
    g_other = [k for k in all_keys if k not in shape_keys_set and k not in behavior_req_set]
    ordered = g_shape + g_behavior + g_other

    buff_param = schema["buff_spec"]["param"]
    specs = []
    for key in ordered:
        if key in g_shape:
            group = "shape"
        elif key in g_behavior:
            group = "behavior"
        else:
            group = "other"
        if key == buff_param:
            # 契约 v1.3：buff_mods 一列 -> 三条对齐列（列头必须与 buff_spec 完全一致）
            for coldef in schema["buff_spec"]["columns"]:
                specs.append({"key": key, "sub": coldef["key"],
                              "label": coldef["label"], "group": group})
        else:
            specs.append({"key": key, "sub": None,
                          "label": schema["param_labels"][key], "group": group})

    groups = []
    cursor = 0
    while cursor < len(specs):
        grp = specs[cursor]["group"]
        end = cursor
        while end + 1 < len(specs) and specs[end + 1]["group"] == grp:
            end += 1
        groups.append((cursor, end))
        cursor = end + 1
    return specs, groups, shape_keys_set, behavior_req_set - shape_keys_set


def param_fill(behavior_id: str, key: str, schema: dict,
               shape_dim_keys: set, gray_keys: set) -> PatternFill:
    """契约 v1.2 三色：黄色只按 behavior_required；形状尺寸参数列一律白色选填。"""
    if key in shape_dim_keys:
        return FILL_WHITE
    row_req = set(schema["behavior_required"].get(behavior_id, [])) - shape_dim_keys
    if key in row_req:
        return FILL_YELLOW
    if key in gray_keys:
        return FILL_GRAY
    return FILL_WHITE


# ============================ 拆分：记录 -> 显式列 + __extras ============================

def split_skill(s: dict, maps: dict):
    cells = {
        "技能名": s["display_name"],
        "代号（自动，别填）": s["gem_id"],
        "施法方式": enc_enum("cast_mode", s["cast_mode"], maps),
        "消耗类型": enc_enum("cost_type", s["cost_type"], maps),
        "消耗数值": s["base_cost"],
        "冷却（秒）": s["base_cooldown"],
        "前摇（秒）": s["base_cast_time"],
        "最多充能": s["max_charges"],
        "充能回复（秒）": s["charge_recharge_time"],
        "每级变强": s["level_scaling"]["per_level"],
        "成长拐点等级": s["level_scaling"]["knee_level"],
        "拐点后每级变强": s["level_scaling"]["per_level_late"],
        "标签（用 + 分隔）": enc_multi("tag", s["tags"], maps),
        "允许的辅助标签": enc_multi("tag", s["allowed_support_tags"], maps),
        # 契约 v1.5：图标列在「备注」前，填 res:// 路径；原值 null / 缺失都写空串
        ICON_LABEL: "" if s.get("icon") is None else str(s["icon"]),
        "备注（不进游戏）": "",
    }
    extras = {k: v for k, v in s.items() if k not in EXPLICIT_SKILL_FIELDS}
    return cells, extras


def split_part(part: dict, parent_name: str, index: int, maps: dict, schema: dict,
               param_key_set: set, param_enums: dict):
    """把一条效果段拆成显式中文列 + __extras。

    参数列：formation / motion 按 param_enum_columns 中文化；buff_mods 按 buff_spec
    展开成三条对齐列（properties 键为 (参数键, 子键)）。
    """
    bp = part["behavior_params"]
    shape_val = bp.get("shape")
    cells = {
        "属于哪个技能": parent_name,
        "第几段": index,
        "效果": enc_enum("behavior", part["behavior_id"], maps),
        "形状": enc_enum("shape", shape_val, maps) if shape_val is not None else "",
        "伤害效用": part["damage_effectiveness"],
        "命中通道": enc_enum("damage_channel", part["damage_channel"], maps),
    }

    # 伤害类型 / 基础伤害：中文 label + 分隔，顺序对应；词表外键进 extras 保底
    bd = part["base_damage"]
    dt_keys, dt_vals, bd_rest = [], [], {}
    dt_v2l = maps["damage_type"]["v2l"]
    for k, v in bd.items():
        if str(k) in dt_v2l:
            dt_keys.append(dt_v2l[str(k)])
            dt_vals.append(fmt_num(v))
        else:
            bd_rest[k] = v
    cells["伤害类型（用 + 分隔）"] = "+".join(dt_keys)
    cells["基础伤害（用 + 分隔，与上一列顺序对应）"] = "+".join(dt_vals)

    buff_param = schema["buff_spec"]["param"]
    param_cells: dict = {}
    bp_rest: dict = {}

    # 契约 v1.3：buff_mods 三列可表达的条件 = 非空列表且每条只有 stat/op/value 三个键
    mods = bp.get(buff_param)
    mods_expressible = bool(
        isinstance(mods, list) and mods
        and all(isinstance(e, dict) and set(e.keys()) <= {"stat", "op", "value"}
                for e in mods))
    if mods_expressible:
        param_cells[(buff_param, "stat")] = "+".join(
            str(enc_enum("stat_labels", e.get("stat"), maps)) for e in mods)
        param_cells[(buff_param, "op")] = "+".join(
            str(enc_enum("op", e.get("op"), maps)) for e in mods)
        param_cells[(buff_param, "value")] = "+".join(
            fmt_num(e.get("value")) for e in mods)

    for k, v in bp.items():
        if k == "shape":
            continue  # 已由「形状」固定列承载
        if k == buff_param:
            if not mods_expressible:
                # 空列表 / 含额外键的条目：整份原样进 __extras，保证零丢失
                bp_rest[k] = v
            continue
        if k in param_key_set and not isinstance(v, (list, dict)):
            if k in param_enums and k in maps:
                param_cells[(k, None)] = enc_enum(param_enums[k], v, maps)
            else:
                param_cells[(k, None)] = v
        else:
            bp_rest[k] = v
    cells["__params__"] = param_cells

    extras = {}
    if bp_rest:
        extras["behavior_params"] = bp_rest
    if bd_rest:
        extras["base_damage"] = bd_rest
    # 除 behavior_params / base_damage 外，SkillPart 其余字段均由显式列承载
    covered = {"behavior_params", "base_damage", "behavior_id",
               "damage_effectiveness", "damage_channel"}
    for k, v in part.items():
        if k not in covered:
            extras[k] = v
    return cells, extras


def split_support(s: dict, maps: dict, support_name_by_id: dict):
    mods = s["stat_modifiers"]
    if mods:
        m0 = mods[0]
        stat_cell = enc_enum("stat_labels", m0["stat"], maps)
        op_cell = enc_enum("op", m0["op"], maps)
        value_cell = m0["value"]
    else:
        stat_cell = op_cell = value_cell = ""
    # 契约 v1.3 support_ref：冲突辅助显示辅助石中文名（多值用 + 分隔），W3 按名还原代号
    conflict_text = "+".join(
        str(support_name_by_id.get(str(v), str(v))) for v in s["conflicts_with"])
    # 契约 v1.5：行为覆盖列展示该行 behavior_overrides 的 JSON 原文；无则留空
    bo = s.get("behavior_overrides")
    bo_cell = json.dumps(bo, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":")) if bo else ""
    cells = {
        "辅助石名": s["display_name"],
        "代号（自动，别填）": s["support_id"],
        "需要的标签（全部，+ 分隔）": enc_multi("tag", s["require_tags"], maps),
        "需要的标签（任一，+ 分隔）": enc_multi("tag", s["require_any_tags"], maps),
        "添加标签": enc_multi("tag", s["add_tags"], maps),
        "排除标签": enc_multi("tag", s["exclude_tags"], maps),
        "消耗倍率": s["cost_multiplier"],
        "属性": stat_cell,
        "运算": op_cell,
        "数值": value_cell,
        "特性（+ 分隔）": "+".join(str(v) for v in s["flags"]),
        "冲突辅助（+ 分隔）": conflict_text,
        # 契约 v1.5：行为覆盖列在「备注」前，工具自动带出，策划勿改
        BO_LABEL: bo_cell,
        "备注（不进游戏）": "",
    }
    # stat_modifiers 是数组，三个标量列只投影第 0 项，无法无损表达整个字段 -> 完整进 extras
    extras = {k: v for k, v in s.items() if k not in EXPLICIT_SUPPORT_FIELDS}
    return cells, extras


def extras_text(extras: dict) -> str:
    return json.dumps(extras, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


# ============================ 示例行 ============================

def example_skill_row(n: int) -> dict:
    profiles = [
        ("法术+投射物+冰冷", "投射物", 10, 3.0),
        ("攻击+近战+物理", "近战", 18, 5.0),
        ("法术+范围+火焰", "范围", 24, 8.0),
        ("召唤+范围+法术", "召唤", 0, 0.0),
    ]
    tags, allow, cost, cd = profiles[(n - 1) % len(profiles)]
    return {
        "技能名": EXAMPLE_MARK,
        "代号（自动，别填）": "（工具自动生成，不用填）",
        "施法方式": "主动施放",
        "消耗类型": "法力" if n <= 3 else "无消耗",
        "消耗数值": cost,
        "冷却（秒）": cd,
        "前摇（秒）": 0.5 if n <= 3 else 0.0,
        "最多充能": 0,
        "充能回复（秒）": 0.0,
        "每级变强": 0.1 if n <= 3 else 0.0,
        "成长拐点等级": 0,
        "拐点后每级变强": 0.0,
        "标签（用 + 分隔）": tags,
        "允许的辅助标签": allow,
        "备注（不进游戏）": EXAMPLE_PREFIX + "照着填，别改灰色的代号列",
    }


# ③ 示例行：覆盖「投掷物 / 近战挥砍 / 线 + 范围爆发 / 引导 / 自我增益」五种
PART_EXAMPLES = [
    {
        "效果": "投掷物", "形状": "圆",
        "伤害类型": "冰冷", "基础伤害": "100", "命中通道": "命中",
        "params": {"radius": 14.0, "speed": 600.0, "lifetime": 2.0, "count_base": 1.0},
    },
    {
        "效果": "近战挥砍", "形状": "扇形",
        "伤害类型": "物理", "基础伤害": "170", "命中通道": "命中",
        "params": {"arc_deg": 70.0, "range": 150.0},
    },
    {
        "效果": "范围爆发", "形状": "线",
        "伤害类型": "火焰", "基础伤害": "120", "命中通道": "命中",
        "params": {"length": 300.0, "width": 120.0, "delay": 0.5, "hit_count": 1},
    },
    {
        "效果": "引导", "形状": "圆",
        "伤害类型": "闪电", "基础伤害": "45", "命中通道": "持续",
        "params": {"range": 140.0, "max_channel_time": 3.0, "tick_interval": 0.5},
    },
    {
        "效果": "自我增益", "形状": "",
        "伤害类型": "", "基础伤害": "", "命中通道": "",
        "params": {"duration": 8.0, "formation": "单点"},
        "buff": ("物理伤害+暴击率", "固定加值+百分比增加", "30+25"),
    },
]


def example_part_row(n: int) -> dict:
    ex = PART_EXAMPLES[n - 1]
    row = {
        "属于哪个技能": EXAMPLE_MARK,
        "第几段": 1,
        "效果": ex["效果"],
        "形状": ex["形状"],
        "伤害类型（用 + 分隔）": ex["伤害类型"],
        "基础伤害（用 + 分隔，与上一列顺序对应）": ex["基础伤害"],
        "伤害效用": 1.0,
        "命中通道": ex["命中通道"],
    }
    params = {(k, None): v for k, v in ex["params"].items()}
    if ex.get("buff"):
        stat, op, value = ex["buff"]
        params[("buff_mods", "stat")] = stat
        params[("buff_mods", "op")] = op
        params[("buff_mods", "value")] = value
    row["__params__"] = params
    return row


def example_support_row(n: int, conflict_name: str = "") -> dict:
    profiles = [
        ("投射物", "冰冷伤害", 1.4, 30),
        ("近战", "物理伤害", 1.2, 40),
        ("范围", "范围大小", 1.3, 35),
        ("火焰", "火焰伤害", 1.5, 50),
    ]
    tag, stat, mult, value = profiles[(n - 1) % len(profiles)]
    return {
        "辅助石名": EXAMPLE_MARK,
        "代号（自动，别填）": "（工具自动生成，不用填）",
        "需要的标签（全部，+ 分隔）": tag,
        "需要的标签（任一，+ 分隔）": "",
        "添加标签": "",
        "排除标签": "",
        "消耗倍率": mult,
        "属性": stat,
        "运算": "百分比增加",
        "数值": value,
        "特性（+ 分隔）": "",
        "冲突辅助（+ 分隔）": conflict_name if n == 2 else "",
        "备注（不进游戏）": EXAMPLE_PREFIX + "照着填",
    }


# ============================ 页签构建 ============================

def style_header(ws, labels: list):
    for i, label in enumerate(labels, start=1):
        c = ws.cell(row=1, column=i, value=label)
        c.fill = FILL_HEADER
        c.font = FONT_HEADER
        c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
        c.protection = Protection(locked=True)
    ws.row_dimensions[1].height = 30
    ws.freeze_panes = "A2"


def add_column_comments(ws, labels: list, notes: dict, aliases: dict | None = None) -> int:
    """契约 v1.3：给每个在 column_notes 里有文案的列，在表头单元格写 Excel 批注。

    文案一律取自 schema.column_notes，不另编；aliases 只用于契约 key 与列头不同名
    的既有情况（② 的「技能代号」->「代号（自动，别填）」）。
    """
    aliases = aliases or {}
    added = 0
    for i, label in enumerate(labels, start=1):
        note = notes.get(label)
        if note is None:
            note = notes.get(aliases.get(label, ""))
        if note is None:
            continue
        ws.cell(row=1, column=i).comment = Comment(
            note, "配置表工具", width=340, height=130)
        added += 1
    return added


def autofit_columns(ws, labels: list, min_w: float = 9, max_w: float = 30):
    """按中文列头长度设列宽，避免表头被截断（中文按双宽估算）。"""
    for i, label in enumerate(labels, start=1):
        text = "" if label is None else str(label)
        width = len(text) * 1.9 + 2
        ws.column_dimensions[get_column_letter(i)].width = min(max_w, max(min_w, width))


def write_data_row(ws, r: int, labels: list, cells: dict, *, example: bool,
                   id_label: str, extras_label: str,
                   param_cols: list | None = None,
                   param_fill_map: dict | None = None,
                   readonly_labels: set | None = None):
    """写一行（含展开后的参数列）。param_cols: [(spec, 列号)]。

    readonly_labels：灰底只读列（如 ④ 的「行为覆盖」），非示例行也灰底 + locked。
    """
    readonly_labels = readonly_labels or set()
    for i, label in enumerate(labels, start=1):
        value = cells.get(label, "")
        c = ws.cell(row=r, column=i, value=value)
        if example:
            c.fill = FILL_EXAMPLE
            c.protection = Protection(locked=True)
        else:
            if label == id_label or label == extras_label or label in readonly_labels:
                c.fill = FILL_GRAY
                c.protection = Protection(locked=True)
            else:
                c.fill = FILL_WHITE
                c.protection = Protection(locked=False)
    if param_cols:
        params = cells.get("__params__", {})
        for spec, col in param_cols:
            value = params.get((spec["key"], spec["sub"]))
            c = ws.cell(row=r, column=col)
            if value is not None and value != "":
                c.value = value
            if example:
                c.fill = FILL_EXAMPLE
                c.protection = Protection(locked=True)
            else:
                c.fill = (param_fill_map or {}).get((spec["key"], spec["sub"]), FILL_WHITE)
                c.protection = Protection(locked=False)


def reserved_count(schema, key: str) -> int:
    """契约 v1.4 new_row_policy.reserved_rows 取本表预留行数（缺字段时用脚本常量兜底）。"""
    policy = schema.get("new_row_policy", {}).get("reserved_rows", {})
    return int(policy.get(key, RESERVED_ROWS[key]))


def write_reserved_rows(ws, first_row: int, count: int, labels: list, *,
                        id_label: str, extras_label: str,
                        param_cols: list | None = None,
                        hint_comment: bool = False,
                        readonly_labels: set | None = None):
    """写「可编辑预留行」（契约 v1.4）。

    · 可见数据列：白底 + unlocked（受同一份 DataValidation 覆盖，下拉照常可用）；
    · 代号列：「代号（自动，别填）」灰底 + locked，浅灰文字给中文占位提示，方案见
      new_row_policy.code_column（不写死具体代号）；②④ 另补中文批注（主键列原有的
      黄色批注会被抹灰覆盖，这里按示例行标记同口径补回）；
    · 高级数据（隐藏）列：locked，内容留空。
    """
    # param_cols: [(spec, 列号)]，只有参数列允许填白，其余可见列同样可编辑
    group_cols = {(col, spec["label"]) for spec, col in (param_cols or [])}
    readonly_labels = readonly_labels or set()
    for r in range(first_row, first_row + count):
        for i, label in enumerate(labels, start=1):
            c = ws.cell(row=r, column=i)
            if label in readonly_labels:
                # 契约 v1.5：行为覆盖列在预留行同样灰底只读（工具自动，策划勿改）
                c.fill = FILL_GRAY
                c.protection = Protection(locked=True)
            elif label == id_label:
                c.value = NEW_ROW_ID_HINT
                c.fill = FILL_GRAY
                c.font = FONT_HINT
                c.alignment = Alignment(horizontal="left", vertical="center")
                c.protection = Protection(locked=True)
                if hint_comment:
                    c.comment = Comment(NEW_ROW_ID_COMMENT, "配置表工具", width=330, height=120)
            elif label == extras_label:
                c.fill = FILL_GRAY
                c.protection = Protection(locked=True)
            elif param_cols and (i, label) in group_cols:
                c.fill = FILL_WHITE
                c.protection = Protection(locked=False)
            else:
                c.fill = FILL_WHITE
                c.protection = Protection(locked=False)


def build_skills(wb, schema, data, maps):
    ws = wb.create_sheet(sheet_title(schema, "skills"))
    labels = [c["label"] for c in schema["columns"]["skills"]]
    style_header(ws, labels)
    add_column_comments(ws, labels, schema["column_notes"]["skills"],
                        {"代号（自动，别填）": "技能代号"})
    id_label = "代号（自动，别填）"

    rows = [example_skill_row(n) for n in range(1, EXAMPLE_ROWS["skills"] + 1)]
    for s in data["skills"]:
        cells, extras = split_skill(s, maps)
        cells[EXTRAS_LABEL] = extras_text(extras)
        rows.append(cells)

    for idx, cells in enumerate(rows, start=2):
        example = idx < 2 + EXAMPLE_ROWS["skills"]
        write_data_row(ws, idx, labels, cells, example=example,
                       id_label=id_label, extras_label=EXTRAS_LABEL)

    # 唯一必填列「技能名」标黄（非示例行），与图例口径一致
    data_start = 2 + EXAMPLE_ROWS["skills"]
    for r in range(data_start, data_start + len(data["skills"])):
        ws.cell(row=r, column=1).fill = FILL_YELLOW
    # 契约 v1.4：数据行之后追加可编辑预留行
    reserved = reserved_count(schema, "skills")
    write_reserved_rows(ws, ws.max_row + 1, reserved, labels,
                        id_label=id_label, extras_label=EXTRAS_LABEL,
                        hint_comment=True)
    autofit_columns(ws, labels)
    set_col_gray_hidden(ws, labels, id_label, EXTRAS_LABEL)
    protect_sheet(ws)
    return ws


def build_parts(wb, schema, data, maps):
    ws = wb.create_sheet(sheet_title(schema, "parts"))
    fixed = [c["label"] for c in schema["columns"]["parts"]]
    specs, groups, shape_dim_keys, gray_keys = plan_param_columns(schema)
    param_enums = param_enum_map(schema)
    fixed_main = [l for l in fixed if l != EXTRAS_LABEL]
    labels = fixed_main + [s["label"] for s in specs] + [EXTRAS_LABEL]
    style_header(ws, labels)
    add_column_comments(ws, labels, schema["column_notes"]["parts"])

    # 展开后的参数列：spec -> 列号
    start = len(fixed_main) + 1
    param_cols = [(spec, start + i) for i, spec in enumerate(specs)]
    for g_start, g_end in groups:
        c1 = get_column_letter(start + g_start)
        c2 = get_column_letter(start + g_end)
        ws.column_dimensions.group(c1, c2, outline_level=1, hidden=False)

    rows = [(example_part_row(n), None)
            for n in range(1, EXAMPLE_ROWS["parts"] + 1)]
    for s in data["skills"]:
        for i, part in enumerate(s["parts"], start=1):
            cells, extras = split_part(part, s["display_name"], i, maps, schema,
                                       set(spec["key"] for spec in specs), param_enums)
            cells[EXTRAS_LABEL] = extras_text(extras)
            rows.append((cells, (part, s)))

    for idx, (cells, meta) in enumerate(rows, start=2):
        example = idx < 2 + EXAMPLE_ROWS["parts"]
        pfill = None
        if not example and meta is not None:
            part, _ = meta
            pfill = {(spec["key"], spec["sub"]):
                     param_fill(part["behavior_id"], spec["key"], schema,
                                shape_dim_keys, gray_keys)
                     for spec in specs}
        write_data_row(ws, idx, labels, cells, example=example,
                       id_label="", extras_label=EXTRAS_LABEL,
                       param_cols=param_cols, param_fill_map=pfill)

    # 契约 v1.4：数据行之后追加可编辑预留行（③ 无代号列，全部可见列可编辑）
    reserved = reserved_count(schema, "parts")
    write_reserved_rows(ws, ws.max_row + 1, reserved, labels,
                        id_label="", extras_label=EXTRAS_LABEL,
                        param_cols=param_cols)
    autofit_columns(ws, labels)
    extras_col = len(labels)
    ws.column_dimensions[get_column_letter(extras_col)].hidden = True
    for r in range(1, ws.max_row + 1):
        ws.cell(row=r, column=extras_col).protection = Protection(locked=True)
    protect_sheet(ws)
    return ws


def build_supports(wb, schema, data, maps, support_name_by_id: dict,
                   conflict_demo: str):
    ws = wb.create_sheet(sheet_title(schema, "supports"))
    labels = [c["label"] for c in schema["columns"]["supports"]]
    style_header(ws, labels)
    add_column_comments(ws, labels, schema["column_notes"]["supports"])
    id_label = "代号（自动，别填）"

    rows = [example_support_row(n, conflict_demo)
            for n in range(1, EXAMPLE_ROWS["supports"] + 1)]
    for s in data["supports"]:
        cells, extras = split_support(s, maps, support_name_by_id)
        cells[EXTRAS_LABEL] = extras_text(extras)
        rows.append(cells)

    # 契约 v1.5：④「行为覆盖」列数据行灰底只读
    readonly = {BO_LABEL}
    for idx, cells in enumerate(rows, start=2):
        example = idx < 2 + EXAMPLE_ROWS["supports"]
        write_data_row(ws, idx, labels, cells, example=example,
                       id_label=id_label, extras_label=EXTRAS_LABEL,
                       readonly_labels=readonly)

    # 唯一必填列「辅助石名」标黄（非示例行），与图例口径一致
    data_start = 2 + EXAMPLE_ROWS["supports"]
    for r in range(data_start, data_start + len(data["supports"])):
        ws.cell(row=r, column=1).fill = FILL_YELLOW
    # 契约 v1.4：数据行之后追加可编辑预留行
    reserved = reserved_count(schema, "supports")
    write_reserved_rows(ws, ws.max_row + 1, reserved, labels,
                        id_label=id_label, extras_label=EXTRAS_LABEL,
                        hint_comment=True, readonly_labels=readonly)
    autofit_columns(ws, labels)
    set_col_gray_hidden(ws, labels, id_label, EXTRAS_LABEL)
    protect_sheet(ws)
    return ws


def set_col_gray_hidden(ws, labels, id_label, extras_label):
    """代号列整列抹灰 + locked，高级数据列整列 locked 且隐藏。

    逐行抹灰会一并覆盖掉该行代号格上原有的内容样式（字体 / 批注 / 填充），因此这里
    同步补回：数据行重新套黄色必填填充（主键列）、示例行与预留行恢复各自的中文批注。
    口径：数据行代号列是「主键列」——黄色＝必须已有代号，且仍 locked；
          示例行 / 预留行（以及表头）代号列才是灰底。
    """
    id_col = labels.index(id_label) + 1
    extras_col = labels.index(extras_label) + 1
    header_comment = ws.cell(row=1, column=id_col).comment
    for r in range(1, ws.max_row + 1):
        idc = ws.cell(row=r, column=id_col)
        old_comment = idc.comment
        idc.fill = FILL_GRAY
        idc.protection = Protection(locked=True)
        if r == 1:
            idc.comment = header_comment
            continue
        first = ws.cell(row=r, column=1).value
        if r > 1 and is_example_marker(first):
            # 示例行：恢复「【示例】照着填」中文批注（原先是主键列的黄色必填批注）
            idc.comment = Comment(EXAMPLE_MARK, "配置表工具", width=330, height=120)
        elif old_comment is not None:
            # 预留行：保留 write_reserved_rows 写入的中文占位批注
            idc.comment = old_comment
            idc.font = FONT_HINT
        else:
            # 数据行：主键列黄色必填的说明补到代号格，别让策划误改
            idc.comment = Comment(KEY_COLUMN_NOTE, "配置表工具", width=330, height=120)
            idc.fill = FILL_YELLOW
        ws.cell(row=r, column=extras_col).protection = Protection(locked=True)
    ws.column_dimensions[get_column_letter(extras_col)].hidden = True


def protect_sheet(ws):
    """开启工作表保护（契约 v1.3 / v1.4）：未解锁单元格一律不可改，允许选格与折叠分组。"""
    ws.protection.sheet = True
    ws.protection.enable()


def build_readme(wb, schema):
    ws = wb.create_sheet(sheet_title(schema, "readme"))
    ws.column_dimensions["A"].width = 6
    for col in "BCDEF":
        ws.column_dimensions[col].width = 20

    ws.merge_cells("A1:F1")
    c = ws["A1"]
    c.value = "技能配置表 · 先看这里"
    c.font = FONT_TITLE
    c.alignment = Alignment(vertical="center")
    ws.row_dimensions[1].height = 36

    row = 3
    lines = [
        "第一步：在「② 技能卡」「③ 效果段」「④ 辅助石」里填好内容：白色格选填、黄色格必填、灰色格不用填；蓝色的几行是【示例】，照着抄、别改。",
        "第二步：保存工作簿，让开发者跑一次「一键收尾」，工具会把这张表变成游戏能读的技能资源（命令与说明见项目根的施工总任务书）。",
        "第三步：打开「⑥ 检查结果」：「问题」列是空的就表示通过；有内容就照「怎么改」那一列改完，再跑一次。",
        "提示：表头格子右上角的小红三角是这一列的说明，鼠标放上去就能看；下拉框里都是中文选项，直接选，别手打。",
        "提示：③ 效果段的「形状」多数情况留空＝用这个效果的默认判定；想指定判定区域才选（圆/线/扇形/环形…），选了以后填它对应的列（半径、长度+宽度、扇形角度、扇形距离…）。",
        "提示：③ 效果段的「增益属性 / 增益运算 / 增益数值」三列要一一对齐：三个 + 列表里的项数必须一样多。",
    ]
    for text in lines:
        ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=6)
        cc = ws.cell(row=row, column=1, value=text)
        cc.font = FONT_BODY
        cc.alignment = Alignment(vertical="center", wrap_text=True)
        ws.row_dimensions[row].height = 26
        row += 1

    row += 1
    ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=6)
    ws.cell(row=row, column=1, value="格子颜色说明（三色图例）").font = FONT_BOLD
    row += 1
    legends = [
        ("黄色", "本行必填：由这个效果 / 形状决定，不填工具会报错。"),
        ("灰色", "不用填：工具也不会读；代号列也是灰色，自动生成、只读，别改。"),
        ("白色", "选填：不影响生成，按需填写。蓝色的整行＝【示例】，照着抄、别改。"),
    ]
    for color, desc in legends:
        cc = ws.cell(row=row, column=1, value=color)
        cc.fill = FILL_LEGEND[color[0]]
        cc.font = FONT_NOTE
        cc.alignment = Alignment(horizontal="center")
        ws.merge_cells(start_row=row, start_column=2, end_row=row, end_column=6)
        dd = ws.cell(row=row, column=2, value=desc)
        dd.font = FONT_NOTE
        dd.alignment = Alignment(vertical="center", wrap_text=True)
        ws.row_dimensions[row].height = 22
        row += 1

    row += 1
    ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=6)
    ws.cell(row=row, column=1, value="五个常见错误").font = FONT_BOLD
    row += 1
    mistakes = [
        "1. 改了灰色的代号列：代号由工具自动生成且锁死，改中文技能名不会改变代号。",
        "2. 伤害类型与基础伤害个数对不上：两列都用 + 分隔，数量必须相同、顺序一一对应。",
        "3. 把多段技能写成一行：一个技能有几段就占「③ 效果段」几行，用「第几段」标 1、2、3…。",
        "4. ③ 的「属于哪个技能」和技能名对不上：直接从下拉里选；手打的内容会被拦下。",
        "5. 增益三列项数不齐：属性 / 运算 / 数值三列都用 + 分隔，项数必须一样多、顺序一一对应。",
    ]
    for text in mistakes:
        ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=6)
        cc = ws.cell(row=row, column=1, value=text)
        cc.font = FONT_NOTE
        cc.alignment = Alignment(vertical="center", wrap_text=True)
        ws.row_dimensions[row].height = 24
        row += 1
    return ws


def build_options(wb, schema, maps):
    ws = wb.create_sheet(sheet_title(schema, "options"))
    names = {
        "behavior": "效果", "shape": "形状", "damage_type": "伤害类型",
        "tag": "标签", "cast_mode": "施法方式", "cost_type": "消耗类型",
        "damage_channel": "命中通道", "op": "运算",
        "stat": "属性（英文标识符）", "stat_labels": "属性",
        # 契约 v1.3：③ 效果段参数列 formation / motion 的中文词表
        "formation": "阵型", "motion": "运动方式",
    }
    defined = {}
    for col, (name, title) in enumerate(names.items(), start=1):
        ws.cell(row=1, column=col, value=title).font = FONT_HEADER
        labels = maps[name]["labels"]
        for r, label in enumerate(labels, start=2):
            ws.cell(row=r, column=col, value=label)
        letter = get_column_letter(col)
        dn = "OPT_" + name.upper()
        ws.parent.defined_names.add(
            DefinedName(dn, attr_text="'%s'!$%s$2:$%s$%d" % (
                sheet_title(schema, "options"), letter, letter, len(labels) + 1))
        )
        defined[name] = dn
        ws.column_dimensions[letter].width = 18
    return ws, defined


def build_report(wb, schema):
    ws = wb.create_sheet(sheet_title(schema, "report"))
    for i, h in enumerate(REPORT_HEADERS, start=1):
        c = ws.cell(row=1, column=i, value=h)
        c.fill = FILL_HEADER
        c.font = FONT_HEADER
        c.alignment = Alignment(horizontal="center")
        ws.column_dimensions[get_column_letter(i)].width = 18
    return ws


# ============================ 即时校验（契约 v1.3） ============================

def _add_dv(ws, letter: str, last_row: int, *, formula: str | None = None,
            block: bool = False, prompt_title: str = "", prompt: str = "",
            error_title: str = "", error: str = ""):
    """加一条中文 DataValidation。

    block=True：下拉拦截，showErrorMessage=True + 中文错误提示（单值枚举列）；
    block=False：允许自由文本，只设 promptTitle/prompt（多值列 / 提示列）。
    formula 为空时不加 list 类型，仅作为「输入提示」挂在单元格上。
    """
    kwargs = {"allow_blank": True, "showErrorMessage": block}
    if formula:
        kwargs["type"] = "list"
        kwargs["formula1"] = "=" + formula
    dv = DataValidation(**kwargs)
    if prompt:
        dv.showInputMessage = True
        dv.promptTitle = prompt_title
        dv.prompt = prompt
    if block:
        dv.errorTitle = error_title or "选项不合法"
        dv.error = error
    dv.add("%s2:%s%d" % (letter, letter, last_row))
    ws.add_data_validation(dv)


def add_validations(wb, schema, defined, skill_name_range: str):
    """按 columns / param_enum_columns / support_ref 给相关列加中文下拉与提示。

    · 单值枚举列：下拉 + showErrorMessage=True +「只能选列表里的中文选项」；
    · 含「+ 分隔」的多值列：保持允许自由文本，只设中文 promptTitle/prompt；
    · ③「属于哪个技能」：引用型下拉，单选、填错即拦（引用 ② 技能卡 技能名数据区）。
    """
    specs, _, _, _ = plan_param_columns(schema)
    spec_by_label = {s["label"]: s for s in specs}
    param_enums = param_enum_map(schema)
    buff_param = schema["buff_spec"]["param"]

    for key in ("skills", "parts", "supports"):
        ws = wb[sheet_title(schema, key)]
        labels = [c.value for c in ws[1]]
        col_defs = {c["label"]: c for c in schema["columns"][key]}
        last_row = max(ws.max_row, 4) + 100
        for col_idx, label in enumerate(labels, start=1):
            if label is None or label == EXTRAS_LABEL:
                continue
            letter = get_column_letter(col_idx)

            # ① ③「属于哪个技能」引用型下拉（契约 v1.3）
            if key == "parts" and label == "属于哪个技能":
                _add_dv(ws, letter, last_row, formula=SKILL_REF_NAME, block=True,
                        prompt_title="属于哪个技能",
                        prompt="从下拉里选「② 技能卡」已有的技能名；一个技能几段就占几行。",
                        error_title="技能名不存在",
                        error="只能从下拉列表里选「② 技能卡」里已有的技能名。")
                continue

            enum_name = None
            single = False
            multi = False
            cdef = col_defs.get(label)
            if cdef is not None:
                type_str = cdef.get("type", "")
                field = cdef.get("field", "")
                enum_name = enum_of_type(type_str)
                if type_str.startswith("enum:"):
                    single = True
                elif type_str.startswith("multienum:"):
                    multi = True
                elif type_str == "float_list" or field in ("flags", "conflicts_with"):
                    multi = True
            elif key == "parts" and label in spec_by_label:
                spec = spec_by_label[label]
                if spec["key"] == buff_param:
                    multi = True
                elif spec["key"] in param_enums:
                    enum_name = param_enums[spec["key"]]
                    single = True

            if not (single or multi):
                continue
            if single:
                if enum_name is None or enum_name not in defined:
                    continue
                _add_dv(ws, letter, last_row, formula=defined[enum_name], block=True,
                        error_title="选项不合法",
                        error=SINGLE_ENUM_ERROR + "；手打的内容不会被识别，请从下拉里选。")
            else:
                prompt = MULTI_PROMPTS.get(label, "可填多个，用 + 分隔。")
                formula = defined[enum_name] if (enum_name in defined) else None
                _add_dv(ws, letter, last_row, formula=formula, block=False,
                        prompt_title=label, prompt=prompt)


def sheet_title(schema, key):
    for s in schema["sheets"]:
        if s["key"] == key:
            return s["title"]
    raise KeyError(key)


def validate_reference_data(data: dict):
    """引用型下拉 / 冲突辅助中文名前置校验：中文名必须唯一、不含 + 号。"""
    skill_names = [s["display_name"] for s in data["skills"]]
    if len(set(skill_names)) != len(skill_names):
        raise ValueError("技能中文名不唯一，无法做引用型下拉与③关联")
    support_name_by_id = {}
    for s in data["supports"]:
        name = s["display_name"]
        if "+" in str(name):
            raise ValueError("辅助石中文名含 + 号，无法无损做「+ 分隔」映射：%s" % name)
        if name in support_name_by_id.values():
            raise ValueError("辅助石中文名不唯一，无法做冲突辅助中文名映射：%s" % name)
        support_name_by_id[s["support_id"]] = name
    return support_name_by_id


def main():
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    data = json.loads(EXPORT_JSON.read_text(encoding="utf-8"))
    # 契约 v1.2：示例行标记以冻结契约为准，脚本常量只是缓存，构造前校验一致
    marker = schema.get("example_row_policy", {}).get("marker", EXAMPLE_PREFIX)
    if marker != EXAMPLE_PREFIX:
        raise ValueError("契约示例行标记与脚本常量不一致：契约=%s 脚本=%s" % (marker, EXAMPLE_PREFIX))
    # 契约 v1.4：预留行数量以契约为准，脚本常量只做一致性校验（不一致直接中文报错）
    got_reserved = dict(schema.get("new_row_policy", {}).get("reserved_rows", {}))
    if got_reserved != RESERVED_ROWS:
        raise ValueError("契约 new_row_policy.reserved_rows 与脚本常量不一致：契约=%s 脚本=%s"
                         % (got_reserved, RESERVED_ROWS))
    maps = build_enum_maps(schema)
    support_name_by_id = validate_reference_data(data)

    # 冲突辅助示例：取真实辅助石里被冲突引用的中文名（示例行只演示，不参与生成）
    conflict_demo = ""
    for s in data["supports"]:
        for cid in s["conflicts_with"]:
            if str(cid) in support_name_by_id:
                conflict_demo = support_name_by_id[str(cid)]
                break
        if conflict_demo:
            break

    wb = Workbook()
    wb.remove(wb.active)

    build_readme(wb, schema)
    build_skills(wb, schema, data, maps)
    build_parts(wb, schema, data, maps)
    build_supports(wb, schema, data, maps, support_name_by_id, conflict_demo)
    _options_ws, defined = build_options(wb, schema, maps)
    build_report(wb, schema)

    # 契约 v1.3：③「属于哪个技能」引用型下拉指向 ② 技能卡 的数据行技能名（跳过示例行）
    # 契约 v1.4：范围一并覆盖「可编辑预留行」——策划新增技能卡后，③ 下拉里能直接选到
    # 它刚填的技能名（空预留行在引用下拉里显示为空，不影响现有内容）。
    skill_start = 2 + EXAMPLE_ROWS["skills"]
    skill_end = skill_start + len(data["skills"]) + reserved_count(schema, "skills") - 1
    skill_range = "'%s'!$A$%d:$A$%d" % (sheet_title(schema, "skills"), skill_start, skill_end)
    wb.defined_names.add(DefinedName(SKILL_REF_NAME, attr_text=skill_range))
    add_validations(wb, schema, defined, skill_range)

    # 「⑤ 可选项」隐藏
    wb[sheet_title(schema, "options")].sheet_state = "hidden"

    WORKBOOK_PATH.parent.mkdir(parents=True, exist_ok=True)
    wb.save(WORKBOOK_PATH)

    total_parts = sum(len(s["parts"]) for s in data["skills"])
    specs, _, _, _ = plan_param_columns(schema)
    print("工作簿已生成：%s" % WORKBOOK_PATH)
    print("页签 %d 个：%s" % (len(wb.sheetnames), " / ".join(wb.sheetnames)))
    print("② 技能卡 %d 行 / ③ 效果段 %d 行 / ④ 辅助石 %d 行（均为数据行；"
          "示例行 %d+%d+%d 行已锁定）" % (
        len(data["skills"]), total_parts, len(data["supports"]),
        EXAMPLE_ROWS["skills"], EXAMPLE_ROWS["parts"], EXAMPLE_ROWS["supports"]))
    print("参数列 %d 个（buff_mods 展开为 %d 条增益列），分 %d 组折叠；"
          "⑤ 可选项 下拉词表 %d 组（含属性中文词表 %d 项）" % (
        len(specs), len(schema["buff_spec"]["columns"]),
        len(plan_param_columns(schema)[1]), len(defined),
        len(maps["stat_labels"]["labels"])))
    print("③ 技能名引用下拉范围 %s；单值枚举列拦截、多值列仅提示；表头批注取自 column_notes" % skill_range)
    print("契约 v1.4 预留行：② %d 行起 %d 行 / ③ %d 行起 %d 行 / ④ %d 行起 %d 行——"
          "可见数据列 unlocked 白底，代号列灰底只读 + 中文占位提示「%s」，"
          "高级数据列仍隐藏且锁定" % (
              skill_start + len(data["skills"]), reserved_count(schema, "skills"),
              EXAMPLE_ROWS["parts"] + 2 + total_parts, reserved_count(schema, "parts"),
              EXAMPLE_ROWS["supports"] + 2 + len(data["supports"]),
              reserved_count(schema, "supports"), NEW_ROW_ID_HINT))


if __name__ == "__main__":
    main()
