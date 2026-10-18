# 01 · WBS 任务拆解（技能编辑器）

> 版本：v1.0　日期：2026-10-18　第 1 轮
> 执笔：WorkBuddy　执行：本地 Claude CLI　审核：WorkBuddy　拍板：用户
> 真源：`S_docs/技能系统书-v1.md`｜素材：`S_docs/collab/assets/`
> 状态：任务卡为派发依据；未标 PASS 的任务不代表已实现。

---

## 一、里程碑与并行线

| 里程碑 | 目标（一句话） | 完成判据 | 并行线 |
|---|---|---|---|
| **M0 地基** | 目录、YAML 契约、积木目录、诊断对象可跑 | `gut` 能跑；CFG 往返无损（ED-16-01） | A |
| **M1 校验** | V-001…V-084 全部可实现且可定位 | 84 条各有触发反例 + 相邻合法边界 | A |
| **M2 编辑器 UI** | Godot 面板能填卡、看诊断、保存、重开 | 走通 20.1 端到端前四步 | D |
| **M3 解析与修饰** | 确定性展开 + 三档权限修饰器 | 覆盖规则生效顺序 set→add→mul→clamp | B |
| **M4 运行时沙盒** | 技能真能跑：运动/命中/结算/派生/终止 | ED-17-05…08、12…15 通过 | C |
| **M5 预览复现** | 固定种子初态可复现、可差分 | ED-17-01…24 全通过 + 重跑一致 | C |
| **M6 表现与验收** | 七段表现只读消费 + 20 章清单收口 | 可勾选清单全勾 | D/C |

**四条并行线**：A 数据与校验 · B 解析与修饰 · C 运行时与预览 · D 编辑器 UI

### 依赖顺序

```
T-000 冻结核心接口  ←── 必须先 PASS，否则四条线不能并行
   │
   ├── T-001…006 (M0, 线A)
   │       │
   │       ├── T-010…016 (M1, 线A)
   │       │        └── T-020…027 (M2, 线D) ← 可用 api 桩先行
   │       └── T-030…035 (M3, 线B)
   │                └── T-045 派生预算 / T-033 live 权限
   └── T-040…048 (M4, 线C)
            └── T-050…054 (M5, 线C)
                     └── T-060…064 (M6, 线D+C)
```

---

## 二、M0 · 地基与契约（线 A）

| ID | 任务 | 依赖 | 产出 | 验收标准 |
|---|---|---|---|---|
| **T-000** | **冻结核心接口**：定义 `skill_core/api/` 的全部对外函数签名（加载/保存/校验/解析/施放/查询）、目录树、错误返回结构 | 无 | `res://skill_core/api/skill_api.gd`（接口声明 + 空实现桩）+ 本协议第三节目录树落地 | ①四条线读同一份签名即可开工；②core 内无任何编辑器 API 引用；③**此任务 PASS 前不得并行** |
| T-001 | 仓库与骨架：git init、`.gitignore`、`res://` 目录树、GUT 跑通一个空测试 | T-000 | 目录 + `tests/test_smoke.gd` | `gut` 命令有通过输出；headless 下可执行 |
| T-002 | `cfg_codec.gd`：UTF-8 YAML 读写 | T-000 | `skill_core/schema/cfg_codec.gd` | 往返一致（ED-16-01）；拒收重复键/自定义标签/隐式布尔/非有限数字；`null` 仅在声明 nullable 时合法；空数组≠缺失 |
| T-003 | 积木目录加载：从 `brick_catalog.json` 载入 28 块 | T-000 | `skill_core/catalog/brick_catalog.gd` + `data/bricks/brick_catalog.json` | 按 `brick_id` 建键；可按 carrier/status 过滤；候选积木可被列出但标记为不可导出（V-012） |
| T-004 | Schema 结构校验：七键、十二字段卡、七表现段、类型/枚举/必填/附加键 | T-002,T-003 | `skill_core/schema/cfg_schema.gd` | 少一个顶层键报错；多一个顶层键报错；`bricks[i]` 少任一字段定位到实际槽位（V-013 展开为 12 个槽位） |
| T-005 | 诊断对象 + 文案注入 | T-000 | `skill_core/validate/diagnostic.gd` | `Diagnostic{rule_id, code, severity, path, actual, expected, hint}`；42 条 E 文案按 ID 注入并填占位；「未填写」与「空列表」渲染不同 |
| T-006 | tick 换算与单位 | T-000 | `skill_core/schema/units.gd` | 秒→tick 按项目频率换算并向上取整；界面可提交秒但落盘只存整数 tick（真源 16.1） |

---

## 三、M1 · 校验器（线 A，四条可再并行）

> 素材：`assets/validation_rules.csv`（84 条）、`assets/error_messages.csv`（42 条）、真源第 14 章

| ID | 规则组 | 产出 | 验收标准 |
|---|---|---|---|
| T-010 ✅ | V-001…V-018 身份、结构、引用 | `validate/rules/r_identity.gd` + `validate/identity_meta.gd` | 每条有触发反例；`bricks[i].author_params` 缺失定位到 `bricks[2].author_params` 而非「参数对象」｜**2026-10-18 PASS**：28/28（661 asserts），全量 88/88；复核方补 D-22（素材迁 `res://data/`）、D-23（U-10 落点裁决） |
| T-011 ✅ | V-019…V-038 类型、时间、命中、事件 | `validate/rules/r_types.gd` | tick 规则不只检查前摇/冷却/寿命三个名字，而是「单位为 tick 且类型为整数的每个实际字段」都生成检查实例｜**2026-10-18 PASS**：23/23（94 asserts），全量 158/158；复核方修一处函数头丢失（坑 5）|
| T-012 | V-039…V-069 修饰器、派生安全、被动触发 | `validate/rules/r_modifier.gd` | V-056 是警告不是阻止保存；缺预算/负预算/越权放大代数是阻止保存（真源 14.4 末段） |
| T-013 | V-070…V-084 表现、保存、契约探针 | `validate/rules/r_present.gd` | V-084 只阻止「把旧预览认证为当前定义」，合法 CFG 仍可保存但标「未预览」 |
| T-014 | 诊断排序与去重 | `validate/diagnostic_sorter.gd` | 阻止保存→警告→提示；同严重度按表单顺序与数组下标；末以规则 ID 破同分；**不得按异步返回顺序乱跳** |
| T-015 | 六个校验入口编排（填写中/整卡/装配组合/保存前/加载前/预览探针） | `validate/validator.gd` | 填写中只查已提交控件值（不刷屏）；保存前对规范化后完整定义再校验一次；并发重校验绑定草稿修订号，旧结果不覆盖新结果 |
| T-016 | 反例夹具：84 条 V 各一条触发反例 + 相邻合法边界 | `tests/test_validate_rules.gd` | 通用类型规则覆盖零/边界值/缺省/null/字符串数字/非有限数/超范围；关联规则先构造「引用都存在但语义仍非法」的情形（真源 20.3 末段） |

---

## 四、M3 · 参数解析与修饰器（线 B）

> 真源：第 5 章参数表、第 6—7 章暴露与挂点、第 16.2/16.3 落点、第 14.4 规则

| ID | 任务 | 依赖 | 产出 | 验收标准 |
|---|---|---|---|---|
| T-030 | `param_resolver.gd`：登记默认 → 通用覆盖 → 指定卡覆盖，确定性展开 + 路径来源表 | T-002,T-003 | `skill_core/resolve/param_resolver.gd` | 一个逻辑叶字段只有一个最终权威来源；默认值/覆盖来源/最终值三者界面可查；错误可定位回真实输入路径 |
| T-031 | 锁定字段与覆盖拒绝 | T-030 | 同上 | 作者覆盖 `locked_params` 命中 V-014，定位到 `params.brick_overrides[i].values.<leaf>` |
| T-032 ✅ | 暴露字段登记 `exposed_fields` | T-030 | `skill_core/resolve/exposed_fields.gd` | 六字段 name/permission/min/max/live/inheritable/set_conflict_note；上下限缺失或倒置 → V-048｜**2026-10-18 PASS**：21/21（1121 asserts）；复核方部署 `data/exposed_fields_meta.json`，并去掉一处写死的上下文键 |
| T-033 | 修饰器引擎三档权限 | T-030,T-032 | `skill_core/modify/modifier_engine.gd` | `mutate_number`/`add_behavior`/`mutate_live_instance` 互不包含；水晶只能 mutate_number（V-041）；live 需物品申请与目标 live 双向许可（V-045） |
| T-034 | 叠加运算 `stack_rule` | T-033 | 同上 | 固定顺序 set→add→mul→clamp；**每次从基准值重算**，不反向撤销；未登记运算不得以字符串表达式执行 |
| T-035 | 继承开关与不可改边界 | T-033 | 同上 | 禁止修饰来源链/实例身份/快照/历史结果（V-046）；禁止改 `max_generation`/`max_chain_depth`/`allow_self_chain`（V-047） |

---

## 五、M4 · 最小运行时沙盒（线 C）

> 真源：卷二《技能运行时契约》第 4—7 章（统一模型/生命周期/终止）、第 10—11 章（命中与结算）、第 14 章（时序）、第 20 章（组合安全）

| ID | 任务 | 依赖 | 产出 | 验收标准 |
|---|---|---|---|---|
| T-040 | 固定步长时钟 + 暂停/慢动作 + 种子 RNG | T-000 | `runtime/sim_clock.gd` | 暂停不推进 tick；同输入同种子逐次一致；表现 RNG 与逻辑 RNG 分离 |
| T-041 | 效果体四类载体生命周期 | T-040 | `runtime/effect_body.gd` | spawn/tick/vanish/purge 四类齐全；**purge 静默**（不发 vanish、不派生、不补 hit）（真源 4.9.3） |
| T-042 | 运动模式 | T-041 | `runtime/motion.gd` | straight/lob/orbit/stationary/wavefront/returning/homing 七种先落；ricochet/expanding/follow 随对应积木后续接 |
| T-043 ✅ | 形状与判定 + `hit_policy` | T-041 | `runtime/shape_hit.gd` | circle/sector/line/rectangle；per_target_limit / rehit_interval_ticks / max_hits 三子字段；候选接触与成立 hit 分别计数｜**2026-10-18 PASS**：26/26（356 asserts）；复核方部署 `data/shape_hit_meta.json`，几何三约定登记 U-14 |
| T-044 | 结算份 `parts` | T-043 | `runtime/settle.gd` | 11 种 part_type；**一次 hit 内多份结算不复制命中派生**；全闪避/免疫/无敌份级区别（ED-17-01…04） |
| T-045 | 派生 hit/vanish + 原因码 + 预算 | T-044 | `runtime/derive.gd` | 只有 `hit`/`vanish` 两事件；原因码 7 种冻结值；`range_end`/`interrupted` 需显式授权（V-034）；代数/因果深度/预算不可被子体重置（V-057/058） |
| T-046 | 防霰弹与家族登记 | T-045 | 同上 | 同次出手独立根实例抑制；分裂全家族记候选接触，兄弟同 tick 竞争稳定顺序先处理者登记 |
| T-047 | 召唤上限与归属清理 | T-041 | `runtime/summon.gd` | 超限清理最旧；绑定主人死亡时 purge；独立实例按契约继续（ED-17-22） |
| T-048 | 预算优先级 + `debug_record` | T-045 | `runtime/budget.gd` | 先丢纯表现；拒绝新根不挤已有根并记录原因；`debug_record` 与正式 UI 隔离（关调试不影响战斗） |

**M4 范围纪律**：不接性能基线（100 子弹/80 特效/80 角色同屏属项目层验收，本期不做）。

---

## 六、M2 · 编辑器插件 UI（线 D）

> 真源：卷一第 13—20 章

| ID | 任务 | 依赖 | 产出 | 验收标准 |
|---|---|---|---|---|
| T-020 | `EditorPlugin` 入口 + 底部面板挂载 | T-000 | `addons/skill_editor/plugin.gd`、`plugin.cfg` | Godot 编辑器启用插件后出现面板；**plugin.gd 只做菜单与挂载，不含任何业务逻辑** |
| T-021 | 技能列表与检索 | T-003,T-020 | `ui/skill_browser.gd` | 按角色/池/标签检索；同名不同 ID 均可找到、精确 ID 只命中一个（ED-13-01…08） |
| T-022 | 积木选择面板 | T-003,T-020 | `ui/brick_picker.gd` | 按 carrier 四组展示；候选状态可见但不可导出（V-012/E-0008）；**不得按中文名自动归类 carrier** |
| T-023 | 参数表单（按九列登记动态生成） | T-030(可先用桩),T-020 | `ui/param_form.gd` | 锁定项不可填；秒/tick 双显且落盘只存 tick；未开放参数不出现在表单 |
| T-024 | 校验诊断面板 | T-005,T-014,T-020 | `ui/diagnostic_panel.gd` | 策划/程序双视图同一份诊断；点击展开折叠区并定位字段；字段位于积木默认值时先提示「错误来自默认卡」，不自动复制到覆盖区 |
| T-025 | 保存/加载/版本 | T-002,T-015,T-020 | `ui/save_flow.gd` | 基线被更新时不覆盖（V-081）；未知版本只读不降级（V-083）；未改内容重复保存不产生假修订 |
| T-026 | 修饰器与暴露字段编辑面板 | T-032,T-033,T-020 | `ui/modifier_panel.gd` | 六字段接口不暗加孤立字段；`tagged` 作用域显式标为「作用域标签」 |
| T-027 | 预览启动与试放入口 | T-050,T-020 | `ui/preview_launcher.gd` | 显式固定初态/种子/输入；版本切换显式化；不用热更新绕开 live 权限（真源 3.6） |

---

## 七、M5 · 预览与复现（线 C）

| ID | 任务 | 依赖 | 产出 | 验收标准 |
|---|---|---|---|---|
| T-050 | 预览沙盒入口 | T-048 | `runtime/preview_runner.gd` | 消费与正式读取同一份 CFG；固定当前配置快照；实例编号不由编辑器预填 |
| T-051 | 预览面板（事件/结算/调试分栏） | T-050 | `ui/preview_panel.gd` | 三栏轨迹；正式与调试数据分离 |
| T-052 | ED-17-01…24 复现夹具 | T-050 | `tests/test_ed17_*.gd` + `data/fixtures/` | 24 条逐条对应测试函数；ED-17-14 夹具必须真实包含合法分裂来源（真源 20.4 末段特别警告） |
| T-053 | 差分与重跑一致性 | T-052 | `tests/test_determinism.gd` | 同输入同种子两次运行逐次一致；首差异可定位 |
| T-054 | 预览指纹与认证分离 | T-053 | `runtime/preview_fingerprint.gd` | 预览指纹≠待保存指纹时按 V-084 处理；保存与「通过验收」是两个状态，界面必须区分 |

---

## 八、M6 · 表现层与整体验收（线 D + C）

| ID | 任务 | 依赖 | 产出 | 验收标准 |
|---|---|---|---|---|
| T-060 | `presentation` 七段配置面板 | T-025 | `ui/presentation_panel.gd` | fx/sfx/anim/trail/camera/damage_number/status_icon 七槽；空段＝未绑定资源，不继承隐藏默认 |
| T-061 | 表现只读消费与动画对齐 | T-060 | `runtime/presentation_bind.gd` | 表现只消费 `hit`/`hit_settled`；动画回调**不得**驱动出手/接触/脉冲/落地（V-072）；对齐项必须有 shot_tick 与 frame（V-074） |
| T-062 | 最小可视化渲染 | T-061 | `ui/preview_viewport.gd` | 形状、拖尾、伤害数字可见（够验证「搭积木」效果即可，不做美术） |
| T-063 | 第 20 章可勾选验收清单执行 | 全部 | `S_docs/collab/reports/acceptance_m6.md` | 清单逐条勾选并附证据；绿色通过必须能展开到具体用例，**不能由「未收到异常」推导** |
| T-064 | 端到端交付证据打包 | T-063 | 交付包 + 证据索引 | 走通 20.1 八步骤，每步有证据且绑定版本与内容指纹 |

---

## 九、第一批派发（立即可并行，T-000 PASS 后）

| 顺序 | 任务 | 线 | 说明 |
|---|---|---|---|
| 0 | **T-000 冻结核心接口** | A | **单点先行**，不可并行；其余线等它 PASS |
| 1 | T-001 仓库骨架 / T-002 CFG 编解码 / T-003 积木目录 | A | 三个可并行 |
| 1 | T-040 时钟 / T-041 效果体生命周期 | C | 依赖 T-000 桩接口即可开工 |
| 1 | T-020 插件入口 / T-021 技能列表 / T-022 积木选择 | D | UI 可用 api 桩先行 |
| 1 | T-030 参数解析 | B | 依赖 T-002 素材文件即可（可先读 JSON） |
| 2 | T-004/T-005/T-006 → T-010…016 → T-030…035 | A/B | 顺序推进 |
| 3 | T-042…048 → T-050…054 | C | 顺序推进 |

---

## 十、全局禁止事项（任何任务违反即 REJECT）

1. 禁止把积木 ID / 枚举值硬编码进 `if-elif` 链 —— 一律走目录与素材驱动。
2. 禁止在 `skill_core/` 引用任何编辑器 API（`@tool`、`EditorPlugin`、`EditorInterface`）。
3. 禁止把运行态数据（`instance_id`、`seq`、`origin`、`snapshot`、`state`、结算结果）写回技能 CFG。
4. 禁止任何「先保存再补校验」的路径。
5. 禁止把警告降级为提示、把阻止保存降级为警告。
6. 禁止对空集合执行「全部成立」判断来冒充验收通过。
7. 禁止修改 `S_docs/技能系统书-v1.md` 与 `S_docs/collab/00~02`。
8. 禁止为校验方便发明开关（真源 14.3 末段：不给作者一个必须恒为 false 的布尔值）。
