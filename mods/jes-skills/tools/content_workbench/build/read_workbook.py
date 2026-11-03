# -*- coding: utf-8 -*-
"""
W3 正向生成 · 交付物 A：Excel 工作簿 → 中间 JSON + 分层中文校验。

链路：中文工作簿 →（本脚本）→ _tmp/build_input.json →（Godot 侧 build_from_json.gd）→ .tres 干跑产物。

只读：schema.json（冻结契约，一个字都不改）、tests/skills/content_snapshot.json（运行时统计数值区间）。
只写：_tmp 下的中间产物（build_input.json / errors.json）。绝不写 content/gems/。

校验不过：不生成中间 JSON，并清理上一次可能残留的 build_input.json（W5 根因 3，
保证生成器绝不读到过期数据），把中文错误清单写入 errors.json，以非零退出码退出。
校验通过：生成 build_input.json，同时把 errors.json 写成「零错误」状态，避免上次失败残留被误读。

契约 v1.3 读侧（二期）新增四件事：
  · ③「阵型」「运动方式」表内写中文（enums.formation / enums.motion），读表还原英文 value，
    旧的英文原值仍兼容；
  · ③「增益内容」改为 buff_spec 的三条对齐列表列（增益属性/增益运算/增益数值）→ buff_mods，
    键按 __extras 同序号条目沿用、不补默认键，多余条目原样保留；
  · ④「冲突辅助（+ 分隔）」表内写辅助石中文名，按 ④ 表内「辅助石名 → 代号」还原 support_id，
    旧英文原值仍兼容；
  · ③ aoe 尺寸硬拦（validation_rules.aoe_size_required，与 test_content_contract.gd
    第 158–165 行同口径）：bhv_aoe_burst 且形状≠点且没有任何一组尺寸 → 中文报错、不生成中间 JSON。

契约 v1.4 读侧（三期 P7-B，新行 → 新技能）：
  · 预留行（②③④ 数据行之后的白底可编辑行）按 new_row_policy 处理：只有代号列的中文占位说明
    （「新技能由工具生成代号，填了技能名即可」）而没有技能名 / 辅助石名 → 整行静默跳过，
    不校验、不产出、不报错；③ 效果段只要「属于哪个技能 / 第几段 / 效果」三列全空即视为未填；
  · 预留行填了真实技能名（④ 辅助石同理）而代号为空或是占位 → 按 id_rule.new 生成
    skill_ / support_ + 三位序号（从 001 起取最小未占用号，避开表内既有全部代号与
    content/gems 下已有资源文件名），同一批内保证唯一；显式填写的合法代号一律尊重；
  · requires_parts：新技能卡至少要有一段有效效果段（③「属于哪个技能」按技能名指向它），
    否则中文报错定位到「② 技能卡 第 N 行 · 效果段」；
  · count_guard + 有效内容台账（运行时从 content/gems 的 .tres 统计，不硬编码）。
    契约 v1.7 起口径改为「目录驱动」：策划新增 / 删除技能或辅助石后不再「拦截不生成」，
    只做中文汇报『新增 N 条 / 删除 N 条，测试断言已随目录自动对齐』（删除类差异另加
    「内容删除不可逆，须制作人拍板」）；数量断言随内容目录实际数量走，测试断言已随
    目录自动对齐，无需人工改测试（依据：台账 P-23 改数写明依据 + 制作人 2026-11-03
    批示）。旧口径「真新增 → 不生成中间 JSON、须上级 AI 裁定」已废止。

契约 v1.6 读侧（四期 P4-3：四条校验规则落地）：
  · active_numeric_sane（硬拦，GUT test_a4 同口径）：② 消耗 >0、前摇 >0、
    每级变强必须显式填写（≥0 允许）；中文定位「② 技能卡 第 N 行 · 列名」；
  · part_form_tag_present（硬拦，GUT test_a5 同口径）：②③ 联查——每段行为自带
    形态标签（enums.behavior[].form_tag），所属技能「标签」必须包含它；
    中文定位「③ 效果段 第 N 行 · 效果」并指明缺哪个标签；behavior_id 为空由
    ③「效果」列必填校验拦截（定位相同）；
  · support_cost_positive（硬拦，GUT test_b4 同口径）：④ 消耗倍率 >0，
    中文定位「④ 辅助石 第 N 行 · 消耗倍率」；
  · channel_circ_range_hint（黄色提醒不拦截）：channel×circ 且半径空且扇形距离非空时，
    按契约 when/text 出中文提醒——现有 3 条 channel×circ 合法内容必须照常生成；
  · 四条规则的口径（阈值、条件、文案）全部取自 schema.validation_rules，不内置第二份。

契约 v1.5 读侧（四期 P4-2：图标 / 行为覆盖 显式列回读）：
  · ②「图标」(field icon, string, res:// 路径) 与 ④「行为覆盖（工具自动，勿改）」
    (field behavior_overrides, json) 按中文标签回读为显式列；显式列非空时优先，
    空则仍走 __extras 兜底 —— 旧工作簿（值只在 __extras 里、甚至整列不存在）照常读通；
  · ④ 行为覆盖按 JSON 原文解析成字典；显式列非空 = 整体生效（覆盖而非与 __extras 并集，
    防止显式列里删掉的旧覆盖键被 __extras 残值「复活」）；非法 JSON 中文报错、不生成中间 JSON；
  · ② 图标填了但不是 res:// 开头 → 中文报错定位「② 技能卡 第 N 行 · 图标」；
    留空不校验（留空 = 未设置，由 __extras 兜底，旧表零差异）。

契约 v1.7 读侧（四期收尾）：
  · shape_keys.line 补「range」：本文件对 shape_keys 的全部使用（合法尺寸键并集
    dimension_keys、按形状查可用键）都直接读 schema["shape_keys"]，没有任何硬编码的
    line 键清单 —— 契约补 range 后读侧自动生效：线形只填「扇形距离」属合法尺寸
    （shape_hit.gd 第 17 行 length 缺省回退 range 承载），契约与代码的缝已消除；
  · new_row_policy.count_guard 改「目录驱动」：见上；数量差异从「硬拦错误」降为
    「中文汇报（warnings 通道）」，删除类差异追加「内容删除不可逆，须制作人拍板」。
    validation_rules.aoe_size_required 口径不动：范围爆发的线形仍要求 半径 或
    长度+宽度 或 扇形角度+扇形距离 三组尺寸之一。

用法：
  python read_workbook.py <工作簿.xlsx> [--schema 路径] [--out 路径] [--errors 路径] [--snapshot 路径]
"""

import argparse
import copy
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

from openpyxl import load_workbook

# ---------------------------------------------------------------- 路径 ----
HERE = Path(__file__).resolve().parent          # .../tools/content_workbench/build
WORKBENCH = HERE.parent                        # .../tools/content_workbench
MODULE = WORKBENCH.parents[1]                  # .../mods/jes-skills
DEFAULT_SCHEMA = WORKBENCH / "schema.json"
DEFAULT_OUT = WORKBENCH / "_tmp" / "build_input.json"
DEFAULT_ERRORS = WORKBENCH / "_tmp" / "errors.json"
DEFAULT_SNAPSHOT = MODULE / "tests" / "skills" / "content_snapshot.json"

# ------------------------------------------------------------ 词表来源 ----
# 「属性」列（type=enum:stat_labels）的中文词表唯一真源是 schema.json 的
# enums.stat_labels（契约 v1.1 追加的 23 项中文 label → 英文 value），由
# build_enum_maps() 运行时读取。本文件不再内置任何中文属性映射，避免两处口径漂移；
# enums.stat 的英文标识符原值另作兼容，保证旧工作簿 / 手工填入的英文值仍可解析。

# 语义为整数的字段 / 参数键。必须与 build_from_json.gd 的 INT_VALUE_KEYS 保持一致。
# 原因：Godot 的 JSON.parse_string 会把所有数字（含 1）解析成 float，故 B 侧按本白名单
# 显式 int() 还原；A 侧按本白名单把 JSON 写成整数，保证「输入 == 回读」。
INT_VALUE_KEYS = {
    "cast_mode", "cost_type", "damage_channel", "max_charges",
    "knee_level", "channel_mask", "op",
    "hit_count", "point_count", "max_count", "per_cast",
    "pierce", "fork_count", "chain_count", "_index",
}

# 数值区间提醒时，工作簿字段名 → content_snapshot.json 里的叶子键名。
RANGE_KEY_ALIASES = {
    "damage_effectiveness": "effectiveness",
    "_value": "value",
    "per_level": "per_level",
}

ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")

# ------------------------------------------------------ 契约 v1.4 常量 ----
# new_row_policy.code_column：W2（export/build_workbook.py 的 NEW_ROW_ID_HINT）写进②④ 预留行
# 代号列的浅灰斜体中文占位说明。读侧只认「说明里提到的占位字样」，不要求整格一字不差；
# 也兼容 W2 早期（示例行）用过的「（工具自动生成，不用填）」写法。
ROW_ID_PLACEHOLDERS = (
    "填了技能名即可",
    "由工具生成代号",
    "工具自动生成，不用填",
)

# id_rule.new：新技能 / 新辅助石代号前缀与三位序号的位数（序号从 001 起，取最小未占用号）
NEW_ID_PREFIX = {"skills": "skill_", "supports": "support_"}
NEW_ID_DIGITS = 3

# new_row_policy.count_guard / 任务书 P7-B：数量口径的真源是运行时内容目录本身
# （契约 v1.7 起 tests 数量断言随目录实数对齐）。读侧不硬编码 67/95/13 这组数字，
# 而是运行时清点 content/gems 下「生成资源」目录里的 .tres 作为「有效内容台账」：
#   gems/active/*.tres   → 技能（79 个文件名与 ② 的「代号」逐条同构，故也用于新增代号避重）
#   gems/supports/*.tres → 辅助石
# 注意：gems/triggers/（触发器，只有 1 个资源）与技能 / 辅助石无关，绝不能计进技能数，
# 故不能按 content/gems 的整个子树计数（P7-B 首版实现即因此把 67 数成 68）。
# 台账变了（上级 AI 裁定后落盘）比较基准自动跟着变，无需改代码。
CONTENT_DIR = MODULE / "content" / "gems"
LEDGER_SUBDIRS = {"skills": "active", "supports": "supports"}

# count_guard（契约 v1.7「目录驱动」汇报）的适用范围（很重要，别放宽）：
# 汇报只对「正式配置表」生效 —— 判据：表内技能代号里来自台账（content/gems 既有
# 代号）的比例 ≥ 该阈值，即这张表是在真实目录基础上增删的；策划的最小自查工作簿、
# W3 自检自造的 1 技能 + 1 效果段 + 1 辅助石夹具，代号全是自造、无一来自台账，
# 不算、也不汇报，避免把「残缺的小表」判成「新增」刷屏（P7-B 首版实现即踩到此坑）。
# 用「表内占比」而不是「台账覆盖率」：策划删掉若干行后，表内仍是清一色既有内容，
# 删除汇报照常触发（台账覆盖率口径会在大量删除时漏报）。
COUNT_GUARD_COVERAGE = 0.9

# add_error 里换行标记（见 add_error 注释）
NL_MARKER = "@@NL@@"

# ------------------------------------------------------ 契约 v1.5 常量 ----
# v1.5 新升的显式中文列（②「图标」icon / ④「行为覆盖」behavior_overrides）。
# 向后兼容硬口径：旧工作簿整列缺失、值只在 __extras 里时必须照常读通
# （extras_policy 的兜底口径），故这两列「表头找不到」不算错误，按整列留空处理。
V15_FALLBACK_FIELDS = {"icon", "behavior_overrides"}


# ------------------------------------------------------------ 工具函数 ----
def is_blank(value) -> bool:
    """单元格是否为空。"""
    if value is None:
        return True
    if isinstance(value, str) and value.strip() == "":
        return True
    return False


def has_value(container, key) -> bool:
    """behavior_params 里某个键是否「有值」：存在、非 None、非空字符串。

    与 GUT test_a6 的 p.has(key) 对齐口径：表里单元格填了（含 0）即视为有该键。
    """
    if not isinstance(container, dict):
        return False
    if key not in container:
        return False
    value = container[key]
    return value is not None and value != ""


def as_number(value):
    """把单元格值转成 Python 数字；失败返回 None。"""
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, str):
        text = value.strip()
        try:
            return int(text) if re.fullmatch(r"[+-]?\d+", text) else float(text)
        except ValueError:
            return None
    return None


def add_error(errors, sheet, row, col, message):
    # 列名里可能带「@@NL@@ 换行」标记（历史 count_guard 多行报错文案遗留的换行能力，现保留通用），
    # 落进中文清单前还原成真正的换行，保证终端 / errors.json 两处读起来都是分行的整句。
    shown = str(col).replace(NL_MARKER, "\n")
    errors.append({
        "sheet": sheet,
        "row": row,
        "col": col,
        "message": message,
        "text": f"{sheet} 第 {row} 行 · {shown}：{message}",
    })


def sheet_title(schema, key):
    for s in schema["sheets"]:
        if s["key"] == key:
            return s["title"]
    return key


def is_example_row(cells, schema) -> bool:
    """按契约 v1.2 example_row_policy 识别「锁定示例行」，整行跳过（不校验、不产出、不进 JSON）。

    要同时兼容两种文本（W2 与我并行，可能分批重建工作簿）：
      · 新标记：主键列以 marker「【示例】」开头；
      · v1.1 遗留：主键列填「这是例子，照着填」、代号列填「（工具自动生成，不用填）」。
    按整行任一单元格命中即判定，保证两种口径都能稳妥跳过；示例行的特征文本
    不会出现在真实数据里，故不会误伤。
    """
    policy = schema.get("example_row_policy", {})
    marker = policy.get("marker", "【示例】")
    legacy = ("这是例子，照着填", "（工具自动生成，不用填）", "(工具自动生成，不用填)")
    for c in cells:
        if is_blank(c):
            continue
        text = str(c).strip()
        if marker and text.startswith(marker):
            return True
        for t in legacy:
            if t in text:
                return True
    return False


# -------------------------------------------------- 契约 v1.4 预留行辅助 ----
def is_row_id_placeholder(value) -> bool:
    """②④ 代号列里的单元格是否只是「自动生成」的中文占位说明（不是真实代号）。"""
    if is_blank(value):
        return False
    text = str(value).strip()
    return any(token in text for token in ROW_ID_PLACEHOLDERS)


def is_blank_row(cells, row_id_values, blank_cols=None) -> bool:
    """预留行是否「一行内容都没有」。

    判据（契约 v1.4 new_row_policy）：
      · ②④ 预留行只填了代号列的占位说明、其余可见列全空 → 跳过（占位说明不算内容）；
      · ③ 效果段无代号列，只有「属于哪个技能 / 第几段 / 效果」都填了才算一条效果段 ——
        只填了其中一两列（例如技能名写了却忘了选「效果」）是「填了一半」，不能静默丢弃，
        必须照常走必填校验、中文报错定位到缺的那一列。
    """
    for idx, value in enumerate(cells):
        if is_blank(value):
            continue
        if idx in row_id_values and is_row_id_placeholder(value):
            continue        # 代号列的中文占位说明不是内容
        if blank_cols is not None and idx not in blank_cols:
            continue        # ③：非关键列（如备注）有字不算「填了」
        return False
    return True


def load_content_ledger(content_dir=None):
    """读运行时内容台账（有效内容基线）：content/gems/active 与 content/gems/supports 下的 .tres。

    返回 {"skills": 技能数, "supports": 辅助石数,
          "skill_ids": {技能代号}, "support_ids": {辅助石代号}, "ids": {全部代号}}。
    目录整体缺失或台账为空时返回 None —— 此时只退化为「不做数量汇报」，
    新代号仍按「本批次 + 表内显式代号」避重（见 next_new_id），不因缺目录误拦正常链路。
    """
    root = Path(content_dir) if content_dir else CONTENT_DIR
    if not root.is_dir():
        return None
    skill_ids, support_ids = set(), set()
    for key, bucket in (("skills", skill_ids), ("supports", support_ids)):
        sub = root / LEDGER_SUBDIRS[key]
        if sub.is_dir():
            bucket |= {p.stem for p in sub.glob("*.tres")}
    if not (skill_ids or support_ids):
        return None
    return {
        "skills": len(skill_ids),
        "supports": len(support_ids),
        "skill_ids": skill_ids,
        "support_ids": support_ids,
        "ids": skill_ids | support_ids,
    }


def count_guard_applies(skill_rows, ledger) -> bool:
    """工作簿是否属于「在真实目录基础上增删的正式配置表」——决定目录驱动汇报要不要生效。

    判据：表内技能代号里来自台账（content/gems 既有技能代号）的比例 ≥ COUNT_GUARD_COVERAGE。
    正式表（67 既有 + 策划新增若干）比例仍接近 100%；策划删掉若干行后表内仍是清一色
    既有内容，比例仍是 100%，删除汇报照常触发；自检夹具 / 策划最小自查表只有自造的
    两三条内容，比例极低，不汇报、不打扰。
    台账里没有技能时（缺目录）由调用方在 ledger 为空时就跳过，这里再兜一层。
    """
    base = ledger.get("skill_ids") if ledger else None
    if not base:
        return False
    got = [r.get("gem_id") for r in skill_rows if r.get("gem_id")]
    if not got:
        return False
    covered = len(set(got) & base)
    return covered / float(len(got)) >= COUNT_GUARD_COVERAGE


def next_new_id(prefix, *, used_live, used_reserved):
    """id_rule.new：前缀 + 三位序号，从 001 起取最小未占用号。

    used_live：本次分配前已占用（content/gems 既有资源文件名 + 本批次已分配的代号），
    必须越过它们，保证同一批新增彼此也不重号；
    used_reserved：表内其余行显式写的代号（尚未分配、但同样不能被新号撞上）。
    两者都不满足才算空闲；命中后把新号塞进 used_live。
    """
    for n in range(1, 10 ** NEW_ID_DIGITS):
        candidate = f"{prefix}{n:0{NEW_ID_DIGITS}d}"
        if candidate not in used_live and candidate not in used_reserved:
            used_live.add(candidate)
            return candidate
    return None


def count_guard_report(label, added, removed):
    """契约 v1.7 new_row_policy.count_guard 的目录驱动中文汇报（不再拦截，只汇报差异）。

    口径：『新增 N 条 / 删除 N 条，测试断言已随目录自动对齐』——数量断言随内容目录
    实际数量走，无需人工改测试；删除类差异追加「内容删除不可逆，须制作人拍板」。
    """
    seg = []
    if added:
        seg.append(f"新增 {len(added)} 条（{'、'.join(added)}）")
    if removed:
        seg.append(f"删除 {len(removed)} 条（{'、'.join(removed)}）")
    text = (f"{label}数量与内容台账（content/gems）比对：" + "、".join(seg)
            + "，测试断言已随目录自动对齐（数量断言随内容目录实际数量走，无需人工改测试）")
    if removed:
        text += "；内容删除不可逆，须制作人拍板"
    return text


def col_label_for(schema, sheet_key, field):
    """契约字段名 → 该表中文列名（报错定位用）；找不到时原样返回字段名。"""
    for c in schema["columns"].get(sheet_key, []):
        if c.get("field") == field:
            return c["label"]
    return field


def get_field(obj, dotted):
    """按带点号的字段路径取值（level_scaling.per_level 等）；缺路径返回 None。"""
    node = obj
    for part in dotted.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def shape_cn_label(schema, shape):
    """形状英文标识符 → 中文 label（黄色提醒里给人看，保持全中文）。"""
    for e in schema["enums"]["shape"]:
        if e["value"] == shape:
            return e["label"]
    return str(shape)


def dimension_keys(schema):
    """形状尺寸参数键的全并集（契约驱动，不硬编码）。

    契约 v1.2：shape_keys 是「该形状可用的参数键」，不是必填键。判断「尺寸参数是否全空」
    时用全并集而非单形状键集，把「扇形距离」range 也算进来 —— 引导类用 range 跨形状
    承载圆/线尺寸是合法既有口径（shape_hit.gd 第 17 行、台账 D-46），不能误报黄色提醒。
    """
    keys = set()
    for group in schema["shape_keys"].values():
        keys |= set(group)
    return keys


def build_enum_maps(schema):
    """从 schema.enums 建立 {类型名: {by_label, labels, values}}，供中文下拉值反查英文标识符。

    契约里有两类词表结构：
      · {label, value} 数组（behavior / shape / stat_labels 等）：中文 label → 英文 value，
        并把 value（英文原值）一并并入 by_label 做兼容；
      · 纯英文标识符数组（enums.stat）：值即英文标识符，原样建立映射。
    「属性」列的中文词表唯一真源是 enums.stat_labels（契约 v1.1），本文件不再内置映射。
    """
    maps = {}
    for name, entries in schema.get("enums", {}).items():
        by_label = {}
        labels = []
        values = []
        if entries and isinstance(entries[0], str):
            for v in entries:
                by_label[v] = v
                labels.append(v)
                values.append(v)
        else:
            for e in entries:
                label, value = e["label"], e["value"]
                by_label[label] = value
                labels.append(label)
                values.append(value)
                if isinstance(value, str):
                    by_label[value] = value            # 兼容直接填英文标识符原值
        maps[name] = {"by_label": by_label, "labels": labels, "values": values}

    # 「属性」列额外兼容 enums.stat 的英文标识符原值：契约 v1.1 的 stat_labels.value
    # 已覆盖全部 stat，显式并入可防未来两表不同步时旧工作簿手填的英文值失效。
    if "stat_labels" in maps and "stat" in maps:
        for v, value in maps["stat"]["by_label"].items():
            maps["stat_labels"]["by_label"].setdefault(v, value)
    return maps


def collect_ranges(snapshot_path):
    """运行时从 80 条现有内容统计各数值字段的区间（不硬编码任何区间值）。

    按「叶子键名」聚合：递归遍历快照，把每个数字归到它所在的键名下。
    """
    buckets = defaultdict(list)
    if not snapshot_path or not Path(snapshot_path).exists():
        return {}

    def walk(node, key_hint):
        if isinstance(node, dict):
            for k, v in node.items():
                walk(v, k)
        elif isinstance(node, list):
            for v in node:
                walk(v, key_hint)
        elif isinstance(node, bool):
            return
        elif isinstance(node, (int, float)):
            buckets[key_hint].append(float(node))

    try:
        data = json.loads(Path(snapshot_path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    walk(data, "")
    return {k: (min(v), max(v)) for k, v in buckets.items() if v}


def range_key_for(field):
    """工作簿数值列 → 快照里的叶子键名。"""
    tail = field.split(".")[-1]
    return RANGE_KEY_ALIASES.get(tail, tail)


def check_range(ranges, key, value, ctx, warnings):
    """超出统计区间只给黄色提醒，不拦截。"""
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return
    bucket = ranges.get(range_key_for(key))
    if not bucket:
        return
    low, high = bucket
    num = float(value)
    if num < low or num > high:
        sheet, row, col = ctx
        fmt = lambda x: ("%g" % x)
        warnings.append(
            f"{sheet} 第 {row} 行 · {col}：填了 {fmt(num)}，超出 {fmt(low)}~{fmt(high)} 的常见区间"
            "（仅黄色提醒，不拦截）"
        )


def merge_missing(dst, src):
    """extras_policy：先按显式列填值，再用 __extras 补齐未被显式列覆盖的字段。

    dst 为显式列结果，src 为 __extras；只补 dst 里缺失的键，已有的以显式列为准。
    对同名嵌套字典递归补齐，保证 behavior_params 等复杂结构一个字段都不丢。
    """
    for k, v in src.items():
        if k not in dst:
            dst[k] = v
        elif isinstance(dst[k], dict) and isinstance(v, dict):
            merge_missing(dst[k], v)


def normalize_aliases(obj, alias):
    """别名归一（台账 P-06）：「投射数量」写回必须落到 count_base。

    alias 形如 {"projectile_count": "count_base"}：把旧键改名到新键；
    若新键已由显式列提供，则以新键为准，丢弃旧键。
    """
    bp = obj.get("behavior_params")
    if not isinstance(bp, dict):
        return
    for old, new in alias.items():
        if old in bp:
            if new in bp:
                bp.pop(old)
            else:
                bp[new] = bp.pop(old)


# ------------------------------------------------------------ 列/行解析 ----
def map_columns(ws, sheet_key, schema, errors, title):
    """把第 1 行中文列头映射成 (列序号 → 列定义 / 参数键)。"""
    header = [c.value for c in ws[1]] if ws.max_row >= 1 else []
    found = {str(h).strip() for h in header if h is not None}
    col_defs = schema["columns"][sheet_key]
    label_to_def = {c["label"]: c for c in col_defs}

    param_label_to_key = {}
    buff_label_to_key = {}
    if sheet_key == "parts":
        # param_columns：参数列按 param_labels 展开成中文列；「形状」已由固定列占用，跳过。
        # 契约 v1.3：增益内容改为 buff_spec 的三条对齐列表列，旧的单列「增益内容」
        # （param=buff_mods）已被替代 —— 旧工作簿里该列即使残留也一律不读，避免把 JSON
        # 原文当普通字符串塞进 behavior_params。
        buff_param = schema.get("buff_spec", {}).get("param", "buff_mods")
        for key, label in schema["param_labels"].items():
            if key == "shape" or key == buff_param:
                continue
            param_label_to_key[label] = key
        for col in schema.get("buff_spec", {}).get("columns", []):
            buff_label_to_key[col["label"]] = col["key"]

    mapping = {}
    for idx, raw_label in enumerate(header):
        if raw_label is None:
            continue
        label = str(raw_label).strip()
        if label in label_to_def:
            mapping[idx] = ("def", label_to_def[label])
        elif label in buff_label_to_key:
            mapping[idx] = ("buff", buff_label_to_key[label])
        elif label in param_label_to_key:
            mapping[idx] = ("param", param_label_to_key[label])
        # 其余列（说明列等）忽略

    for c in col_defs:
        # __extras 是隐藏列，W2 可能不导出；允许缺省
        if c["field"] == "__extras":
            continue
        # 契约 v1.5 向后兼容：图标 / 行为覆盖（v1.5 新升显式列）整列缺失不报错 ——
        # 旧工作簿（真实表现状）没有这两列、值只在 __extras 里，必须照常读通；
        # 整列缺失等价于「每行该列都空」，逐行走 __extras 兜底。
        if c["field"] in V15_FALLBACK_FIELDS:
            continue
        if c["label"] not in found:
            add_error(errors, title, 1, c["label"], "缺少这一列（表头找不到该中文列名）")
    return mapping


def parse_enum_value(enum_info, raw, ctx, errors, col_label):
    """中文下拉值 → 英文标识符；非法值中文报错并列出可选值。"""
    text = str(raw).strip()
    by_label = enum_info["by_label"]
    if text in by_label:
        return by_label[text]
    # 数字型枚举：允许直接填数字（如 0/1/2/7）
    num = as_number(raw)
    if num is not None:
        for v in enum_info["values"]:
            if isinstance(v, (int, float)) and float(v) == float(num):
                return v
    options = "/".join(str(x) for x in enum_info["labels"])
    sheet, row, _ = ctx
    add_error(errors, sheet, row, col_label,
              f"填了『{text}』，只能选 {options}")
    return None


def split_plus(raw):
    """「+」分隔的多值还原成列表，逐项去空格、丢弃空项。"""
    return [p.strip() for p in str(raw).split("+") if p.strip() != ""]


def parse_def_column(col, raw, ctx, enum_maps, errors, warnings, ranges):
    """解析一个显式中文列，返回 (field, value)；空值返回 (field, None)。"""
    field = col["field"]
    label = col["label"]
    typ = col["type"]
    sheet, row, _ = ctx

    if is_blank(raw):
        return field, None

    if field == "__extras":
        return field, raw  # 稍后单独按 JSON 解析

    if typ == "string":
        return field, str(raw).strip()

    if typ == "int":
        num = as_number(raw)
        if num is None or float(num) != int(num):
            add_error(errors, sheet, row, label, f"应填整数，实际填了『{raw}』")
            return field, None
        value = int(num)
        check_range(ranges, field, value, (sheet, row, label), warnings)
        return field, value

    if typ == "float":
        num = as_number(raw)
        if num is None:
            add_error(errors, sheet, row, label, f"应填数字，实际填了『{raw}』")
            return field, None
        value = float(num)
        check_range(ranges, field, value, (sheet, row, label), warnings)
        return field, value

    if typ == "float_list":
        parts = split_plus(raw)
        values = []
        bad = False
        for p in parts:
            num = as_number(p)
            if num is None:
                bad = True
                break
            values.append(float(num))
        if bad:
            add_error(errors, sheet, row, label, f"应填用 + 分隔的数字，实际填了『{raw}』")
            return field, None
        for v in values:
            check_range(ranges, field, v, (sheet, row, label), warnings)
        return field, values

    if typ.startswith("enum:"):
        name = typ.split(":", 1)[1]
        info = enum_maps.get(name)
        if info is None:
            add_error(errors, sheet, row, label, f"契约里找不到词表『{name}』")
            return field, None
        return field, parse_enum_value(info, raw, (sheet, row, label), errors, label)

    if typ.startswith("multienum:"):
        name = typ.split(":", 1)[1]
        info = enum_maps.get(name)
        if info is None:
            add_error(errors, sheet, row, label, f"契约里找不到词表『{name}』")
            return field, None
        values = []
        for part in split_plus(raw):
            v = parse_enum_value(info, part, (sheet, row, label), errors, label)
            if v is not None:
                values.append(v)
        return field, values

    if typ == "ref:skills":
        return field, str(raw).strip()

    if typ == "json":
        # 契约 v1.5：json 型显式列（④「行为覆盖」）单元格填 JSON 原文 → 解析成字典。
        # 空单元格在前面已按「无显式值」返回 None，走 __extras 兜底（旧表零差异）；
        # 非法 JSON 中文报错定位行/列，本行该字段交回 __extras 兜底（错误会拦住落盘）。
        try:
            data = json.loads(str(raw))
        except (ValueError, TypeError):
            add_error(errors, sheet, row, label,
                      f"应为一个 JSON 对象原文（工具自动生成，勿手改），实际填了『{raw}』")
            return field, None
        if not isinstance(data, dict):
            add_error(errors, sheet, row, label,
                      f"应为一个 JSON 对象（工具自动生成，勿手改），实际填了『{raw}』")
            return field, None
        return field, data

    # 兜底：按字符串处理
    return field, str(raw).strip()


def parse_param_column(key, raw, ctx, errors, warnings, ranges, schema, enum_maps):
    """解析 ③ 效果段 的展开参数列（值可能是数字或字符串枚举）。

    契约 v1.3 param_enum_columns：表内写中文的封闭枚举参数（formation / motion）先按词表
    还原英文 value；词表 by_label 同时收英文原值，故旧工作簿的英文值仍兼容。其余参数保持
    数字优先、字符串原样透传。
    """
    sheet, row, _ = ctx
    label = schema["param_labels"].get(key, key)
    if is_blank(raw):
        return None
    enum_name = schema.get("param_enum_columns", {}).get(key)
    if enum_name:
        info = enum_maps.get(enum_name)
        if info is None:
            add_error(errors, sheet, row, label, f"契约里找不到词表『{enum_name}』")
            return None
        return parse_enum_value(info, raw, (sheet, row, label), errors, label)
    num = as_number(raw)
    if num is not None:
        value = int(num) if key in INT_VALUE_KEYS else float(num)
        check_range(ranges, key, value, (sheet, row, label), warnings)
        return value
    # 非数字：formation / motion / scene / angle_deg 之类的字符串参数，原样透传
    return str(raw).strip()


def apply_field(obj, field, value):
    """把解析后的显式列值写进对象（处理带点号的嵌套字段）。"""
    if field.startswith("_") or field == "__extras":
        return  # _parent / _index / _note 不进最终对象
    if field in ("base_damage._keys", "base_damage._values") or field.startswith("stat_modifiers."):
        return  # 合成字段：由下面的 base_damage / stat_modifiers 组装逻辑处理
    if "." in field:
        head, tail = field.split(".", 1)
        obj.setdefault(head, {})[tail] = value
    else:
        obj[field] = value


def parse_extras(raw, ctx, errors):
    """__extras 原样透传：解析成字典；非法 JSON 中文报错。"""
    sheet, row, label = ctx
    if is_blank(raw):
        return {}
    try:
        data = json.loads(str(raw))
    except (ValueError, TypeError):
        add_error(errors, sheet, row, label, "高级数据不是合法的 JSON 原文，请勿手改")
        return {}
    if not isinstance(data, dict):
        add_error(errors, sheet, row, label, "高级数据应为一个 JSON 对象")
        return {}
    return data



# --------------------------------------------------- 契约 v1.3 增益三列 ----
def parse_buff_columns(raws, schema, enum_maps, errors, warnings, ranges, title, row_no):
    """增益三列（buff_spec.columns）→ [{key: value}, ...]；解析失败/个数不一致返回 None。

    三条列都是「+ 分隔、顺序一一对应」的列表：增益属性（中文词表）、增益运算（中文词表）、
    增益数值（数字）。三列条目数必须一致，否则中文报错并逐列定位（返回 None，条目不组装）。
    """
    columns = schema.get("buff_spec", {}).get("columns", [])
    if not columns:
        return None
    parsed = {}
    failed = False
    for col in columns:
        key, label, typ = col["key"], col["label"], col["type"]
        raw = raws.get(key)
        if is_blank(raw):
            parsed[key] = []
            continue
        values = []
        if typ.startswith("multienum:"):
            name = typ.split(":", 1)[1]
            info = enum_maps.get(name)
            if info is None:
                add_error(errors, title, row_no, label, f"契约里找不到词表『{name}』")
                return None
            for part in split_plus(raw):
                v = parse_enum_value(info, part, (title, row_no, label), errors, label)
                if v is not None:
                    values.append(v)
                else:
                    failed = True
        elif typ == "float_list":
            bad = False
            for part in split_plus(raw):
                num = as_number(part)
                if num is None:
                    bad = True
                    break
                values.append(float(num))
            if bad:
                add_error(errors, title, row_no, label,
                          f"应填用 + 分隔的数字，实际填了『{raw}』")
                return None
            for v in values:
                check_range(ranges, "value", v, (title, row_no, label), warnings)
        else:
            add_error(errors, title, row_no, label, f"契约里增益列类型『{typ}』不认识")
            return None
        parsed[key] = values

    if failed:
        # 本行增益列已产生解析错误，不再叠加「个数不一致」的噪声错误
        return None

    keys = [c["key"] for c in columns]
    counts = [len(parsed[k]) for k in keys]
    if len(set(counts)) != 1:
        detail = "、".join(f"{c['label']} {n} 个" for c, n in zip(columns, counts))
        for col in columns:
            add_error(errors, title, row_no, col["label"],
                      f"增益三列个数要一一对应（{detail}），请补齐或删掉多出的项")
        return None
    if not counts[0]:
        return None  # 三列都空：不改动 __extras 里的 buff_mods

    entries = []
    for i in range(counts[0]):
        entries.append({k: parsed[k][i] for k in keys})
    return entries


def build_buff_mods(entries, extras_mods):
    """按 buff_spec.overflow_rule 组装 buff_mods。

    前 N 条（N=表内条目数）按序号沿用该行 __extras 里同序号条目的**全部键**（例如
    channel_mask / require_tags），再用三列覆盖 stat/op/value；__extras 没有对应条目时
    新条目只写 stat/op/value —— **不补 buff_spec.defaults**，否则资源语义会漂移
    （defaults 是 W2 写表侧的缺省约定，不是读侧补键依据）。
    表内条目少于 __extras 条目时，多出的条目按原样追加保留，保证零丢失。
    """
    result = []
    for i, entry in enumerate(entries):
        if i < len(extras_mods) and isinstance(extras_mods[i], dict):
            mod = dict(extras_mods[i])
        else:
            mod = {}
        mod["stat"] = entry["stat"]
        mod["op"] = int(entry["op"])
        mod["value"] = float(entry["value"])
        result.append(mod)
    for extra in extras_mods[len(entries):]:
        result.append(dict(extra) if isinstance(extra, dict) else extra)
    return result


def resolve_conflicts(support_rows, support_metas, schema, errors):
    """④「冲突辅助（+ 分隔）」中文辅助石名 → support_id；英文原值仍兼容。

    映射源是同一张 ④ 表内的「辅助石名 → 代号」（support_ref.rule）。既不是表内中文名、
    也不像英文代号的写法（含中文/空格等）→ 中文报错并定位到该行的「冲突辅助（+ 分隔）」列。
    纯英文代号（与旧工作簿 / 手工填法一致）原样保留，保证旧内容零差异。
    """
    if not support_rows:
        return
    rule = schema.get("support_ref", {})
    col_label = rule.get("column", "冲突辅助（+ 分隔）")
    title = sheet_title(schema, rule.get("sheet", "supports"))
    name_to_id = {}
    for row in support_rows:
        name, rid = row.get("display_name"), row.get("support_id")
        if isinstance(name, str) and name and isinstance(rid, str) and rid:
            name_to_id.setdefault(name, rid)

    for i, row in enumerate(support_rows):
        values = row.get("conflicts_with")
        if not isinstance(values, list):
            continue
        resolved = []
        for token in values:
            if not isinstance(token, str):
                resolved.append(token)
                continue
            text = token.strip()
            if not text:
                continue
            if text in name_to_id:
                resolved.append(name_to_id[text])
            elif ID_RE.fullmatch(text):
                resolved.append(text)          # 旧英文原值兼容
            else:
                add_error(errors, title, support_metas[i]["row"], col_label,
                          f"填了『{text}』，④ 表里找不到这个辅助石中文名"
                          "（也可以直接填英文代号，多个用 + 分隔）")
        row["conflicts_with"] = resolved


def parse_sheet(ws, sheet_key, schema, enum_maps, ranges, errors, warnings,
               id_gen=None):
    """解析一张数据表，返回 (行对象列表, 元信息列表)。

    id_gen：契约 v1.4 新增行代号分配器，签名 id_gen(sheet_key, reserved) → 新代号或 None。
    ② 技能卡 / ④ 辅助石 用到；③ 效果段没有代号列，传 None。
    """
    title = sheet_title(schema, sheet_key)
    mapping = map_columns(ws, sheet_key, schema, errors, title)
    rows, metas = [], []
    dim_keys = dimension_keys(schema)

    # 代号列在元组里的下标（②④ 有，③ 无）：占位说明不算内容，见 is_blank_row
    id_label = "代号（自动，别填）"

    # 契约 v1.5：json 型显式字段集合（④「行为覆盖」；__extras 单独处理、不会进 explicit）
    json_fields = {c["field"] for c in schema["columns"][sheet_key]
                   if c.get("type") == "json"} - {"__extras"}
    row_id_values = {idx for idx, (kind, payload) in mapping.items()
                     if kind == "def" and payload.get("label") == id_label}
    id_field = "gem_id" if sheet_key == "skills" else (
        "support_id" if sheet_key == "supports" else None)

    # ③ 效果段的「关键列」：三列都空才算没填，见 is_blank_row
    key_cols = None
    if sheet_key == "parts":
        key_labels = {"属于哪个技能", "第几段", "效果"}
        key_cols = {idx for idx, (kind, payload) in mapping.items()
                    if kind == "def" and payload.get("label") in key_labels}

    # 契约 v1.4 id_rule.new：先把本表「显式写死的真实代号」全收一遍作为保留集，
    # 新号既不能撞 content/gems 既有文件名，也不能撞表里别的行已经写死的代号。
    reserved = set()
    if id_gen is not None and id_field and row_id_values:
        id_idx = next(iter(row_id_values))
        for cells in ws.iter_rows(min_row=2, values_only=True):
            raw_id = cells[id_idx] if id_idx < len(cells) else None
            if is_blank(raw_id) or is_row_id_placeholder(raw_id):
                continue
            reserved.add(str(raw_id).strip())

    for row_no, cells in enumerate(ws.iter_rows(min_row=2, values_only=True), start=2):
        if all(is_blank(c) for c in cells):
            continue
        # 契约 v1.2 example_row_policy：锁定示例行整行跳过，不校验、不产出、不进中间 JSON。
        if is_example_row(cells, schema):
            continue
        # 契约 v1.4 new_row_policy：预留行只填了代号列的中文占位说明、没填技能名 / 辅助石名
        # → 整行跳过，不校验（否则「代号不是资源文件名」「技能名必填」会误报）、不产出、不报错。
        if is_blank_row(cells, row_id_values, key_cols):
            continue

        explicit = {}       # 显式列解析结果（field → value）
        extras = {}         # __extras 字典
        param_values = {}   # 展开参数列（param key → value）
        buff_raw = {}       # 契约 v1.3 增益三列原始单元格（buff key → 原文）
        meta = {"row": row_no, "_parent": None, "_index": None}

        for idx, (kind, payload) in mapping.items():
            raw = cells[idx] if idx < len(cells) else None
            if kind == "def":
                col = payload
                field, value = parse_def_column(
                    col, raw, (title, row_no, col["label"]),
                    enum_maps, errors, warnings, ranges,
                )
                if value is None:
                    continue
                if field == "__extras":
                    extras = parse_extras(value, (title, row_no, col["label"]), errors)
                    continue
                explicit[field] = value
            elif kind == "buff":
                buff_raw[payload] = raw
            else:
                key = payload
                ctx = (title, row_no, schema["param_labels"].get(key, key))
                value = parse_param_column(
                    key, raw, ctx, errors, warnings, ranges, schema, enum_maps)
                if value is not None:
                    param_values[key] = value

        # 契约 v1.4 id_rule.new：新增行（② 技能卡 / ④ 辅助石）代号为空或是中文占位说明
        # → 按 skill_ / support_ + 三位序号自动生成（避开表内既有代号与 content/gems 已有
        # 文件名，同一批内不重号）。显式填写的代号一律尊重，交给下面的合法性与唯一性校验。
        if id_gen is not None and id_field:
            given = explicit.get(id_field)
            if given is None or is_row_id_placeholder(given):
                new_id = id_gen(sheet_key, reserved)
                if new_id is None:
                    add_error(errors, title, row_no, id_label,
                              "新代号已用尽（"
                              f"{NEW_ID_PREFIX[sheet_key]}001~"
                              f"{NEW_ID_PREFIX[sheet_key]}{10 ** NEW_ID_DIGITS - 1}），"
                              "请先删掉不用的新增行")
                else:
                    explicit[id_field] = new_id
                    meta["new_id"] = new_id
                    name = explicit.get("display_name", "")
                    warnings.append(
                        f"{title} 第 {row_no} 行 · {id_label}：新增『{name}』，"
                        f"工具自动生成代号『{new_id}』（契约 id_rule.new）"
                    )

        # 契约 v1.5：②「图标」填了就必须是 res:// 开头；列缺失/留空不校验
        # （留空 = 未设置，走 __extras 兜底，旧表零差异不受影响）。
        for col in schema["columns"][sheet_key]:
            if col.get("field") == "icon":
                icon = explicit.get("icon")
                if icon is not None and not str(icon).startswith("res://"):
                    add_error(errors, title, row_no, col["label"],
                              "图标必须以 res:// 开头"
                              "（例如 res://mods/jes-skills/content/icons/xxx.png），"
                              f"实际填了『{icon}』；留空则沿用高级数据兜底")

        # 逐列必填校验（含只读代号列）
        for col in schema["columns"][sheet_key]:
            field, label = col["field"], col["label"]
            if not (col.get("required") or col.get("readonly")):
                continue
            if field in ("_parent", "_index"):
                present = explicit.get(field) is not None
            elif field == "__extras":
                continue
            else:
                present = explicit.get(field) is not None
            if not present:
                add_error(errors, title, row_no, label, "必填，不能为空")

        # 代号与文件名一致性：代号必须是合法的资源文件名（小写字母/数字/下划线）
        if id_field and explicit.get(id_field) is not None:
            gem_id = str(explicit[id_field])
            if not ID_RE.fullmatch(gem_id):
                add_error(errors, title, row_no,
                          "代号（自动，别填）",
                          f"代号『{gem_id}』不能作为资源文件名，只能用小写字母/数字/下划线，且以字母开头")

        # 伤害类型与数值个数必须匹配
        dmg_keys = explicit.get("base_damage._keys")
        dmg_values = explicit.get("base_damage._values")
        if (dmg_keys is None) != (dmg_values is None):
            add_error(errors, title, row_no, "基础伤害（用 + 分隔，与上一列顺序对应）",
                      "『伤害类型』和『基础伤害』两列要同时填、同时空")
        elif dmg_keys is not None and len(dmg_keys) != len(dmg_values):
            add_error(errors, title, row_no, "基础伤害（用 + 分隔，与上一列顺序对应）",
                      f"伤害类型有 {len(dmg_keys)} 个，基础伤害有 {len(dmg_values)} 个，个数要一一对应")

        # ---- 组装对象：先显式列，再用 __extras 补齐，显式列非空优先 ----
        # dict 型显式值必须先深拷贝再进 obj：merge_missing 对同名嵌套字典是就地
        # 递归补齐，会把 __extras 残值直接写进 obj 里的那个 dict；若不拷贝，explicit
        # 里的原字典（同一对象）会被一并改写，显式列的「原始值」就丢了。
        obj = {}
        for field, value in explicit.items():
            apply_field(obj, field, copy.deepcopy(value) if isinstance(value, dict) else value)
        merge_missing(obj, extras)

        # 契约 v1.5：json 型显式列（④ 行为覆盖）非空 = 整体生效——直接覆盖。
        # merge_missing 对同名嵌套字典是递归补齐，会让显式列里删掉的旧覆盖键被
        # __extras 残值「复活」，违背「显式列非空时优先」，故用未污染的原始值整体替换。
        for field, value in explicit.items():
            if field in json_fields and isinstance(value, dict):
                obj[field] = copy.deepcopy(value)

        # ---- 契约 v1.6 validation_rules：按表生效的硬拦规则（GUT 同口径）----
        # 阈值与字段全部取自契约 rules，不内置第二份口径。
        vr = schema.get("validation_rules", {})
        sane = vr.get("active_numeric_sane")
        if sane and sane.get("sheet") == sheet_key:
            for rule in sane.get("rules", []):
                field, op = rule.get("field"), rule.get("op")
                label = col_label_for(schema, sheet_key, field)
                value = get_field(obj, field)
                if op == "required":
                    if value is None:
                        add_error(errors, title, row_no, label,
                                  "必须显式填写（允许 0；等级曲线不靠默认值）")
                elif op == ">":
                    num = as_number(value)
                    if num is None or not num > rule.get("value", 0):
                        add_error(errors, title, row_no, label,
                                  f"必须 > {rule.get('value', 0)}，实际填了『{value}』")
        cost_pos = vr.get("support_cost_positive")
        if cost_pos and cost_pos.get("sheet") == sheet_key:
            for rule in cost_pos.get("rules", []):
                field, op = rule.get("field"), rule.get("op")
                label = col_label_for(schema, sheet_key, field)
                if op == ">":
                    num = as_number(obj.get(field))
                    if num is None or not num > rule.get("value", 0):
                        add_error(errors, title, row_no, label,
                                  f"必须 > {rule.get('value', 0)}（防 0 成本辅助），实际填了『{obj.get(field)}』")

        # 参数列覆盖 behavior_params（显式列优先）
        if param_values:
            bp = obj.setdefault("behavior_params", {})
            for k, v in param_values.items():
                bp[k] = v

        # 契约 v1.3：增益三列 → buff_mods（键沿用 __extras 同序号条目，不补默认键；多余条目原样保留）
        if buff_raw:
            buff_entries = parse_buff_columns(
                buff_raw, schema, enum_maps, errors, warnings, ranges, title, row_no)
            if buff_entries:
                bp = obj.setdefault("behavior_params", {})
                extras_mods = bp.get("buff_mods")
                if not isinstance(extras_mods, list):
                    extras_mods = []
                bp["buff_mods"] = build_buff_mods(buff_entries, extras_mods)

        # 伤害类型 + 数值 → base_damage 字典
        if dmg_keys is not None and dmg_values is not None and len(dmg_keys) == len(dmg_values):
            obj["base_damage"] = dict(zip(dmg_keys, dmg_values))

        # 辅助石 stat_modifiers 三列 → 一个 ModifierSpec
        sm_stat = explicit.get("stat_modifiers._stat")
        sm_op = explicit.get("stat_modifiers._op")
        sm_value = explicit.get("stat_modifiers._value")
        if any(v is not None for v in (sm_stat, sm_op, sm_value)):
            if sm_stat is None or sm_op is None or sm_value is None:
                add_error(errors, title, row_no, "属性",
                          "『属性』『运算』『数值』三列要一起填（或都留空由高级数据补齐）")
            else:
                # 显式三列只覆盖「第一条」修正的 stat / op / value；
                # 该条的其余键（channel_mask / require_tags / exclude_tags）从 __extras 原值补齐，
                # 第 2 条起的修正原样保留（例如「召唤强化」有 3 条修正、部分辅助带 require_tags）。
                # 旧实现只取第一条并整体替换，会丢 2 条修正与 require_tags（W5 语义比对发现）。
                extra_mods = obj.get("stat_modifiers")
                base = {}
                tail = []
                if isinstance(extra_mods, list) and extra_mods:
                    if isinstance(extra_mods[0], dict):
                        base = dict(extra_mods[0])
                    tail = [dict(m) for m in extra_mods[1:] if isinstance(m, dict)]
                mod = dict(base)
                mod["stat"] = sm_stat
                mod["op"] = int(sm_op)
                mod["value"] = float(sm_value)
                mod.setdefault("channel_mask", 7)
                mod.setdefault("require_tags", [])
                mod.setdefault("exclude_tags", [])
                obj["stat_modifiers"] = [mod] + tail

        # flags / conflicts_with：「+」分隔的字符串列 → 数组
        for f in ("flags", "conflicts_with"):
            if isinstance(obj.get(f), str):
                obj[f] = split_plus(obj[f])

        # 别名归一（P-06）
        normalize_aliases(obj, schema.get("alias", {}))

        # 形状参数校验（契约 v1.2：shape_keys 是「该形状可用的参数键」，不是必填键）
        if sheet_key == "parts":
            bp = obj.get("behavior_params", {})
            behavior = obj.get("behavior_id")
            shape = bp.get("shape")

            # ① 硬必填只按 behavior_required；形状参数一律不参与必填硬校验。
            #    引导类用「扇形距离」range 承载圆/线尺寸、不填半径/长度/宽度是合法既有口径
            #    （shape_hit.gd 第 17 行、台账 D-46），不再因 shape_keys 缺项报错拦断全链。
            buff_cols = schema.get("buff_spec", {}).get("columns", [])
            buff_param = schema.get("buff_spec", {}).get("param", "buff_mods")
            for key in sorted(schema["behavior_required"].get(behavior, [])):
                if key not in bp or bp[key] is None or bp[key] == "":
                    if key == buff_param and buff_cols:
                        # 契约 v1.3：增益内容不再是一列，报错定位到三列中的第一列并说清怎么补
                        add_error(errors, title, row_no, buff_cols[0]["label"],
                                  "当前效果要求必填『增益内容』："
                                  "增益属性/增益运算/增益数值三列不能都为空")
                        continue
                    label = schema["param_labels"].get(key, key)
                    add_error(errors, title, row_no, label,
                              f"当前效果要求必填『{label}』，该参数列为空")

            # ② 「填了的值必须在合法键范围内」：参数列由 map_columns 按 param_labels
            #    展开成固定中文列，列头不在 param_labels 的列根本不会进入 behavior_params，
            #    故策划手填的参数键天然落在合法键范围内；这里不额外对 __extras 透传的
            #    unknown_param 做拦截（unknown_param_policy 要求零丢失）。形状列的枚举值
            #    合法性也已在 parse_def_column 的 enum:shape 处校验过。

            # ③ 「该形状全部尺寸参数列均为空」→ 只给黄色提醒、不拦截。
            #    尺寸键取 shape_keys 全并集（含 range），引导类用 range 承载尺寸不会被误报。
            if shape and schema["shape_keys"].get(shape):
                has_dimension = any(
                    k in bp and bp[k] is not None and bp[k] != ""
                    for k in dim_keys
                )
                if not has_dimension:
                    shape_label = shape_cn_label(schema, shape)
                    warnings.append(
                        f"{title} 第 {row_no} 行 · 形状『{shape_label}』："
                        "未填任何尺寸参数（半径/长度/宽度/扇形距离等），按缺省承载"
                        "（仅黄色提醒，不拦截）"
                    )

            # ④ 契约 v1.3 硬拦（与 tests/skills/test_content_contract.gd 第 158–165 行同口径）：
            #    效果=bhv_aoe_burst 且 形状≠点 且没有任何一组尺寸
            #    （radius / length+width / arc_deg+range）→ 中文报错定位到「半径」列、不生成中间 JSON；
            #    点爆（shape=pt）豁免。形状留空按 ≠点 处理，与 GUT 的 p.get(&"shape",&"") 一致。
            aoe_rule = schema.get("validation_rules", {}).get("aoe_size_required", {})
            if (aoe_rule
                    and behavior == aoe_rule.get("behavior", "bhv_aoe_burst")
                    and shape != "pt"):
                has_aoe_dim = (
                    has_value(bp, "radius")
                    or (has_value(bp, "length") and has_value(bp, "width"))
                    or (has_value(bp, "arc_deg") and has_value(bp, "range"))
                )
                if not has_aoe_dim:
                    add_error(errors, title, row_no, "半径",
                              "效果是『范围爆发』且形状不是『点』时，必须至少填一组尺寸："
                              "半径，或 长度+宽度，或 扇形角度+扇形距离（点爆豁免）")

            # ⑤ 契约 v1.6 channel_circ_range_hint：channel×circ 只填 range 时黄色提醒（不拦截）。
            #    触发条件与文案都取自契约 when / text（按空格分词解析，不内置第二份口径）；
            #    现有 3 条 channel×circ 合法内容（引导领域/蓄力大爆/原地旋风）必须照常通过。
            hint = vr.get("channel_circ_range_hint") if isinstance(vr, dict) else None
            if hint:
                when = str(hint.get("when", ""))
                conds = dict(re.findall(r"(\w+)=(\w+)", when))
                empty_keys = re.findall(r"(\w+) 为空", when)
                filled_keys = re.findall(r"(\w+) 非空", when)
                if (conds
                        and behavior == conds.get("behavior")
                        and shape == conds.get("shape")
                        and all(not has_value(bp, k) for k in empty_keys)
                        and all(has_value(bp, k) for k in filled_keys)):
                    shape_label = shape_cn_label(schema, shape)
                    warnings.append(
                        f"{title} 第 {row_no} 行 · 形状『{shape_label}』：{hint.get('text', '')}")

        meta["_parent"] = explicit.get("_parent")
        meta["_index"] = explicit.get("_index")
        rows.append(obj)
        metas.append(meta)

    return rows, metas


# ------------------------------------------------------------ 跨表校验 ----
def cross_validate(skill_rows, skill_metas, part_rows, part_metas,
                   support_rows, support_metas, schema, errors, ledger=None,
                   warnings=None):
    """代号重复、技能名关联、效果段归并、段号检查、新技能卡必须有有效效果段、目录驱动数量汇报。"""
    title_s = sheet_title(schema, "skills")
    title_p = sheet_title(schema, "parts")
    title_u = sheet_title(schema, "supports")

    # 代号唯一（全局：技能 + 辅助石，避免生成时文件名撞车）
    seen = {}
    for rows, metas, title, id_field in (
        (skill_rows, skill_metas, title_s, "gem_id"),
        (support_rows, support_metas, title_u, "support_id"),
    ):
        for i, row in enumerate(rows):
            rid = row.get(id_field)
            if not rid:
                continue
            row_no = metas[i]["row"]
            if rid in seen:
                add_error(errors, title, row_no, "代号（自动，别填）",
                          f"代号『{rid}』重复，与 {seen[rid]} 冲突")
            else:
                seen[rid] = f"{title} 第 {row_no} 行"

    # 技能名唯一（供「属于哪个技能」关联）
    name_to_row = {}
    for i, row in enumerate(skill_rows):
        name = row.get("display_name")
        if not name:
            continue
        if name in name_to_row:
            add_error(errors, title_s, skill_metas[i]["row"], "技能名",
                      f"技能名『{name}』重复，效果段无法判断属于哪个技能")
        else:
            name_to_row[name] = i

    for row in skill_rows:
        row["parts"] = []

    # 效果段归并到技能，按 _index 排序
    grouped = defaultdict(list)
    for i, (row, meta) in enumerate(zip(part_rows, part_metas)):
        parent = meta["_parent"]
        index = meta["_index"]
        row_no = meta["row"]
        if parent is None:
            continue  # 必填校验已报错
        if parent not in name_to_row:
            add_error(errors, title_p, row_no, "属于哪个技能",
                      f"填了『{parent}』，{title_s} 里找不到这个技能名")
            continue
        if not isinstance(index, int) or index < 1:
            add_error(errors, title_p, row_no, "第几段", "应填正整数（1、2……）")
            continue
        grouped[parent].append((index, row_no, row))

    for parent, items in grouped.items():
        indexes = [x[0] for x in items]
        for idx in set(indexes):
            if indexes.count(idx) > 1:
                rows = [str(x[1]) for x in items if x[0] == idx]
                add_error(errors, title_p, items[0][1], "第几段",
                          f"技能『{parent}』的第 {idx} 段重复（第 {'、'.join(rows)} 行）")
        items.sort(key=lambda x: x[0])
        skill_rows[name_to_row[parent]]["parts"] = [x[2] for x in items]

        # 契约 v1.6 part_form_tag_present（GUT test_a5 同口径硬拦）：②③ 联查——
        # 每段行为自带形态标签（enums.behavior[].form_tag），所属技能「标签」列必须包含它，
        # 否则「辅助按标签过滤」会失准；中文定位「③ 效果段 第 N 行 · 效果」并指明缺哪个标签。
        # behavior_id 为空由 ③「效果」列必填校验拦截（定位相同），这里不重复报。
        tag_rule = schema.get("validation_rules", {}).get("part_form_tag_present")
        if tag_rule:
            behavior_entries = schema["enums"].get("behavior", [])
            form_tag_by_behavior = {e["value"]: e.get("form_tag") for e in behavior_entries}
            behavior_label_cn = {e["value"]: e["label"] for e in behavior_entries}
            tag_label_cn = {e["value"]: e["label"] for e in schema["enums"].get("tag", [])}
            skill = skill_rows[name_to_row[parent]]
            tags = set(skill.get("tags") or [])
            for _idx, part_row_no, part in items:
                behavior_id = part.get("behavior_id")
                if not behavior_id:
                    continue        # ③「效果」必填校验已在同行同列报错
                form_tag = form_tag_by_behavior.get(behavior_id)
                if form_tag and form_tag not in tags:
                    add_error(errors, title_p, part_row_no, "效果",
                              f"所属技能『{skill.get('display_name')}』的"
                              f"『{behavior_label_cn.get(behavior_id, behavior_id)}』段"
                              f"缺形态标签『{tag_label_cn.get(form_tag, form_tag)}』，"
                              "请在② 该技能的『标签（用 + 分隔）』列补上"
                              "（辅助按标签过滤会失准）")

    # 契约 v1.4 new_row_policy.requires_parts：新增技能卡至少要有一段有效效果段
    # （③「属于哪个技能」按技能名指向它），否则中文报错定位到「② 技能卡 第 N 行 · 效果段」。
    # 对「新增」硬拦：判定口径与目录驱动数量汇报的「新增」一致 ——
    #   ① 本行代号由工具生成（meta.new_id），或
    #   ② 本行代号不在内容台账（content/gems/{active,supports}）里，即表里新加、还没有落盘资源；
    # 对「表里其余技能卡」（不在台账里、代号沿用）沿用二期口径只做中文提示，便于早期工作簿
    # 定位漏填效果段；既有 67 条技能卡的资源本来就在台账里，一条都不会被这条规则打扰。
    for i, row in enumerate(skill_rows):
        if row.get("parts"):
            continue
        meta = skill_metas[i]
        gem_id = row.get("gem_id")
        generated = bool(meta.get("new_id"))
        unknown = bool(ledger) and gem_id not in ledger["ids"]
        if not (generated or unknown):
            continue
        prefix = "新增技能" if generated else "技能"
        add_error(errors, title_s, meta["row"], "效果段",
                  f"{prefix}『{row.get('display_name')}』没有任何有效效果段："
                  f"新增技能卡至少要有一段效果段——请在『{title_p}』里加一行，"
                  "『属于哪个技能』填这个技能名（一字不差）、『第几段』从 1 开始、『效果』选一个"
                  "（只有『效果段』三列都填了才算数）")

    # 契约 v1.3：④「冲突辅助（+ 分隔）」中文辅助石名 → support_id（旧英文原值兼容）
    resolve_conflicts(support_rows, support_metas, schema, errors)

    # 契约 v1.7 new_row_policy.count_guard（目录驱动）：数量断言随内容目录实际数量走，
    # 策划新增 / 删除技能或辅助石后不再「拦截不生成」，只做中文汇报——
    # 『新增 N 条 / 删除 N 条，测试断言已随目录自动对齐』；删除类差异另加
    # 「内容删除不可逆，须制作人拍板」。基线（有效内容台账）运行时从
    # content/gems/{active,supports} 统计，不硬编码数字；判定用「表里代号与台账
    # 文件名的差」而不是单纯比数量：数量刚好相等但内容换了，同样要汇报。
    # 只对「正式配置表」生效：表内技能代号绝大多数来自台账才算（见 count_guard_applies）；
    # 小夹具（自检 / 策划自查的最小表）不汇报、不打扰。
    if ledger and count_guard_applies(skill_rows, ledger) and warnings is not None:
        for label, id_field, rows, base_ids in (
            ("技能", "gem_id", skill_rows, ledger.get("skill_ids") or set()),
            ("辅助石", "support_id", support_rows, ledger.get("support_ids") or set()),
        ):
            ids = [r.get(id_field) for r in rows if r.get(id_field)]
            id_set = set(ids)
            added = [i for i in ids if i not in ledger["ids"]]
            removed = sorted(base_ids - id_set)
            if not added and not removed:
                continue
            warnings.append(count_guard_report(label, added, removed))

    return skill_rows, support_rows


# ------------------------------------------------------------ 主流程 ----
def main(argv=None):
    parser = argparse.ArgumentParser(description="W3：工作簿 → 中间 JSON（分层中文校验）")
    parser.add_argument("workbook", help="中文 Excel 工作簿路径")
    parser.add_argument("--schema", default=str(DEFAULT_SCHEMA), help="冻结契约 schema.json（只读）")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="中间 JSON 输出路径")
    parser.add_argument("--errors", default=str(DEFAULT_ERRORS), help="中文错误清单输出路径")
    parser.add_argument("--snapshot", default=str(DEFAULT_SNAPSHOT),
                        help="数值快照（只读，用于运行时统计数值区间）")
    parser.add_argument("--content", default=str(CONTENT_DIR),
                        help="有效内容台账（只读）：content/gems 目录，用于新增代号避重与目录驱动数量汇报基线")
    args = parser.parse_args(argv)

    errors_path = Path(args.errors)
    out_path = Path(args.out)
    errors_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # 事务式（W5 根因 3）：本次运行一开始就清掉上一次的中间产物及其临时文件。
    # 这样无论校验成功、校验失败还是中途异常，生成器都不可能读到过期的 build_input.json。
    # 只清 _tmp 下自己产出的文件，不触碰任何共享文件 / content/gems/。
    stale_part = out_path.with_suffix(out_path.suffix + ".part")
    for stale in (out_path, stale_part):
        if stale.exists():
            stale.unlink()

    errors, warnings = [], []

    book_path = Path(args.workbook)
    if not book_path.exists():
        add_error(errors, "工作簿", 0, "文件", f"找不到工作簿『{book_path}』")
        return finish(False, errors, warnings, out_path, errors_path, args.workbook)

    schema_path = Path(args.schema)
    if not schema_path.exists():
        add_error(errors, "契约", 0, "文件", f"找不到冻结契约『{schema_path}』")
        return finish(False, errors, warnings, out_path, errors_path, args.workbook)
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    enum_maps = build_enum_maps(schema)
    ranges = collect_ranges(args.snapshot)

    wb = load_workbook(book_path, data_only=True)
    book_titles = {str(name).strip(): name for name in wb.sheetnames}

    def find_ws(key):
        title = sheet_title(schema, key)
        if title in book_titles:
            return wb[book_titles[title]], title
        if title in wb.sheetnames:
            return wb[title], title
        # 兜底：按 key 或去掉编号后的名字匹配
        for name in wb.sheetnames:
            if key in str(name) or str(name).endswith(title[1:] if len(title) > 1 else title):
                return wb[name], str(name)
        add_error(errors, title, 0, "页签", f"工作簿里找不到页签『{title}』")
        return None, title

    ws_s, _ = find_ws("skills")
    ws_p, _ = find_ws("parts")
    ws_u, _ = find_ws("supports")

    if ws_s is None or ws_p is None or ws_u is None:
        return finish(False, errors, warnings, out_path, errors_path, args.workbook)

    # 契约 v1.4 / v1.7：有效内容台账（content/gems/{active,supports} 的资源文件名）+ 新增行代号分配器。
    # 台账为空（缺目录）时不做数量汇报（目录驱动口径只由台账驱动）；此时新号仍按
    # 「本批次已分配号 + 表内显式号」避重。
    ledger = load_content_ledger(args.content)
    used_ids = set(ledger["ids"]) if ledger else set()

    def id_gen(sheet_key, reserved):
        return next_new_id(NEW_ID_PREFIX[sheet_key],
                           used_live=used_ids, used_reserved=reserved)

    skill_rows, skill_metas = parse_sheet(ws_s, "skills", schema, enum_maps, ranges, errors, warnings,
                                          id_gen=id_gen)
    part_rows, part_metas = parse_sheet(ws_p, "parts", schema, enum_maps, ranges, errors, warnings)
    support_rows, support_metas = parse_sheet(ws_u, "supports", schema, enum_maps, ranges, errors, warnings,
                                              id_gen=id_gen)

    skill_rows, support_rows = cross_validate(
        skill_rows, skill_metas, part_rows, part_metas,
        support_rows, support_metas, schema, errors, ledger=ledger, warnings=warnings
    )

    ok = len(errors) == 0
    return finish(ok, errors, warnings, out_path, errors_path, args.workbook,
                  skill_rows=skill_rows, support_rows=support_rows)


def finish(ok, errors, warnings, out_path, errors_path, workbook_name,
           skill_rows=None, support_rows=None):
    """统一收口：失败不生成中间 JSON；成功生成 build_input.json。两种情况都写 errors.json。"""
    report = {
        "ok": ok,
        "count": len(errors),
        "errors": errors,
        "warnings": warnings,
        "text": "\n".join(e["text"] for e in errors),
    }
    errors_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    if not ok:
        # W5 根因 3：失败分支再次兜底，确保中间 JSON 与其临时文件都不存在，
        # 保证生成器绝不可能读到上一次自检遗留的过期数据。
        stale_part = out_path.with_suffix(out_path.suffix + ".part")
        for stale in (out_path, stale_part):
            if stale.exists():
                stale.unlink()
        print(f"校验未通过，共 {len(errors)} 处错误（未生成任何中间 JSON、未落盘，已清理旧中间 JSON）：")
        for e in errors:
            print("  " + e["text"])
        for w in warnings:
            print("  [黄色提醒] " + w)
        return 1

    payload = {
        "version": "1.0",
        "source": Path(workbook_name).name,
        "skills": skill_rows or [],
        "supports": support_rows or [],
        "warnings": warnings,
    }
    # 原子写入，避免留下半截 JSON
    tmp = out_path.with_suffix(out_path.suffix + ".part")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    tmp.replace(out_path)

    n_parts = sum(len(s.get("parts", [])) for s in (skill_rows or []))
    print(f"校验通过：{len(skill_rows or [])} 个技能、{n_parts} 个效果段、"
          f"{len(support_rows or [])} 个辅助石，中间 JSON 已写入 {out_path}")
    for w in warnings:
        print("  [黄色提醒] " + w)
    return 0


if __name__ == "__main__":
    sys.exit(main())
