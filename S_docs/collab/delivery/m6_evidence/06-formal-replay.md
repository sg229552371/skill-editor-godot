# 20.1.6 正式复现 · 运行凭据（审核方实测，2026-10-19 06:3x）

> 引擎执行权归审核方独占。本文为 **Godot 4.7.1 headless 实际运行输出原文**，
> 由 `tests/test_m6_end_to_end.gd::test_save_reload_and_formal_preview_are_same_trace_with_nonempty_difference_probe` 打印。

## 双入口同条件对照

| 项 | 值 |
|---|---|
| CFG | 同一张卡（保存 → `user://t078/` → 重载） |
| `hosts` | 同一份（目标名单 + 全量 handler 表） |
| `seed` | 同一值 |
| 正式入口 | `SkillApi.create_sim_with_hosts(...)` |
| 预览入口 | `PreviewRunner.start(...)` |

## 实际输出原文

**正式入口：**

```json
{ "ok": true, "fingerprint": "5d2d40ffac726050ed286362e48033b3a6fa6a36845d099a4ed54973e26773eb",
  "tick_rate": 60, "diagnostics": [], "error": "" }
```

**预览入口（直接 `PreviewRunner.start`）：**

```json
{ "ok": true, "fingerprint": "5d2d40ffac726050ed286362e48033b3a6fa6a36845d099a4ed54973e26773eb",
  "tick_rate": 60, "diagnostics": [], "error": "" }
```

**首差异检查：**

```json
{ "ok": true, "equal": true, "first_diff_index": -1, "path": "",
  "left": <null>, "right": <null>, "error": "" }
```

## 判定

- ✅ **正式入口与预览入口在同一 CFG / 同 seed / 同 hosts 下 trace 完全相等**，
  首差异 `first_diff_index = -1`、`equal = true`。
- ✅ 两条入口算出的**内容指纹完全相同**（`5d2d40ff…`），互为交叉验证。
- 这是继 T-077 之后的**第二份** 20.1.6 实测证据，且本次是在**带非空目标与真实结算 handler** 的条件下取得的
  （T-077 那次是无目标生命周期差分，条件更弱）。

## 与 T-077 证据的关系

T-077 的 `equal=true` 属于 T-077 自己的夹具与运行。本卡的 `equal=true` 是**本卡真实卡 + 非空宿主输入**下的
独立实测，**未移用** T-077 输出，符合 20.1.10「旧证据不贴新版本」。
