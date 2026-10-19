# T-078 20.1.3 整卡校验凭据（第 4 轮）

## 状态

**✅ 已取得（审核方 2026-10-19 08:0x 串行实测）**：六阶段实际输出原文全部落盘，
**六阶段 block=0 成立**。本文件由执笔方建立时标为 blocked（当时未运行引擎），
审核方完成串行门禁后**用实际输出替换了全部「未取得」占位**。

> 第 4 轮交付时本文件曾如实记录「未取得」，属**未建空占位的合规处置**。

## 校验卡绑定

- CFG：U-39 **v2 卡**，`meta.version: "1.0.0"`，落 `user://t078/`（不在 `res://` 建文件）。
- CFG 原文：`01-fill-card.md` 的《v2 卡》章节（78 行 yaml）。
- **v2 CFG 内容指纹**：`sha256 = 1f67673c7b9661ec58b655df1766eec6edd5e1a81260d98f55ab716d75728a9b`
  —— 算法：`sha256(utf-8)`，输入为 `01-fill-card.md` 中「## v2 卡」标题下第一个 `yaml` 代码块正文，**可复算**。
- **禁止跨卡复用**：v1 卡（`meta.version: "1"`）与既有 05/06/07 凭据**不得**作为 v2 整卡证据（U-39）。
- 真实规则卡：`r_identity`（V-001…018）· `r_types`（V-019…038）· `r_modifier`（V-039…069）· `r_present`（V-070…084）。
- 调用入口：`SkillApi.validate_with_context(cfg, stage, context)`；既有 `SkillApi.validate(cfg, stage)` **仍为桩**（U-38 要求一字不动，实测检查通过）。
- `anim` 段：v2 CFG 含 `anim: {}`（**空 dict，未启用**），符合派单 §四「不启用 `anim` 段」。

## 六阶段实际输出（原文）

数据来源：`res://tests/test_m6_end_to_end.gd`，Godot 4.7.1 headless GUT 串行执行时打印的返回包原文
（`gut_cmdln.gd -gtest=res://tests/test_m6_end_to_end.gd -gexit`）。

| 阶段 | `ok` | block | warn | hint | `revision` | `stale` | `accepted` |
|---|---|---:|---:|---:|---:|---|---|
| `filling` | **true** | **0** | 0 | 0 | **2** | false | true |
| `card` | **true** | **0** | 0 | 0 | **2** | false | true |
| `assembly` | **true** | **0** | 0 | 0 | **2** | false | true |
| `save` | **true** | **0** | 0 | 0 | **2** | false | true |
| `load` | **true** | **0** | 0 | 0 | **2** | false | true |
| `preview` | **true** | **0** | 0 | 0 | **2** | false | true |

**目标「六阶段 block=0」已被动态证明。** 六个阶段返回**完全相同形状**的结果包，
`diagnostics` 均为空数组。

### 返回包原文（`save` 阶段，六阶段同构）

```text
T078 v2 validation save: { "ok": true, "diagnostics": [], "notices": ["V-076：可选上下文 damage_number_semantics 缺失，子检查跳过"], "removed": 0, "duplicates": [], "revision": 2, "stale": false, "accepted": true, "error": "" }
```

其余五阶段原文（`filling` / `card` / `assembly` / `load` / `preview`）除阶段名外**逐字段相同**。

> **关于 `notices`**：`V-076` 是 **notice（跳过提示）**，不是 `diagnostics` 成员，
> 不参与 block 判定 —— 六阶段 `diagnostics` 实测均为 `[]`。

## 坑 13 非空对照（**「零阻止项」不是空集合恒真**）

往 v2 CFG 注入非法 `skill_id` 后同入口复跑，实际输出：

```text
T078 v2 invalid identity probe: { "ok": false, "diagnostics": [<RefCounted#...>], "notices": ["V-076：可选上下文 damage_number_semantics 缺失，子检查跳过"], "removed": 0, "duplicates": [], "revision": 2, "stale": false, "accepted": true, "error": "" }
```

- `ok` 由 `true` → **`false`**，且 `diagnostics` 由 `[]` → **非空 1 条** —— 证明校验确实在读取 CFG。
- 反向对照：`test_validate_with_context_does_not_fabricate_missing_context`
  断言**缺少 `draft_revision` 时显式失败**（不是 6 个阶段全绿）——
  这条同时防住了 U-38 第 5 条「禁止在 API 内编造 context」的违反。

## 调用方实际 context 绑定

六个 context 键**全部由调用方显式传入**，`SkillApi` 内部未做任何推导/兜底（U-38 第 5 条）：

| 键 | 实际值（本次调用） | 来源 |
|---|---|---|
| `draft_revision` | `2` | 夹具显式入参，缺时被 API 显式拒绝（见上） |
| `submitted_paths` | 七键全列：`schema_version` / `skill_id` / `meta` / `bricks` / `params` / `presentation` / `runtime_hints` | 填写阶段调用方提交路径集合 |
| `cross_card_facts` 等跨卡事实 | 同 `_validation_context()` 构造（`catalog` / `card_behaviors` / `definitions` …） | assembly 阶段由调用方提供 |
| `baseline_version_state` | 由调用方传入 | load 阶段必需 |
| `migration_state` | 由调用方传入 | load 阶段必需 |
| `probe_credentials` · `preview_fingerprint` | 由调用方传入 | preview 阶段必需 |

另含 `record_fields`（`res://data/record_fields.json`）、`project_limits`、`budget_estimate` 等配料键。

## 审核方做的机械修复（**不是执笔方的设计缺陷**）

首跑 **3/6 红**，原文：

```text
ERROR: Parse JSON failed. Error at line 0: Unknown error getting token
   at: parse_string (core/io/json.cpp:629)
       [0] _json (res://tests/test_m6_end_to_end.gd:11)
       [1] _validation_context (res://tests/test_m6_end_to_end.gd:202)
```

真因：`_validation_context()` 第 202 行写的是 `_json("res://data/record_fields")` ——
**漏了 `.json` 扩展名**，`FileAccess.get_file_as_string()` 取到空串。

**处置**：补 `.json` → `"res://data/record_fields.json"`，**未改任何生产行为、未放松断言**。
复跑 **6/6，53 asserts，Failing 0**。

## 结论

- ✅ **20.1.3 整卡校验**：六入口**无阻止项**，取到 `revision=2` 与依赖指纹。
- ✅ 坑 13 非空对照成立。
- ✅ U-38 全部条款守住：`validate` 桩未动、纯新增、不编造 context。
- ❌ **20.1.8 人审核仍缺** —— 由审核方另行出具，本凭据不冒充。

引擎命令由审核方执行（Godot 4.7.1，逐文件串行，禁 `-gdir`）；执笔方本轮**未运行引擎，已静态复核**。
