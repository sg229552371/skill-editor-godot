# -*- coding: utf-8 -*-
"""W4 · 一键收尾编排。

把「刷新类缓存 → 生成 → 重生成 API 地图 → 重生成数值快照 → 漂移检查
→ 全量门禁 → 结果回写工作簿」串成一条命令。

命令形态取自项目根《策划配置表工具_施工总任务书.md》§8；执行顺序按 W4 任务卡：
  1  刷新全局类缓存（第 1 次，P-08 类缓存坑）
  2  刷新全局类缓存（第 2 次）
  3  W2 export_to_json.gd          反向导出中间 JSON
  4  W2 build_workbook.py          仅首次建表，默认跳过（--rebuild-workbook 才执行）
  5  W3 read_workbook.py           读表 + 中文分层校验
  6  W3 build_from_json.gd         正向生成（按 W3 契约只写临时目录）
  7  gen_api_map.gd                重生成 API 地图
  8  gen_content_snapshot.gd       重生成数值快照
  9  git diff --exit-code ...       漂移检查
 10  全量 GUT 门禁                 并核对 Scripts=37 / 用例≥370 / 断言≥4716
 最后一步由 report.py 把中文结果回写「⑥ 检查结果」页签。

纪律：
- W2/W3 脚本按约定路径「只读调用」，本脚本绝不补写、绝不修改它们；
- 依赖脚本缺失时明确报「等待 W2/W3 交付」，不崩溃、不执行任何命令、不落盘；
- 任何一步失败立即停止，不继续后续步骤，不落盘，并把中文错误交给 report.py 回写；
- 本编排不做真实落盘（不写 content/gems/、不覆盖正式 .tres），
  全链集成与真实落盘由上级 AI 在 W5 统一执行；
- Godot 可执行文件由 --godot 或环境变量 GODOT_BIN / GODOT 传入，默认值留空，
  绝不把本机盘符绝对路径写死进脚本、文档或任何提交物；
- --dry-run 只打印命令序列，不执行任何命令。

集成参数（W4 增量，按 W2/W3 已交付脚本的真实签名逐条核对）：
- 只有 W3 的 read_workbook.py 需要 1 个必填位置参数：工作簿路径；
- W2 的 export_to_json.gd / build_workbook.py、W3 的 build_from_json.gd 均为零入参
  （build_from_json.gd 的 --input / --output 是可选项，默认值即可，不必传）；
- 不显式传 --out / --errors：read_workbook.py 的默认值落在
  content_workbench/_tmp/build_input.json 与 _tmp/errors.json，
  正好与 build_from_json.gd 的 DEFAULT_INPUT 严格对齐，改了反而会切断 A→B 契约；
- 全部入参集中在 Step.extra_args 一处，由 --workbook 解析出的「相对项目根」路径提供，
  不把本机盘符绝对路径写进命令与日志。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

FINISH_DIR = Path(__file__).resolve().parent
if str(FINISH_DIR) not in sys.path:
    sys.path.insert(0, str(FINISH_DIR))

import report  # noqa: E402  同目录的结果回写模块

TMP_DIR = FINISH_DIR / "_tmp"
DEFAULT_RESULT_JSON = TMP_DIR / "last_result.json"
RAW_OUTPUT_PATH = TMP_DIR / "run_all_raw_output.txt"

# ---------------------------------------------------------------------------
# 按约定路径调用 W2/W3（路径来自总任务书 §3 文件所有权地图）
# ---------------------------------------------------------------------------
W2_EXPORT_GD = "mods/jes-skills/tools/content_workbench/export/export_to_json.gd"
W2_BUILD_PY = "mods/jes-skills/tools/content_workbench/export/build_workbook.py"
W3_READ_PY = "mods/jes-skills/tools/content_workbench/build/read_workbook.py"
W3_BUILD_GD = "mods/jes-skills/tools/content_workbench/build/build_from_json.gd"
API_MAP_GD = "mods/jes-skills/tools/gen_api_map.gd"
SNAPSHOT_GD = "mods/jes-skills/tests/skills/gen_content_snapshot.gd"
GUT_CMDLN_GD = "addons/gut/gut_cmdln.gd"
DRIFT_TARGET = "mods/jes-skills/content/"

# 与冻结契约 schema.json 的 workbook 字段一致；运行时以 --workbook 解析结果为准
DEFAULT_WORKBOOK_REL = "mods/jes-skills/content_src/技能配置表.xlsx"
# W3 read_workbook.py 的结构化中文错误清单（只读，属 W3 目录，本脚本绝不写）
W3_ERRORS_REL = "mods/jes-skills/tools/content_workbench/_tmp/errors.json"

GODOT_BASE = ["--headless", "--path", "."]
GUT_ARGS = [
    "-s", "addons/gut/gut_cmdln.gd",
    "-gdir=res://mods/jes-skills/tests",
    "-ginclude_subdirs",
    "-gexit",
]

# 门禁基线（总任务书 §0 / §6 / §7：37 脚本、370 用例、4716 断言只升不降）
GATE_SCRIPTS_EXACT = 37
GATE_TESTS_MIN = 370
GATE_ASSERTS_MIN = 4716

EXE_DISPLAY = {"godot": "godot", "python": "python", "git": "git"}
ANSI_PATTERN = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
GUT_KEYS = (
    "Scripts", "Passing Tests", "Failing Tests", "Tests", "Asserts",
    "Errors", "Warnings", "Deprecated", "Orphans", "Time",
)


@dataclass
class Step:
    """一步外部命令。"""
    name: str
    kind: str                      # godot / python / git
    tail: list
    owner: str                     # W2 / W3 / 既有（用于依赖缺失提示）
    dep: str | None = None         # 需要先存在的依赖文件（相对项目根）
    optional: bool = False        # True = 默认跳过
    gate: bool = False             # True = 需要解析 GUT 汇总并核对指标
    extra_args: list = field(default_factory=list)  # W2/W3 脚本入参，一处集中配置


def build_steps(rebuild_workbook, workbook_arg=None):
    """按 W4 任务卡顺序构造步骤（命令形态严格照 §8，入参按 W2/W3 真实签名）。"""
    workbook_arg = workbook_arg or DEFAULT_WORKBOOK_REL
    return [
        Step("刷新全局类缓存（第 1 次，P-08）", "godot", GODOT_BASE + ["--import"], "项目既有"),
        Step("刷新全局类缓存（第 2 次，P-08）", "godot", GODOT_BASE + ["--import"], "项目既有"),
        Step("W2 反向导出 export_to_json.gd", "godot",
             GODOT_BASE + ["-s", "res://" + W2_EXPORT_GD], "W2", dep=W2_EXPORT_GD),
        Step("W2 首次建表 build_workbook.py", "python", [W2_BUILD_PY], "W2",
             dep=W2_BUILD_PY, optional=not rebuild_workbook),
        # 唯一需要入参的脚本：1 个必填位置参数（工作簿路径）；
        # --out / --errors / --schema / --snapshot 均用脚本默认值，不额外传。
        Step("W3 读表与中文分层校验 read_workbook.py", "python", [W3_READ_PY], "W3",
             dep=W3_READ_PY, extra_args=[workbook_arg]),
        Step("W3 正向生成 build_from_json.gd", "godot",
             GODOT_BASE + ["-s", "res://" + W3_BUILD_GD], "W3", dep=W3_BUILD_GD),
        Step("重生成 API 地图 gen_api_map.gd", "godot",
             GODOT_BASE + ["-s", "res://" + API_MAP_GD], "项目既有", dep=API_MAP_GD),
        Step("重生成数值快照 gen_content_snapshot.gd", "godot",
             GODOT_BASE + ["-s", "res://" + SNAPSHOT_GD], "项目既有", dep=SNAPSHOT_GD),
        Step("漂移检查 git diff --exit-code", "git",
             ["diff", "--exit-code", DRIFT_TARGET], "项目既有"),
        Step("全量 GUT 门禁", "godot", GODOT_BASE + GUT_ARGS, "项目既有",
             dep=GUT_CMDLN_GD, gate=True),
    ]


def display_command(step):
    """用于打印 / 核对的命令串：可执行名用通用占位，不含任何本机绝对路径。"""
    return " ".join([EXE_DISPLAY[step.kind]] + step.tail + step.extra_args)


def real_argv(step, godot_exe):
    """用于实际执行的命令：Godot 用调用方给的路径，Python 用当前解释器。"""
    exe = {"godot": godot_exe, "python": sys.executable, "git": "git"}[step.kind]
    return [exe] + step.tail + step.extra_args


def display_workbook_arg(workbook_path, project_root):
    """把 --workbook 解析出的路径规范成「相对项目根」形式。

    执行时 cwd=project_root，相对路径可被 W3 脚本正确解析；
    同时保证命令序列与日志里不出现本机盘符绝对路径。
    """
    path = Path(workbook_path)
    if project_root is not None:
        try:
            return path.resolve().relative_to(Path(project_root).resolve()).as_posix()
        except (ValueError, OSError):
            try:
                return os.path.relpath(path.resolve(),
                                      Path(project_root).resolve()).replace("\\", "/")
            except (ValueError, OSError):
                pass
    return path.as_posix()


# ---------------------------------------------------------------------------
# GUT 汇总解析（防「整份静默跳过造成假绿」）
# ---------------------------------------------------------------------------
def strip_ansi(text):
    return ANSI_PATTERN.sub("", text or "")


def parse_number(raw):
    """把 GUT 的 Totals 数字串转成整数；'none' 视为 0；'X/Y' 取总数 Y。"""
    if raw is None:
        return None
    raw = raw.strip()
    if raw in ("none", "None", "-"):
        return 0
    if "/" in raw:
        tail = raw.split("/")[-1].strip()
        return int(tail) if tail.isdigit() else None
    return int(raw) if raw.isdigit() else None


def parse_gut_totals(text):
    """解析 GUT 输出里的 Totals 区块。返回 (指标字典, 中文错误)。"""
    lines = strip_ansi(text).splitlines()
    start = None
    for index, line in enumerate(lines):
        if line.strip() == "Totals":
            start = index          # 取最后一个，避免前面出现同名文字
    if start is None:
        return None, "输出里没找到 GUT 的 Totals 汇总区块（可能是整份静默跳过）"

    found = {}
    for line in lines[start:]:
        for key in GUT_KEYS:
            match = re.match(r"^\s*" + re.escape(key) + r"\s+(\S+)\s*$", line)
            if match:
                found.setdefault(key, match.group(1))
                break

    missing = [key for key in ("Scripts", "Tests", "Asserts") if key not in found]
    if missing:
        return None, "Totals 区块缺少字段 " + "、".join(missing) + "（已读到：" + "、".join(found) + "）"

    return {
        "scripts": parse_number(found["Scripts"]),
        "tests": parse_number(found["Tests"]),
        "asserts": parse_number(found["Asserts"]),
        "failing_tests": parse_number(found.get("Failing Tests")),
        "errors": parse_number(found.get("Errors")),
        "raw": found,
    }, ""


def check_gate(metrics, exit_code, parse_error):
    """核对门禁；返回中文问题列表，空列表代表通过。"""
    problems = []
    if exit_code != 0:
        problems.append(f"GUT 退出码为 {exit_code}（应为 0）")
    if parse_error:
        problems.append(f"门禁结果解析失败：{parse_error}，按失败处理")
        return problems
    if metrics is None:
        problems.append("门禁结果解析失败：没有拿到汇总指标，按失败处理")
        return problems

    scripts, tests, asserts = metrics["scripts"], metrics["tests"], metrics["asserts"]
    if scripts is None or scripts != GATE_SCRIPTS_EXACT:
        problems.append(
            f"测试脚本数 Scripts = {scripts}，必须恰好 = {GATE_SCRIPTS_EXACT}"
            "（防 GUT 整份静默跳过造成假绿）")
    if tests is None or tests < GATE_TESTS_MIN:
        problems.append(f"用例数 = {tests}，要求 ≥ {GATE_TESTS_MIN}")
    if asserts is None or asserts < GATE_ASSERTS_MIN:
        problems.append(f"断言数 = {asserts}，要求 ≥ {GATE_ASSERTS_MIN}")
    if metrics.get("failing_tests"):
        problems.append(f"存在失败用例 {metrics['failing_tests']} 个")
    if metrics.get("errors"):
        problems.append(f"GUT 汇总里有 {metrics['errors']} 个错误")
    return problems


# ---------------------------------------------------------------------------
# W3 校验错误清单解析（优先结构化 errors.json，保证「页签 + 行 + 列」定位）
# ---------------------------------------------------------------------------
def map_w3_error(item):
    """把 W3 errors.json 的 sheet/row/col/message 映射成 report.py 的字段名。

    W3 写的是 col / message（另有组合文本 text）；report.py 期望 column / problem。
    """
    return {
        "sheet": item.get("sheet") or item.get("页签") or "未定位",
        "row": item.get("row") if item.get("row") not in (None, "") else "",
        "column": item.get("col") or item.get("column") or item.get("列") or "",
        "problem": (item.get("message") or item.get("problem")
                    or item.get("问题") or item.get("text") or ""),
        "fix": item.get("fix") or item.get("怎么改") or "请按提示修改后重跑一键收尾",
    }


def read_w3_errors(errors_path):
    """只读 W3 的结构化 errors.json；不存在 / 损坏 / 零错误时返回空列表以触发降级。

    以文件实际内容为准：W3 失败时可能删除旧 build_input.json，但 errors.json 会保留；
    文件不存在、JSON 损坏、字段缺失、errors 为空一律容错，不抛异常、不崩溃。
    """
    if not errors_path:
        return []
    path = Path(errors_path)
    if not path.is_file():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeError):
        return []
    if not isinstance(payload, dict):
        return []
    items = payload.get("errors")
    if not isinstance(items, list) or not items:
        return []
    mapped = [map_w3_error(item) for item in items if isinstance(item, dict)]
    return [item for item in mapped if item["sheet"] or item["problem"]]


def parse_validation_errors(text, errors_path=None):
    """抽取「页签 + 行 + 列 + 问题 + 怎么改」的中文错误清单。

    优先读 W3 的 _tmp/errors.json（结构化字段，带行 / 列定位）；
    文件不存在、解析失败、零错误时降级到 stdout 文本解析，全程不崩溃。

    errors_path 由编排传入：只在 W3 读表校验这一步传真实路径，其它步骤传 None，
    避免把上次 W3 校验失败残留的结构化错误误当成当前步骤的失败原因。
    自检可传入 finish/_tmp/ 下的模拟文件，不触碰 W3 的共享目录。
    """
    structured = read_w3_errors(errors_path)
    if structured:
        return structured

    # 降级：从 stdout 文本里解析 JSON 数组 / 对象（保持原有宽容解析）
    clean = strip_ansi(text)
    decoded = None
    try:
        decoded = json.loads(clean)
    except ValueError:
        match = re.search(r"\[[\s\S]*\]", clean)
        if match:
            try:
                decoded = json.loads(match.group(0))
            except ValueError:
                decoded = None
    if isinstance(decoded, dict):
        decoded = decoded.get("errors") or decoded.get("校验错误") or []
    if isinstance(decoded, list) and decoded:
        errors = [map_w3_error(item) for item in decoded if isinstance(item, dict)]
        if errors:
            return errors
    return []


def failure_errors(step, index, exit_code, output):
    """步骤失败时至少给出一条可回写的中文错误（含定位信息与怎么改）。"""
    tail = strip_ansi(output).strip().splitlines()
    brief = " / ".join(line.strip() for line in tail[-6:] if line.strip())
    if len(brief) > 800:
        brief = brief[-800:]
    return [{
        "sheet": f"【一键收尾】第 {index} 步",
        "row": "",
        "column": "",
        "problem": f"{step.name} 未通过（退出码 {exit_code}）。原始输出末尾：{brief or '（无输出）'}",
        "fix": ("已停止后续步骤、未落盘。请查看上方原始输出定位问题，"
                "修好后重跑一键收尾；若是 W2/W3 脚本报错，请转交对应子代理修复。"),
    }]


# ---------------------------------------------------------------------------
# 编排主体
# ---------------------------------------------------------------------------
def find_project_root():
    """上溯找含 project.godot 的目录，避免写死本机绝对路径。"""
    for parent in Path(__file__).resolve().parents:
        if (parent / "project.godot").is_file():
            return parent
    return None


def resolve_godot_exe(cli_value):
    """默认值留空，由调用方给；绝不内置任何盘符绝对路径。"""
    return cli_value or os.environ.get("GODOT_BIN") or os.environ.get("GODOT") or ""


def check_dependencies(project_root, workbook_path, steps):
    """返回缺失依赖清单 [(归属, 用途, 相对路径)]。"""
    missing = []
    for index, step in enumerate(steps, 1):
        if step.dep and not (project_root / step.dep).is_file():
            missing.append((step.owner, f"第 {index} 步 {step.name}", step.dep))
    if not workbook_path.is_file():
        missing.append(("W2", "结果回写「⑥ 检查结果」页签", "工作簿（由冻结契约指定）"))
    return missing


def print_dependency_status(project_root, workbook_path, steps):
    """空跑时只读显示依赖存在性：不执行命令、不阻断、不影响退出码。

    并行期依赖缺失时只如实标注，保证「自检不依赖 W2/W3 真的存在」仍然成立；
    W2/W3 交付后则明确显示「全部就位」，供集成核对。
    """
    print("[一键收尾 · 空跑] 依赖存在性检查（只读，不执行任何命令）：")
    if project_root is None:
        print("  未定位到项目根，跳过依赖检查（空跑不受影响）。")
        return
    total = sum(1 for step in steps if step.dep) + 1  # 末尾 +1 是工作簿
    missing = check_dependencies(project_root, workbook_path, steps)
    if missing:
        print(f"  依赖检查未全通过：{len(missing)}/{total} 项尚缺失（仅如实提示，空跑不阻断）：")
        for owner, usage, path in missing:
            print(f"    - 待交付 [{owner}] {usage}｜{path}")
        return
    print(f"  全部就位：{total}/{total} 项依赖均已落盘，依赖检查通过，无需等待交付。")
    for step in steps:
        if step.dep:
            print(f"    - 已就位 [{step.owner}] {step.dep}")
    print(f"    - 已就位 [W2] {display_workbook_arg(workbook_path, project_root)}")


def print_dry_run(steps, title):
    """只打印命令序列，不执行任何命令。"""
    print("[一键收尾 · 空跑] 只打印命令序列，不执行任何命令、不真实落盘。")
    print("[命令形态] 取自总任务书 §8；Godot 可执行文件由 --godot / 环境变量 GODOT_BIN 提供，空跑统一显示为 godot。")
    print("[执行顺序] 两次刷新类缓存 → W2 反向导出 / 建表 → W3 读表 / 生成 → API 地图 → 数值快照 → 漂移检查 → 全量门禁。")
    print()
    for index, step in enumerate(steps, 1):
        state = "跳过（默认不重建，避免覆盖策划已填内容；仅首次建表加 --rebuild-workbook）" \
            if step.optional else "执行"
        print(f"[{index:02d}] {step.name}")
        print(f"     状态：{state}")
        print(f"     命令：{display_command(step)}")
        if step.extra_args:
            print(f"     入参：{len(step.extra_args)} 个（{'、'.join(step.extra_args)}）")
        else:
            print("     入参：0 个（该脚本零入参）")
    print(f"[{len(steps) + 1:02d}] 结果回写 → 工作簿「{title}」页签（report.py，只写数据行，不改静态结构）")
    print()
    print("[入参说明] 仅第 5 步 read_workbook.py 需要 1 个必填位置参数（工作簿路径）；"
          "其余脚本零入参；--out / --errors 用脚本默认值（与 build_from_json.gd 默认输入对齐），不额外传。")
    print(f"[一键收尾 · 空跑] 共 {len(steps)} 条外部命令 + 1 步结果回写。"
          "其中第 4 步默认跳过；加 --rebuild-workbook 才执行。")


def append_raw_output(text):
    """保留每一步的原始输出，便于守门员追溯。"""
    try:
        TMP_DIR.mkdir(parents=True, exist_ok=True)
        with RAW_OUTPUT_PATH.open("a", encoding="utf-8") as handle:
            handle.write(text)
            if not text.endswith("\n"):
                handle.write("\n")
    except OSError:
        pass  # 日志写不进去不影响编排结论


def write_back(workbook_path, result):
    """把中文结果交给 report.py 回写；工作簿缺失或回写异常都不崩溃。"""
    if not workbook_path.is_file():
        print("[结果回写] 跳过：工作簿尚未由 W2 生成（等待 W2 交付），结果已保留在结果 JSON 中。")
        return False
    try:
        info = report.write_report(str(workbook_path), result)
    except Exception as exc:  # 不因回写异常而崩溃
        print(f"[结果回写] 失败：{exc}；结果已保留在结果 JSON 中。")
        return False
    print(f"[结果回写] 完成：页签「{info['sheet']}」，表头第 {info['header_row']} 行未改动，"
          f"写入 {info['rows_written']} 行数据；其它页签未改动。")
    return True


def finalize(result, result_json, workbook_path, do_report=True):
    """写结果 JSON、回写工作簿、打印中文总结。"""
    result["generated_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    try:
        result_json.parent.mkdir(parents=True, exist_ok=True)
        with result_json.open("w", encoding="utf-8") as handle:
            json.dump(result, handle, ensure_ascii=False, indent=2)
    except OSError as exc:
        print(f"[一键收尾] 结果 JSON 写入失败：{exc}（不影响回写）")
    if do_report:
        write_back(workbook_path, result)
    print()
    state_text = "成功" if result["success"] else "失败"
    phase_note = "" if result["phase"] == state_text else f"（{result['phase']}）"
    print(f"[一键收尾] 结论：{state_text}{phase_note}")
    print(f"[一键收尾] {result['summary']}")
    for item in result.get("errors", []):
        print(f"  - 页签：{item.get('sheet') or '未定位'}｜行：{item.get('row') or '—'}"
              f"｜列：{item.get('column') or '—'}｜问题：{item.get('problem')}"
              f"｜怎么改：{item.get('fix')}")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="W4 一键收尾：串起生成链、API 地图、数值快照、漂移检查、全量门禁与结果回写")
    parser.add_argument("--godot", default="",
                        help="Godot 4.7.1 控制台可执行文件路径；也可设环境变量 GODOT_BIN / GODOT。默认留空")
    parser.add_argument("--project-root", default=None,
                        help="项目根（含 project.godot）；默认自动上溯定位")
    parser.add_argument("--workbook", default=None,
                        help="工作簿路径；默认取冻结契约 schema.json 的 workbook 字段")
    parser.add_argument("--result-json", default=None,
                        help="结果 JSON 落点；默认 finish/_tmp/last_result.json")
    parser.add_argument("--rebuild-workbook", action="store_true",
                        help="执行 W2 的 build_workbook.py（仅首次建表时用；默认跳过，避免覆盖策划已填内容）")
    parser.add_argument("--dry-run", action="store_true",
                        help="只打印将执行的命令序列，不实际执行")
    parser.add_argument("--timeout", type=int, default=900,
                        help="单条命令超时秒数，默认 900")
    args = parser.parse_args(argv)

    try:
        schema = report.load_schema()
        title = report.report_sheet_title(schema)
        workbook_rel = schema["workbook"]
        project_root = Path(args.project_root).resolve() if args.project_root else find_project_root()
        if args.workbook:
            workbook_path = Path(args.workbook).resolve()
        elif project_root is not None:
            workbook_path = project_root / workbook_rel
        else:
            workbook_path = Path(workbook_rel)
        workbook_arg = display_workbook_arg(workbook_path, project_root)
        steps = build_steps(args.rebuild_workbook, workbook_arg)

        # --dry-run 必须能独立跑通：不需要 Godot，也不依赖 W2/W3 脚本是否存在。
        # 依赖状态只做只读显示，不阻断、不影响退出码，仍是「只打印、不执行」。
        if args.dry_run:
            print_dependency_status(project_root, workbook_path, steps)
            print()
            print_dry_run(steps, title)
            return 0

        if project_root is None:
            print("[一键收尾] 找不到项目根（含 project.godot 的目录），请用 --project-root 指定。")
            return 3
        result_json = Path(args.result_json).resolve() if args.result_json else DEFAULT_RESULT_JSON
        godot_exe = resolve_godot_exe(args.godot)

        result = {
            "success": False,
            "phase": "执行中",
            "summary": "",
            "steps": [],
            "errors": [],
            "gate": None,
            "commands": [display_command(step) for step in steps],
            "dry_run": False,
            "note": "本次未执行真实落盘（不写 content/gems/、不覆盖正式 .tres）；全链集成与真实落盘由 W5 统一执行。",
        }

        # 依赖性检查：缺失时优雅报「等待 W2/W3 交付」，不崩溃、不补写脚本、不执行任何命令
        missing = check_dependencies(project_root, workbook_path, steps)
        if missing:
            print("[一键收尾] 等待 W2/W3 交付：以下依赖按约定路径调用，目前尚不存在；"
                  "本脚本不自行补写它们的脚本。")
            for owner, usage, path in missing:
                print(f"  - [{owner}] {usage}｜{path}")
            print("[一键收尾] 未执行任何生成命令、未真实落盘；未继续后续步骤。")
            result["phase"] = "等待交付"
            result["summary"] = (f"等待 W2/W3 交付：缺 {len(missing)} 项依赖，"
                                 "已按约定路径检查，未执行任何命令、未落盘。")
            result["steps"] = [
                {"name": step.name, "ok": False, "skipped": False, "exit_code": None,
                 "detail": "未执行（依赖缺失，等待 W2/W3 交付）"}
                for step in steps
            ]
            result["errors"] = [{
                "sheet": "【一键收尾】依赖检查",
                "row": "",
                "column": "",
                "problem": f"[{owner}] 缺少依赖：{path}（{usage}）",
                "fix": "等待 W2/W3 交付脚本与工作簿后重跑一键收尾；本脚本不补写它们的脚本。",
            } for owner, usage, path in missing]
            finalize(result, result_json, workbook_path)
            return 2

        if not godot_exe:
            print("[一键收尾] 未提供 Godot 可执行文件：请用 --godot 传入，或设置环境变量 GODOT_BIN / GODOT；"
                  "本脚本不写死任何本机绝对路径。未执行任何命令、未落盘。")
            result["phase"] = "环境未就绪"
            result["summary"] = "缺少 Godot 可执行文件，未执行任何命令、未落盘。"
            result["errors"] = [{
                "sheet": "【一键收尾】环境检查", "row": "", "column": "",
                "problem": "未提供 Godot 可执行文件",
                "fix": "用 --godot 传入 Godot 4.7.1 控制台可执行文件路径，或设置环境变量 GODOT_BIN。",
            }]
            finalize(result, result_json, workbook_path)
            return 3

        print(f"[一键收尾] 开始：共 {len(steps)} 步外部命令 + 结果回写。"
              "本次不执行真实落盘（由 W5 统一执行）。")
        append_raw_output(f"\n===== 一键收尾 {datetime.now():%Y-%m-%d %H:%M:%S} =====\n")

        failed = False
        for index, step in enumerate(steps, 1):
            if failed:
                print(f"[{index:02d}/{len(steps)}] {step.name}：未执行（前序步骤失败，已立即停止）")
                result["steps"].append({
                    "name": step.name, "ok": False, "skipped": False, "exit_code": None,
                    "detail": "未执行（前序步骤失败，已立即停止）",
                })
                continue

            if step.optional:
                print(f"[{index:02d}/{len(steps)}] {step.name}：跳过（默认不重建表）")
                result["steps"].append({
                    "name": step.name, "ok": True, "skipped": True, "exit_code": 0,
                    "detail": "默认跳过，避免覆盖策划已填内容；仅首次建表加 --rebuild-workbook",
                })
                continue

            command = real_argv(step, godot_exe)
            print(f"[{index:02d}/{len(steps)}] {step.name}：执行中…  {display_command(step)}")
            try:
                proc = subprocess.run(
                    command, cwd=str(project_root), capture_output=True,
                    text=True, encoding="utf-8", errors="replace",
                    timeout=args.timeout,
                )
                output = (proc.stdout or "") + (proc.stderr or "")
                exit_code = proc.returncode
            except subprocess.TimeoutExpired:
                output = f"命令超时（{args.timeout} 秒）"
                exit_code = -1
            except OSError as exc:
                output = f"命令无法启动：{exc}"
                exit_code = -1

            append_raw_output(f"\n----- 第 {index} 步 {step.name}（退出码 {exit_code}）-----\n{output}\n")

            step_errors = []
            detail = f"退出码 {exit_code}"
            if exit_code != 0:
                failed = True
                if step.name.startswith("漂移检查"):
                    detail = (f"退出码 {exit_code}：{DRIFT_TARGET} 存在漂移（可能有人手工改过正式资源或生成产物），"
                              "本次不落盘；请核对差异后再生成")
                    step_errors.append({
                        "sheet": "【一键收尾】漂移检查", "row": "", "column": "",
                        "problem": detail,
                        "fix": "用 git diff 查看 content/ 下的差异，确认是手工误改还是生成结果不一致；修好后重跑一键收尾。",
                    })
                else:
                    # 只在 W3 读表校验这一步读结构化 errors.json（带行 / 列定位）；
                    # 其它步骤传 None，避免把上次 W3 失败残留误当成当前失败原因。
                    errors_path = (project_root / W3_ERRORS_REL) \
                        if step.dep == W3_READ_PY else None
                    step_errors = parse_validation_errors(output, errors_path)
                    step_errors += failure_errors(step, index, exit_code, output)
            elif step.gate:
                metrics, parse_error = parse_gut_totals(output)
                problems = check_gate(metrics, exit_code, parse_error)
                if metrics:
                    result["gate"] = {
                        "scripts": metrics["scripts"], "tests": metrics["tests"],
                        "asserts": metrics["asserts"], "raw": metrics["raw"],
                    }
                    detail = (f"退出码 {exit_code}；解析到 测试脚本 {metrics['scripts']} / "
                              f"用例 {metrics['tests']} / 断言 {metrics['asserts']}")
                if problems:
                    failed = True
                    detail += "；门禁核对未通过：" + "；".join(problems)
                    step_errors.append({
                        "sheet": "【一键收尾】全量门禁", "row": "", "column": "",
                        "problem": "；".join(problems),
                        "fix": ("禁止放宽或删除任何既有测试。先确认 GUT 是否整份静默跳过（Scripts 必须 = 37），"
                                "再按红项修数据或修工具，复跑全量门禁。"),
                    })
                else:
                    detail += "；Scripts = 37、用例 ≥ 370、断言 ≥ 4716 全部满足"

            result["steps"].append({
                "name": step.name, "ok": not failed, "skipped": False,
                "exit_code": exit_code, "detail": detail,
                "output": strip_ansi(output)[-20000:],
            })
            if failed:
                result["errors"] = step_errors
                print(f"[{index:02d}/{len(steps)}] {step.name}：失败。{detail}")
                print("[一键收尾] 已立即停止，不继续后续步骤、不落盘；中文错误将回写工作簿。")
            else:
                print(f"[{index:02d}/{len(steps)}] {step.name}：通过。{detail}")

        result["success"] = not failed
        result["phase"] = "完成" if not failed else "失败"
        result["summary"] = (
            "全链通过，门禁全绿且 Scripts = 37、用例 ≥ 370、断言 ≥ 4716；本次未执行真实落盘（由 W5 统一执行）。"
            if not failed else
            "某一步失败后已立即停止，未继续后续步骤、未落盘；请按下方错误清单处理后重跑。"
        )
        finalize(result, result_json, workbook_path)
        return 0 if not failed else 1

    except Exception as exc:  # 顶层兜底：任何意外都给中文提示，不向用户抛英文栈
        print(f"[一键收尾] 发生意外，已安全停止：{exc}（未落盘）")
        return 1


if __name__ == "__main__":
    sys.exit(main())
