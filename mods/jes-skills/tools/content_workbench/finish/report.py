# -*- coding: utf-8 -*-
"""W4 一键收尾 · 中文结果回写。

职责：把一键收尾的结果（整体成功/失败、每一步结论、错误清单
「页签 + 行 + 列 + 问题 + 怎么改」）写进工作簿「⑥ 检查结果」页签。

边界（严禁越界）：
- 只写「⑥ 检查结果」这一个页签，且只写表头行以下的数据行；
- 不改页签名单、不改列头、不改说明文字、不改示例行、不改其它页签；
- 通过冻结契约 schema.json 拿页签标题，schema.json 只读，绝不修改；
- 自检一律用 finish/_tmp/ 下的测试工作簿，不打开真实工作簿。

页签表头由 W2 负责。本模块按中文语义识别列（页签/行/列/问题/怎么改），
识别不到的语义按固定顺序占用表头里尚未被占用的列；绝不新建列。
约定：该页签「表头行以下」为结果数据区，重跑时整段覆盖，避免残留旧结果。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from openpyxl import load_workbook

FINISH_DIR = Path(__file__).resolve().parent
# 冻结契约：只读，仅用于取页签标题与工作簿相对路径
SCHEMA_PATH = FINISH_DIR.parent / "schema.json"

# 中文表头语义 → 识别关键词。表头列名全中文，不塞英文标识符。
COLUMN_HINTS = {
    "sheet": ("页签", "表页", "工作表"),
    "row": ("行号", "行"),
    "column": ("列名", "列"),
    "problem": ("问题", "原因", "错误", "结论", "说明"),
    "fix": ("怎么改", "修改建议", "建议", "处理", "办法", "对策"),
}
# 表头无法按语义识别时的兜底列序
FALLBACK_ORDER = ("sheet", "row", "column", "problem", "fix")

# 数据行的分类标签（写在「页签」列，用于区分汇总行与字段错误行）
TAG_RESULT = "【一键收尾】整体结果"
TAG_STEP = "【一键收尾】第 {index} 步"
TAG_GATE = "【一键收尾】门禁核对"
TAG_CHECK = "【一键收尾】字段校验"


class ReportError(Exception):
    """中文错误。交给调用方打印，不向用户抛英文栈。"""


def load_schema():
    """读取冻结契约（只读）。"""
    if not SCHEMA_PATH.is_file():
        raise ReportError(f"找不到冻结契约 {SCHEMA_PATH.name}，无法确认「检查结果」页签标题")
    with SCHEMA_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def report_sheet_title(schema):
    """从冻结契约里取 key=report 的页签标题（⑥ 检查结果）。"""
    for item in schema.get("sheets", []):
        if item.get("key") == "report":
            return item["title"]
    raise ReportError("冻结契约里没有 key=report 的页签定义，无法定位「检查结果」页签")


def find_report_sheet(workbook, title):
    """定位页签；找不到时报中文错误，绝不新建页签。"""
    if title in workbook.sheetnames:
        return workbook[title]
    for name in workbook.sheetnames:
        if "检查结果" in str(name):
            return workbook[name]
    existing = "、".join(str(name) for name in workbook.sheetnames)
    raise ReportError(f"工作簿里没有「{title}」页签（现有页签：{existing}），请先由 W2 建表")


def find_header_row(sheet):
    """在前 10 行里找表头行；找不到则按第 1 行处理。

    兼容 W2 把说明文字放在表头行上方的情况：说明行不会被当成数据区。
    """
    for row in range(1, min(10, sheet.max_row) + 1):
        texts = [str(sheet.cell(row, col).value or "").strip()
                 for col in range(1, sheet.max_column + 1)]
        joined = "".join(texts)
        if "页签" in joined or ("问题" in joined and "列" in joined):
            return row
    return 1


def map_columns(sheet, header_row):
    """返回 {语义: 列号}。只使用表头行已存在的列，绝不新建列。"""
    headers = {}
    for col in range(1, sheet.max_column + 1):
        value = sheet.cell(header_row, col).value
        headers[col] = str(value).strip() if value is not None else ""

    mapping = {}
    for key, hints in COLUMN_HINTS.items():
        for col, text in headers.items():
            if text and any(hint in text for hint in hints):
                mapping[key] = col
                break

    # 兜底：按固定顺序占用表头里尚未被占用的列（仍在已有列范围内）
    used = set(mapping.values())
    for key in FALLBACK_ORDER:
        if key in mapping:
            continue
        for col in range(1, sheet.max_column + 1):
            if col not in used:
                mapping[key] = col
                used.add(col)
                break
    return mapping


def build_rows(result):
    """把结果对象翻译成若干「中文数据行」，每行是 {语义: 值}。"""
    success = bool(result.get("success"))
    phase = result.get("phase") or ("完成" if success else "失败")
    summary = result.get("summary") or ""
    rows = [{
        "sheet": TAG_RESULT,
        "row": "",
        "column": "",
        "problem": f"整体结果：{'成功' if success else '失败'}｜阶段：{phase}｜{summary}",
        "fix": "全部通过，无需处理" if success else "按下方「问题 / 怎么改」逐条处理后再运行一键收尾",
    }]

    for index, step in enumerate(result.get("steps", []), 1):
        if step.get("skipped"):
            state = "跳过"
        elif step.get("ok"):
            state = "通过"
        else:
            state = "失败"
        code = step.get("exit_code")
        code_text = "" if code is None else f"（退出码 {code}）"
        detail = step.get("detail") or ""
        rows.append({
            "sheet": TAG_STEP.format(index=index),
            "row": "",
            "column": "",
            "problem": f"{step.get('name', '')}：{state}{code_text}{detail}",
            "fix": "" if state != "失败" else "请查看该步骤的原始输出，修好后重跑一键收尾",
        })

    gate = result.get("gate")
    if gate:
        rows.append({
            "sheet": TAG_GATE,
            "row": "",
            "column": "",
            "problem": "测试脚本 {} / 用例 {} / 断言 {}".format(
                gate.get("scripts"), gate.get("tests"), gate.get("asserts")),
            "fix": "要求：测试脚本必须 = 37（防整份静默跳过造成假绿），用例 ≥ 370，断言 ≥ 4716",
        })

    errors = result.get("errors", [])
    if errors:
        for item in errors:
            rows.append({
                "sheet": item.get("sheet") or "未定位",
                "row": "" if item.get("row") in (None, "") else item.get("row"),
                "column": item.get("column") or "",
                "problem": item.get("problem") or "",
                "fix": item.get("fix") or "请按提示修改后重跑一键收尾",
            })
    else:
        rows.append({
            "sheet": TAG_CHECK,
            "row": "",
            "column": "",
            "problem": "无字段错误",
            "fix": "无需处理",
        })
    return rows


def write_report(workbook_path, result):
    """把中文结果写回「⑥ 检查结果」页签的数据行。

    只动该页签表头行以下的单元格值；不动表头行、不动样式、
    不动合并单元格、不动下拉、不动其它任何页签。
    """
    schema = load_schema()
    title = report_sheet_title(schema)
    path = Path(workbook_path)
    if not path.is_file():
        raise ReportError("工作簿不存在，请先由 W2 生成（等待 W2 交付）："
                          + str(schema.get("workbook", "技能配置表.xlsx")))

    workbook = load_workbook(path)
    sheet = find_report_sheet(workbook, title)
    header_row = find_header_row(sheet)
    mapping = map_columns(sheet, header_row)
    if not mapping:
        raise ReportError(f"「{title}」页签没有可用的数据列，请先由 W2 建表")

    max_col = sheet.max_column
    writable = {key: col for key, col in mapping.items() if col <= max_col}

    # 清空「表头行以下、本工具会写的列」的旧值，避免上次结果残留。
    # 只清单元格的值：不删除行、不改列宽/样式/合并单元格/下拉。
    for row in range(header_row + 1, sheet.max_row + 1):
        for col in writable.values():
            sheet.cell(row, col).value = None

    rows = build_rows(result)
    for offset, row_data in enumerate(rows):
        target_row = header_row + 1 + offset
        for key, col in writable.items():
            sheet.cell(target_row, col).value = row_data.get(key, "")

    # 放不下的语义（列数不足时）合并进「问题」列，绝不新建列
    missing_keys = [key for key in FALLBACK_ORDER if key not in writable]
    if missing_keys and "problem" in writable:
        for offset, row_data in enumerate(rows):
            extra = "；".join(f"{key}：{row_data.get(key, '')}"
                             for key in missing_keys if row_data.get(key, "") not in (None, ""))
            if extra:
                cell = sheet.cell(header_row + 1 + offset, writable["problem"])
                cell.value = f"{cell.value or ''}｜{extra}"

    workbook.save(path)
    return {
        "sheet": title,
        "header_row": header_row,
        "rows_written": len(rows),
        "columns": {key: col for key, col in sorted(writable.items())},
    }


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="把一键收尾的中文结果写回工作簿「⑥ 检查结果」页签（只写数据行）")
    parser.add_argument("--workbook", required=True,
                        help="工作簿路径；自检时用 finish/_tmp/ 下的测试工作簿")
    parser.add_argument("--result", required=True,
                        help="结果 JSON 文件路径")
    args = parser.parse_args(argv)

    try:
        with open(args.result, "r", encoding="utf-8") as handle:
            result = json.load(handle)
        info = write_report(args.workbook, result)
    except (ReportError, OSError, ValueError, KeyError) as exc:
        print(f"[结果回写] 失败：{exc}")
        return 1

    columns = "、".join(f"{key}={col}" for key, col in info["columns"].items())
    print(f"[结果回写] 完成：页签「{info['sheet']}」，表头第 {info['header_row']} 行保持不动，"
          f"写入 {info['rows_written']} 行数据；列映射 {columns}；其它页签未改动。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
