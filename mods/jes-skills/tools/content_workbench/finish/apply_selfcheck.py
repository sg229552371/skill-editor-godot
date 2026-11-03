# -*- coding: utf-8 -*-
"""P5 · 落盘工具 apply.py 的自检。

全程只使用系统临时目录里的一次性假项目根，绝不触碰真实
mods/jes-skills/content/，不运行 Godot，也不跑 run_all.py。

逐条验证（对应二期任务书 P5）：
  一、空跑零写入：默认命令只打印「新增 / 会改动 / 不变」，退出 0，目录树与字节完全不变。
  二、--apply 正确落盘：80 个目标文件齐全且字节与 dryrun 一致，.gdkeep / 既有非计划文件保留。
  三、幂等：连续两次 --apply 结果一致，第二次全部判为「不变」。
  四、中途失败自动回滚：注入第 20 个文件替换失败，内容目录恢复写盘前状态，无临时目录残留。
  五、守卫拒绝：缺 export.json / 数量不对 / 非法文件名 / 类别数量不对 / 内容目录缺失 /
      代号与文件名不一致，均中文报错、退出 1、不写任何文件。

用 python 标准库即可，不引入新依赖。打印 [通过]/[失败] 清单与结论，
非零退出码表示存在未通过项。
"""

from __future__ import annotations

import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

FINISH_DIR = Path(__file__).resolve().parent
if str(FINISH_DIR) not in sys.path:
    sys.path.insert(0, str(FINISH_DIR))

# 自检自身不要生成 __pycache__ 垃圾文件
sys.dont_write_bytecode = True

import apply as apply_mod  # noqa: E402  同目录的落盘工具

APPLY_PY = FINISH_DIR / "apply.py"
RAW_LOG = FINISH_DIR / "_tmp" / "apply_selfcheck_raw_output.txt"

# 假的归属代号：67 主动技能 + 13 辅助石，只在本自检的临时目录里使用。
SKILL_IDS = [f"skill_{index:03d}" for index in range(1, 68)]
SUPPORT_IDS = [f"support_{index:03d}" for index in range(1, 14)]
ALL_IDS = SKILL_IDS + SUPPORT_IDS
EXPECTED_TOTAL = 80

# 假内容目录的基线分布：59 新增 + 14 会改动 + 7 不变。
EXPECTED_COUNTS = {"新增": 59, "会改动": 14, "不变": 7}

LEGACY_BYTES = "; 既有非计划文件，写盘后必须原样保留\n".encode("utf-8")

RAW_LINES: list[str] = []
RAW_FULL: list[str] = []
CHECKS: list[tuple[str, bool, str]] = []
TEMP_ROOT: Path | None = None


# ---------------------------------------------------------------------------
# 日志与断言
# ---------------------------------------------------------------------------
def log(text: str = "") -> None:
    print(text)
    RAW_LINES.append(str(text))


def scrub(text: str, root: Path | None = None) -> str:
    """日志里不出现临时目录绝对路径与盘符路径。"""
    text = str(text)
    if root is not None:
        try:
            text = text.replace(str(root.resolve()), "<临时项目根>")
        except OSError:
            pass
    return re.sub(r"[A-Za-z]:[\\/][^\s，。；、）]*", "<路径>", text)


def has_abs_path(text: str, root: Path) -> bool:
    if re.search(r"[A-Za-z]:[\\/]", text):
        return True
    try:
        return str(root.resolve()) in text
    except OSError:
        return False


def check(label: str, condition: bool, measured: str) -> None:
    CHECKS.append((label, bool(condition), str(measured)))
    mark = "通过" if condition else "失败"
    print(f"    [{mark}] {label}｜实测：{measured}")


def show_output(title: str, text: str, root: Path) -> None:
    """控制台只显示节选，完整原始输出写入 _tmp 的日志文件。"""
    log(title)
    lines = text.rstrip().splitlines()
    if len(lines) <= 36:
        for line in lines:
            log("    " + line)
    else:
        for line in lines[:18]:
            log("    " + line)
        log(f"    ……（中间省略 {len(lines) - 30} 行，完整原始输出见 finish/_tmp/apply_selfcheck_raw_output.txt）")
        for line in lines[-12:]:
            log("    " + line)
    RAW_FULL.append(f"\n===== {title} =====\n{scrub(text, root)}")


def header(title: str) -> None:
    log("=" * 72)
    log(title)
    log("=" * 72)


# ---------------------------------------------------------------------------
# 假项目根与假数据
# ---------------------------------------------------------------------------
def dryrun_bytes(resource_id: str) -> bytes:
    return (
        "[gd_resource type=\"Resource\" script_class=\"SkillData\" format=3]\n"
        "\n"
        f"; 自检假 dryrun：{resource_id}\n"
        "value = 1\n"
    ).encode("utf-8")


def old_bytes(resource_id: str) -> bytes:
    return (
        "[gd_resource type=\"Resource\" format=3]\n"
        "\n"
        f"; 自检旧内容（必须被覆盖）：{resource_id}\n"
        "value = 0\n"
    ).encode("utf-8")


class Fixture:
    """在一次性临时目录里构造假项目根。"""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.dryrun = root / apply_mod.DEFAULT_DRYRUN_REL
        self.export_json = root / apply_mod.DEFAULT_EXPORT_REL
        self.content_root = root / apply_mod.DEFAULT_CONTENT_REL
        self.active = self.content_root / "active"
        self.supports = self.content_root / "supports"

    def create(self) -> None:
        self.root.mkdir(parents=True, exist_ok=True)
        (self.root / "project.godot").write_text("; 自检假项目根，非真实项目\n", encoding="utf-8")
        self.dryrun.mkdir(parents=True, exist_ok=True)
        self.export_json.parent.mkdir(parents=True, exist_ok=True)
        self.reset_dryrun()
        self.write_export()
        self.reset_content()

    def reset_dryrun(self) -> None:
        if self.dryrun.exists():
            shutil.rmtree(self.dryrun)
        self.dryrun.mkdir(parents=True)
        for resource_id in ALL_IDS:
            (self.dryrun / f"{resource_id}.tres").write_bytes(dryrun_bytes(resource_id))

    def write_export(self, skill_ids=None, support_ids=None) -> None:
        skills = list(SKILL_IDS if skill_ids is None else skill_ids)
        supports = list(SUPPORT_IDS if support_ids is None else support_ids)
        payload = {
            "meta": {
                "skill_count": len(skills),
                "support_count": len(supports),
                "total": len(skills) + len(supports),
            },
            "skills": [{"gem_id": resource_id, "display_name": f"自检技能{index + 1}"}
                       for index, resource_id in enumerate(skills)],
            "supports": [{"support_id": resource_id, "display_name": f"自检辅助{index + 1}"}
                         for index, resource_id in enumerate(supports)],
            "source_files": {resource_id: f"{resource_id}.tres"
                             for resource_id in skills + supports},
        }
        self.export_json.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    def reset_content(self) -> None:
        if self.content_root.exists():
            shutil.rmtree(self.content_root)
        self.active.mkdir(parents=True)
        self.supports.mkdir(parents=True)
        (self.active / ".gdkeep").write_bytes(b"")
        (self.supports / ".gdkeep").write_bytes(b"")
        (self.active / "legacy_only.tres").write_bytes(LEGACY_BYTES)

        for index, resource_id in enumerate(SKILL_IDS, 1):
            if index <= 10:      # 会改动
                (self.active / f"{resource_id}.tres").write_bytes(old_bytes(resource_id))
            elif index <= 15:    # 不变
                (self.active / f"{resource_id}.tres").write_bytes(dryrun_bytes(resource_id))
        for index, resource_id in enumerate(SUPPORT_IDS, 1):
            if index <= 4:       # 会改动
                (self.supports / f"{resource_id}.tres").write_bytes(old_bytes(resource_id))
            elif index <= 6:     # 不变
                (self.supports / f"{resource_id}.tres").write_bytes(dryrun_bytes(resource_id))

    def reset_all(self) -> None:
        self.reset_dryrun()
        self.write_export()
        self.reset_content()

    def target(self, resource_id: str) -> Path:
        directory = self.active if resource_id in SKILL_IDS else self.supports
        return directory / f"{resource_id}.tres"


# ---------------------------------------------------------------------------
# 快照与运行工具
# ---------------------------------------------------------------------------
def snapshot_paths(base: Path) -> dict:
    """记录目录树：全部文件字节 + 全部子目录（用于证明零写入/回滚一致）。"""
    files: dict[str, bytes] = {}
    dirs: set[str] = set()
    if not base.exists():
        return {"files": files, "dirs": dirs}
    for path in sorted(base.rglob("*")):
        relative = path.relative_to(base).as_posix()
        if path.is_dir():
            dirs.add(relative)
        elif path.is_file():
            files[relative] = path.read_bytes()
    return {"files": files, "dirs": dirs}


def run_apply(root: Path, apply_flag: bool = False, extra=None):
    """子进程跑 apply.py；强制 UTF-8 输出，保证中文断言稳定。"""
    command = [sys.executable, str(APPLY_PY), "--project-root", str(root)]
    if apply_flag:
        command.append("--apply")
    if extra:
        command.extend(extra)
    environment = dict(os.environ)
    environment["PYTHONIOENCODING"] = "utf-8"
    environment["PYTHONUTF8"] = "1"
    environment["PYTHONDONTWRITEBYTECODE"] = "1"
    proc = subprocess.run(
        command, capture_output=True, text=True, encoding="utf-8",
        errors="replace", cwd=str(root), env=environment,
    )
    return proc, (proc.stdout or "") + (proc.stderr or "")


def run_apply_inprocess(root: Path, apply_flag: bool = True) -> tuple[int, str]:
    buffer = io.StringIO()
    arguments = ["--project-root", str(root)]
    if apply_flag:
        arguments.append("--apply")
    with redirect_stdout(buffer):
        return_code = apply_mod.main(arguments)
    return return_code, buffer.getvalue()


def parse_counts(text: str) -> dict[str, int | None]:
    counts: dict[str, int | None] = {}
    for kind in ("新增", "会改动", "不变"):
        match = re.search(rf"^\[{kind}\]\s*(\d+)\s*个", text, re.M)
        counts[kind] = int(match.group(1)) if match else None
    return counts


def missing_keywords(text: str, keywords) -> list[str]:
    return [keyword for keyword in keywords if keyword not in text]


# ---------------------------------------------------------------------------
# 自检一：空跑零写入
# ---------------------------------------------------------------------------
def scenario_dry_run(fixture: Fixture) -> None:
    header("自检一：空跑零写入（默认命令只打印清单、不写任何文件）")
    fixture.reset_all()
    before = snapshot_paths(fixture.root)

    proc, text = run_apply(fixture.root)
    show_output("[原始输出] python finish/apply.py（默认空跑）", text, fixture.root)
    after = snapshot_paths(fixture.root)

    check("空跑退出码为 0", proc.returncode == 0, f"退出码 {proc.returncode}")
    counts = parse_counts(text)
    check("空跑三类清单数量 = 新增 59 / 会改动 14 / 不变 7",
          counts == EXPECTED_COUNTS, f"实测 {counts}")
    check("空跑汇总总数为 80", "共 80 个" in text, "输出含「共 80 个」")
    check("空跑输出三类清单标题齐全",
          all(f"[{kind}]" in text for kind in ("新增", "会改动", "不变")),
          "新增 / 会改动 / 不变 三类标题都出现")
    check("空跑明确标注本次未真实写盘",
          "[本次是否真实写盘] 否（空跑，一个字节都没写）" in text,
          "含「本次是否真实写盘：否（空跑…）」")
    check("空跑输出不含本机绝对路径", not has_abs_path(text, fixture.root),
          "无盘符绝对路径、无临时目录绝对路径")
    check("空跑未写任何文件（目录树与全部文件字节前后一致）",
          before == after,
          f"文件 {len(before['files'])} 个 / 目录 {len(before['dirs'])} 个，前后一致")
    log()


# ---------------------------------------------------------------------------
# 自检二：--apply 正确落盘
# ---------------------------------------------------------------------------
def scenario_apply(fixture: Fixture) -> None:
    header("自检二：--apply 正确落盘（80 个 / 字节一致 / 保留 .gdkeep 与既有文件）")
    fixture.reset_all()
    proc, text = run_apply(fixture.root, apply_flag=True)
    show_output("[原始输出] python finish/apply.py --apply", text, fixture.root)

    check("--apply 退出码为 0", proc.returncode == 0, f"退出码 {proc.returncode}")
    counts = parse_counts(text)
    check("--apply 三类数量 = 新增 59 / 会改动 14 / 不变 7",
          counts == EXPECTED_COUNTS, f"实测 {counts}")
    check("--apply 明确标注本次已真实写盘",
          "[本次是否真实写盘] 是（真实写入 73 个 .tres" in text,
          "含「本次是否真实写盘：是」与写入 73 个")

    bad = [resource_id for resource_id in ALL_IDS
           if not fixture.target(resource_id).is_file()
           or fixture.target(resource_id).read_bytes() != dryrun_bytes(resource_id)]
    check("--apply 后 80 个目标文件全部存在且字节与 dryrun 完全一致",
          not bad, "80/80 一致" if not bad else f"不一致 {len(bad)} 个：{bad[:5]}")

    gdkeep_ok = ((fixture.active / ".gdkeep").is_file()
                 and (fixture.active / ".gdkeep").read_bytes() == b""
                 and (fixture.supports / ".gdkeep").is_file()
                 and (fixture.supports / ".gdkeep").read_bytes() == b"")
    check(".gdkeep 在两个类别目录里均保留且字节未变", gdkeep_ok,
          "active/.gdkeep 与 supports/.gdkeep 保留、均为空文件")

    legacy = fixture.active / "legacy_only.tres"
    check("既有非计划文件 legacy_only.tres 未被删除或改写",
          legacy.is_file() and legacy.read_bytes() == LEGACY_BYTES,
          "仍存在且字节与写盘前一致")

    stages = list(fixture.content_root.glob(".apply-stage-*"))
    check("写盘成功后无临时副本目录残留", not stages,
          "content/gems 下无 .apply-stage-* 目录" if not stages else f"残留 {len(stages)} 个")

    active_tres = list(fixture.active.glob("*.tres"))
    support_tres = list(fixture.supports.glob("*.tres"))
    check("active 下 .tres 数 = 68（67 技能 + 1 个既有保留文件）",
          len(active_tres) == 68, f"实测 {len(active_tres)} 个")
    check("supports 下 .tres 数 = 13", len(support_tres) == 13,
          f"实测 {len(support_tres)} 个")
    check("--apply 输出不含本机绝对路径", not has_abs_path(text, fixture.root),
          "无盘符绝对路径、无临时目录绝对路径")
    log()


# ---------------------------------------------------------------------------
# 自检三：幂等
# ---------------------------------------------------------------------------
def scenario_idempotent(fixture: Fixture) -> None:
    header("自检三：幂等（连续两次 --apply 结果一致）")
    fixture.reset_all()
    first_proc, first_text = run_apply(fixture.root, apply_flag=True)
    first_snapshot = snapshot_paths(fixture.content_root)

    second_proc, second_text = run_apply(fixture.root, apply_flag=True)
    second_snapshot = snapshot_paths(fixture.content_root)
    show_output("[原始输出] 第二次 python finish/apply.py --apply（节选）",
                second_text, fixture.root)

    check("第一次 --apply 退出码为 0", first_proc.returncode == 0,
          f"退出码 {first_proc.returncode}")
    check("第二次 --apply 退出码为 0", second_proc.returncode == 0,
          f"退出码 {second_proc.returncode}")
    counts = parse_counts(second_text)
    check("第二次 --apply 三类数量 = 新增 0 / 会改动 0 / 不变 80",
          counts == {"新增": 0, "会改动": 0, "不变": 80}, f"实测 {counts}")
    check("第二次明确没有文件需要写盘",
          "没有需要写盘的文件" in second_text
          and "[本次是否真实写盘] 否（无变化，未写任何文件）" in second_text,
          "输出含「没有需要写盘的文件」与「否（无变化…）」")
    check("两次 --apply 后内容目录文件集合与全部字节完全一致",
          first_snapshot == second_snapshot,
          f"文件 {len(first_snapshot['files'])} 个 / 目录 {len(first_snapshot['dirs'])} 个，两次一致")
    log()


# ---------------------------------------------------------------------------
# 自检四：中途失败自动回滚
# ---------------------------------------------------------------------------
def scenario_rollback(fixture: Fixture) -> None:
    header("自检四：中途失败自动回滚（注入第 20 个文件替换失败）")
    fixture.reset_all()
    before = snapshot_paths(fixture.content_root)

    calls = {"count": 0}
    original_commit = apply_mod.commit_one

    def flaky_commit(staged_path, target_path):
        calls["count"] += 1
        if calls["count"] >= 20:
            raise OSError("注入故障：模拟第 20 个文件替换失败")
        return original_commit(staged_path, target_path)

    apply_mod.commit_one = flaky_commit
    try:
        return_code, text = run_apply_inprocess(fixture.root, apply_flag=True)
    finally:
        apply_mod.commit_one = original_commit

    after = snapshot_paths(fixture.content_root)
    show_output("[原始输出] 注入失败后的 apply.py（节选）", text, fixture.root)

    check("失败时退出码为 1", return_code == 1, f"实测 {return_code}")
    check("失败发生在中途（第 20 个文件替换时抛错，前 19 个已提交）",
          calls["count"] == 20, f"commit_one 调用 {calls['count']} 次")
    check("输出明确报告写盘失败", "[写盘] 失败" in text,
          "含「[写盘] 失败」")
    check("输出明确报告自动回滚完成", "[回滚] 完成" in text,
          "含「[回滚] 完成」")
    check("回滚后内容目录文件集合与全部字节恢复写盘前状态",
          before == after,
          f"文件 {len(before['files'])} 个 / 目录 {len(before['dirs'])} 个，前后一致")
    stages = list(fixture.content_root.glob(".apply-stage-*"))
    check("回滚后无临时副本目录残留", not stages,
          "content/gems 下无 .apply-stage-* 目录" if not stages else f"残留 {len(stages)} 个")
    check("回滚后明确本次未真实写盘",
          "[本次是否真实写盘] 否（写盘失败已自动回滚" in text,
          "含「本次是否真实写盘：否（写盘失败已自动回滚…）」")
    check("失败回滚输出不含本机绝对路径", not has_abs_path(text, fixture.root),
          "无盘符绝对路径、无临时目录绝对路径")
    log()


# ---------------------------------------------------------------------------
# 自检五：前置守卫拒绝
# ---------------------------------------------------------------------------
def mutate_missing_export(fixture: Fixture) -> None:
    fixture.export_json.unlink()


def mutate_count_79(fixture: Fixture) -> None:
    (fixture.dryrun / "skill_067.tres").unlink()


def mutate_illegal_name(fixture: Fixture) -> None:
    (fixture.dryrun / "skill_067.tres").unlink()
    (fixture.dryrun / "Bad-Name.tres").write_bytes(dryrun_bytes("bad_name"))


def mutate_junk_file(fixture: Fixture) -> None:
    (fixture.dryrun / "skill_001.tres.uid").write_bytes(b"uid://dummy")


def mutate_wrong_category_counts(fixture: Fixture) -> None:
    fixture.write_export(skill_ids=SKILL_IDS[1:], support_ids=SUPPORT_IDS + [SKILL_IDS[0]])


def mutate_misplaced_file(fixture: Fixture) -> None:
    shutil.copyfile(fixture.dryrun / "skill_001.tres",
                    fixture.supports / "skill_001.tres")


def mutate_content_missing(fixture: Fixture) -> None:
    shutil.rmtree(fixture.content_root)


def mutate_code_mismatch(fixture: Fixture) -> None:
    (fixture.dryrun / "skill_001.tres").rename(fixture.dryrun / "skill_001x.tres")


def run_guard_case(fixture: Fixture, name: str, mutate, keywords) -> None:
    fixture.reset_all()
    mutate(fixture)
    before = snapshot_paths(fixture.root)
    proc, text = run_apply(fixture.root, apply_flag=True)
    after = snapshot_paths(fixture.root)

    show_output(f"[原始输出] 守卫拒绝：{name}", text, fixture.root)
    check(f"{name}：--apply 被前置守卫拒绝（退出码 1）",
          proc.returncode == 1, f"退出码 {proc.returncode}")
    missing = missing_keywords(text, keywords)
    check(f"{name}：中文报错含 {'、'.join(keywords)}",
          not missing, "全部命中" if not missing else "缺少：" + "、".join(missing))
    check(f"{name}：守卫失败时未写任何文件（目录树与字节前后一致）",
          before == after,
          f"文件 {len(before['files'])} 个 / 目录 {len(before['dirs'])} 个，前后一致")
    check(f"{name}：明确本次未真实写盘",
          "[本次是否真实写盘] 否" in text, "含「本次是否真实写盘：否」")
    check(f"{name}：输出不含本机绝对路径",
          not has_abs_path(text, fixture.root), "无盘符绝对路径、无临时目录绝对路径")
    log()


def scenario_guards(fixture: Fixture) -> None:
    header("自检五：前置守卫拒绝（中文报错 / 退出 1 / 不落盘）")
    cases = [
        ("缺 export.json", mutate_missing_export, ["缺少 export.json"]),
        ("dryrun 数量 79", mutate_count_79, ["文件数 = 79", "80"]),
        ("非法文件名 Bad-Name.tres", mutate_illegal_name, ["非法文件名", "Bad-Name.tres"]),
        ("dryrun 混入非 .tres 文件", mutate_junk_file, ["非法文件", "skill_001.tres.uid"]),
        ("归属类别数量 66/14", mutate_wrong_category_counts,
         ["类别数量", "66", "14", "67", "13"]),
        ("内容目录不存在", mutate_content_missing, ["内容目录不存在"]),
        ("内容目录与预期类别不符", mutate_misplaced_file, ["类别不符", "skill_001"]),
        ("代号与文件名不一致", mutate_code_mismatch, ["不一致", "skill_001"]),
    ]
    for name, mutate, keywords in cases:
        log(f"【守卫用例】{name}")
        run_guard_case(fixture, name, mutate, keywords)


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
def main() -> int:
    global TEMP_ROOT
    TEMP_ROOT = Path(tempfile.mkdtemp(prefix="jes_apply_selfcheck_"))
    fixture = Fixture(TEMP_ROOT)

    log("P5 落盘工具 apply.py · 自检")
    log(f"Python：{sys.version.split()[0]}；只用标准库，不运行 Godot、不跑 run_all.py")
    log(f"临时项目根：<系统临时目录>/{TEMP_ROOT.name}（结束后自动删除，不触碰真实 content/）")
    log()

    try:
        fixture.create()
        scenario_dry_run(fixture)
        scenario_apply(fixture)
        scenario_idempotent(fixture)
        scenario_rollback(fixture)
        scenario_guards(fixture)
    except Exception as exc:  # 自检本身异常也必须让结论变红
        check("自检过程无意外异常", False,
              f"{type(exc).__name__}: {scrub(exc, TEMP_ROOT)}")
    finally:
        shutil.rmtree(TEMP_ROOT, ignore_errors=True)

    passed = sum(1 for _, ok, _ in CHECKS if ok)
    total = len(CHECKS)
    log("=" * 72)
    log(f"自检汇总：{passed}/{total} 条通过")
    for label, ok, measured in CHECKS:
        log(f"    [{'通过' if ok else '失败'}] {label}｜实测：{measured}")
    log("=" * 72)

    try:
        RAW_LOG.parent.mkdir(parents=True, exist_ok=True)
        RAW_LOG.write_text("\n".join(RAW_FULL) + "\n" + "\n".join(RAW_LINES) + "\n",
                           encoding="utf-8")
        print("[自检] 完整原始输出已保留：finish/_tmp/apply_selfcheck_raw_output.txt")
    except OSError as exc:
        print(f"[自检] 原始输出写入失败：{scrub(exc)}")

    print(f"[自检] 结论：{'全部通过' if passed == total else '存在未通过项'}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
