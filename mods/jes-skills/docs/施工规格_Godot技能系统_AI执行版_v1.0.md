# Godot 4.7 技能系统 · 施工规格（AI 执行版）

**版本**：v1.0　**生成日期**：2026-10-19　**配套**：《流放之路风格·高自由度技能系统规格.md》（下称"原规格"）
**本文性质**：这是**执行约束文件**，不是设计建议。标注「必须」的条目不得自行改写；标注「可选」的条目需先向人类确认。

---

## 0. 给执行 AI 的三十秒说明

你要在 **Godot 4.7.x + GDScript** 中实现一套类 PoE 的数据驱动技能系统。核心复杂度全部集中在**属性结算管线**与**辅助石装配**两处，其余都是它的外设。

**开工前记住六句话**：

1. **运行时逻辑只写一次，技能差异全部来自数据**。新增一个技能 = 新增一个 `.tres`，不改 `.gd`。
2. **修饰符只有三种算子**：`FLAT_ADD`（加）、`INCREASED`（加算百分比）、`MORE`（乘算百分比）。禁止出现第四种、禁止混用。
3. **辅助石通过"标签三元组 + 修饰符列表"生效**，不允许在代码里写 `if gem_id == "xxx"`。
4. **行为组件不认识具体宝石**，只读 `SkillContext` 里的最终数值。
5. **热路径禁止 `instantiate/free`**，投射物/特效/Hitbox 一律走对象池与数据化数组。
6. **每个里程碑必须有可手算核对的断言**，测试不绿不得进入下一阶段。

**禁止**：引入任何未经人类批准的新依赖；不得参考无许可证的仓库（尤其 `Simplereally/the-exile-engine-v2`，该仓库无 LICENSE，代码不可复制）；不得照搬 Path of Exile 的技能名与数值。

**交付**：按 §11 的 M0–M8 顺序提交，每阶段附测试报告（通过数/失败数/未覆盖项）。

## 0.1 施工进度（2026-10-19 终局更新）

全部里程碑 **M0–M8 已完成**，全量测试 **85/85（269 asserts）100% 绿**。

| 里程碑 | 状态 | 测试 |
|---|---|---|
| M0 环境/GUT | ✅ | 2 |
| M1 StatsComponent/修饰符管线 | ✅ | 8 |
| M2 DamageConversion/SkillData | ✅ | 9 |
| M3 SupportGem/SocketGraph 装配 | ✅ | 6 |
| M4 DamagePacket/Calculator/命中与击杀 | ✅ | 16 |
| M5 ResourcePool/冷却充能/技能栏 | ✅ | 14 |
| M6 行为组件（7 项） | ✅ | 13 |
| M7 TriggerManager/CombatEventBus | ✅ | 10 |
| M8 DoT 全局 ticker/AILMENT 通道隔离/ProjectilePool 硬上限 | ✅ | 7 |

关键实现位置：`mods/jes-skills/systems/skills/`（核心）+ `behavior/`（行为）+ `combat/`（战斗管线/DoT/池）+ `data/`（数据类）；测试 `mods/jes-skills/tests/skills/test_m0…m8.gd`。

---

## 1. 技术路线裁定

### 1.1 采用：二为骨、一为镜

| 层 | 来源 | 用法 | 硬边界 |
|---|---|---|---|
| **语义层（怎么算对）** | `PathOfBuildingCommunity/PathOfBuilding` 的 `src/Modules/Calc*.lua`、`src/Data/Skills/sup_*.lua` | 校对算子的**顺序、作用域、边界**（转换上限、多源合并、inc/more 分桶、触发限流） | **不移植 Lua 代码**。仅用作"标准答案"比对；`CalcOffence.lua` 单文件 6263 行，移植＝重写 |
| **实现层（怎么跑起来）** | `ClarkWain/godot-arpg-kit`（MIT，Godot 4.5+，9189 行，38 个测试脚本） | 抄**结构**：`RefCounted` 纯函数管线、事件总线 autoload、`StatModifier` 数据形态、测试组织与 CI | 只抄结构，**不抄它的 CombatComponent 双管线**（见 §13.3） |
| **自研层（护城河）** | 本项目 | 插槽图 `SocketGraph`、水晶条件系统、局内武器栏多槽、投射物 DOD、空间哈希、确定性 RNG | 任何人不得用现成库替代 |
| **架构参考（只看不抄）** | Unreal GAS 系（`gamesmiths-guild/forge-godot` 等） | 只借鉴 "Attribute / Effect / Tag / Cue" 的**职责切分** | 不引入其运行时、不引入其节点结构 |

### 1.2 为什么不整仓复用 `the-exile-engine-v2`

已实测：该仓库 241 个 `.gd`、1340 个 `.json`，但**没有 `project.godot`**（Godot 打不开）、**没有 LICENSE 文件**（默认保留所有权利）、末次提交 2026-04-11、`src/skills/` 的辅助石兼容性靠 `stat_name.contains("area")` 字符串分支判定。

**结论**：只允许读三处**思想**，零代码复制——`core/deterministic_rng.gd`（种子回放）、`tests/core/test_spatial_partition.gd`（空间分区）、`skills/gem_socket_system.gd` 中 `_links: Array[bool]` 的连通表达方式。

---

## 2. 开工前必读（三份来源，附精确读取清单）

> 你的上下文预算有限，**不要通读整个仓库**。按下表逐条读取，读完即停。

| 顺序 | 目标 | 精确路径 | 读什么 | 目标产出 |
|---|---|---|---|---|
| 1 | PoB 结算语义 | `src/Modules/CalcActiveSkill.lua`（934 行） | 技能如何被"注册"进计算、多 part 伤害如何拆分 | 列出 part 的数据结构 |
| 2 | PoB 算子顺序 | `src/Modules/CalcOffence.lua`（6263 行，**只读转换与 inc/more 段**） | 转换在 inc 之前还是之后、多源转换如何归一化 | 写出 §4.3 的顺序表并逐条对照 |
| 3 | PoB 辅助石判定 | `src/Data/Skills/sup_int.lua`（7007 行，**只看 3 个字段**） | `requireSkillTypes` / `addSkillTypes` / `excludeSkillTypes` 的语义 | 落到 §3.3 的三元组 |
| 4 | PoB 触发限流 | `src/Modules/CalcTriggers.lua`（1627 行） | 同事件多触发、chance 与 cooldown 如何共同限流 | 落到 §7.2 公式 |
| 5 | kit 管线形态 | `scripts/stats/stats_component.gd`、`scripts/stats/stat_modifier.gd` | 属性容器如何持有 modifier 列表、如何按来源移除 | 抄接口签名，不抄实现细节 |
| 6 | kit 纯函数伤害 | `scripts/combat/damage_calculator.gd`、`scripts/combat/damage_info.gd` | 为什么用 `RefCounted` 静态类、`DamageInfo` 字段 | 抄这个模式 |
| 7 | kit 事件总线 | `scripts/combat/combat_event_bus.gd`（autoload） | 信号命名与订阅时机 | 抄 |
| 8 | kit 测试组织 | `tests/`（38 个 `.gd`）、`.github/workflows/tests.yml` | headless 跑测的退出码陷阱、`seed(0)` 治理 flake | 抄 CI 配置与 flake 治理手法 |

**校验点**：读完第 4 条后，你应当能回答——"事件率 5 次/秒、概率 30%、自身 CD 0.5 秒，实际触发频率是多少？"答案见 §7.2，若答不出说明没读懂，回去重读。

---

## 3. 数据契约（六张表，字段级）

> 所有表用 `.tres`（`Resource`）实现；**禁止**用字典散装传参。所有字符串键用 `StringName`（`&"xxx"`），并集中注册在 `stat_registry.gd` / `tag_registry.gd` 中，禁止裸字符串散落各文件。

### 3.1 SkillData（主动技能）

```gdscript
class_name SkillData extends Resource

@export var gem_id: StringName                  # &"frost_shard"，全局唯一
@export var display_name: String
@export var icon: Texture2D
@export var parts: Array[SkillPart]             # 至少 1 个；多段伤害=多 part
@export var tags: Array[StringName]             # 决定辅助石兼容性 & 词缀作用域
@export var cast_mode: CastMode                 # ACTIVE / TRIGGER_ONLY
@export var base_cast_time: float = 0.5
@export var cost_type: CostType                 # MANA / LIFE / ENERGY_SHIELD / NONE
@export var base_cost: float = 10.0
@export var base_cooldown: float = 0.0
@export var max_charges: int = 0                # >0 时冷却改为充能回复
@export var charge_recharge_time: float = 0.0
@export var level_scaling: GemLevelScaling
@export var allowed_support_tags: Array[StringName] = []   # 空=接受全部
```

```gdscript
class_name SkillPart extends Resource
@export var damage_channel: Channel             # HIT / DOT / AILMENT（见 §4.1）
@export var base_damage: Dictionary             # {&"physical": 100.0, &"cold": 20.0}
@export var damage_effectiveness: float = 1.0   # 附加伤害的缩放系数
@export var behavior_id: StringName             # 指向 bhv_*.gd
@export var behavior_params: Dictionary         # 见 §3.6
```

**必须**：`damage_channel` 与 `tags` 是两个**正交维度**。原规格用"分系（melee/projectile/area/dot）"一个维度表达，会导致"近战投射物技能吃哪一系词缀"无解——这是必须修正的设计缺陷，详见 §4.1。

### 3.2 ModifierSpec（修饰符规格）

```gdscript
class_name ModifierSpec extends Resource
@export var stat: StringName                   # &"projectile_damage"
@export var op: Op                             # FLAT_ADD / INCREASED / MORE
@export var value: float
@export var channel_mask: int = Channel.ALL    # 位掩码：HIT|DOT|AILMENT
@export var require_tags: Array[StringName]    # 全部命中才生效（AND）
@export var exclude_tags: Array[StringName]    # 命中任一即失效
@export var conditions: Array[ConditionSpec]   # 可选：生命低于 35% 等
```

运行时实例：

```gdscript
class_name Modifier extends RefCounted
var stat: StringName
var op: int
var value: float
var source_id: StringName                      # 必填！&"gem:frost_shard" / &"support:multishot"
var channel_mask: int
var require_tags: Array[StringName]
var exclude_tags: Array[StringName]
```

**必须**：`source_id` 不可为空。卸下辅助石/装备时按 `source_id` 精确批量移除，这是"卸下即还原"的唯一实现方式。

### 3.3 SupportGemData（辅助石）—— 三元组是核心

```gdscript
class_name SupportGemData extends Resource
@export var support_id: StringName
@export var display_name: String
@export var require_tags: Array[StringName]    # 必须全部具备
@export var add_tags: Array[StringName]        # 给技能追加标签（会影响后续辅助的兼容判定）
@export var exclude_tags: Array[StringName]    # 命中任一即不兼容
@export var cost_multiplier: float = 1.0
@export var stat_modifiers: Array[ModifierSpec]
@export var behavior_overrides: Dictionary     # {&"projectile_count": {"add": 2}}
@export var flags: Array[StringName]           # &"cannot_crit" / &"cost_life" ...
@export var conflicts_with: Array[StringName]  # 独占组
```

**装配规则（必须按此顺序，不可交换）**：

```
1. 从 SkillData.allowed_support_tags 与 support.require_tags / exclude_tags 求交集 → 判定兼容
2. 先把所有已装配辅助的 add_tags 追加到"有效标签集"（多轮判定，直到收敛）
   —— 即：靠前的辅助可以"打开"靠后辅助的兼容性
3. 逐个辅助注入 stat_modifiers（source_id = support_id）
4. 按声明顺序应用 behavior_overrides：加法类先合并，乘法类后合并
5. cost = base_cost × Π(cost_multiplier) × skill_cost_multiplier
6. 检查 conflicts_with：命中两件即装配失败，回滚全部注入
```

**禁止**：把兼容判定写成字符串包含判断（`stat_name.contains("area")`）。标签是精确匹配的 `StringName`。

### 3.4 TriggerData（触发器）

```gdscript
class_name TriggerData extends Resource
@export var event: StringName      # &"on_hit" &"on_crit" &"on_kill"
                                   # &"on_take_damage" &"on_block" &"on_cooldown_end" &"on_interval"
@export var chance: float = 1.0
@export var cooldown: float = 0.0
@export var interval: float = 0.0  # 仅 on_interval 使用
@export var linked_slot_index: int
```

### 3.5 StatDef（属性注册表）

```gdscript
# stat_registry.gd（autoload 或静态类）
const DEFS := {
    &"projectile_damage": {"default": 1.0, "aggregate": "multiplicative_base"},
    &"projectile_count":  {"default": 1.0, "aggregate": "flat_then_round"},
    &"cast_speed":        {"default": 1.0, "aggregate": "multiplicative_base"},
    &"area_size":         {"default": 1.0, "aggregate": "multiplicative_base"},
}
```

**必须**：整数型属性（`projectile_count`、`chain_count`、`fork_count`、`pierce`）在管线末端统一 `floor` 一次，中途不得取整。否则 `+2` 与 `×1.5` 的先后会改变结果。

### 3.6 BehaviorConfig（行为参数）

```gdscript
# bhv_projectile 的 params 规范
{
  &"count_base": 1, &"speed": 900.0, &"radius": 12.0,
  &"pierce_base": 0, &"fork_base": 0, &"chain_base": 0,
  &"lifetime": 1.2, &"spread_deg": 0.0       # spread=0 时单发；>0 时按扇形均分
}
```

---

## 4. 属性与结算管线（本系统的宪法）

### 4.1 双维度作用域（对原规格的必要修正）

原规格把 `melee / projectile / area / dot` 并列为"分系"。问题是这四者不同类：前三个是**技能形态标签**，`dot` 是**伤害通道**。一个"近战投射物"技能应同时吃 melee 与 projectile 词缀，而"点燃伤害"只吃 dot/ailment 通道的词缀。

**必须改为**：

```gdscript
enum Channel { HIT = 1, DOT = 2, AILMENT = 4, ALL = 7 }
```

- `Channel.HIT`：直接命中伤害（默认）
- `Channel.DOT`：持续伤害（引导 tick、地面效果）
- `Channel.AILMENT`：异常状态伤害（点燃/中毒/流血）
- 技能形态仍放在 `tags`：`&"melee" &"projectile" &"area" &"spell" &"attack" &"minion" &"channel" &"movement" &"buff"`

**判定公式**：

```
modifier 生效 ⟺ (mod.channel_mask & ctx.channel) != 0
              ∧ mod.require_tags ⊆ ctx.tags
              ∧ mod.exclude_tags ∩ ctx.tags == ∅
```

### 4.2 计算顺序（七步，严格固定）

```
① 取基础值      base = part.base_damage × Σ(level_scaling)
② 加平值        v = base + Σ(FLAT_ADD)          ← 仅同 stat、同通道、同标签集
③ 伤害转换      见 §4.3（仅对伤害类 stat）
④ 加算百分比    v = v × (1 + Σ(INCREASED)/100)
⑤ 乘算百分比    v = v × Π(1 + MORE_i/100)
⑥ 暴击          if roll < crit_chance: v = v × crit_multi
⑦ 目标侧减免    闪避判定 → 护甲/抗性 → 护盾吸收 → 扣血
```

**必须**：④ 与 ⑤ 之间不得插入任何逻辑。所有"特殊效果"（连锁、穿透、分裂）属于**行为层**，不属于数值层。

**必须**：`FLAT_ADD` 阶段的附加伤害要乘 `damage_effectiveness`；`INCREASED/MORE` 阶段不再乘。

### 4.3 伤害转换规则（最容易做错的地方）

```
- 转换发生在 ② 之后、④ 之前
- 同一次结算内，多源转换对同一源类型**相加**，总和超过 100% 时按比例归一化
  例：60% 物理→火 + 60% 物理→冰  ⇒  各 50%，物理残留 0%
- 转换后的伤害按**新类型**参与 ④⑤（即吃火焰/冰霜词缀，不吃物理词缀）
- 转换后的伤害**不再二次转换**（禁止链式递归）
- 上限：每个源类型转出总量 ≤ 100%，不足部分保留原类型
```

**验收样例**：base 100 物理 + FLAT 20 物理，50% 物理→火，物理 inc +20%，火焰 inc +40%。
手算：`(100+20) = 120` → 火 60 / 物理 60 → 物理 72 / 火焰 84 → **合计 156**。

### 4.4 快照语义

出手瞬间生成不可变快照：

```gdscript
class_name DamagePacket extends RefCounted
var elements: Dictionary          # {&"physical": 72.0, &"fire": 84.0}
var crit: bool
var crit_multi: float
var channel: int
var tags: Array[StringName]
var source_instance_id: StringName
var rng_tick: int                 # 用于回放
```

**必须**：DoT 与召唤物的伤害使用**出手时的 stats 快照**，不随后续换装/增益变化。理由：否则"脱装备刷新 DoT"会变成可无限叠加的漏洞。

---

## 5. 插槽与装配（自研，无参考实现可抄）

### 5.1 数据结构

```gdscript
class_name SkillSlot extends Resource
@export var slot_index: int
@export var active_gem: SkillData
@export var active_level: int = 1
@export var active_quality: int = 0
@export var supports: Array[SupportGemData] = []
@export var socket_count: int = 4          # 首版 4~6
@export var links: Array[int] = []         # 连通关系：link[i]=j 表示第 i 孔与第 j 孔相连
```

### 5.2 SocketGraph（连通分量）

```
assemble(slot) -> AssemblyResult:
  1. 用并查集对 links 求连通分量，得到 groups: Array[Array[int]]
  2. 每个 group 内：找出唯一的主动宝石（0 个=空组；≥2 个=非法，报错）
  3. 该组的辅助石只作用于同组的主动宝石（首版可先做"全部孔单组"，但算法必须按连通分量写，
     以便后续开启链式约束时无需重构）
  4. 输出 AssemblyResult { modifiers[], behavior_overrides{}, effective_tags, cost_multiplier }
  5. 缓存结果，key = (gem_id, level, support_ids 排序后哈希)；装配是纯函数
```

**必须**：装配结果**只包含数据**，不持有 Node 引用。这样"换辅助 = 重算 + 重挂 modifier"，无需销毁重建实例。

### 5.3 局内武器栏多槽

- 技能栏 1~8 键，每键绑定一个 `SkillSlot`
- **同一时刻只有一个 `SkillInstance`** 由该 `SkillSlot` 派生（切换武器栏时重建实例，但 `SkillSlot` 数据不变）
- 武器绑定"初始主动技能"，无普攻（以项目设计为准，本规格只提供能力，不定义规则）

---

## 6. 水晶接入契约（扩展位，具体规则以《水晶系统 v0.5》为准）

本规格**不定义**水晶的具体效果，只定义它接进来的方式。水晶必须表现为：

1. **修饰符源**：给目标技能注入 `ModifierSpec`，`source_id = &"crystal:<id>"`，可整体移除
2. **标签源**：可 `add_tags`，从而改变该技能可接受的辅助石集合
3. **行为改写源**：可覆盖 `behavior_overrides`
4. **条件门**：通过 `conditions` 表达"仅对稀有技能生效""仅当技能为初始技能时生效"等

**禁止**：把水晶逻辑写进 `SupportGemData`（会破坏两种来源的正交性），或写进 `bhv_*` 行为组件（会污染演出层）。

**待人类确认**：水晶是否允许修改 `SkillData` 的引用本身（即换掉主动技能），还是只允许附加修饰。两种实现差异很大，不要自行决定。

---

## 7. 触发系统

### 7.1 结构

```
CombatEventBus（autoload，单一实例）
  ├─ signal hit_landed(packet, target)
  ├─ signal crit_landed(packet, target)
  ├─ signal entity_killed(victim, killer)
  ├─ signal damage_taken(entity, packet)
  ├─ signal block_occurred(entity, packet)
  └─ signal skill_cooldown_finished(instance)

TriggerManager（每角色一个）
  ├─ 订阅上述信号
  ├─ 按 event 索引 TriggerData
  └─ 命中条件后调用 instance.trigger_cast()（绕过输入，仍走消耗与自身 CD）
```

### 7.2 限流公式（必须实现，且必须可测）

```
effective_rate = min( 1.0 / cooldown , event_rate × chance )     # cooldown>0
effective_rate = event_rate × chance                             # cooldown==0
```

**验收样例**：事件率 5 次/秒、`chance = 0.3`、`cooldown = 0.5s`
→ `min(2.0, 1.5) = 1.5 次/秒`。跑 100 秒，触发次数应落在 `150 ± 15`（±10%）。

### 7.3 调度

- `on_interval` 用**一个全局最小堆 ticker** 统一调度，**禁止**每个触发器一个 `Timer` 节点
- 同一事件多个触发器**各自独立**计时，互不阻塞
- 触发链深度上限 = 3（A 触发 B 触发 C，C 触发 A 则丢弃），防止无限递归

---

## 8. 伤害、异常、召唤、资源

### 8.1 异常状态（必须与命中分离）

| 异常 | 触发条件 | 伤害通道 | 关键规则 |
|---|---|---|---|
| 点燃 | 火焰暴击命中 | `AILMENT` | 基础伤害取**点燃瞬间**的火伤快照，不吃后续增益 |
| 冰缓 | 冰霜命中 | 无（Debuff） | 降低移动/攻速，有叠加上限 |
| 冰冻 | 冰缓累积达阈值 | 无（控制） | 定身；有最短时间保护（防无限控） |
| 感电 | 闪电命中 | 无（Debuff） | 目标承伤 +X%，X 由伤害量决定 |
| 中毒 | 混沌/物理命中 | `AILMENT` | 可叠层，每层独立计时 |
| 流血 | 物理命中 | `AILMENT` | 移动时伤害更高（可选） |

**必须**：异常伤害走 `AILMENT` 通道，因此**不吃**"hit damage increased"，只吃"dot / ailment damage"。这条错了会让数值整体偏高 30% 以上。

**必须**：DoT 用**一个全局 ticker**（0.1s 或 0.25s 网格），每个效果记录 `next_tick_at`；**禁止**每个 DoT 一个 `Timer`。

### 8.2 召唤物

- 召唤物继承施法者的**指定子集**（`minion_damage`、`minion_attack_speed`、`minion_life`），不继承全部 stats
- 召唤物技能复用 `bhv_projectile` 等行为组件，**不新写一套**
- `max_count` 上限到达时，新召唤顶掉最旧的

### 8.3 资源与充能

```
可用资源 = max_stat − Σ(reserved)
cost    = base_cost × Π(support.cost_multiplier) × skill_cost_multiplier
冷却     = base_cooldown / cooldown_recovery
充能型   = max_charges > 0 时，冷却改为每 charge_recharge_time 秒回复 1 层
```

**必须**：资源不足时 `can_cast()` 返回 false，且**不得**进入 cast（禁止"扣成负数再回滚"）。

---

## 9. 性能架构（100 弹 / 80 特效 / 80 角色）

### 9.1 三档红线

| 类别 | 上限 | 实现方式 | 禁止 |
|---|---|---|---|
| 投射物 | 100 发/秒（同屏可达 300+） | **SoA 数组**（位置/速度/寿命/伤害包分数组）+ `MultiMeshInstance2D` 一次绘制 | 每发一个 `Area2D` 节点 |
| 特效 | 80 个并发 | `GPUParticles2D` 池化，复用 `emitting` 开关 | 每次 `instantiate` |
| 角色 | 80 个 | 常规 `CharacterBody2D`，但 AI 与属性更新分帧 | 每帧全量重算 stats |

### 9.2 碰撞（关键决策）

投射物不要用 `Area2D` 的物理引擎。改为：

```
每帧：
  1. 清空空间哈希网格（均匀网格，cell = 2 × 最大投射物半径）
  2. 把所有敌人插入网格（O(n)）
  3. 遍历投弹，仅查询其覆盖的 3×3 格（O(m × k)，k 很小）
  4. 圆形近似判定（距离平方比较，不开方）
```

预期：300 投弹 × 80 敌人，朴素 O(n·m) = 24000 次/帧；哈希后 < 2000 次/帧。

### 9.3 对象池

```gdscript
class_name ProjectilePool
func acquire() -> ProjectileSlot      # 池空且达上限时，回收最旧的（不是新建）
func release(slot: ProjectileSlot) -> void
```

**必须**：池有硬上限（建议投射物 512、特效 128），达上限时回收最旧而非扩容。理由：宁可掉视觉，不可掉帧。

### 9.4 确定性随机

```gdscript
class_name RngService
# 分流：damage / loot / spawn / cosmetic
# 同一 seed + 同一输入序列 ⇒ 同一结果（支持回放与复现 BUG）
func roll(stream: StringName, tick: int, salt: int) -> float
```

**必须**：战斗结果相关的 roll 不得与表现层（粒子随机）共用流，否则改动特效会改变战斗结果。

---

## 10. 最终目录结构

```
res://
├── systems/skills/
│   ├── skill_instance.gd
│   ├── skill_executor.gd
│   ├── socket_graph.gd               # 自研
│   ├── assembly.gd                   # 装配纯函数
│   ├── behavior/
│   │   ├── bhv_projectile.gd
│   │   ├── bhv_melee_swing.gd
│   │   ├── bhv_aoe_burst.gd
│   │   ├── bhv_channel.gd
│   │   ├── bhv_summon.gd
│   │   ├── bhv_dash.gd
│   │   └── bhv_buff_self.gd
│   ├── data/
│   │   ├── skill_data.gd  skill_part.gd  support_gem_data.gd
│   │   ├── trigger_data.gd  modifier_spec.gd  condition_spec.gd
│   │   └── gem_level_scaling.gd
│   ├── combat/
│   │   ├── stats_component.gd        # 只做"存 + 按来源移除"，不做业务
│   │   ├── modifier.gd
│   │   ├── damage_pipeline.gd        # 纯函数，七步管线
│   │   ├── damage_packet.gd
│   │   ├── hitbox_component.gd  hurtbox_component.gd
│   │   └── status_effect_manager.gd
│   ├── pools/  projectile_pool.gd  effect_pool.gd
│   └── util/   rng_service.gd  stat_registry.gd  tag_registry.gd
├── systems/perf/  spatial_hash.gd  dot_ticker.gd
├── content/gems/  active/  supports/  triggers/       # 全是 .tres
└── tests/skills/                                       # GUT 或自写 assert
```

---

## 11. 施工顺序与门禁

| 阶段 | 交付 | 门禁（不达标不得进下一阶段） |
|---|---|---|
| **M0** 工程骨架 | `project.godot`、目录、GUT 接入、CI | `godot --headless` 跑测试退出码 = 0；空测试也能跑通「0 通过 0 失败」而非报错 |
| **M1** 管线 | `StatsComponent` + `damage_pipeline.gd` | §12 的 G1–G4 全绿；转换归一化用例通过 |
| **M2** 技能与行为 | `SkillData` + `SkillExecutor` + projectile/melee 两个行为 | 单发冰矛能打出数字；改 `.tres` 数值即改伤害，不改代码 |
| **M3** 装配 | `SocketGraph` + `Assembly` | G5–G7 通过；卸下辅助后数值**完全还原**（逐位相等，不是近似） |
| **M4** 伤害闭环 | Hitbox/Hurtbox、暴击、抗性、击杀 | G8–G9 通过；端到端 DPS 与手算差 ≤ 0.5% |
| **M5** 资源 | 冷却/充能/消耗/多技能栏 | 资源不足无法施法；8 个技能位全可用 |
| **M6** 其余行为 | aoe/channel/summon/dash/buff | W1 内容集 8 主动全部上线 |
| **M7** 触发 | `CombatEventBus` + `TriggerManager` | G10 通过（触发频率落在 ±10%）；链深保护生效 |
| **M8** 性能 | SoA 投射物 + 空间哈希 + 池 | 100 弹并发同屏 ≥ 60fps（目标机型）；GC 峰值无尖刺 |

**硬门禁**：M3 结束时，若出现任何"为跑通而写的 `if gem_id ==`"分支，**立即停止并重构**，不接受"先跑通再优化"。

---

## 12. 测试规格（10 条黄金用例，全部可手算）

> 每条都是"输入 → 期望值"，AI 必须写成断言，不许只写"能跑"。

| ID | 场景 | 输入 | 期望 |
|---|---|---|---|
| **G1** | 加乘分离 | base 100，inc +50%，两个 more 各 +20% | `100 × 1.5 × 1.2 × 1.2 = 216.0` |
| **G2** | inc 加算 | base 100，inc +30% +30%，两个 more 各 +20% | `100 × 1.6 × 1.44 = 230.4` |
| **G3** | 转换顺序 | 见 §4.3 | `156.0` |
| **G4** | 转换归一化 | base 100 物理，60%→火 + 60%→冰 | 火 50 / 冰 50 / 物理 0（合计 100） |
| **G5** | 辅助装配 | 冰矛 + 多重投射(+2) + 连锁(+2) | `projectile_count = 3`、`chain_count = 2`、消耗 `×1.5×1.3` |
| **G6** | 卸下还原 | 装上再卸下同一辅助 | 所有 stat **逐位等于**装配前 |
| **G7** | 兼容排除 | 无情（require=melee, exclude=spell）挂到法术技能 | 装配失败，返回明确错误码，**不得静默忽略** |
| **G8** | 暴击期望 | base 100，crit 30%，crit_multi 150% | 1000 次采样均值 ≈ `115 ± 3` |
| **G9** | 异常通道 | 点燃目标，施加 "hit damage +100%" | 点燃 DPS **不变**（证明通道隔离正确） |
| **G10** | 触发限流 | 事件率 5/s，chance 0.3，CD 0.5s | 100 秒触发 `150 ± 15` 次 |

**必须**：G6 用 `==` 而非 `is_equal_approx`——"卸下即还原"是精确性要求，不是近似要求。

---

## 13. 禁止事项（违者返工）

### 13.1 架构类

1. 禁止在运行时代码中出现具体宝石 id（`"frost_shard"`）、具体技能名、具体数值。
2. 禁止给 `Modifier` 增加第四种算子（如 `CONVERTED` 直接塞进 stat 管线，转换必须走独立阶段）。
3. 禁止把 `INCREASED` 逐条相乘（这是最常见的"看起来对"的错误）。
4. 禁止行为组件读取其他行为组件的内部状态。
5. 禁止 `SkillInstance` 持有插槽数据副本（单一真源在 `SkillSlot`）。

### 13.2 性能类

6. 禁止热路径 `instantiate/free`。
7. 禁止每个投射物挂 `Area2D`。
8. 禁止每个 DoT 挂 `Timer`。
9. 禁止每帧重算全部 stats（脏标记 + 按需重算）。
10. 禁止在 `_process` 里做字符串拼接/字典分配。

### 13.3 从 kit 抄的时候必须避开的坑

> kit 的复盘文档自己暴露了一个 P0：**防御结算被执行了两次**（`armor=100` 实际减伤 75% 而非 50%，`dodge=30%` 实际 51%）。根因是"攻击者视角管线"和"受击方视角管线"被串联调用。

11. **禁止**同时存在两条伤害/减伤管线。本项目只允许**一条**：`attack → 生成 DamagePacket → 受击方结算`。攻击侧只负责算"打出多少"，受击侧只负责"扣多少"，**不得互相调用对方的减伤逻辑**。
12. **禁止**用"把默认值清零"的方式写测试（会让 BUG 隐身）。测试必须覆盖"护甲 100 / 闪避 30% / 有护盾"的**非零默认态**。

### 13.4 合规类

13. 禁止复制 `the-exile-engine-v2` 的任何代码（无 LICENSE）。
14. 禁止使用 Path of Exile 的技能名、图标、数值表。
15. 若引入 `godot-arpg-kit` 代码，必须在 `NOTICE` 或文件头保留：`Portions derived from godot-arpg-kit, Copyright (c) 2026 eiehihi, MIT License`。

---

## 14. 多平台与导出

| 平台 | 要求 | 注意 |
|---|---|---|
| Windows / macOS / Linux | 主验收 | — |
| Android | 必测 60fps | 虚拟摇杆另做；`config/features` 需含 `"Mobile"` |
| Web (WASM) | **待人类确认是否必需** | 若必需：关闭多线程物理、音频改用 `AudioStreamGenerator` 兼容路径、纹理需压缩 |
| iOS | 可选 | 需签名，性能预期同 Android |

**必须**：所有平台共用同一套 `.tres` 与同一套逻辑；**禁止**用 `if OS.has_feature("mobile")` 分叉游戏规则（只允许分叉输入与画质）。

---

## 15. 术语替换（可选，但与 IP 风险直接相关）

原规格的 40 个主动宝石大量沿用 PoE 原名（`Ice Shard` / `Cleave` / `Leap Slam` / `Storm Call` / `Arc` / `Ground Slam` / `Rockfall`…）。若项目计划商业化，建议按下表规则替换（保留意译，去掉专名）：

| 原 | 建议 | 规则 |
|---|---|---|
| Ice Shard | 霜棱 | 材质 + 形态，不用 PoE 组合词 |
| Cleave | 裂斩 | 动词化 |
| Leap Slam | 震跃 | 动作 + 结果 |
| Storm Call | 落雷印记 | 去掉 `Call` 这类 PoE 惯用后缀 |
| Arc | 电弧链 | 加限定词，避免单词雷同 |
| Ground Slam | 地裂击 | 同上 |

**规则三条**：① 不用 PoE 的"单词型"技能名（Arc / Cleave / Spark）；② 不用 `Awakened / Vaal / Mirror / Atlas / 6-Link` 等专有体系词；③ 中文名以"材质+形态"或"动作+结果"两段式为主。

---

## 附录 A｜PoB 精确读取清单（按需读，不要全文）

| 文件 | 行数 | 只读这些 |
|---|---|---|
| `src/Modules/CalcActiveSkill.lua` | 934 | 技能注册、多 part 拆分 |
| `src/Modules/CalcOffence.lua` | 6263 | 只读 conversion 段与 `increased/more` 聚合段 |
| `src/Modules/CalcTriggers.lua` | 1627 | 触发频率与 cooldown 扣减 |
| `src/Classes/SkillsTab.lua` | 1502 | `socketGroupList` 的数据形态（仅借鉴命名） |
| `src/Data/Skills/sup_int.lua` | 7007 | 只看 `requireSkillTypes / addSkillTypes / excludeSkillTypes` 三个字段 |
| `src/Data/SkillStatMap.lua` | — | stat 名 → 修饰符的映射表形态 |

**提醒**：这些是"标准答案"，不是"模板"。把 6263 行的 Lua 移植到 GDScript 属于无效工作。

## 附录 B｜kit 抄/不抄清单

| 抄 | 文件 | 理由 |
|---|---|---|
| ✅ | `scripts/stats/stat_modifier.gd` | 数据形态干净，带来源 |
| ✅ | `scripts/stats/stats_component.gd` | 接口签名（`add/remove_by_source`） |
| ✅ | `scripts/combat/damage_calculator.gd` + `damage_info.gd` | 纯函数 + `RefCounted`，可单测 |
| ✅ | `scripts/combat/combat_event_bus.gd` | autoload 事件总线 |
| ✅ | `tests/`、`.github/workflows/tests.yml` | 测试组织 + headless 退出码经验 |
| ❌ | `combat_component.gd` 的攻击/受击双管线 | 曾导致双重减伤 P0 |
| ❌ | `skills/skill_manager.gd` 的释放流程 | 无插槽/装配层，需重写 |
| ❌ | 节点化的战斗与碰撞实现 | 撑不到 300 投射物 |

## 附录 C｜提交前自检（AI 请逐条回答 yes/no）

1. 新增一个辅助石，我改了几个 `.gd` 文件？（答案必须是 **0**）
2. `INCREASED` 是求和后一次乘，还是逐条乘？（必须是**求和后一次乘**）
3. 转换发生在 `INCREASED` 之前还是之后？（必须是**之前**）
4. 点燃伤害吃不吃 `hit damage`？（必须是**不吃**）
5. 卸下辅助后数值能否逐位还原？（必须是**能**）
6. 是否存在第二条减伤管线？（必须是**没有**）
7. 300 投射物时是 O(n·m) 还是哈希查询？（必须是**哈希**）
8. 每个 DoT 是否各自挂了 Timer？（必须是**没有，走全局 ticker**）
9. 是否有任何一行代码写死了宝石 id 或数值？（必须是**没有**）
10. 测试里是否把默认值清零来"制造通过"？（必须是**没有**）

---

**文档结束。** 执行中遇到本文件未覆盖的设计抉择，**停下来问人类**，不要自行发明规则——尤其是水晶系统的具体效果与《水晶系统 v0.5》的对接方式。
