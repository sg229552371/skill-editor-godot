# -*- coding: utf-8 -*-
"""W4 · 一键收尾自检。

三项自检（必须实际跑通，保留原始输出）：
  一、跑 --dry-run，核对命令序列与总任务书 §8 完全一致；
      另用模拟文本核对 GUT 汇总解析与门禁指标（不跑真实全量 GUT 门禁）。
  二、用 finish/_tmp/ 下的测试工作簿验证 report.py 能正确写入「⑥ 检查结果」，
      且不破坏其它页签（比对其它页签单元格值、合并区域、列宽前后一致）；
      同时验证该页签的说明行 / 表头行不变，只改数据行。
  三、用隔离的假项目根验证依赖脚本缺失时 run_all.py 优雅报
      「等待 W2/W3 交付」而非崩溃，且未执行任何命令、未落盘。

自检不依赖 W2/W3 脚本真的存在，也不打开真实工作簿、不跑全量门禁、不落盘。
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

from openpyxl import Workbook, load_workbook

FINISH_DIR = Path(__file__).resolve().parent
if str(FINISH_DIR) not in sys.path:
    sys.path.insert(0, str(FINISH_DIR))

import report  # noqa: E402
import run_all  # noqa: E402

TMP_DIR = FINISH_DIR / "_tmp"
RAW_LOG = TMP_DIR / "selfcheck_raw_output.txt"
TEST_WORKBOOK = TMP_DIR / "selfcheck_workbook.xlsx"
DEP_RESULT_JSON = TMP_DIR / "selfcheck_dep_result.json"
FAKE_ROOT = TMP_DIR / "fake_root"
RUN_ALL_PY = FINISH_DIR / "run_all.py"
FAILFAST_ROOT = TMP_DIR / "failfast_root"
FAILFAST_WORKBOOK = TMP_DIR / "failfast_workbook.xlsx"
FAILFAST_RESULT = TMP_DIR / "failfast_result.json"
# 增量二：模拟 W3 结构化错误清单，全部造在 finish/_tmp/，绝不写 W3 的共享目录
MOCK_ERRORS_JSON = TMP_DIR / "mock_errors.json"
BROKEN_ERRORS_JSON = TMP_DIR / "broken_errors.json"
ZERO_ERRORS_JSON = TMP_DIR / "zero_errors.json"
MISSING_ERRORS_JSON = TMP_DIR / "no_such_errors_increment2.json"  # 故意不创建
ERRORS_CHECK_WORKBOOK = TMP_DIR / "errors_check_workbook.xlsx"
DEGRADE_CHECK_WORKBOOK = TMP_DIR / "degrade_check_workbook.xlsx"

# 期望的命令序列：命令形态取自总任务书 §8，执行顺序按 W4 任务卡
EXPECTED_COMMANDS = [
    "godot --headless --path . --import",
    "godot --headless --path . --import",
    "godot --headless --path . -s res://mods/jes-skills/tools/content_workbench/export/export_to_json.gd",
    "python mods/jes-skills/tools/content_workbench/export/build_workbook.py",
    "python mods/jes-skills/tools/content_workbench/build/read_workbook.py mods/jes-skills/content_src/技能配置表.xlsx",
    "godot --headless --path . -s res://mods/jes-skills/tools/content_workbench/build/build_from_json.gd",
    "godot --headless --path . -s res://mods/jes-skills/tools/gen_api_map.gd",
    "godot --headless --path . -s res://mods/jes-skills/tests/skills/gen_content_snapshot.gd",
    "git diff --exit-code mods/jes-skills/content/",
    "godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://mods/jes-skills/tests -ginclude_subdirs -gexit",
]

RAW_LINES = []
CHECKS = []


def log(text=""):
    """打印并保留原始输出。"""
    print(text)
    RAW_LINES.append(str(text))


def check(label, condition, measured):
    """记录一条断言：验收项 → 实测值。"""
    CHECKS.append((label, bool(condition), measured))
    mark = "通过" if condition else "未通过"
    log(f"    [{mark}] {label}｜实测：{measured}")


def project_root():
    for parent in FINISH_DIR.parents:
        if (parent / "project.godot").is_file():
            return parent
    raise RuntimeError("找不到项目根（含 project.godot 的目录）")


def read_spec_commands(root):
    """从总任务书 §8 表格里抽取命令形态（只读，不改）。"""
    spec = root / "策划配置表工具_施工总任务书.md"
    text = spec.read_text(encoding="utf-8")
    section = text.split("## 8. 环境命令", 1)[1].split("## 9.", 1)[0]
    candidates = re.findall(r"`([^`]+)`", section)
    return [item.strip() for item in candidates
            if item.strip().startswith(("godot ", "git "))]


def run_dry_run(extra_args=()):
    """在真实项目根下跑空跑，保证依赖状态与工作簿相对路径按真实环境解析。"""
    command = [sys.executable, str(RUN_ALL_PY), "--dry-run", *extra_args]
    proc = subprocess.run(command, capture_output=True, text=True,
                          encoding="utf-8", errors="replace",
                          cwd=str(project_root()))
    return proc, (proc.stdout or "") + (proc.stderr or "")


# ---------------------------------------------------------------------------
# 逐条核对：10 步命令与 W2/W3 已交付脚本的真实签名一致
# ---------------------------------------------------------------------------
def selfcheck_signatures(root, extracted):
    """只读抽取脚本签名，核对每条命令「脚本路径之后的入参」无缺参、无多参。"""
    log("【W2/W3 已交付脚本的真实签名（只读源码抽取）】")
    rw_text = (root / run_all.W3_READ_PY).read_text(encoding="utf-8")
    positional = re.findall(r'add_argument\(\s*"([^"-][^"]*)"', rw_text)
    options = re.findall(r'add_argument\(\s*"(--[^"]+)"', rw_text)
    log(f"    read_workbook.py 位置参数 {positional}；可选参数 {options}")
    check("W3 read_workbook.py 真实签名 = 1 个必填位置参数 workbook",
          positional == ["workbook"], f"实测 {positional}")
    check("W3 read_workbook.py 的 --out / --errors 有默认值，不必显式传",
          "--out" in options and "--errors" in options, f"实测 {options}")

    bj_text = (root / run_all.W3_BUILD_GD).read_text(encoding="utf-8")
    a_default = 'WORKBENCH / "_tmp" / "build_input.json"' in rw_text
    b_default = "content_workbench/_tmp/build_input.json" in bj_text
    check("A 默认 --out 与 B DEFAULT_INPUT 指向同一中间 JSON（故不额外传 --out）",
          a_default and b_default,
          f"A 默认输出命中={a_default}，B 默认输入命中={b_default}")

    bw_text = (root / run_all.W2_BUILD_PY).read_text(encoding="utf-8")
    check("W2 build_workbook.py 无 argparse / sys.argv（零入参）",
          "add_argument(" not in bw_text and "sys.argv" not in bw_text, "零入参")
    ej_text = (root / run_all.W2_EXPORT_GD).read_text(encoding="utf-8")
    check("W2 export_to_json.gd 不读命令行参数（零入参）",
          "get_cmdline_user_args" not in ej_text, "零入参")
    check("W3 build_from_json.gd 的 --input/--output 为可选项且有默认值（零必填入参）",
          "DEFAULT_INPUT" in bj_text and "--input" in bj_text, "有默认值，无需传参")
    log()

    # 只对 W2/W3 交付的 4 个脚本核对「脚本路径之后的入参」；
    # 其余 6 步是 §8 固定命令形态（含 GUT 的 -gdir 等），已由「命令序列逐条一致」核对。
    expected_tail = {
        3: [], 4: [], 5: [run_all.DEFAULT_WORKBOOK_REL], 6: [],
    }
    actual_tail = {}
    for index, command in enumerate(extracted, 1):
        tokens = command.split()
        tail = []
        for pos, token in enumerate(tokens):
            if token.endswith(".gd") or token.endswith(".py"):
                tail = tokens[pos + 1:]
                break
        actual_tail[index] = tail

    log("【逐条核对：10 步命令在脚本路径之后的入参】")
    for index in range(1, 11):
        if index in expected_tail:
            note = f"｜W2/W3 脚本签名要求 {expected_tail[index]}"
        else:
            note = "｜§8 固定命令形态（非 W2/W3 脚本，按 §8 核对）"
        log(f"    {index:02d}  实际入参 {actual_tail.get(index, [])}{note}")
    log()
    matched = {key: actual_tail.get(key, []) for key in expected_tail} == expected_tail
    check("W2/W3 四步入参逐条与真实签名一致（无缺参数、无多参数）", matched,
          "逐条一致" if matched else
          f"不一致：{[k for k in expected_tail if actual_tail.get(k, []) != expected_tail[k]]}")
    check("10 条命令形态逐条与 §8 一致（含 GUT 全部固定参数）",
          extracted == EXPECTED_COMMANDS, "逐条一致" if extracted == EXPECTED_COMMANDS else "不一致")
    check("第 5 步工作簿参数为相对项目根路径，未写盘符绝对路径",
          actual_tail.get(5) == [run_all.DEFAULT_WORKBOOK_REL]
          and not re.match(r"^[A-Za-z]:", actual_tail.get(5, [""])[0]),
          f"实测 {actual_tail.get(5)}")
    check("W2/W3 其余三步（3/4/6）均为零入参",
          all(actual_tail.get(index) == [] for index in (3, 4, 6)),
          "全部为零入参")
    log()


# ---------------------------------------------------------------------------
# 自检一：--dry-run 命令序列
# ---------------------------------------------------------------------------
def selfcheck_dry_run(root):
    log("=" * 72)
    log("自检一：--dry-run 命令序列与总任务书 §8 完全一致")
    log("=" * 72)
    proc, text = run_dry_run()
    log("【原始输出：python run_all.py --dry-run】")
    log(text.rstrip())
    log()

    check("空跑退出码为 0", proc.returncode == 0, f"退出码 {proc.returncode}")
    check("空跑未声称执行了命令", "执行中" not in text, "输出里没有「执行中」字样")

    extracted = re.findall(r"^[ \t]*命令：(.+?)[ \t]*$", text, re.M)
    log(f"【从空跑输出提取到的命令序列】共 {len(extracted)} 条")
    for index, command in enumerate(extracted, 1):
        log(f"    {index:02d}  {command}")
    log()

    check("命令条数 = 10", len(extracted) == 10, f"实测 {len(extracted)} 条")
    check("命令序列逐条与预期一致", extracted == EXPECTED_COMMANDS,
          "逐条一致" if extracted == EXPECTED_COMMANDS else f"实测 {extracted}")
    check("空跑显示依赖存在性检查（只读、不执行命令）", "依赖存在性检查" in text, "含该段")
    check("依赖检查现在全部通过：8/8 全部就位",
          "全部就位" in text and "8/8" in text,
          "全部就位：8/8 项依赖均已落盘" if "全部就位" in text else "未全部就位")
    check("不再报「等待 W2/W3 交付」", "等待 W2/W3 交付" not in text,
          "输出不含该提示" if "等待 W2/W3 交付" not in text else "仍含该提示")

    spec_commands = read_spec_commands(root)
    log("【总任务书 §8 抽取到的命令形态】")
    for command in spec_commands:
        log(f"    {command}")
    log()
    check("§8 命令形态共 5 条", len(spec_commands) == 5, f"实测 {len(spec_commands)} 条：{spec_commands}")
    check("§8 每条命令都在空跑输出里逐字出现",
          all(command in text for command in spec_commands),
          "全部出现" if all(command in text for command in spec_commands)
          else "缺少：" + "、".join(c for c in spec_commands if c not in text))
    check("§8 每条命令都在期望序列里",
          all(command in EXPECTED_COMMANDS for command in spec_commands),
          "全部收录")
    check("两次 --import 刷新类缓存（P-08）",
          extracted.count("godot --headless --path . --import") == 2,
          f"实测出现 {extracted.count('godot --headless --path . --import')} 次")
    check("第 4 步默认标注为跳过（不覆盖策划已填内容）",
          "跳过（默认不重建，避免覆盖策划已填内容" in text, "输出含跳过标注")
    check("末尾标注结果回写「⑥ 检查结果」页签",
          "结果回写" in text and "⑥ 检查结果" in text, "输出含结果回写说明")
    selfcheck_signatures(root, extracted)

    # 加 --rebuild-workbook 后第 4 步应变为「执行」
    proc2, text2 = run_dry_run(("--rebuild-workbook",))
    log("【原始输出：python run_all.py --dry-run --rebuild-workbook（第 4 步节选）】")
    lines2 = text2.splitlines()
    for index, line in enumerate(lines2):
        if "[04]" in line:
            for snippet in lines2[index:index + 3]:
                log("    " + snippet)
            break
    log()
    check("加 --rebuild-workbook 时空跑退出码为 0", proc2.returncode == 0, f"退出码 {proc2.returncode}")
    check("加 --rebuild-workbook 后第 4 步不再跳过",
          "跳过（默认不重建" not in text2, "输出里没有跳过标注")
    check("默认不重建工作簿：仅第 4 步跳过，其余 9 步执行",
          text.count("状态：执行") == 9 and text.count("状态：跳过") == 1,
          f"实测「状态：执行」{text.count('状态：执行')} 处、「状态：跳过」{text.count('状态：跳过')} 处")
    check("加 --rebuild-workbook 后 10 步全部执行",
          text2.count("状态：执行") == 10 and "状态：跳过" not in text2,
          f"实测「状态：执行」{text2.count('状态：执行')} 处")
    check("W2 build_workbook.py 命令两次空跑均零入参",
          f"命令：python {run_all.W2_BUILD_PY}" in text
          and f"命令：python {run_all.W2_BUILD_PY}" in text2,
          "两次命令一致且无额外入参")

    # 门禁解析逻辑：只用模拟文本，绝不跑真实全量 GUT 门禁
    log("【门禁解析单测：模拟 GUT Totals 文本，不跑真实门禁】")
    good = ("Totals\n------\n"
            "Scripts                  37\n"
            "Tests                    370\n"
            "Passing Tests            370\n"
            "Asserts                 4716\n"
            "Time                    1.2s\n")
    fake_green = good.replace("Scripts                  37", "Scripts               none")
    low_tests = good.replace("Tests                    370", "Tests                    300")
    broken = "---- 没有任何汇总 ----\n"

    metrics, err = run_all.parse_gut_totals(good)
    problems = run_all.check_gate(metrics, 0, err)
    log(f"    正常 37/370/4716 → 指标 {metrics and {k: metrics[k] for k in ('scripts','tests','asserts')}}，问题 {problems}")
    check("正常汇总解析并核对通过", metrics is not None and not problems,
          f"Scripts={metrics and metrics['scripts']}，用例={metrics and metrics['tests']}，"
          f"断言={metrics and metrics['asserts']}，问题数={len(problems)}")

    metrics0, err0 = run_all.parse_gut_totals(fake_green)
    problems0 = run_all.check_gate(metrics0, 0, err0)
    log(f"    假绿（整份静默跳过）→ 指标 {metrics0 and metrics0['scripts']}，问题 {problems0}")
    check("Scripts 非 37 被判失败（防假绿）",
          any("Scripts" in item for item in problems0), f"实测问题：{problems0}")

    metrics1, err1 = run_all.parse_gut_totals(low_tests)
    problems1 = run_all.check_gate(metrics1, 0, err1)
    check("用例数 < 370 被判失败", any("用例数" in item for item in problems1),
          f"实测问题：{problems1}")

    metrics2, err2 = run_all.parse_gut_totals(broken)
    problems2 = run_all.check_gate(metrics2, 0, err2)
    check("缺少 Totals 视为解析失败", bool(problems2), f"实测问题：{problems2}")
    log()


# ---------------------------------------------------------------------------
# 自检二：report.py 写入「⑥ 检查结果」且不破坏其它页签
# ---------------------------------------------------------------------------
def snapshot(workbook, sheet_names):
    """记录页签的单元格值 / 合并区域 / 列宽，用于前后比对。"""
    data = {}
    for name in sheet_names:
        sheet = workbook[name]
        data[name] = {
            "values": [[sheet.cell(row, col).value
                        for col in range(1, sheet.max_column + 1)]
                       for row in range(1, sheet.max_row + 1)],
            "merged": sorted(str(item) for item in sheet.merged_cells.ranges),
            "widths": {key: dim.width for key, dim in sheet.column_dimensions.items()},
        }
    return data


def make_test_workbook(path, schema):
    """在 _tmp/ 下造一个等价测试工作簿（不打开真实工作簿）。"""
    titles = [item["title"] for item in schema["sheets"]]
    workbook = Workbook()
    workbook.active.title = titles[0]
    for title in titles[1:]:
        workbook.create_sheet(title)

    # 其它 5 个页签：模拟 W2 的静态结构（中文列头、示例行、说明、数字、空值、公式）
    readme = workbook[titles[0]]
    readme["A1"] = "① 先看这里"
    readme["A2"] = "三句话说明：策划只填中文列"
    readme["B2"] = "三色图例"
    readme["A3"] = "常见错误：代号列别填"
    readme["C4"] = 42
    readme.merge_cells("B2:C2")
    readme.column_dimensions["A"].width = 22

    skills = workbook[titles[1]]
    for col, value in enumerate(["技能名", "代号（自动，别填）", "施法方式", "消耗数值"], 1):
        skills.cell(1, col, value)
    skills.cell(2, 1, "火球")
    skills.cell(2, 2, "skill_001")
    skills.cell(2, 3, "主动施放")
    skills.cell(2, 4, 12)
    skills.cell(3, 1, "冰霜新星")
    skills.cell(3, 5, "=SUM(D2:D3)")
    skills.column_dimensions["B"].width = 26

    parts = workbook[titles[2]]
    parts["A1"] = "属于哪个技能"
    parts["B1"] = "第几段"
    parts["C1"] = "效果"
    parts["A2"] = "火球"
    parts["B2"] = 1
    parts["C2"] = "投掷物"

    supports = workbook[titles[3]]
    supports["A1"] = "辅助石名"
    supports["B1"] = "代号（自动，别填）"
    supports["A2"] = "多重投射"
    supports["B2"] = "support_001"

    options = workbook[titles[4]]
    options["A1"] = "下拉词表（策划不看）"
    options["A2"] = "投掷物"
    options["A3"] = "近战挥砍"
    options.sheet_state = "hidden"

    # 「⑥ 检查结果」：第 1 行说明、第 2 行表头、第 3 行模拟上次结果残留
    check_sheet = workbook[titles[5]]
    check_sheet["A1"] = "本页由一键收尾自动填写，策划不用改（说明文字）"
    for col, value in enumerate(["页签", "行", "列", "问题", "怎么改"], 1):
        check_sheet.cell(2, col, value)
    check_sheet.cell(3, 1, "旧结果")
    check_sheet.cell(3, 4, "上一次的残留")
    check_sheet.cell(3, 5, "无")

    workbook.save(path)
    return titles


def make_fake_result():
    """模拟一次「W3 中文校验失败」的收尾结果。"""
    return {
        "success": False,
        "phase": "失败",
        "summary": "第 5 步中文分层校验未通过，已停止后续步骤、未落盘。",
        "steps": [
            {"name": "刷新全局类缓存（第 1 次，P-08）", "ok": True, "skipped": False,
             "exit_code": 0, "detail": "退出码 0"},
            {"name": "刷新全局类缓存（第 2 次，P-08）", "ok": True, "skipped": False,
             "exit_code": 0, "detail": "退出码 0"},
            {"name": "W2 首次建表 build_workbook.py", "ok": True, "skipped": True,
             "exit_code": 0, "detail": "默认跳过"},
            {"name": "W3 读表与中文分层校验 read_workbook.py", "ok": False, "skipped": False,
             "exit_code": 1, "detail": "退出码 1"},
            {"name": "全量 GUT 门禁", "ok": False, "skipped": False,
             "exit_code": None, "detail": "未执行（前序步骤失败，已立即停止）"},
        ],
        "errors": [
            {"sheet": "② 技能卡", "row": 12, "column": "消耗数值",
             "problem": "消耗数值不能为负数", "fix": "改成 0 或正数"},
            {"sheet": "③ 效果段", "row": 7, "column": "效果",
             "problem": "效果不能为空", "fix": "从下拉里选一个效果"},
        ],
        "gate": {"scripts": 37, "tests": 370, "asserts": 4716},
        "dry_run": False,
    }


def selfcheck_report(schema):
    log("=" * 72)
    log("自检二：report.py 写入「⑥ 检查结果」，且不破坏其它页签")
    log("=" * 72)
    titles = make_test_workbook(TEST_WORKBOOK, schema)
    report_title = report.report_sheet_title(schema)
    other_titles = [title for title in titles if title != report_title]

    before_workbook = load_workbook(TEST_WORKBOOK)
    before = snapshot(before_workbook, other_titles)
    before_note = [before_workbook[report_title].cell(1, col).value for col in range(1, 6)]
    before_header = [before_workbook[report_title].cell(2, col).value for col in range(1, 6)]
    log(f"【测试工作簿】{TEST_WORKBOOK.name}（不打开真实工作簿）")
    log(f"    页签：{'、'.join(titles)}")
    log(f"    其它页签共 {len(other_titles)} 个，记录单元格值 / 合并区域 / 列宽快照")
    log(f"    「{report_title}」说明行原文：{before_note}")
    log(f"    「{report_title}」表头行原文：{before_header}")
    log()

    result = make_fake_result()
    info = report.write_report(str(TEST_WORKBOOK), result)
    log("【report.write_report 返回】")
    log(f"    {json.dumps(info, ensure_ascii=False)}")
    log()

    after_workbook = load_workbook(TEST_WORKBOOK)
    after = snapshot(after_workbook, other_titles)
    check("其它页签单元格值前后完全一致",
          all(before[name]["values"] == after[name]["values"] for name in other_titles),
          "；".join(f"{name}: {'一致' if before[name]['values'] == after[name]['values'] else '不一致'}"
                    for name in other_titles))
    check("其它页签合并区域前后完全一致",
          all(before[name]["merged"] == after[name]["merged"] for name in other_titles),
          "；".join(f"{name}: {'一致' if before[name]['merged'] == after[name]['merged'] else '不一致'}"
                    for name in other_titles))
    check("其它页签列宽前后完全一致",
          all(before[name]["widths"] == after[name]["widths"] for name in other_titles),
          "；".join(f"{name}: {'一致' if before[name]['widths'] == after[name]['widths'] else '不一致'}"
                    for name in other_titles))
    check("页签名单未变（没有新增/删除页签）",
          after_workbook.sheetnames == titles, f"实测 {after_workbook.sheetnames}")

    sheet = after_workbook[report_title]
    after_note = [sheet.cell(1, col).value for col in range(1, 6)]
    after_header = [sheet.cell(2, col).value for col in range(1, 6)]
    check("「⑥ 检查结果」说明文字行未改动", after_note == before_note, f"实测 {after_note}")
    check("「⑥ 检查结果」列头行未改动（不改静态结构）",
          after_header == before_header, f"实测 {after_header}")

    data_rows = []
    for row in range(3, sheet.max_row + 1):
        values = [sheet.cell(row, col).value for col in range(1, 6)]
        if any(value not in (None, "") for value in values):
            data_rows.append(values)
    log("【写入后的「⑥ 检查结果」数据行（页签 / 行 / 列 / 问题 / 怎么改）】")
    for row_values in data_rows:
        log(f"    {row_values}")
    log()
    all_text = "\n".join(str(value) for row in data_rows for value in row if value is not None)

    check("写入了数据行", len(data_rows) >= 8, f"实测 {len(data_rows)} 行")
    check("写入整体「失败」结论", "失败" in all_text, "含「失败」")
    check("写入每一步结论（含「未执行」的前序停止说明）",
          "刷新全局类缓存" in all_text and "未执行" in all_text, "含步骤结论与未执行说明")
    check("写入门禁核对行", "门禁核对" in all_text and "37" in all_text, "含门禁核对与 37")
    check("错误清单含「页签 + 行 + 列 + 问题 + 怎么改」",
          all(token in all_text for token in ["② 技能卡", "12", "消耗数值", "不能为负数", "改成 0 或正数"]),
          "② 技能卡 / 12 / 消耗数值 / 不能为负数 / 改成 0 或正数 全部出现")
    check("错误清单按列落在正确位置（页签列=② 技能卡，行=12，列=消耗数值）",
          any(row[0] == "② 技能卡" and str(row[1]) == "12" and row[2] == "消耗数值"
              and row[3] == "消耗数值不能为负数" for row in data_rows),
          "找到对应数据行")
    check("上次结果残留已清除", "上一次的残留" not in all_text, "不含旧残留")
    log()


# ---------------------------------------------------------------------------
# 自检三：依赖脚本缺失时优雅报「等待 W2/W3 交付」
# ---------------------------------------------------------------------------
def selfcheck_missing_deps():
    log("=" * 72)
    log("自检三：依赖脚本缺失时优雅报「等待 W2/W3 交付」，不崩溃、不执行、不落盘")
    log("=" * 72)
    FAKE_ROOT.mkdir(parents=True, exist_ok=True)
    # 假项目根里造齐「项目既有」文件的占位，但不放 W2/W3 脚本、不放工作簿，
    # 于是缺失清单只反映「等待 W2/W3 交付」，且自检不依赖它们真的存在。
    (FAKE_ROOT / "project.godot").write_text("; 自检占位，非真实项目\n", encoding="utf-8")
    for rel in (run_all.API_MAP_GD, run_all.SNAPSHOT_GD, run_all.GUT_CMDLN_GD):
        target = FAKE_ROOT / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("; 自检占位\n", encoding="utf-8")

    # 打印一律用占位符，绝不把本机盘符绝对路径写进日志或提交物；实际执行用真实路径
    display = ("python finish/run_all.py --project-root <_tmp/fake_root> "
               "--result-json <_tmp/selfcheck_dep_result.json>")
    real_command = [sys.executable, str(RUN_ALL_PY),
                    "--project-root", str(FAKE_ROOT),
                    "--result-json", str(DEP_RESULT_JSON)]
    log(f"【自检命令（内部路径用占位显示）】{display}")
    proc = subprocess.run(real_command, capture_output=True, text=True,
                          encoding="utf-8", errors="replace")
    text = (proc.stdout or "") + (proc.stderr or "")
    log("【原始输出：run_all.py --project-root <_tmp/fake_root>】")
    log(text.rstrip())
    log()

    check("退出码为 2（等待交付专用码，非崩溃）", proc.returncode == 2,
          f"实测退出码 {proc.returncode}")
    check("明确报「等待 W2/W3 交付」", "等待 W2/W3 交付" in text, "含该中文提示")
    check("没有 Python 异常栈", "Traceback" not in text and "Exception" not in text,
          "输出里没有 Traceback / Exception")
    check("明确说明未执行任何生成命令", "未执行任何生成命令" in text, "含该说明")
    check("明确说明未真实落盘", "未真实落盘" in text, "含该说明")
    check("列出缺失的 W2/W3 依赖", "export_to_json.gd" in text and "read_workbook.py" in text,
          "列出了 export_to_json.gd 与 read_workbook.py")
    check("声明不自行补写脚本", "不自行补写它们的脚本" in text, "含该声明")

    phase = None
    if DEP_RESULT_JSON.is_file():
        with DEP_RESULT_JSON.open("r", encoding="utf-8") as handle:
            phase = json.load(handle).get("phase")
    check("结果 JSON 记录 phase=等待交付", phase == "等待交付", f"实测 phase={phase}")
    log()


def selfcheck_fail_fast(schema):
    """补充实测（非三项之一）：任一步失败立即停止后续步骤，并把中文错误回写。

    用假的 subprocess.run 让第 1 步返回 1，后续命令一次都不该被发起；
    全程不执行任何真实命令、不跑门禁、不落盘。
    """
    import io
    import shutil
    from contextlib import redirect_stdout

    log("=" * 72)
    log("补充实测：任一步失败立即停止后续步骤、中文错误回写、未落盘")
    log("=" * 72)

    FAILFAST_ROOT.mkdir(parents=True, exist_ok=True)
    (FAILFAST_ROOT / "project.godot").write_text("; 自检占位，非真实项目\n", encoding="utf-8")
    # 只在 _tmp/ 的假项目根里放占位文件，绝不触碰真实的 W2/W3 脚本
    placeholders = [
        run_all.W2_EXPORT_GD, run_all.W2_BUILD_PY,
        run_all.W3_READ_PY, run_all.W3_BUILD_GD,
        run_all.API_MAP_GD, run_all.SNAPSHOT_GD, run_all.GUT_CMDLN_GD,
    ]
    for rel in placeholders:
        target = FAILFAST_ROOT / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("; 自检占位\n", encoding="utf-8")
    shutil.copyfile(TEST_WORKBOOK, FAILFAST_WORKBOOK)

    calls = []
    original_run = run_all.subprocess.run

    def fake_run(command, **kwargs):
        calls.append(list(command))
        return subprocess.CompletedProcess(
            command, 1, stdout="模拟：第 1 步刷新全局类缓存失败", stderr="")

    buffer = io.StringIO()
    run_all.subprocess.run = fake_run
    try:
        with redirect_stdout(buffer):
            return_code = run_all.main([
                "--godot", "godot",
                "--project-root", str(FAILFAST_ROOT),
                "--workbook", str(FAILFAST_WORKBOOK),
                "--result-json", str(FAILFAST_RESULT),
            ])
    finally:
        run_all.subprocess.run = original_run

    # run_all 的打印只含相对路径与 res:// 形态，不含本机盘符绝对路径
    main_output = buffer.getvalue()
    log("【原始输出：模拟第 1 步失败后的一键收尾】")
    log(main_output.rstrip())
    log()
    log(f"【实际发起的子进程命令】共 {len(calls)} 条：{calls}")
    log()

    check("失败时返回码为 1", return_code == 1, f"实测 {return_code}")
    check("只发起第 1 步，后续命令一次都没执行（立即停止）", len(calls) == 1,
          f"实测发起 {len(calls)} 条命令")
    check("原始输出明确声明已停止、不落盘",
          "已立即停止" in main_output and "不落盘" in main_output, "含该中文声明")

    result = json.loads(FAILFAST_RESULT.read_text(encoding="utf-8"))
    check("后续 9 步全部标记为「未执行」",
          all("未执行" in (item.get("detail") or "") for item in result["steps"][1:]),
          "；".join(f"第{i + 2}步「{(item.get('detail') or '')[:16]}」"
                    for i, item in enumerate(result["steps"][1:])))
    check("失败中文错误清单已生成", len(result.get("errors", [])) > 0,
          f"实测 {len(result.get('errors', []))} 条")

    workbook = load_workbook(FAILFAST_WORKBOOK)
    sheet = workbook[report.report_sheet_title(schema)]
    written = "\n".join(str(sheet.cell(row, col).value or "")
                        for row in range(3, sheet.max_row + 1)
                        for col in range(1, 6))
    check("中文错误已回写「⑥ 检查结果」数据行",
          "刷新全局类缓存" in written and "模拟" in written, "含第 1 步失败信息")
    check("结果 JSON 记录未真实落盘说明",
          "未执行真实落盘" in (result.get("note") or ""), "含该说明")
    log()


def selfcheck_error_rows(schema):
    """增量二自检：结构化 errors.json 回写后「行 / 列」有值且正确；缺失时降级不崩溃。"""
    log("=" * 72)
    log("增量二自检：结构化 errors.json → 「⑥ 检查结果」的行 / 列定位；缺失时降级不崩溃")
    log("=" * 72)

    # 模拟 W3 read_workbook.py 写出的 errors.json（字段 sheet/row/col/message/text）
    payload = {
        "ok": False,
        "count": 2,
        "errors": [
            {"sheet": "② 技能卡", "row": 12, "col": "消耗数值",
             "message": "应填数字，实际填了『abc』",
             "text": "② 技能卡 第 12 行 · 消耗数值：应填数字，实际填了『abc』"},
            {"sheet": "③ 效果段", "row": 7, "col": "效果",
             "message": "填了『瞬移』，只能选 投掷物/近战挥砍/范围爆发/引导/召唤/位移/自我增益",
             "text": "③ 效果段 第 7 行 · 效果：填了『瞬移』，只能选 投掷物/近战挥砍/范围爆发/引导/召唤/位移/自我增益"},
        ],
        "warnings": [],
        "text": "② 技能卡 第 12 行 · 消耗数值：应填数字，实际填了『abc』",
    }
    MOCK_ERRORS_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    BROKEN_ERRORS_JSON.write_text("{ 这不是合法 JSON", encoding="utf-8")
    ZERO_ERRORS_JSON.write_text(
        json.dumps({"ok": True, "count": 0, "errors": [], "warnings": [], "text": ""},
                   ensure_ascii=False), encoding="utf-8")

    log("【模拟 errors.json（造在 finish/_tmp/，不碰 W3 共享目录）】")
    log(json.dumps(payload, ensure_ascii=False, indent=2))
    log()

    stdout_text = "校验未通过，共 1 处错误（未生成任何中间 JSON，未落盘）：降级文本不应被采用"
    structured = run_all.parse_validation_errors(stdout_text, MOCK_ERRORS_JSON)
    log(f"【parse_validation_errors 返回】{json.dumps(structured, ensure_ascii=False)}")
    log()
    check("优先读到 2 条结构化错误", len(structured) == 2, f"实测 {len(structured)} 条")
    check("有效 errors.json 时不降级到 stdout",
          "降级文本不应被采用" not in str(structured), "未采用 stdout 降级文本")
    check("sheet / row / col / message 完整映射成 report.py 字段",
          structured and structured[0] == {
              "sheet": "② 技能卡", "row": 12, "column": "消耗数值",
              "problem": "应填数字，实际填了『abc』",
              "fix": "请按提示修改后重跑一键收尾",
          }, f"实测 {structured[0] if structured else None}")
    check("第二条错误的 sheet / row / col 也完整",
          len(structured) > 1 and structured[1]["sheet"] == "③ 效果段"
          and structured[1]["row"] == 7 and structured[1]["column"] == "效果",
          f"实测 {structured[1] if len(structured) > 1 else None}")

    # 真正走一遍 report.py 回写，验证「行」「列」两列有值且正确
    report_title = report.report_sheet_title(schema)
    make_test_workbook(ERRORS_CHECK_WORKBOOK, schema)
    result = {
        "success": False, "phase": "失败",
        "summary": "W3 中文分层校验未通过，已停止后续步骤、未落盘。",
        "steps": [{"name": "W3 读表与中文分层校验 read_workbook.py", "ok": False,
                   "skipped": False, "exit_code": 1, "detail": "退出码 1"}],
        "errors": structured,
        "gate": None, "dry_run": False,
    }
    info = report.write_report(str(ERRORS_CHECK_WORKBOOK), result)
    workbook = load_workbook(ERRORS_CHECK_WORKBOOK)
    sheet = workbook[report_title]
    data_rows = []
    for row in range(3, sheet.max_row + 1):
        values = [sheet.cell(row, col).value for col in range(1, 6)]
        if any(value not in (None, "") for value in values):
            data_rows.append(values)
    log("【回写后的「⑥ 检查结果」数据行（页签 / 行 / 列 / 问题 / 怎么改）】")
    for values in data_rows:
        log(f"    {values}")
    log()
    log(f"【report.write_report 返回】{json.dumps(info, ensure_ascii=False)}")
    log()
    check("回写后「行」列有值且正确（第 12 行）",
          any(values[0] == "② 技能卡" and str(values[1]) == "12" for values in data_rows),
          "找到 ② 技能卡 / 12")
    check("回写后「列」列有值且正确（消耗数值）",
          any(values[0] == "② 技能卡" and values[2] == "消耗数值" for values in data_rows),
          "找到 ② 技能卡 / 消耗数值")
    check("回写后「问题」列取到 W3 的 message",
          any(values[3] == "应填数字，实际填了『abc』" for values in data_rows),
          "含 W3 原始 message")
    check("第二条错误回写后 页签 / 行 / 列 同样正确",
          any(values[0] == "③ 效果段" and str(values[1]) == "7"
              and values[2] == "效果" for values in data_rows),
          "找到 ③ 效果段 / 7 / 效果")
    check("只改数据行：表头行仍为原中文列头",
          [sheet.cell(2, col).value for col in range(1, 6)] == ["页签", "行", "列", "问题", "怎么改"],
          f"实测 {[sheet.cell(2, col).value for col in range(1, 6)]}")

    # 降级：文件不存在 / JSON 损坏 / 零错误状态，都不崩溃
    degrade_cases = [
        ("文件不存在", MISSING_ERRORS_JSON),
        ("JSON 损坏", BROKEN_ERRORS_JSON),
        ("零错误状态", ZERO_ERRORS_JSON),
    ]
    crashed = None
    degraded = {}
    try:
        for label, path in degrade_cases:
            degraded[label] = run_all.parse_validation_errors(stdout_text, path)
    except Exception as exc:  # 任何异常都算降级失败
        crashed = str(exc)
    log(f"【三种降级路径返回】{ {k: v for k, v in degraded.items()} }")
    log()
    check("errors.json 不存在 / 损坏 / 零错误时降级且不崩溃",
          crashed is None, f"异常={crashed}")
    check("三种降级均返回空清单（由编排的 failure_errors 兜底）",
          all(value == [] for value in degraded.values()) and len(degraded) == 3,
          f"实测 { {k: len(v) for k, v in degraded.items()} }")

    # 降级后仍能把中文兜底错误回写，不崩溃
    make_test_workbook(DEGRADE_CHECK_WORKBOOK, schema)
    fallback = run_all.failure_errors(run_all.build_steps(False)[4], 5, 1, stdout_text)
    degrade_result = {
        "success": False, "phase": "失败", "summary": "errors.json 缺失，已降级。",
        "steps": [{"name": "W3 读表与中文分层校验 read_workbook.py", "ok": False,
                   "skipped": False, "exit_code": 1, "detail": "退出码 1"}],
        "errors": degraded.get("文件不存在", []) + fallback,
        "gate": None, "dry_run": False,
    }
    write_ok = True
    try:
        report.write_report(str(DEGRADE_CHECK_WORKBOOK), degrade_result)
    except Exception as exc:
        write_ok = False
        log(f"    降级回写异常：{exc}")
    check("降级路径仍能回写「⑥ 检查结果」且不崩溃", write_ok, "回写成功")
    fallback_sheet = load_workbook(DEGRADE_CHECK_WORKBOOK)[report_title]
    fallback_text = "\n".join(str(fallback_sheet.cell(row, col).value or "")
                            for row in range(3, fallback_sheet.max_row + 1)
                            for col in range(1, 6))
    check("降级回写含中文兜底错误与修改建议",
          "未通过" in fallback_text and "修好后重跑" in fallback_text,
          "含兜底错误与「怎么改」建议")
    log()


def main():
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    log("W4 一键收尾 · 自检原始输出")
    log(f"Python：{sys.version.split()[0]}；openpyxl 已装载")
    log(f"自检产物目录：finish/_tmp/（隔离，不打开真实工作簿、不跑全量门禁、不落盘）")
    log()

    try:
        schema = report.load_schema()
        root = project_root()
        selfcheck_dry_run(root)
        selfcheck_report(schema)
        selfcheck_missing_deps()
        selfcheck_fail_fast(schema)
        selfcheck_error_rows(schema)
    except Exception as exc:
        log(f"[自检] 发生意外：{exc}")
        check("自检过程无异常", False, str(exc))

    passed = sum(1 for _, ok, _ in CHECKS if ok)
    total = len(CHECKS)
    log("=" * 72)
    log(f"自检汇总：{passed}/{total} 条通过")
    for label, ok, measured in CHECKS:
        log(f"    [{'通过' if ok else '未通过'}] {label}｜实测：{measured}")
    log("=" * 72)

    try:
        RAW_LOG.write_text("\n".join(RAW_LINES) + "\n", encoding="utf-8")
        print(f"[自检] 原始输出已保留：{RAW_LOG.name}")
    except OSError as exc:
        print(f"[自检] 原始输出写入失败：{exc}")

    print(f"[自检] 结论：{'全部通过' if passed == total else '存在未通过项'}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
