# -*- coding: utf-8 -*-
"""P5 · 落盘工具：把生成目录里的 80 个 .tres 事务式落到正式内容目录。

用法（在项目根或任意目录执行均可，脚本按 __file__ 上溯定位项目根）：
  python mods/jes-skills/tools/content_workbench/finish/apply.py            # 空跑（默认）
  python mods/jes-skills/tools/content_workbench/finish/apply.py --apply    # 真实写盘

设计要点（对应二期任务书 P5）：
- 默认空跑：按字节比对现有内容，只打印「新增 / 会改动 / 不变」三类清单，退出码 0，
  保证一个字节都不写。
- --apply 才写：逐文件先写临时副本并校验，对已存在的目标先做备份，再原子替换；
  任一步失败按逆序回滚（已覆盖的恢复原样、本次新建的删除），不留半写状态。
- 只写 .tres；.gdkeep 等非 .tres 文件一律不碰；正常写盘路径不删除任何既有文件。
- 前置守卫任一不满足即中文报错、退出 1，且不创建任何文件：
  dryrun 不是恰好 80 个 .tres / 缺 export.json / 代号与文件名非法 /
  归属类别数量不是 67 主动 + 13 辅助 / 内容目录不存在 / 目标位置被目录占用。
- 输出一律使用「相对项目根」或 res:// 形态，不把本机绝对路径写进脚本、输出或文档。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import time
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

# 中文输出在部分 Windows 控制台可能遇到不可编码字符：降级为替换，不因打印失败而崩。
try:
    sys.stdout.reconfigure(errors="replace")
    sys.stderr.reconfigure(errors="replace")
except (AttributeError, ValueError):
    pass

# 全部默认路径均相对项目根，不写死任何本机盘符绝对路径。
WORKBENCH_REL = Path("mods/jes-skills/tools/content_workbench")
DEFAULT_DRYRUN_REL = WORKBENCH_REL / "_tmp" / "dryrun"
DEFAULT_EXPORT_REL = WORKBENCH_REL / "_tmp" / "export.json"
DEFAULT_CONTENT_REL = Path("mods/jes-skills/content/gems")

SKILL_COUNT = 67
SUPPORT_COUNT = 13
EXPECTED_TOTAL = SKILL_COUNT + SUPPORT_COUNT

NAME_PATTERN = re.compile(r"^[a-z][a-z0-9_]*\.tres$")
ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")
ABS_PATH_PATTERN = re.compile(r"[A-Za-z]:[\\/][^\s，。；、）]*")

KIND_NEW = "新增"
KIND_CHANGED = "会改动"
KIND_SAME = "不变"
KINDS = (KIND_NEW, KIND_CHANGED, KIND_SAME)


@dataclass(frozen=True)
class Category:
    """一类内容的归属规则。"""

    key: str          # export.json 里的列表名
    id_key: str       # 列表项里的代号字段
    dir_name: str     # content/gems 下的子目录
    label: str        # 中文类别名
    expected: int     # 类别数量硬断言（二期基线 67 / 13）


CATEGORIES = (
    Category("skills", "gem_id", "active", "主动技能", SKILL_COUNT),
    Category("supports", "support_id", "supports", "辅助石", SUPPORT_COUNT),
)
CATEGORY_BY_KEY = {category.key: category for category in CATEGORIES}
CATEGORY_BY_DIR = {category.dir_name: category for category in CATEGORIES}


class GuardError(Exception):
    """前置守卫未通过：中文提示、退出码 1、不落盘。"""


@dataclass
class Layout:
    """本次运行使用的目录布局（内部为绝对路径，打印时统一转相对路径）。"""

    project_root: Path
    dryrun: Path
    export_json: Path
    content_root: Path


@dataclass
class Entry:
    """一个待落盘的资源。"""

    name: str
    resource_id: str
    category: Category
    data: bytes
    target: Path


@dataclass
class Action:
    """一个文件的三态判定结果。"""

    entry: Entry
    kind: str
    old_bytes: bytes | None


# ---------------------------------------------------------------------------
# 路径与中文输出
# ---------------------------------------------------------------------------
def find_project_root(start: Path | None = None) -> Path | None:
    """从脚本位置向上找含 project.godot 的目录；找不到返回 None。"""
    start = Path(start or Path(__file__).resolve().parent).resolve()
    for candidate in (start, *start.parents):
        if (candidate / "project.godot").is_file():
            return candidate
    return None


def display_path(path: Path, project_root: Path | None) -> str:
    """显示路径：优先相对项目根，项目外只给带标签的文件名，绝不打印绝对路径。"""
    path = Path(path)
    if project_root is not None:
        try:
            return path.resolve().relative_to(Path(project_root).resolve()).as_posix()
        except (ValueError, OSError):
            pass
    return "<项目外>/" + path.name


def sanitize(value, project_root: Path | None = None) -> str:
    """把异常文本里的本机绝对路径替换成占位符，避免日志泄漏。"""
    text = str(value)
    if project_root is not None:
        try:
            root_text = str(Path(project_root).resolve())
            text = text.replace(root_text, "<项目根>")
            text = text.replace(root_text.replace("\\", "/"), "<项目根>")
        except OSError:
            pass
    return ABS_PATH_PATTERN.sub("<路径>", text)


def resolve_layout(args) -> Layout:
    """解析项目根与三个目录；默认值全部相对项目根。"""
    if args.project_root:
        root = Path(args.project_root).expanduser()
        if not root.is_dir():
            raise GuardError("项目根不存在，请检查 --project-root 指向的目录")
        root = root.resolve()
    else:
        root = find_project_root()
        if root is None:
            raise GuardError("找不到项目根（含 project.godot 的目录），请在项目根执行或用 --project-root 指定")
    dryrun = Path(args.dryrun).expanduser().resolve() if args.dryrun else (root / DEFAULT_DRYRUN_REL)
    export_json = Path(args.export_json).expanduser().resolve() if args.export_json else (root / DEFAULT_EXPORT_REL)
    content_root = Path(args.content).expanduser().resolve() if args.content else (root / DEFAULT_CONTENT_REL)
    return Layout(root, dryrun, export_json, content_root)


# ---------------------------------------------------------------------------
# 前置守卫
# ---------------------------------------------------------------------------
def collect_dryrun_files(layout: Layout) -> list[Path]:
    """守卫：dryrun 目录里必须恰好是 80 个合法命名的 .tres。"""
    dryrun = layout.dryrun
    if not dryrun.exists():
        raise GuardError(f"dryrun 目录不存在：{display_path(dryrun, layout.project_root)}（请先跑 W3 正向生成）")
    if not dryrun.is_dir():
        raise GuardError(f"dryrun 不是目录：{display_path(dryrun, layout.project_root)}")

    items = list(dryrun.iterdir())
    bad_items = sorted(
        item.name + ("/" if item.is_dir() else "")
        for item in items
        if item.is_dir() or not item.name.endswith(".tres")
    )
    if bad_items:
        preview = "、".join(bad_items[:8]) + ("……" if len(bad_items) > 8 else "")
        raise GuardError(
            f"dryrun 出现非法文件或目录：{preview}（只允许 80 个 .tres，不允许子目录/其它扩展名，不落盘）")

    files = sorted((item for item in items if item.is_file()), key=lambda item: item.name)
    if len(files) != EXPECTED_TOTAL:
        raise GuardError(
            f"dryrun 文件数 = {len(files)}，要求恰好 {EXPECTED_TOTAL} 个 .tres（不落盘）")
    for file_path in files:
        if not NAME_PATTERN.match(file_path.name):
            raise GuardError(
                f"dryrun 出现非法文件名：{file_path.name}"
                "（只允许小写字母 / 数字 / 下划线 + .tres，不落盘）")
    return files


def load_export(layout: Layout) -> tuple[dict[str, list[str]], dict[str, str]]:
    """守卫：export.json 必须存在、可解析，且归属类别恰好 67 主动 + 13 辅助。"""
    path = layout.export_json
    if not path.is_file():
        raise GuardError(
            f"缺少 export.json：{display_path(path, layout.project_root)}（请先跑 W2 反向导出，不落盘）")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError) as exc:
        raise GuardError(
            f"export.json 读取失败：{sanitize(exc, layout.project_root)}（不落盘）") from exc
    except ValueError as exc:
        raise GuardError(
            f"export.json 不是合法 JSON：{sanitize(exc, layout.project_root)}（不落盘）") from exc
    if not isinstance(payload, dict):
        raise GuardError("export.json 顶层必须是对象（不落盘）")

    ids_by_category: dict[str, list[str]] = {}
    for category in CATEGORIES:
        items = payload.get(category.key)
        if not isinstance(items, list):
            raise GuardError(f"export.json 缺少 {category.key} 列表（不落盘）")
        ids: list[str] = []
        for index, item in enumerate(items):
            if not isinstance(item, dict):
                raise GuardError(f"export.json 的 {category.key} 第 {index + 1} 项不是对象（不落盘）")
            resource_id = item.get(category.id_key)
            if not isinstance(resource_id, str) or not ID_PATTERN.match(resource_id):
                raise GuardError(
                    f"export.json 的 {category.key} 第 {index + 1} 项代号非法：{resource_id!r}"
                    "（只允许小写字母 / 数字 / 下划线，不落盘）")
            ids.append(resource_id)
        if len(set(ids)) != len(ids):
            duplicates = sorted({item for item in ids if ids.count(item) > 1})
            raise GuardError(f"export.json 的 {category.key} 代号重复：{'、'.join(duplicates)}（不落盘）")
        ids_by_category[category.key] = ids

    actual_skills = len(ids_by_category["skills"])
    actual_supports = len(ids_by_category["supports"])
    if actual_skills != SKILL_COUNT or actual_supports != SUPPORT_COUNT:
        raise GuardError(
            f"export.json 类别数量 = 主动技能 {actual_skills} 个 / 辅助石 {actual_supports} 个，"
            f"要求 {SKILL_COUNT} / {SUPPORT_COUNT}（不落盘）")

    source_files = payload.get("source_files")
    if not isinstance(source_files, dict):
        raise GuardError("export.json 缺少 source_files 映射（不落盘）")

    id_to_file: dict[str, str] = {}
    for category in CATEGORIES:
        for resource_id in ids_by_category[category.key]:
            if resource_id not in source_files:
                raise GuardError(f"export.json 的 source_files 缺少代号 {resource_id}（不落盘）")
            file_name = source_files[resource_id]
            if not isinstance(file_name, str) or not NAME_PATTERN.match(file_name):
                raise GuardError(f"export.json 的 source_files 文件名非法：{resource_id} → {file_name!r}（不落盘）")
            if file_name != resource_id + ".tres":
                raise GuardError(
                    f"代号与文件名不一致：{resource_id} → {file_name}"
                    "（规则：文件名 = 代号 + .tres，不落盘）")
            id_to_file[resource_id] = file_name

    known_ids = set(id_to_file)
    extra_ids = sorted(set(source_files) - known_ids)
    if extra_ids:
        raise GuardError(f"export.json 的 source_files 含无法归属的代号：{'、'.join(extra_ids)}（不落盘）")
    return ids_by_category, id_to_file


def pair_entries(layout: Layout, files: list[Path],
                 ids_by_category: dict[str, list[str]],
                 id_to_file: dict[str, str]) -> list[Entry]:
    """把 dryrun 文件与 export.json 的代号/类别一一配对。"""
    file_to_id = {file_name: resource_id for resource_id, file_name in id_to_file.items()}
    dryrun_names = [file_path.name for file_path in files]
    expected_names = set(id_to_file.values())

    missing = sorted(expected_names - set(dryrun_names))
    extra = sorted(set(dryrun_names) - expected_names)
    if missing or extra:
        detail = []
        if missing:
            detail.append("缺少 " + "、".join(missing[:6]) + ("……" if len(missing) > 6 else ""))
        if extra:
            detail.append("多出 " + "、".join(extra[:6]) + ("……" if len(extra) > 6 else ""))
        raise GuardError(f"dryrun 与 export.json 不一致：{'；'.join(detail)}（不落盘）")

    id_to_category: dict[str, Category] = {}
    for category in CATEGORIES:
        for resource_id in ids_by_category[category.key]:
            id_to_category[resource_id] = category

    entries: list[Entry] = []
    for file_path in files:
        resource_id = file_to_id[file_path.name]
        category = id_to_category[resource_id]
        try:
            data = file_path.read_bytes()
        except OSError as exc:
            raise GuardError(
                f"读取 dryrun 文件失败：{file_path.name}（{sanitize(exc, layout.project_root)}，不落盘）") from exc
        entries.append(Entry(
            name=file_path.name,
            resource_id=resource_id,
            category=category,
            data=data,
            target=layout.content_root / category.dir_name / file_path.name,
        ))
    return entries


def validate_targets(layout: Layout, entries: list[Entry]) -> None:
    """守卫：内容目录存在；目标位置不能被目录占用。"""
    content_root = layout.content_root
    if not content_root.exists():
        raise GuardError(
            f"内容目录不存在：{display_path(content_root, layout.project_root)}（不落盘）")
    if not content_root.is_dir():
        raise GuardError(
            f"内容目录不是文件夹：{display_path(content_root, layout.project_root)}（不落盘）")

    for category in CATEGORIES:
        target_dir = content_root / category.dir_name
        if target_dir.exists() and not target_dir.is_dir():
            raise GuardError(
                f"内容类别目录被文件占用：{display_path(target_dir, layout.project_root)}（不落盘）")

    for entry in entries:
        if entry.target.is_dir():
            raise GuardError(
                f"目标位置被目录占用：{display_path(entry.target, layout.project_root)}（不落盘）")

    # 内容目录与预期类别不符：同一个 dryrun 文件若已落在另一类别目录，直接拒绝写盘。
    for entry in entries:
        for category in CATEGORIES:
            if category.dir_name == entry.category.dir_name:
                continue
            misplaced = content_root / category.dir_name / entry.name
            if misplaced.is_file():
                raise GuardError(
                    f"内容目录与预期类别不符：{display_path(misplaced, layout.project_root)}"
                    f" 应位于 {entry.category.dir_name} 目录（不落盘）")


def build_plan(entries: list[Entry]) -> list[Action]:
    """按字节比对给出「新增 / 会改动 / 不变」三类判定。"""
    actions: list[Action] = []
    for entry in entries:
        if not entry.target.exists():
            actions.append(Action(entry, KIND_NEW, None))
            continue
        old_bytes = entry.target.read_bytes()
        kind = KIND_SAME if old_bytes == entry.data else KIND_CHANGED
        actions.append(Action(entry, kind, old_bytes))
    return actions


# ---------------------------------------------------------------------------
# 空跑输出
# ---------------------------------------------------------------------------
def print_guard_ok(layout: Layout, entries: list[Entry]) -> None:
    counts = {category.key: 0 for category in CATEGORIES}
    for entry in entries:
        counts[entry.category.key] += 1
    print("[前置守卫] 通过：")
    print(f"  - dryrun：{display_path(layout.dryrun, layout.project_root)}（{len(entries)} 个 .tres）")
    print(f"  - export.json：{display_path(layout.export_json, layout.project_root)}"
          f"（主动技能 {counts['skills']} 个 / 辅助石 {counts['supports']} 个）")
    print(f"  - 内容目录：{display_path(layout.content_root, layout.project_root)}")


def print_plan(actions: list[Action], project_root: Path) -> None:
    counts = {category.key: 0 for category in CATEGORIES}
    for action in actions:
        counts[action.entry.category.key] += 1
    print(f"[归属] 主动技能 {counts['skills']} 个 → content/gems/active；"
          f"辅助石 {counts['supports']} 个 → content/gems/supports")
    for kind in KINDS:
        subset = [action for action in actions if action.kind == kind]
        print(f"[{kind}] {len(subset)} 个")
        if not subset:
            print("  （无）")
            continue
        for action in subset:
            entry = action.entry
            target_display = display_path(entry.target, project_root)
            if kind == KIND_NEW:
                detail = f"新建，{len(entry.data)} B"
            elif kind == KIND_CHANGED:
                detail = f"{len(action.old_bytes or b'')} B → {len(entry.data)} B"
            else:
                detail = "字节完全一致"
            print(f"  - {target_display}（{detail}）")


def print_summary(actions: list[Action]) -> None:
    counts = {kind: sum(1 for action in actions if action.kind == kind) for kind in KINDS}
    print(f"[汇总] 新增 {counts[KIND_NEW]} 个｜会改动 {counts[KIND_CHANGED]} 个｜"
          f"不变 {counts[KIND_SAME]} 个（共 {len(actions)} 个）")


# ---------------------------------------------------------------------------
# 真实写盘（事务 + 回滚）
# ---------------------------------------------------------------------------
def replace_with_retry(src: Path, dst: Path, attempts: int = 10, base_delay: float = 0.3) -> None:
    """带瞬态锁重试的原子替换。

    Windows 上杀毒实时扫描 / 索引器 / 文件观察进程可能短暂占用目标文件，
    使 os.replace 偶发 WinError 5（拒绝访问）或 32（共享冲突）；这类占用
    通常几百毫秒内释放，逐次退避重试即可通过，不属于真正的权限错误。
    """
    last: OSError | None = None
    for attempt in range(attempts):
        try:
            os.replace(str(src), str(dst))
            return
        except PermissionError as exc:
            last = exc
        except OSError as exc:
            if getattr(exc, "winerror", None) not in (5, 32):
                raise
            last = exc
        time.sleep(base_delay * (1 + attempt))
    assert last is not None
    raise last


def commit_one(staged_path: Path, target_path: Path) -> None:
    """把已校验的临时副本原子替换到目标位置。"""
    replace_with_retry(staged_path, target_path)


def restore_one(backup_path: Path, target_path: Path) -> None:
    """回滚专用：把备份原子放回目标位置。"""
    replace_with_retry(backup_path, target_path)


def count_non_tres(content_root: Path) -> int:
    return sum(1 for path in content_root.rglob("*") if path.is_file() and path.suffix != ".tres")


def cleanup_stage(stage_root: Path, project_root: Path) -> None:
    try:
        shutil.rmtree(stage_root)
    except OSError as exc:
        print(f"[清理] 临时副本目录删除失败（不影响写盘结果）：{sanitize(exc, project_root)}")


def rollback(records: list[dict], created_dirs: list[Path], project_root: Path) -> tuple[int, list[str]]:
    """按逆序回滚：已覆盖的恢复备份，本次新建的删除；返回（成功数, 失败清单）。"""
    restored = 0
    failed: list[str] = []
    for record in reversed(records):
        target = record["target"]
        try:
            if record["existed"]:
                backup = record["backup"]
                if backup is None or not Path(backup).is_file():
                    raise OSError("备份文件缺失")
                restore_one(Path(backup), target)
                if target.read_bytes() != record["old"]:
                    raise OSError("回滚后字节校验失败")
            else:
                if target.is_file():
                    target.unlink()
                if target.exists():
                    raise OSError("回滚后本次新建文件仍存在")
            restored += 1
        except (OSError, KeyError) as exc:
            failed.append(f"{record.get('display', target.name)}（{sanitize(exc, project_root)}）")

    # 只删除本次新建且已空的目录（如首次落盘时的 active/supports）。
    for directory in sorted(created_dirs, key=lambda item: len(item.parts), reverse=True):
        try:
            directory.rmdir()
        except OSError:
            pass
    return restored, failed


def apply_plan(layout: Layout, actions: list[Action]) -> int:
    """--apply 真实写盘；失败自动回滚，并明确报告本次是否真实写盘。"""
    project_root = layout.project_root
    changes = [action for action in actions if action.kind != KIND_SAME]
    unchanged = len(actions) - len(changes)
    counts = {kind: sum(1 for action in actions if action.kind == kind) for kind in KINDS}

    print()
    if not changes:
        print("[写盘] 没有需要写盘的文件：内容目录已与 dryrun 完全一致。")
        print(f"[校验] 全部 {len(actions)} 个 .tres 字节一致，未写任何文件。")
        print("[本次是否真实写盘] 否（无变化，未写任何文件）")
        print("[下一步] 写盘完成后需重生成 API 地图、重生成数值快照，并跑 GUT 全量门禁；本脚本不执行这些步骤。")
        return 0

    print(f"[写盘] 开始：共 {len(changes)} 个文件需要写入"
          f"（新增 {counts[KIND_NEW]} 个、覆盖 {counts[KIND_CHANGED]} 个），不变 {unchanged} 个跳过。")

    stage_root = Path(tempfile.mkdtemp(prefix=".apply-stage-", dir=str(layout.content_root)))
    records: list[dict] = []
    created_dirs: list[Path] = []
    keep_stage = False
    try:
        for index, action in enumerate(changes, 1):
            entry = action.entry
            staged = stage_root / "new" / entry.category.dir_name / entry.name
            staged.parent.mkdir(parents=True, exist_ok=True)
            staged.write_bytes(entry.data)
            if staged.read_bytes() != entry.data:
                raise OSError(f"临时副本校验失败：{entry.name}")

            target = entry.target
            if not target.parent.is_dir():
                target.parent.mkdir(parents=True, exist_ok=True)
                created_dirs.append(target.parent)

            record = {
                "target": target,
                "existed": target.is_file(),
                "old": action.old_bytes,
                "backup": None,
                "display": display_path(target, project_root),
            }
            if record["existed"]:
                backup = stage_root / "backup" / entry.category.dir_name / entry.name
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, backup)
                if backup.read_bytes() != action.old_bytes:
                    raise OSError(f"原有文件备份校验失败：{entry.name}")
                record["backup"] = backup

            commit_one(staged, target)
            records.append(record)
            if target.read_bytes() != entry.data:
                raise OSError(f"写后字节校验失败：{entry.name}")
            print(f"[写盘] {index}/{len(changes)} {record['display']}（{action.kind}）")

        # 整体再校验一次，任何不一致都走回滚。
        bad = [action.entry.name for action in changes
               if action.entry.target.read_bytes() != action.entry.data]
        if bad:
            raise OSError(f"写后整体校验失败：{len(bad)} 个文件字节不一致（{bad[0]} 等）")

    except BaseException as exc:  # 包含 Ctrl+C：先回滚再报告，避免半写状态
        print(f"[写盘] 失败：{sanitize(exc, project_root)}")
        restored, failed = rollback(records, created_dirs, project_root)
        if failed:
            keep_stage = True
            print(f"[回滚] 未完全恢复：{len(failed)} 个文件回滚失败，备份保留在 "
                  f"{display_path(stage_root, project_root)}；请勿删除该目录，并立即报告。")
            print("[本次是否真实写盘] 否（写盘失败且回滚未完成，内容目录可能不一致）")
            return 1
        cleanup_stage(stage_root, project_root)
        print(f"[回滚] 完成：已恢复或撤销本次写盘涉及的 {restored} 个文件，"
              "内容目录回到写盘前状态。")
        print("[本次是否真实写盘] 否（写盘失败已自动回滚，未保留任何改动）")
        return 1
    cleanup_stage(stage_root, project_root)
    print(f"[写盘] 完成：新增 {counts[KIND_NEW]} 个、覆盖 {counts[KIND_CHANGED]} 个、"
          f"不变 {unchanged} 个，共 {len(actions)} 个。")
    print(f"[校验] 写后逐文件字节比对：{len(changes)}/{len(changes)} 个与 dryrun 完全一致。")
    print(f"[保留] 内容目录下非 .tres 文件（含 .gdkeep）未改动：{count_non_tres(layout.content_root)} 个。")
    print(f"[本次是否真实写盘] 是（真实写入 {len(changes)} 个 .tres；写入后字节与 dryrun 完全一致）")
    print("[下一步] 写盘完成后需重生成 API 地图、重生成数值快照，并跑 GUT 全量门禁；本脚本不执行这些步骤。")
    return 0


# ---------------------------------------------------------------------------
# 入口
# ---------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="P5 落盘工具：把 _tmp/dryrun 的 80 个 .tres 事务式落到 content/gems/{active,supports}")
    parser.add_argument("--project-root", default=None,
                        help="项目根（含 project.godot）；默认从脚本位置向上自动定位")
    parser.add_argument("--dryrun", default=None,
                        help="生成目录；默认 <项目根>/mods/jes-skills/tools/content_workbench/_tmp/dryrun")
    parser.add_argument("--export", dest="export_json", default=None,
                        help="反向导出 JSON；默认 <项目根>/mods/jes-skills/tools/content_workbench/_tmp/export.json")
    parser.add_argument("--content", default=None,
                        help="正式内容目录；默认 <项目根>/mods/jes-skills/content/gems")
    parser.add_argument("--apply", action="store_true",
                        help="真实写盘；不加时默认空跑，只打印三类清单、不写任何文件")
    parser.add_argument("--expect-clean", dest="expect_clean", action="store_true",
                        help="漂移检查用（仅空跑模式）：若出现「新增」或「会改动」则退出码 1，正式内容应与生成结果零漂移")
    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)

    try:
        layout = resolve_layout(args)
    except GuardError as exc:
        print(f"[落盘工具] 未开始：{exc}")
        print("[本次是否真实写盘] 否（未写任何文件）")
        return 1

    print("[落盘工具] P5 · 内容落盘")
    print(f"[落盘工具] 模式：{'真实写盘（--apply）' if args.apply else '空跑（默认，只读不写）'}")

    try:
        files = collect_dryrun_files(layout)
        ids_by_category, id_to_file = load_export(layout)
        entries = pair_entries(layout, files, ids_by_category, id_to_file)
        validate_targets(layout, entries)
        print_guard_ok(layout, entries)
        actions = build_plan(entries)
    except GuardError as exc:
        print(f"[前置守卫] 未通过：{exc}")
        print("[本次是否真实写盘] 否（前置守卫未通过，未写任何文件）")
        return 1
    except OSError as exc:
        print(f"[落盘工具] 读取现有内容失败，已停在写盘之前：{sanitize(exc, layout.project_root)}")
        print("[本次是否真实写盘] 否（未写任何文件）")
        return 1
    except Exception as exc:  # 顶层兜底：任何意外都给中文提示，不向用户抛英文栈
        print(f"[落盘工具] 发生意外，已安全停止：{sanitize(exc, layout.project_root)}")
        print("[本次是否真实写盘] 否（未写任何文件）")
        return 1

    print()
    print_plan(actions, layout.project_root)
    print()
    print_summary(actions)
    print()

    if not args.apply:
        print("[本次是否真实写盘] 否（空跑，一个字节都没写）")
        if args.expect_clean:
            drifted = [a for a in actions if a.kind in (KIND_NEW, KIND_CHANGED)]
            if drifted:
                print(f"[漂移检查] 不通过：{len(drifted)} 个资源与生成结果不一致（新增/会改动），正式内容与工具生成存在漂移。")
                return 1
            print("[漂移检查] 通过：正式内容与生成结果零漂移（新增 0｜会改动 0）。")
        print("[下一步] 确认清单无误后，加 --apply 才会真实写盘。")
        print("[下一步] 真实写盘后需重生成 API 地图、重生成数值快照，并跑 GUT 全量门禁；本脚本不执行这些步骤。")
        return 0

    return apply_plan(layout, actions)


if __name__ == "__main__":
    sys.exit(main())
