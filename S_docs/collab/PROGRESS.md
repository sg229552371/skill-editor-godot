# 开发进度看板（WorkBuddy 维护，每次汇报刷新）

> 引擎：Godot **4.7.1**（`Ryko.GodotHub/godot-versions/4.7.1-stable`）｜门禁归 WorkBuddy 独占，Claude CLI 只写代码
> 更新：2026-10-18 21:25

## 一、总览

| 项 | 数 |
|---|---|
| 已 PASS 并合入主干的任务卡 | 19（基线 10 + T-030/042 + T-010/011/012/032/033/043/044 + **T-034/T-045**） |
| 在跑（CLI 后台） | 1（**T-013 线A 二轮**，素材已补齐后重派） |
| 待派 | 见第四节 |
| 全量测试 | **285/285 绿**（17 个测试文件） |

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

## 三、在跑（CLI 后台）

| 卡 | 线 | 产出 | 状态 |
|---|---|---|---|
| **T-013（二轮）** | A 校验 | `validate/rules/r_present.gd`（V-070…084） | 21:2x 重派。首轮 BLOCKED（素材不全）→ 审核方已补 `presentation_meta.json`（60 叶 + 启用判据/拖尾关系/合并边界/订阅禁值/回写禁区/runtime_hints）与 context 契约 V-076…084，并裁定 V-073 两段式、V-075 关系、V-080 未登记叶、V-084 入口区分 |

**验收流程（每张卡固定）**：`--check-only` 编译 → 单文件 GUT 串行 → 全量回归 → 写复核结论到 `reports/T-xxx.md` → 判 PASS 才提交（`T-xxx` 开头 commit）。

## 四、待派（下一步）

**线 A 校验**：T-014（诊断排序）、T-015（六入口编排）、T-016（84 条反例夹具）
**线 B 解析**：T-031（锁定字段拒绝）、T-035（继承与边界）
**线 C 运行时**：T-046（防霰弹）、T-047（召唤）、T-048（预算 + debug_record）
**线 D UI**：T-023（参数表单）、T-024…027

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

已关闭：**U-13**（→D-24）、**U-17**（→D-28）

## 七、决策与坑位

- **D-22** 素材迁 `res://data/` · **D-23** V 规则字段统称以 Schema 落点为准（别名进元数据，CSV 原文不动）
- **D-24** 四种结算记录 = `enums.record`；hit/vanish/debug_record 均非合法订阅
- **D-25** 校验器不拥有解析能力，只消费已解析事实；缺 context 显式失败
- **D-26** crystal 仅 mutate_number；relic 的 live 降为 conditional（从严）
- **D-27** 严重度唯一真源是 CSV（V-050/**V-054**/V-056 警告）
- **D-28** `evadable` 缺省按有益有害补默认（有害 true / 有益 false）；无敌只让五种伤害元素视为闪避
- **坑 5** 函数头丢失（第一条 `Function X not found in base self` 是真定位点）
- **坑 6** Variant 跨类型比较抛运行时错误 → GUT 记 Unexpected Errors，断言只差 1，极难看出
- **坑 7** 点语法给 Dictionary 写新键生成 StringName 键，不是 String（`has("x")` 取不到）
- **坑 8**（本轮 T-034 新踩）给**显式类型变量**赋 null 抛运行时错误：`var list: Array = dict.get(k, null)`；
  它不中断脚本但让函数返回空值，下游 `result.ok` 再报一条误导性错误。**容器取值一律先声明 `Variant` 再 `is` 判定**
- **D-29**（本轮）V-073 两段式：类型/范围走 Schema（minimum 0），「启用时正整数」走启用态（`enabled_minimum_overrides`）
- **D-30**（本轮）V-084 入口区分：certify 指纹不同 → 阻止保存；save 指纹不同 → 可保存 + 「未预览」notice（真源 133，不动 CSV 严重度）
