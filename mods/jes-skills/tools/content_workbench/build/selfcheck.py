# -*- coding: utf-8 -*-
"""
W3 自检 · 交付物 C：不依赖 W2 的产物，自己用 openpyxl 构造最小测试工作簿，实测 A/B 全链。

自造：1 个技能 + 1 个效果段 + 1 个辅助石的干净工作簿，以及追加 1 行故意填错的工作簿。
实测四项（外加事务回滚、分层校验变体、契约 v1.1 词表、契约 v1.2 三项增量自检）：
  ① A 正常路径 → 能生成中间 JSON；
  ② A 填错路径 → 中文报错定位到行/列且不生成 JSON；
  ③ B（调用 Godot）→ 生成 .tres 且逐条 load() 回读字段一致；
  ④ 同一输入跑两次 → 产物 .tres 逐字节一致。

契约 v1.2 增量三项：示例行被跳过（【示例】新标记 + v1.1 遗留文本均兼容）、
引导类「只有扇形距离」能通过、校验失败后旧 build_input.json 不再存在；
同时把旧的「形状与参数列不匹配」硬报错预期改为「形状参数不再硬必填」。

契约 v1.3 增量（二期 P2 读侧 / P4）：
  · ③ 阵型 / 运动方式写中文 → 回读还原英文 value，旧英文原值仍兼容，非法中文报错定位；
  · ③ 增益三列（buff_spec.columns）→ buff_mods：键沿用 __extras 同序号条目、不补默认键、
    多余条目原样追加；三列个数不一致 / 非法属性 → 中文报错定位且不生成中间 JSON；
  · ④ 冲突辅助写辅助石中文名 → 按表内「辅助石名 → 代号」还原 support_id，旧英文原值兼容，
    映射不到 → 中文报错；中文属性词表沿用 v1.1 全量用例；
  · aoe 尺寸硬拦与 GUT test_a6 同口径：点爆（pt）豁免通过、环缺尺寸硬拦报错定位「半径」；
    非 aoe 的「未填尺寸」仍只给黄色提醒。

契约 v1.4 增量（三期 P7-B 读侧：新行 → 新技能）：
  · 全预留行不填（②④ 代号列只有中文占位说明、③ 全空）→ 正常通过、仍是 67/95/13、无多余条目；
  · 新技能卡 + 1 段效果段（代号留空）→ 按 id_rule.new 自动生成 skill_001、效果段正确归并、
    命中数量守卫（新会打破 67，须上级 AI 裁定）且未生成中间 JSON；
  · 新技能卡缺效果段 → 中文报错定位「② 技能卡 第 N 行 · 效果段」；
  · 新技能代号写成既有代号 → 中文报错「代号重复」；写成非法文件名 / skill_001 撞基线 → 中文报错；
  · 代号留空自动生成规则（从 001 起、取最小未占用号、同一批不重号、新角色从 001 重开）；
  · 新辅助石代号留空 → support_001 + 数量守卫；同批新技能 + 新辅助石 → 代号互不冲突。

全部原始输出保留在 _tmp/selfcheck/logs/，汇总写在 _tmp/selfcheck/selfcheck_summary.txt。
干跑产物一律落在 _tmp/ 下，绝不写 content/gems/。

用法：
  python selfcheck.py [--godot <Godot 控制台 exe 路径>]
"""

import argparse
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

from openpyxl import Workbook, load_workbook

# ---------------------------------------------------------------- 路径 ----
HERE = Path(__file__).resolve().parent          # .../tools/content_workbench/build
WORKBENCH = HERE.parent                        # .../tools/content_workbench
MODULE = WORKBENCH.parents[1]                  # .../mods/jes-skills
PROJECT = WORKBENCH.parents[3]                 # 项目根
SCHEMA = WORKBENCH / "schema.json"
SNAPSHOT = MODULE / "tests" / "skills" / "content_snapshot.json"
A_SCRIPT = HERE / "read_workbook.py"
B_SCRIPT = "res://mods/jes-skills/tools/content_workbench/build/build_from_json.gd"

BASE = WORKBENCH / "_tmp" / "selfcheck"
LOGS = BASE / "logs"
RES_BASE = "res://mods/jes-skills/tools/content_workbench/_tmp/selfcheck"

OK_XLSX = BASE / "ok.xlsx"
BAD_XLSX = BASE / "bad.xlsx"
OK_DIR = BASE / "ok"
BAD_DIR = BASE / "bad"
OK_ERRORS = OK_DIR / "errors.json"
BAD_JSON = BAD_DIR / "build_input.json"
BAD_ERRORS = BAD_DIR / "errors.json"

# 主验收走 A/B 的默认路径（W4 只读调用时使用的命令形态）：
# A 默认输出 _tmp/build_input.json，B 默认读它、默认写 _tmp/dryrun/。
OK_JSON = WORKBENCH / "_tmp" / "build_input.json"
DRYRUN = WORKBENCH / "_tmp" / "dryrun"
DEFAULT_STAGING = WORKBENCH / "_tmp" / "dryrun_staging"

DEFAULT_GODOT = r"C:/Users/Administrator/AppData/Roaming/Ryko.GodotHub/godot-versions/4.7.1-stable/Godot_v4.7.1-stable_win64_console.exe"

GODOT = ""


# ---------------------------------------------------------------- 输出 ----
def run(name, cmd):
    """跑子进程，控制台打印完整原始输出，并原样留档到 logs/<name>.log。"""
    LOGS.mkdir(parents=True, exist_ok=True)
    log = LOGS / (name + ".log")
    header = "$ " + " ".join(shlex.quote(str(c)) for c in cmd) + "\n"
    proc = subprocess.run(
        [str(c) for c in cmd],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    body = (header
            + "--- stdout ---\n" + (proc.stdout or "")
            + "--- stderr ---\n" + (proc.stderr or "")
            + ("\n--- 退出码 %d ---\n" % proc.returncode))
    log.write_text(body, encoding="utf-8")
    print(f"\n===== [{name}] 退出码 {proc.returncode}，日志 {log} =====")
    for line in (proc.stdout or "").splitlines():
        print("  | " + line)
    if proc.stderr:
        for line in proc.stderr.splitlines():
            print("  | [stderr] " + line)
    return proc, body


def indent_print(text):
    for line in text.splitlines():
        print("  | " + line)


# ------------------------------------------------------------ 构造工作簿 ----
def headers_for(schema, sheet_key, with_params=False):
    labels = [c["label"] for c in schema["columns"][sheet_key]]
    if with_params:
        # param_columns：参数列按 param_labels 展开成中文列；「形状」已由固定列占用。
        # 契约 v1.3：增益内容改为 buff_spec 的三条对齐列表列（替换旧的单列「增益内容」），
        # 与 W2 真实工作簿保持同构，让增益回读链路进入正常路径实测。
        buff = schema.get("buff_spec", {})
        buff_labels = [c["label"] for c in buff.get("columns", [])]
        buff_param = buff.get("param", "buff_mods")
        for key, label in schema["param_labels"].items():
            if key == "shape":
                continue
            if buff_labels and key == buff_param:
                labels.extend(buff_labels)
                continue
            labels.append(label)
    return labels


def write_sheet(ws, headers, rows):
    ws.append(headers)
    for row in rows:
        ws.append([row.get(label) for label in headers])


def sheet_by_key(schema, key):
    for s in schema["sheets"]:
        if s["key"] == key:
            return s["title"]
    return key


def build_workbooks(schema):
    """构造干净工作簿 ok.xlsx 与追加 1 行故意错的 bad.xlsx（6 页签，中文列头）。"""
    BASE.mkdir(parents=True, exist_ok=True)
    wb = Workbook()
    wb.remove(wb.active)
    for s in schema["sheets"]:
        ws = wb.create_sheet(s["title"])
        if s.get("hidden"):
            ws.sheet_state = "hidden"

    # ① 先看这里：三句话中文说明（A 不解析）
    readme = wb[sheet_by_key(schema, "readme")]
    readme.append(["技能配置表 · W3 自检用最小工作簿"])
    readme.append(["一、只改白色格；黄色格是本行必填；灰色格不用填。"])
    readme.append(["二、下拉值必须选词表里的中文；多值用 + 分隔。"])
    readme.append(["三、代号列是自动生成的，请勿手改；高级数据列请勿手改。"])

    h_skill = headers_for(schema, "skills")
    h_part = headers_for(schema, "parts", with_params=True)
    h_support = headers_for(schema, "supports")

    # ② 技能卡：1 个技能
    skill_row = {
        "技能名": "自检·寒霜脉冲",
        "代号（自动，别填）": "w3_selfcheck_frost",
        "施法方式": "主动施放",
        "消耗类型": "法力",
        "消耗数值": 12,
        "冷却（秒）": 2.5,
        "前摇（秒）": 0.5,
        "最多充能": 0,
        "充能回复（秒）": 0,
        "每级变强": 0.1,
        "成长拐点等级": 0,
        "拐点后每级变强": 0,
        "标签（用 + 分隔）": "法术+范围+冰冷",
        "允许的辅助标签": "法术+冰冷",
        "备注（不进游戏）": "W3 自检用",
        "高级数据（工具自动，勿改）": "{}",
    }

    # ③ 效果段：1 个效果段；__extras 里故意放旧别名 projectile_count 与复杂参数，
    #    用来实测「__extras 原样透传」+「投射数量别名归一到 count_base」。
    part_extras = json.dumps({
        "behavior_params": {
            "projectile_count": 9,
            "delay": 0.35,
            "hit_count": 1,
            "hit_interval": 0.0,
        }
    }, ensure_ascii=False)
    part_row = {
        "属于哪个技能": "自检·寒霜脉冲",
        "第几段": 1,
        "效果": "范围爆发",
        "形状": "圆",
        "伤害类型（用 + 分隔）": "冰冷",
        "基础伤害（用 + 分隔，与上一列顺序对应）": "140",
        "伤害效用": 1.0,
        "命中通道": "命中",
        "高级数据（工具自动，勿改）": part_extras,
        "半径": 130,
    }

    # ④ 辅助石：1 个辅助石；显式三列组装 ModifierSpec，__extras 补齐其余字段
    # 「属性」改用契约 v1.1 enums.stat_labels 的中文 label（唯一真源）；取 value=crit_chance
    # 的那一项，基线产物与上一波字节一致，同时把契约词表链路纳入正常路径实测。
    stat_pairs = [(e["label"], e["value"]) for e in schema["enums"]["stat_labels"]]
    base_stat_label = next(label for label, value in stat_pairs if value == "crit_chance")
    support_extras = json.dumps({
        "behavior_overrides": {"pierce": {"add": 2.0}},
        "flags": ["cannot_crit"],
        "conflicts_with": ["w3_selfcheck_other"],
        "require_any_tags": ["aoe"],
    }, ensure_ascii=False)
    support_row = {
        "辅助石名": "自检·锐化",
        "代号（自动，别填）": "w3_selfcheck_sharp",
        "需要的标签（全部，+ 分隔）": "法术",
        "需要的标签（任一，+ 分隔）": None,
        "添加标签": "冰冷",
        "排除标签": None,
        "消耗倍率": 1.25,
        "属性": base_stat_label,
        "运算": "固定加值",
        "数值": 15,
        "特性（+ 分隔）": None,
        "冲突辅助（+ 分隔）": None,
        "备注（不进游戏）": "W3 自检用",
        "高级数据（工具自动，勿改）": support_extras,
    }

    write_sheet(wb[sheet_by_key(schema, "skills")], h_skill, [skill_row])
    write_sheet(wb[sheet_by_key(schema, "parts")], h_part, [part_row])
    write_sheet(wb[sheet_by_key(schema, "supports")], h_support, [support_row])

    # ⑤ 可选项：按契约放中文词表（A 不解析，仅模拟 W2 的真实工作簿）
    options = wb[sheet_by_key(schema, "options")]
    options.append(["形状词表"])
    for e in schema["enums"]["shape"]:
        options.append([e["label"]])
    options.append(["属性词表（契约 v1.1 enums.stat_labels）"])
    for e in schema["enums"]["stat_labels"]:
        options.append([e["label"]])

    # ⑥ 检查结果：留给 W4，这里保持空
    wb.save(OK_XLSX)

    # bad.xlsx：在 ③ 效果段 追加 1 行故意填错（一行触发多类分层校验）
    bad = load_workbook(OK_XLSX)
    ws_p = bad[sheet_by_key(schema, "parts")]
    bad_row = {
        "属于哪个技能": "不存在的技能名",
        "第几段": None,                 # 必填缺失
        "效果": "范围爆发",
        "形状": "方形",                 # 枚举非法
        "伤害类型（用 + 分隔）": "冰冷+火焰",
        "基础伤害（用 + 分隔，与上一列顺序对应）": "100",   # 个数不匹配
        "伤害效用": "abc",              # 数值类型错误
        "命中通道": "命中",
        "高级数据（工具自动，勿改）": "{}",
    }
    ws_p.append([bad_row.get(label) for label in h_part])
    bad.save(BAD_XLSX)
    print(f"已构造：{OK_XLSX}（1 技能 + 1 效果段 + 1 辅助石）、{BAD_XLSX}（追加 1 行故意错）")


# ------------------------------------------------------------ 变异工作簿 ----
def col_of(ws, label):
    for c in ws[1]:
        if c.value == label:
            return c.column
    raise KeyError(f"找不到列：{label}")


def mutate(src, dst, edits):
    """edits: {页签名: [(行号, 列名, 新值), ...]}；新值为 None 表示清空该单元格。

    注意：openpyxl 的 ws.cell(..., value=None) 会跳过赋值、保留原值，
    因此这里显式写 cell.value = value，保证「清空尺寸参数列」这类变异真的生效。
    """
    wb = load_workbook(src)
    for sheet_title, changes in edits.items():
        ws = wb[sheet_title]
        for row_no, label, value in changes:
            ws.cell(row=row_no, column=col_of(ws, label)).value = value
    dst.parent.mkdir(parents=True, exist_ok=True)
    wb.save(dst)


def drop_columns(src, dst, sheet_title, labels):
    """按中文列名删除整列（用于构造「旧工作簿」：没有 v1.3 增益三列）。"""
    wb = load_workbook(src)
    ws = wb[sheet_title]
    indexes = sorted((col_of(ws, label) for label in labels), reverse=True)
    for idx in indexes:
        ws.delete_cols(idx)
    dst.parent.mkdir(parents=True, exist_ok=True)
    wb.save(dst)


def duplicate_skill(src, dst):
    """复制 ② 技能卡 第 2 行到第 3 行，制造代号重复 + 技能名重复。"""
    wb = load_workbook(src)
    ws = wb["② 技能卡"]
    values = [c.value for c in ws[2]]
    for i, v in enumerate(values, start=1):
        ws.cell(row=3, column=i, value=v)
    dst.parent.mkdir(parents=True, exist_ok=True)
    wb.save(dst)


def build_stat_vocab_workbook(schema, src, dst):
    """用契约 v1.1 enums.stat_labels 的全部中文 label 造 N 行辅助石（每行一个属性）。

    用于验证「中文属性词表 → 英文标识符」全量还原，而不是抽样。
    """
    wb = load_workbook(src)
    ws = wb["④ 辅助石"]
    headers = [c.value for c in ws[1]]
    base_row = [c.value for c in ws[2]]

    def col(label):
        return headers.index(label)

    pairs = [(e["label"], e["value"]) for e in schema["enums"]["stat_labels"]]
    for i, (label, _value) in enumerate(pairs):
        row = list(base_row)
        row[col("属性")] = label
        row[col("代号（自动，别填）")] = "w3_stat_%02d" % i
        row[col("辅助石名")] = "属性词表校验%02d" % i
        if i == 0:
            for c, v in enumerate(row, start=1):
                ws.cell(row=2, column=c, value=v)
        else:
            ws.append(row)
    dst.parent.mkdir(parents=True, exist_ok=True)
    wb.save(dst)
    return pairs


def append_rows(src, dst, extra_by_sheet):
    """往工作簿各页签追加行：extra_by_sheet = {页签名: [ {中文列名: 值}, ... ]}。

    用于构造示例行自检：追加的行若被 A 当真实数据，会触发非法代号/非法形状/必填缺失
    等错误；若被正确跳过，A 仍应退出码 0，产物行数与追加前一致。
    """
    wb = load_workbook(src)
    for sheet_title, rows in extra_by_sheet.items():
        ws = wb[sheet_title]
        headers = [c.value for c in ws[1]]
        for row in rows:
            ws.append([row.get(label) for label in headers])
    dst.parent.mkdir(parents=True, exist_ok=True)
    wb.save(dst)


# --------------------------------------------- 契约 v1.4 内容台账（只读） ----
def load_ledger(content_dir=None):
    """读有效内容台账（content/gems 的 .tres 文件名），作为新增代号避重与数量守卫基线。

    返回 {"skills": [技能代号], "supports": [辅助石代号], "ids": {全部代号}}；目录缺失返回 None。
    与 read_workbook.py 的 load_content_ledger 同口径：support_ 前缀算辅助石，其余算技能。
    """
    path = Path(content_dir) if content_dir else MODULE / "content" / "gems"
    if not path.is_dir():
        return None
    # 目录布局（实测）：content/gems/active/*.tres = 67 主动技能，
    # content/gems/supports/*.tres = 13 辅助石，content/gems/triggers/*.tres = 1 演示触发器。
    # 触发器不参与表格化，绝不能计进技能数（按整子树计数会把 67 数成 68）。
    skill_ids = sorted(p.stem for p in (path / "active").glob("*.tres"))
    support_ids = sorted(p.stem for p in (path / "supports").glob("*.tres"))
    if not skill_ids:
        return None
    ids = set(skill_ids) | set(support_ids)
    ids |= {p.stem for p in (path / "triggers").glob("*.tres")}   # 只进避重集合
    return {"skills": skill_ids, "supports": support_ids, "ids": ids}


# ------------------------------------------------------------ 自检主流程 ----
def main():
    parser = argparse.ArgumentParser(description="W3 自检：不依赖 W2 产物，实测 A/B 全链")
    parser.add_argument("--godot", default=os.environ.get("GODOT_CONSOLE", DEFAULT_GODOT),
                        help="Godot 控制台可执行文件绝对路径")
    args = parser.parse_args()
    global GODOT
    GODOT = args.godot

    BASE.mkdir(parents=True, exist_ok=True)
    LOGS.mkdir(parents=True, exist_ok=True)
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    # 契约 v1.4 new_row_policy.reserved_rows（②40 / ③90 / ④30），增量四构造预留行时用
    reserved = dict(schema.get("new_row_policy", {}).get("reserved_rows",
                                                         {"skills": 40, "parts": 90, "supports": 30}))
    build_workbooks(schema)

    results = []

    def record(name, ok, detail):
        results.append((name, bool(ok), detail))
        print(("  [通过] " if ok else "  [失败] ") + name + "：" + detail)

    def a_cmd(xlsx, out, errs):
        # out / errs 为 None 时不传对应参数，走 A 的默认路径
        cmd = [sys.executable, str(A_SCRIPT), str(xlsx),
               "--schema", str(SCHEMA), "--snapshot", str(SNAPSHOT)]
        if out is not None:
            cmd += ["--out", str(out)]
        if errs is not None:
            cmd += ["--errors", str(errs)]
        return cmd

    def b_cmd(input_res=None, output_res=None):
        # 不带任何 -- 参数时即任务书给出的默认跑法，B 用默认输入/输出路径
        cmd = [GODOT, "--headless", "--path", PROJECT.as_posix(), "-s", B_SCRIPT]
        if input_res or output_res:
            cmd.append("--")
            if input_res:
                cmd += ["--input", input_res]
            if output_res:
                cmd += ["--output", output_res]
        return cmd

    def a_variant(tag, xlsx):
        """跑一个变体工作簿：返回 (进程结果, 输出 JSON 路径, 解析后 payload, 中文错误原文)。"""
        vdir = BASE / ("var_" + tag)
        out = vdir / "build_input.json"
        err = vdir / "errors.json"
        proc, _ = run(tag, a_cmd(xlsx, out, err))
        data = json.loads(out.read_text(encoding="utf-8")) if out.exists() else None
        report = json.loads(err.read_text(encoding="utf-8")) if err.exists() else {}
        return proc, out, data, report.get("text", "")

    # ---------------------------------------------------------- 自检 ① ----
    print("\n########## 自检 ①：A 正常路径能生成中间 JSON ##########")
    # 不删除任何文件：填错路径的输出 JSON 从未被生成过，正常路径每次覆盖写，结论依然可信
    p1, _ = run("A_正常路径", a_cmd(OK_XLSX, None, OK_ERRORS))
    payload = None
    try:
        payload = json.loads(OK_JSON.read_text(encoding="utf-8")) if OK_JSON.exists() else None
    except ValueError:
        payload = None
    ok1 = (p1.returncode == 0 and payload is not None
           and len(payload.get("skills", [])) == 1
           and len(payload.get("supports", [])) == 1
           and len(payload["skills"][0].get("parts", [])) == 1)
    # 顺带实测 __extras 透传 + 别名归一
    alias_ok = False
    if payload:
        bp = payload["skills"][0]["parts"][0].get("behavior_params", {})
        alias_ok = ("count_base" in bp and "projectile_count" not in bp
                    and bp.get("count_base") == 9 and bp.get("delay") == 0.35)
        ov = payload["supports"][0].get("behavior_overrides", {})
        alias_ok = alias_ok and "pierce" in ov and payload["supports"][0].get("flags") == ["cannot_crit"]
    record("自检① A 正常路径生成中间 JSON", ok1,
            f"退出码={p1.returncode}，技能={len(payload.get('skills', [])) if payload else '无'}，"
            f"辅助石={len(payload.get('supports', [])) if payload else '无'}，"
            f"效果段={len(payload['skills'][0].get('parts', [])) if payload else '无'}")
    record("自检①附带 __extras 透传 + 投射数量别名归一 count_base", ok1 and alias_ok,
            "projectile_count→count_base=9、delay=0.35、behavior_overrides/flags 均还原" if alias_ok
            else "别名归一或 __extras 透传未生效")
    if payload:
        print("  A 黄色提醒数：%d" % len(payload.get("warnings", [])))
        for w in payload.get("warnings", []):
            print("  [黄色提醒] " + w)

    # ---------------------------------------------------------- 自检 ② ----
    print("\n########## 自检 ②：A 填错路径中文报错定位行列且不生成 JSON ##########")
    # BAD_JSON 从未被生成过（填错路径永不写 JSON），故直接断言其不存在即可
    p2, _ = run("A_填错路径", a_cmd(BAD_XLSX, BAD_JSON, BAD_ERRORS))
    err_report = json.loads(BAD_ERRORS.read_text(encoding="utf-8"))
    text = err_report.get("text", "")
    located = ("③ 效果段 第 3 行 · 形状" in text and "方形" in text
               and "只能选 点/圆/环/扇形/线/矩形/多点" in text)
    ok2 = (p2.returncode != 0 and not BAD_JSON.exists()
           and err_report.get("ok") is False and err_report.get("count", 0) > 0
           and located)
    record("自检② A 填错路径不生成 JSON 且中文报错定位行/列", ok2,
            f"退出码={p2.returncode}，错误数={err_report.get('count')}，"
            f"build_input.json 存在={BAD_JSON.exists()}，定位示例命中={located}")
    print("  --- 中文错误清单（原始）---")
    indent_print(text)

    # 补验：不传 --errors 时，A 按默认路径写 _tmp/errors.json
    p2d, _ = run("A_填错路径_默认错误清单", a_cmd(BAD_XLSX, BAD_JSON, None))
    default_err = WORKBENCH / "_tmp" / "errors.json"
    dr = json.loads(default_err.read_text(encoding="utf-8"))
    ok2d = (p2d.returncode != 0 and not BAD_JSON.exists()
            and dr.get("ok") is False and "③ 效果段 第 3 行 · 形状" in dr.get("text", ""))
    record("自检②附带 默认 _tmp/errors.json 中文错误清单", ok2d,
            f"退出码={p2d.returncode}，错误清单路径={default_err}，"
            f"错误数={dr.get('count')}，ok={dr.get('ok')}")

    # ---------------------------------------------------------- 自检 ③ ----
    print("\n########## 自检 ③：B 生成 .tres 且回读字段一致 ##########")
    p3, body3 = run("B_首次生成", b_cmd())
    tres_files = sorted(DRYRUN.glob("*.tres")) if DRYRUN.exists() else []
    verified = "逐条 load() 回读自查全部通过" in body3
    ok3 = p3.returncode == 0 and len(tres_files) >= 1 and verified
    snap1 = {f.name: f.read_bytes() for f in tres_files}
    record("自检③ B 生成 .tres 且逐条回读字段一致", ok3,
            f"退出码={p3.returncode}，产物数={len(tres_files)}（{[f.name for f in tres_files]}），"
            f"回读自查通过={verified}")
    for f in tres_files:
        print(f"  --- {f.name} 内容（原始）---")
        indent_print(f.read_text(encoding="utf-8"))

    # ---------------------------------------------------------- 自检 ④ ----
    print("\n########## 自检 ④：同一输入跑两次产物逐字节一致 ##########")
    p4, _ = run("B_第二次生成", b_cmd())
    tres_files2 = sorted(DRYRUN.glob("*.tres")) if DRYRUN.exists() else []
    snap2 = {f.name: f.read_bytes() for f in tres_files2}
    same_names = set(snap1) == set(snap2)
    same_bytes = same_names and all(snap1[k] == snap2[k] for k in snap1)
    ok4 = p4.returncode == 0 and same_names and same_bytes and len(snap1) > 0
    record("自检④ 两次生成 .tres 逐字节一致", ok4,
            f"第二次退出码={p4.returncode}，文件集合一致={same_names}，"
            f"逐文件字节一致={same_bytes}，比对文件数={len(snap1)}")

    # ------------------------------------------------ 加分：事务回滚 ----
    print("\n########## 加分：失败自动回滚（保留旧目录、删半成品）##########")
    rb_dir = BASE / "rollback"
    rb_dir.mkdir(parents=True, exist_ok=True)
    bad_input = rb_dir / "bad_input.json"
    if payload:
        broken = {
            "version": "1.0", "source": "rollback_probe",
            "skills": [payload["skills"][0], {"gem_id": "非法 名字", "display_name": "坏数据", "parts": []}],
            "supports": [],
        }
        bad_input.write_text(json.dumps(broken, ensure_ascii=False), encoding="utf-8")
    p5, _ = run("B_失败回滚", b_cmd(RES_BASE + "/rollback/bad_input.json"))
    tres_after = sorted(DRYRUN.glob("*.tres")) if DRYRUN.exists() else []
    snap_after = {f.name: f.read_bytes() for f in tres_after}
    staging = DEFAULT_STAGING
    staging_clean = not any(staging.glob("*.tres")) if staging.exists() else True
    rollback_ok = (p5.returncode != 0 and snap_after == snap2 and staging_clean)
    record("加分 失败自动回滚", rollback_ok,
            f"退出码={p5.returncode}（非零），旧 dryrun 字节不变={snap_after == snap2}，"
            f"暂存半成品已清理={staging_clean}")

    # -------------------------------------------- 加分：分层校验变体 ----
    print("\n########## 加分：分层校验覆盖（代号/形状参数等）##########")
    variants = []

    v1 = BASE / "var_badid.xlsx"
    mutate(OK_XLSX, v1, {"② 技能卡": [(2, "代号（自动，别填）", "非法 名字")]})
    variants.append(("代号与文件名不一致", v1, "不能作为资源文件名"))

    v2 = BASE / "var_dupid.xlsx"
    duplicate_skill(OK_XLSX, v2)
    variants.append(("代号重复", v2, "重复"))

    for label, xlsx, keyword in variants:
        vdir = BASE / ("var_" + xlsx.stem)
        vout = vdir / "build_input.json"
        verr = vdir / "errors.json"
        pv, _ = run("变体_" + label, a_cmd(xlsx, vout, verr))
        vt = json.loads(verr.read_text(encoding="utf-8")).get("text", "")
        hit = keyword in vt
        record("分层校验 · " + label,
               pv.returncode != 0 and hit and not vout.exists(),
               f"退出码={pv.returncode}，命中『{keyword}』={hit}，未生成 JSON={not vout.exists()}")

    # 契约 v1.3 / P4：aoe 尺寸硬拦与 GUT test_a6（test_content_contract.gd 第 158–165 行）同口径。
    # ① 点爆豁免：范围爆发 + 形状=点 + 无任何尺寸 → 通过并生成中间 JSON。
    v3 = BASE / "var_aoe_pt.xlsx"
    mutate(OK_XLSX, v3, {"③ 效果段": [(2, "形状", "点"), (2, "半径", None)]})
    pv3, v3out, v3_data, v3_text = a_variant("var_aoe_pt", v3)
    v3_bp = v3_data["skills"][0]["parts"][0]["behavior_params"] if v3_data else {}
    record("分层校验 · aoe 点爆豁免（形状=点、无尺寸仍通过）",
           pv3.returncode == 0 and v3_data is not None and v3_bp.get("shape") == "pt"
           and "radius" not in v3_bp and not v3_text,
           f"退出码={pv3.returncode}，生成 JSON={v3out.exists()}，"
           f"shape={v3_bp.get('shape')}，半径缺失={'radius' not in v3_bp}，错误数={len(v3_text.splitlines())}")

    # ② 环缺尺寸硬拦：范围爆发 + 形状=环 + 清空全部尺寸 → 中文报错定位「半径」、不生成 JSON。
    v3b = BASE / "var_aoe_ring.xlsx"
    mutate(OK_XLSX, v3b, {"③ 效果段": [(2, "形状", "环"), (2, "半径", None)]})
    pv3b, v3bout, v3b_data, v3b_text = a_variant("var_aoe_ring", v3b)
    ring_located = ("③ 效果段 第 2 行 · 半径" in v3b_text and "点爆豁免" in v3b_text)
    record("分层校验 · aoe 环缺尺寸硬拦（与 GUT test_a6 同口径）",
           pv3b.returncode != 0 and v3b_data is None and not v3bout.exists() and ring_located,
           f"退出码={pv3b.returncode}，未生成 JSON={not v3bout.exists()}，"
           f"定位『③ 效果段 第 2 行 · 半径』={ring_located}")
    print("  --- aoe 缺尺寸中文报错（原始）---")
    indent_print(v3b_text)

    # ③ 非 aoe_burst 的「该形状尺寸全空」仍只给黄色提醒、不拦截（契约 v1.2 口径保留）。
    v3c = BASE / "var_shape_warn.xlsx"
    mutate(OK_XLSX, v3c, {"③ 效果段": [
        (2, "效果", "引导"),
        (2, "形状", "圆"),
        (2, "半径", None),
        (2, "最大引导时间", 2.0),
    ]})
    pv3c, v3cout, v3c_data, _ = a_variant("var_shape_warn", v3c)
    v3c_warn = " ".join(v3c_data.get("warnings", [])) if v3c_data else ""
    record("分层校验 · 非 aoe 形状缺尺寸仅黄色提醒（不拦截）",
           pv3c.returncode == 0 and v3c_data is not None
           and "形状与参数列不匹配" not in v3c_warn and "未填任何尺寸参数" in v3c_warn,
           f"退出码={pv3c.returncode}，生成 JSON={v3cout.exists()}，"
           f"黄色提醒命中={'未填任何尺寸参数' in v3c_warn}")

    # 数值区间提醒：超出统计区间只给黄色提醒，不拦截，仍生成中间 JSON
    v4 = BASE / "var_outlier.xlsx"
    mutate(OK_XLSX, v4, {"③ 效果段": [(2, "半径", 99999)]})
    v4dir = BASE / "var_outlier"
    v4out = v4dir / "build_input.json"
    v4err = v4dir / "errors.json"
    pv4, _ = run("变体_数值区间提醒", a_cmd(v4, v4out, v4err))
    warn_text = ""
    if v4out.exists():
        warn_text = " ".join(json.loads(v4out.read_text(encoding="utf-8")).get("warnings", []))
    record("分层校验 · 数值超区间仅黄色提醒不拦截",
           pv4.returncode == 0 and v4out.exists() and "超出" in warn_text,
           f"退出码={pv4.returncode}，仍生成 JSON={v4out.exists()}，提醒含『超出』={'超出' in warn_text}")
    if warn_text:
        print("  [黄色提醒] " + warn_text)

    # 补验：A 的最简默认命令（只传工作簿路径，其余全默认），即 W4 只读调用时的形态
    pd, _ = run("A_纯默认命令", [sys.executable, str(A_SCRIPT), str(OK_XLSX)])
    dr2 = json.loads(default_err.read_text(encoding="utf-8"))
    ok_default = (pd.returncode == 0 and OK_JSON.exists()
                 and dr2.get("ok") is True and dr2.get("count") == 0)
    record("补验 A 最简默认命令（只传工作簿）", ok_default,
            f"退出码={pd.returncode}，默认中间 JSON 存在={OK_JSON.exists()}，"
            f"默认错误清单 ok={dr2.get('ok')}、错误数={dr2.get('count')}")

    # ---------------------- 增量：契约 v1.1 enums.stat_labels ----------------------
    print("\n########## 增量自检：契约 v1.1 中文属性词表（唯一真源）##########")

    # 增量①：全量 23 项中文 label 逐行造数据，确认每一项都还原成对应英文标识符
    vocab_xlsx = BASE / "stat_vocab.xlsx"
    pairs = build_stat_vocab_workbook(schema, OK_XLSX, vocab_xlsx)
    vdir_v = BASE / "var_stat_vocab"
    vout_v = vdir_v / "build_input.json"
    verr_v = vdir_v / "errors.json"
    pv_v, _ = run("契约词表_属性全量还原", a_cmd(vocab_xlsx, vout_v, verr_v))
    vocab_data = json.loads(vout_v.read_text(encoding="utf-8")) if vout_v.exists() else None
    mismatch = []
    if vocab_data:
        for i, (label, value) in enumerate(pairs):
            got = vocab_data["supports"][i]["stat_modifiers"][0]["stat"]
            if got != value:
                mismatch.append(f"{label}→{got}（期望 {value}）")
    ok_vocab = (pv_v.returncode == 0 and vocab_data is not None
                and len(vocab_data.get("supports", [])) == len(pairs)
                and not mismatch)
    record("增量① 契约 v1.1 中文属性词表全量还原英文标识符", ok_vocab,
            f"退出码={pv_v.returncode}，词表项数={len(pairs)}，"
            f"辅助石行数={len(vocab_data.get('supports', [])) if vocab_data else '无'}，"
            f"不一致项={mismatch or '无'}")
    print(f"  词表抽样：{pairs[0][0]}→{pairs[0][1]}、{pairs[5][0]}→{pairs[5][1]}、{pairs[-1][0]}→{pairs[-1][1]}")

    # 增量②：英文原值兼容（旧工作簿 / 手工填入的英文标识符仍能解析）
    v_en = BASE / "var_stat_en.xlsx"
    mutate(OK_XLSX, v_en, {"④ 辅助石": [(2, "属性", "crit_chance")]})
    vdir_en = BASE / "var_stat_en"
    vout_en = vdir_en / "build_input.json"
    verr_en = vdir_en / "errors.json"
    pen, _ = run("契约词表_英文原值兼容", a_cmd(v_en, vout_en, verr_en))
    en_data = json.loads(vout_en.read_text(encoding="utf-8")) if vout_en.exists() else None
    en_stat = en_data["supports"][0]["stat_modifiers"][0]["stat"] if en_data else None
    record("增量② 英文标识符原值仍可解析（兼容旧工作簿）",
           pen.returncode == 0 and en_stat == "crit_chance",
           f"退出码={pen.returncode}，填『crit_chance』→ 还原 stat={en_stat}")

    # 增量③：停用内置映射 —— 上一波自造的「暴击几率」不再是合法值，候选来自契约词表
    v_old = BASE / "var_stat_old.xlsx"
    mutate(OK_XLSX, v_old, {"④ 辅助石": [(2, "属性", "暴击几率")]})
    vdir_old = BASE / "var_stat_old"
    vout_old = vdir_old / "build_input.json"
    verr_old = vdir_old / "errors.json"
    pold, _ = run("契约词表_停用内置映射", a_cmd(v_old, vout_old, verr_old))
    old_text = json.loads(verr_old.read_text(encoding="utf-8")).get("text", "")
    old_ok = (pold.returncode != 0 and not vout_old.exists()
              and "暴击几率" in old_text and "暴击率" in old_text and "只能选" in old_text)
    record("增量③ 停用内置映射、口径统一到契约",
           old_ok,
           f"退出码={pold.returncode}，未生成 JSON={not vout_old.exists()}，"
           f"报错候选含契约词『暴击率』={'暴击率' in old_text}")
    print("  --- 停用内置映射后的报错（原始）---")
    indent_print(old_text)

    # ---------------------- 增量二：契约 v1.2 联调打回三项 ----------------------
    print("\n########## 增量二自检①：示例行被跳过（【示例】+ 遗留文本）##########")
    ex_xlsx = BASE / "example_rows.xlsx"
    s_skill = sheet_by_key(schema, "skills")
    s_part = sheet_by_key(schema, "parts")
    s_support = sheet_by_key(schema, "supports")
    # 追加 6 行示例行：既有【示例】新标记，也有 v1.1 遗留文本，且故意填非法代号 /
    # 非法形状 / 缺必填 —— 若没被跳过，A 必定报错、退出码非 0。
    append_rows(OK_XLSX, ex_xlsx, {
        s_skill: [
            {"技能名": "【示例】照着填（新标记）", "代号（自动，别填）": "（工具自动生成，不用填）"},
            {"技能名": "这是例子，照着填", "代号（自动，别填）": "（工具自动生成，不用填）"},
        ],
        s_part: [
            {"属于哪个技能": "【示例】例子效果", "第几段": None, "形状": "方形"},
            {"属于哪个技能": "这是例子，照着填", "第几段": None, "形状": "方形"},
        ],
        s_support: [
            {"辅助石名": "【示例】例子辅助", "代号（自动，别填）": "（工具自动生成，不用填）"},
            {"辅助石名": "这是例子，照着填", "代号（自动，别填）": "（工具自动生成，不用填）"},
        ],
    })
    ex_dir = BASE / "var_example_rows"
    ex_out = ex_dir / "build_input.json"
    ex_err = ex_dir / "errors.json"
    pex, _ = run("增量二_示例行跳过", a_cmd(ex_xlsx, ex_out, ex_err))
    ex_data = json.loads(ex_out.read_text(encoding="utf-8")) if ex_out.exists() else None
    ex_text = ex_out.read_text(encoding="utf-8") if ex_out.exists() else ""
    no_leak = ("这是例子" not in ex_text and "【示例】" not in ex_text
              and "（工具自动生成，不用填）" not in ex_text)
    ok_ex = (pex.returncode == 0 and ex_data is not None
             and len(ex_data.get("skills", [])) == 1
             and len(ex_data.get("supports", [])) == 1
             and len(ex_data["skills"][0].get("parts", [])) == 1
             and no_leak)
    record("增量二① 示例行被跳过（【示例】新标记 + v1.1 遗留文本均兼容）", ok_ex,
           f"退出码={pex.returncode}，追加 6 行示例后仍为 技能=1/效果段=1/辅助石=1，"
           f"示例文本零泄漏={no_leak}")

    print("\n########## 增量二自检②：引导类『只有扇形距离』能通过 ##########")
    # 引导（bhv_channel）用「扇形距离」range 承载圆/线尺寸、不填半径/长度/宽度
    # 是合法既有口径（shape_hit.gd 第 17 行、D-46）。behavior_required 只要求
    # 「最大引导时间」，补齐即可；断言 A 退出码 0 且 range 被还原、无误报尺寸黄色提醒。
    ch_xlsx = BASE / "channel_range_only.xlsx"
    mutate(OK_XLSX, ch_xlsx, {"③ 效果段": [
        (2, "效果", "引导"),
        (2, "形状", "圆"),
        (2, "半径", None),
        (2, "扇形距离", 120),
        (2, "最大引导时间", 2.0),
    ]})
    ch_dir = BASE / "var_channel_range"
    ch_out = ch_dir / "build_input.json"
    ch_err = ch_dir / "errors.json"
    pch, _ = run("增量二_引导类只有扇形距离", a_cmd(ch_xlsx, ch_out, ch_err))
    ch_data = json.loads(ch_out.read_text(encoding="utf-8")) if ch_out.exists() else None
    ch_bp = ch_data["skills"][0]["parts"][0]["behavior_params"] if ch_data else {}
    ch_warn = " ".join(ch_data.get("warnings", [])) if ch_data else ""
    no_dim_warn = "未填任何尺寸参数" not in ch_warn
    ok_ch = (pch.returncode == 0 and ch_data is not None
             and ch_bp.get("range") == 120 and ch_bp.get("max_channel_time") == 2.0
             and "radius" not in ch_bp and no_dim_warn)
    record("增量二② 引导类『只有扇形距离』能通过（形状参数不拦截）", ok_ch,
           f"退出码={pch.returncode}，range={ch_bp.get('range')}、"
           f"max_channel_time={ch_bp.get('max_channel_time')}、半径缺失={'radius' not in ch_bp}，"
           f"无误报『未填尺寸』黄色提醒={no_dim_warn}")

    print("\n########## 增量二自检③：校验失败后旧 build_input.json 不再存在 ##########")
    # ① 隔离路径：先成功生成一份「旧」中间 JSON，再用含错工作簿跑到同一路径，断言被清理。
    stale_dir = BASE / "var_stale"
    stale_json = stale_dir / "build_input.json"
    stale_err = stale_dir / "errors.json"
    ppre, _ = run("增量二_预置旧中间JSON", a_cmd(OK_XLSX, stale_json, stale_err))
    had_old = stale_json.exists()
    pfail, _ = run("增量二_失败清理旧JSON", a_cmd(BAD_XLSX, stale_json, stale_err))
    isolated_clean = (ppre.returncode == 0 and had_old
                       and pfail.returncode != 0 and not stale_json.exists())

    # ② 默认路径（直接复现 W5 根因 3）：先纯默认成功（旧数据），再纯默认失败，
    #    断言默认 _tmp/build_input.json 不存在；随后重建，避免自检收尾留下无输入状态。
    pdef_ok, _ = run("增量二_默认路径预置", [sys.executable, str(A_SCRIPT), str(OK_XLSX)])
    had_default = OK_JSON.exists()
    pdef_bad, _ = run("增量二_默认路径失败", [sys.executable, str(A_SCRIPT), str(BAD_XLSX)])
    default_gone = not OK_JSON.exists()
    default_clean = (pdef_ok.returncode == 0 and had_default
                     and pdef_bad.returncode != 0 and default_gone)
    run("增量二_默认路径重建", [sys.executable, str(A_SCRIPT), str(OK_XLSX)])

    record("增量二③ 校验失败后旧 build_input.json 不再存在", isolated_clean and default_clean,
           f"隔离路径：预置成功={had_old}、失败退出码={pfail.returncode}、旧文件已清理={not stale_json.exists()}；"
           f"默认路径：预置成功={had_default}、失败退出码={pdef_bad.returncode}、旧文件已清理={default_gone}"
           f"（收尾已重建默认中间 JSON）")

    # ================= 增量三：契约 v1.3 读侧（二期 P2 读侧 / P4） =================
    print("\n########## 增量三自检①：阵型 / 运动方式 中文回读 ##########")
    v_cn = BASE / "cn_basic.xlsx"
    mutate(OK_XLSX, v_cn, {"③ 效果段": [(2, "阵型", "直线排"), (2, "运动方式", "环绕飞行")]})
    pcn, cn_out, cn_data, cn_text = a_variant("cn_basic", v_cn)
    cn_bp = cn_data["skills"][0]["parts"][0]["behavior_params"] if cn_data else {}
    ok_cn = (pcn.returncode == 0 and cn_data is not None
             and cn_bp.get("formation") == "line" and cn_bp.get("motion") == "orbit")
    record("增量三① 阵型/运动方式 中文→英文回读（直线排→line、环绕飞行→orbit）", ok_cn,
           f"退出码={pcn.returncode}，formation={cn_bp.get('formation')}，"
           f"motion={cn_bp.get('motion')}")

    # 旧英文原值仍兼容
    v_cn_en = BASE / "cn_en.xlsx"
    mutate(OK_XLSX, v_cn_en, {"③ 效果段": [(2, "阵型", "line"), (2, "运动方式", "orbit")]})
    pcen, cen_out, cen_data, cen_text = a_variant("cn_en", v_cn_en)
    cen_bp = cen_data["skills"][0]["parts"][0]["behavior_params"] if cen_data else {}
    record("增量三①附带 旧英文原值仍兼容（line / orbit 直接填）",
           pcen.returncode == 0 and cen_data is not None
           and cen_bp.get("formation") == "line" and cen_bp.get("motion") == "orbit",
           f"退出码={pcen.returncode}，formation={cen_bp.get('formation')}，"
           f"motion={cen_bp.get('motion')}")

    # 非法中文 → 中文报错定位 + 候选中文词表 + 不生成中间 JSON
    v_cn_bad = BASE / "cn_bad.xlsx"
    mutate(OK_XLSX, v_cn_bad, {"③ 效果段": [(2, "阵型", "斜着排")]})
    pcb, cb_out, cb_data, cb_text = a_variant("cn_bad", v_cn_bad)
    cb_ok = (pcb.returncode != 0 and not cb_out.exists() and cb_data is None
             and "③ 效果段 第 2 行 · 阵型" in cb_text
             and "斜着排" in cb_text and "直线排" in cb_text and "只能选" in cb_text)
    record("增量三①附带 非法中文阵型 → 中文报错定位且不生成 JSON", cb_ok,
           f"退出码={pcb.returncode}，未生成 JSON={not cb_out.exists()}，"
           f"定位『③ 效果段 第 2 行 · 阵型』={'③ 效果段 第 2 行 · 阵型' in cb_text}，"
           f"候选含『直线排』={'直线排' in cb_text}")
    print("  --- 非法阵型中文报错（原始）---")
    indent_print(cb_text)

    print("\n########## 增量三自检②：冲突辅助中文名 → support_id ##########")
    # 先追加第 2 个辅助石，再在第一个辅助石的「冲突辅助」里写第 2 个的中文名 + 一个旧英文代号。
    conf_base = BASE / "cn_conflicts_base.xlsx"
    append_rows(OK_XLSX, conf_base, {"④ 辅助石": [{
        "辅助石名": "自检·锐化二",
        "代号（自动，别填）": "w3_selfcheck_second",
        "属性": "暴击率",
        "运算": "固定加值",
        "数值": 5,
        "高级数据（工具自动，勿改）": "{}",
    }]})
    v_conf = BASE / "cn_conflicts.xlsx"
    mutate(conf_base, v_conf, {"④ 辅助石": [
        (2, "冲突辅助（+ 分隔）", "自检·锐化二+w3_selfcheck_other")]})
    pcf, cf_out, cf_data, cf_text = a_variant("cn_conflicts", v_conf)
    cf_list = cf_data["supports"][0].get("conflicts_with") if cf_data else None
    ok_cf = (pcf.returncode == 0 and cf_data is not None
             and len(cf_data.get("supports", [])) == 2
             and cf_list == ["w3_selfcheck_second", "w3_selfcheck_other"])
    record("增量三② 冲突辅助中文名→英文 support_id（且旧英文原值混排仍兼容）", ok_cf,
           f"退出码={pcf.returncode}，辅助石数={len(cf_data.get('supports', [])) if cf_data else '无'}，"
           f"conflicts_with={cf_list}")

    # 中文名映射不到 → 中文报错定位该行「冲突辅助（+ 分隔）」列、不生成 JSON
    v_conf_bad = BASE / "cn_conflicts_bad.xlsx"
    mutate(OK_XLSX, v_conf_bad, {"④ 辅助石": [(2, "冲突辅助（+ 分隔）", "查无此石")]})
    pcfb, cfb_out, cfb_data, cfb_text = a_variant("cn_conflicts_bad", v_conf_bad)
    cfb_ok = (pcfb.returncode != 0 and not cfb_out.exists() and cfb_data is None
              and "④ 辅助石 第 2 行 · 冲突辅助（+ 分隔）" in cfb_text
              and "查无此石" in cfb_text and "找不到" in cfb_text)
    record("增量三②附带 冲突辅助中文名映射不到 → 中文报错定位且不生成 JSON", cfb_ok,
           f"退出码={pcfb.returncode}，未生成 JSON={not cfb_out.exists()}，"
           f"定位『④ 辅助石 第 2 行 · 冲突辅助（+ 分隔）』="
           f"{'④ 辅助石 第 2 行 · 冲突辅助（+ 分隔）' in cfb_text}")
    print("  --- 冲突辅助映射不到中文报错（原始）---")
    indent_print(cfb_text)

    print("\n########## 增量三自检③：增益三列 → buff_mods ##########")
    # 3 条表内条目覆盖 2 条 __extras：第 1 条要继承 channel_mask/require_tags，第 3 条原样追加。
    buff_extras = json.dumps({"behavior_params": {"buff_mods": [
        {"stat": "fire_damage", "op": 0, "value": 99.0, "channel_mask": 3, "require_tags": ["fire"]},
        {"stat": "cold_damage", "op": 1, "value": 88.0},
        {"stat": "armor", "op": 0, "value": 260.0, "channel_mask": 7},
    ]}}, ensure_ascii=False)
    buff_cells = {
        "③ 效果段": [
            (2, "效果", "自我增益"),
            (2, "形状", None),
            (2, "半径", None),
            (2, "增益时长", 5),
            (2, "增益属性（用 + 分隔）", "物理伤害+暴击率"),
            (2, "增益运算（用 + 分隔，与上一列顺序对应）", "百分比增加+固定加值"),
            (2, "增益数值（用 + 分隔，与上一列顺序对应）", "30+25"),
        ]
    }
    v_buff = BASE / "buff_three.xlsx"
    mutate(OK_XLSX, v_buff, {"③ 效果段": buff_cells["③ 效果段"]
                             + [(2, "高级数据（工具自动，勿改）", buff_extras)]})
    pb, b_out, b_data, b_text = a_variant("buff_three", v_buff)
    b_bp = b_data["skills"][0]["parts"][0]["behavior_params"] if b_data else {}
    got_buff = b_bp.get("buff_mods")
    expect_buff = [
        {"stat": "physical_damage", "op": 1, "value": 30.0, "channel_mask": 3, "require_tags": ["fire"]},
        {"stat": "crit_chance", "op": 0, "value": 25.0},
        {"stat": "armor", "op": 0, "value": 260.0, "channel_mask": 7},
    ]
    record("增量三③ 增益三列→buff_mods（沿用 __extras 同序号键、多余条目原样保留、不补默认键）",
           pb.returncode == 0 and b_data is not None and got_buff == expect_buff,
           f"退出码={pb.returncode}，buff_mods={got_buff}")
    print("  期望 buff_mods：" + json.dumps(expect_buff, ensure_ascii=False))

    # 旧工作簿兼容：表里没有增益三列时，buff_mods 完全由 __extras 原文保留（不造键、不报错）。
    legacy_xlsx = BASE / "buff_legacy.xlsx"
    drop_columns(OK_XLSX, legacy_xlsx, "③ 效果段",
                 [c["label"] for c in schema["buff_spec"]["columns"]])
    mutate(legacy_xlsx, legacy_xlsx, {"③ 效果段": [
        (2, "效果", "自我增益"),
        (2, "形状", None),
        (2, "半径", None),
        (2, "增益时长", 5),
        (2, "高级数据（工具自动，勿改）", buff_extras),
    ]})
    plg, lg_out, lg_data, lg_text = a_variant("buff_legacy", legacy_xlsx)
    lg_bp = lg_data["skills"][0]["parts"][0]["behavior_params"] if lg_data else {}
    expect_legacy = [
        {"stat": "fire_damage", "op": 0, "value": 99.0, "channel_mask": 3, "require_tags": ["fire"]},
        {"stat": "cold_damage", "op": 1, "value": 88.0},
        {"stat": "armor", "op": 0, "value": 260.0, "channel_mask": 7},
    ]
    record("增量三③附带 旧工作簿（无增益三列）buff_mods 由 __extras 原样保留",
           plg.returncode == 0 and lg_data is not None and lg_bp.get("buff_mods") == expect_legacy,
           f"退出码={plg.returncode}，buff_mods={lg_bp.get('buff_mods')}")

    # __extras 没有对应条目 → 新条目只写 stat/op/value（不得补 channel_mask 等默认键）
    v_buff_new = BASE / "buff_new.xlsx"
    mutate(OK_XLSX, v_buff_new, {"③ 效果段": [
        (2, "效果", "自我增益"),
        (2, "形状", None),
        (2, "半径", None),
        (2, "增益时长", 5),
        (2, "增益属性（用 + 分隔）", "物理伤害"),
        (2, "增益运算（用 + 分隔，与上一列顺序对应）", "固定加值"),
        (2, "增益数值（用 + 分隔，与上一列顺序对应）", "10"),
        (2, "高级数据（工具自动，勿改）", "{}"),
    ]})
    pbn, bn_out, bn_data, bn_text = a_variant("buff_new", v_buff_new)
    bn_bp = bn_data["skills"][0]["parts"][0]["behavior_params"] if bn_data else {}
    new_buff = bn_bp.get("buff_mods")
    expect_new = [{"stat": "physical_damage", "op": 0, "value": 10.0}]
    record("增量三③附带 无 __extras 条目时只写 stat/op/value（不补默认键，防语义漂移）",
           pbn.returncode == 0 and bn_data is not None and new_buff == expect_new,
           f"退出码={pbn.returncode}，buff_mods={new_buff}")

    # 三列个数不一致 → 中文报错逐列定位（本例错在「增益运算」）、不生成中间 JSON
    v_buff_bad = BASE / "buff_mismatch.xlsx"
    mutate(OK_XLSX, v_buff_bad, {"③ 效果段": [
        (2, "效果", "自我增益"),
        (2, "形状", None),
        (2, "半径", None),
        (2, "增益时长", 5),
        (2, "增益属性（用 + 分隔）", "物理伤害+暴击率"),
        (2, "增益运算（用 + 分隔，与上一列顺序对应）", "固定加值"),
        (2, "增益数值（用 + 分隔，与上一列顺序对应）", "30+25"),
    ]})
    pbb, bb_out, bb_data, bb_text = a_variant("buff_mismatch", v_buff_bad)
    bb_ok = (pbb.returncode != 0 and not bb_out.exists() and bb_data is None
             and "③ 效果段 第 2 行 · 增益运算" in bb_text and "一一对应" in bb_text)
    record("增量三③附带 增益三列个数不一致 → 中文报错定位「增益运算」且不生成 JSON", bb_ok,
           f"退出码={pbb.returncode}，未生成 JSON={not bb_out.exists()}，"
           f"定位『③ 效果段 第 2 行 · 增益运算』="
           f"{'③ 效果段 第 2 行 · 增益运算' in bb_text}")
    print("  --- 增益三列个数不一致中文报错（原始）---")
    indent_print(bb_text)

    # 非法增益属性 → 中文报错列候选词表、不生成中间 JSON
    v_buff_stat = BASE / "buff_badstat.xlsx"
    mutate(OK_XLSX, v_buff_stat, {"③ 效果段": [
        (2, "效果", "自我增益"),
        (2, "形状", None),
        (2, "半径", None),
        (2, "增益时长", 5),
        (2, "增益属性（用 + 分隔）", "不存在属性"),
        (2, "增益运算（用 + 分隔，与上一列顺序对应）", "固定加值"),
        (2, "增益数值（用 + 分隔，与上一列顺序对应）", "10"),
    ]})
    pbs, bs_out, bs_data, bs_text = a_variant("buff_badstat", v_buff_stat)
    bs_ok = (pbs.returncode != 0 and not bs_out.exists() and bs_data is None
             and "③ 效果段 第 2 行 · 增益属性（用 + 分隔）" in bs_text
             and "不存在属性" in bs_text and "物理伤害" in bs_text and "只能选" in bs_text)
    record("增量三③附带 非法增益属性 → 中文报错候选契约词表且不生成 JSON", bs_ok,
           f"退出码={pbs.returncode}，未生成 JSON={not bs_out.exists()}，"
           f"定位『③ 效果段 第 2 行 · 增益属性（用 + 分隔）』="
           f"{'③ 效果段 第 2 行 · 增益属性（用 + 分隔）' in bs_text}")

    # ================= 增量四：契约 v1.4 读侧（三期 P7-B 新行 → 新技能） =================
    # 本段工作簿统一从「真实工作簿副本」构造：先把 ②③④ 的数据区按真实列结构重建
    # （示例行 4/5/4 + 67 技能 + 95 效果段 + 13 辅助石 + 40/90/30 预留行，代号/技能名
    # 全部取自 content/gems 的 .tres 文件名），让数量守卫的基线（67 技能 / 13 辅助石）
    # 与真实链路一致；再用真实工作簿里一模一样的中文占位说明填满预留行代号列，
    # 这样「全预留行不填 → 正常通过」测的就是 W2 真实产物的形态。
    print("\n########## 增量四：契约 v1.4 新行 → 新技能（P7-B 读侧）##########")

    real_wb_path = MODULE / "content_src" / "技能配置表.xlsx"
    real_wb = load_workbook(real_wb_path, data_only=True) if real_wb_path.exists() else None
    ledger = load_ledger()
    if real_wb is None or not ledger:
        record("增量四 前置（真实工作簿 + 内容台账可用）", False,
               f"真实工作簿={real_wb_path.exists()}，台账技能={len(ledger.get('skills', []))}、"
               f"辅助石={len(ledger.get('supports', []))}")
    else:
        base_skills, base_parts, base_supports = real_wb["② 技能卡"], real_wb["③ 效果段"], real_wb["④ 辅助石"]
        s_skill_hdr = [c.value for c in base_skills[1]]
        s_part_hdr = [c.value for c in base_parts[1]]
        s_sup_hdr = [c.value for c in base_supports[1]]

        def real_rows(ws, headers):
            """真实数据行 → [{中文列名: 值}]（跳过真正的整行空行，示例行与数据行都保留）。"""
            out = []
            for cells in ws.iter_rows(min_row=2, values_only=True):
                if all(c is None or (isinstance(c, str) and not c.strip()) for c in cells):
                    continue
                out.append({h: cells[i] for i, h in enumerate(headers) if i < len(cells)})
            return out

        skill_data = real_rows(base_skills, s_skill_hdr)
        part_data = real_rows(base_parts, s_part_hdr)
        support_data = real_rows(base_supports, s_sup_hdr)
        # 真实工作簿里的占位说明原文（不写死：取 ② 预留区域里 ② 只剩代号列内容的那一行）
        REAL_HINT = next(
            (row["代号（自动，别填）"] for row in skill_data
             if len([v for k, v in row.items() if k != "代号（自动，别填）" and v not in (None, "")]) == 0),
            "新技能由工具生成代号，填了技能名即可")
        real_parts = sum(1 for r in part_data if str(r.get("属于哪个技能") or "").startswith("【示例】") is False
                         and r.get("属于哪个技能"))
        real_skills = [r for r in skill_data if r.get("技能名")
                       and not str(r.get("技能名")).startswith("【示例】")]
        real_supports = [r for r in support_data if r.get("辅助石名")
                         and not str(r.get("辅助石名")).startswith("【示例】")]

        def write_rows(ws, headers, rows):
            ws.delete_rows(2, ws.max_row)
            for row in rows:
                ws.append([row.get(label) for label in headers])

        def make_real_base(dst):
            """真实工作簿全部数据 + 预留行（代号列只有中文占位说明、其余列空）。"""
            book = load_workbook(real_wb_path)
            write_rows(book["② 技能卡"], s_skill_hdr, skill_data + [
                {"代号（自动，别填）": REAL_HINT} for _ in range(reserved["skills"])])
            write_rows(book["③ 效果段"], s_part_hdr, part_data + [{} for _ in range(reserved["parts"])])
            write_rows(book["④ 辅助石"], s_sup_hdr, support_data + [
                {"代号（自动，别填）": REAL_HINT} for _ in range(reserved["supports"])])
            dst.parent.mkdir(parents=True, exist_ok=True)
            book.save(dst)

        new_part = {
            "属于哪个技能": "自检新技能",
            "第几段": 1,
            "效果": "投掷物",
            "形状": "圆",
            "伤害类型（用 + 分隔）": "冰冷",
            "基础伤害（用 + 分隔，与上一列顺序对应）": "120",
            "伤害效用": 1.0,
            "命中通道": "命中",
            "半径": 14,
            "速度": 620,
            "存活（秒）": 2.0,
            "投射数量": 1,
            "高级数据（工具自动，勿改）": "{}",
        }
        new_skill = {
            "技能名": "自检新技能",
            "代号（自动，别填）": REAL_HINT,      # 真实预留行形态：只有中文占位说明
            "施法方式": "主动施放",
            "消耗类型": "法力",
            "消耗数值": 10,
            "冷却（秒）": 3,
            "前摇（秒）": 0.5,
            "最多充能": 0,
            "充能回复（秒）": 0,
            "每级变强": 0.1,
            "成长拐点等级": 0,
            "拐点后每级变强": 0,
            "标签（用 + 分隔）": "法术+投射物+冰冷",
            "高级数据（工具自动，勿改）": "{}",
        }

        # 真实工作簿里三类行的起始行号（运行时从真实工作簿数出来，不写死）：
        # 第一个预留行 = 数据区之后的第一行；变体一律「原地填进第一个预留行」，
        # 与策划真实的填法一致（③ 只填技能名不算效果段，必须三列齐）
        first_skill_row = 2 + len(skill_data)
        first_part_row = 2 + len(part_data)
        first_sup_row = 2 + len(support_data)

        def real_variant(name, add_skills=(), add_parts=(), add_supports=()):
            """真实基线 + 把新增内容原地填进各页签的第一个预留行。"""
            path = BASE / (name + ".xlsx")
            book = load_workbook(BASE / "v14_base.xlsx")
            for ws, headers, rows, first in (
                (book["② 技能卡"], s_skill_hdr, list(add_skills), first_skill_row),
                (book["③ 效果段"], s_part_hdr, list(add_parts), first_part_row),
                (book["④ 辅助石"], s_sup_hdr, list(add_supports), first_sup_row),
            ):
                for k, row in enumerate(rows):
                    for ci, label in enumerate(headers, start=1):
                        ws.cell(row=first + k, column=ci).value = row.get(label)
            path.parent.mkdir(parents=True, exist_ok=True)
            book.save(path)
            return path

        make_real_base(BASE / "v14_base.xlsx")

        # ---- 变体①：全预留行不填 → 正常通过、67/95/13、无多余条目 ----
        v14_all_empty = BASE / "v14_reserved_empty.xlsx"
        make_real_base(v14_all_empty)
        pv14a, o14a, d14a, t14a = a_variant("v14_reserved_empty", v14_all_empty)
        n_sk = len(d14a.get("skills", [])) if d14a else None
        n_pt = sum(len(s.get("parts", [])) for s in d14a.get("skills", [])) if d14a else None
        n_su = len(d14a.get("supports", [])) if d14a else None
        leak = bool(d14a) and (REAL_HINT in o14a.read_text(encoding="utf-8"))
        ok14a = (pv14a.returncode == 0 and d14a is not None and not t14a
                 and n_sk == 67 and n_pt == 95 and n_su == 13 and not leak)
        record("增量四① 全预留行不填 → 正常通过、67/95/13、占位零泄漏", ok14a,
               f"退出码={pv14a.returncode}，技能={n_sk}、效果段={n_pt}、辅助石={n_su}，"
               f"错误数={len(t14a.splitlines())}，占位说明进 JSON={leak}")

        # ---- 变体②：新增 1 张技能卡 + 1 段效果段 → 命中数量守卫、未生成 JSON ----
        v14_one = real_variant("v14_new_skill", add_skills=[new_skill], add_parts=[new_part])
        pv14b, o14b, d14b, t14b = a_variant("v14_new_skill", v14_one)
        guard_hit = ("新增会打破数量硬断言，需按台账 P-23 同步改数量断言，须上级 AI 裁定" in t14b)
        gen_id = "skill_001" in t14b
        guard_base = f"但内容台账基线是 {len(ledger['skills'])} 条" in t14b
        ok14b = (pv14b.returncode != 0 and not o14b.exists() and d14b is None
                 and guard_hit and guard_base and gen_id)
        record("增量四② 新增 1 张技能卡 + 1 段效果段 → 命中数量守卫且未生成中间 JSON", ok14b,
               f"退出码={pv14b.returncode}，未生成 JSON={not o14b.exists()}，"
               f"命中『P-23 须上级 AI 裁定』={guard_hit}，"
               f"写明基线 {len(ledger['skills'])} 条={guard_base}，自动代号 skill_001 出现={gen_id}")
        print("  --- 新增技能卡中文报错（原始）---")
        indent_print(t14b)

        # ---- 变体③：新技能卡缺效果段 → 中文报错定位「② 技能卡 第 N 行 · 效果段」 ----
        v14_nopart = real_variant("v14_no_part", add_skills=[new_skill])
        pv14c, o14c, d14c, t14c = a_variant("v14_no_part", v14_nopart)
        # 新技能卡落在真实工作簿 ② 的第一个预留行（W2 实测为第 73 行），行号运行时算，
        # 不写死，避免 W2 改示例行数后变体假红。
        new_skill_row = first_skill_row
        locate_c = f"② 技能卡 第 {new_skill_row} 行 · 效果段"
        hit_c = locate_c in t14c
        ok14c = (pv14c.returncode != 0 and not o14c.exists() and d14c is None
                 and hit_c and "没有任何有效效果段" in t14c)
        record(f"增量四③ 新技能卡缺效果段 → 中文报错定位『{locate_c}』", ok14c,
               f"退出码={pv14c.returncode}，未生成 JSON={not o14c.exists()}，"
               f"定位命中={hit_c}")
        print("  --- 新技能卡缺效果段中文报错（原始）---")
        indent_print(t14c)

        # ---- 变体④：新技能代号与既有重复 → 中文报错；非法代号 → 中文报错 ----
        v14_dup = real_variant(
            "v14_dup_id",
            add_skills=[dict(new_skill, **{"代号（自动，别填）": ledger["skills"][0]})],
            add_parts=[new_part])
        pv14d, o14d, d14d, t14d = a_variant("v14_dup_id", v14_dup)
        dup_loc = f"② 技能卡 第 {first_skill_row} 行 · 代号（自动，别填）"
        dup_hit = (f"代号『{ledger['skills'][0]}』重复" in t14d and dup_loc in t14d)
        record("增量四④ 新技能代号与既有重复 → 中文报错且不生成 JSON", 
               pv14d.returncode != 0 and not o14d.exists() and dup_hit,
               f"退出码={pv14d.returncode}，未生成 JSON={not o14d.exists()}，"
               f"命中『代号『{ledger['skills'][0]}』重复』={dup_hit}")
        print("  --- 代号重复中文报错（原始）---")
        indent_print(t14d)

        v14_bad = real_variant(
            "v14_bad_id",
            add_skills=[dict(new_skill, **{"代号（自动，别填）": "自检 新技能"})],
            add_parts=[new_part])
        pv14d2, o14d2, d14d2, t14d2 = a_variant("v14_bad_id", v14_bad)
        bad_hit = ("不能作为资源文件名" in t14d2 and dup_loc in t14d2)
        record("增量四④附带 新技能代号非法（不能当资源文件名）→ 中文报错",
               pv14d2.returncode != 0 and not o14d2.exists() and bad_hit,
               f"退出码={pv14d2.returncode}，未生成 JSON={not o14d2.exists()}，定位命中={bad_hit}")

        # ---- 变体⑤：代号留空自动生成规则 ----
        # ⑤-1 单条：留空（真空）与占位说明等价的生成结果一致，且从 001 起取最小未占用号。
        v14_id_empty = real_variant("v14_id_empty", add_skills=[dict(new_skill, **{"代号（自动，别填）": None})],
                                    add_parts=[new_part])
        pv14e, o14e, d14e, t14e = a_variant("v14_id_empty", v14_id_empty)
        gen_empty = "skill_001" in t14e
        v14_id_hint = real_variant("v14_id_hint", add_skills=[new_skill], add_parts=[new_part])
        pv14e2, o14e2, d14e2, t14e2 = a_variant("v14_id_hint", v14_id_hint)
        gen_hint = "skill_001" in t14e2
        record("增量四⑤ 代号留空 / 留占位说明 → 都自动生成 skill_001（规则一致）",
               gen_empty and gen_hint and t14e2.split("skill_")[1][:3] == t14e.split("skill_")[1][:3],
               f"留空→skill_001={gen_empty}，占位说明→skill_001={gen_hint}")

        # ⑤-2 多张新卡：2 张新技能卡按行序生成 001 / 002，互不重号
        new_skill2 = dict(new_skill, **{"技能名": "自检新技能二"})
        new_part2 = dict(new_part, **{"属于哪个技能": "自检新技能二"})
        v14_two = real_variant("v14_two_skills",
                               add_skills=[new_skill, new_skill2],
                               add_parts=[new_part, new_part2])
        pv14f, o14f, d14f, t14f = a_variant("v14_two_skills", v14_two)
        # 两个新代号都只出现在「自动生成代号」黄色提醒里（数量守卫报错只汇总代号），
        # 故两者一起在 errors.json 的 text + warnings 里找，并核对落在第一 / 第二个预留行。
        # 数量守卫命中时不会生成中间 JSON（d14f 为 None），真正的黄色提醒在错误清单
        # errors.json 的 warnings 字段里 —— 必须从错误清单读，不能只读 payload。
        two_warnings = json.loads((BASE / "var_v14_two_skills" / "errors.json")
                                  .read_text(encoding="utf-8")).get("warnings", [])
        two_text = t14f + "\n" + "\n".join(two_warnings)
        row_a = f"第 {first_skill_row} 行"
        row_b = f"第 {first_skill_row + 1} 行"
        two_ok = ("skill_001" in two_text and "skill_002" in two_text
                  and row_a in two_text and row_b in two_text)
        record("增量四⑤附带 同批 2 张新技能卡 → skill_001 / skill_002 互不重号", two_ok,
               f"退出码={pv14f.returncode}，skill_001/skill_002 分别落在 "
               f"第 {first_skill_row} / {first_skill_row + 1} 行={two_ok}")

        # ⑤-2b 新号避重：表里既有行显式占用 skill_001（台账里没有这个文件）时，
        # 新技能卡必须越过它、拿到 skill_002 —— 证明「避开既有 80 条」不只看 content/gems，
        # 也看表内其他行已经写死的代号。
        v14_avoid = real_variant("v14_id_avoid",
                                 add_skills=[dict(new_skill, **{"技能名": "自检占号",
                                                                "代号（自动，别填）": "skill_001"}),
                                             new_skill],
                                 add_parts=[new_part])
        pv14i, o14i, d14i, t14i = a_variant("v14_id_avoid", v14_avoid)
        avoid_warnings = json.loads((BASE / "var_v14_id_avoid" / "errors.json")
                                    .read_text(encoding="utf-8")).get("warnings", [])
        avoid_text = t14i + "\n" + "\n".join(avoid_warnings)
        avoid_ok = (pv14i.returncode != 0 and not o14i.exists()
                    and f"第 {first_skill_row + 1} 行" in avoid_text
                    and "skill_002" in avoid_text
                    and "代号『skill_001』重复" not in t14i)
        record("增量四⑤附带 新号避开表内既有显式代号（占用 skill_001 → 新卡得 skill_002）",
               avoid_ok,
               f"退出码={pv14i.returncode}，未生成 JSON={not o14i.exists()}，"
               f"第二个预留行拿到 skill_002={avoid_ok}")

        # ⑤-3 新辅助石：代号留空 → support_001 + 数量守卫（辅助石 13→14）
        v14_sup = real_variant("v14_new_support", add_supports=[{
            "辅助石名": "自检新辅助",
            "代号（自动，别填）": REAL_HINT,
            "消耗倍率": 1.2,
            "属性": "暴击率",
            "运算": "固定加值",
            "数值": 5,
            "高级数据（工具自动，勿改）": "{}",
        }])
        pv14g, o14g, d14g, t14g = a_variant("v14_new_support", v14_sup)
        sup_ok = ("support_001" in t14g and "④ 辅助石 第 0 行 · 数量守卫" in t14g
                  and "需按台账 P-23" in t14g and not o14g.exists())
        record("增量四⑤附带 新辅助石代号留空 → support_001 + 数量守卫（④ 辅助石）", sup_ok,
               f"退出码={pv14g.returncode}，未生成 JSON={not o14g.exists()}，"
               f"报错含 support_001 与④定位={sup_ok}")
        print("  --- 新辅助石中文报错（原始）---")
        indent_print(t14g)

        # ⑤-4 同批新技能 + 新辅助石：两条数量守卫各自命中，代号互不串用
        v14_both = real_variant("v14_both", add_skills=[new_skill], add_parts=[new_part],
                                add_supports=[{
                                    "辅助石名": "自检新辅助",
                                    "代号（自动，别填）": None,
                                    "消耗倍率": 1.2,
                                    "属性": "暴击率",
                                    "运算": "固定加值",
                                    "数值": 5,
                                    "高级数据（工具自动，勿改）": "{}",
                                }])
        pv14h, o14h, d14h, t14h = a_variant("v14_both", v14_both)
        both_ok = ("② 技能卡 第 0 行 · 数量守卫" in t14h
                   and "④ 辅助石 第 0 行 · 数量守卫" in t14h
                   and "skill_001" in t14h and "support_001" in t14h)
        record("增量四⑤附带 同批新技能 + 新辅助石 → 两条数量守卫各自命中", both_ok,
               f"退出码={pv14h.returncode}，②/④ 数量守卫同时命中={both_ok}")
        print("  --- 同批新增中文报错（原始）---")
        indent_print(t14h)

        # 台账目录缺失（--content 指向不存在的目录）时不做数量守卫：证明守卫由台账驱动、
        # 不会因目录缺失而误拦正常链路（守卫只由 content/gems 台账驱动，不是写死数字）。
        v14_noledger = real_variant("v14_no_ledger", add_skills=[new_skill], add_parts=[new_part])
        nl_dir = BASE / "var_v14_no_ledger"
        nl_out = nl_dir / "build_input.json"
        nl_err = nl_dir / "errors.json"
        pnl, _ = run("变体_v14_no_ledger",
                     a_cmd(v14_noledger, nl_out, nl_err) + ["--content", str(BASE / "no_such_dir")])
        nl_text = json.loads(nl_err.read_text(encoding="utf-8")).get("text", "") if nl_err.exists() else ""
        nl_ok = (pnl.returncode == 0 and nl_out.exists() and "P-23" not in nl_text)
        record("增量四⑤附带 台账目录缺失 → 不做数量守卫（守卫由台账驱动，不误拦）", nl_ok,
               f"退出码={pnl.returncode}，生成 JSON={nl_out.exists()}，"
               f"未出现数量守卫提示={'P-23' not in nl_text}")


    # ---------------------------------------------------------- 汇总 ----
    print("\n########## W3 自检汇总 ##########")
    lines = ["W3 自检汇总（每项后附实测值）", "=" * 60]
    for name, ok, detail in results:
        line = ("[通过] " if ok else "[失败] ") + name + " → " + detail
        lines.append(line)
        print(line)
    all_ok = all(ok for _, ok, _ in results)
    lines.append("=" * 60)
    lines.append("结论：" + ("全部通过" if all_ok else "存在未通过项"))
    lines.append("全部原始输出见：" + str(LOGS))
    (BASE / "selfcheck_summary.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("结论：" + ("全部通过" if all_ok else "存在未通过项"))
    print("汇总文件：" + str(BASE / "selfcheck_summary.txt"))
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
