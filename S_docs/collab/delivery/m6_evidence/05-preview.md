# 20.1.5 预览 · 运行凭据（审核方实测，2026-10-19 06:3x）

> 引擎执行权归审核方独占。本文为 **Godot 4.7.1 headless 实际运行输出原文**，
> 由 `tests/test_m6_end_to_end.gd::test_real_card_host_channel_produces_nonempty_three_stream_snapshot` 打印。

## 运行条件

| 项 | 实际值 |
|---|---|
| 入口 | `SkillApi.create_sim_with_hosts(cfg, seed, hosts)` → `PreviewRunner.start` |
| 目标名单 | `hosts.targets = ["enemy_one"]`（**非空**，第 1 轮 blocked 的物理阻塞点已解除） |
| handler 表 | 按 `data/params_meta.json` 的 `enums.part_type` **全量登记**，未用类型绑显式 `false` 的 `_unsupported_part` |
| tick_rate | **60** |
| 指纹 | `5d2d40ffac726050ed286362e48033b3a6fa6a36845d099a4ed54973e26773eb` |
| 运行状态 | `{"ok": true, "diagnostics": [], "error": ""}` |

## 三栏实际条目原文（**分别非空**，对应 20.1.9）

### 事件栏 `events`（1 条）

```json
[{ "type": "hit", "tick": 1, "body_id": "preview:0:root:0", "target_id": "enemy_one" }]
```

### 结算栏 `records`（1 条）

```json
[{ "type": "hit_settled", "tick": 1, "body_id": "preview:0:root:0", "target_id": "enemy_one",
   "parts": [{ "part_index": 0, "type": "physical", "evaded": false, "immune": false, "zero": false, "value": 2.5 }],
   "killed": false }]
```

### 调试栏 `debug`（1 条）

```json
[{ "root_id": "preview:0:root:1", "id": "preview:0:root:1", "reason": "budget_drop",
   "occupied": 1, "type": "debug_record", "kind": "budget_drop" }]
```

## 判定

- ✅ **三栏各自非空**（事件 1 / 结算 1 / 调试 1），满足 20.1.9「例子输入非空且到目标分支」的非空要求。
- ✅ 结算栏的 `parts` 含真实数值 `value: 2.5`、`evaded/immune/zero` 三态齐备 → 不是空壳记录。
- ✅ 事件栏只有 `hit`（D-33：hit 不落结算栏；此处 `hit` 在事件栏、`hit_settled` 在结算栏，**分界正确**）。

## 局限（如实标注）

- 本文凭据来自**集成测试内的 CFG**（`user://t078/`），尚未由**编辑器 UI** 手动填卡触发；
  20.1.1「从已登记积木创建技能」的编辑器接线仍未完成。
- 三栏各 1 条，是最低非空强度，**不是** ED-17 全集覆盖（ED-17 的 17 条 blocked 未齐）。
