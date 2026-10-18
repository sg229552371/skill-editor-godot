# 开发进度看板（WorkBuddy 维护，每次汇报刷新）

> 引擎：Godot **4.7.1**（`Ryko.GodotHub/godot-versions/4.7.1-stable`）｜门禁归 WorkBuddy 独占，Claude CLI 只写代码
> 更新：2026-10-18 20:35

## 一、总览

| 项 | 数 |
|---|---|
| 已 PASS 并合入主干的任务卡 | 14（T-000/001/002/003/005/020/021/022/040/041 基线；+ T-030、T-042、T-010、**T-032、T-043、T-011**） |
| 在跑（CLI 后台） | 3（T-012 线A / T-033 线B / T-044 线C） |
| 待派 | 见第四节 |
| 全量测试 | **158/158 绿**（12 个测试文件，截至三张卡合入后） |

## 二、已 PASS（按完成时间）

| 卡 | 内容 | 产出 | 门禁 |
|---|---|---|---|
| T-000/001/002/003/005/020/021/022 | 接口冻结、骨架、YAML 编解码、积木目录、诊断对象、编辑器插件壳/列表/积木选择 | `skill_core/api/*`、`schema/*`、`catalog/*`、`addons/skill_editor/*` | 基线 `43b80da` |
| T-040 | 固定步长时钟 + 暂停/慢动作 + 种子 RNG | `runtime/sim_clock.gd` | 4/4 |
| T-041 | 效果体四类载体生命周期（purge 静默） | `runtime/effect_body.gd` | 7/7 |
| T-042 | 运动模式（7 种先落） | `runtime/motion.gd` | 14/14 |
| T-030 | 参数解析与合并 + 路径来源表 | `resolve/param_resolver.gd` | 3/3（修 D-20 游离字典 + 路径前缀） |
| T-010 | V-001…V-018 身份/结构/引用 | `validate/rules/r_identity.gd`、`validate/identity_meta.gd` | 28/28，661 asserts（`fc46093`） |
| **T-032** | **暴露字段登记 exposed_fields** | `resolve/exposed_fields.gd` + `data/exposed_fields_meta.json` | **21/21，1121 asserts**（`a539a8f`） |
| **T-043** | **形状与判定 + hit_policy** | `runtime/shape_hit.gd` + `data/shape_hit_meta.json` | **26/26，356 asserts**（`21acbe6`） |
| **T-011** | **V-019…V-038 类型/时间/命中/事件** | `validate/rules/r_types.gd` | **23/23，94 asserts**（`123d6cf`，复核方修函数头丢失＝坑 5） |

## 三、在跑（CLI 后台，实时状态）

| 卡 | 线 | 产出 | 状态 |
|---|---|---|---|
| T-012 | A 校验 | `validate/rules/r_modifier.gd`（V-039…069，31 条） | 20:32 派发，含 D-24 裁定与 `project_limits.json` |
| T-033 | B 解析 | `modify/modifier_engine.gd`（三档权限） | 20:33 派发，消费 T-032 的暴露事实 |
| T-044 | C 运行时 | `runtime/settle.gd`（结算份 parts，ED-17-01…06） | 20:34 派发，依赖已 PASS 的 shape_hit.gd |

**验收流程（每张卡固定）**：`--check-only` 编译 → 单文件 GUT 串行 → 全量回归 → 写复核结论到 `reports/T-xxx.md` → 判 PASS 才提交（`T-xxx` 开头 commit）。

## 四、待派（下一步）

**线 A 校验**：T-013（V-070…084）、T-014（诊断排序）、T-015（六入口编排）、T-016（84 条反例夹具）
**线 B 解析**：T-031（锁定字段拒绝）、T-034（叠加运算 stack_rule）、T-035（继承与边界）
**线 C 运行时**：T-045（派生+原因码+预算，依赖 T-044）、T-046（防霰弹）、T-047（召唤）、T-048（预算+debug_record）
**线 D UI**：T-023（参数表单）、T-024…027

## 五、素材（`res://data/`，D-22：运行期只从这里读）

`brick_catalog.json` · `relic_policy.json` · `motion_meta.json` · `validation_rules.csv`(84) · `error_messages.csv`(42)
· `identity_meta.json` · `params_meta.json`(叶 159/数组 26/对象 28/tick 15/枚举 14)
· `exposed_fields_meta.json`(T-032) · `shape_hit_meta.json`(T-043) · `project_limits.json`(硬上限，含 `_provisional` 标记)

抽取脚本：`S_docs/collab/assets/extract_params_meta.py`（Schema 改了重跑，两份必须一致）

## 六、未决（不阻塞，见 02-决策台账.md）

U-09 YamlLite chomping（`>-` `|-`）· U-11 V-018 动词词表 · U-12 切句符号
· **U-14** 几何三约定（sector 全角 / line 平端 / rectangle 居中，〔推荐默认〕）
· **U-15** V-030「择一」策略落点
· **U-16** `project_limits.json` 中 `_provisional` 数值（cast_budget 64、三处硬上限）真源标注「仅示例，最终值由项目配置与性能测量决定」（F-26），M5 前定稿

## 七、本轮新增决策

- **D-22**（素材迁 `res://data/`）· **D-23**（V 规则字段统称以 Schema 落点为准，别名进元数据，CSV 原文不动）
- **D-24**（U-13 定稿）：V-060 被动订阅的四种结算记录 = `params_meta.enums.record`（cast_started / hit_settled / evaded_all / damage_taken）；`hit`、`vanish`、`debug_record` **不是**合法订阅记录（debug_record 另受真源 7135 约束：非事件、非结算记录，任何层不得订阅）
- **坑 5**（写入 CLAUDE.md）：GDScript 函数头丢失会让整脚本编译失败，第一条 `Function X() not found in base self` 才是真定位点
