# 开发进度看板（WorkBuddy 维护，每次汇报刷新）

> 引擎：Godot **4.7.1**（`Ryko.GodotHub/godot-versions/4.7.1-stable`）｜门禁归 WorkBuddy 独占，Claude CLI 只写代码
> 更新：2026-10-19 02:40（**本轮自动化复核**：T-064 / T-075 第 1 轮双双中断于 01:29–01:30，
> 审核方复核后**保留有价值半成品**并派出第 2 轮；全量回归 **50 文件 / 647 用例 / 13364 断言 /
> Failing 1**（T-075 半成品 ED-17-09 红灯）→ **红灯不提交**，HEAD 仍 `77bb3c5`）
>
> ⚠ **坑 20（本轮实证）**：CLI 中断后留下的半成品「**能编译、但红**」——
> `--check-only` 全过、GUT 却在运行时红。`--check-only` 通过 ≠ 门禁通过，**必须跑 GUT 才能判**。
> 另：中断判定靠 `tasklist | grep claude` **+ 回执文件是否存在**双条件，只看进程会漏判「写完正文却没写回执」。

## 一、总览

| 项 | 数 |
|---|---|
| 已 PASS 并合入主干的任务卡 | **52 / 54**（本轮新增 **T-064** 纯文档卡 `ceddcd0`、**T-075** ED-17 生产接口 `0482ce0`） |
| 在跑（CLI 后台，02:58 派出） | **1 条**：**T-076** ED-19 装配公共冷却 + 原子换装补齐（T-075 明确遗留的真实缺口） |
| 待派 | T-073（U-23 结构校验接 validator，**须先裁 U-23**）；**U-28**（M6 端到端 0/8）裁完后重算 M6 剩余卡 |
| 本轮已提交 | `ceddcd0` **T-064** 交付证据包 · `0482ce0` **T-075** ED-17 生产接口（三轮收口）。**红灯期间一律未提交** |
| 全量测试 | **51 文件 / 650 用例 / 649 通过 / 13462 断言 / FAILED 0**；唯一 `PENDING` 为 `test_runner_host_integration` 的「打断入口不存在」（诚实标注，非失败）；**加载/解析错误 `bad=0`** |
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

**剩余 15 张**（其中 2 张在跑，13 张待派）：

| 里程碑 | 剩余卡 |
|---|---|
| M0 地基 | **T-004（在跑）** —— 1（**T-006 已 PASS**） |
| M1 校验（线 A） | —— 0（**线 A 收口**：T-010…T-016 全绿） |
| M3 解析（线 B） | —— 0（**线 B 收口**） |
| M4 运行时（线 C） | —— 0（**线 C 收口**：T-048 已 PASS，沙盒成型） |
| M2 编辑器 UI（线 D） | —— 0（T-023…T-027 全绿） |
| M5 预览复现（线 C） | —— 0（T-050…T-054 全绿） |
| M6 表现与验收（D+C） | **T-063（在跑）**、T-064（待派，依赖 T-070） —— 2 |
| M7 沙盒能力扩展（新增） | **T-071 / T-072（在跑）** —— 2 |

**当前批次（4 条并行，00:12 派出）**：T-070 宿主接线 · T-071 适配器注册表+cast · T-072 霰弹去重 · T-063 验收清单。
文件所有权互斥：`plugin.gd`+`editor_panel.*` / `preview_runner.gd`+`hosts/*` / `family_ledger.gd` / 纯文档，零重叠。

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
