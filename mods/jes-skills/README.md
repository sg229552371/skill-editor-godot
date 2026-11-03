# jes-skills · 技能自定义底座（Godot 4.7.1 数据驱动技能系统）

> **一句话**：类 PoE 的数据驱动技能系统。运行时逻辑只写一次，技能差异全部来自数据——新增/修改技能 = 改一张 Excel，零代码改动。
> **给后续 AI 的最快路径**：本文（3 分钟）→ `docs/_AI开发与文档/00_开工必读.md`（治理口径唯一入口）→ 按任务跳转，不要通读 docs。

---

## 一、目录地图

| 路径（相对本模块） | 是什么 | 谁可以改 |
|---|---|---|
| `content/gems/{active,supports,triggers}/*.tres` | **运行时真数据**：69 主动 + 13 辅助 + 1 触发（生成物，勿手改） | 只许工具写 |
| `content_src/技能配置表.xlsx` | **策划唯一手改入口**（6 页签中文工作簿） | 策划/AI（走流水线校验） |
| `systems/skills/` | 运行时核心：注册表 / 装配 / 执行 / 伤害管线 / 行为（48 文件，全自研，第三方依赖 0） | 运行时代码，原则上冻结 |
| `systems/skills/behavior/bhv_*.gd` | 7 种行为：投掷物 / 近战挥砍 / 范围爆发 / 引导 / 召唤 / 位移 / 自我增益 | 冻结 |
| `sandbox/` | 可玩沙盒实验台（`sandbox_main.tscn`），新技能肉眼验收用 | 演示层 |
| `tools/content_workbench/` | 策划配置表工具：Excel ↔ .tres 双向流水线（入口 `README.md`） | 工具层 |
| `tools/api_map_generator.gd` | 生成 `docs/_AI开发与文档/03_查规则/API地图.md`（内容速查表） | 工具层 |
| `tests/` | GUT 门禁：`skills/`（内容契约）`sandbox/`（实放闭环）`docs/`（治理门禁）`perf/` | 只增不删不放宽 |
| `docs/` | 知识与治理（三分区，见 §五） | 受门禁约束 |

## 二、运行时 API 速查（全部 `class_name` 全局可用）

```gdscript
# 1) 内容注册表（自动扫描 content/gems，文件名 == id）
GemRegistry.reload()                        # 刷新（扫盘，重进场景/测试 before_all 调）
GemRegistry.skills()                        # Array[SkillData]
GemRegistry.skill(&"trample_charge")        # SkillData 或 null
GemRegistry.supports() / support(id) / triggers() / has_skill(id) / has_support(id)

# 2) 出招：数据 → 行为计划（纯函数，不碰节点）
var plans := SkillExecutor.cast(skill_data, 1, stats)
# plans: Array[Dictionary]，每条含 behavior_id / elements / params / angle_deg
# 未知 behavior_id 的段被跳过；behavior_overrides 可选（辅助石装配层注入）

# 3) 装配：槽位（技能 + 辅助石）→ 实际施放物
var res := SocketGraph.assemble(slot)       # res.ok / res.cost_multiplier
var slot := SkillSlotBar.new(); slot.get_slot(0)   # 9 槽，主动+辅助

# 4) 资源与冷却
main.mana.get_current(&"mana")              # ResourcePool
var cd := CooldownComponent.new(); cd.configure(base, recharge, max_charges, charge_time)

# 5) 行为计划消费（各行为一个纯静态类，produced_params() 是键面承诺）
var dash := BhvDash.plan_to_dash(plan)      # distance/speed/path_width/hit_count/tick_interval/path_damage...
var burst := BhvAoeBurst.plan_to_burst(plan) # shape=pt/circ/ring/sec/line/multi + delay/hit_count/hit_interval

# 6) 触发器
main.trigger_mgr                            # TriggerManager：on_crit 等条件→槽位施放
```

**标签契约要点**：行为自带形态标签（`SkillExecutor.BEHAVIOR_FORM_TAG`：dash→movement 等），技能 `tags` 必须包含它；
冲刺距离/速度不吃范围加成（D-40）；「投射数量」写回键是 `count_base`（P-06）。
完整词表/形状/必填参数唯一真源：`tools/content_workbench/schema.json`。

## 三、内容生产流水线（在仓库根执行，Python 3.13 + openpyxl）

```powershell
$env:PYTHONUTF8 = '1'   # Windows 控制台先设
# ① 改表后校验（错误定位到 页签+行+列，中文提示）
python mods/jes-skills/tools/content_workbench/build/read_workbook.py mods/jes-skills/content_src/技能配置表.xlsx
# ② 生成干跑（只写 _tmp/dryrun，不碰正式内容；需 Godot 控制台 exe）
godot --headless --path . -s res://mods/jes-skills/tools/content_workbench/build/build_from_json.gd
# ③ 落盘空跑 → 确认清单 → 真写（唯一改 content/ 的命令；新增内容须制作人拍板）
python mods/jes-skills/tools/content_workbench/finish/apply.py
python mods/jes-skills/tools/content_workbench/finish/apply.py --apply
# ④ 一键收尾 10 步：刷新类缓存→导出→校验→生成→API地图→数值快照→漂移检查→GUT 全量→回写⑥页签
python mods/jes-skills/tools/content_workbench/finish/run_all.py --godot <Godot 控制台 exe>
```

**新增技能三步**：② 技能卡预留行填名 + ③ 效果段行指到该名 → ①②③④ 跑一遍 →
**把工具生成的代号回写锁定进工作簿代号列**（防跨次生成代号漂移，台账 D-64 踩坑）。
详细用法/报错速查：`tools/content_workbench/README.md`；表结构契约：`schema.json`（冻结）。

## 四、测试与门禁

```powershell
# 全量门禁（当前基线：37 脚本 / 373 用例 / 4769 断言，只升不降）
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://mods/jes-skills/tests -ginclude_subdirs -gexit
```

- 内容契约（`tests/skills/test_content_contract.gd`）：文件名==id、标签全注册、施放层显式、必填参数、形态标签。
- 签名唯一（`test_batch_c_content.gd` C6）：全量技能「行为×参数」签名两两不同——新技能必须与全部既有技能至少差一个参数键。
- 游戏内自检范本：`tools/content_workbench/_tmp/selfcheck_impact_skills.gd`（注册→契约→签名→沙盒实放四段式）。
- 治理门禁（`tests/docs/`）：文档禁止项目外路径；docs 下每个 .md 必须在真源清单登记；台账每条 D-* 必须挂载到记忆图谱。

## 五、docs/ 文档地图（三分区）

| 区 | 路径 | 用途 | 权限 |
|---|---|---|---|
| **001 热区** | `docs/_AI开发与文档/` | `00_开工必读.md`（治理入口）· `02_改代码/施工规格…v1.0.md`（S1 宪法 69KB）· `01_写内容/`（总纲/AI执行版/白名单矩阵/内容设计手册）· `03_查规则/`（API地图 / 踩坑与决策台账 D-01~D-65 / 信息来源与真源清单 / 项目记忆图谱） | 读写主体 |
| **002 冷区** | `docs/_重要资料记录/` | 架构溯源、PoE2 参考资料、辅助宝石数据（派生品 + 生成器；原始 lua 快照已按制作人批示清理，重取路径见资料夹索引） | 只查不写 |
| **过程档案** | `docs/_人工文档流程/` | 原始设计案（过程稿）、架构起源原件 | 默认不读，不得当依据 |
| **垃圾桶** | `docs/垃圾桶/README.md` | 「移而不删」冷存区机制与登记 | — |

**查规则优先级**：现行口径（S1）> 台账 D-*（为什么）> 本 README（导航）。冲突时以 001 热区为准。

## 六、当前状态（2026-11-03）

- 内容：**69 主动 / 13 辅助 / 1 触发**；位移（冲击）族 10 格已铺 9 格，仅 `DASH·LINE·ZONE`（路径光墙）待制作人拍板（与留下火径同站位）。
- 门禁：**37 脚本 / 373 用例 / 4769 断言全绿**；生成↔落盘零漂移。
- 决策台账至 **D-65**；本模块开发已完成并打标「Godot-Mods-技能自定义底座」。

## 七、纪律红线（违者施工失败）

1. 运行时代码（`systems/`）冻结；新增内容零代码改动。
2. 不放宽/删除既有测试；红了修数据或修工具。
3. Excel 是唯一手改入口；`.tres` 是生成物勿手改；`schema.json` 冻结。
4. 台账只追加；图谱每条 D-* 必挂载；docs 不写项目外绝对路径。
5. 提交/推送须制作人明示；删除内容类文件须制作人拍板。
