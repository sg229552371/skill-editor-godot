# 20.1.7 重跑 · 运行凭据与破坏对照（审核方实测，2026-10-19 06:3x）

> 引擎执行权归审核方独占。本文为 **Godot 4.7.1 headless 实际运行输出原文**，
> 由 `tests/test_m6_end_to_end.gd::test_save_reload_and_formal_preview_are_same_trace_with_nonempty_difference_probe` 打印。

## 1. 同输入同种子重跑：逐项相等

```json
{ "ok": true, "equal": true, "first_diff_index": -1, "path": "",
  "left": <null>, "right": <null>, "error": "" }
```

正式入口与预览入口两次运行逐项相等，无差异。

## 2. **非空破坏对照**（关键，坑 13）

只断言「相等」会落入**空集合恒真**陷阱 —— 若两次 trace 都是空数组，也会「相等」。
因此必须证明：**改动输入后，首差异确实能被检出**。

改动 `amount` 后的实际输出：

```json
{ "ok": true, "equal": false, "first_diff_index": 0, "path": "trace[0].fingerprint",
  "left":  "5d2d40ffac726050ed286362e48033b3a6fa6a36845d099a4ed54973e26773eb",
  "right": "a533944f687bb5fc2015a24512c0daa5b30e8ce92f250ec360c244878f9e9603",
  "error": "" }
```

| 项 | 值 |
|---|---|
| `equal` | **false** |
| `first_diff_index` | **0**（不是 -1） |
| `path` | `trace[0].fingerprint` |
| 左值（原卡） | `5d2d40ff…` |
| 右值（改后） | `a533944f…` |

## 判定

- ✅ **破坏对照成立**：改一个参数后首差异**非空**（`equal=false`、`first_diff_index=0`、两侧指纹实际不同）。
  → 证明上一节的「相等 / 首差异为空」**不是空集合恒真**，是真实的一致性证据。
- ✅ 满足 20.1.10「证据绑定版本和内容指纹」：改动后指纹随之变化，指纹确实绑定内容。

## 局限（如实标注）

- 本文是**正式 vs 预览双入口**的差分与破坏对照，**不是**「同一入口连续重跑两次」的严格重跑报告。
  严格意义的 20.1.7 两次完整 trace 比较报告，需在后续轮次补 `create_sim_with_hosts` **同入口两次运行**的
  独立 trace 原文。
- 当前凭据为**单次运行快照**，尚未做跨进程/重启后的重跑一致性验证。
