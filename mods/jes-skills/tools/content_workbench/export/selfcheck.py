# -*- coding: utf-8 -*-
"""W2 自检：把工作簿「显式中文列 + 隐藏高级数据」独立反解回结构，
与 _tmp/export.json 逐字段比对，输出「零差异」或逐条差异。

本文件刻意不 import build_workbook.py：反解规则依据 schema.json 独立重写一遍，
让「生成」与「回读」互相印证，而不是共用同一段可能同时写错的代码。

另校验：6 页签齐全、中文列头、技能 67 行 / 效果段 95 行 / 辅助石 13 行、
代号唯一且与文件名一致、代号只读、示例行锁定、隐藏列、中文下拉、
参数分组折叠、检查结果空表头。

契约 v1.1 增量：④ 辅助石「属性」列存中文 label，本端按 enums.stat_labels 反查回
英文 value 后再逐字段比对（等价于 W3 的还原规则），并专项校验该列逐行不含英文标识符、
下拉为中文、中文词表可完整映射回 enums.stat 原英文数组。

契约 v1.2 增量：按 example_row_policy.marker「【示例】」识别并跳过示例行（兼容旧文本）；
新增三色专项断言——形状尺寸参数列不再被标黄、黄色格只来自 behavior_required。

契约 v1.3 增量：
  · ③ 阵型 / 运动方式 按 param_enum_columns 存中文，本端独立反解回英文再逐字段比对；
  · ④ 冲突辅助显示辅助石中文名，本端用「辅助石名 → 代号」映射还原后比对；
  · ③ buff_mods 由三条对齐列（buff_spec.columns）承载，逐行按项数还原；
  · ② ③ ④ 表头批注必须逐列等于 column_notes 原文；
  · 示例行 ② 4 / ③ 5 / ④ 4，③ 覆盖「线 + 范围爆发」「引导」「自我增益」；
  · 单值枚举列下拉必须 showErrorMessage=True + 中文错误提示，多值列必须允许自由
    文本且带中文 prompt；③「属于哪个技能」为引用型下拉（OPT_SKILL_NAMES）。

契约 v1.4 增量（P7-A 预留行可编辑）：
  · ②③④ 预留行数量必须逐张等于 new_row_policy.reserved_rows（40 / 90 / 30），且
    必须紧接在数据行之后（② 第 73 行起 / ③ 第 102 行起 / ④ 第 19 行起）；
  · 预留行的可见数据列必须 unlocked（这样才能真的填写新技能），白底、无内容；
  · 预留行与数据行的代号列必须仍 grey + locked 且带中文占位说明（不写死具体代号）；
  · 预留行与示例行的高级数据（隐藏）列必须仍 hidden + locked；
  · 示例行整行仍 locked、表头仍 locked、工作表保护仍开启；
  · 三个断言都带**变异测试**（见 _mutation_cases / mutation_test）：把工作簿副本逐项
    弄坏，确认 main() 真的返回 1 并给出对应中文问题，避免断言写成永远为真。
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.utils import column_index_from_string, get_column_letter

HERE = Path(__file__).resolve().parent
WORKBENCH = HERE.parent
SCHEMA_PATH = WORKBENCH / "schema.json"
EXPORT_JSON = WORKBENCH / "_tmp" / "export.json"
MODULE_DIR = WORKBENCH.parent.parent
WORKBOOK_PATH = MODULE_DIR / "content_src" / "技能配置表.xlsx"
GEMS_DIR = MODULE_DIR / "content" / "gems"

EXAMPLE_MARK = "这是例子，照着填"   # v1.1 及以前的旧文本，仅用于兼容
EXAMPLE_PREFIX = "【示例】"         # 契约 v1.2 example_row_policy.marker 的默认值
EXAMPLE_ROWS = {"skills": 4, "parts": 5, "supports": 4}  # 契约 v1.3
REPORT_HEADERS = ["页签", "行", "列", "问题", "怎么改"]
# 契约 v1.4 new_row_policy.reserved_rows（脚本常量只做一致性校验，实值以契约为准）
RESERVED_ROWS = {"skills": 40, "parts": 90, "supports": 30}
# 预留行「代号（自动，别填）」列的中文占位说明关键字（不校验具体代号）
ID_HINT_KEYS = ("工具生成代号", "自动生成")
EXTRAS_LABEL = "高级数据（工具自动，勿改）"
SKILL_REF_NAME = "OPT_SKILL_NAMES"
SINGLE_ENUM_ERROR = "只能选列表里的中文选项"
GRAY = "00D9D9D9"
YELLOW = "00FFF2CC"               # 三色·本行必填（只按 behavior_required）


def is_example_row(value, prefix: str) -> bool:
    """按契约 v1.2 marker 前缀识别锁定示例行；兼容 v1.1 旧文本以免回归失败。"""
    if value is None:
        return False
    s = str(value)
    return s.startswith(prefix) or s == EXAMPLE_MARK


# ============================ 词表（独立实现） ============================

def build_enum_maps(schema: dict) -> dict:
    maps = {}
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
            "l2v": {l: v for l, v in zip(labels, values)},
            "v2l": {str(v): l for v, l in zip(values, labels)},
        }
    return maps


def dec_enum(name: str, cell, maps: dict):
    """中文 label -> value；词表不认识就原样返回（无损兜底）。"""
    if cell is None or cell == "":
        return None
    key = str(cell)
    if key in maps[name]["l2v"]:
        return maps[name]["l2v"][key]
    return cell


def split_plus(cell) -> list:
    s = "" if cell is None else str(cell)
    if s.strip() == "":
        return []
    return [seg.strip() for seg in s.split("+") if seg.strip() != ""]


def dec_multi(name: str, cell, maps: dict) -> list:
    return [dec_enum(name, seg, maps) for seg in split_plus(cell)]


def enum_of_type(type_str: str):
    if type_str.startswith("enum:") or type_str.startswith("multienum:"):
        return type_str.split(":", 1)[1]
    return None


def param_enum_map(schema: dict) -> dict:
    return {k: v for k, v in schema.get("param_enum_columns", {}).items()
            if k != "note" and isinstance(v, str)}


# ============================ 列布局规划（独立实现） ============================

def plan_param_columns(schema: dict):
    """与生成端同规则推导参数列顺序，并把 buff_mods 展开成 buff_spec 三条对齐列。

    返回 specs: [{"key","sub","label","group"}]。
    """
    shape_keys_set = {k for ks in schema["shape_keys"].values() for k in ks}
    behavior_req_set = {k for ks in schema["behavior_required"].values() for k in ks}
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
            for coldef in schema["buff_spec"]["columns"]:
                specs.append({"key": key, "sub": coldef["key"],
                              "label": coldef["label"], "group": group})
        else:
            specs.append({"key": key, "sub": None,
                          "label": schema["param_labels"][key], "group": group})
    return specs, shape_keys_set, behavior_req_set - shape_keys_set


def expected_labels(schema: dict) -> dict:
    labels = {}
    for key in ("skills", "parts", "supports"):
        labels[key] = [c["label"] for c in schema["columns"][key]]
    specs, _, _ = plan_param_columns(schema)
    labels["parts"] = ([l for l in labels["parts"] if l != EXTRAS_LABEL]
                       + [s["label"] for s in specs] + [EXTRAS_LABEL])
    return labels


# ============================ 逐字段差异 ============================

def canon(x):
    """数值统一成 float（吸收 int/float 表示差异），结构递归归一。"""
    if isinstance(x, dict):
        return {k: canon(v) for k, v in x.items()}
    if isinstance(x, list):
        return [canon(v) for v in x]
    if isinstance(x, bool):
        return ("bool", x)
    if isinstance(x, (int, float)):
        return float(x)
    return x


def diff(a, b, path="") -> list:
    """返回 (路径, 回读值, 原始值) 差异清单，逐字段定位。"""
    out = []
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            p = f"{path}.{k}" if path else k
            if k not in a:
                out.append((p, "<缺失>", b[k]))
            elif k not in b:
                out.append((p, a[k], "<多余>"))
            else:
                out.extend(diff(a[k], b[k], p))
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append((path + ".长度", len(a), len(b)))
        for i, (x, y) in enumerate(zip(a, b)):
            out.extend(diff(x, y, f"{path}[{i}]"))
    else:
        if canon(a) != canon(b):
            out.append((path if path else "<根>", a, b))
    return out


# ============================ 反解：工作簿行 -> 记录 ============================

def row_dict(ws, r: int, headers: list) -> dict:
    return {h: ws.cell(row=r, column=i + 1).value for i, h in enumerate(headers)}


def decode_skill(row: dict, maps: dict) -> dict:
    rec = {
        "display_name": row["技能名"],
        "gem_id": row["代号（自动，别填）"],
        "cast_mode": dec_enum("cast_mode", row["施法方式"], maps),
        "cost_type": dec_enum("cost_type", row["消耗类型"], maps),
        "base_cost": row["消耗数值"],
        "base_cooldown": row["冷却（秒）"],
        "base_cast_time": row["前摇（秒）"],
        "max_charges": row["最多充能"],
        "charge_recharge_time": row["充能回复（秒）"],
        "level_scaling": {
            "per_level": row["每级变强"],
            "knee_level": row["成长拐点等级"],
            "per_level_late": row["拐点后每级变强"],
        },
        "tags": dec_multi("tag", row["标签（用 + 分隔）"], maps),
        "allowed_support_tags": dec_multi("tag", row["允许的辅助标签"], maps),
    }
    extras = json.loads(row[EXTRAS_LABEL])
    rec.update(extras)  # 补齐 icon / parts 等未被显式列承载的字段
    return rec


def decode_support(row: dict, maps: dict, support_name_to_id: dict) -> dict:
    rec = {
        "display_name": row["辅助石名"],
        "support_id": row["代号（自动，别填）"],
        "require_tags": dec_multi("tag", row["需要的标签（全部，+ 分隔）"], maps),
        "require_any_tags": dec_multi("tag", row["需要的标签（任一，+ 分隔）"], maps),
        "add_tags": dec_multi("tag", row["添加标签"], maps),
        "exclude_tags": dec_multi("tag", row["排除标签"], maps),
        "cost_multiplier": row["消耗倍率"],
        "flags": split_plus(row["特性（+ 分隔）"]),
        # 契约 v1.3 support_ref：中文辅助石名 -> 英文 support_id
        "conflicts_with": [support_name_to_id.get(seg, seg)
                           for seg in split_plus(row["冲突辅助（+ 分隔）"])],
    }
    extras = json.loads(row[EXTRAS_LABEL])
    rec.update(extras)  # 补齐 stat_modifiers（完整数组）/ behavior_overrides

    # 按 schema.extras_policy.generate_rule：显式列非空时以显式列为准，覆盖第 0 项
    mods = list(rec.get("stat_modifiers", []))
    if mods:
        m0 = dict(mods[0])
        if row["属性"] not in (None, ""):
            m0["stat"] = dec_enum("stat_labels", row["属性"], maps)
        if row["运算"] not in (None, ""):
            m0["op"] = dec_enum("op", row["运算"], maps)
        if row["数值"] not in (None, ""):
            m0["value"] = row["数值"]
        mods[0] = m0
        rec["stat_modifiers"] = mods
    return rec


def decode_part_full(row: dict, maps: dict, specs: list, schema: dict):
    """独立反解一条效果段；返回 (记录, 提示列表)。"""
    warns = []
    buff_param = schema["buff_spec"]["param"]
    buff_cols = schema["buff_spec"]["columns"]
    param_enums = param_enum_map(schema)

    ks = split_plus(row["伤害类型（用 + 分隔）"])
    vs = split_plus(row["基础伤害（用 + 分隔，与上一列顺序对应）"])
    if len(ks) != len(vs):
        warns.append("伤害类型 %d 项 / 基础伤害 %d 项，数量不一致" % (len(ks), len(vs)))
    explicit_bd = {}
    for i, k in enumerate(ks):
        explicit_bd[dec_enum("damage_type", k, maps)] = float(vs[i]) if i < len(vs) else 0.0

    explicit_bp = {}
    if row["形状"] not in (None, ""):
        explicit_bp["shape"] = dec_enum("shape", row["形状"], maps)
    for spec in specs:
        if spec["key"] == buff_param:
            continue
        cell = row.get(spec["label"])
        if cell is None or cell == "":
            continue
        if spec["key"] in param_enums:
            explicit_bp[spec["key"]] = dec_enum(param_enums[spec["key"]], cell, maps)
        else:
            explicit_bp[spec["key"]] = cell

    # 契约 v1.3：三条对齐列 -> buff_mods（stat/op/value 中文还原成英文）
    buff_cells = {c["key"]: row.get(c["label"]) for c in buff_cols}
    buff_any = any(v not in (None, "") for v in buff_cells.values())
    if buff_any:
        stat_l = split_plus(buff_cells.get("stat"))
        op_l = split_plus(buff_cells.get("op"))
        val_l = split_plus(buff_cells.get("value"))
        counts = {len(stat_l), len(op_l), len(val_l)}
        if len(counts) != 1:
            warns.append("增益三列项数不一致：属性 %d / 运算 %d / 数值 %d" % (
                len(stat_l), len(op_l), len(val_l)))
        mods = []
        for i in range(min(len(stat_l), len(op_l), len(val_l))):
            mods.append({
                "stat": dec_enum("stat_labels", stat_l[i], maps),
                "op": dec_enum("op", op_l[i], maps),
                "value": float(val_l[i]),
            })
        explicit_bp[buff_param] = mods

    extras = json.loads(row[EXTRAS_LABEL])
    # 显式列为准：先铺 __extras，再用显式列覆盖同名字段
    behavior_params = dict(extras.get("behavior_params", {}))
    behavior_params.update(explicit_bp)
    base_damage = dict(extras.get("base_damage", {}))
    base_damage.update(explicit_bd)

    rec = {
        "behavior_id": dec_enum("behavior", row["效果"], maps),
        "damage_effectiveness": row["伤害效用"],
        "damage_channel": dec_enum("damage_channel", row["命中通道"], maps),
        "base_damage": base_damage,
        "behavior_params": behavior_params,
    }
    for k, v in extras.items():
        if k not in ("behavior_params", "base_damage"):
            rec[k] = v
    return rec, warns


def expected_validations(schema: dict) -> tuple:
    """独立推导每张表应有哪些「单值枚举 / 多值 / 引用型」校验列。"""
    specs, _, _ = plan_param_columns(schema)
    spec_by_label = {s["label"]: s for s in specs}
    param_enums = param_enum_map(schema)
    buff_param = schema["buff_spec"]["param"]
    single, multi, refs = [], [], []
    for key in ("skills", "parts", "supports"):
        col_defs = {c["label"]: c for c in schema["columns"][key]}
        for label in expected_labels(schema)[key]:
            if label == EXTRAS_LABEL:
                continue
            if key == "parts" and label == "属于哪个技能":
                refs.append((key, label))
                continue
            cdef = col_defs.get(label)
            if cdef is not None:
                t = cdef.get("type", "")
                field = cdef.get("field", "")
                if t.startswith("enum:"):
                    single.append((key, label, enum_of_type(t)))
                elif t.startswith("multienum:"):
                    multi.append((key, label, enum_of_type(t)))
                elif t == "float_list" or field in ("flags", "conflicts_with"):
                    multi.append((key, label, None))
            elif key == "parts" and label in spec_by_label:
                spec = spec_by_label[label]
                if spec["key"] == buff_param:
                    multi.append((key, label, None))
                elif spec["key"] in param_enums:
                    single.append((key, label, param_enums[spec["key"]]))
    return single, multi, refs


def dvs_for_column(ws, col_idx: int) -> list:
    letter = get_column_letter(col_idx)
    out = []
    for dv in ws.data_validations.dataValidation:
        if re.match(r"^%s\d" % re.escape(letter), str(dv.sqref)):
            out.append(dv)
    return out


# ============================ 主流程 ============================

def main() -> int:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    data = json.loads(EXPORT_JSON.read_text(encoding="utf-8"))
    marker = schema.get("example_row_policy", {}).get("marker", EXAMPLE_PREFIX)
    maps = build_enum_maps(schema)
    wb = load_workbook(WORKBOOK_PATH)

    # 契约 v1.4：预留行数量以契约为准；脚本常量不一致就中文报错（防契约漂移）
    reserved_of = dict(schema.get("new_row_policy", {}).get("reserved_rows", {}))
    rv_filled: list = []          # 预留区里被策划填了内容的行（= 新增技能卡，读侧接管）
    problems_reserved = ("契约缺少 new_row_policy.reserved_rows，无法校验预留行"
                         if not reserved_of else None)

    titles = [s["title"] for s in schema["sheets"]]
    hidden_titles = {s["title"] for s in schema["sheets"] if s["hidden"]}
    sheet_of = {s["key"]: s["title"] for s in schema["sheets"]}
    problems: list[str] = []
    print("=== W2 自检（export/selfcheck.py）契约 v1.3 ===")

    # [1] 6 页签齐全
    ok1 = list(wb.sheetnames) == titles
    print("[1] 页签齐全：%d/%d 个 → %s" % (len(wb.sheetnames), len(titles),
          " / ".join(wb.sheetnames) if ok1 else "顺序或名称不符"))
    if not ok1:
        problems.append("页签不齐或顺序不符")
    for h in hidden_titles:
        if h in wb.sheetnames and wb[h].sheet_state == "visible":
            problems.append("隐藏页签 %s 未隐藏" % h)

    labels = expected_labels(schema)

    # 契约 v1.4：预留行边界（数据行 = 示例行之后、预留行之前）
    exp_parts = sum(len(s["parts"]) for s in data["skills"])
    reserved_of_ = {k: int(reserved_of.get(k, RESERVED_ROWS[k]))
                    for k in ("skills", "parts", "supports")}
    data_end = {
        "skills": 1 + EXAMPLE_ROWS["skills"] + len(data["skills"]),
        "parts": 1 + EXAMPLE_ROWS["parts"] + exp_parts,
        "supports": 1 + EXAMPLE_ROWS["supports"] + len(data["supports"]),
    }

    def is_reserved_row(key: str, ws, r: int) -> bool:
        """契约 v1.4 预留行：数据行之后、预留区之内，且可见数据列全空（且不是示例行）。

        只认「整行可见数据列全空」的预留行——策划往预留行里真的填了新技能卡之后，
        该行就变成新数据行，由读侧（W3）接手校验，而不是永远被当成空预留行跳过。
        """
        start = data_end[key] + 1
        end = start + reserved_of_[key] - 1
        if not (start <= r <= end):
            return False
        heads = [c.value for c in ws[1]]
        for ci, h in enumerate(heads, start=1):
            if h == EXTRAS_LABEL or h == "代号（自动，别填）":
                continue
            if ws.cell(row=r, column=ci).value not in (None, ""):
                return False
        return True

    # [2] 列头全中文且与契约一致（③ 含 buff_spec 三条对齐列）
    col_count = 0
    eng_cols = []
    for key in ("skills", "parts", "supports"):
        ws = wb[sheet_of[key]]
        heads = [c.value for c in ws[1]]
        col_count += len(heads)
        if heads != labels[key]:
            problems.append("%s 列头与契约不一致" % key)
        for h in heads:
            if h and re.search(r"[A-Za-z]", str(h)):
                eng_cols.append((key, h))
    print("[2] 列头全中文且与契约一致：3 张数据表共 %d 列，含英文标识符的列 %d 个" % (
        col_count, len(eng_cols)))
    if eng_cols:
        problems.append("列头出现英文标识符：%s" % eng_cols)

    # [3] 数据行计数（跳过示例行）+ 示例行数量
    def data_rows(key):
        """数据行 = 示例行之后、预留区之前；预留区里的空行不计入数据行。"""
        ws = wb[sheet_of[key]]
        heads = [c.value for c in ws[1]]
        rows = []
        ex_count = 0
        for r in range(2, ws.max_row + 1):
            if r <= 1 + EXAMPLE_ROWS[key] and is_example_row(
                    ws.cell(row=r, column=1).value, marker):
                ex_count += 1
                continue
            if is_reserved_row(key, ws, r):
                continue
            rows.append((r, row_dict(ws, r, heads)))
        return ws, heads, rows, ex_count

    ws_sk, heads_sk, rows_sk, ex_sk = data_rows("skills")
    ws_pt, heads_pt, rows_pt, ex_pt = data_rows("parts")
    ws_sp, heads_sp, rows_sp, ex_sp = data_rows("supports")
    ok3 = (len(rows_sk) == len(data["skills"]) == 67
           and len(rows_sp) == len(data["supports"]) == 13
           and len(rows_pt) == exp_parts == 95)
    ok3 = ok3 and (ex_sk, ex_pt, ex_sp) == (4, 5, 4)
    print("[3] 数据行计数：技能 %d / 效果段 %d / 辅助石 %d（期望 67/95/13）；"
          "示例行 %d+%d+%d（期望 4/5/4）%s" % (
              len(rows_sk), len(rows_pt), len(rows_sp), ex_sk, ex_pt, ex_sp,
              "✓" if ok3 else "✗"))
    if not ok3:
        problems.append("数据行或示例行数不符")

    if problems_reserved:
        problems.append(problems_reserved)
    if reserved_of != RESERVED_ROWS:
        problems.append("契约 new_row_policy.reserved_rows=%s 与脚本常量 %s 不一致" % (
            reserved_of, RESERVED_ROWS))

    # [3b] 契约 v1.4 预留行专项：数量 / 位置 / 可编辑 / 代号列 / 高级数据列 / 示例行 / 表头
    sheet_of_ws = {"skills": ws_sk, "parts": ws_pt, "supports": ws_sp}
    heads_of = {"skills": heads_sk, "parts": heads_pt, "supports": heads_sp}
    last_data_row = dict(data_end)
    rv_count, rv_unlocked, rv_errors = {}, {}, []
    for key in ("skills", "parts", "supports"):
        ws, heads = sheet_of_ws[key], heads_of[key]
        want = int(reserved_of.get(key, RESERVED_ROWS[key]))
        start = last_data_row[key] + 1
        end = start + want - 1
        id_label = "代号（自动，别填）"
        id_col = heads.index(id_label) + 1 if id_label in heads else None
        extras_col = heads.index(EXTRAS_LABEL) + 1
        editable = [ci for ci, h in enumerate(heads, start=1)
                    if h != EXTRAS_LABEL and ci != id_col]
        meas_count, meas_unlocked = 0, 0
        for r in range(start, ws.max_row + 1):
            if all(ws.cell(row=r, column=ci).value in (None, "")
                   for ci in editable) and not is_example_row(
                       ws.cell(row=r, column=1).value, marker):
                meas_count += 1
            else:
                break
        for r in range(start, end + 1):
            cells = [ws.cell(row=r, column=ci) for ci in editable]
            if any(c.value not in (None, "") for c in cells):
                # 策划往预留行填了新内容 = 新增技能卡，读侧接管；这里只提示、不判错
                rv_filled.append("%s 第%d行" % (key, r))
                continue
            if any(c.protection.locked for c in cells):
                rv_errors.append("%s 第%d行存在仍锁定的可见列" % (key, r))
            if any(str(c.fill.fgColor.rgb) == GRAY for c in cells):
                rv_errors.append("%s 第%d行可见列出现灰底（应为白底）" % (key, r))
            if id_col is not None:
                idc = ws.cell(row=r, column=id_col)
                if not idc.protection.locked:
                    rv_errors.append("%s 第%d行代号列被解锁" % (key, r))
                if str(idc.fill.fgColor.rgb) != GRAY:
                    rv_errors.append("%s 第%d行代号列不是灰底" % (key, r))
                text = "" if idc.value is None else str(idc.value)
                if not any(k in text for k in ID_HINT_KEYS):
                    rv_errors.append("%s 第%d行代号列缺中文占位说明：%r" % (key, r, text))
                if not (idc.comment and any(k in idc.comment.text for k in ID_HINT_KEYS)):
                    rv_errors.append("%s 第%d行代号列缺中文批注" % (key, r))
            exc = ws.cell(row=r, column=extras_col)
            if not exc.protection.locked:
                rv_errors.append("%s 第%d行高级数据列被解锁" % (key, r))
            if not _col_hidden(ws, extras_col):
                rv_errors.append("%s 第%d行高级数据列可见" % (key, r))
        rv_count[key] = meas_count
        rv_unlocked[key] = len(editable)
        if meas_count != want:
            rv_errors.append("%s 预留行实测 %d 行 ≠ 契约 %d 行" % (key, meas_count, want))
        if ws.max_row != end and any(ws.cell(row=r, column=1).value
                                     for r in range(end + 1, ws.max_row + 1)):
            rv_errors.append("%s 预留行之后仍有 %d 行多余内容" % (key, ws.max_row - end))
    print("[3b] 契约 v1.4 预留行专项：② 第%d行起 %d 行（可编辑列 %d）/ "
          "③ 第%d行起 %d 行（可编辑列 %d）/ ④ 第%d行起 %d 行（可编辑列 %d）；异常 %d → %s" % (
              last_data_row["skills"] + 1, rv_count.get("skills", 0), rv_unlocked.get("skills", 0),
              last_data_row["parts"] + 1, rv_count.get("parts", 0), rv_unlocked.get("parts", 0),
              last_data_row["supports"] + 1, rv_count.get("supports", 0),
              rv_unlocked.get("supports", 0), len(rv_errors),
              "✓" if not rv_errors else "✗"))
    if rv_filled:
        print("      预留区已有内容（新增技能卡，交由读侧 W3 校验）：%s" % rv_filled[:10])
    if rv_errors:
        for e in rv_errors[:10]:
            print("      - " + e)
        problems.append("预留行不符合契约 v1.4 %d 处" % len(rv_errors))

    # [4] 代号唯一
    skill_ids = [row["代号（自动，别填）"] for _, row in rows_sk]
    support_ids = [row["代号（自动，别填）"] for _, row in rows_sp]
    ok4 = len(set(skill_ids)) == len(skill_ids) == 67 and len(set(support_ids)) == len(support_ids) == 13
    print("[4] 代号唯一：技能 %d 个（唯一 %d）/ 辅助 %d 个（唯一 %d）%s" % (
        len(skill_ids), len(set(skill_ids)), len(support_ids), len(set(support_ids)),
        "✓" if ok4 else "✗"))
    if not ok4:
        problems.append("代号不唯一")

    # [5] 代号与文件名一致（同时核对真实目录与 A 记录的 source_files）
    active_files = {p.stem for p in (GEMS_DIR / "active").glob("*.tres")}
    support_files = {p.stem for p in (GEMS_DIR / "supports").glob("*.tres")}
    src = data["source_files"]
    bad_src = [i for i in skill_ids + support_ids if src.get(i) != i + ".tres"]
    ok5 = (set(skill_ids) == active_files and set(support_ids) == support_files
           and not bad_src and len(src) == 80)
    print("[5] 代号与文件名一致：active 目录 %d 个 / supports 目录 %d 个 / source_files %d 条，不匹配 %d 个 %s" % (
        len(active_files), len(support_files), len(src), len(bad_src), "✓" if ok5 else "✗"))
    if not ok5:
        problems.append("代号与文件名不一致")

    # [6] 逐字段比对（独立反解）
    specs, shape_dim_keys, gray_keys = plan_param_columns(schema)
    orig_skill = {s["gem_id"]: s for s in data["skills"]}
    orig_support = {s["support_id"]: s for s in data["supports"]}
    by_name = {s["display_name"]: s for s in data["skills"]}
    support_name_to_id = {s["display_name"]: s["support_id"] for s in data["supports"]}
    all_diffs: list[str] = []
    warns_all: list[str] = []

    for r, row in rows_sk:
        gid = row["代号（自动，别填）"]
        if gid not in orig_skill:
            all_diffs.append("② 技能卡 第%d行：代号 %s 找不到原始记录" % (r, gid))
            continue
        try:
            rec = decode_skill(row, maps)
        except Exception as exc:  # 结构损坏（如示例行被改成真实行）也应中文报错，不崩
            all_diffs.append("② 技能卡 第%d行(%s) 反解失败：%s" % (r, gid, exc))
            continue
        for p, a, b in diff(rec, orig_skill[gid]):
            all_diffs.append("② 技能卡 第%d行(%s) %s：回读=%r 原始=%r" % (r, gid, p, a, b))

    for r, row in rows_sp:
        sid = row["代号（自动，别填）"]
        if sid not in orig_support:
            all_diffs.append("④ 辅助石 第%d行：代号 %s 找不到原始记录" % (r, sid))
            continue
        try:
            rec = decode_support(row, maps, support_name_to_id)
        except Exception as exc:
            all_diffs.append("④ 辅助石 第%d行(%s) 反解失败：%s" % (r, sid, exc))
            continue
        for p, a, b in diff(rec, orig_support[sid]):
            all_diffs.append("④ 辅助石 第%d行(%s) %s：回读=%r 原始=%r" % (r, sid, p, a, b))

    name_unique = len(by_name) == len(data["skills"])
    if not name_unique:
        all_diffs.append("技能中文名不唯一，③ 效果段 无法可靠关联")
    for r, row in rows_pt:
        parent = row["属于哪个技能"]
        idx = row["第几段"]
        if parent not in by_name:
            all_diffs.append("③ 效果段 第%d行：关联技能名 %r 不存在" % (r, parent))
            continue
        s = by_name[parent]
        if not isinstance(idx, int) or not (1 <= idx <= len(s["parts"])):
            all_diffs.append("③ 效果段 第%d行：第几段 %r 越界" % (r, idx))
            continue
        try:
            rec, warns = decode_part_full(row, maps, specs, schema)
        except Exception as exc:
            all_diffs.append("③ 效果段 第%d行(%s 第%s段) 反解失败：%s" % (
                r, parent, idx, exc))
            continue
        for w in warns:
            warns_all.append("③ 效果段 第%d行：%s" % (r, w))
        for p, a, b in diff(rec, s["parts"][idx - 1]):
            all_diffs.append("③ 效果段 第%d行(%s 第%s段) %s：回读=%r 原始=%r" % (
                r, parent, idx, p, a, b))

    compared = len(rows_sk) + len(rows_sp) + len(rows_pt)
    if all_diffs:
        print("[6] 逐字段比对：%d 行，发现 %d 处差异：" % (compared, len(all_diffs)))
        for line in all_diffs[:40]:
            print("    - " + line)
        if len(all_diffs) > 40:
            print("    …… 其余 %d 处省略" % (len(all_diffs) - 40))
        problems.append("逐字段比对有 %d 处差异" % len(all_diffs))
    else:
        print("[6] 逐字段比对：%d 行（技能 %d + 效果段 %d + 辅助石 %d）全部还原 → 零差异 ✓" % (
            compared, len(rows_sk), len(rows_pt), len(rows_sp)))
    if warns_all:
        print("    多值列长度提示 %d 条：" % len(warns_all))
        for w in warns_all[:10]:
            print("    - " + w)
        problems.append("多值列长度不一致 %d 条" % len(warns_all))

    # [6a] 契约 v1.1 属性列专项：逐行全中文、下拉中文、中文词表可映射回原英文 value
    stat_col = heads_sp.index("属性") + 1
    stat_letter = get_column_letter(stat_col)
    sl = maps["stat_labels"]
    stat_filled = 0
    ascii_hits, unmapped = [], []
    for r in range(2, ws_sp.max_row + 1):
        v = ws_sp.cell(row=r, column=stat_col).value
        if v in (None, ""):
            continue
        stat_filled += 1
        if re.search(r"[A-Za-z]", str(v)):
            ascii_hits.append((r, v))
        if v not in sl["l2v"]:
            unmapped.append((r, v))

    opt = wb[sheet_of["options"]]
    opt_heads = [c.value for c in opt[1]]
    opt_stat_col = opt_heads.index("属性") + 1
    opt_words = [opt.cell(row=r, column=opt_stat_col).value
                 for r in range(2, opt.max_row + 1)]
    opt_words = [v for v in opt_words if v not in (None, "")]
    zh_words_ok = (opt_words == sl["labels"]
                   and all(not re.search(r"[A-Za-z]", str(v)) for v in opt_words))
    cover_ok = (len(sl["labels"]) == 23
                and set(sl["l2v"].values()) == set(schema["enums"]["stat"]))
    stat_dv = [dv for dv in ws_sp.data_validations.dataValidation
               if dv.type == "list" and str(dv.sqref).startswith(stat_letter + "2:")]
    dv_ok = (len(stat_dv) == 1
             and "STAT_LABELS" in str(stat_dv[0].formula1).upper()
             and str(stat_dv[0].formula1).lstrip("=") in wb.defined_names)

    spec_items = [
        ("属性列逐行（含 %d 行示例）共 %d 个有值单元格，均不含英文标识符" % (
            ex_sp, stat_filled), not ascii_hits),
        ("每个中文 label 均可依 stat_labels 映射回原英文 value（不可映射 %d 个）" % len(unmapped),
         not unmapped),
        ("⑤ 可选项 已补 23 项中文属性词表且全中文", zh_words_ok),
        ("中文词表 value 与 enums.stat 原英文数组 23 项一一对应", cover_ok),
        ("属性列下拉引用中文词表 OPT_STAT_LABELS", dv_ok),
    ]
    print("[6a] 属性列专项（契约 v1.1）：")
    for name, ok in spec_items:
        print("    · %s：%s" % (name, "✓" if ok else "✗"))
        if not ok:
            problems.append("属性列专项：" + name)
    if ascii_hits:
        print("    含英文标识符的行：%s" % ascii_hits[:10])
    if unmapped:
        print("    不可映射的行：%s" % unmapped[:10])

    # [6b] 契约 v1.2 三色专项：形状尺寸参数列一律白色、不再因 shape_keys 标黄
    dim_cols = {}
    for k in shape_dim_keys:
        label = schema["param_labels"].get(k)
        if label in heads_pt:
            dim_cols[label] = heads_pt.index(label) + 1
    spec_by_label = {s["label"]: s for s in specs}
    dim_yellow = []
    for r in range(2, ws_pt.max_row + 1):
        for label, col in dim_cols.items():
            if str(ws_pt.cell(row=r, column=col).fill.fgColor.rgb) == YELLOW:
                dim_yellow.append((r, label))
    # 顺带验证「黄色只按 behavior_required」：黄色格必须都在该行行为必填键内
    b_l2v = maps["behavior"]["l2v"]
    eff_col = heads_pt.index("效果") + 1
    yellow_total = 0
    bad_yellow = []
    for r in range(2, ws_pt.max_row + 1):
        if is_example_row(ws_pt.cell(row=r, column=1).value, marker):
            continue
        eff = ws_pt.cell(row=r, column=eff_col).value
        bval = b_l2v.get(str(eff), eff)
        req = set(schema["behavior_required"].get(str(bval), [])) - shape_dim_keys
        for label, spec in spec_by_label.items():
            col = heads_pt.index(label) + 1
            if str(ws_pt.cell(row=r, column=col).fill.fgColor.rgb) == YELLOW:
                yellow_total += 1
                if spec["key"] not in req:
                    bad_yellow.append((r, label, spec["key"]))
    print("[6b] 三色专项（契约 v1.2）：③ 效果段 %d 个形状尺寸参数列 × %d 行，标黄 %d 处 → %s" % (
        len(dim_cols), ws_pt.max_row - 1, len(dim_yellow), "✓" if not dim_yellow else "✗"))
    print("      数据行黄色参数格 %d 个，越出 behavior_required 的 %d 个 → %s" % (
        yellow_total, len(bad_yellow), "✓" if not bad_yellow else "✗"))
    if dim_yellow:
        print("      误标黄的位置：%s" % dim_yellow[:10])
        problems.append("形状尺寸参数列被标黄 %d 处" % len(dim_yellow))
    if bad_yellow:
        print("      越界黄色格：%s" % bad_yellow[:10])
        problems.append("黄色格越出 behavior_required %d 个" % len(bad_yellow))

    # [6c] 契约 v1.3 中文值专项：阵型 / 运动方式 / 冲突辅助 / 增益三列
    param_enums = param_enum_map(schema)
    buff_param = schema["buff_spec"]["param"]
    buff_labels = [c["label"] for c in schema["buff_spec"]["columns"]]
    buff_keys = [c["key"] for c in schema["buff_spec"]["columns"]]
    formation_cells, motion_cells = {}, {}
    ascii_bad = []
    for label, enum_name in (("阵型", param_enums.get("formation")),
                             ("运动方式", param_enums.get("motion"))):
        col = heads_pt.index(label) + 1
        for r, row in rows_pt:
            v = ws_pt.cell(row=r, column=col).value
            if v in (None, ""):
                continue
            if re.search(r"[A-Za-z]", str(v)) or v not in maps[enum_name]["l2v"]:
                ascii_bad.append((label, r, v))
            bucket = formation_cells if label == "阵型" else motion_cells
            bucket[v] = bucket.get(v, 0) + 1
    # 期望中文值直接由原始数据反推（独立于生成端）
    exp_form, exp_motion = {}, {}
    for s in data["skills"]:
        for part in s["parts"]:
            bp = part["behavior_params"]
            for key, enum_name, bucket in (
                    ("formation", "formation", exp_form),
                    ("motion", "motion", exp_motion)):
                if key in bp:
                    lbl = maps[enum_name]["v2l"].get(str(bp[key]), bp[key])
                    bucket[lbl] = bucket.get(lbl, 0) + 1
    form_ok = (formation_cells == exp_form and motion_cells == exp_motion and not ascii_bad)
    print("[6c] 契约 v1.3 中文值专项：")
    print("    · ③ 阵型中文值 %s（期望 %s）/ 运动方式中文值 %s（期望 %s）：%s" % (
        formation_cells, exp_form, motion_cells, exp_motion, "✓" if form_ok else "✗"))
    if not form_ok:
        problems.append("阵型/运动方式未全中文或与原始值不符")
    if ascii_bad:
        print("      含英文/非法值的单元格：%s" % ascii_bad[:10])

    # ④ 冲突辅助：中文辅助石名、可还原、无英文
    conflict_col = heads_sp.index("冲突辅助（+ 分隔）") + 1
    conf_cells, conf_ok, conf_count = [], True, 0
    for r, row in rows_sp:
        cell = ws_sp.cell(row=r, column=conflict_col).value
        orig = orig_support[row["代号（自动，别填）"]]["conflicts_with"]
        names = split_plus(cell)
        if orig:
            conf_count += 1
            conf_cells.append((r, cell))
            if len(names) != len(orig) or any(n not in support_name_to_id for n in names):
                conf_ok = False
            if re.search(r"[A-Za-z]", str(cell)):
                conf_ok = False
        elif names:
            conf_ok = False
    exp_conf = sum(1 for s in data["supports"] if s["conflicts_with"])
    conf_ok = conf_ok and conf_count == exp_conf and conf_count > 0
    print("    · ④ 冲突辅助显示辅助石中文名：%d 行（期望 %d），无英文代号 %s" % (
        conf_count, exp_conf, "✓" if conf_ok else "✗"))
    if not conf_ok:
        problems.append("冲突辅助未全部显示中文辅助石名")
    else:
        print("      中文值：%s" % conf_cells)
    if conf_cells:
        print("      还原为代号：%s" % [
            (r, [support_name_to_id.get(n, n) for n in split_plus(c)]) for r, c in conf_cells])

    # ③ 增益三列：列头一致、7 条自我增益逐行三列项数对齐、中文属性/运算、数值可解析
    buff_heads_ok = all(l in heads_pt for l in buff_labels)
    # 原始 buff_mods 行（独立从 export.json 取）
    exp_buff = {}
    for s in data["skills"]:
        for i, part in enumerate(s["parts"], start=1):
            mods = part["behavior_params"].get(buff_param)
            if mods:
                exp_buff[(s["display_name"], i)] = mods
    got_buff, buff_bad, buff_items = {}, [], 0
    for r, row in rows_pt:
        cells = [ws_pt.cell(row=r, column=heads_pt.index(l) + 1).value for l in buff_labels]
        if all(v in (None, "") for v in cells):
            continue
        key = (row["属于哪个技能"], row["第几段"])
        got_buff[key] = cells
        parts_lists = [split_plus(v) for v in cells]
        counts = {len(x) for x in parts_lists}
        if len(counts) != 1:
            buff_bad.append((r, "三列项数不一致", [len(x) for x in parts_lists]))
            continue
        n = len(parts_lists[0])
        buff_items += n
        for i in range(n):
            if parts_lists[0][i] not in maps["stat_labels"]["l2v"]:
                buff_bad.append((r, "属性非中文", parts_lists[0][i]))
            if parts_lists[1][i] not in maps["op"]["l2v"]:
                buff_bad.append((r, "运算非中文", parts_lists[1][i]))
            try:
                float(parts_lists[2][i])
            except ValueError:
                buff_bad.append((r, "数值非数字", parts_lists[2][i]))
    exp_items = sum(len(v) for v in exp_buff.values())
    buff_ok = (buff_heads_ok and set(got_buff) == set(exp_buff)
               and len(got_buff) == 7 and buff_items == exp_items and not buff_bad)
    print("    · ③ 增益三列：列头 %s；有值行 %d（期望 7）/ 条目 %d（期望 %d）/ 异常 %d → %s" % (
        buff_labels, len(got_buff), buff_items, exp_items, len(buff_bad),
        "✓" if buff_ok else "✗"))
    if buff_bad:
        print("      异常：%s" % buff_bad[:10])
    if not buff_ok:
        problems.append("增益三列不完整或与原始 buff_mods 不符")
    for key, cells in got_buff.items():
        print("      %s 第%s段：%s" % (key[0], key[1], " | ".join(str(c) for c in cells)))

    # [6d] 契约 v1.3 即时校验专项：单值枚举列拦截 / 多值列仅提示 / 引用型下拉
    singles, multis, refs = expected_validations(schema)
    dv_bad = []

    def dv_for(ws, label, heads):
        return dvs_for_column(ws, heads.index(label) + 1)

    for key, label, enum_name in singles:
        ws, heads = {"skills": (ws_sk, heads_sk), "parts": (ws_pt, heads_pt),
                     "supports": (ws_sp, heads_sp)}[key]
        dvs = dv_for(ws, label, heads)
        if len(dvs) != 1:
            dv_bad.append((key, label, "DV 数量 %d" % len(dvs)))
            continue
        dv = dvs[0]
        formula = str(dv.formula1 or "").lstrip("=")
        if not dv.showErrorMessage:
            dv_bad.append((key, label, "未开 showErrorMessage"))
        if SINGLE_ENUM_ERROR not in str(dv.error or ""):
            dv_bad.append((key, label, "错误提示不是中文约定文案"))
        if formula != "OPT_" + str(enum_name).upper():
            dv_bad.append((key, label, "下拉引用 %r，期望 OPT_%s" % (formula, str(enum_name).upper())))
    for key, label, enum_name in multis:
        ws, heads = {"skills": (ws_sk, heads_sk), "parts": (ws_pt, heads_pt),
                     "supports": (ws_sp, heads_sp)}[key]
        dvs = dv_for(ws, label, heads)
        if len(dvs) != 1:
            dv_bad.append((key, label, "DV 数量 %d" % len(dvs)))
            continue
        dv = dvs[0]
        if dv.showErrorMessage:
            dv_bad.append((key, label, "多值列被硬拦（showErrorMessage=True）"))
        if not (dv.showInputMessage and str(dv.prompt or "").strip()):
            dv_bad.append((key, label, "缺中文填写提示"))
        if enum_name is not None:
            formula = str(dv.formula1 or "").lstrip("=")
            if formula != "OPT_" + str(enum_name).upper():
                dv_bad.append((key, label, "多值下拉引用 %r 不符" % formula))
    for key, label in refs:
        ws, heads = ws_pt, heads_pt
        dvs = dv_for(ws, label, heads)
        if len(dvs) != 1:
            dv_bad.append((key, label, "引用型 DV 数量 %d" % len(dvs)))
            continue
        dv = dvs[0]
        if str(dv.formula1 or "").lstrip("=") != SKILL_REF_NAME:
            dv_bad.append((key, label, "引用型 DV 未指向 %s" % SKILL_REF_NAME))
        if not dv.showErrorMessage or "技能名" not in str(dv.error or ""):
            dv_bad.append((key, label, "引用型 DV 未拦或错误提示不符"))
    dv_total = sum(len(w.data_validations.dataValidation) for w in (ws_sk, ws_pt, ws_sp))
    print("[6d] 即时校验专项（契约 v1.3）：单值枚举 %d 列 / 多值 %d 列 / 引用型 %d 列，"
          "共 %d 个 DV；异常 %d → %s" % (
              len(singles), len(multis), len(refs), dv_total, len(dv_bad),
              "✓" if not dv_bad else "✗"))
    if dv_bad:
        print("      异常：%s" % dv_bad[:15])
        problems.append("即时校验不符合契约 %d 处" % len(dv_bad))

    # [7] 结构验收
    checks = []
    # 代号列只读；数据行代号列属主键列（黄色必填）——契约 v1.4 口径
    for key, ws_heads, rows, ws in (("skills", heads_sk, rows_sk, ws_sk),
                                    ("supports", heads_sp, rows_sp, ws_sp)):
        idc = ws_heads.index("代号（自动，别填）") + 1
        ok = all(ws.cell(row=r, column=idc).protection.locked for r, _ in rows)
        checks.append(("%s 数据行代号列（主键）只读" % key, ok))
    # 高级数据列隐藏
    for key, ws, heads in (("skills", ws_sk, heads_sk), ("parts", ws_pt, heads_pt),
                           ("supports", ws_sp, heads_sp)):
        exc = heads.index(EXTRAS_LABEL) + 1
        ok = _col_hidden(ws, exc)
        checks.append(("%s 高级数据列隐藏" % key, ok))
    # 示例行（契约 v1.3）：数量 + 主键列【示例】+ 整行锁定；② ④ 备注列同样带前缀
    def example_ok(ws, count: int, has_note: bool) -> bool:
        heads = [c.value for c in ws[1]]
        note_col = heads.index("备注（不进游戏）") + 1 if has_note else None
        for r in range(2, 2 + count):
            v = ws.cell(row=r, column=1).value
            if not (is_example_row(v, marker) and str(v).startswith(marker)):
                return False
            for c in ws[r]:
                if c.value not in (None, "") and not c.protection.locked:
                    return False
            if note_col:
                nv = ws.cell(row=r, column=note_col).value
                if nv is None or not str(nv).startswith(marker):
                    return False
        nxt = ws.cell(row=2 + count, column=1).value
        return not is_example_row(nxt, marker)
    ok_ex = (example_ok(ws_sk, EXAMPLE_ROWS["skills"], True)
             and example_ok(ws_pt, EXAMPLE_ROWS["parts"], False)
             and example_ok(ws_sp, EXAMPLE_ROWS["supports"], True))
    checks.append(("三张数据表示例行 4/5/4，主键列【示例】、整行锁定、②④备注同步", ok_ex))
    # 示例行覆盖「线 + 范围爆发」「引导」「自我增益」
    ex_effects = [ws_pt.cell(row=r, column=heads_pt.index("效果") + 1).value
                  for r in range(2, 2 + EXAMPLE_ROWS["parts"])]
    ex_shapes = [ws_pt.cell(row=r, column=heads_pt.index("形状") + 1).value
                 for r in range(2, 2 + EXAMPLE_ROWS["parts"])]
    cover_ok2 = ("范围爆发" in ex_effects and "引导" in ex_effects
                 and "自我增益" in ex_effects
                 and ex_shapes[ex_effects.index("范围爆发")] == "线")
    checks.append(("③ 示例覆盖「线 + 范围爆发」「引导」「自我增益」：%s" % (
        list(zip(ex_effects, ex_shapes))), cover_ok2))
    # 表头批注：逐列等于 column_notes 原文（含 ② 技能代号别名），全中文，只写在表头
    aliases = {"skills": {"代号（自动，别填）": "技能代号"}}
    exp_comments = {}
    for key in ("skills", "parts", "supports"):
        notes = schema["column_notes"][key]
        for label in labels[key]:
            if label == EXTRAS_LABEL:
                continue
            note = notes.get(label)
            if note is None:
                note = notes.get(aliases.get(key, {}).get(label, ""))
            if note is not None:
                exp_comments[(key, label)] = note
    got_comments = {}
    comment_nonheader = []
    for key, ws in (("skills", ws_sk), ("parts", ws_pt), ("supports", ws_sp)):
        for row in ws.iter_rows():
            for c in row:
                if c.comment:
                    if c.row != 1:
                        # 契约 v1.4：主键列 / 代号列的数据格允许带中文说明（批量填表用）
                        if key in ("skills", "supports") and c.column in (
                                _key_col(key, ws), _id_col(ws)):
                            continue
                        comment_nonheader.append((key, c.coordinate))
                    got_comments[(key, ws.cell(row=1, column=c.column).value)] = c.comment.text
    comments_ok = (got_comments == exp_comments and not comment_nonheader
                   and all(not re.search(r"[A-Za-z]", t) for t in got_comments.values()))
    checks.append(("②③④ 表头批注 %d 列且逐列等于 column_notes 原文、全中文" % len(got_comments),
                   comments_ok))
    # ⑤ 可选项 12 组词表且隐藏；阵型/运动方式词表存在且全中文
    opt_letters = {opt_heads.index(t) + 1: t for t in ("阵型", "运动方式")}
    opt_titles_ok = opt_heads == ["效果", "形状", "伤害类型", "标签", "施法方式",
                                  "消耗类型", "命中通道", "运算", "属性（英文标识符）",
                                  "属性", "阵型", "运动方式"]
    opt_chinese_ok = True
    for ci, title in enumerate(opt_heads, start=1):
        if title == "属性（英文标识符）":
            continue
        vals = [opt.cell(row=r, column=ci).value for r in range(2, opt.max_row + 1)]
        vals = [v for v in vals if v not in (None, "")]
        if not vals or any(re.search(r"[A-Za-z]", str(v)) for v in vals):
            opt_chinese_ok = False
    vocab_ok = (len(opt_heads) == 12 and opt_titles_ok and opt_chinese_ok
                and opt.sheet_state != "visible")
    checks.append(("⑤ 可选项 12 组词表（含阵型/运动方式）全中文且隐藏", vocab_ok))
    # 定义名：OPT_FORMATION / OPT_MOTION / OPT_SKILL_NAMES
    def_name_ok, def_detail = True, {}
    for enum_name, letter_index in (("formation", 11), ("motion", 12)):
        dn = "OPT_" + enum_name.upper()
        if dn not in wb.defined_names:
            def_name_ok = False
            def_detail[dn] = "缺少"
            continue
        text = wb.defined_names[dn].attr_text
        letter = get_column_letter(letter_index)
        expect = "'%s'!$%s$2:$%s$%d" % (
            sheet_of["options"], letter, letter, len(maps[enum_name]["labels"]) + 1)
        def_detail[dn] = text
        if text != expect:
            def_name_ok = False
    skill_start = 2 + EXAMPLE_ROWS["skills"]
    # 契约 v1.4：引用下拉范围还要覆盖预留区，策划新填的技能名在 ③ 里能直接选到
    skill_end = skill_start + len(data["skills"]) + reserved_of_["skills"] - 1
    expect_skill = "'%s'!$A$%d:$A$%d" % (sheet_of["skills"], skill_start, skill_end)
    if SKILL_REF_NAME not in wb.defined_names:
        def_name_ok = False
        def_detail[SKILL_REF_NAME] = "缺少"
    else:
        def_detail[SKILL_REF_NAME] = wb.defined_names[SKILL_REF_NAME].attr_text
        if wb.defined_names[SKILL_REF_NAME].attr_text != expect_skill:
            def_name_ok = False
    checks.append(("定义名 OPT_FORMATION/OPT_MOTION 指向 ⑤ 阵型/运动方式；%s → %s" % (
        SKILL_REF_NAME, expect_skill), def_name_ok))
    if not def_name_ok:
        print("      定义名实测：%s" % def_detail)
    # 契约 v1.3：②③④ 数据行可见列不再出现英文标识符（代号列 / 隐藏高级数据除外）
    eng_hits = []
    for key, ws, heads in (("skills", ws_sk, heads_sk), ("parts", ws_pt, heads_pt),
                           ("supports", ws_sp, heads_sp)):
        for ci, h in enumerate(heads, start=1):
            if h in (EXTRAS_LABEL, "代号（自动，别填）"):
                continue
            for r in range(2, ws.max_row + 1):
                if is_example_row(ws.cell(row=r, column=1).value, marker):
                    continue
                v = ws.cell(row=r, column=ci).value
                if isinstance(v, str) and re.search(r"[A-Za-z]", v):
                    eng_hits.append((key, r, h, v))
    checks.append(("②③④ 数据行可见列无英文标识符（%d 处）" % len(eng_hits), not eng_hits))
    if eng_hits:
        print("      残留英文值：%s" % eng_hits[:10])
    # 参数分组折叠
    grp = [cd for i, cd in ws_pt.column_dimensions.items()
           if cd.outlineLevel and cd.outlineLevel >= 1]
    checks.append(("③ 参数列按行为/形状分组折叠（%d 组）" % len(grp), len(grp) >= 3))
    # 数据表开启工作表保护
    checks.append(("三张数据表开启工作表保护（示例行锁定生效）",
                   all(ws.protection.sheet for ws in (ws_sk, ws_pt, ws_sp))))
    # 契约 v1.4：预留行数量 / 可编辑 / 示例行与代号列、高级数据列、表头仍锁定
    checks.append(("契约 v1.4 预留行数量 ② %d / ③ %d / ④ %d 且紧接数据行" % (
        rv_count.get("skills"), rv_count.get("parts"), rv_count.get("supports")),
        (rv_count.get("skills"), rv_count.get("parts"), rv_count.get("supports"))
        == (RESERVED_ROWS["skills"], RESERVED_ROWS["parts"], RESERVED_ROWS["supports"])))
    unlocked_ok = True
    for key in ("skills", "parts", "supports"):
        ws, heads = sheet_of_ws[key], heads_of[key]
        start = last_data_row[key] + 1
        end = start + int(reserved_of.get(key, RESERVED_ROWS[key])) - 1
        id_col = heads.index("代号（自动，别填）") + 1 if "代号（自动，别填）" in heads else None
        for r in range(start, end + 1):
            for ci, h in enumerate(heads, start=1):
                if h == EXTRAS_LABEL or ci == id_col:
                    continue
                if ws.cell(row=r, column=ci).protection.locked:
                    unlocked_ok = False
    checks.append(("②③④ 预留行可见数据列全部可编辑（unlocked）", unlocked_ok))
    ex_locked = True
    for key, ws in (("skills", ws_sk), ("parts", ws_pt), ("supports", ws_sp)):
        for r in range(2, 2 + EXAMPLE_ROWS[key]):
            for c in ws[r]:
                if not c.protection.locked:
                    ex_locked = False
    checks.append(("②③④ 示例行 4/5/4 仍整行锁定", ex_locked))
    # 契约 v1.4 口径：代号列 = 表头 + 示例行 + 预留行 灰底且锁定（数据行代号是主键列，
    # 保持既有的黄色必填填充，同样 locked）。灰底必须是「灰」，不能是表头蓝或白底。
    id_gray_locked = True
    for key, ws, heads in (("skills", ws_sk, heads_sk), ("supports", ws_sp, heads_sp)):
        idc = heads.index("代号（自动，别填）") + 1
        reserved_start = data_end[key] + 1
        reserved_end = reserved_start + reserved_of_[key] - 1
        for r in [1] + list(range(2, 2 + EXAMPLE_ROWS[key])) + list(
                range(reserved_start, reserved_end + 1)):
            c = ws.cell(row=r, column=idc)
            if not (c.protection.locked and str(c.fill.fgColor.rgb) == GRAY):
                id_gray_locked = False
    checks.append(("②④ 代号列（表头/示例行/预留行）灰底 + 锁定，未写死任何代号",
                   id_gray_locked and not rv_errors))
    header_locked = True
    for key, ws, heads in (("skills", ws_sk, heads_sk), ("parts", ws_pt, heads_pt),
                           ("supports", ws_sp, heads_sp)):
        exc = heads.index(EXTRAS_LABEL) + 1
        for ci in range(1, len(heads) + 1):
            c = ws.cell(row=1, column=ci)
            if not c.protection.locked:
                header_locked = False
            if ci == exc and not _col_hidden(ws, exc):
                header_locked = False
    checks.append(("②③④ 表头整行仍锁定、高级数据列仍隐藏", header_locked))
    # 报告空表头
    rep = wb[sheet_of["report"]]
    checks.append(("⑥ 检查结果 仅空表头",
                   [c.value for c in rep[1]] == REPORT_HEADERS and rep.max_row == 1))
    # 说明页全中文
    readme = wb[titles[0]]
    zh = all(not (isinstance(c.value, str) and re.search(r"[A-Za-z]", c.value))
             for row in readme.iter_rows() for c in row if c.value)
    checks.append(("① 先看这里 全中文且字号放大", zh and readme["A1"].font.size >= 18))

    print("[7] 结构验收：%d 项" % len(checks))
    for name, ok in checks:
        print("    · %s：%s" % (name, "✓" if ok else "✗"))
        if not ok:
            problems.append(name)
    print("    通过 %d / %d 项" % (sum(1 for _, ok in checks if ok), len(checks)))

    # 结论
    print("---")
    if problems:
        print("结论：自检未通过，共 %d 项问题：" % len(problems))
        for p in problems:
            print("    ! " + p)
        return 1
    print("结论：零差异 —— 80 条资源（主动 67 / 辅助 13）逐字段往返无损；")
    print("      契约 v1.3：③ 阵型/运动方式中文、④ 冲突辅助中文名、③ 增益三列可编辑；")
    print("      单值枚举列下拉中文拦截、多值列仅提示；②③④ 表头批注取自 column_notes；")
    print("      示例行 4/5/4 锁定且覆盖「线 + 范围爆发」「引导」「自我增益」；")
    print("      契约 v1.4：②③④ 预留行可编辑（%d/%d/%d 行，代号列灰底只读 + 中文提示）、"
          "示例行/代号列/高级数据列/表头仍锁定；" % (
              rv_count.get("skills"), rv_count.get("parts"), rv_count.get("supports")))
    print("      工作簿 6 页签、中文列头、三色、代号只读、隐藏高级数据全部齐全；")
    print("      触发器目录未处理、未修改、未删除。")
    return 0


def _col_index(i):
    return i if isinstance(i, int) else column_index_from_string(i)


def _id_col(ws) -> int:
    """②④ 代号列（自动，别填）列号；无此列返回 -1。"""
    heads = [c.value for c in ws[1]]
    return heads.index("代号（自动，别填）") + 1 if "代号（自动，别填）" in heads else -1


def _key_col(key: str, ws) -> int:
    """②④ 主键列（技能名 / 辅助石名）列号。"""
    return 1 if key in ("skills", "supports") else -1


def _col_hidden(ws, col_idx: int) -> bool:
    """列是否隐藏（openpyxl 的 column_dimensions 键可能是字母或数字，两种都认）。"""
    for key, cd in ws.column_dimensions.items():
        if _col_index(key) == col_idx:
            return bool(cd.hidden)
    return False




# ============================ 变异测试（证明断言能抓错） ============================

MUT_ROWS = {"skills": (73, 40), "parts": (102, 90), "supports": (19, 30)}


def _relayout_rows(wb, schema, key: str, delta: int):
    """把某张表的预留区加/减 delta 个「空白可编辑行」，模拟「预留行数量不对」。

    · delta > 0：在预留区头部插入空白行（样式按预留行口径重扫一遍）；
    · delta < 0：删掉预留区末尾的空白行；
    两种情况都不碰数据行，自检必须由「预留行实测行数 ≠ 契约行数」抓出来。
    """
    from openpyxl.styles import PatternFill, Protection

    white = PatternFill("solid", fgColor="FFFFFF")
    titles = {s["key"]: s["title"] for s in schema["sheets"]}
    ws = wb[titles[key]]
    rv_start, rv_count = MUT_ROWS[key]
    rv_end = rv_start + rv_count - 1
    heads = [c.value for c in ws[1]]
    idc = heads.index("代号（自动，别填）") + 1 if "代号（自动，别填）" in heads else None
    if delta > 0:
        ws.insert_rows(rv_start, delta)
        for r in range(rv_start, rv_end + delta + 1):
            for ci, h in enumerate(heads, start=1):
                c = ws.cell(row=r, column=ci)
                if ci == idc:
                    c.value = "新技能由工具生成代号，填了技能名即可"
                    c.protection = Protection(locked=True)
                elif h == EXTRAS_LABEL:
                    c.value = None
                    c.protection = Protection(locked=True)
                else:
                    c.value = None
                    c.fill = white
                    c.protection = Protection(locked=False)
    else:
        ws.delete_rows(rv_end + delta + 1, -delta)


def mutation_cases(schema: dict) -> list:
    """返回 [(用例名, 期望命中的自检关键字, 变异函数(wb)->None)]。"""
    from openpyxl.styles import PatternFill, Protection

    def _cell(ws, label, r):
        return ws.cell(row=r, column=[c.value for c in ws[1]].index(label) + 1)

    def unlock_example(wb):
        ws = wb["② 技能卡"]
        _cell(ws, "消耗数值", 3).protection = Protection(locked=False)

    def lock_reserved(wb):
        ws = wb["③ 效果段"]
        heads = [c.value for c in ws[1]]
        for ci in range(1, len(heads) + 1):
            ws.cell(row=102, column=ci).protection = Protection(locked=True)

    def ungray_code(wb):
        ws = wb["④ 辅助石"]
        _cell(ws, "代号（自动，别填）", 19).fill = PatternFill("solid", fgColor="FFFFFF")

    def id_wrong_text(wb):
        ws = wb["② 技能卡"]
        heads = [c.value for c in ws[1]]
        for r in range(73, 113):
            _cell(ws, "代号（自动，别填）", r).value = "skill_999"

    def id_unlocked(wb):
        ws = wb["② 技能卡"]
        for r in range(73, 113):
            _cell(ws, "代号（自动，别填）", r).protection = Protection(locked=False)

    def unhide_extras(wb):
        ws = wb["③ 效果段"]
        exc = [c.value for c in ws[1]].index(EXTRAS_LABEL) + 1
        ws.column_dimensions[get_column_letter(exc)].hidden = False

    def unlock_header(wb):
        wb["③ 效果段"].cell(row=1, column=1).protection = Protection(locked=False)

    def fill_reserved(wb):
        wb["② 技能卡"].cell(row=73, column=1).value = "不该预填的值"

    def more_parts(wb):
        _relayout_rows(wb, schema, "parts", 1)

    def less_supports(wb):
        _relayout_rows(wb, schema, "supports", -1)

    return [
        ("预留行数量不对（③ 多 1 行）", "预留行实测", more_parts),
        ("预留行数量不对（④ 少 1 行）", "预留行实测", less_supports),
        ("解锁示例行", "示例行", unlock_example),
        ("锁定预留行", "仍锁定的可见列", lock_reserved),
        ("去掉代号列灰底", "代号列不是灰底", ungray_code),
        ("代号列写死具体代号", "缺中文占位说明", id_wrong_text),
        ("解除代号列锁定", "代号列被解锁", id_unlocked),
        ("隐藏列变为可见", "高级数据列", unhide_extras),
        ("表头解锁", "表头整行仍锁定", unlock_header),
        ("预留行被预填内容", "预留行实测", fill_reserved),
    ]


def run_one_workbook(path=None) -> tuple:
    """在进程内跑一次 main()，返回 (退出码, 输出文本)；不打印到终端。"""
    import contextlib
    import io as _io
    global WORKBOOK_PATH
    old = WORKBOOK_PATH
    if path is not None:
        WORKBOOK_PATH = Path(path)
    buf = _io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            rc = main()
    finally:
        WORKBOOK_PATH = old
    return rc, buf.getvalue()


def mutation_test() -> int:
    """逐项弄坏工作簿副本，确认真自检真的报红（退出码 1）并命中对应中文问题。

    · 先跑「未变异工作簿」作对照，必须通过——证明变异框架没把结论弄反；
    · 每个变异都要求：退出码=1 且输出命中该用例的中文关键字；
    · 副本写到 _tmp/（已 gitignore），跑完即删，绝不碰正式工作簿。
    """
    import shutil
    tmp = WORKBENCH / "_tmp"
    tmp.mkdir(parents=True, exist_ok=True)
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))

    rc0, _out0 = run_one_workbook()
    print("=== 变异测试（export/selfcheck.py --mutation-test）===")
    print("对照：未变异工作簿 退出码=%d（期望 0）→ %s" % (rc0, "✓" if rc0 == 0 else "✗"))
    all_ok = rc0 == 0
    print("%-26s %-4s %-4s %s" % ("变异用例", "退出", "结论", "命中的中文问题"))
    for i, (name, keyword, mutate) in enumerate(mutation_cases(schema), start=1):
        p = tmp / ("mut_v14_%02d.xlsx" % i)
        shutil.copyfile(WORKBOOK_PATH, p)
        wb = load_workbook(p)
        mutate(wb)
        wb.save(p)
        rc, out = run_one_workbook(p)
        lines = [ln.strip() for ln in out.splitlines()]
        hit = [ln for ln in lines if keyword in ln
               and (ln.startswith("!") or ln.startswith("- "))]
        ok = rc == 1 and "自检未通过" in out and bool(hit)
        all_ok = all_ok and ok
        print("%-26s %-4s %-4s %s" % (name, rc, "抓住" if ok else "漏过!",
                                      (hit[0][:62] if hit else "")))
        p.unlink(missing_ok=True)
    print("---")
    print("变异测试结论：%s" % ("全部变异都被抓住 ✓" if all_ok else "存在漏过 ✗"))
    return 0 if all_ok else 1


if __name__ == "__main__":
    if "--mutation-test" in sys.argv:
        sys.exit(mutation_test())
    sys.exit(main())
