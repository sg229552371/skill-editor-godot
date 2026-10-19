# 开发进度看板（WorkBuddy 维护，每次汇报刷新）

> 引擎：Godot **4.7.1**（`Ryko.GodotHub/godot-versions/4.7.1-stable`）｜门禁归 WorkBuddy 独占，Claude CLI 只写代码
> 更新：2026-10-19 09:5x（**WorkBuddy 单工作流首批**：用户拍板 D-00-4，执笔与门禁合并到主会话，
> 审核改由**独立子 Agent** 承担；同批交付 **T-081 `save_cfg` / T-082 `load_cfg`** 两张填桩卡，
> 补上 M6 20.1.4「保存→重载」凭据。全量回归
> **55 文件 / 698 用例 / 14380 断言 / Failing 0 / Risky 1(pending) / bad=0**，较上轮 **+1 文件 +23 用例 +113 断言**。
> ⚠ **坑 27（本轮新增，环境级）**：`tests/test_plugin_wiring.gd` 内的 `class PreviewRunner`
> 与 `skill_core/runtime/preview_runner.gd` 的全局 `class_name PreviewRunner` 撞名 ——
> 在**干净环境**（新克隆 + 首次 import）直接 `Parse Error: Class "PreviewRunner" hides a global script class`，
> 该文件 7 用例整体不执行。旧环境因 `.godot` 类缓存先于该文件建立而未暴露。已改名 `WiringPreviewRunner`。
> **固化：测试内自定义类不得与任何 `class_name` 同名；换环境复跑是唯一可靠的暴露手段。**
>
> ⚠ 隔离门禁说明：本轮用户 Godot 4.7.1 编辑器占用主工程 `.godot`（PID 37172），
> 门禁在 `E:/tmp/skill_editor_gate` 镜像副本执行，与主工程同源同版本，不共享缓存。
> 更新：2026-10-19 07:4x（**本轮自动化**：开场 HEAD `96e15e2`，上一批已完整收口 ——
> **无 CLI 进程、无未提交代码、无漂流产出**。全量回归实测
> **54 / 675 / 674 / 14219 / Failing 0 / Risky 1 / bad=0**，与上一轮权威基线**逐项一致** → 基线完好。
> 审核方静态复核定位到两条被低估的缺口，据此裁决 **U-37** 并派出双卡：
> **T-078 第 3 轮**（`validate` 桩 → 真实转发，取 20.1.3 凭据）·
> **T-080**（ED-17-19：装配目前是**孤儿状态**，从未被任何实例创建逻辑消费）。
> 两卡文件所有权**零重叠**（`api/` 层 vs `runtime/` 层），07:5x 并行派出）
>
> **✅ U-37 裁决（本轮新增，重要澄清）**：**既有 `_not_implemented` 桩改为真实转发不构成改契约** ——
> T-000 冻结的是**契约**（签名 + 返回包形状），不是「函数体必须永远是空壳」。
> 只要签名一字不动、返回包键只增不减、不在 `api/` 下新建文件，即为**本地可裁决范围，不再逐桩重复申请**。
> 上一轮把「填桩」误判成与 U-34「新增入口」同级，导致 M6 停滞一轮；本条明确**降级**，避免重复开销。
>
> **🔎 本轮最有价值的发现（T-080 的立项依据）**：`_equipment_slots` 全工程 grep 只剩
> `preview_input_host.gd` 内部自循环，`equipment_snapshot()` **无任何 core 调用方**（只被测试调用）。
> 也就是说 T-076 三轮交付的装配能力**只是能被读写，没有被任何东西消费** ——
> 「换装后新出手读到新装配」「旧实例保留」这两条 ED-17-19 正向验收**从未被真正观测过**。
>
> 更新：2026-10-19 05:5x（**本轮自动化**：04:46/04:47 派出的 T-076 第 4 轮与 T-079 已收口 ——
> **T-079 = blocked 零产出**（诚实标出「既有标量断言 vs U-23 数组契约」冲突）、
> **T-076 第 4 轮 = 零产出静默中断**（回执无第 4 轮章节，产出 mtime 停在 04:40 早于派单 04:46）。
> 全量回归 **52 / 658 / 657 / 13598 / Failing 0 / Risky 1 / bad=0**，与权威基线**逐项一致** → 基线完好。
> 审核方裁决 **U-33**（真源 > 既有测试，授权迁移 V-074 断言）→ 重派 **T-079 第 2 轮**；
> 同时派出 **T-078**（M6 端到端八步骤）。**T-076 第 5 轮暂缓**（连续两轮零产出，待本批交付后拆细重派））
>
> 更新：2026-10-19 04:50（**本轮自动化收口**：04:10 双卡派出 → 04:31 双双收口 → 门禁
> **首轮 9 红**（`test_skill_api_sim` 0/8 + `test_ed17_repro` 1）→ 审核方机械修复 + 按既有裁定改正向探针
> → **复跑全绿 52 文件 / 658 用例 / 657 通过 / 13598 断言 / Failing 0 / bad=0** → 两卡一卡一 commit 合入）
>
> ⚠ **坑 22（本轮新增）**：CLI 落盘的 GDScript 会出现**缩进被写坏**（`_hosts = ...` 前多 61 个 tab、
> 两行多一档缩进）。症状是 `--check-only` 直接 `Expected statement, found "Indent"`。
> **编译过 ≠ 语义对**，`git diff` 对照可确定唯一正确缩进，审核方机械修复后跑门禁即可。
>
> 更新：2026-10-19 04:10（**本轮自动化复核**：HEAD 仍 `12b3c89`，工作树**零新产出**——
> T-076 第 2 轮 03:05 派出后**静默中断**，正文与回执双双未落盘，**比 T-064 中断得更早**。
> 全量回归 **51 文件 / 650 用例 / 649 通过 / 13462 断言 / Failing 0 / Risky 1 / bad=0**，
> 与上一轮权威基线**逐项一致** → 基线完好、无红灯，**本轮无卡可提交**。
> 已按 U-29 原样重派 **T-076 第 3 轮**，并**代拍 U-28**（采纳 b）派生 **T-077**，04:10 双卡并行）
>
> ⚠ **坑 20（再次实证，本轮更彻底）**：中断判定必须靠
> `tasklist | grep claude` **无进程** + **回执文件不存在** + **产出文件 mtime 未更新**三条件。
> 本轮 T-076 第 2 轮连正文都没落盘（`skill_core/**`、`tests/**` 最新 mtime 停在 02:51），
> 只靠「进程没了」会误判成「正在思考」而空等 58 分钟。
> **新固化：派单里加「进度保底」条款——宁可回执写 blocked，不可什么都不写。**

## 一、总览

| 项 | 数 |
|---|---|
| 已 PASS 并合入主干的任务卡 | **57 / 59**（本轮新增 **T-081** `save_cfg` / **T-082** `load_cfg` 填桩，**待独立审核**；审核通过后转 PASS） |
| 在跑 | **0 条** |
| 待派 | **T-073**（已解锁，**定义仍待补**）· M6 剩余：**20.1.7 / 20.1.8 端到端证据**待补 |
| 本轮已提交 | 见 `git log`：D-00-4 流程合并 + T-081/T-082 填桩 + 坑 27 修复 |
| U-28 状态 | **已由「待用户拍板」裁决为「采纳 (b)」**（自动化会话代拍板，**用户可推翻**）：先补 `create_sim` 正式入口 → 派生 T-077 已派出；(a) 留作 T-078；(c) 不采纳，**M6 口径不得因缺证据而下调** |
| 全量测试 | **55 文件 / 698 用例 / 697 通过 / 14380 断言 / FAILED 0**（T-082 后**最新基线**）；唯一 `PENDING` 为 `test_runner_host_integration` 的「打断入口不存在」（诚实标注，非失败）；**加载/解析错误 `bad=0`** |
| **runner 能力边界** | `cast` 已接：前摇/出手 tick/冷却。`timing`/`attached`/`summon`/`emission` 仍显式拒绝。`carrier` 仍只允许 `independent` |
| 门禁工具 | `gate.sh` 新增 **YELLOW/PENDING** 通道：pending≠失败，但也不计入绿，必须单独可见 |
| 里程碑 | **M0/M1 清零**、**M4 沙盒成型**；**M5 预览链路全绿**（T-050…T-054）；**M6：T-064 交付包结论 —— 20.1 八步骤完整整步证据 0/8**（1–5/7 有局部证据，3/6/8 无证据）→ **M6 尚未端到端可交付**，登记 **U-28** 待拍板 |
| ✅ 模型 | 用户 23:32 更新本地 CLI 模型配置：`ANTHROPIC_MODEL=gpt-6.1-sol`（已实测连通，额度不再打满）。**后续派单一律不带 `--model`**，用 CLI 默认模型；在跑的 T-004/T-024 仍用旧的 `gpt-6-sol`，保持不变 |

## 二、已 PASS（按完成时间）

| 卡 | 内容 | 产出 | 门禁 |
|---|---|---|---|
| T-000/001/002/003/005/020/021/022 | 接口冻结、骨架、YAML 编解码、积木目录、诊断对象、编辑器插件壳/列表/积木选择 | `skill_core/api/*`、`schema/*`、`catalog/*`、`addons/skill_editor/*` | 基线 `43b80da` |
| T-040 | 固定步长时钟 + 暂停/慢动作 + 种子 RNG | `runtime/sim_clock.gd` | 4/4 |
| T-041 | 效果体四类载体生命周期（purge 静默） | `runtime/effect_body.gd` | 7/7 |
| T-042 | 运动模式（7 种先落） | `runtime/motion.gd` | 14/14 |
| T-030 | 参数解析与合并 + 路径来源表 | `resolve/param_resolver.gd` | 3/3 |
| T-010 | V-001…V-018 身份/结构/引用 | `validate/rules/r_identity.gd` | 28/28，661 asserts（`fc46093`） |
| T-032 | 暴露字段登记 exposed_fields | `resolve/exposed_fields.gd` | 21/21，1121 asserts（`a539a8f`） |
| T-043 | 形状与判定 + hit_policy | `runtime/shape_hit.gd` | 26/26，356 asserts（`21acbe6`） |
| T-011 | V-019…V-038 类型/时间/命中/事件 | `validate/rules/r_types.gd` | 23/23，94 asserts（`123d6cf`，坑 5） |
| **T-012** | **V-039…V-069 修饰器/派生安全/被动触发** | `validate/rules/r_modifier.gd` | **41/41，756 asserts**（`4ce0969`，坑 6） |
| **T-033** | **修饰器引擎三档权限** | `modify/modifier_engine.gd` | **24/24，1433 asserts**（`4af27a7`，坑 6+7） |
| **T-044** | **结算份 parts（ED-17-01…06）** | `runtime/settle.gd` + `data/settle_meta.json` | **23/23，487 asserts**（`cd1ad30`，D-28） |
| **T-034** | **叠加运算 stack_rule（set→add→mul→clamp，从基准重算）** | `modify/stack_rule.gd` | **11/11，48 asserts**（`0089d7e`，修坑 8 后转绿） |
| **T-045** | **派生 hit/vanish + 7 原因码 + 预算（purge 静默、三代继承）** | `runtime/derive.gd` | **28/28，602 asserts**（`9d40721`） |
| **T-013** | **V-070…V-084 表现/保存/契约探针** | `validate/rules/r_present.gd` | **17/17，239 asserts**（二轮 PASS；审核方修坑 9 与素材键后转绿） |
| **T-031** | **锁定字段与覆盖拒绝 V-014** | `resolve/lock_guard.gd` | **10/10，181 asserts**（二轮 PASS；审核方修**坑 10**：素材路径含 `[i]` 与作者键是两套判据，原共用判据导致 configure 显式失败、9 条用例全红） |
| **T-046** | **防霰弹与家族登记** | `runtime/family_ledger.gd` | **9/9，157 asserts**（二轮 PASS；审核方修**坑 11**：`derive_meta.json` 的 `_note` 注释键被当成业务条目，读原文件配置必炸，已同步修 `derive.gd` 两处） |
| **T-035** | **继承开关与不可改边界 V-046/V-047** | `modify/inherit_guard.gd` | **10/10，81 asserts**（**一次绿**，全文件零硬编码字段名） |
| **T-047** | **召唤上限与归属清理** | `runtime/summon.gd` | **10/10，120 asserts**（三轮；审核方补裁定：`seq` 由账本内部分配，「最旧」= seq 最小） |
| **T-048** | **预算优先级 + debug_record 隔离** | `runtime/budget.gd` | **9/9，110 asserts**（审核方修一条测试期望算错：根拒绝也要留痕，2→3） |
| **T-014** | **诊断排序与去重** | `validate/diagnostic_sorter.gd` | **9/9，138 asserts**（**一次绿**；审核方补抽 `data/diagnostic_meta.json`） |
| **T-006** | **tick 换算与单位（秒→tick 向上取整）** | `schema/units.gd` | **27/27，126 asserts**（审核方修**坑 12**：测试里调 GUT 不存在的 `fail()` → 整脚本 Parse Error、**0 用例执行**、GUT 显示 `Nothing was run`，假绿） |
| **T-015** | **六入口编排 Validator（六阶段 × 区间注入 × 严重度聚合 × 修订号）** | `validate/validator.gd` + `tests/test_validate_stages.gd` + `tests/test_validate_integration.gd` | **一轮 10/10（68 asserts）+ 二轮 5/5（48 asserts）**；一轮全用桩**不判 PASS**，二轮四张真实卡接线；审核方反向对照发现 modifier 区间断言**恒真**（基线就带 6 条 V-053），改为「相对基线增量断言」→ 登记**坑 13** |
| **T-016** | **84 条 V 反例夹具 + 相邻合法边界** | `data/validate_fixtures.json` + `tests/test_validate_rules.gd` | **2/2，948 asserts**（三轮）；首轮 847/934 的 87 条红灯真因是 **core bug**：`r_modifier._limit()` 对素材值严格 `is int`、而 `project_limits.json` 的 `1` 是 float 1.0 → 每积木 2 条 V-053、基线永不干净。审核方修（→**坑 14**），T-012 复跑仍 41/41 无回归。**线 A 收口** |
| **T-023** | **参数表单（九列登记动态生成）** | `addons/skill_editor/ui/param_form.gd/.tscn` + `tests/test_ui_param_form.gd` | **10/10，84 asserts**（二轮；首轮 6/6 但 33 asserts 撑不起 8 条验收，不判 PASS）。审核方修两处 Parse Error（`class_name` 未进全局类缓存 → **坑 15**）；二轮补：draft 不写回、专家级展开仍锁、enum 随素材、0.0001 秒→1 tick、缺 tick_rate 显式禁用。登记 **U-21**（九列缺列补抽）、**U-22**（core 按路径查询 façade） |

## 三、在跑（CLI 后台）

### 当前批次（2 条并行，07:5x 派出，最多两条）

| 卡 | 线 | 内容 | 文件所有权 |
|---|---|---|---|
| **T-078 第 3 轮** | M6 端到端 | U-37 授权：把 `skill_api.validate` 桩接成 `Validator` 真实转发 → 取得 **20.1.3 六入口整卡校验**实际输出原文 + 依赖指纹，存档 `03-card-validation.md`；`test_m6_end_to_end` 追加 ≥2 条（**必含坑 13 非空对照**） | `skill_core/api/skill_api.gd`（**只改 `validate` 一个函数体**）+ `tests/test_m6_end_to_end.gd`（只追加）+ `delivery/m6_evidence/**` |
| **T-080** | M7 沙盒能力 | ED-17-19 **装配被真实消费**：新实例固化当前装配、旧实例参数/行为/快照三条各自不变；A 段不成就交付 A 段 + B 段 blocked | `preview_input_host.gd` + `preview_runner.gd` + `tests/test_ed17_capability.gd`（追加）+ `tests/test_ed17_repro.gd`（**只改 `test_ed17_19_*` 一个函数**）+ `data/fixtures/ed17.json`（**只改 ED-17-19 一条**） |

**文件所有权互斥、零重叠**：前者碰 `api/` 层，后者碰 `runtime/` 层 + 夹具。
**均不得新增 runner 公开方法**（`test_ed17_repro` 断言 `methods.size() == 6`）；装配走**发射上下文**，不走新 API。

**T-080 拆细理由**：沿 T-076 第 6 轮「只做一件事」的成功范式 ——
T-076 **第 2/4 轮双双零产出静默中断**，根因判定为单卡范围过大。本卡再按 A/B 两段降级：
**A 段（装配被消费）完成即可交付**，B 段（fixture 转正 + 探针转正）做不完如实 blocked。

### 历史在跑（均已收口留档）

| 卡 | 线 | 产出 | 状态 |
|---|---|---|---|
| **T-004** | M0 地基 | `skill_core/schema/cfg_schema.gd` + `tests/test_schema_structure.gd` | 10/10，92 asserts ✅ |
| **T-024** | D 编辑器 UI | `ui/diagnostic_panel.gd` + `tests/test_ui_diagnostic_panel.gd` | 8/8，99 asserts；策划/程序双视图同源、点击定位、「错误来自默认卡」只提示不复制到覆盖区 ✅ |
| **T-027** | D 编辑器 UI | `ui/preview_launcher.gd` + `tests/test_ui_preview_launcher.gd` | **7/7，39 asserts**（首跑被 00:01 写盘假红灯，重验绿）✅ |
| **T-051** | D 编辑器 UI | `ui/preview_panel.gd` + `tests/test_ui_preview_panel.gd` | **9/9，268 asserts**（审核方修**坑 17 复现**：`const Panel` 遮蔽原生类 → 改名 `PreviewPanel`）✅ |
| **T-052** | C 线 | `tests/test_ed17_repro.gd`（ED-17×24 夹具） | **24/24，947 asserts**；结论：7 条可跑 / **17 条 blocked（缺 runner 宿主适配器）**，直接催生 T-071/072 ✅ |
| **T-053** | C 线 | `runtime/run_diff.gd` + `tests/test_determinism.gd` | **13/13，342 asserts** ✅ |
| **T-061** | D+C | `runtime/presentation_bind.gd` + `tests/test_presentation_bind.gd` | **12/12，242 asserts** ✅ |
| **T-070** | 集成 | `plugin.gd` + `ui/editor_panel.gd/.tscn` + `tests/test_plugin_wiring.gd` | 在跑｜**修复「10 个 UI 模块全是孤儿脚本」** |
| **T-071** | C 线 | `runtime/hosts/host_registry.gd` + `hosts/host_cast.gd` + runner 三处改动 | 在跑｜解锁 ED-17-09/10/12/19 |
| **T-072** | C 线 | `runtime/family_ledger.gd`（改） + `tests/test_family_evade_dedup.gd` | 在跑｜修 ED-17-13：同 shot 全闪避应只 1 条 `evaded_all` |
| **T-063** | M6 | `reports/acceptance_m6.md` | 在跑｜第 20 章逐条勾选，✅ 必须能展开到 `文件::函数名` |

（T-015/016 已判 PASS；**T-023 二轮 23:30 判 PASS**，见第二节）

### 本轮（02:40）中断与红灯台账

| 卡 | 中断时点 | 落盘半成品 | 审核方处置 |
|---|---|---|---|
| **T-064** 第 1 轮 | 01:29（写完 `delivery_m6.md`，缺 `evidence_index.md` + 回执） | 正文 10897 B，质量合格 | **保留** → 派「T-064 补件」→ 补齐后 **PASS 并合入 `ceddcd0`** |
| **T-075** 第 1 轮 | 01:30（落 `preview_input_host.gd` + runner 注入 + 09 改写，无回执） | 编译全过、**GUT 1 红** | **保留** → 第 2 轮修 09 红灯（24/24 ✅）→ 但新增的 `test_ed17_capability.gd` 1/4 红 → 第 3 轮修（3/3 ✅）→ **PASS 并合入 `0482ce0`** |

**中断判定双条件**（坑 20）：`tasklist | grep claude` 无进程 **且** 回执文件不存在。
只看进程会漏判「正文已写完、回执没写」这种静默中断。

派单原文留存：`S_docs/collab/dispatch/T-xxx-派单.md`（便于额度/模型切换后原样重派）。

**验收流程（每张卡固定）**：`--check-only` 编译 → 单文件 GUT 串行 → 全量回归 → 写复核结论到 `reports/T-xxx.md` → 判 PASS 才提交（`T-xxx` 开头 commit）。

**⚠ 本轮新风险：并行会话的工作树冲突（21:36）**
T-031 会话报告：`param_resolver.gd` 出现 T-030 的未提交实现、随后被「外部操作」恢复为旧版，它刚写的 `tests/test_resolve_locked.gd` 也被删除。
同一时段 T-046 的测试文件同样失踪（只留下 `family_ledger.gd` 与回执）。
→ 结论：**三条线同时在同一工作树上写文件存在互相回滚风险**。后续改为**最多两条并行**，
并在派单里加硬条款：不得 `git checkout/clean/stash/revert`、不得删除或恢复他人文件、发现冲突立即停手并在回执里报备。

**冲突溯源（同为 WorkBuddy，21:33 自动化会话）**：上述「外部操作」是本轮汇报自动化做的隔离清理，非回滚。
当时三个 `claude -p` 进程因主模型额度耗尽被中断，留下**解析不过的半成品**（`param_resolver.gd` 缺函数体导致 T-030 既有测试 0/3；`diagnostic_sorter.gd` / `r_present.gd` / `test_validate_*.gd` 均 Parse Error），
已把 T-030 PASS 版 `param_resolver.gd` 用 `git checkout` 复位，其余半成品移到 `.workbuddy/wip-2026-10-18/`（Godot 不可见 + gitignored，可原样取回参考）。
复位后全量回归回到 **285/285 绿**。**后续不再清理在跑会话的文件，只在回执验收阶段处理。**

## 四、待派（下一步）

**在跑 2 张，待派 2 张**（04:10 刷新；T-063/064/070/071/072 均已 PASS 并合入）：

| 里程碑 | 剩余卡 |
|---|---|
| M0 地基 | —— 0（**T-004 / T-006 均已 PASS**） |
| M1 校验（线 A） | —— 0（**线 A 收口**：T-010…T-016 全绿） |
| M3 解析（线 B） | —— 0（**线 B 收口**） |
| M4 运行时（线 C） | —— 0（**线 C 收口**：T-048 已 PASS，沙盒成型） |
| M2 编辑器 UI（线 D） | —— 0（T-023…T-027 全绿） |
| M5 预览复现（线 C） | —— 0（T-050…T-054 全绿） |
| M6 表现与验收（D+C） | —— 0（T-063 / T-064 已 PASS）；**U-28 派生卡见下** |
| M7 沙盒能力扩展 | **T-076 第 5 轮（在跑，06:1x，拆细版）** · **T-080（待派，拆出的完整链路）** —— 2（T-071 / T-072 已 PASS） |
| M6 端到端（U-28 派生） | **T-077（已 PASS）** · **T-078 第 2 轮（在跑，06:1x，U-34 扩权）** —— 1 |
| M1 校验（线 A 收尾） | **T-073（待派，**已解锁**，定义待补）** —— 1；**T-079 第 2 轮已 PASS 合入** ✅ |

**当前批次（2 条并行，06:1x 派出，最多两条）**：

| 卡 | 内容 | 文件所有权 |
|---|---|---|
| **T-078 第 2 轮** | U-34 授权**新增宿主输入通道窄入口** → 真实设计卡走 20.1.1→20.1.7 + 凭据存档 | `skill_core/api/skill_api.gd`（**只增一个方法**）+ `tests/test_m6_end_to_end.gd`（新）+ `S_docs/collab/delivery/m6_evidence/**` |
| **T-076 第 5 轮** | **拆细版**：装配公共冷却 CFG 时长消费 + 两槽拒绝/冷却后成功 | `preview_input_host.gd` + `preview_runner.gd` + `data/params_meta.json` + `tests/test_ed17_capability.gd` |

**文件所有权互斥，零重叠**：前者碰 `api/` 层，后者碰 `runtime/` 层 + `data/params_meta.json`。

**T-076 拆细理由**：第 2 轮与第 4 轮**双双零产出静默中断**，判定根因为**单卡范围过大**。
第 5 轮只做**一件事**（冷却时长消费 + 两槽验收），完整生产链路与 19 条全集拆为 **T-080**。

**T-052 揭示的真实边界（决定后续排期）**：ED-17 的 24 条里 **17 条 blocked**，全部因为 runner 不接受
`cast / timing / attached / summon / emission` 五个 section，且 `carrier` 只允许 `independent`。
这不是 bug 而是**沙盒能力边界**。T-071 打开注册表通路并实现 cast；后续按「解锁条数 / 成本」排序为：
carrier 载体（self/attached，3 条）→ live 修饰与被动订阅（3 条）→ 余额度/暂停/碰撞优先级（3 条）。

## 五、素材（`res://data/`，D-22：运行期只从这里读）

`brick_catalog.json` · `relic_policy.json` · `motion_meta.json` · `validation_rules.csv`(84) · `error_messages.csv`(42)
· `identity_meta.json` · `params_meta.json`(叶 159/数组 26/对象 28/tick 15/枚举 14)
· `exposed_fields_meta.json` · `shape_hit_meta.json` · `settle_meta.json` · `presentation_meta.json`
· `project_limits.json`(硬上限，含 `_provisional`) · `item_permission_policy.json` · `protected_targets.json`
· `record_fields.json` · `validation_context_contract.json`（已登记 V-076…084 context 键 + `path_ruling.V-084`）

抽取脚本：`S_docs/collab/assets/extract_params_meta.py` · `extract_presentation_meta.py`（本轮新增，抽 presentation 60 叶 + 七段结构）

## 六、未决（不阻塞，见 02-决策台账.md）

U-09 YamlLite chomping（`>-` `|-`）· U-11 V-018 动词词表 · U-12 切句符号
· **U-14** 几何三约定（sector 全角 / line 平端 / rectangle 居中，〔推荐默认〕）
· **U-15** V-030「择一」策略落点
· **U-16** `project_limits.json` 中 `_provisional` 数值（真源 F-26「仅示例」），M5 前定稿
· **U-18** 结算运行态词表 `target_roles`（invulnerable/evade/immune），M6 前由宿主适配器契约定稿
· **U-19**（本轮新增）**项目 tick 频率**（每秒多少 tick）：真源 16.1 只说「按项目频率换算」，
  全篇**未冻结具体值**。T-006 已按「必须注入、缺失显式失败」实现（禁硬编码 60），最终值与 U-16 一并拍板
· **U-21**（T-023 新增）**九列缺列补抽**：`params_meta.json` 只有字段名/类型/单位/枚举/Schema 路径五列，
  **取值范围 / 必填 / 分级** 未登记，表单按「未登记」显式呈现（不推断、不校验）。M2 收口前由审核方补抽
· **U-22**（T-023 新增）**core 缺「按路径查询锁定/开放/来源」的只读 façade**：UI（参数表单、后续诊断面板）
  目前做展示侧路径匹配。T-025/T-026 之前补 façade，UI 改调 façade 并删掉本地匹配；在此之前**不得用于保存判定**

· **U-20**（本轮新增）**规则卡注册接口统一**：现 Validator 兼容 `configured` / `_ready` 属性判断「已 configure」，
  且 `assembly` 跨卡事实兼容 `cross_card_facts` / `assembly_facts` / `cross_card` 三个键名。M6 前冻结为 `is_configured()` + `cross_card_facts` 单一契约
已关闭：**U-13**（→D-24）、**U-17**（→D-28）

## 七、决策与坑位

- **D-22** 素材迁 `res://data/` · **D-23** V 规则字段统称以 Schema 落点为准（别名进元数据，CSV 原文不动）
- **D-24** 四种结算记录 = `enums.record`；hit/vanish/debug_record 均非合法订阅
- **D-25** 校验器不拥有解析能力，只消费已解析事实；缺 context 显式失败
- **D-26** crystal 仅 mutate_number；relic 的 live 降为 conditional（从严）
- **D-27** 严重度唯一真源是 CSV（V-050/**V-054**/V-056 警告）
- **D-28** `evadable` 缺省按有益有害补默认（有害 true / 有益 false）；无敌只让五种伤害元素视为闪避
- **D-29** V-073 两段式（Schema `minimum 0` 类型范围 ／ 启用态下界 1）· **D-30** V-084 入口区分（certify 阻止 / save 仅 notice）
- **D-31** 表现段素材与 context 契约补齐 · **D-32** 未复现红灯判定口径：存档原文 → 三连绿 + 独立 `_diag_` 断面复核 → 转加固项不判红（用于 T-034 首轮偶发红灯）
- **坑 5** 函数头丢失（第一条 `Function X not found in base self` 是真定位点）
- **坑 6** Variant 跨类型比较抛运行时错误 → GUT 记 Unexpected Errors，断言只差 1，极难看出
- **坑 7** 点语法给 Dictionary 写新键生成 StringName 键，不是 String（`has("x")` 取不到）
- **坑 9**（本轮 T-013 新踩）**JSON 解析出来的数字一律是 float**：`JSON.parse_string('{"a":1}')["a"] is int` 为 false。
  素材数值禁用 `is int` 单判（会让子检查静默不触发）；作者填进 CFG 的值才用严格 `is int`
- **坑 12**（本轮 T-006 新踩）**测试脚本里别调 GUT 不存在的方法**（`fail()` 不是 `GutTest` API）：
  解析期就抛 `Function "fail()" not found` → 整脚本加载不了 → GUT 输出 `Nothing was run`、
  **0 条用例执行**，看板上是**假绿**，比红灯危险。要制造必然失败用 `assert_true(false, "...")`。
- **坑 15**（本轮 T-023 新踩）**新增脚本的 `class_name` 不能当类型名用**：`class_name` 只在全局类缓存
  `.godot/global_script_class_cache.cfg` 里，本项目不依赖编辑器 import（实测 `SkillUnits` 缓存 0 条），
  裸类名做类型标注 → `Could not find type` → 整脚本加载不了。一律 `const X = preload(...)` 再标注
- **坑 13**（本轮 T-015 二轮新踩）**区间型断言会恒真**：断言「破坏后某规则号区间内出现诊断」时，
  若该区间在**合法输入的基线**上本就有诊断（本轮 modifier 区间基线自带 6 条 `V-053`），
  断言无论破坏与否都成立 → 测试**永远绿但没证明任何事**（同坑 12 一类假绿）。
  固定做法：先跑一次合法输入取基线，断言**只认相对基线新增**的规则号（本轮新增 `_new_in_range()` 助手）。
  审核方验收新测试时应主动做一次「合法输入反向对照」验伪（本轮用 `tests/_diag_t015_neg.gd`）。
- **坑 8**（本轮 T-034 新踩）给**显式类型变量**赋 null 抛运行时错误：`var list: Array = dict.get(k, null)`；
  它不中断脚本但让函数返回空值，下游 `result.ok` 再报一条误导性错误。**容器取值一律先声明 `Variant` 再 `is` 判定**
- **D-29**（本轮）V-073 两段式：类型/范围走 Schema（minimum 0），「启用时正整数」走启用态（`enabled_minimum_overrides`）
- **D-30**（本轮）V-084 入口区分：certify 指纹不同 → 阻止保存；save 指纹不同 → 可保存 + 「未预览」notice（真源 133，不动 CSV 严重度）
- **D-33**（本轮，T-051）**UI 三栏事件栏/结算栏分界**：事件栏只收 `enums.event`（hit/vanish），结算栏只收 `enums.record`（四值），**hit 任何情况下不得落结算栏**。派单 T-051 验收②原文作废
- **坑 18**（本轮，T-053 偏离裁决）**CLI 侧禁止使用会写 git 元数据的隔离型工具**：`isolation: "worktree"` 一类会自建 worktree/分支的参数，与 `git add/commit/checkout/stash/clean` 同列禁令。需隔离复核时改用只读检索或 `_diag_*.gd` 临时断面

---

## 八、本轮自动化验收明细（2026-10-19 00:0x，引擎执行权归本会话）

### 门禁结果（Godot 4.7.1，逐文件串行，禁 `-gdir`）

| 卡 | 编译 `--check-only` | 单文件 GUT | 判定 |
|---|---|---|---|
| T-027 试放入口 | 通过 | **7/7，39 asserts** | PASS |
| T-051 预览三栏 | 通过 | **9/9，268 asserts** | PASS |
| T-052 ED-17×24 夹具 | 通过 | **24/24，947 asserts** | PASS（夹具交付） |
| T-053 差分重跑 | 通过 | **13/13，342 asserts** | PASS |
| T-061 表现只读消费 | 通过 | **12/12，242 asserts** | PASS |

合计 **65 用例 / 1838 断言，0 红**；全量回归 **44 文件 / 574 用例 / 11699 断言，0 红**。

### 已合入（`git log`，一卡一 commit）

`9cbeaae` T-027 · `01c3b20` T-051 · `c89f676` T-052 · `0d034cc` T-053 · `7172b19` T-061

### 三项裁定要点

1. **T-051 的 U-T051-hit** → 采纳执笔方从严分离，派单原文有误，登记 **D-33**。
2. **T-052 的 `status` 口径冲突** → 收口：7 条 `ok` 由实测正式认证；**17 条 `blocked` 实测通过只证明缺口探针如实编码了当前行为，不认证对应 ED 验收通过**。ED-17-13 探针在能力补齐后**应当变红**，届时改正向验收，**不得反向改 core 恢复旧行为**。
3. **T-053 的 worktree 偏离** → `git worktree list` 仅主树、无残留，不判红，登记 **坑 18** 并固化进派单硬条款。

### 新增未决

- **U-23**（T-061）V-074 对齐落点冲突：`presentation_meta.json` 是标量别名，真源要求数组条目。**接线 T-060 表现面板前必须先清**，否则非空 anim 会被误判为数据错误。
- **U-24**（T-052）ED-17 复现缺口 17 条 → 已派生 T-071（宿主适配器注册表 + cast）、T-072（ED-17-13 霰弹去重）在跑。

---

## 九、本轮自动化验收明细（2026-10-19 01:1x–01:35，引擎执行权归本会话）

### 门禁结果（Godot 4.7.1，逐文件串行，禁 `-gdir`）

| 卡 | 编译 `--check-only` | 单文件 GUT | 判定 |
|---|---|---|---|
| T-072 家族完成判定去重 | 通过 | **14/14，209 asserts** | **PASS** |
| T-071 宿主注册表 | 通过 | **11/11，169 asserts** | **PASS** |
| T-071 cast 适配器 | 通过 | **23/23，977 asserts** | **PASS** |
| T-071 runner 集成 | 通过 | **11 通过 + 1 pending，164 asserts**，Failing=0 | **PASS**（pending 是诚实缺口标注） |
| T-070 插件组合根 | 通过 | 首轮 **5/7 红** → 修后 **7/7，28 asserts**（连跑 2 次稳定） | **PASS**（以修后版本为准） |
| T-074 ED-17 夹具迁移 | 通过 | **24/24，1054 asserts** | 夹具交付，**不判整卡 PASS** |
| T-063 M6 验收清单 | 文档卡，无需编译 | — | 交付（审计结论，非门禁证据） |

回归佐证：`test_runtime_family` 9/9·157（T-046 无回归）· `test_preview_runner` 13/13·220（T-050 无回归）· `test_schema_codec` 15/15·357（codec 改动无回归）· `test_codec_text_port` 6/6·22。

**全量权威基线：50 文件 / 647 用例 / 13375 断言 / Failing 0**（约 2m41s）。

### 一卡一 commit

`9901727` T-072 · `00f94aa` T-071 · `598e322` T-070 · `0a06d51` T-063 · `69727dc` T-074 · `ac93a65` UI 补强

### T-070 两条红灯的真因（独立断面 `tests/_diag_t070.gd` 实测）

1. `options.handlers` 传 `[]` → launcher 要求 **explicit dictionary**，拒绝正确（T-027 既有契约）。
2. `codec.encode()` 对**顶层第八个键** `unknown_field` 返回空串 → 七键 CFG 铁律拒绝正确。
→ 两条都是**测试夹具与既有契约不符**，非 core 缺陷。修法把未知键移入 `params`（自由 map），断言未放松 → 采纳，裁决 **U-27**。

### 三项新登记

1. **U-27（已裁决）** CFG 未知键落点：顶层严格七键、七键外一律拒绝；`params` 为自由 map，作者自定义/未知嵌套键在 `params` 内保留并可往返。
2. **U-25（关闭）** `CfgCodec` 此前只有文件 I/O 入口，UI 接线无法通过 `save_flow.configure()` 的方法名探测 → T-070 补上纯文本层（`parse_text`/`encode`/`last_error`，+30 行纯增量），无回归。
3. **坑 19** 门禁窗口内文件被并发改写 → 单文件结论与全量结论打架。判门禁前必须核对 mtime 并复跑。

### ⚠ 偏离：T-070 回执声明与事实不符

回执写「没有修改任何 `skill_core/**`」，实测改了 `cfg_codec.gd`（+30 行）。改动有益且零回归，**不回滚**，但登记为审核方不信任项：后续卡回执必须如实列出所有触碰文件。

---

## 十、本轮自动化验收明细（2026-10-19 04:0x–04:1x，引擎执行权归本会话）

### 1. 工作树体检：零新产出，判定 T-076 第 2 轮静默中断

| 检查项 | 结果 |
|---|---|
| `git log --oneline -1` | HEAD 仍 `12b3c89`（台账：U-29 裁决 + T-076 第 2 轮派单） |
| `git status --short` | 与上一轮**完全一致**，无新增未跟踪文件（历史残留仍是旧派单/素材/`.uid`） |
| `tasklist \| grep claude` | **无进程** |
| `S_docs/collab/reports/T-076.md` | **无第 2 轮章节**（mtime 停在 03:00，仍只有第 1 轮） |
| `skill_core/**/*.gd` + `tests/*.gd` | **最新 mtime 02:51**，03:05 之后零写入 |

→ **坑 20 三条件全中：静默中断，且中断点在正文落盘之前**（比 T-064 更早，T-064 至少留下了 `delivery_m6.md`）。
本轮因此**没有新代码可门禁**，改为「先复核基线、再重派」。

### 2. 全量回归（51 文件串行，2m33s，禁 `-gdir`）

```
FILES=51 TESTS=650 PASSING=649 ASSERTS=13462 FAILING=0 RISKY=1 BAD_LOAD=0
```

与上一轮权威基线（51 / 650 / 649 / 13462 / 0 / 1 / 0）**逐项一致**，七项零回归指标全部命中：

`test_runtime_derive` 28/28·602 · `test_ed17_repro` 24/24·1065 · `test_ed17_capability` 3/3·76 ·
`test_runtime_settle` 23/23·487 · `test_runtime_family` 9/9·157 · `test_preview_runner` 13/13·220 ·
`test_runner_host_integration` 11+1pending·164。

唯一 `Risky/Pending` 是 `test_runner_host_integration` 的「打断入口不存在」诚实标注，
**Failing=0，不是红灯**（单列通道，不计绿也不计红）。

→ **基线完好 → 本轮无红灯 → 无卡可提交**（不为空转凑 commit）。

### 3. 本轮两项裁决（用户未在线，按授权代拍板，均登记进 `02-决策台账.md`）

| 编号 | 内容 | 去向 |
|---|---|---|
| **U-28** | M6 端到端 0/8 → **采纳 (b)**：先把 `create_sim` 做成真实入口；(a) 留作 **T-078**；(c) **不采纳**（M6 口径不得因缺证据下调） | 派生 **T-077**，04:10 派出 |
| **U-30** | 开放 `skill_core/api/skill_api.gd` 写权限（T-000 冻结，需申请）—— 只准把两个桩实现为真实转发，**签名与返回包形状一字不动**，其余 10 个桩保持原样 | T-077 派单硬条款 |

**U-30 的裁定逻辑**（供用户复核）：冻结冻结的是**契约**（签名 + 包形状），不是「永远是桩」。
把桩接线到既有 PreviewRunner 能力**既不改契约也不改语义**，不构成协议第 134 行的
「改变已冻结数据契约」，因此属本地可裁决范围，**不必升级到用户**。

### 4. 本轮派出（2 条并行，04:10，最多两条）

| 卡 | 内容 | 文件所有权 |
|---|---|---|
| **T-076 第 3 轮** | 零产出静默中断后**原样重派**（内容等同第 2 轮，U-29 扩权照用）：补 ED-17-19 原子换装 + 装配公共冷却 | `derive.gd` + `hosts/*` + `preview_runner.gd` + `tests/test_ed17_*.gd` |
| **T-077**（新） | `SkillApi.create_sim`/`step_sim` 真实生产入口 + 正式/预览双入口同夹具差分（U-28 步骤 6 的 S6a/S6b 证据） | `api/skill_api.gd` + `tests/test_smoke.gd` + `tests/test_skill_api_sim.gd` |

**零重叠**。两条派单均新加**「进度保底」条款**（本轮实证产物）：
> 预计写不完时**优先保证回执落盘**。宁可回执写 blocked，不可什么都不写。

**落盘纪律**（T-077）：CFG 落盘一律走 `user://t077/`，**禁止在 `res://` 下新建 CFG**
（会连带产生 `.import` / `.uid` 未跟踪文件，污染工作树）。

### 5. 门禁收口（04:31 CLI 双双收口后，引擎归本会话串行跑）

**首轮：9 条红灯**

| 文件 | 首轮 | 真因 |
|---|---|---|
| `tests/test_skill_api_sim.gd`（新） | **0/8 红** | 夹具 CFG 里 `params.unknown_nested` 触发 **V-019 未登记附加键**（见 **U-32**） |
| `tests/test_ed17_repro.gd` | **23/24 红 1** | `test_ed17_19_*` 末条「方法清单快照」断言因 T-076 新增四个装配窄入口而变 —— **既有裁定已预见：探针应当变红，改正向断言，不得反向改 core** |
| `skill_api.gd` / `preview_runner.gd` / `derive.gd` | **编译红** | `Identifier not found: DiagnosticScript`＋**两处缩进被写坏**（**坑 22**） |

**审核方三处机械修复**（均非设计改动，`git diff` 可对照出唯一正确形态）：

1. `skill_api.gd`：函数体内 `const X = preload(...)` 在嵌套 lambda 里解析不到 →
   **提升到脚本级**（与 `preview_runner.gd` 既有写法一致）；`DiagnosticScript.new()` → `Diagnostic.new()`。
   **签名与返回包形状一字未动**，符合 U-30。
2. `preview_runner.gd` `_hosts = ...` 前 **61 个多余 tab** → 还原为 1 个；
   `derive.gd` 两行多一档缩进 → 还原。
3. `test_skill_api_sim.gd`：`_cfg()` 去掉 `unknown_nested`（schema-clean 给 `create_sim`），
   U-27 保留断言改挂到**独立的 codec 往返探针** `persist_cfg` 上（U-32 分层）。

**复跑：全绿**

```
FILES=52 TESTS=658 PASSING=657 ASSERTS=13598 FAILING=0 RISKY=1 BAD_LOAD=0
```

较基线（51 / 650 / 649 / 13462）+1 文件、+8 用例、+8 通过、+136 断言，**Failing 仍为 0**。

### 6. U-28 取得第一份实测证据（步骤 6「正式复现」）

```
T077 first difference result: { "ok": true, "equal": true, "first_diff_index": -1, "path": "", "left": <null>, "right": <null>, "error": "" }
```

正式入口（`save_cfg`→`load_cfg`→`create_sim`）与预览入口（直接 `PreviewRunner.start`）在
**同夹具、同 seed** 下两条 6 样本 trace **完全相等**。此前该步为「无证据」，现已取得实测。

**但 U-28 不因此关闭**：八步骤的**完整整步流水线**仍是 **T-078** 的活；M6 口径不下调。

### 7. 本轮新登记

- **U-32** `params` 的「自由 map」**只在 codec 层成立**，schema 层（V-019）仍拒未登记键 ——
  走 schema 的入口（`PreviewRunner.start`、`SkillApi.create_sim`）**不会放行**未登记 `params` 键。
- **坑 22** CLI 落盘的 GDScript 会出现缩进被写坏；`--check-only` 才能发现，编译过 ≠ 语义对。
- **U-23 已裁决**（以真源数组契约为准，派生 **T-079**）；T-073 解锁条件改为「须先交付 T-079」。

---

## 十一、本轮自动化验收明细（2026-10-19 05:5x，引擎执行权归本会话）

### 1. 工作树体检：两卡收口，一 blocked 一静默中断

| 检查项 | 结果 |
|---|---|
| HEAD | `829e420`（T-079 派单，04:48） |
| `tasklist \| grep claude` | **无进程**（两卡均已收工） |
| `skill_core/**` + `tests/**` 最新 mtime | **04:40**（早于 04:46/04:47 派单时间）→ **本批零代码产出** |
| `reports/T-079.md` | 04:49 落地，**完整 blocked 回执** |
| `reports/T-076.md` | 04:44，章节只到第 3 轮复核，**无第 4 轮内容** |

**判定**：

- **T-079 = blocked 成立**（零产出但回执完整、诚实、未留半成品）—— 执笔方处置**正确，不判 REJECT**。
- **T-076 第 4 轮 = 零产出静默中断**（**坑 20 三条件全中**：无进程 + 无回执 + mtime 未更新）。
  这是该卡**第 2 次**零产出中断（第 2 轮同样）。

### 2. 全量回归（52 文件串行，2m39s，禁 `-gdir`）

```
files=52 tests=658 passing=657 asserts=13598 failing=0 risky=1 bad=0
```

与上一轮权威基线（52 / 658 / 657 / 13598 / 0 / 1 / 0）**七项逐项一致** → **基线完好、无红灯**。
本批**无新代码产出**，故无 `--check-only` 与单文件 GUT 对象，**本轮无卡可合入**（不为空转凑 commit）。

### 3. U-33 裁决：T-079 的冲突，是「测试迁移」不是「契约让步」

**冲突本体**：既有 `tests/test_validate_present.gd:104-113` 的 V-074 用例断言**标量**落点
（`logic_release_tick` / `release_frame`），与 U-23 裁定的**数组**契约直接冲突，
而 T-079 未被授权改这个文件。

**审核方复核真源**：`S_docs/技能系统书-v1.md:3889` 明写
`presentation.anim.alignments[i].shot_tick`、`presentation.anim.alignments[i].frame` ——
**数组是唯一真源口径**，U-23 裁决无误。

**裁定（登记 U-33）**：

| 条 | 内容 |
|---|---|
| 1 | 权威层级：真源 > 素材抽取物 > **既有测试**。U-23 已判标量形态「作废」，该断言**不是需保护的回归契约，而是待迁移的旧断言** |
| 2 | **扩权**：授权改 `tests/test_validate_present.gd`，**仅限 V-074 那一个用例**，其余 16 条一字不动 |
| 3 | 验收强度**不得降低**：仍覆盖缺失/非法/齐全三档，落点改为数组与`[i]`实际条目 |
| 4 | 断言数基线**允许变化**（239 含旧标量断言，**不是冻结契约**），回执须报迁移前后两个数 |
| 5 | 沿用**坑 13**：`_no_rule` 类断言**必须配非空对照**，杜绝空集合恒真 |
| 6 | **禁止反向放宽**：不得为保绿保留标量别名或让 V-074 对旧标量放行 |

**该裁决不升级给用户**：U-23 本身已按真源裁定，本次只是解决**执行层面的冲突**，
不改变方向、不改已冻结数据契约（七键 / 十二字段 / 四类载体 / 两事件），属本地可裁决范围。

### 4. 本轮派出（2 条并行，05:5x，最多两条）

| 卡 | 内容 | 状态 |
|---|---|---|
| **T-079 第 2 轮** | V-074 数组契约落地 + U-33 授权的既有断言迁移 | 已派 |
| **T-078** | M6 端到端：同一张真实设计卡走 20.1.1→20.1.7 + 运行凭据存档 | 已派 |

**T-076 第 5 轮暂缓**：连续两轮零产出，提示**单卡范围过大**。下一轮**拆细**为
「装配公共冷却 CFG 时长消费 + 两槽拒绝/冷却后成功」单项，完整链路与 19 条正向验收再拆一张。

### 5. 本轮提交

`df18f4c` T-079 第 2 轮派单 + U-33 裁决 · `d67b96a` T-078 派单

### 6. 需用户复核（自动化会话代拍板，均可推翻）

1. **U-33**（本轮新）：既有测试断言让位于真源契约。**风险低**（真源明写数组），但改变了
   「既有绿灯即契约」的默认认知 —— 若用户认为**既有测试不可动**，请推翻，则 U-23 需重裁。
2. **T-076 暂缓 + 拆细**：M7 沙盒扩展让位于 M6 端到端。若用户认为 ED-17-19 原子换装优先级更高，可调回。

---

## 十二、本轮第二批验收明细（2026-10-19 06:0x–06:1x，引擎执行权归本会话）

### 1. T-079 第 2 轮：**PASS 并合入**（`6ce743b`）

**门禁（Godot 4.7.1）**：

| 项 | 结果 |
|---|---|
| `--check-only` 编译（3 个脚本） | **全过，一次通过**（坑 22 **未复现**） |
| `test_validate_alignment`（新） | **12/12，425 asserts** |
| `test_validate_present`（迁移后） | **17/17，248 asserts**（239 → 248） |
| `test_ui_presentation_panel` | 7/7，240（239 → 240） |
| `test_presentation_bind` | 12/12，242 |
| `test_validate_rules` | 2/2，**947**（948 → 947） |
| `test_validate_integration` | 5/5，48 · `test_validate_stages` 10/10，68 |
| **全量回归** | **53 / 670 / 669 / 14032 / Failing 0 / Risky 1 / bad=0**（+1 文件 +12 用例 +434 断言，**零回归**） |

**U-33 六条核验**：`git diff -U0` 只有 **1 个 hunk**（`@@ -107,7 +107,13 @@`），
其余 16 条**零改动**；验收档位 **4 档 → 6 档**（新增「空数组」档，强度**提升**）；
`_no_rule` 配了非空对照（坑 13 未犯）；未保留塌缩别名、旧标量非空 anim **确实**变为阻止保存。

**断言数新基线**：`test_validate_present` **248** · `test_validate_rules` **947** · `test_ui_presentation_panel` **240**。
**U-23 执行完毕，T-073 解锁。**

### 2. T-078 首轮：**blocked 成立**（`d3c3c19`，文档合入）

七步 **0/7**，但**停手理由真实且有价值** —— 静态反证指出 `create_sim` **没有宿主输入通道**：
`skill_api.gd:126–133` handlers 全绑 `_unsupported_part`（返回 false）、`:149–154` options 固定
`targets: []` / `derivation_bindings: {}`。因此正式入口**物理无法产生非空结算栏**，
M6 的「三栏非空 + 双入口同条件差分」不可达。
未建空占位凭据、未留已知红灯测试 → **判 blocked 成立，不判 REJECT**。

### 3. U-34 裁决：`api/**` 冻结扩权（T-078 第 2 轮专用）

沿用 U-29/U-30 的「**只增不改建**」口径：允许**新增**一个窄入口透传宿主输入，
❌ 禁改既有 `create_sim(cfg, seed)` 签名一字、❌ 禁改返回包形状、❌ 禁在 `api/` 下新建文件。
理由：冻结冻结的是**契约**，不是「永远只有这些方法」；新增方法对既有调用方**零影响**，
不构成「改变已冻结数据契约」，属本地可裁决范围。

### 4. U-35（未决）`frame` 校验期与消费期的整数口径断层

派单要求数值型（允许 0.5），`presentation_bind.gd:154–157` 运行时要求整数。真源未冻结。
→ 登记未决，**不阻塞 T-079 PASS**；**统一前不得依赖 fractional frame 可运行**。

### 5. 本轮第二批派出（2 条并行，06:1x）

**T-078 第 2 轮**（U-34 扩权 + 七步流水线）· **T-076 第 5 轮**（拆细版单项）。
零重叠：前者 `api/` 层，后者 `runtime/` 层 + `data/params_meta.json`。

### 6. 需用户复核（自动化会话代拍板，均可推翻）

1. **U-33**：既有测试断言让位于真源契约。**风险低**（真源 `:3889` 明写数组），但若用户认为
   **既有绿灯即契约、不可动**，请推翻 → U-23 需重裁。
2. **U-34**：给冻结的 `api/` **新增**一个公开方法。既有签名一字未动，但 API 面**扩大了**。
   若用户认为 `api/` 应严格只减不增，请推翻 → M6 端到端将承认「正式入口无宿主输入通道」为能力边界。
3. **T-076 拆细 + 暂缓完整链路**：若 ED-17-19 优先级更高可调回。
4. **U-35** 未决：`frame` 是否取整数（建议与运行时对齐）。
5. **U-36**：tick 字段数快照 15→16 让位于合法登记（与 U-33 同款，见下节）。
6. **U-37**（本轮新增，07:4x）：**既有 `_not_implemented` 桩 → 真实转发不构成改契约**。
   冻结的是**契约**（签名 + 返回包形状），不是「函数体必须永远是空壳」。
   API 面**零扩大**（比 U-34 更保守），风险低于前项；但认定上推翻了上一轮
   「填桩需同级别扩权」的判断 —— 若用户认为 `api/` 连函数体都不可填，请推翻 → M6 的 20.1.3/20.1.4
   将长期拿不到运行凭据。本条与 U-34 同类，**建议并行复核**。

---

## 十三、本轮第三批（2026-10-19 06:2x–06:4x，引擎执行权归本会话）

### 1. T-078 第 2 轮：**PASS（增量落地，整卡仍 blocked）** —— `d3fa67e`

| 项 | 结果 |
|---|---|
| `--check-only` | `skill_api.gd` / `test_m6_end_to_end.gd` **两个全过** |
| `tests/test_m6_end_to_end.gd`（新） | **3/3，30 asserts，0.768s，bad=0** |
| **全量回归** | **54 文件 / 673 用例 / 672 通过 / 14062 断言 / Failing 0 / Risky 1 / bad=0** |

**U-34 核验**：`git diff --stat skill_api.gd` = **+99 行、0 删除**（纯新增），
既有 `create_sim(cfg, seed)` **一字未动**；`hosts` 走入口参数、未写回 CFG；handler 按 `enums.part_type` 全量预检（坑 21 未犯）。

**实测突破**（本轮最有价值）：集成测试证明**宿主输入通道真的能产生非空三栏** ——
第 1 轮 blocked 的物理阻塞点**已解除**。

### 2. M6 运行凭据落盘（`9741290`，审核方实测）

抓取 `test_m6_end_to_end` 的实际打印输出，三份凭据**已取得真实运行原文**：

| 凭据 | 实测内容 |
|---|---|
| [05-preview](delivery/m6_evidence/05-preview.md) | 三栏**分别非空**：events 1（`hit`）/ records 1（`hit_settled`，parts value 2.5）/ debug 1（`budget_drop`）。D-33 分界正确（hit 在事件栏、hit_settled 在结算栏） |
| [06-formal-replay](delivery/m6_evidence/06-formal-replay.md) | 正式/预览双入口 **`equal=true`、`first_diff_index=-1`**；两入口指纹**同为** `5d2d40ff…`，交叉验证通过 |
| [07-rerun](delivery/m6_evidence/07-rerun.md) | **非空破坏对照**：改 `amount` 后 **`equal=false`、`first_diff_index=0`、`path=trace[0].fingerprint`**，左右指纹实际不同 → 证明「相等」非空集合恒真 |

**U-28 状态更新**：M6 端到端「完整整步证据」由 **0/8 → 约 4/8**
（步骤 5 预览 ✅、步骤 6 正式复现 ✅、步骤 7 差分 ✅、步骤 10 指纹绑定 ✅）。
**M6 口径不下调** —— 剩余步骤 1（编辑器填卡接线）、2（控件→validator）、3（六入口整卡，`validate` 仍为桩）、
4（编辑器 API 保存重开）、8（人审核）**仍未取得证据**。

### 3. T-076 第 5 轮：**blocked 成立**，已由 U-36 解锁续派

完成全部设计后被 `tests/test_validate_types.gd:82` 的 `found.size() == 15` 卡住
（新增合法 tick 字段后为 16）。**逐处精确撤回**（Edit，未用 `git checkout`）、
保留 WIP-1~5 全部设计、主动披露隔离工具误调用（`isolation: remote`，已立即停止）。
审核方核验 `git worktree list` / `git branch`：**无残留、分支干净**。

**U-36 裁决**（与 U-33 同款）：**素材登记的合法性 > 既有测试的条数快照**。
授权登记 `params.assembly_shared_cooldown_ticks` + **仅** `:82` 的 15→16。
❌ 禁止为维持 15 而漏登记 `tick_fields`、删旧字段、改 V-021 语义。

**已派 T-076 第 6 轮**（`ea2c0ec`）。

### 4. 本轮固化的两条方法论

1. **「X 数量的既有断言 vs 合法新增」冲突**（本轮出现**两次**：U-33 的 V-074、U-36 的 tick 15→16）→
   统一按**权威层级**处理：真源/素材登记的合法性 > 既有测试的**条数快照**。
   前提是新增本身合法（真源要求或真源未禁），且**不许反向改生产行为迁就旧条目数**。
2. **诚实 blocked + 精确撤回 + 主动披露偏离** → 判「blocked 成立」，**不判 REJECT**（T-078 首轮、T-076 第 5 轮双实证）。
   撤回用 Edit 逐处还原、不用 `git checkout`，可避免误伤并行会话的改动。

---

## 十四、本轮第四批（2026-10-19 06:3x，引擎执行权归本会话）

### 1. T-076 第 6 轮：**PASS** —— `3c5c225`

| 项 | 结果 |
|---|---|
| `--check-only`（4 个脚本） | **全过**（坑 22 未复现） |
| `test_ed17_capability` | **5/5，230 asserts**（既有 3 条 + 新增 2 条；与执笔方静态预估**完全一致**） |
| `test_validate_types` | 23/23，94（15→16 后仍绿）· `test_ed17_repro` 24/24·1065 · `test_runtime_derive` 28/28·602 |
| **全量回归** | **54 / 675 / 674 / 14219 / Failing 0 / Risky 1 / bad=0**（+2 用例 +157 断言） |

**U-36 核验**：`git diff -U0 tests/test_validate_types.gd` **只有 1 个 hunk**（`@@ -82 +82 @@`，15→16，注释未动）；
两份 `params_meta.json` 各 2 处登记（leaves + tick_fields）且一致。

### 2. ⚠ **坑 23**（本轮新增）：素材登记数的快照断言**分散在多个测试文件**

首轮全量跑出 **1 条红灯**：

```
test_schema_units: [Failed] [16] expected to equal [15]:
                   the currently deployed metadata registers 15 fields
```

**真因**：`tests/test_schema_units.gd:88` 有**同款**快照断言，U-36 派单只授权改 `test_validate_types.gd`
—— **是审核方派单的遗漏，不是执笔方实现问题**。

**处置**：按 U-36 同款裁定机械修复 15→16（文案同步），**未改生产行为、未反向删登记**，复跑全绿。

**固化**：改素材登记（尤其 `tick_fields` 这类**会被多处计数**的清单）时，
**必须全量 grep 找齐所有快照断言**，不能只改派单点名的那一个文件。同理 U-33/U-36 类扩权，
派单应写「如其他测试文件存在同款快照断言，一并列出待审核方确认」，而非只点名一个文件。

### 3. 本轮四项待用户复核

| 编号 | 内容 | 风险 |
|---|---|---|
| **U-33** | 既有测试断言让位于真源契约（V-074 标量→数组） | 低（真源 `:3889` 明写数组） |
| **U-34** | 冻结的 `api/**` **新增**一个公开方法（既有签名一字未动，但 API 面扩大） | 中 |
| **U-36** | tick 字段数快照 15→16 让位于合法登记 | 低（真源 `:6891` 要求时长入 CFG） |
| **U-35** | 未决：`frame` 是否取整数（建议与运行时对齐） | 低 |

另有 **T-076 拆细**（完整链路拆为 T-080）为排期决策，可调回。

---

### 坑 27（2026-10-19 09:4x，环境级）测试内自定义类与全局 `class_name` 撞名 → 干净环境整文件不执行

**症状**：新克隆 + 首次 `--import` 后，`test_plugin_wiring.gd` 报
`SCRIPT ERROR: Parse Error: Class "PreviewRunner" hides a global script class.`，
GUT 侧只说 `Ignoring script ... because it does not extend GutTest` + `Nothing was run`，
**7 个用例整体消失**，而 gate 汇总只体现为 `FAILED: test_plugin_wiring.gd` 一行。

**真因**：该文件第 18 行 `class PreviewRunner extends RefCounted:` 与
`skill_core/runtime/preview_runner.gd` 的 `class_name PreviewRunner` 同名。
GDScript 规则：内部类不得遮蔽全局脚本类。旧环境未暴露，是因为 `.godot/global_script_class_cache.cfg`
的建立顺序先于该文件被解析 —— **缓存掩盖了非法写法**。

**处置**：改名 `WiringPreviewRunner`（仅测试夹具，零生产行为变更）。

**固化**：
1. 测试里的假对象命名统一带 `Wiring` / `Fake` 前缀，禁止与 `skill_core/**` 的 `class_name` 同名。
2. **换环境（新克隆、清 `.godot`、换机器）必须整套复跑** —— 同一份代码在旧缓存下绿、在干净环境下红，
   是本项目已知的高频假绿来源（坑 11 / 坑 23 同族）。
3. 看到 `does not extend GutTest` 先查 Parse Error，别当成「测试基类写错」。
